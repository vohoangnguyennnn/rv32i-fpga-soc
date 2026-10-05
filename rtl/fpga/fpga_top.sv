// A7-Lite: direct 50 MHz clock, asynchronous assertion/synchronous reset release.
module fpga_top #(parameter string TCM_INIT_FILE = "") (
  input logic clk_50m_i, reset_ni, user_reset_ni,
  input logic uart_rx_i,
  output logic uart_tx_o,
  output logic led1_n_o, led2_n_o, fail_o, done_o
);
  logic rst, pass;
  reset_sync u_reset_sync (.clk_i(clk_50m_i), .arst_ni(reset_ni && user_reset_ni), .rst_o(rst));
  rv32i_soc_top #(.TCM_INIT_FILE(TCM_INIT_FILE)) u_soc (
    .clk_i(clk_50m_i), .rst_i(rst), .done_o(done_o), .pass_o(pass), .fail_o(fail_o),
    .uart_rx_i(uart_rx_i), .uart_tx_o(uart_tx_o),
    .perf_cycle_o(), .perf_instret_o(), .perf_load_use_stall_o(),
    .perf_mem_stall_o(), .perf_redirect_o(), .perf_squash_o()
  );
  assign led1_n_o = !done_o;
  assign led2_n_o = !pass;
endmodule
