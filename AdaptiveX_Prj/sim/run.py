#!/usr/bin/env python3
"""Run the delivered functional netlists with Vivado 2021.2 XSim."""
from pathlib import Path
import argparse,hashlib,json,os,re,shutil,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'build'))
from materialize import materialize

def run(command,out,label):
 with (out/(label+'.log')).open('w') as log:
  p=subprocess.run([str(x) for x in command],cwd=out,stdout=log,stderr=subprocess.STDOUT)
 text=(out/(label+'.log')).read_text(errors='replace')
 if p.returncode or '\nERROR:' in text or '\nFatal:' in text:
  raise RuntimeError(label+' failed. See '+str(out/(label+'.log')))
 return text

def _compare_bits(out):
 reference={k:[int(s,16) for s in (ROOT/'data'/(k+'_expected.mem')).read_text().split()] for k in ('coded','decoded')}
 result={}
 for kind in reference:
  got=[];widths=[];tags=[]
  for line in (out/(kind+'.txt')).read_text().splitlines():
   fields=line.split()
   if len(fields)!=(5 if kind=='coded' else 2) or re.fullmatch(r'[0-9a-fA-F]{8}',fields[-1]) is None:
    raise RuntimeError(kind+' valid output is malformed or contains X/Z')
   width=int(fields[2] if kind=='coded' else fields[0]);widths.append(width);got.append(int(fields[-1],16))
   if kind=='coded':tags.append(tuple(map(int,fields[:4])))
  expected=reference[kind]
  if len(got)!=len(expected):raise RuntimeError(kind+' output length mismatch: '+str(len(got))+' vs '+str(len(expected)))
  if any(x!=2 for x in widths):raise RuntimeError('Fixture requires width 2, received another mode')
  if kind=='coded':
   expected_tags=[(frame,block,2,int(row==0)) for frame in range(16) for block in range(6) for row in range(255)]
   if tags!=expected_tags:raise RuntimeError('Coded frame/block/start ordering differs from the fixture')
  errors=sum(((a^b)&3).bit_count() for a,b in zip(got,expected))
  result[kind]={'bits':len(got)*2,'bit_errors':errors,'ber':errors/(len(got)*2)}
 counts=json.loads((out/'counts.json').read_text())
 events=[line.split() for line in (out/'events.txt').read_text().splitlines()]
 frames=[int(row[2]) for row in events if row[1]=='FRAME']
 recommendations=[int(row[2]) for row in events if row[1]=='RECOMMEND']
 if len(recommendations)!=counts['ai_recommendations'] or any(x not in range(9) for x in recommendations):
  raise RuntimeError('AI recommendation event count/range mismatch')
 if frames!=list(range(16)):raise RuntimeError('Frame event sequence is incomplete')
 for stage in ('window','fde','nlms'):
  stage_rows=[line.split() for line in (out/(stage+'.txt')).read_text().splitlines()]
  expected_per_frame=2048 if stage=='window' else 1530
  if len(stage_rows)!=16*expected_per_frame:raise RuntimeError(stage+' stage output length mismatch')
  if any(len(row)!=4 or any(re.fullmatch(r'[0-9a-fA-F]{32}',field) is None for field in row[2:]) for row in stage_rows):
   raise RuntimeError(stage+' valid I/Q output is malformed or contains X/Z')
  if any(int(row[0])!=i//expected_per_frame or int(row[1])!=2 for i,row in enumerate(stage_rows)):
   raise RuntimeError(stage+' frame/P tags differ from the P2 fixture')
 result['counts']=counts
 errors=('overflow_fast','overflow_ldpc','ldpc_mode_error','acquire_error')
 result['mode_evidence']='Aligned algorithm-stage P tags are 2 and coded/decoded widths are 2 (BPSK). Raw detected-M VIO sampling is not independently logged.'
 result['status']='PASS' if result['decoded']['bit_errors']==0 and counts['frames']==16 and counts['ldpc_blocks']==96 and counts['ldpc_failed_checks']==0 and counts['ai_recommendations']>0 and all(counts[k]==0 for k in errors) else 'FAIL'
 (out/'bit_results.json').write_text(json.dumps(result,indent=2)+'\n')
 if result['status']!='PASS':raise RuntimeError('RX output differs from MATLAB truth; see bit_results.json')
 return result

def compare_bits(out):
 result_path=out/'bit_results.json'
 result_path.write_text(json.dumps({'status':'CHECKING'},indent=2)+'\n')
 try:
  return _compare_bits(out)
 except Exception as error:
  result_path.write_text(json.dumps({'status':'FAIL','error':str(error)},indent=2)+'\n')
  raise

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('case',choices=['codec','rrc','rx_link']);p.add_argument('--output',required=True,type=Path);p.add_argument('--vivado-root',type=Path);p.add_argument('--adc-file',type=Path);p.add_argument('--check-only',action='store_true',help='Recheck existing rx_link output without running a simulator');a=p.parse_args()
 out=a.output.resolve()
 if a.check_only:
  if a.case!='rx_link':p.error('--check-only is only available for rx_link')
  print(json.dumps(compare_bits(out),indent=2));return
 if a.vivado_root is None:p.error('--vivado-root is required to run a simulation')
 if a.adc_file is not None and a.case!='rx_link':p.error('--adc-file is only available for rx_link')
 if out.exists() and any(out.iterdir()):raise RuntimeError('Use a new or empty simulation output directory')
 out.mkdir(parents=True,exist_ok=True)
 v=a.vivado_root.resolve();exe=lambda x:v/'bin'/(x+'.bat' if os.name=='nt' else x)
 for n in ('xvlog','xvhdl','xelab','xsim'):
  if not exe(n).is_file():raise RuntimeError('Missing tool: '+str(exe(n)))
 # XSim 2021.2 prints its version but exits 1 for -version; -help exits 0.
 version=run([exe('xsim'),'-help'],out,'tool_version')
 if re.search(r'\bv2021\.2\b',version) is None:raise RuntimeError('The delivered models require Vivado/XSim 2021.2')
 started=time.time();result={'case':a.case,'status':'RUNNING','implementation':'delivered structural functional netlists'}
 (out/'execution.json').write_text(json.dumps(result,indent=2)+'\n')
 try:
  files=[];vhdl=[];includes=[]
  if a.case=='rrc':
   cache=out/'cores_tx';materialize(cache,'tx');files.append(cache/'tx/RRC_Shared/core_sim.v')
   for f in (ROOT/'data/rrc').glob('*.mem'):shutil.copy2(f,out/f.name)
   top='tb_rrc'
  elif a.case=='codec':
   for side,core in [('tx','ldpc_encoder'),('rx','ldpc_decoder')]:
    cache=out/('cores_'+side);materialize(cache,side);files.append(cache/side/core/'core_sim.v')
   for f in (ROOT/'data/codec').glob('*.mem'):shutil.copy2(f,out/f.name)
   top='tb_codec'
  else:
   materialize(out/'cores','rx')
   files.extend(sorted((out/'cores/rx').glob('*/core_sim.v')))
   src=ROOT/'src/rx/sources_1'
   files.extend(sorted(src.rglob('*.v')))
   includes.append(src/'ldpc')
   for f in src.rglob('*.mem'):
    dest=out/f.name
    if dest.exists() and dest.read_bytes()!=f.read_bytes():raise RuntimeError('Conflicting ROM name '+f.name)
    shutil.copy2(f,dest)
   vhdl=sorted((ROOT/'sim/vendor_models').glob('*.vhd'))
   adc=(a.adc_file or ROOT/'data/adc_input.mem').resolve()
   raw=adc.read_bytes();words=raw.decode('ascii').split()
   if not 1<=len(words)<=131072 or any(re.fullmatch(r'[0-9a-fA-F]{48}',word) is None for word in words):
    raise RuntimeError('ADC input must contain 1..131072 words of 48 hexadecimal digits')
   shutil.copy2(adc,out/'adc_input.mem')
   result['adc']={'file':adc.name,'words':len(words),'sha256':hashlib.sha256(raw).hexdigest()}
   top='tb_rx_link'
  files.extend([ROOT/'sim'/(top+'.sv'),v/'data/verilog/src/glbl.v'])
  if vhdl:run([exe('xvhdl')]+vhdl,out,'xvhdl')
  include_args=sum((['-i',x] for x in includes if x.is_dir()),[])
  run([exe('xvlog'),'--sv']+include_args+files,out,'xvlog')
  libs=['xpm','unisims_ver','cordic_v6_0_17','mult_gen_v12_0_17']
  run([exe('xelab'),top,'glbl']+sum((['-L',x] for x in libs),[])+['-s',a.case],out,'xelab')
  if 'WARNING: [VRFC 10-3091]' in (out/'xelab.log').read_text(errors='replace'):
   raise RuntimeError('Port width mismatch during elaboration; rejecting simulation model binding')
  plusargs=['-testplusarg','WORDS='+str(len(words))] if a.case=='rx_link' else []
  simlog=run([exe('xsim'),a.case]+plusargs+['-runall','-log',str(out/'kernel.log')],out,'simulate')
  marker={'codec':'CODEC_ALL_PASS','rrc':'RRC_ALL_PASS','rx_link':'RX_EXECUTION_COMPLETE'}[a.case]
  if marker not in simlog:raise RuntimeError('Simulation terminated before completion')
  details=json.loads((out/(a.case+'_result.json')).read_text()) if a.case in ('codec','rrc') else compare_bits(out)
  result.update(status='PASS',details=details)
 except Exception as e:
  result.update(status='FAIL',error=str(e));raise
 finally:
  result['elapsed_seconds']=round(time.time()-started,2)
  (out/'execution.json').write_text(json.dumps(result,indent=2)+'\n')
  print(json.dumps(result,indent=2))
if __name__=='__main__':main()
