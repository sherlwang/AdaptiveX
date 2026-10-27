#!/usr/bin/env python3
"""Publish one approved Submission snapshot as browsable Git files and a complete Release."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import uuid

sys.dont_write_bytecode = True

MANIFEST = 'PUBLICATION_MANIFEST.json'


class PublishError(RuntimeError):
    pass


def digest(path: Path) -> str:
    checksum = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            checksum.update(chunk)
    return checksum.hexdigest()


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    temporary.replace(path)


def run(command, *, env=None, cwd=None, check=True, input_text=None, timeout=3600):
    result = subprocess.run([str(item) for item in command], cwd=cwd, env=env,
                            input=input_text, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=timeout)
    if check and result.returncode:
        # Credentials are supplied by gh, never interpolated into URLs or commands.
        message = (result.stderr or result.stdout).strip()
        raise PublishError(f'{Path(str(command[0])).name} {command[1]} failed: {message}')
    return result


def find_gh(explicit=None) -> Path:
    candidates = [Path(explicit)] if explicit else []
    found = shutil.which('gh')
    if found:
        candidates.append(Path(found))
    cache = Path.home() / '.cache/adaptivex-publish/cli'
    if cache.is_dir():
        candidates.extend(sorted(cache.glob('**/bin/gh'), key=lambda path: path.stat().st_mtime,
                                 reverse=True))
    for path in candidates:
        if path.is_file() and os.access(path, os.X_OK):
            return path.resolve()
    raise PublishError('GitHub CLI (gh) is not available. Install the official CLI, then use --gh if it is not on PATH.')


class GitHub:
    def __init__(self, executable: Path, repo: str):
        self.executable = executable
        self.repo = repo
        self.env = os.environ.copy()
        self.env.update(GH_PROMPT_DISABLED='1', GIT_TERMINAL_PROMPT='0',
                        GH_NO_UPDATE_NOTIFIER='1', GH_PAGER='cat')

    def command(self, *arguments, check=True, input_text=None, timeout=3600):
        return run([self.executable, *arguments], env=self.env, check=check,
                   input_text=input_text, timeout=timeout)

    def api(self, endpoint: str, *, missing=False, method=None, payload=None):
        arguments = ['api', '--hostname', 'github.com', endpoint]
        if method:
            arguments += ['--method', method]
        if payload is not None:
            arguments += ['--input', '-']
        response = self.command(*arguments, check=False,
                                input_text=json.dumps(payload) if payload is not None else None)
        if response.returncode:
            if missing and ('HTTP 404' in response.stderr or '"status":404' in response.stdout
                            or '"status": 404' in response.stdout):
                return None
            # GitHub answers ref lookups with 409 before an empty repository's first push.
            try:
                error = json.loads(response.stdout)
            except ValueError:
                error = {}
            if (missing and method in (None, 'GET')
                    and re.fullmatch(r'repos/[^/]+/[^/]+/git/ref/tags/.+', endpoint)
                    and ('HTTP 409' in response.stderr or str(error.get('status')) == '409')
                    and (error.get('message') == 'Git Repository is empty.'
                         or 'Git Repository is empty.' in response.stderr)):
                return None
            raise PublishError('GitHub request failed: ' + response.stderr.strip())
        return json.loads(response.stdout) if response.stdout.strip() else None

    def authenticate(self):
        status = self.command('auth', 'status', '--hostname', 'github.com', check=False)
        if status.returncode:
            raise PublishError('GitHub is not authenticated. Complete gh auth login --hostname github.com --web --git-protocol https first, then rerun this command.')
        user = self.api('user')
        info = self.api('repos/' + self.repo)
        if info.get('archived') or not info.get('permissions', {}).get('push'):
            raise PublishError('The authenticated account cannot write to this repository.')
        if info.get('default_branch', 'main') != 'main':
            raise PublishError('This workflow expects main; it will not change the repository default branch.')
        return user

    def release(self, tag):
        release = self.api(f'repos/{self.repo}/releases/tags/{tag}', missing=True)
        if release is not None:
            return release
        # The by-tag endpoint does not return unpublished drafts without an actual Git tag.
        page = 1
        while True:
            releases = self.api(f'repos/{self.repo}/releases?per_page=100&page={page}')
            drafts = [item for item in releases if item['draft'] and item['tag_name'] == tag]
            if len(drafts) > 1:
                raise PublishError('Multiple draft Releases use this tag; no assets were replaced.')
            if drafts:
                return self.api(f'repos/{self.repo}/releases/{drafts[0]["id"]}')
            if len(releases) < 100:
                return None
            page += 1

    def tag_commit(self, tag, *, missing=False):
        reference = self.api(f'repos/{self.repo}/git/ref/tags/{tag}', missing=missing)
        if reference is None:
            return None
        item = reference['object']
        for _ in range(4):
            if item['type'] == 'commit':
                return item['sha']
            if item['type'] != 'tag':
                break
            item = self.api(f'repos/{self.repo}/git/tags/{item["sha"]}')['object']
        raise PublishError('Release tag does not resolve to a commit.')


class GitCheckout:
    def __init__(self, directory: Path, gh: GitHub, *, remote=None):
        self.directory = directory
        self.gh = gh
        self.remote = remote or f'https://github.com/{gh.repo}.git'

    def git(self, *arguments, check=True):
        # Scope authentication and byte-preserving settings to this child process.
        helper = '!' + shlex.quote(str(self.gh.executable)) + ' auth git-credential'
        return run(['git', '-C', self.directory, '-c', 'credential.helper=',
                    '-c', 'credential.helper=' + helper, '-c', 'core.autocrlf=false',
                    *arguments], env=self.gh.env, check=check)

    def head(self):
        result = self.git('rev-parse', '--verify', 'HEAD', check=False)
        return result.stdout.strip() if not result.returncode else None

    def remote_head(self):
        result = self.git('ls-remote', '--heads', 'origin', 'refs/heads/main')
        return result.stdout.split()[0] if result.stdout.strip() else None

    def initialize(self, user, pending=None):
        self.directory.mkdir(parents=True, exist_ok=True)
        if not (self.directory / '.git').exists():
            if any(self.directory.iterdir()):
                raise PublishError('Publication checkout is not empty and is not a managed Git repository.')
            self.git('init', '-b', 'main')
            self.git('remote', 'add', 'origin', self.remote)
        if (self.directory / '.git').is_symlink() or not (self.directory / '.git').is_dir():
            raise PublishError('Publication checkout must have its own .git directory.')
        root = self.git('rev-parse', '--show-toplevel').stdout.strip()
        if Path(root).resolve() != self.directory.resolve():
            raise PublishError('Publication checkout must be the Git root.')
        if self.git('remote', 'get-url', 'origin').stdout.strip() != self.remote:
            raise PublishError('Existing origin is different; it was not replaced.')
        if self.git('symbolic-ref', '--short', 'HEAD').stdout.strip() != 'main':
            raise PublishError('Publication checkout is not on main; no branch was changed.')
        if self.git('status', '--porcelain', '--untracked-files=all').stdout:
            raise PublishError('Publication checkout has local changes; preserve or review them before rerunning.')
        remote = self.remote_head()
        head = self.head()
        if remote:
            self.git('fetch', '--no-tags', 'origin', 'refs/heads/main')
            fetched = self.git('rev-parse', 'FETCH_HEAD').stdout.strip()
            if head is None:
                self.git('checkout', '-b', 'main', fetched)
            elif head != fetched:
                if self.git('merge-base', '--is-ancestor', head, fetched, check=False).returncode == 0:
                    self.git('merge', '--ff-only', fetched)
                elif (pending == head and self.git('merge-base', '--is-ancestor', fetched, head,
                                                   check=False).returncode == 0):
                    pass  # Resume this workflow's recorded, previously unpushed commit.
                else:
                    raise PublishError('Local and remote history do not match this workflow; no reset or force push was performed.')
        elif head is not None and pending != head:
            raise PublishError('Remote main is missing while the local checkout already has history.')
        for key, value in [('user.name', user.get('name') or user['login']),
                           ('user.email', f'{user["id"]}+{user["login"]}@users.noreply.github.com')]:
            if not self.git('config', '--get', key, check=False).stdout.strip():
                self.git('config', '--local', key, value)
        return self.head()

    def synchronize(self, staged: Path):
        import publish as legacy
        expected = legacy.check(staged)
        tracked = set(self.git('ls-files', '-z').stdout.rstrip('\0').split('\0')) - {''}
        old_files = set()
        if self.head():
            if (self.directory / MANIFEST).exists():
                old = legacy.check(self.directory)
                old_files = {entry['path'] for entry in old['files']} | {MANIFEST}
            else:
                bootstrap = {'README', 'README.md', 'README.rst', 'LICENSE', 'LICENSE.md',
                             'LICENSE.txt', '.gitignore', '.gitattributes', '.editorconfig'}
                actual = set()
                for path in self.directory.rglob('*'):
                    relative = path.relative_to(self.directory)
                    if '.git' in relative.parts:
                        continue
                    if path.is_symlink():
                        raise PublishError('Initial repository contains a symlink; no files were replaced.')
                    if path.is_file():
                        actual.add(relative.as_posix())
                if not tracked or tracked - bootstrap or actual != tracked:
                    raise PublishError('Existing repository has unmanaged content beyond an initial README, license and standard Git settings.')
                old_files = tracked
        if tracked != old_files:
            raise PublishError('Tracked files are not exactly the previous managed publication.')
        paths = sorted({entry['path'] for entry in expected['files']} | {MANIFEST})
        removed = sorted(old_files - set(paths))
        for name in removed:
            (self.directory / name).unlink()
        # Only prune directories emptied by managed deletions; preserve any other content.
        for name in removed:
            parent = (self.directory / name).parent
            while parent != self.directory:
                try:
                    parent.rmdir()
                except OSError:
                    break
                parent = parent.parent
        for name in paths:
            target = self.directory / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(staged / name, target)
        for start in range(0, len(removed), 100):
            self.git('update-index', '--force-remove', '--', *removed[start:start + 100])
        for start in range(0, len(paths), 100):
            self.git('add', '-f', '--', *paths[start:start + 100])
        index = {}
        for entry in self.git('ls-files', '--stage', '-z').stdout.split('\0'):
            if entry:
                metadata, name = entry.split('\t', 1)
                _, object_id, stage = metadata.split()
                if stage != '0':
                    raise PublishError('Unresolved Git index entry.')
                index[name] = object_id
        if set(index) != set(paths):
            raise PublishError('Git index differs from the explicit publication selection.')
        for start in range(0, len(paths), 100):
            batch = paths[start:start + 100]
            objects = self.git('hash-object', '--no-filters', '--', *batch).stdout.splitlines()
            if len(objects) != len(batch) or any(index[name] != oid for name, oid in zip(batch, objects)):
                raise PublishError('Git filters changed staged bytes; no commit was made.')
        if self.git('diff', '--cached', '--quiet', check=False).returncode:
            self.git('commit', '-m', 'Update AdaptiveX submission snapshot')
        return self.head()

    def push(self, commit):
        self.git('push', 'origin', 'HEAD:refs/heads/main')
        if self.remote_head() != commit:
            raise PublishError('Remote main did not resolve to the pushed commit.')


def verify_asset(gh: GitHub, release: dict, local: dict, work: Path):
    matching = [item for item in release.get('assets', []) if item['name'] == local['name']]
    if len(matching) != 1:
        raise PublishError('Missing or duplicated Release asset: ' + local['name'])
    remote = matching[0]
    if remote.get('state') != 'uploaded' or remote['size'] != local['bytes']:
        raise PublishError('Release asset is incomplete or has a different size: ' + local['name'])
    checksum = remote.get('digest')
    if checksum:
        if checksum != 'sha256:' + local['sha256']:
            raise PublishError('Release asset digest mismatch: ' + local['name'])
    else:
        download = work / 'asset_checks' / str(remote['id'])
        download.mkdir(parents=True, exist_ok=True)
        target = download / local['name']
        if target.exists() and digest(target) != local['sha256']:
            raise PublishError('A previous asset check download is different: ' + local['name'])
        if not target.exists():
            gh.command('release', 'download', release['tag_name'], '--repo', gh.repo,
                       '--pattern', local['name'], '--dir', download)
        if digest(target) != local['sha256']:
            raise PublishError('Downloaded Release asset digest mismatch: ' + local['name'])
    return {'name': local['name'], 'bytes': local['bytes'], 'sha256': local['sha256'],
            'url': remote.get('browser_download_url')}


def publish_release(gh: GitHub, plan: dict, commit: str, work: Path, preview: bool, progress):
    tag = plan['tag']
    expected = {item['name']: item for item in plan['assets']}
    target = gh.tag_commit(tag, missing=True)
    if target is not None and target != commit:
        raise PublishError('Existing Git tag points to a different commit; no Release was created or published.')
    release = gh.release(tag)
    if release is None:
        notes = work / 'release_notes.md'
        notes.write_text(
            '# AdaptiveX submission\n\n'
            + ('This is a preview upload for delivery verification.\n\n' if preview else '')
            + 'The repository contains browsable source inputs, documentation and skills. '
              'The attached ZIP parts preserve the complete approved submission, including completed '
              'Vivado projects and the Vitis workspace.\n\n'
            + f'Git commit: `{commit}`\n\nSnapshot SHA-256: `{plan["fingerprint"]}`\n\n'
            + 'Download all ZIP parts and submission-manifest.json from this release. '
              'Use the supplied receive_submission.py to restore and verify the files.\n', encoding='utf-8')
        arguments = ['release', 'create', tag, '--repo', gh.repo, '--target', commit,
                     '--title', ('AdaptiveX preview ' if preview else 'AdaptiveX submission ') + plan['fingerprint'][:12],
                     '--notes-file', notes, '--draft']
        if preview:
            arguments.append('--prerelease')
        gh.command(*arguments)
        release = gh.release(tag)
        if release is None:
            raise PublishError('Draft Release creation returned, but the authenticated lookup could not find it. The pushed Git commit was retained.')
    if release.get('target_commitish') != commit:
        # Do not repoint a published tag or reuse another release's name.
        raise PublishError('Existing Release is bound to a different Git commit; no tag or asset was replaced.')
    extra = {item['name'] for item in release.get('assets', [])} - set(expected)
    if extra:
        raise PublishError('Existing Release contains unexpected assets: ' + ', '.join(sorted(extra)))
    for position, local in enumerate(plan['assets']):
        if digest(Path(local['path'])) != local['sha256'] or Path(local['path']).stat().st_size != local['bytes']:
            raise PublishError('Local Release asset changed after preparation: ' + local['name'])
        names = {item['name'] for item in release.get('assets', [])}
        if local['name'] not in names:
            if not release['draft']:
                raise PublishError('Published Release is missing an asset; it will not be overwritten.')
            progress('release_asset_uploading', asset=local['name'], bytes=local['bytes'],
                     completed_count=position, total_count=len(plan['assets']))
            gh.command('release', 'upload', tag, local['path'], '--repo', gh.repo, timeout=None)
            release = gh.release(tag)
            if release is None:
                raise PublishError('Release could not be found after uploading an asset; the completed Git push was retained.')
        verify_asset(gh, release, local, work)
        progress('release_asset_verified', asset=local['name'], bytes=local['bytes'],
                 completed_count=position + 1, total_count=len(plan['assets']))
    progress('release_assets_verified', release_id=release['id'])
    if release['draft']:
        target = gh.tag_commit(tag, missing=True)
        if target is not None and target != commit:
            raise PublishError('Git tag changed before publication; the Release remains a draft.')
        release = gh.api(f'repos/{gh.repo}/releases/{release["id"]}', method='PATCH', payload={
            'draft': False, 'prerelease': preview, 'make_latest': 'false' if preview else 'true'})
    release = gh.release(tag)
    if release is None:
        raise PublishError('Release could not be found after publication; inspect the recorded Git commit and draft state before retrying.')
    if release['draft'] or bool(release['prerelease']) != preview or gh.tag_commit(tag) != commit:
        raise PublishError('Published Release status or tag target did not match this snapshot.')
    verified = [verify_asset(gh, release, local, work) for local in plan['assets']]
    return release, verified


def publish(plan, *, gh, work: Path, preview: bool):
    user = gh.authenticate()
    repo_key = gh.repo.replace('/', '--')
    receipt_file = work / 'receipts' / repo_key / (plan['tag'] + '.json')
    receipt = {'schema_version': 1, 'repository': gh.repo, 'tag': plan['tag'],
               'fingerprint': plan['fingerprint'], 'preview': preview,
               'authenticated_login': user['login'], 'status': 'IN_PROGRESS',
               'source_unchanged_by_publisher': True}

    def progress(stage, **values):
        receipt.update(stage=stage, **values)
        write_json(receipt_file, receipt)
        print(json.dumps({'stage': stage, **values}, ensure_ascii=False), flush=True)

    # Each attempt uses a fresh checkout. Interrupted local copying cannot poison a rerun;
    # successfully pushed history and matching draft assets are recovered from GitHub.
    checkout_path = work / 'checkouts' / repo_key / (plan['tag'] + '-' + uuid.uuid4().hex[:12])
    checkout = GitCheckout(checkout_path, gh)
    receipt['checkout'] = str(checkout_path)
    try:
        checkout.initialize(user)
        progress('git_checkout_ready')
        commit = checkout.synchronize(Path(plan['repo_dir']))
        progress('git_committed', commit=commit)
        existing = gh.release(plan['tag'])
        if existing and existing.get('target_commitish') != commit:
            raise PublishError('This content tag already belongs to a different commit; refusing to replace it.')
        target = gh.tag_commit(plan['tag'], missing=True)
        if target is not None and target != commit:
            raise PublishError('This Git tag already belongs to a different commit; refusing to replace it.')
        checkout.push(commit)
        progress('git_pushed', commit=commit)
        release, assets = publish_release(gh, plan, commit, work, preview, progress)
        receipt.update(status='PASS', stage='release_published', commit=commit,
                       release_url=release['html_url'], repository_url=f'https://github.com/{gh.repo}',
                       release_assets=assets, published=True)
        write_json(receipt_file, receipt)
        return receipt
    except Exception as exc:
        receipt.update(status='FAILED', error=str(exc),
                       note='Git push and Release publication are separate operations. Completed steps were not rolled back. Rerun after resolving the reported condition to resume matching draft assets.')
        write_json(receipt_file, receipt)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--policy', type=Path, default=Path(__file__).resolve().parents[1] / 'assets/adaptivex_public_files.json')
    parser.add_argument('--repo', help='owner/repository; defaults to the project policy')
    parser.add_argument('--gh', type=Path, help='Official GitHub CLI executable')
    parser.add_argument('--work-dir', type=Path, default=Path.home() / '.cache/adaptivex-publish')
    parser.add_argument('--preview', action='store_true', help='Create a prerelease for this upload test')
    parser.add_argument('--push', action='store_true', help='Push Git and publish the verified Release')
    parser.add_argument('--plan', '--prepare-only', action='store_true', dest='plan', help='Prepare files and archives locally without signing in or uploading')
    args = parser.parse_args()
    try:
        if args.plan and args.push:
            raise PublishError('Choose --push or --plan, not both.')
        source = args.source.resolve(strict=True)
        work = args.work_dir.resolve()
        if source == work or source in work.parents or work in source.parents:
            raise PublishError('Keep publisher working data outside the Submission directory.')
        policy = json.loads(args.policy.read_text(encoding='utf-8-sig'))
        repo = args.repo or policy.get('repository') or policy.get('repo')
        if not repo or not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
            raise PublishError('Use an explicit GitHub owner/repository without a URL or credentials.')
        gh = GitHub(find_gh(args.gh), repo) if args.push else None
        if gh:
            gh.authenticate()  # Fail before spending time on a large archive when authentication is missing.
        work.mkdir(parents=True, exist_ok=True)
        from submission_bundle import prepare
        output = work / 'bundles' / ('snapshot-' + uuid.uuid4().hex[:16])
        plan = prepare(source, output, args.policy.resolve(strict=True), repo, preview=args.preview)
        print(json.dumps({'stage': 'prepared', 'tag': plan['tag'], 'fingerprint': plan['fingerprint'],
                          'counts': plan.get('counts'), 'work': str(output)}, ensure_ascii=False), flush=True)
        if not args.push:
            print('Prepared only; use --push to upload this approved Submission snapshot.')
            return 0
        receipt = publish(plan, gh=gh, work=work, preview=args.preview)
        print(json.dumps(receipt, ensure_ascii=False, indent=2))
        return 0
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as exc:
        print('ERROR: ' + str(exc), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
