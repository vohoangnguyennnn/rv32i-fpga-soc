module tb_baremetal;
  timeunit 1ns; timeprecision 1ps;
  logic clk, rst, done, pass, fail;
  logic [63:0] cycles, instructions, load_use, memory_stall, redirects, squashed;
  string image;
  int unsigned limit;
  rv32i_soc_top dut(.clk_i(clk),.rst_i(rst),.done_o(done),.pass_o(pass),.fail_o(fail),
    .uart_rx_i(1'b1), .uart_tx_o(),
    .perf_cycle_o(cycles),.perf_instret_o(instructions),.perf_load_use_stall_o(load_use),
    .perf_mem_stall_o(memory_stall),.perf_redirect_o(redirects),.perf_squash_o(squashed));
  always #5 clk=~clk;
  initial begin
    clk=0;rst=1;limit=2000000000;
    if (!$value$plusargs("mem=%s",image)) $fatal(1,"missing +mem");
    if ($value$plusargs("max_cycles=%d",limit)) begin end
    $readmemh(image,dut.u_tcm.mem);
    repeat(5) @(negedge clk); rst=0;
  end
  // Observe the retirement boundary before NBA, adding exactly this edge's completion retirement.
  always @(posedge clk) if(!rst) begin
    if(cycles >= 64'(limit)) $fatal(1,"timeout");
    if(dut.trace_valid && dut.trace_fault) $fatal(1,"CPU fault pc=%h cause=%d",dut.u_core.trace_pc_o,dut.u_core.trace_cause_o);
    if(dut.trace_valid && !dut.trace_fault && dut.trace_addr==32'hfffc && dut.trace_strobe==4'hf && dut.trace_data[0]) begin
      $display("PERF cycles=%0d instructions=%0d load_use=%0d memory_stall=%0d redirects=%0d squashed=%0d",
        cycles+64'd1,instructions+64'd1,load_use,memory_stall,redirects,squashed);
      if(dut.u_tcm.mem[32'he000/4]==32'h434d524b) begin
        $write("COREMARK");
        for(int k=0;k<16;k++) $write(" %0d",dut.u_tcm.mem[32'he000/4+k]);
        $write("\n");
      end
      if(dut.trace_data!=1) $fatal(1,"software FAIL status=%h",dut.trace_data);
      $display("PASS: baremetal %s",image); $finish;
    end
  end
endmodule
