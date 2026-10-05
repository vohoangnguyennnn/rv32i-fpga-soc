// Interactive end-to-end test through physical RX/TX pins and FPGA TCM INIT.
module tb_sort_uart;
  timeunit 1ns; timeprecision 1ps;
  localparam int CLKS_PER_BIT = 434;
  localparam time BIT_TIME = 8680ns;
  localparam string BANNER = {"RV32I SORT\r\n",
    "Enter 1..32 int32 values separated by spaces; press Enter.\r\nREADY\r\n"};
  logic clk, reset_n, user_reset_n, rx, tx, led_done_n, led_pass_n, fail, done;
  int received;
  string expected;
  logic outstanding, held, saw_uart_wait;
  logic [68:0] held_payload;
  logic req_fire, rsp_fire;
  logic [68:0] request_payload;

  fpga_top #(.TCM_INIT_FILE("build/sw/sort_uart.mem")) dut (
    .clk_50m_i(clk), .reset_ni(reset_n), .user_reset_ni(user_reset_n),
    .uart_rx_i(rx), .uart_tx_o(tx), .led1_n_o(led_done_n),
    .led2_n_o(led_pass_n), .fail_o(fail), .done_o(done)
  );
  always #10 clk = ~clk;
  assign req_fire = dut.u_soc.dmem.req_valid && dut.u_soc.dmem.req_ready;
  assign rsp_fire = dut.u_soc.dmem.rsp_valid;
  assign request_payload = {dut.u_soc.dmem.req_addr, dut.u_soc.dmem.req_write,
                            dut.u_soc.dmem.req_wdata, dut.u_soc.dmem.req_wstrb};

  // Verify single ownership and stable requests during UART backpressure.
  always @(posedge clk) begin
    if (dut.rst) begin
      outstanding = 1'b0;
      saw_uart_wait = 1'b0;
      held = 1'b0;
      held_payload = '0;
    end else begin
      if (!$onehot0({dut.u_soc.ram_data.req_valid, dut.u_soc.perf_data.req_valid,
                     dut.u_soc.uart_data.req_valid}) ||
          !$onehot0({dut.u_soc.ram_data.rsp_valid, dut.u_soc.perf_data.rsp_valid,
                     dut.u_soc.uart_data.rsp_valid}))
        $fatal(1, "multiple bus targets active");
      if (held && (!dut.u_soc.dmem.req_valid || request_payload !== held_payload))
        $fatal(1, "UART backpressure changed request payload");
      if (rsp_fire && !outstanding) $fatal(1, "unsolicited data response");
      if (req_fire && outstanding && !rsp_fire) $fatal(1, "multiple outstanding requests");
      if (rsp_fire) outstanding = 1'b0;
      if (req_fire) outstanding = 1'b1;
      held = dut.u_soc.dmem.req_valid && !dut.u_soc.dmem.req_ready;
      held_payload = request_payload;
      if (dut.u_soc.uart_data.req_valid && !dut.u_soc.uart_data.req_ready)
        saw_uart_wait = 1'b1;
      if (dut.u_soc.trace_valid && dut.u_soc.trace_fault) $fatal(1, "CPU fault");
    end
  end

  // Decode external TX, independent of the CPU's register or memory values.
  initial begin : receiver
    logic [7:0] ch;
    forever begin
      @(negedge tx);
      repeat(CLKS_PER_BIT/2) @(posedge clk);
      #1;
      if (tx !== 1'b0) $fatal(1, "invalid UART start bit");
      for (int bit_index = 0; bit_index < 8; bit_index++) begin
        repeat(CLKS_PER_BIT) @(posedge clk);
        #1; ch[bit_index] = tx;
      end
      repeat(CLKS_PER_BIT) @(posedge clk);
      #1;
      if (tx !== 1'b1) $fatal(1, "invalid UART stop bit");
      if (received >= expected.len() || ch !== expected[received])
        $fatal(1, "UART byte %0d: got %h expected %h", received, ch, expected[received]);
      received++;
      $write("%c", ch);
    end
  end

  // Back-to-back frames model a pasted line, asynchronous to the FPGA clock.
  task automatic send_byte(input logic [7:0] ch, input logic stop_bit = 1'b1);
    rx = 1'b0; #(BIT_TIME);
    for (int bit_index = 0; bit_index < 8; bit_index++) begin
      rx = ch[bit_index]; #(BIT_TIME);
    end
    rx = stop_bit; #(BIT_TIME);
  endtask

  task automatic send_line(input string text);
    #3ns;
    for (int k = 0; k < text.len(); k++) send_byte(text[k]);
  endtask

  task automatic wait_output;
    while (received < expected.len()) @(negedge clk);
    repeat(CLKS_PER_BIT) @(negedge clk); // Final stop bit and polling restart.
    if (received != expected.len() || tx !== 1'b1 || fail)
      $fatal(1, "unexpected terminal output or CPU fail");
  endtask

  task automatic exchange(input string request, input string reply);
    expected = {expected, reply, "READY\r\n"};
    send_line(request);
    wait_output();
  endtask

  initial begin
    clk = 0; reset_n = 0; user_reset_n = 1; rx = 1; received = 0; expected = BANNER;
    repeat(8) @(negedge clk);
    reset_n = 1;
    wait_output();
    if (done || !led_done_n || !led_pass_n) $fatal(1, "completed before receiving an array");
    exchange("9 -3 14 0 7 7 -8\r\n", "Sorted: -8 -3 0 7 7 9 14\r\n");
    if (!done || led_done_n || led_pass_n || !saw_uart_wait)
      $fatal(1, "first-success status or backpressure coverage");
    exchange("-2147483648 2147483647 0 -1 +5\r", "Sorted: -2147483648 -1 0 5 2147483647\r\n");
    exchange("3, 0,\t-2\n", "Sorted: -2 0 3\r\n");
    exchange({"1", 8'h08, "2 3\n"}, "Sorted: 2 3\r\n");
    exchange("2147483648\n", "ERROR: int32 range\r\n");
    exchange("-2147483649\n", "ERROR: int32 range\r\n");
    exchange("1 x 2\n", "ERROR: invalid number\r\n");
    exchange("1-2\n", "ERROR: invalid number\r\n");
    exchange("\n", "ERROR: empty input\r\n");
    exchange("32 31 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1\n", "Sorted: 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32\r\n");
    exchange("1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1\n", "ERROR: max 32 numbers\r\n");
    exchange("-2147483648 2147483647 -2147483648 2147483647 -2147483648 2147483647 -2147483648 2147483647 -2147483648 2147483647 -2147483648 2147483647 -2147483648 2147483647 -2147483648 2147483647 -2147483648 2147483647 -2147483648 2147483647 -2147483648 2147483647 -2147483648 2147483647 -2147483648 2147483647 -2147483648 2147483647 -2147483648 2147483647 -2147483648 2147483647\n", "Sorted: -2147483648 -2147483648 -2147483648 -2147483648 -2147483648 -2147483648 -2147483648 -2147483648 -2147483648 -2147483648 -2147483648 -2147483648 -2147483648 -2147483648 -2147483648 -2147483648 2147483647 2147483647 2147483647 2147483647 2147483647 2147483647 2147483647 2147483647 2147483647 2147483647 2147483647 2147483647 2147483647 2147483647 2147483647 2147483647\r\n");
    begin
      string long_line;
      long_line = "";
      for (int k = 0; k < 520; k++) long_line = {long_line, "7"};
      exchange({long_line, "\n"}, "ERROR: line too long\r\n");
    end
    // A malformed stop bit must reject the line, then a valid line must work.
    expected = {expected, "ERROR: UART receive\r\nREADY\r\n"};
    send_byte(8'h34, 1'b0);
    rx = 1'b1; #(2*BIT_TIME);
    send_line("\n");
    wait_output();
    exchange("8 2 -4\n", "Sorted: -4 2 8\r\n");
    // Reset during a partial line: no stale input may appear in the next request.
    send_line("99 3 ");
    expected = {expected, BANNER};
    user_reset_n = 0;
    repeat(8) @(negedge clk);
    if (done || fail || !led_done_n || !led_pass_n || tx !== 1'b1)
      $fatal(1, "button reset did not clear state");
    user_reset_n = 1;
    wait_output();
    exchange("6 -2 6\n", "Sorted: -2 6 6\r\n");
    if (!done || fail || led_done_n || led_pass_n) $fatal(1, "status after reset rerun");
    $display("PASS: interactive UART RX/TX, repeated arrays, CR/LF/CRLF, int32 bounds, input rejection, framing error recovery, backpressure and partial-line reset");
    $finish;
  end
  initial begin
    #500ms;
    $fatal(1, "interactive sort UART timeout");
  end
endmodule
