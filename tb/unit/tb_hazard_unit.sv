module tb_hazard_unit;
  timeunit 1ns; timeprecision 1ps;
  import rv32_pkg::*;
  id_ex_t producer; decode_ctrl_t consumer;
  logic valid, load_use, stall;
  logic [4:0] rs1, rs2;
  hazard_unit dut(.id_valid_i(valid),.id_rs1_i(rs1),.id_rs2_i(rs2),
    .id_ctrl_i(consumer),.id_ex_i(producer),.load_use_o(load_use),.stall_id_o(stall));
  initial begin
    valid=1; producer='0; consumer='0; rs1=3; rs2=4;
    producer.valid=1; producer.rd=3; producer.ctrl.reg_write=1; producer.ctrl.mem_cmd=MEM_LOAD;
    consumer.uses_rs1=1; #1; if (!load_use || !stall) $fatal(1,"load dependency");
    consumer.uses_rs1=0; #1; if(stall) $fatal(1,"unused operand");
    consumer.uses_rs2=1; producer.rd=4; #1; if(!stall) $fatal(1,"store data dependency");
    producer.rd=0; rs2=0; #1; if(stall) $fatal(1,"x0 false dependency");
    producer.rd=4; rs2=4; producer.exc.valid=1; #1; if(stall) $fatal(1,"fault producer");
    producer.exc.valid=0; producer.ctrl.mem_cmd=MEM_NONE; #1; if(stall) $fatal(1,"forwardable ALU");
    $display("PASS: load-use, unused operands, x0, fault producer"); $finish;
  end
endmodule
