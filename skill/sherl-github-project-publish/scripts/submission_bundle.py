#!/usr/bin/env python3
"""Prepare an AdaptiveX Git tree and complete, path-preserving Release ZIPs."""
from __future__ import annotations
import fnmatch
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import zipfile

FORMAT = 1
RELEASE_MANIFEST = 'submission-manifest.json'
PUBLICATION_MANIFEST = 'PUBLICATION_MANIFEST.json'
CHUNK = 1024 * 1024
VIDEO_SUFFIXES = {'.mp4', '.mov', '.avi', '.mkv', '.webm', '.mpg', '.mpeg', '.m4v', '.wmv', '.flv', '.3gp', '.m2ts'}
MEDIA_SUFFIXES = VIDEO_SUFFIXES | {'.pdf', '.docx', '.doc', '.pptx', '.ppt', '.odp', '.png', '.jpg', '.jpeg',
                                  '.svg', '.bmp', '.webp', '.tif', '.tiff', '.zip', '.rar', '.7z'}
RUNTIME_DIRECTORIES = ['.git', 'validation', '__pycache__', '.Xil', '*.cache']
RUNTIME_SUFFIXES = ['.pyc', '.log', '.jou']


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(CHUNK), b''):
            h.update(block)
    return h.hexdigest()


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + '\n').encode('utf-8')


def name_ok(value):
    p = PurePosixPath(value)
    if (not value or p.is_absolute() or '..' in p.parts or p.as_posix() != value
            or '\\' in value or ':' in value or any(c in value for c in '\n\r\0')):
        raise ValueError('Unsafe relative path: ' + repr(value))
    return value


def file_metadata(path):
    mode = stat.S_IMODE(path.stat().st_mode)
    if mode & ~0o777:
        raise ValueError('Special file permissions are not supported: ' + path.name)
    return {'bytes': path.stat().st_size, 'sha256': digest(path), 'mode': mode}


def excluded_payload(relative, policy):
    # Apply submission-media exclusions at every depth without removing functional code.
    lowered = [part.casefold() for part in relative.parts]
    excluded_names = {value.casefold() for value in policy.get('exclude_names', ['2zyj.txt'])}
    if any(part in excluded_names for part in lowered):
        return True
    suffix = relative.suffix.casefold()
    if suffix in VIDEO_SUFFIXES:
        return True
    if suffix in MEDIA_SUFFIXES:
        patterns = [value.casefold() for value in policy['exclude_root_patterns']]
        return any(fnmatch.fnmatchcase(part, pattern) for part in lowered for pattern in patterns)
    return False


def walk_files(directory, excluded_names, policy):
    if directory.is_symlink():
        raise ValueError('Symbolic links are not publication inputs: ' + str(directory))
    for base, directories, files in os.walk(directory, topdown=True):
        base = Path(base)
        for name in list(directories):
            p = base / name
            if name in excluded_names:
                directories.remove(name)
            elif p.is_symlink():
                raise ValueError('Symbolic directory is not a publication input: ' + str(p))
        directories.sort()
        for name in sorted(files):
            p = base / name
            if excluded_payload(p.relative_to(directory), policy):
                continue
            if p.is_symlink() or not p.is_file():
                raise ValueError('Expected a regular publication file: ' + str(p))
            yield p


def select_inputs(source, policy):
    projects = [name for name in policy['project_directory_candidates'] if (source / name).exists()]
    if len(projects) != 1:
        raise ValueError('Expected exactly one engineering directory, found: ' + repr(projects))
    project = projects[0]
    required = policy.get('required_directories', [])
    directories = [project] + policy['include_directories']
    selected = []
    for name in directories:
        name_ok(name)
        d = source / name
        if not d.is_dir():
            if name in required or name == project:
                raise ValueError('Missing publication directory: ' + name)
            continue
        selected.extend(walk_files(d, set(policy.get('excluded_directory_names', ['.git'])), policy))
    for name in policy['include_root_files']:
        name_ok(name)
        p = source / name
        if not p.is_file() or p.is_symlink():
            raise ValueError('Missing/invalid root input: ' + name)
        selected.append(p)
    for p in sorted(source.iterdir()):
        if not p.is_file() or p.name in policy['include_root_files']:
            continue
        lowered = p.name.casefold()
        if any(fnmatch.fnmatchcase(lowered, v.casefold()) for v in policy['exclude_root_patterns']):
            continue
        if any(fnmatch.fnmatchcase(lowered, v.casefold()) for v in policy['include_root_patterns']):
            if p.is_symlink():
                raise ValueError('Symbolic input is not allowed: ' + p.name)
            selected.append(p)
    result = {}
    for p in sorted(set(selected), key=lambda v: v.relative_to(source).as_posix()):
        relative = name_ok(p.relative_to(source).as_posix())
        if excluded_payload(Path(relative), policy):
            continue
        result[relative] = file_metadata(p)
    return project, result


