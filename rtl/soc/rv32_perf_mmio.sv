// Read-only counters, fixed one-cycle response; writes/unmapped offsets error.
module rv32_perf_mmio (
  input logic clk_i, rst_i,
  input logic [63:0] cycle_i, instret_i, load_use_i, mem_stall_i, redirect_i, squash_i,
  rv32_mem_if.slave bus_s
);
  logic [31:0] data;
  logic mapped;
  assign bus_s.req_ready = !rst_i;
  always_comb begin
    data = 32'b0;
    mapped = 1'b1;
    case (bus_s.req_addr)
      32'h10000000: data = cycle_i[31:0];
      32'h10000004: data = cycle_i[63:32];
      32'h10000008: data = instret_i[31:0];
      32'h1000000c: data = instret_i[63:32];
      32'h10000010: data = load_use_i[31:0];
      32'h10000014: data = mem_stall_i[31:0];
      32'h10000018: data = redirect_i[31:0];
      32'h1000001c: data = squash_i[31:0];
      default: mapped = 1'b0;
    endcase
  end
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      bus_s.rsp_valid <= 1'b0;
      bus_s.rsp_err <= 1'b0;
      bus_s.rsp_rdata <= 32'b0;
    end else begin
      bus_s.rsp_valid <= bus_s.req_valid && bus_s.req_ready;
      bus_s.rsp_err <= bus_s.req_write || !mapped;
      bus_s.rsp_rdata <= data;
    end
  end
endmodule
