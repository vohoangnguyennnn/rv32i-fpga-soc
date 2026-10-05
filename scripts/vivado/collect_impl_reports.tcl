# Source after an implemented design is open.
file mkdir reports/vivado
report_utilization -file reports/vivado/utilization.rpt
report_utilization -hierarchical -file reports/vivado/hierarchy.rpt
report_timing_summary -delay_type min_max -report_unconstrained -file reports/vivado/timing.rpt
report_drc -file reports/vivado/drc.rpt