def write_browse_manifest(project_root):
    """Write inventory from copied data; never import or execute Submission-provided code."""
    path = project_root / 'MANIFEST.json'
    if path.is_file():
        book = json.loads(path.read_text(encoding='utf-8'))
        if not isinstance(book, dict):
            raise ValueError('Engineering manifest must be a JSON object')
    else:
        book = {'format': 2}
    rules = book.get('excluded_runtime_files',
                     {'directories': RUNTIME_DIRECTORIES, 'suffixes': RUNTIME_SUFFIXES})
    if not isinstance(rules, dict):
        raise ValueError('Invalid runtime exclusion metadata')
    directories = rules.get('directories', RUNTIME_DIRECTORIES)
    suffixes = rules.get('suffixes', RUNTIME_SUFFIXES)
    if any(not isinstance(values, list) or not all(isinstance(v, str) for v in values)
           for values in (directories, suffixes)):
        raise ValueError('Runtime exclusion rules must be string lists')
    entries = {}
    for file in sorted(project_root.rglob('*')):
        if not file.is_file():
            continue
        relative = file.relative_to(project_root)
        if relative.as_posix() == 'MANIFEST.json':
            continue
        if (any(fnmatch.fnmatchcase(part, pattern) for part in relative.parts for pattern in directories)
                or relative.suffix in suffixes):
            continue
        entries[relative.as_posix()] = {'bytes': file.stat().st_size, 'sha256': digest(file)}
    book.update({'scope': 'rebuild_inputs', 'excluded_runtime_files': rules, 'files': entries})
    path.write_bytes(json_bytes(book))


def publication_receipt(repo_dir, policy_sha):
    entries = []
    for path in sorted(repo_dir.rglob('*')):
        if not path.is_file() or path.name == PUBLICATION_MANIFEST:
            continue
        name = path.relative_to(repo_dir).as_posix()
        if '__pycache__' in path.parts:
            raise ValueError('Unexpected bytecode in Git tree: ' + name)
        entries.append({'path': name, 'bytes': path.stat().st_size, 'sha256': digest(path)})
    return {'schema_version': 1, 'scope': 'Reviewed AdaptiveX Git tree; complete files are Release assets',
            'policy_sha256': policy_sha, 'files': entries,
            'manual_content_review': [v['path'] for v in entries if Path(v['path']).suffix.lower()
                                      in {'.rar', '.gz', '.xsa', '.dcp', '.bit', '.docx', '.mlx', '.slx'}],
            'non_ascii_or_special_paths': [v['path'] for v in entries
                                          if not re.fullmatch(r'[A-Za-z0-9_./-]+', v['path'])]}


