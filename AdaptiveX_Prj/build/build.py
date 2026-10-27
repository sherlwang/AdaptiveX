#!/usr/bin/env python3
"""Build the public project without external project files, caches or checkpoints."""
from pathlib import Path
import argparse,json,os,re,shutil,subprocess,time
from materialize import materialize
ROOT=Path(__file__).resolve().parents[1]
def find_vivado(root):
 name='vivado.bat' if os.name=='nt' else 'vivado'
 p=Path(root)/'bin'/name if root else shutil.which(name)
 if not p or not Path(p).is_file():raise RuntimeError('Vivado not found; provide --vivado-root for Vivado 2021.2')
 version=subprocess.run([str(p),'-version'],capture_output=True,text=True)
 if version.returncode or re.search(r'Vivado\s+v\.?2021\.2\b',version.stdout) is None:
  raise RuntimeError('This delivered netlist package requires Vivado 2021.2; no IP upgrade was attempted')
 return str(p)
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('side',choices=['tx','rx']);p.add_argument('--stage',choices=['create','synth','bit'],default='create');p.add_argument('--output',required=True,type=Path);p.add_argument('--vivado-root',type=Path);a=p.parse_args()
 out=a.output.resolve()
 if out.exists() and any(out.iterdir()):raise RuntimeError('Use a new or empty build directory: '+str(out))
 out.mkdir(parents=True,exist_ok=True);count=materialize(out/'cores',a.side)
 exe=find_vivado(a.vivado_root);env=os.environ.copy();env.setdefault('LANG','en_US.UTF-8');env.setdefault('LC_ALL','en_US.UTF-8')
 result={'side':a.side,'stage':a.stage,'delivered_cores':count,'status':'RUNNING','started_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())}
 (out/'build_result.json').write_text(json.dumps(result,indent=2)+'\n')
 command=[exe,'-mode','batch','-source',str(ROOT/'build'/('recreate_'+a.side+'.tcl')),'-log',str(out/'vivado.log'),'-nojournal','-tclargs',str(out/'project'),a.stage,str(out/'cores')]
 with (out/'console.log').open('w') as f:r=subprocess.run(command,cwd=out,env=env,stdout=f,stderr=subprocess.STDOUT)
 log=(out/'console.log').read_text(errors='replace')
 expected=(out/'project'/('input_files.txt' if a.stage=='create' else 'BUILD_COMPLETE.txt'))
 result.update(exit_code=r.returncode,status='PASS' if r.returncode==0 and expected.is_file() and '\nERROR:' not in log else 'FAIL',finished_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()))
 (out/'build_result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2));print('Log:',out/'console.log')
 if result['status']!='PASS':raise SystemExit(1)
if __name__=='__main__':main()
