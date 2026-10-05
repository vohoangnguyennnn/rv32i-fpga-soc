PYTHON ?= python3
COREMARK_ITERATIONS ?= 1
.PHONY: lint unit integration test software sort benchmark coremark fpga fpga-reports bitstream clean
lint:
	verilator --lint-only -Wall -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PINCONNECTEMPTY --top-module fpga_top -f files/fpga.f
integration: software
unit integration:
	$(PYTHON) tools/run_tests.py $@
test: lint unit integration sort
software:
	$(MAKE) -C sw all
sort: software
	$(PYTHON) tools/run_benchmarks.py --program arithmetic_demo --program sort
benchmark: software
	$(PYTHON) tools/run_benchmarks.py
coremark:
	$(MAKE) -C sw coremark-images COREMARK_ITERATIONS=$(COREMARK_ITERATIONS)
	$(PYTHON) tools/run_coremark.py
fpga fpga-reports bitstream: software
	vivado -mode batch -source scripts/vivado/build.tcl -log build/vivado.log -journal build/vivado.jou
clean:
	rm -rf build
