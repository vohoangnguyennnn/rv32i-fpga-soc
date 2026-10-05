#!/usr/bin/env python3
import json,re
from run_benchmarks import run,table,root
rows=[]
for program in ['coremark_performance','coremark_validation']:
    full,log=run(program)
    words=list(map(int,re.search(r'COREMARK (.*)',log)[1].split()))
    cycle=words[5]+(words[6]<<32);inst=words[7]+(words[8]<<32)
    data=dict(full,ROI_cycles=cycle,ROI_instructions=inst,ROI_CPI=cycle/inst,ROI_IPC=inst/cycle,
        iterations=words[4],clock_hz=words[3],seedcrc=hex(words[9]),CRC_valid=bool(words[14]),errors=words[15])
    data['duration_seconds']=cycle/words[3]
    data['CoreMark_per_MHz']=words[4]*1000000/cycle if cycle>=10*words[3] and data['CRC_valid'] and words[15]==0 else None
    rows.append(data)
report='CoreMark: ROI uses high-low-high MMIO reads; sequential cycle/instret samples include measurement overhead.\n\n'+table(rows)
for r in rows:
    report+=f"\n{r['program']}: CRC_valid={r['CRC_valid']}, iterations={r['iterations']}, ROI cycles={r['ROI_cycles']}, instructions={r['ROI_instructions']}, CPI={r['ROI_CPI']:.4f}, IPC={r['ROI_IPC']:.4f}, CoreMark/MHz={r['CoreMark_per_MHz']}.\n"
report+='\nShort runs are functional validation only; no publishable CoreMark score.\n'
(root/'reports/coremark/results.md').write_text(report)
(root/'reports/coremark/results.json').write_text(json.dumps(rows,indent=2));print(report)
