#!/usr/bin/env python3
"""Read-only tree content/metadata snapshots. Python 3.9+, standard library only."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import sys


def absolute(path):
    return Path(os.path.abspath(os.path.expanduser(path)))


def no_link_path(path):
    """Reject symlinks in an input path; scanning never traverses tree links."""
    current = Path(path.anchor)
    for part in path.parts[1:]:
        current /= part
        if current.is_symlink():
            raise ValueError("Input path contains a symlink: " + str(current))


def signature(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_size,
            info.st_mtime_ns, info.st_ctime_ns)


def file_digest(path, expected):
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags)
    with os.fdopen(fd, "rb") as stream:
        before = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode) or signature(before) != signature(expected):
            raise ValueError("File changed before hashing: " + str(path))
        digest = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
        after = os.fstat(stream.fileno())
    if signature(before) != signature(after) or signature(after) != signature(path.lstat()):
        raise ValueError("File changed while hashing: " + str(path))
    return digest.hexdigest()


def canonical_digest(value):
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True,
                     separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def snapshot(root):
    no_link_path(root)
    if not root.is_dir():
        raise ValueError("Root must be a directory: " + str(root))
    entries = []
    unsupported = []

    def visit(path):
        before = path.lstat()
        relative = "." if path == root else path.relative_to(root).as_posix()
        record = {"path": relative, "mode": stat.S_IMODE(before.st_mode),
                  "mtime_ns": before.st_mtime_ns}
        if stat.S_ISLNK(before.st_mode):
            record.update(type="symlink", target=os.readlink(path))
        elif stat.S_ISREG(before.st_mode):
            record.update(type="file", bytes=before.st_size,
                          sha256=file_digest(path, before))
        elif stat.S_ISDIR(before.st_mode):
            record["type"] = "directory"
            with os.scandir(path) as stream:
                children = sorted((Path(item.path) for item in stream), key=lambda p: p.name)
            for child in children:
                visit(child)
        else:
            record.update(type="other", file_type=stat.S_IFMT(before.st_mode))
            unsupported.append(relative)
        if signature(before) != signature(path.lstat()):
            raise ValueError("Entry changed during scan: " + str(path))
        entries.append(record)

    visit(root)
    entries.sort(key=lambda entry: entry["path"])
    content = [{k: v for k, v in entry.items() if k not in ("mode", "mtime_ns")}
               for entry in entries]
    return {"schema": "tree-snapshot-v1", "root": str(root), "entries": entries,
            "content_sha256": canonical_digest(content),
            "metadata_sha256": canonical_digest(entries),
            "unsupported_entries": unsupported,
            "scope": "File bytes, link targets, mode and mtime; no links traversed. "
                     "Does not preserve ownership, ACLs, xattrs or access time; scan a quiescent tree."}


def write_report(path, value, root):
    path = absolute(str(path))
    # Resolve the destination only for validation, never to alter the source tree.
    resolved = path.resolve(strict=False)
    if resolved == root or root in resolved.parents:
        raise ValueError("Output must be outside the protected source tree")
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    create = sub.add_parser("snapshot", help="Create a new immutable manifest")
    create.add_argument("root")
    create.add_argument("--output", required=True)
    verify = sub.add_parser("verify", help="Compare current tree with a manifest")
    verify.add_argument("root")
    verify.add_argument("--snapshot", required=True)
    verify.add_argument("--output", required=True)
    verify.add_argument("--content-only", action="store_true",
                        help="Report metadata changes but do not fail solely on them")
    args = parser.parse_args()
    root = absolute(args.root)
    try:
        current = snapshot(root)
        if args.command == "snapshot":
            current["status"] = "INCOMPLETE" if current["unsupported_entries"] else "PASS"
            write_report(args.output, current, root)
            print(json.dumps({"status": current["status"], "entries": len(current["entries"])}))
            return 2 if current["unsupported_entries"] else 0
        previous = json.loads(Path(args.snapshot).read_text(encoding="utf-8"))
        if previous.get("schema") != "tree-snapshot-v1":
            raise ValueError("Unsupported snapshot schema")
        # Verify the supplied manifest itself before using its aggregate hashes.
        old_entries = previous["entries"]
        old_content = [{k: v for k, v in e.items() if k not in ("mode", "mtime_ns")}
                       for e in old_entries]
        if (canonical_digest(old_entries) != previous["metadata_sha256"]
                or canonical_digest(old_content) != previous["content_sha256"]):
            raise ValueError("Snapshot entries do not match its recorded hashes")
        old = {entry["path"]: entry for entry in old_entries}
        new = {entry["path"]: entry for entry in current["entries"]}
        if len(old) != len(old_entries):
            raise ValueError("Duplicate paths in snapshot")
        changes = [{"path": key, "before": old.get(key), "after": new.get(key)}
                   for key in sorted(old.keys() | new.keys()) if old.get(key) != new.get(key)]
        content_equal = previous["content_sha256"] == current["content_sha256"]
        metadata_equal = previous["metadata_sha256"] == current["metadata_sha256"]
        unsupported = bool(current["unsupported_entries"] or previous.get("unsupported_entries"))
        passed = content_equal and (metadata_equal or args.content_only) and not unsupported
        report = {"schema": "tree-verification-v1", "status": "PASS" if passed else "FAIL",
                  "root": str(root), "snapshot": str(absolute(args.snapshot)),
                  "content_equal": content_equal, "metadata_equal": metadata_equal,
                  "content_only_requested": args.content_only, "changes": changes,
                  "unsupported_entries": current["unsupported_entries"], "scope": current["scope"]}
        write_report(args.output, report, root)
        print(json.dumps({k: report[k] for k in ("status", "content_equal", "metadata_equal")}))
        return 0 if passed else 1
    except (OSError, ValueError, KeyError, TypeError) as error:
        print("ERROR: " + str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
