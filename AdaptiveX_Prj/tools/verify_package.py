#!/usr/bin/env python3
"""Verify engineering files and compressed core payloads without Vivado."""
from pathlib import Path, PurePosixPath
import argparse
import gzip
import hashlib
import json
from manifest_rules import file_digest, inventory_files

ROOT = Path(__file__).resolve().parents[1]


def safe_path(root, name):
    relative = PurePosixPath(name)
    if relative.is_absolute() or '..' in relative.parts or '\\' in name:
        raise RuntimeError('Unsafe package path: ' + name)
    path = root.joinpath(*relative.parts)
    if not path.resolve().is_relative_to(root.resolve()):
        raise RuntimeError('Package path leaves its root: ' + name)
    return path


def check_core(file, root, errors):
    meta = json.loads(file.read_text())
    for name, spec in meta['files'].items():
        path = safe_path(file.parent, spec['path'])
        if file_digest(path) != spec['sha256']:
            errors.append('Core hash: ' + path.relative_to(root).as_posix())
        checksum = hashlib.sha256()
        size = 0
        top_found = False
        tail = b''
        opener = gzip.open if path.suffix == '.gz' else open
        declaration = ('module ' + meta['name']).encode()
        with opener(path, 'rb') as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                checksum.update(chunk)
                size += len(chunk)
                if name == 'core_sim.v':
                    top_found |= declaration in tail + chunk
                    tail = chunk[-len(declaration):]
        if size != spec['raw_bytes'] or checksum.hexdigest() != spec['raw_sha256']:
            errors.append('Expanded hash: ' + path.relative_to(root).as_posix())
        if name == 'core_sim.v' and not top_found:
            errors.append('Core top declaration: ' + meta['name'])


def check():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--manifest', type=Path, help='Default: ROOT/MANIFEST.json')
    args = parser.parse_args()
    root = args.root.resolve()
    manifest = args.manifest or root / 'MANIFEST.json'
    if not manifest.is_file():
        raise RuntimeError('MANIFEST.json is missing')
    book = json.loads(manifest.read_text())
    errors = []
    for name, spec in book['files'].items():
        try:
            path = safe_path(root, name)
            if not path.is_file():
                errors.append('Missing: ' + name)
            elif path.stat().st_size != spec['bytes'] or file_digest(path) != spec['sha256']:
                errors.append('Changed: ' + name)
        except (OSError, RuntimeError) as exc:
            errors.append(str(exc))
    try:
        actual = {name for _, name in inventory_files(root)}
        errors.extend('Unlisted: ' + name for name in sorted(actual - set(book['files'])))
    except (OSError, RuntimeError) as exc:
        errors.append(str(exc))
    cores = 0
    for file in sorted((root / 'ip').glob('*/*/core.json')):
        try:
            check_core(file, root, errors)
        except (OSError, RuntimeError, KeyError, ValueError) as exc:
            errors.append('Core metadata/payload ' + file.relative_to(root).as_posix() + ': ' + str(exc))
        cores += 1
    if cores != 9:
        errors.append('Expected nine delivered cores, found ' + str(cores))
    print(json.dumps({'status': 'PASS' if not errors else 'FAIL', 'files': len(book['files']),
                      'cores': cores, 'scope': book.get('scope', 'legacy'), 'errors': errors}, indent=2))
    if errors:
        raise SystemExit(1)


if __name__ == '__main__':
    check()
