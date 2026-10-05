// RV32I combinational execute and accepted control-transfer resolution.
module ex_stage (
  input  logic                    rst_i,
  input  logic                    kill_i,

  input  wire rv32_pkg::id_ex_t   id_ex_i,
  input  rv32_pkg::fwd_sel_e      fwd_a_sel_i,
  input  rv32_pkg::fwd_sel_e      fwd_b_sel_i,
  input  logic [31:0]             ex_mem_fwd_value_i,
  input  logic [31:0]             mem_wb_fwd_value_i,

  input  logic                    result_ready_i,

  output wire rv32_pkg::ex_mem_t  ex_mem_o,
  output wire rv32_pkg::redirect_t control_redirect_o,
  output logic                    result_valid_o,
  output logic                    wait_o
);

  import rv32_pkg::*;

  word_t     forwarded_rs1;
  word_t     forwarded_rs2;
  word_t     alu_operand_a;
  word_t     alu_operand_b;
  word_t     alu_result;

  logic      branch_taken;
  word_t     branch_target;
  logic      branch_target_misaligned;

  logic      active;
  logic      is_control;
  logic      control_taken;
  word_t     control_target;
  logic      control_target_misaligned;
  logic      ex_fire;





  ex_mem_t   ex_mem_d;
  redirect_t control_redirect_d;

  function automatic word_t select_forwarded_operand(
    input fwd_sel_e select,
    input word_t    regfile_value,
    input word_t    ex_mem_value,
    input word_t    mem_wb_value
  );
    begin
      unique case (select)
        FWD_EX_MEM: select_forwarded_operand = ex_mem_value;
        FWD_MEM_WB: select_forwarded_operand = mem_wb_value;
        default:    select_forwarded_operand = regfile_value;
      endcase
    end
  endfunction

  assign active     = id_ex_i.valid && !rst_i && !kill_i;
  assign is_control = (id_ex_i.ctrl.branch_kind != BR_NONE);

  always_comb begin
    forwarded_rs1 = select_forwarded_operand(
      fwd_a_sel_i,
      id_ex_i.rs1_value,
      ex_mem_fwd_value_i,
      mem_wb_fwd_value_i
    );

    forwarded_rs2 = select_forwarded_operand(
      fwd_b_sel_i,
      id_ex_i.rs2_value,
      ex_mem_fwd_value_i,
      mem_wb_fwd_value_i
    );
  end

  always_comb begin
    alu_operand_a = 32'b0;
    alu_operand_b = 32'b0;

    unique case (id_ex_i.ctrl.op_a_sel)
      OP_A_RS1:  alu_operand_a = forwarded_rs1;
      OP_A_PC:   alu_operand_a = id_ex_i.pc;
      OP_A_ZERO: alu_operand_a = 32'b0;
      default:   alu_operand_a = 32'b0;
    endcase

    unique case (id_ex_i.ctrl.op_b_sel)
      OP_B_RS2: alu_operand_b = forwarded_rs2;
      OP_B_IMM: alu_operand_b = id_ex_i.imm;
      default:  alu_operand_b = 32'b0;
    endcase
  end

  alu u_alu (
    .op_i     (id_ex_i.ctrl.alu_op),
    .a_i      (alu_operand_a),
    .b_i      (alu_operand_b),
    .result_o (alu_result)
  );

  branch_unit u_branch_unit (
    .kind_i       (id_ex_i.ctrl.branch_kind),
    .pc_i         (id_ex_i.pc),
    .imm_i        (id_ex_i.imm),
    .rs1_i        (forwarded_rs1),
    .rs2_i        (forwarded_rs2),
    .taken_o      (branch_taken),
    .target_o     (branch_target),
    .misaligned_o (branch_target_misaligned)
  );

  always_comb begin
    control_taken  = branch_taken;
    control_target = branch_target;


    // Valid is independent of downstream ready.
    result_valid_o = active;
    control_target_misaligned = branch_target_misaligned;
    ex_fire        = result_valid_o && result_ready_i;
    wait_o         = active && !ex_fire;

    ex_mem_d = '0;

    if (result_valid_o) begin
      ex_mem_d.valid          = 1'b1;
      ex_mem_d.pc             = id_ex_i.pc;
      ex_mem_d.insn           = id_ex_i.insn;
      ex_mem_d.rd             = id_ex_i.rd;
      ex_mem_d.reg_write      = id_ex_i.ctrl.reg_write;
      ex_mem_d.wb_sel         = id_ex_i.ctrl.wb_sel;
      ex_mem_d.ex_result      = alu_result;
      ex_mem_d.store_data     = forwarded_rs2;
      ex_mem_d.mem_cmd        = id_ex_i.ctrl.mem_cmd;
      ex_mem_d.mem_size       = id_ex_i.ctrl.mem_size;
      ex_mem_d.load_unsigned  = id_ex_i.ctrl.load_unsigned;
      ex_mem_d.control        = is_control;
      ex_mem_d.control_taken  = control_taken;
      ex_mem_d.control_target = control_target;
      ex_mem_d.exc            = id_ex_i.exc;

      if (!ex_mem_d.exc.valid && is_control && control_target_misaligned) begin
        ex_mem_d.exc.valid = 1'b1;
        ex_mem_d.exc.cause = EXC_INST_ADDR_MISALIGNED;
        ex_mem_d.exc.tval = control_target;
      end

      // Exception packets retain metadata but carry no architectural side effects.
      if (ex_mem_d.exc.valid) begin
        ex_mem_d.reg_write = 1'b0;
        ex_mem_d.mem_cmd   = MEM_NONE;
      end
    end

    control_redirect_d = '0;

    if (ex_fire && is_control && control_taken && !ex_mem_d.exc.valid) begin
      control_redirect_d.valid  = 1'b1;
      control_redirect_d.target = control_target;
    end
  end

  assign ex_mem_o           = ex_mem_d;
  assign control_redirect_o = control_redirect_d;

endmodule
