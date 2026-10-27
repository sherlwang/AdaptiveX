#!/usr/bin/env python3
"""Refresh the engineering inventory after an intentional, reviewed update."""
from pathlib import Path
import argparse
import json
from manifest_rules import file_digest, inventory_files

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path, help='Default: ROOT/MANIFEST.json')
    args = parser.parse_args()
    root = args.root.resolve()
    completed = [(root / name / 'project' / (name.lower() + '.xpr')).is_file()
                 for name in ('Tx', 'Rx')]
    if any(completed) and not all(completed):
        raise RuntimeError('The completed-project package requires both Tx and Rx XPR files')
    files = {
        relative: {'bytes': path.stat().st_size, 'sha256': file_digest(path)}
        for path, relative in inventory_files(root)
    }
    book = {
        'format': 2,
        'scope': 'completed_projects_and_rebuild_inputs' if all(completed) else 'rebuild_inputs',
        'configuration': {'receiver_sampling_phase': 0},
        'excluded_runtime_files': {
            'directories': ['.git', 'validation', '__pycache__', '.Xil', '*.cache'],
            'suffixes': ['.pyc', '.log', '.jou'],
        },
        'files': dict(sorted(files.items())),
    }
    output = args.output or root / 'MANIFEST.json'
    output.write_text(json.dumps(book, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({'status': 'PASS', 'manifest': str(output), 'files': len(files),
                      'bytes': sum(item['bytes'] for item in files.values()), 'scope': book['scope']}))


if __name__ == '__main__':
    main()
