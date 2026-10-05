#!/usr/bin/env python3
import argparse,json,pathlib,re,subprocess
from run_tests import build,root

def run(program):
    exe=build('tb_baremetal')
    result=subprocess.run([str(exe),f'+mem={root}/build/sw/{program}.mem'],cwd=root,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    out=root/'reports/performance';out.mkdir(parents=True,exist_ok=True)
    (out/f'{program}.log').write_text(result.stdout)
    if result.returncode: raise RuntimeError(result.stdout[-3000:])
    m=re.search(r'PERF (.*)',result.stdout)
    if not m:raise RuntimeError('Missing performance report')
    data={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',m[1])}
    data['program']=program;data['CPI']=data['cycles']/data['instructions'];data['IPC']=data['instructions']/data['cycles']
    return data,result.stdout

def table(rows):
    out='| Benchmark | Instructions | Cycles | CPI | IPC | Load-use | Memory stall | Redirects | Squashed |\n|---|---:|---:|---:|---:|---:|---:|---:|---:|\n'
    for r in rows:
        out+=f"| {r['program']} | {r['instructions']} | {r['cycles']} | {r['CPI']:.4f} | {r['IPC']:.4f} | {r['load_use']} | {r['memory_stall']} | {r['redirects']} | {r['squashed']} |\n"
    return out
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--program',action='append');args=parser.parse_args()
    rows=[run(p)[0] for p in args.program or ['bench_arithmetic','bench_branch','bench_memory','sort']]
    total={k:sum(r[k] for r in rows) for k in ['cycles','instructions','load_use','memory_stall','redirects','squashed']}
    total.update(program='Aggregate',CPI=total['cycles']/total['instructions'],IPC=total['instructions']/total['cycles'])
    report=table(rows+[total]);print(report)
    (root/'reports/performance/benchmarks.md').write_text('Full-program: reset release through WB completion store (inclusive).\n\n'+report)
    (root/'reports/performance/benchmarks.json').write_text(json.dumps(rows+[total],indent=2))
