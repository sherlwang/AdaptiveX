#!/usr/bin/env python3
"""Download and verify a complete AdaptiveX Submission from GitHub Release ZIPs."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tempfile
from urllib.parse import quote
from urllib.request import urlopen
import zipfile

CHUNK = 1024 * 1024
MANIFEST_NAME = 'submission-manifest.json'


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for data in iter(lambda: stream.read(CHUNK), b''):
            h.update(data)
    return h.hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate JSON key: ' + key)
        result[key] = value
    return result


def safe_name(value):
    p = PurePosixPath(value)
    if (not isinstance(value, str) or not value or p.is_absolute() or '..' in p.parts
            or p.as_posix() != value or '\\' in value or ':' in value or '.git' in p.parts
            or any(c in value for c in '\r\n\0')):
        raise ValueError('Unsafe archive path: ' + repr(value))
    return value


def validate_manifest(manifest, repo=None, tag=None):
    if manifest.get('format') != 1:
        raise ValueError('Unsupported Submission manifest format')
    actual_repo = manifest.get('repository', '')
    actual_tag = manifest.get('tag', '')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', actual_repo):
        raise ValueError('Invalid repository in manifest')
    if not re.fullmatch(r'(?:preview|submission)-[0-9a-f]{12}', actual_tag):
        raise ValueError('Invalid release tag in manifest')
    if repo is not None and repo != actual_repo:
        raise ValueError('Manifest belongs to another repository')
    if tag not in (None, 'latest') and tag != actual_tag:
        raise ValueError('Manifest belongs to another release')
    if not re.fullmatch('[0-9a-f]{64}', manifest.get('fingerprint', '')):
        raise ValueError('Invalid source fingerprint')
    if not actual_tag.endswith(manifest['fingerprint'][:12]):
        raise ValueError('Release tag does not match source fingerprint')
    parts = manifest.get('parts')
    files = manifest.get('files')
    if not isinstance(parts, list) or not parts or not isinstance(files, dict) or not files:
        raise ValueError('Empty parts or files inventory')
    names = set()
    counts = {}
    for part in parts:
        name = part.get('name', '')
        if not re.fullmatch(r'submission-[0-9]{3,}\.zip', name) or name in names:
            raise ValueError('Invalid or duplicate archive part name')
        if not isinstance(part.get('bytes'), int) or not 0 < part['bytes'] < 2 * 1024**3:
            raise ValueError('Invalid archive part size')
        if not re.fullmatch('[0-9a-f]{64}', part.get('sha256', '')):
            raise ValueError('Invalid archive part SHA256')
        names.add(name); counts[name] = 0
    for name, spec in files.items():
        safe_name(name)
        if not isinstance(spec, dict) or spec.get('part') not in names:
            raise ValueError('File references an unknown archive part')
        if not isinstance(spec.get('bytes'), int) or not 0 <= spec['bytes'] < 2 * 1024**3:
            raise ValueError('Invalid file size: ' + name)
        if not isinstance(spec.get('mode'), int) or spec['mode'] & ~0o777:
            raise ValueError('Invalid file mode: ' + name)
        if not re.fullmatch('[0-9a-f]{64}', spec.get('sha256', '')):
            raise ValueError('Invalid file SHA256: ' + name)
        counts[spec['part']] += 1
    if any(part.get('files') != counts[part['name']] for part in parts):
        raise ValueError('Archive part file count differs from manifest')
    return manifest


def get_url(repo, tag, filename):
    if tag == 'latest':
        return f'https://github.com/{repo}/releases/latest/download/{quote(filename)}'
    return f'https://github.com/{repo}/releases/download/{quote(tag, safe="")}/{quote(filename)}'


def download(url, path, expected_bytes=None):
    count = 0
    with urlopen(url, timeout=60) as response, Path(path).open('xb') as stream:
        while data := response.read(CHUNK):
            count += len(data)
            if count > (expected_bytes if expected_bytes is not None else 20 * 1024**2):
                raise ValueError('Downloaded file exceeds declared size or manifest limit')
            stream.write(data)
    if expected_bytes is not None and count != expected_bytes:
        raise ValueError('Downloaded file length differs from manifest')


def restore(manifest_path, assets_directory, output, repo=None, tag=None):
    output = Path(output).absolute()
    if output.is_symlink() or (output.exists() and (not output.is_dir() or any(output.iterdir()))):
        raise ValueError('Output must be a new or empty directory')
    if output.parent.is_symlink():
        raise ValueError('Use a real output parent directory')
    output.parent.mkdir(parents=True, exist_ok=True)
    offline = Path(assets_directory).resolve(strict=True) if assets_directory is not None else None
    if offline is not None and not offline.is_dir():
        raise ValueError('Assets directory must be a directory')
    with tempfile.TemporaryDirectory(prefix='.adaptivex_receive_', dir=output.parent) as temporary:
        temporary = Path(temporary)
        if manifest_path is not None:
            path = Path(manifest_path).resolve(strict=True)
        elif offline is not None:
            path = offline / MANIFEST_NAME
        else:
            if repo is None:
                repo = 'sherlwang/AdaptiveX'
            if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
                raise ValueError('Expected GitHub owner/repository')
            path = temporary / MANIFEST_NAME
            download(get_url(repo, tag or 'latest', MANIFEST_NAME), path, None)
        if path.stat().st_size > 20 * 1024**2:
            raise ValueError('Manifest exceeds20MiB')
        manifest = validate_manifest(json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=unique_object), repo, tag)
        downloaded = {}
        for part in manifest['parts']:
            if offline is not None:
                file = offline / part['name']
            else:
                file = temporary / part['name']
                download(get_url(manifest['repository'], manifest['tag'], part['name']), file, part['bytes'])
            if file.is_symlink() or not file.is_file() or file.stat().st_size != part['bytes'] or digest(file) != part['sha256']:
                raise ValueError('Archive hash/size mismatch: ' + part['name'])
            downloaded[part['name']] = file
        staging = temporary / 'restored'; staging.mkdir()
        seen = set()
        for part_name, archive_path in downloaded.items():
            with zipfile.ZipFile(archive_path) as archive:
                for member in archive.infolist():
                    name = safe_name(member.filename)
                    mode = (member.external_attr >> 16) & 0xFFFF
                    spec = manifest['files'].get(name)
                    if (name in seen or spec is None or spec['part'] != part_name
                            or member.is_dir() or stat.S_ISLNK(mode)
                            or (stat.S_IFMT(mode) not in (0, stat.S_IFREG))
                            or member.flag_bits & 1 or member.file_size != spec['bytes']
                            or stat.S_IMODE(mode) != spec['mode']):
                        raise ValueError('Unexpected/duplicate/invalid archive member: ' + name)
                    dest = staging.joinpath(*PurePosixPath(name).parts)
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    checksum = hashlib.sha256(); length = 0
                    with archive.open(member) as src, dest.open('xb') as target:
                        while block := src.read(CHUNK):
                            length += len(block)
                            if length > spec['bytes']:
                                raise ValueError('Expanded file exceedsdeclaredsize: ' + name)
                            checksum.update(block); target.write(block)
                    if length != spec['bytes'] or checksum.hexdigest() != spec['sha256']:
                        raise ValueError('Expanded file hash/size mismatch: ' + name)
                    if os.name == 'posix':
                        dest.chmod(spec['mode'])
                    seen.add(name)
        if seen != set(manifest['files']):
            raise ValueError('Archive set is incomplete')
        for name, spec in manifest['files'].items():
            file = staging.joinpath(*PurePosixPath(name).parts)
            if digest(file) != spec['sha256'] or file.stat().st_size != spec['bytes']:
                raise ValueError('Restored file differs: ' + name)
            if os.name == 'posix' and stat.S_IMODE(file.stat().st_mode) != spec['mode']:
                raise ValueError('Restored file mode differs: ' + name)
        # Publish the verified tree only after every part and every file passed.
        if output.exists():
            if output.is_symlink() or not output.is_dir() or any(output.iterdir()):
                raise ValueError('Output changed while receiving')
            output.rmdir()
        os.replace(staging, output)
        return {'status': 'PASS', 'repository': manifest['repository'], 'tag': manifest['tag'],
                'fingerprint': manifest['fingerprint'], 'files': len(seen),
                'bytes': sum(v['bytes'] for v in manifest['files'].values()), 'output': str(output)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', help='Default:sherlwang/AdaptiveX; local manifest may supply it')
    parser.add_argument('--tag', default='latest')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, help='Use this local release manifest')
    parser.add_argument('--assets-directory', type=Path, help='Offline archive directory; never accesses network')
    args = parser.parse_args()
    print(json.dumps(restore(args.manifest, args.assets_directory, args.output, args.repo, args.tag), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
