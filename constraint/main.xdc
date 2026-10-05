
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]


set_property -dict {PACKAGE_PIN J19 IOSTANDARD LVCMOS33} [get_ports {clk_50m_i}]


set_property -dict {PACKAGE_PIN L18 IOSTANDARD LVCMOS33} [get_ports {reset_ni}]
set_false_path -from [get_ports {reset_ni}]

set_property -dict {PACKAGE_PIN AA1 IOSTANDARD LVCMOS33} [get_ports {user_reset_ni}]
set_false_path -from [get_ports {user_reset_ni}]






set_property -dict {PACKAGE_PIN M18 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} \
  [get_ports {led1_n_o}]
set_property -dict {PACKAGE_PIN N18 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} \
  [get_ports {led2_n_o}]

set_property -dict {PACKAGE_PIN W21 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} \
  [get_ports {fail_o}]
set_property -dict {PACKAGE_PIN W22 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} \
  [get_ports {done_o}]


set_false_path -to [get_ports {led1_n_o}]
set_false_path -to [get_ports {led2_n_o}]
set_false_path -to [get_ports {fail_o}]
set_false_path -to [get_ports {done_o}]
# On-board CH340 USB-UART: FPGA TX -> CH340 RX, CH340 TX -> FPGA RX.
# Pin mapping inherited from the original A7-Lite board constraints.
set_property -dict {PACKAGE_PIN V2 IOSTANDARD LVCMOS33} [get_ports {uart_tx_o}]
set_property -dict {PACKAGE_PIN U2 IOSTANDARD LVCMOS33} [get_ports {uart_rx_i}]
# RX enters the UART's two-flop synchronizer. Serial I/O is asynchronous
# to the external terminal; internal synchronous timing remains constrained.
set_false_path -from [get_ports {uart_rx_i}]
set_false_path -to [get_ports {uart_tx_o}]
create_clock -name clk_50m -period 20.000 [get_ports clk_50m_i]
