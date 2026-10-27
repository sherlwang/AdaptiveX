#!/usr/bin/env python3
"""Expand and verify the fixed-configuration core files. Python standard library only."""
from pathlib import Path
import argparse,gzip,hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[1]
def sha(data):return hashlib.sha256(data).hexdigest()
def materialize(output,side):
 out=Path(output).resolve()
 if out.exists() and any(out.iterdir()):raise RuntimeError('Use a new or empty core output directory: '+str(out))
 out.mkdir(parents=True,exist_ok=True)
 count=0
 for manifest in sorted((ROOT/'ip'/side).glob('*/core.json')):
  core=json.loads(manifest.read_text());dest=out/side/manifest.parent.name;dest.mkdir(parents=True)
  for name,spec in core['files'].items():
   data=(manifest.parent/spec['path']).read_bytes()
   if sha(data)!=spec['sha256']:raise RuntimeError('Compressed core hash mismatch: '+str(manifest))
   raw=gzip.decompress(data) if spec['path'].endswith('.gz') else data
   if len(raw)!=spec['raw_bytes'] or sha(raw)!=spec['raw_sha256']:raise RuntimeError('Expanded core hash mismatch: '+str(manifest))
   (dest/name).write_bytes(raw)
  count+=1
 if not count:raise RuntimeError('No delivered cores for '+side)
 return count
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('side',choices=['tx','rx']);p.add_argument('--output',required=True,type=Path);a=p.parse_args()
 print('Verified and expanded',materialize(a.output,a.side),'cores')
