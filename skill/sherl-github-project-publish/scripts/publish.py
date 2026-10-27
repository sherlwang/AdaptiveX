#!/usr/bin/env python3
"""Stage an explicit public file selection, verify it, and optionally push it with Git."""
import argparse
import fnmatch
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit


MANIFEST = 'PUBLICATION_MANIFEST.json'
MAX_FILE_BYTES = 100 * 1024 * 1024
SECRET = re.compile(rb'-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----|\bgh[pousr]_[A-Za-z0-9]{30,}|\bgithub_pat_[A-Za-z0-9_]{30,}')
OPAQUE = {'.rar', '.zip', '.7z', '.gz', '.tgz', '.tar', '.docx', '.xlsx', '.pptx', '.mlx', '.slx', '.xsa', '.dcp', '.edf', '.edn', '.bit'}


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def relative_name(value):
    p = PurePosixPath(value)
    if not value or p.is_absolute() or '..' in p.parts or '\\' in value or p.as_posix() != value or any(c in value for c in '\n\r\0'):
        raise ValueError(f'Use a normalized relative path with /: {value!r}')
    if '.git' in p.parts or value == MANIFEST:
        raise ValueError(f'Reserved publication path: {value}')
    return value


def excluded(name, patterns):
    return any(fnmatch.fnmatchcase(name, pat) or
               (pat.startswith('**/') and fnmatch.fnmatchcase(name, pat[3:])) or
               name == pat.rstrip('/') or name.startswith(pat.rstrip('/') + '/')
               for pat in patterns)


def inspect_file(path, name):
    if path.is_symlink() or not path.is_file():
        raise ValueError(f'Expected a regular file: {name}')
    size = path.stat().st_size
    if size >= MAX_FILE_BYTES:
        raise ValueError(f'File reaches the 100 MiB Git limit: {name}. Use a separately approved Release/LFS workflow.')
    if path.name.lower() in {'.env', 'id_rsa', 'id_ed25519'} or path.suffix.lower() in {'.nky', '.bek', '.p12', '.pfx'}:
        raise ValueError(f'Credential or device-key file is not publishable with this helper: {name}')
    overlap = b''
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            if SECRET.search(overlap + chunk):
                raise ValueError(f'Possible private key or GitHub token found in {name}; contents were not printed.')
            overlap = chunk[-256:]
    return {'path': name, 'bytes': size, 'sha256': digest(path)}


def stage(args):
    source = args.source.resolve(strict=True)
    output = args.output.absolute()
    if not source.is_dir() or output.exists() or output.is_symlink():
        raise ValueError('Source must be a directory; output must not exist.')
    if output.resolve().is_relative_to(source) or source.is_relative_to(output.resolve()):
        raise ValueError('Keep source and publication output in separate trees.')
    policy = json.loads(args.policy.read_text(encoding='utf-8-sig'))
    include = policy.get('include')
    patterns = policy.get('exclude', [])
    if not isinstance(include, list) or not include or not all(isinstance(n, str) for n in include):
        raise ValueError('Policy needs a nonempty include list of exact relative files/directories.')
    if not isinstance(patterns, list) or not all(isinstance(n, str) for n in patterns):
        raise ValueError('exclude must be a list of glob strings.')
    names = set()
    for selection in include:
        relative_name(selection)
        selected = source / selection
        for p in [selected, *selected.parents]:
            if p == source:
                break
            if p.is_symlink():
                raise ValueError(f'Symlink in selected input: {selection}')
        if not selected.exists():
            raise ValueError(f'Included path does not exist: {selection}')
        candidates = [selected] if selected.is_file() else sorted(selected.rglob('*'))
        for path in candidates:
            name = path.relative_to(source).as_posix()
            if '.git' in PurePosixPath(name).parts or excluded(name, patterns):
                continue
            if path.is_symlink():
                raise ValueError(f'Symlink is not allowed: {name}')
            if path.is_file():
                relative_name(name)
                names.add(name)
    if not names:
        raise ValueError('Selection contains no publishable files.')
    entries = [inspect_file(source / name, name) for name in sorted(names)]
    review = [e['path'] for e in entries if Path(e['path']).suffix.lower() in OPAQUE]
    naming = [e['path'] for e in entries if not re.fullmatch(r'[A-Za-z0-9_./-]+', e['path'])]
    receipt = {'schema_version': 1, 'scope': 'Explicit public selection; no claim of complete confidentiality auditing',
               'policy_sha256': digest(args.policy), 'files': entries,
               'manual_content_review': review, 'non_ascii_or_special_paths': naming}
    if args.plan:
        print(json.dumps(receipt, indent=2, ensure_ascii=False))
        return
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.publication_stage_', dir=output.parent) as tmp:
        staged = Path(tmp) / 'tree'
        staged.mkdir()
        for entry in entries:
            src, dst = source / entry['path'], staged / entry['path']
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dst)
            if digest(dst) != entry['sha256'] or digest(src) != entry['sha256']:
                raise ValueError(f'Source changed while staging: {entry["path"]}')
        (staged / MANIFEST).write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        if output.exists():
            raise ValueError('Output appeared while staging; refusing to replace it.')
        os.rename(staged, output)
    print(json.dumps({'stage': 'PASS', 'file_count': len(entries), 'total_bytes': sum(e['bytes'] for e in entries),
                      'manual_content_review': review, 'non_ascii_or_special_paths': naming,
                      'output': str(output)}, ensure_ascii=False, indent=2))


