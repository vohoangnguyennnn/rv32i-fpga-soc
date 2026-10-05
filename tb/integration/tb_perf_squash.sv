// Two taken redirects discard PCs 0x1c/0x20 and 0x28/0x2c.
// Reuse the directed program and its checks for wrong-path side effects.
module tb_perf_squash;
  timeunit 1ns; timeprecision 1ps;
  rv32_pipeline_test test();
  logic [63:0] expected_squash;
  int redirects_seen;

  always @(posedge test.clk) begin
    if (test.rst) begin
      expected_squash = 64'd0;
      redirects_seen = 0;
    end else begin
      if (test.dut.perf_squash_o !== expected_squash)
        $fatal(1, "squash counter: expected %0d, got %0d",
               expected_squash, test.dut.perf_squash_o);
      if (test.dut.redirect_valid) begin
        // Each redirect has one valid ID packet and a distinct IF response.
        // Expected count comes from the known wrong-path PCs, not counter logic.
        if (!test.dut.if_id_q.valid || !test.imem.rsp_valid ||
            !test.dut.u_if_stage.request_sent_q || test.dut.u_if_stage.discard_q ||
            test.dut.u_if_stage.packet_valid_q ||
            test.dut.if_id_q.pc != (redirects_seen == 0 ? 32'h1c : 32'h28) ||
            test.dut.u_if_stage.request_pc_q != (redirects_seen == 0 ? 32'h20 : 32'h2c))
          $fatal(1, "squash regression did not reach the expected redirect window");
        redirects_seen++;
        expected_squash += 64'd2;
      end
    end
  end

  // Check after the counter's NBA update, before the shared program finishes.
  always @(negedge test.clk) if (!test.rst) begin
    if (test.dut.perf_squash_o !== expected_squash)
      $fatal(1, "squash counter post-edge mismatch");
    if (redirects_seen == 2 && expected_squash == 64'd4)
      if (test.valid && test.strb == 4'hf && test.addr == 32'h408)
        $display("PASS: perf_squash = 4 for two redirects; wrong-path packets counted once");
  end
endmodule
