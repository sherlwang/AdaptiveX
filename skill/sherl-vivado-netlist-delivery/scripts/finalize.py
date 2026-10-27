#!/usr/bin/env python3
"""Package Vivado-generated structural outputs; never collect source RTL."""
from pathlib import Path
import argparse,gzip,hashlib,json,re

def sha(data):return hashlib.sha256(data).hexdigest()
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',required=True,type=Path)
    p.add_argument('--output',required=True,type=Path)
    p.add_argument('--top',required=True)
    p.add_argument('--part',required=True)
    p.add_argument('--parameters',default='{}')
    a=p.parse_args()
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_$]*',a.top):raise ValueError('Use a Verilog module identifier')
    parameters=json.loads(a.parameters)
    if not isinstance(parameters,dict):raise ValueError('Parameters must be a JSON object')
    src=a.source.resolve();out=a.output.resolve()
    if src==out or src in out.parents or out in src.parents:raise ValueError('Keep export and payload directories separate')
    if out.exists() and any(out.iterdir()):raise ValueError('Output directory must be new or empty')
    required=['core.edf','core_stub.v','core_sim.v','utilization.rpt']
    text={n:(src/n).read_text(encoding='utf-8') for n in required}
    sim=text['core_sim.v']
    if 'NotValidForBitStream' not in sim or not re.search(r'\bmodule\s+'+re.escape(a.top)+r'\b',sim):raise ValueError('Expected the generated functional netlist for the selected top')
    if re.search(r'`pragma\s+protect|pragma\s+protect',sim,re.I):raise ValueError('Protected vendor blocks require their supported delivery flow; no rewriting is attempted')
    local=[n for n in re.findall(r'(?m)^module\s+([A-Za-z_][A-Za-z0-9_$]*)',sim) if n not in (a.top,'glbl')]
    prefix=a.top+'__local__'
    for name in sorted(local,key=len,reverse=True):
        sim=re.sub(r'\b'+re.escape(name)+r'\b',lambda _:prefix+name,sim)
    text['core_sim.v']=sim
    out.mkdir(parents=True,exist_ok=True)
    info={'name':a.top,'part':a.part,'generic':parameters,'files':{},'namespaced_structural_helpers':local,'simulation_helper_namespace':prefix}
    for name,body in text.items():
        body=re.sub(r'(?m)^// (Host|Command|Date)\s*:.*\n','',body)
        if str(src) in body:raise ValueError('Private export path remains in generated content: '+name)
        raw=body.encode('utf-8')
        filename=name+'.gz' if name in ('core.edf','core_sim.v') else name
        packed=gzip.compress(raw,compresslevel=9,mtime=0) if filename.endswith('.gz') else raw
        (out/filename).write_bytes(packed)
        if name!='utilization.rpt':info['files'][name]={'path':filename,'sha256':sha(packed),'raw_sha256':sha(raw),'raw_bytes':len(raw)}
    (out/'core.json').write_text(json.dumps(info,indent=2)+'\n')
    print(json.dumps({'top':a.top,'payload':str(out),'local_helpers':len(local),'files':len(required)+1}))
if __name__=='__main__':main()