def verify_reuse(output, fingerprint, tag):
    plan_file = output / 'plan.json'
    if not plan_file.is_file():
        raise ValueError('Output exists without a completed plan; use another output directory: ' + str(output))
    plan = json.loads(plan_file.read_text(encoding='utf-8'))
    if Path(plan.get('repo_dir', '')).resolve() != (output / 'repo').resolve():
        raise ValueError('Prepared Git tree path leaves the preparation directory')
    if plan.get('fingerprint') != fingerprint or plan.get('tag') != tag:
        raise ValueError('Output belongs to a different source snapshot or preview mode')
    for asset in plan['assets']:
        name_ok(asset['name'])
        path = Path(asset['path'])
        if path.resolve() != (output / 'assets' / asset['name']).resolve() or '/' in asset['name']:
            raise ValueError('Prepared asset path leaves the assets directory')
        if not path.is_file() or path.stat().st_size != asset['bytes'] or digest(path) != asset['sha256']:
            raise ValueError('Existing prepared asset changed: ' + asset['name'])
    repo_dir = Path(plan['repo_dir'])
    receipt = json.loads((repo_dir / PUBLICATION_MANIFEST).read_text(encoding='utf-8'))
    actual = {p.relative_to(repo_dir).as_posix() for p in repo_dir.rglob('*') if p.is_file()
              and p.name != PUBLICATION_MANIFEST and '.git' not in p.parts}
    expected = {item['path'] for item in receipt['files']}
    if actual != expected:
        raise ValueError('Prepared Git tree has missing or extra files')
    for entry in receipt['files']:
        p = repo_dir / entry['path']
        if p.stat().st_size != entry['bytes'] or digest(p) != entry['sha256']:
            raise ValueError('Prepared Git input changed: ' + entry['path'])
    return plan


