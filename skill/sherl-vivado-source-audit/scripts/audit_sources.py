#!/usr/bin/env python3
"""Static Vivado dependencies and source-tree comparisons; does not invoke EDA."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET


def absolute(path):
    return Path(os.path.abspath(os.path.expanduser(str(path))))


def first_symlink(path):
    """Inspect components from the root; stop before entering a linked directory."""
    path = absolute(path)
    current = Path(path.anchor)
    for part in path.parts[1:]:
        current /= part
        if current.is_symlink():
            return current
        if not current.exists():
            break
    return None


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def inventory(root, findings=None):
    """Do not traverse symlink directories or use linked files as audit inputs."""
    files, links = [], []
    if first_symlink(root):
        raise ValueError("Tree input path contains a symlink: " + str(root))
    if not root.is_dir():
        raise ValueError("Tree input is not a directory: " + str(root))
    def on_error(error):
        if findings is None:
            raise error
        findings.append({"kind": "source_read_failure", "path": str(error.filename),
                         "detail": str(error)})

    for folder, directories, names in os.walk(root, followlinks=False, onerror=on_error):
        for name in list(directories):
            path = Path(folder) / name
            if path.is_symlink():
                links.append(path)
                directories.remove(name)
        for name in names:
            path = Path(folder) / name
            (links if path.is_symlink() else files).append(path)
    return sorted(files), sorted(links)


def within(path, roots):
    target = path.resolve(strict=False)
    return any(target == root or root in target.parents for root in roots)


def local_name(tag):
    return tag.rsplit("}", 1)[-1]


def strip_comments(text):
    # Preserve quoted strings and newlines; a path containing // is not a comment.
    token = re.compile(r'"(?:\\.|[^"\\])*"|/\*.*?\*/|//[^\n]*', re.S)
    return token.sub(lambda m: m.group() if m.group().startswith('"')
                     else "".join("\n" if c == "\n" else " " for c in m.group()), text)


def project_audit(args):
    xpr = absolute(args.xpr)
    if first_symlink(xpr):
        raise ValueError("Project input path contains a symlink")
    root = xpr.parent
    allowed = [root.resolve()] + [absolute(path).resolve() for path in args.allow_root]
    tree = ET.parse(xpr)
    # These are Vivado's conventional native project directories, not arbitrary
    # environment-variable expansion. Unknown macros remain unresolved.
    macros = {"PPRDIR": root, "PSRCDIR": root / (xpr.stem + ".srcs"),
              "PGENDIR": root / (xpr.stem + ".gen"),
              "PRUNDIR": root / (xpr.stem + ".runs"),
              "PCACHEDIR": root / (xpr.stem + ".cache"),
              "PIPUSERFILESDIR": root / (xpr.stem + ".ip_user_files")}
    findings, records, assets, ip_paths, bd_paths, options = [], [], [], [], [], []

    def issue(kind, path, detail):
        findings.append({"kind": kind, "path": str(path), "detail": detail})

    def read_text(path):
        link = first_symlink(path)
        if link:
            issue("symlink_reference_not_scanned", path, "Linked component: " + str(link))
            return None
        try:
            return path.read_text(encoding="utf-8", errors="strict")
        except UnicodeDecodeError as error:
            issue("unsupported_encoding", path,
                  "UTF-8 decoding failed at byte " + str(error.start)
                  + "; bytes were preserved; text analysis was not performed: " + error.reason)
        except OSError as error:
            issue("source_read_failure", path, str(error))
        return None

    def resolve(value, base):
        value = value.replace("\\", "/")
        for key, path in macros.items():
            value = value.replace("${" + key + "}", str(path))
            value = re.sub(r"\$" + re.escape(key) + r"\b", lambda m: str(path), value)
        if "$" in value:
            return None
        path = Path(value)
        return absolute(path if path.is_absolute() else base / path)

    registered = []
    for fileset in tree.findall("./FileSets/FileSet"):
        for element in fileset.findall("File"):
            value = element.get("Path", "")
            path = resolve(value, root)
            link = first_symlink(path) if path else None
            record = {"fileset": fileset.get("Name"), "literal": value,
                      "resolved": str(path) if path else None,
                      "exists": bool(path and not link and path.is_file()),
                      "symlink_component": str(link) if link else None,
                      "inside_allowed_roots": bool(path and within(path, allowed)),
                      "attributes": [attr.attrib for attr in element.findall("./FileInfo/Attr")]}
            records.append(record)
            if path is None:
                issue("unresolved_project_path", xpr, value)
            elif link:
                issue("symlink_reference_not_scanned", path, "Linked component: " + str(link))
            elif not record["inside_allowed_roots"]:
                issue("external_project_reference", path, value)
            elif not record["exists"]:
                issue("missing_registered_file", path, value)
            else:
                try:
                    record["sha256"] = digest(path)
                    registered.append(path)
                except OSError as error:
                    issue("source_read_failure", path, str(error))
    for element in tree.iter():
        name = element.get("Name", "")
        if any(word in name.lower() for word in ("includedir", "iprepopath")):
            options.append({"name": name, "value": element.get("Val"),
                            "note": "Recorded for review; Tcl list syntax is not evaluated."})
            if element.get("Val", "").strip():
                issue("search_path_option_requires_review", xpr, name + "=" + element.get("Val", ""))
    source_tree = root / (xpr.stem + ".srcs")
    if first_symlink(source_tree):
        issue("source_tree_symlink_not_scanned", source_tree,
              "Linked component: " + str(first_symlink(source_tree)))
        files, links = [], []
    else:
        files, links = inventory(source_tree, findings) if source_tree.is_dir() else ([], [])
    for path in links:
        issue("source_tree_symlink_not_scanned", path, os.readlink(path))
    # Explicit roots determine assets; no successful resolution by a global
    # basename guess. Candidates are evidence to review, not a build guarantee.
    search_dirs = [root] + [absolute(path) for path in args.search_dir]
    names = {}
    for path in files:
        names.setdefault(path.name, []).append(path)
    text_files = sorted(set(path for path in registered
                            if path.suffix.lower() in (".v", ".sv", ".vh", ".svh")))
    seen = set()
    while text_files:
        path = text_files.pop(0)
        if path in seen:
            continue
        seen.add(path)
        original_text = read_text(path)
        if original_text is None:
            continue
        text = strip_comments(original_text)
        requests = [("include", m.group(1), m.start()) for m in
                    re.finditer(r'`include\s+"([^"\n]+)"', text)]
        for match in re.finditer(r'`include\s+([^\n]+)', text):
            if not match.group(1).lstrip().startswith('"'):
                issue("dynamic_include_reference", path, match.group(1).strip())
        for match in re.finditer(r'\$readmem[hb]\s*\(\s*([^,\n]+)', text):
            expression = match.group(1).strip()
            if re.fullmatch(r'"[^"\n]+"', expression):
                requests.append(("readmem", expression[1:-1], match.start()))
            else:
                issue("dynamic_memory_reference", path, expression)
        for kind, literal, position in requests:
            direct = []
            linked = []
            for base in [path.parent] + search_dirs:
                resolved = resolve(literal, base)
                link = first_symlink(resolved) if resolved else None
                if link:
                    item = {"path": str(resolved), "linked_component": str(link),
                            "real_target_inside_allowed_roots": within(resolved, allowed)}
                    if item not in linked:
                        linked.append(item)
                        issue("asset_path_symlink_not_scanned", path,
                              literal + "; linked component: " + str(link))
                    continue
                if resolved and resolved.is_file() and resolved not in direct:
                    direct.append(resolved)
            candidates = names.get(Path(literal.replace("\\", "/")).name, [])
            asset = {"kind": kind, "file": str(path), "line": text[:position].count("\n") + 1,
                     "literal": literal, "explicit_path_matches": [str(p) for p in direct],
                     "linked_path_candidates_not_scanned": linked,
                     "basename_candidates": [str(p) for p in candidates],
                     "resolution": "unresolved"}
            if kind == "readmem":
                asset["runtime_note"] = "A file beside HDL is only a static candidate; simulator working directory and Vivado memory staging must be checked."
            if len(direct) == 1 and within(direct[0], allowed):
                try:
                    asset.update(resolution="unique_explicit_path", sha256=digest(direct[0]))
                    if kind == "include":
                        text_files.append(direct[0])
                except OSError as error:
                    issue("source_read_failure", direct[0], str(error))
            elif not direct:
                issue("unresolved_asset_path", path, literal)
            else:
                issue("ambiguous_or_external_asset_path", path, literal)
            assets.append(asset)
    for path in sorted(set(files + registered)):
        if path.suffix.lower() == ".xci":
            original_text = read_text(path)
            if original_text is None:
                continue
            try:
                ip = ET.ElementTree(ET.fromstring(original_text))
            except ET.ParseError as error:
                issue("ip_xml_parse_failure", path, str(error))
                continue
            for node in ip.iter():
                key = next((v for k, v in node.attrib.items() if local_name(k) == "referenceId"), "")
                value = node.text or ""
                if key == "RUNTIME_PARAM.OUTPUTDIR" or re.search(r'\.(?:coe|mem|mif)$', value, re.I):
                    target = resolve(value, path.parent)
                    link = first_symlink(target) if target else None
                    item = {"file": str(path), "field": key, "literal": value,
                            "resolved": str(target) if target else None,
                            "exists": bool(target and not link and target.exists()),
                            "symlink_component": str(link) if link else None,
                            "inside_allowed_roots": bool(target and within(target, allowed))}
                    ip_paths.append(item)
                    if link:
                        issue("ip_path_symlink_not_scanned", path, key + "; linked component: " + str(link))
                    elif not item["inside_allowed_roots"]:
                        issue("external_or_unresolved_ip_path", path, key + "=" + value)
                    elif key != "RUNTIME_PARAM.OUTPUTDIR" and not item["exists"]:
                        issue("missing_ip_memory_file", path, value)
        elif path.suffix.lower() == ".bd":
            original_text = read_text(path)
            if original_text is None:
                continue
            try:
                data = json.loads(original_text)
            except ValueError as error:
                issue("bd_json_parse_failure", path, str(error))
                continue

            def visit(value, prefix=""):
                if isinstance(value, dict):
                    for key, child in value.items():
                        location = prefix + "/" + key
                        if key in ("xci_path", "gen_directory") and isinstance(child, str):
                            target = resolve(child, path.parent)
                            link = first_symlink(target) if target else None
                            item = {"file": str(path), "field": location, "literal": child,
                                    "resolved": str(target) if target else None,
                                    "exists": bool(target and not link and target.exists()),
                                    "symlink_component": str(link) if link else None,
                                    "inside_allowed_roots": bool(target and within(target, allowed))}
                            bd_paths.append(item)
                            if link:
                                issue("bd_path_symlink_not_scanned", path, child + "; linked component: " + str(link))
                            elif not item["inside_allowed_roots"]:
                                issue("external_or_unresolved_bd_path", path, child)
                            elif key == "xci_path" and not item["exists"]:
                                issue("missing_bd_ip_product", path, child)
                        visit(child, location)
                elif isinstance(value, list):
                    for index, child in enumerate(value):
                        visit(child, prefix + "/" + str(index))
            visit(data)
    return {"status": "REVIEW" if findings else "STATIC_CLEAR", "project": str(xpr),
            "project_sha256": digest(xpr), "allowed_roots": [str(p) for p in allowed],
            "registered_files": records, "source_tree_inventory_count": len(files),
            "asset_references": assets, "ip_paths": ip_paths, "bd_paths": bd_paths,
            "search_path_options": options, "findings": findings,
            "scope": "Static paths and literal dependencies only. No Tcl, preprocessing, "
                     "HDL elaboration, encrypted sources, generated products, IP licensing, "
                     "ROM ordering, timing or functional equivalence is proved. Missing BD IP "
                     "products may be regenerable, but are not silently accepted. "
                     "HDL/XCI/BD text is decoded as strict UTF-8; unsupported encodings "
                     "are reported per file without lossy decoding or source changes."}


def xml_shape(node):
    text = node.text if node.text and node.text.strip() else None
    return [node.tag, sorted(node.attrib.items()), text,
            [xml_shape(child) for child in node]]


def differences(left, right, prefix=""):
    if type(left) is not type(right):
        return [{"path": prefix or "/", "before": left, "after": right}]
    if isinstance(left, dict):
        changes = []
        for key in sorted(left.keys() | right.keys()):
            if key not in left or key not in right:
                changes.append({"path": prefix + "/" + key,
                                "before_present": key in left, "after_present": key in right,
                                "before": left.get(key), "after": right.get(key)})
            else:
                changes.extend(differences(left[key], right[key], prefix + "/" + key))
        return changes
    if left != right:
        return [{"path": prefix or "/", "before": left, "after": right}]
    return []


def compare(args):
    reference, candidate = absolute(args.reference), absolute(args.candidate)
    scan_findings = []
    old_files, old_links = inventory(reference, scan_findings)
    new_files, new_links = inventory(candidate, scan_findings)
    old = {str(p.relative_to(reference)): p for p in old_files + old_links}
    new = {str(p.relative_to(candidate)): p for p in new_files + new_links}
    records, pending = [], []
    for name in sorted(old.keys() | new.keys()):
        a, b = old.get(name), new.get(name)
        item = {"path": name, "status": "REVIEW"}
        try:
            if a is None or b is None:
                item.update(reason="added_or_missing", reference_present=a is not None,
                            candidate_present=b is not None)
            elif a.is_symlink() or b.is_symlink():
                equal = a.is_symlink() and b.is_symlink() and os.readlink(a) == os.readlink(b)
                item.update(status="IDENTICAL_LINK" if equal else "REVIEW", reason="link_target_compare")
            elif digest(a) == digest(b):
                item.update(status="BYTE_IDENTICAL", sha256=digest(a))
            elif a.suffix.lower() == ".xci":
                left, right = ET.parse(a).getroot(), ET.parse(b).getroot()
                changed = []
                for tree, label in ((left, "reference"), (right, "candidate")):
                    found = []
                    for node in tree.iter():
                        key = next((v for k, v in node.attrib.items() if local_name(k) == "referenceId"), "")
                        if key == "RUNTIME_PARAM.OUTPUTDIR":
                            found.append(node.text)
                            node.text = "<approved-output-directory-metadata>"
                    changed.append({"side": label, "OUTPUTDIR_values": found})
                equal = xml_shape(left) == xml_shape(right)
                item.update(status="PATH_METADATA_OR_XML_FORMAT_ONLY" if equal else "REVIEW",
                            outputdir_values=changed,
                            reason="All XML fields compared; only OUTPUTDIR text and XML formatting normalized")
            elif a.suffix.lower() == ".bd":
                left = json.loads(a.read_text(encoding="utf-8"))
                right = json.loads(b.read_text(encoding="utf-8"))
                diffs = differences(left, right)
                allowed_path = "/design/design_info/gen_directory"
                accepted = [d for d in diffs if d["path"] == allowed_path
                            and "before_present" not in d]
                unresolved = [d for d in diffs if d not in accepted]
                item.update(status="PATH_METADATA_OR_JSON_FORMAT_ONLY" if not unresolved else "REVIEW",
                            accepted_metadata_changes=accepted, unreviewed_changes=unresolved,
                            reason="BD default expansion is reported, never automatically accepted or called a hardware change")
            else:
                item.update(reason="byte_difference", reference_sha256=digest(a), candidate_sha256=digest(b))
        except UnicodeDecodeError as error:
            item.update(reason="unsupported_encoding", detail="UTF-8 decoding failed at byte "
                        + str(error.start) + "; bytes preserved; text comparison was not performed")
        except (OSError, ET.ParseError, ValueError) as error:
            item.update(reason="source_read_or_parse_failure", detail=str(error))
        records.append(item)
        if item["status"] == "REVIEW":
            pending.append(name)
    return {"status": "REVIEW" if pending or scan_findings else "STATIC_CLEAR",
            "reference": str(reference), "candidate": str(candidate), "files": records,
            "unreviewed_files": pending, "inventory_findings": scan_findings,
            "scope": "Relative-path file comparison with an explicit two-field metadata allowance; "
                     "no automatic migration and no functional, constraint or hardware equivalence claim."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    project = commands.add_parser("project", help="Audit XPR, literals and IP/BD paths")
    project.add_argument("xpr")
    project.add_argument("--allow-root", action="append", default=[])
    project.add_argument("--search-dir", action="append", default=[],
                         help="Explicit asset/include search directory; not an automatic Vivado setting")
    project.add_argument("--output", required=True)
    trees = commands.add_parser("compare", help="Compare matching source trees read-only")
    trees.add_argument("reference")
    trees.add_argument("candidate")
    trees.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        output = absolute(args.output)
        roots = ([absolute(args.xpr).parent] + [absolute(p) for p in args.allow_root + args.search_dir]
                 if args.command == "project"
                 else [absolute(args.reference), absolute(args.candidate)])
        if any(within(output, [root.resolve()]) for root in roots):
            raise ValueError("Output must be outside all audited source trees")
        result = project_audit(args) if args.command == "project" else compare(args)
        with output.open("x", encoding="utf-8") as stream:
            json.dump(result, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        print(json.dumps({"status": result["status"], "report": str(output)}))
        return 0 if result["status"] == "STATIC_CLEAR" else 1
    except (OSError, ValueError, KeyError, TypeError, ET.ParseError) as error:
        print("ERROR: " + str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
