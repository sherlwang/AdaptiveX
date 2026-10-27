"""Shared inventory rules for engineering inputs and completed Vivado projects."""
from pathlib import Path
import hashlib
import os

ROOT_DIRECTORIES = {
    'src', 'ip', 'build', 'software', 'sim', 'data', 'matlab',
    'results', 'docs', 'tools', 'LICENSES', 'Tx', 'Rx',
}
ROOT_FILES = {'README.md', 'THIRD_PARTY_NOTICES.md', '.gitignore', '.gitattributes'}
IGNORED_DIRECTORIES = {'.git', 'validation', '__pycache__', '.Xil'}
IGNORED_SUFFIXES = {'.pyc', '.log', '.jou'}


def ignored(relative):
    """Exclude runtime caches and logs; keep source and generated design artifacts."""
    return (
        any(part in IGNORED_DIRECTORIES or part.endswith('.cache')
            for part in relative.parts)
        or relative.suffix in IGNORED_SUFFIXES
    )


def file_digest(path):
    checksum = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            checksum.update(chunk)
    return checksum.hexdigest()


def inventory_files(root):
    """Yield the same inventory in both the writer and the verifier."""
    root = Path(root)
    for base, directories, filenames in os.walk(root, topdown=True):
        base = Path(base)
        directories.sort()
        filenames.sort()
        retained = []
        for name in directories:
            path = base / name
            relative = path.relative_to(root)
            if ignored(relative):
                continue
            if path.is_symlink():
                raise RuntimeError('Symlinks are not part of this standalone package: ' + relative.as_posix())
            if len(relative.parts) == 1 and name not in ROOT_DIRECTORIES:
                raise RuntimeError('Unexpected engineering root entry: ' + name)
            retained.append(name)
        directories[:] = retained
        for name in filenames:
            path = base / name
            relative = path.relative_to(root)
            if relative.as_posix() == 'MANIFEST.json' or ignored(relative):
                continue
            if path.is_symlink():
                raise RuntimeError('Symlinks are not part of this standalone package: ' + relative.as_posix())
            if len(relative.parts) == 1 and name not in ROOT_FILES:
                raise RuntimeError('Unexpected engineering root entry: ' + name)
            yield path, relative.as_posix()