def prepare(source: Path, output: Path, policy_path: Path, repo: str, preview: bool = False) -> dict:
    source = Path(source).resolve(strict=True)
    output = Path(output).resolve()
    if not source.is_dir() or source == output or source in output.parents or output in source.parents:
        raise ValueError('Use a separate preparation directory outside Submission')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
        raise ValueError('Expected GitHub owner/repository')
    policy = json.loads(Path(policy_path).read_text(encoding='utf-8-sig'))
    if policy.get('schema_version') != 2 or policy.get('repository') != repo:
        raise ValueError('Publication policy schema/repository differs from requested target')
    policy_sha = digest(policy_path)
    project, inventory = select_inputs(source, policy)
    if not inventory:
        raise ValueError('No publication files selected')
    fingerprint = hashlib.sha256(json_bytes({'format': FORMAT, 'repo': repo,
                      'policy_sha256': policy_sha, 'files': inventory})).hexdigest()
    tag = ('preview-' if preview else 'submission-') + fingerprint[:12]
    if output.exists():
        return verify_reuse(output, fingerprint, tag)
    limit = policy.get('asset_raw_limit_bytes', 7 * 1024**3 // 4)
    if not isinstance(limit, int) or not 1024 * 1024 <= limit <= 7 * 1024**3 // 4:
        raise ValueError('Use an asset raw limit from1MiB through1.75GiB')
    groups = []; group = []; size = 0
    for name, item in inventory.items():
        if item['bytes'] > limit:
            raise ValueError('Single file exceeds ZIP grouping limit: ' + name)
        if group and size + item['bytes'] > limit:
            groups.append(group); group = []; size = 0
        group.append(name); size += item['bytes']
    if group:
        groups.append(group)
    output.mkdir(parents=True)
    assets_dir = output / 'assets'; assets_dir.mkdir()
    repo_dir = output / 'repo'; repo_dir.mkdir()
    assets = []; assigned = {}
    for number, names in enumerate(groups, 1):
        filename = f'submission-{number:03d}.zip'
        dest = assets_dir / filename
        with zipfile.ZipFile(dest, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as archive:
            for name in names:
                spec = inventory[name]
                info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = (stat.S_IFREG | spec['mode']) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                checksum = hashlib.sha256(); count = 0
                with (source / name).open('rb') as stream, archive.open(info, 'w', force_zip64=True) as target:
                    for block in iter(lambda: stream.read(CHUNK), b''):
                        target.write(block); checksum.update(block); count += len(block)
                if count != spec['bytes'] or checksum.hexdigest() != spec['sha256']:
                    raise ValueError('Source changed while archiving: ' + name)
                assigned[name] = filename
        if dest.stat().st_size >= 2 * 1024**3:
            raise ValueError('Release asset reaches2GiB: ' + filename)
        assets.append({'name': filename, 'path': str(dest), 'bytes': dest.stat().st_size,
                       'sha256': digest(dest), 'files': len(names)})
    manifest = {'format': FORMAT, 'repository': repo, 'tag': tag, 'fingerprint': fingerprint,
                'project_directory': project, 'description': 'Complete approved Submission files; source file bytes preserved.',
                'parts': [{key: item[key] for key in ('name', 'bytes', 'sha256', 'files')} for item in assets],
                'files': {name: {**spec, 'part': assigned[name]} for name, spec in inventory.items()}}
    manifest_bytes = json_bytes(manifest)
    (assets_dir / RELEASE_MANIFEST).write_bytes(manifest_bytes)
    assets.append({'name': RELEASE_MANIFEST, 'path': str(assets_dir / RELEASE_MANIFEST),
                   'bytes': len(manifest_bytes), 'sha256': hashlib.sha256(manifest_bytes).hexdigest()})
    exclude_project = set(policy.get('git_excluded_project_directories', ['Tx', 'Rx']))
    exclude_names = set(policy.get('git_excluded_directory_names', ['__pycache__', '.Xil']))
    git_limit = policy.get('git_max_file_bytes', 100 * 1024**2)
    for name in inventory:
        parts = PurePosixPath(name).parts
        if parts[0] == 'vitis_workspace' or (parts[0] == project and len(parts) > 1 and parts[1] in exclude_project):
            continue
        if any(p in exclude_names for p in parts):
            continue
        if inventory[name]['bytes'] >= git_limit:
            raise ValueError('Git-browsable file reaches100MiB: ' + name)
        dest = repo_dir / name; dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / name, dest)
        if digest(dest) != inventory[name]['sha256']:
            raise ValueError('Source changed while copying: ' + name)
    write_browse_manifest(repo_dir / project)
    root_readme = repo_dir / 'README.md'
    original_readme = root_readme.read_text(encoding='utf-8')
    introduction = f'''<!-- AdaptiveX publication entry -->
## 完整工程下载

本页提供源码、Skill、技术文档与代码包的浏览入口。已完成综合/实现的 Tx/Rx 工程和原生 Vitis 工作区随本版 Release 提供，下载后保持原相对目录。

[下载本版完整工程](https://github.com/{repo}/releases/tag/{tag})，或在本仓库目录执行：

```bash
python3 skill/sherl-github-project-publish/scripts/receive_submission.py --repo {repo} --tag {tag} --output /path/to/AdaptiveX_Submission
```

输出目录须为空。脚本下载全部附件、核对 SHA-256 并恢复文件。GitHub 自动生成的源码 ZIP 只包含可浏览文件；完整工程使用上述 Release 附件。

---

'''
    root_readme.write_text(introduction + original_readme, encoding='utf-8')
    # Generated rules preserve exact reviewed bytes and ignore no selected publication inputs.
    (repo_dir / '.gitignore').write_text('.git/\n__pycache__/\n*.pyc\n', encoding='utf-8')
    (repo_dir / '.gitattributes').write_text('* -text\n', encoding='utf-8')
    (repo_dir / 'SUBMISSION_RELEASE.json').write_bytes(manifest_bytes)
    receipt = publication_receipt(repo_dir, policy_sha)
    (repo_dir / PUBLICATION_MANIFEST).write_bytes(json_bytes(receipt))
    _, after = select_inputs(source, policy)
    if inventory != after:
        raise ValueError('Submission changed during preparation; do not publish this output')
    plan = {'format': FORMAT, 'tag': tag, 'fingerprint': fingerprint, 'repo': repo,
            'repo_dir': str(repo_dir), 'assets': assets, 'manifest_asset': RELEASE_MANIFEST,
            'preview': bool(preview), 'policy_sha256': policy_sha,
            'counts': {'source_files': len(inventory), 'source_bytes': sum(v['bytes'] for v in inventory.values()),
                       'git_files': len(receipt['files']), 'git_bytes': sum(v['bytes'] for v in receipt['files']),
                       'archive_parts': len(groups), 'asset_bytes': sum(v['bytes'] for v in assets)}}
    (output / 'plan.json').write_bytes(json_bytes(plan))
    return plan


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--policy', type=Path, required=True)
    parser.add_argument('--repo', default='sherlwang/AdaptiveX')
    parser.add_argument('--preview', action='store_true')
    args = parser.parse_args()
    print(json.dumps(prepare(args.source, args.output, args.policy, args.repo, args.preview), ensure_ascii=False, indent=2))
