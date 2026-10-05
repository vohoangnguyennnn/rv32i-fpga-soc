set root [file normalize [file join [file dirname [info script]] ../..]]
cd $root
file mkdir reports/vivado
create_project -force rv32i_coursework build/vivado -part xc7a35tfgg484-2
set f [open files/fpga.f r]
foreach source [split [read $f] \n] {
  if {[string trim $source] ne ""} { read_verilog -sv $source }
}
close $f
read_xdc constraint/main.xdc
set_property top fpga_top [current_fileset]
set image [file normalize build/sw/sort_uart.mem]
set_property generic "TCM_INIT_FILE=$image" [current_fileset]
synth_design -top fpga_top -part xc7a35tfgg484-2
report_utilization -hierarchical -file reports/vivado/synth_utilization.rpt
opt_design
place_design
phys_opt_design
route_design
report_utilization -file reports/vivado/utilization.rpt
report_utilization -hierarchical -file reports/vivado/hierarchy.rpt
report_timing_summary -delay_type min_max -report_unconstrained -file reports/vivado/timing.rpt
report_drc -file reports/vivado/drc.rpt
write_checkpoint -force build/rv32i_sort_routed.dcp
write_bitstream -force build/rv32i_sort.bit
