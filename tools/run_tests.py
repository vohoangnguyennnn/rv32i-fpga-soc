#!/usr/bin/env python3
import argparse, pathlib, subprocess, sys
root=pathlib.Path(__file__).resolve().parents[1]
core=(root/'files/core.f').read_text().split()
soc=['rtl/soc/rv32_uart.sv','rtl/soc/rv32_tcm.sv','rtl/soc/rv32_perf_mmio.sv','rtl/soc/rv32i_soc_top.sv']
common=['rtl/fpga/reset_sync.sv','rtl/fpga/fpga_top.sv','tb/common/rv32_tb_pkg.sv','tb/common/rv32_delayed_mem.sv','tb/common/rv32_pipeline_test.sv']
flags=['--binary','--timing','--assert','-Wall','-Wno-TIMESCALEMOD','-Wno-UNUSEDPARAM','-Wno-UNUSEDSIGNAL','-Wno-PINCONNECTEMPTY','-Wno-BLKSEQ']
def build(top):
    out=root/'build/sim'/top;out.mkdir(parents=True,exist_ok=True)
    tb=list(root.glob(f'tb/*/{top}.sv'))
    if not tb: raise RuntimeError(top)
    sources=core+soc+common+[str(tb[0].relative_to(root))]
    exe=out/f'V{top}'
    if exe.exists() and exe.stat().st_mtime>max((root/s).stat().st_mtime for s in sources):return exe
    with (out/'build.log').open('w') as log:
        code=subprocess.call(['verilator',*flags,'-j','4','--top-module',top,'--Mdir',str(out),*sources],cwd=root,stdout=log,stderr=subprocess.STDOUT)
    if code: raise RuntimeError((out/'build.log').read_text()[-6000:])
    return exe
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('suite',choices=['unit','integration','baremetal']);args=parser.parse_args()
    tests=sorted(root.glob(f'tb/{args.suite}/tb_*.sv')) if args.suite!='baremetal' else [root/'tb/integration/tb_baremetal.sv']
    tests=[f for f in tests if f.stem!='tb_baremetal'] if args.suite=='integration' else tests
    for f in tests:
        print('TEST',f.stem,flush=True)
        exe=build(f.stem)
        if args.suite!='baremetal': subprocess.run([str(exe)],cwd=root,check=True)
