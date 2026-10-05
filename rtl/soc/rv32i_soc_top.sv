// One clock domain, blocking data master, dual-port synchronous TCM.
module rv32i_soc_top #(
  parameter int unsigned TCM_BYTES = 65536,
  parameter string TCM_INIT_FILE = ""
)(
  input logic clk_i, rst_i,
  input logic uart_rx_i,
  output logic uart_tx_o,
  output logic done_o, pass_o, fail_o,
  output logic [63:0] perf_cycle_o, perf_instret_o, perf_load_use_stall_o,
                       perf_mem_stall_o, perf_redirect_o, perf_squash_o
);
  rv32_mem_if imem();
  rv32_mem_if dmem();
  rv32_mem_if ram_data();
  rv32_mem_if perf_data();
  rv32_mem_if uart_data();
  logic perf_select, uart_select;
  logic trace_valid, trace_fault;
  logic [31:0] trace_addr, trace_data;
  logic [3:0] trace_strobe;
  assign perf_select = dmem.req_addr[31:8] == 24'h100000;
  assign uart_select = dmem.req_addr[31:8] == 24'h100001;
  assign ram_data.req_valid = dmem.req_valid && !perf_select && !uart_select && !rst_i;
  assign uart_data.req_valid = dmem.req_valid && uart_select && !rst_i;
  assign uart_data.req_addr = dmem.req_addr;
  assign uart_data.req_write = dmem.req_write;
  assign uart_data.req_wdata = dmem.req_wdata;
  assign uart_data.req_wstrb = dmem.req_wstrb;
  assign perf_data.req_valid = dmem.req_valid && perf_select && !rst_i;
  assign ram_data.req_addr = dmem.req_addr;
  assign perf_data.req_addr = dmem.req_addr;
  assign ram_data.req_write = dmem.req_write;
  assign perf_data.req_write = dmem.req_write;
  assign ram_data.req_wdata = dmem.req_wdata;
  assign perf_data.req_wdata = dmem.req_wdata;
  assign ram_data.req_wstrb = dmem.req_wstrb;
  assign perf_data.req_wstrb = dmem.req_wstrb;
  assign dmem.req_ready = perf_select ? perf_data.req_ready
                       : uart_select ? uart_data.req_ready : ram_data.req_ready;
  // Return by response validity, never by the current request address.
  // The blocking LSU owns at most one outstanding data transaction. UART
  // backpressure holds its request until TX has capacity; responses are
  // selected by validity even if the request address has already changed.
  assign dmem.rsp_valid = ram_data.rsp_valid || perf_data.rsp_valid || uart_data.rsp_valid;
  assign dmem.rsp_err = perf_data.rsp_valid ? perf_data.rsp_err
                     : uart_data.rsp_valid ? uart_data.rsp_err : ram_data.rsp_err;
  assign dmem.rsp_rdata = perf_data.rsp_valid ? perf_data.rsp_rdata
                       : uart_data.rsp_valid ? uart_data.rsp_rdata : ram_data.rsp_rdata;
  rv32_uart #(.BASE_ADDR(32'h1000_0100), .CLK_FREQ_HZ(50_000_000), .BAUD_RATE(115_200)) u_uart (
    .clk_i(clk_i), .rst_i(rst_i), .uart_s(uart_data),
    .uart_rx_i(uart_rx_i), .uart_tx_o(uart_tx_o)
  );
  rv32_tcm #(.BYTES(TCM_BYTES), .INIT_FILE(TCM_INIT_FILE)) u_tcm (
    .clk_i(clk_i), .imem_s(imem), .dmem_s(ram_data)
  );
  rv32_perf_mmio u_perf (
    .clk_i(clk_i), .rst_i(rst_i), .cycle_i(perf_cycle_o), .instret_i(perf_instret_o),
    .load_use_i(perf_load_use_stall_o), .mem_stall_i(perf_mem_stall_o),
    .redirect_i(perf_redirect_o), .squash_i(perf_squash_o), .bus_s(perf_data)
  );
  rv32_core u_core (
    .clk_i(clk_i), .rst_i(rst_i), .imem_m(imem), .dmem_m(dmem),
    .trace_valid_o(trace_valid), .trace_pc_o(), .trace_insn_o(),
    .trace_rd_we_o(), .trace_rd_addr_o(), .trace_rd_data_o(),
    .trace_mem_addr_o(trace_addr), .trace_mem_wstrb_o(trace_strobe),
    .trace_mem_wdata_o(trace_data), .trace_trap_o(trace_fault), .trace_cause_o(),
    .trace_control_o(), .trace_taken_o(), .trace_target_o(),
    .perf_cycle_o(perf_cycle_o), .perf_instret_o(perf_instret_o),
    .perf_load_use_stall_o(perf_load_use_stall_o), .perf_mem_stall_o(perf_mem_stall_o),
    .perf_redirect_o(perf_redirect_o), .perf_squash_o(perf_squash_o)
  );
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      done_o <= 1'b0; pass_o <= 1'b0; fail_o <= 1'b0;
    end else if (!done_o && trace_valid) begin
      if (trace_fault) begin
        done_o <= 1'b1; fail_o <= 1'b1;
      end else if ((trace_addr == 32'(TCM_BYTES-4)) && (trace_strobe == 4'b1111) && trace_data[0]) begin
        done_o <= 1'b1;
        pass_o <= trace_data == 32'd1;
        fail_o <= trace_data != 32'd1;
      end
    end
  end
endmodule
