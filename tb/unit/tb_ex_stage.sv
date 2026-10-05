module tb_ex_stage;
  timeunit 1ns; timeprecision 1ps;
  import rv32_pkg::*;
  id_ex_t packet; ex_mem_t result; redirect_t redirect;
  logic ready, valid, waiting, kill;
  ex_stage dut (.rst_i(1'b0), .kill_i(kill), .id_ex_i(packet),
    .fwd_a_sel_i(FWD_EX_MEM), .fwd_b_sel_i(FWD_MEM_WB),
    .ex_mem_fwd_value_i(32'd17), .mem_wb_fwd_value_i(32'd9),
    .result_ready_i(ready), .ex_mem_o(result), .control_redirect_o(redirect),
    .result_valid_o(valid), .wait_o(waiting));
  initial begin
    packet='0; packet.valid=1; packet.ctrl.reg_write=1;
    packet.ctrl.alu_op=ALU_SUB; ready=1; kill=0;
    #1; if (!valid || result.ex_result!=8 || result.store_data!=9) $fatal(1,"forwarded arithmetic");
    packet.ctrl.branch_kind=BR_JAL; packet.pc=32'h100; packet.imm=32'h20;
    #1; if (!redirect.valid || redirect.target!=32'h120) $fatal(1,"jump");
    ready=0; #1; if (redirect.valid || !valid || !waiting) $fatal(1,"redirect repeated under hold");
    ready=1; packet.imm=2; #1;
    if (!result.exc.valid || result.reg_write || redirect.valid) $fatal(1,"alignment side effects");
    packet.exc.valid=1; packet.exc.cause=EXC_ILLEGAL_INSN; packet.ctrl.mem_cmd=MEM_STORE;
    #1; if (result.mem_cmd!=MEM_NONE || result.reg_write) $fatal(1,"fault side effects");
    kill=1; #1; if (valid || result.valid || redirect.valid) $fatal(1,"kill");
    $display("PASS: EX forwarding, backpressure, control, faults"); $finish;
  end
endmodule