def check(directory):
    directory = directory.resolve(strict=True)
    if not directory.is_dir():
        raise ValueError('directory must be a directory.')
    manifest_path = directory / MANIFEST
    if manifest_path.is_symlink():
        raise ValueError('Publication manifest must not be a symlink.')
    receipt = json.loads(manifest_path.read_text(encoding='utf-8'))
    expected = {relative_name(e['path']): e for e in receipt['files']}
    if not expected or len(expected) != len(receipt['files']):
        raise ValueError('Empty or duplicate publication manifest entries.')
    actual = set()
    for path in directory.rglob('*'):
        name = path.relative_to(directory).as_posix()
        if '.git' in PurePosixPath(name).parts:
            continue
        if path.is_symlink():
            raise ValueError(f'Symlink in publication: {name}')
        if path.is_file() and name != MANIFEST:
            actual.add(name)
    if actual != set(expected):
        raise ValueError(f'Files differ from the selection. Extra: {sorted(actual-set(expected))}; missing: {sorted(set(expected)-actual)}')
    for name, entry in expected.items():
        if inspect_file(directory / name, name) != entry:
            raise ValueError(f'File changed after staging: {name}. Regenerate the publication directory.')
    return receipt


def git(directory, *args, check_return=True):
    result = subprocess.run(['git', '-C', str(directory), *args], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=300)
    if check_return and result.returncode:
        raise ValueError(f'Git {args[0]} failed: {result.stderr.strip()}')
    return result


