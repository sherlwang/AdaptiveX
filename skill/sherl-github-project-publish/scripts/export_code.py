#!/usr/bin/env python3
"""Export AdaptiveX source inputs without Vivado run trees, then verify all bytes."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

PROJECT_DIRS = ('src', 'ip', 'build', 'software', 'sim', 'data', 'matlab',
                'results', 'docs', 'tools', 'LICENSES')
PROJECT_FILES = ('README.md', 'THIRD_PARTY_NOTICES.md', '.gitignore', '.gitattributes')
ROOT_FILES = ('README.md', 'LICENSE', '.gitignore', '.gitattributes')
SKIP_PARTS = {'.git', '__pycache__', 'validation', '.Xil'}
NOTICE = ('出于核心技术保护考虑，本次提供部分功能代码；'
          '技术文档及演示中的性能结果来自源工程。')

ROOT_README = '''# AdaptiveX 智能自适应多速率宽带通信系统：代码包

基于 AMD RFSoC ZU47DR 的九模式单载波通信工程，支持 P=2/4/8 与 BPSK、QPSK、16QAM。

{notice}

## 1. 内容与入口

- [工程源码、依赖与重建入口](AdaptiveX_Prj/README.md)：Vivado/Vitis 2021.2。
- [独立 Skill](skill/README.md)：资源基线、数值对照、依赖审查和发布工具。
- [源工程测试资料](AdaptiveX_Prj/results/system_examples/README.md)与[随包输入的验证记录](AdaptiveX_Prj/results/README.md)。

本代码包从同版完成态工程提取源输入、必要网表/初始化数据、软件及测试依赖，不包含综合/实现运行树与原生 IDE 工作区。请按重建入口创建新工程；直接打开完成态 XPR、使用已有 bit 的流程在完整工程包中提供。

## 2. 完整性检查

在本目录执行：

```bash
python3 AdaptiveX_Prj/tools/verify_package.py
python3 skill/sherl-github-project-publish/scripts/export_code.py verify --directory .
```

`SOURCE_EXPORT.json` 记录每个选中文件的来源、字节数与 SHA-256。计算代码保持原字节；本页、工程首页和文件清单按代码包入口生成。

## 3. 许可

项目自有内容采用 [MIT License](LICENSE)。第三方部分沿用[原始条款](AdaptiveX_Prj/THIRD_PARTY_NOTICES.md)。
'''

PROJECT_README = '''# AdaptiveX 工程源码与构建输入

基于 AMD RFSoC ZU47DR 的九模式单载波基带，采样率 4.9152 GSPS；P=2/4/8，对应 BPSK、QPSK、16QAM。

{notice}

## 1. 新建与构建

使用 Vivado/Vitis 2021.2、Python 3.10+。在本目录执行：

```bash
python3 tools/verify_package.py
python3 build/build.py tx --stage create --output validation/tx --vivado-root /path/to/Vivado/2021.2
python3 build/build.py rx --stage create --output validation/rx --vivado-root /path/to/Vivado/2021.2
```

使用 `--stage synth` 进行综合，`--stage bit` 完成综合、实现和导出。选择新的输出目录，不覆盖提交输入。

## 2. 源文件与验证

| 路径 | 用途 |
|---|---|
| `src`、`ip`、`build` | 集成 RTL、约束、BD/IP、预编译核和源重建入口 |
| `software/board` | PS 应用源码、链接脚本、匹配 XSA 与 Vitis 构建入口 |
| `software/matlab` | MATLAB 上位机 |
| `sim`、`data`、`matlab` | 测试台、固定输入/真值及数值核对 |
| `results`、`docs` | 对象与条件已标明的验证记录、工程说明和源工程展示资料 |
| `tools`、`MANIFEST.json` | 本代码包的文件清单和校验入口 |

配置与接口见[工程说明](docs/engineering.md)，仿真及 PS 构建入口见[使用与复现](docs/usage.md)，结果见[验证说明](docs/testing.md)。其中涉及已生成 XPR/bit/LTX/XSA 的操作适用于完整工程包；本代码包从上述 `build/build.py` 源重建入口开始。

[Skill](../skill/README.md)、[许可证](../LICENSE)和[第三方条款](THIRD_PARTY_NOTICES.md)随包保留。计算代码与完成态工程的对应源输入保持字节一致；根目录 `SOURCE_EXPORT.json` 记录选择与来源。
'''


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def metadata(path: Path) -> dict:
    return {'bytes': path.stat().st_size, 'sha256': sha(path)}


def skip(path: Path) -> bool:
    return bool(SKIP_PARTS.intersection(path.parts)) or path.suffix == '.pyc'


def selected_files(source: Path) -> list[Path]:
    selected = []
    for name in ROOT_FILES:
        selected.append(source / name)
    for name in PROJECT_FILES:
        selected.append(source / 'AdaptiveX_Prj' / name)
    for name in PROJECT_DIRS:
        directory = source / 'AdaptiveX_Prj' / name
        if not directory.is_dir():
            raise RuntimeError('Missing source directory: ' + str(directory))
        for path in directory.rglob('*'):
            if path.is_symlink():
                raise RuntimeError('Symlink input is not standalone: ' + str(path))
            if path.is_file():
                selected.append(path)
    for path in (source / 'skill').rglob('*'):
        if path.is_symlink():
            raise RuntimeError('Symlink Skill input is not standalone: ' + str(path))
        if path.is_file():
            selected.append(path)
    result = []
    for path in sorted(set(selected)):
        relative = path.relative_to(source)
        if skip(relative):
            continue
        if path.is_symlink() or not path.is_file():
            raise RuntimeError('Expected regular input: ' + str(relative))
        result.append(path)
    return result


def check_export(directory: Path) -> dict:
    receipt_file = directory / 'SOURCE_EXPORT.json'
    receipt = json.loads(receipt_file.read_text(encoding='utf-8'))
    entries = receipt['files']
    errors = []
    for name, item in entries.items():
        rel = Path(name)
        if rel.is_absolute() or '..' in rel.parts:
            raise RuntimeError('Unsafe receipt path: ' + name)
        path = directory / rel
        if not path.is_file() or path.is_symlink():
            errors.append('Missing/nonregular: ' + name)
        elif metadata(path) != {key: item[key] for key in ('bytes', 'sha256')}:
            errors.append('Changed: ' + name)
    for path in directory.rglob('*'):
        relative = path.relative_to(directory)
        if skip(relative) or not path.is_file():
            continue
        if relative.as_posix() not in entries and relative.as_posix() != 'SOURCE_EXPORT.json':
            errors.append('Unlisted: ' + relative.as_posix())
    summary = {'status': 'FAIL' if errors else 'PASS', 'files': len(entries),
               'copied': sum(item['kind'] == 'copied' for item in entries.values()),
               'generated': sum(item['kind'] == 'generated' for item in entries.values()),
               'bytes': sum(item['bytes'] for item in entries.values()), 'errors': errors}
    if errors:
        raise RuntimeError(json.dumps(summary, ensure_ascii=False))
    return summary


def export(source: Path, output: Path) -> dict:
    source, output = source.resolve(), output.resolve()
    if source == output or source in output.parents or output in source.parents:
        raise RuntimeError('Export directory must be outside and separate from source tree')
    if output.exists():
        raise RuntimeError('Output must be a new directory: ' + str(output))
    required_helper = source / 'skill/sherl-github-project-publish/scripts/export_code.py'
    if not required_helper.is_file():
        raise RuntimeError('Install this export helper in the supplied Skill before exporting')
    inputs = selected_files(source)
    before = {p.relative_to(source).as_posix(): metadata(p) for p in inputs}
    output.mkdir(parents=True)
    for path in inputs:
        target = output / path.relative_to(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    generated = {'README.md': ROOT_README.format(notice=NOTICE),
                 'AdaptiveX_Prj/README.md': PROJECT_README.format(notice=NOTICE)}
    for name, text in generated.items():
        (output / name).write_text(text, encoding='utf-8')
    manifest = output / 'AdaptiveX_Prj/MANIFEST.json'
    subprocess.run([sys.executable, str(output / 'AdaptiveX_Prj/tools/update_manifest.py'),
                    '--root', str(output / 'AdaptiveX_Prj')], check=True)
    subprocess.run([sys.executable, str(output / 'AdaptiveX_Prj/tools/verify_package.py'),
                    '--root', str(output / 'AdaptiveX_Prj')], check=True)
    entries = {}
    for name, item in before.items():
        copied = metadata(output / name)
        if name not in generated and copied != item:
            raise RuntimeError('Copy mismatch: ' + name)
        if metadata(source / name) != item:
            raise RuntimeError('Source changed during export: ' + name)
        entries[name] = {'kind': 'generated' if name in generated else 'copied',
                         'source': name, 'source_sha256': item['sha256'], **copied}
    entries['AdaptiveX_Prj/MANIFEST.json'] = {
        'kind': 'generated', 'source': 'AdaptiveX_Prj/MANIFEST.json',
        'source_sha256': sha(source / 'AdaptiveX_Prj/MANIFEST.json'), **metadata(manifest)}
    receipt = {'schema': 1, 'profile': 'source_inputs', 'source_label': 'AdaptiveX_Submission',
               'source_engineering_manifest_sha256': sha(source / 'AdaptiveX_Prj/MANIFEST.json'),
               'description': 'Selected same-version inputs and dependencies; generated entry pages and subset manifest.',
               'excluded_scope': ['completed Tx/Rx run trees', 'native IDE workspace', 'root report and media'],
               'files': entries}
    (output / 'SOURCE_EXPORT.json').write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return check_export(output)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    command = parser.add_subparsers(dest='command', required=True)
    make = command.add_parser('export')
    make.add_argument('--source', type=Path, required=True)
    make.add_argument('--output', type=Path, required=True)
    verify = command.add_parser('verify')
    verify.add_argument('--directory', type=Path, required=True)
    args = parser.parse_args()
    result = export(args.source, args.output) if args.command == 'export' else check_export(args.directory.resolve())
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    main()