def upload(args):
    directory = args.directory.resolve(strict=True)
    receipt = check(directory)
    if not shutil.which('git'):
        raise ValueError('Install Git first.')
    remote = args.remote
    if remote.startswith('-') or any(c in remote for c in '\n\r\0'):
        raise ValueError('Invalid remote.')
    parsed = urlsplit(remote)
    if parsed.scheme and parsed.scheme not in {'https', 'file', 'ssh'}:
        raise ValueError('Use HTTPS, SSH, or a local test remote.')
    if parsed.scheme == 'https' and (parsed.username or parsed.password or parsed.query or parsed.fragment):
        raise ValueError('Do not put tokens or credentials in the remote URL.')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_/-]*', args.branch) or '..' in args.branch:
        raise ValueError('Use a simple branch name such as main.')
    if not (directory / '.git').exists():
        git(directory, 'init', '-b', args.branch)
    if (directory / '.git').is_symlink() or not (directory / '.git').is_dir():
        raise ValueError('Use an independent publication repository with its own .git directory.')
    root = git(directory, 'rev-parse', '--show-toplevel').stdout.strip()
    if Path(root).resolve() != directory:
        raise ValueError('The publication directory is not the Git root.')
    branch = git(directory, 'symbolic-ref', '--short', 'HEAD').stdout.strip()
    if branch != args.branch:
        raise ValueError(f'Current branch is {branch}; helper will not switch branches.')
    for key in ['user.name', 'user.email']:
        if not git(directory, 'config', '--get', key, check_return=False).stdout.strip():
            raise ValueError(f'Configure {key} for this repository; no global identity was changed.')
    if git(directory, 'diff', '--cached', '--quiet', check_return=False).returncode:
        raise ValueError('Existing staged changes need review before using this helper.')
    paths = [MANIFEST] + [entry['path'] for entry in receipt['files']]
    old_manifest = git(directory, 'show', f'HEAD:{MANIFEST}', check_return=False)
    previously_managed = set()
    if not old_manifest.returncode:
        old = json.loads(old_manifest.stdout)
        previously_managed = {MANIFEST, *(relative_name(e['path']) for e in old['files'])}
    tracked = set(git(directory, 'ls-files', '-z').stdout.rstrip('\0').split('\0')) - {''}
    if tracked - set(paths) - previously_managed:
        raise ValueError('Repository tracks files outside this publication workflow; use a dedicated publication clone.')
    origin = git(directory, 'remote', 'get-url', 'origin', check_return=False)
    if origin.returncode:
        git(directory, 'remote', 'add', 'origin', remote)
    elif origin.stdout.strip() != remote:
        raise ValueError('Existing origin differs from --remote; helper will not replace it.')
    # Only the manifest-listed content is added, never an unfiltered git add .
    for start in range(0, len(paths), 100):
        git(directory, '-c', 'core.autocrlf=false', 'add', '--', *paths[start:start+100])
    removed = sorted(previously_managed - set(paths))
    for start in range(0, len(removed), 100):
        git(directory, 'add', '-u', '--', *removed[start:start+100])
    index = {}
    for entry in git(directory, 'ls-files', '--stage', '-z').stdout.split('\0'):
        if entry:
            meta, name = entry.split('\t', 1)
            mode, oid, stage_number = meta.split()
            if stage_number != '0':
                raise ValueError('Unresolved Git index entry; no commit was made.')
            index[name] = oid
    if set(index) != set(paths):
        raise ValueError('Git index differs from the publication selection; no commit was made.')
    for start in range(0, len(paths), 100):
        batch = paths[start:start+100]
        raw_objects = git(directory, 'hash-object', '--no-filters', '--', *batch).stdout.splitlines()
        if any(index[name] != oid for name, oid in zip(batch, raw_objects)):
            raise ValueError('Git attributes or filters changed staged bytes. Review .gitattributes; no commit was made.')
    if git(directory, 'diff', '--cached', '--quiet', check_return=False).returncode:
        git(directory, 'commit', '-m', args.message)
    commit = git(directory, 'rev-parse', 'HEAD').stdout.strip()
    if args.push:
        git(directory, 'push', '--set-upstream', 'origin', args.branch)
    print(json.dumps({'local_commit': commit, 'push_performed': args.push,
                      'files': len(paths), 'branch': args.branch,
                      'note': 'No history rewrite, visibility change, or force push was performed.'}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('stage', help='Create an independent tree from an explicit file policy')
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--policy', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--plan', action='store_true')
    p = sub.add_parser('check', help='Check current files against the publication manifest')
    p.add_argument('--directory', type=Path, required=True)
    p = sub.add_parser('upload', help='Create a local commit; network push requires --push')
    p.add_argument('--directory', type=Path, required=True)
    p.add_argument('--remote', required=True)
    p.add_argument('--message', default='Publish reviewed project release')
    p.add_argument('--branch', default='main')
    p.add_argument('--push', action='store_true')
    args = parser.parse_args()
    try:
        if args.command == 'stage':
            stage(args)
        elif args.command == 'check':
            receipt = check(args.directory)
            print(json.dumps({'check': 'PASS', 'files': len(receipt['files']),
                              'manual_content_review': receipt.get('manual_content_review', [])}, indent=2))
        else:
            upload(args)
        return 0
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
