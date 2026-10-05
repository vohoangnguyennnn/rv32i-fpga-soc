// Combinational RV32I instruction decoder.
//
// The decoder is intentionally strict: outputs default to a side-effect-free
// illegal instruction and are enabled only after all relevant opcode, funct3
// and funct7 fields have been validated.
module decoder (
  input  logic [31:0]               insn_i,
  output logic [4:0]                rs1_o,
  output logic [4:0]                rs2_o,
  output logic [4:0]                rd_o,
  output rv32_pkg::imm_sel_e        imm_sel_o,
  output rv32_pkg::decode_ctrl_t    ctrl_o,
  output logic                      illegal_o
);

  import rv32_pkg::*;

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;

  always_comb begin
    opcode = insn_i[6:0];
    funct3 = insn_i[14:12];
    funct7 = insn_i[31:25];

    // Register indices are always exposed; uses_rs* identify true dependencies.
    rs1_o = insn_i[19:15];
    rs2_o = insn_i[24:20];
    rd_o  = insn_i[11:7];

    // Side-effect-free defaults make unmatched encodings illegal without latches.
    imm_sel_o          = IMM_NONE;
    ctrl_o             = '0;
    ctrl_o.op_a_sel    = OP_A_ZERO;
    ctrl_o.op_b_sel    = OP_B_IMM;
    ctrl_o.mem_size    = MEM_WORD;
    illegal_o          = 1'b1;

    unique case (opcode)
      OPCODE_LUI: begin
        imm_sel_o       = IMM_U;
        ctrl_o.reg_write = 1'b1;
        ctrl_o.alu_op    = ALU_ADD;
        ctrl_o.op_a_sel  = OP_A_ZERO;
        ctrl_o.op_b_sel  = OP_B_IMM;
        illegal_o        = 1'b0;
      end

      OPCODE_AUIPC: begin
        imm_sel_o        = IMM_U;
        ctrl_o.reg_write = 1'b1;
        ctrl_o.alu_op    = ALU_ADD;
        ctrl_o.op_a_sel  = OP_A_PC;
        ctrl_o.op_b_sel  = OP_B_IMM;
        illegal_o        = 1'b0;
      end

      OPCODE_JAL: begin
        imm_sel_o          = IMM_J;
        ctrl_o.reg_write   = 1'b1;
        ctrl_o.wb_sel      = WB_PC4;
        ctrl_o.branch_kind = BR_JAL;
        illegal_o          = 1'b0;
      end

      OPCODE_JALR: begin
        if (funct3 == FUNCT3_JALR) begin
          imm_sel_o          = IMM_I;
          ctrl_o.uses_rs1    = 1'b1;
          ctrl_o.reg_write   = 1'b1;
          ctrl_o.wb_sel      = WB_PC4;
          ctrl_o.branch_kind = BR_JALR;
          illegal_o          = 1'b0;
        end
      end

      OPCODE_BRANCH: begin
        unique case (funct3)
          FUNCT3_BEQ:  begin ctrl_o.branch_kind = BR_BEQ;  illegal_o = 1'b0; end
          FUNCT3_BNE:  begin ctrl_o.branch_kind = BR_BNE;  illegal_o = 1'b0; end
          FUNCT3_BLT:  begin ctrl_o.branch_kind = BR_BLT;  illegal_o = 1'b0; end
          FUNCT3_BGE:  begin ctrl_o.branch_kind = BR_BGE;  illegal_o = 1'b0; end
          FUNCT3_BLTU: begin ctrl_o.branch_kind = BR_BLTU; illegal_o = 1'b0; end
          FUNCT3_BGEU: begin ctrl_o.branch_kind = BR_BGEU; illegal_o = 1'b0; end
          default: ;
        endcase

        if (!illegal_o) begin
          imm_sel_o       = IMM_B;
          ctrl_o.uses_rs1 = 1'b1;
          ctrl_o.uses_rs2 = 1'b1;
        end
      end

      OPCODE_LOAD: begin
        unique case (funct3)
          FUNCT3_LB: begin
            ctrl_o.mem_size      = MEM_BYTE;
            ctrl_o.load_unsigned = 1'b0;
            illegal_o            = 1'b0;
          end
          FUNCT3_LH: begin
            ctrl_o.mem_size      = MEM_HALF;
            ctrl_o.load_unsigned = 1'b0;
            illegal_o            = 1'b0;
          end
          FUNCT3_LW: begin
            ctrl_o.mem_size      = MEM_WORD;
            ctrl_o.load_unsigned = 1'b0;
            illegal_o            = 1'b0;
          end
          FUNCT3_LBU: begin
            ctrl_o.mem_size      = MEM_BYTE;
            ctrl_o.load_unsigned = 1'b1;
            illegal_o            = 1'b0;
          end
          FUNCT3_LHU: begin
            ctrl_o.mem_size      = MEM_HALF;
            ctrl_o.load_unsigned = 1'b1;
            illegal_o            = 1'b0;
          end
          default: ;
        endcase

        if (!illegal_o) begin
          imm_sel_o          = IMM_I;
          ctrl_o.uses_rs1    = 1'b1;
          ctrl_o.reg_write   = 1'b1;
          ctrl_o.alu_op      = ALU_ADD;
          ctrl_o.op_a_sel    = OP_A_RS1;
          ctrl_o.op_b_sel    = OP_B_IMM;
          ctrl_o.wb_sel      = WB_LOAD;
          ctrl_o.mem_cmd     = MEM_LOAD;
        end
      end

      OPCODE_STORE: begin
        unique case (funct3)
          FUNCT3_SB: begin ctrl_o.mem_size = MEM_BYTE; illegal_o = 1'b0; end
          FUNCT3_SH: begin ctrl_o.mem_size = MEM_HALF; illegal_o = 1'b0; end
          FUNCT3_SW: begin ctrl_o.mem_size = MEM_WORD; illegal_o = 1'b0; end
          default: ;
        endcase

        if (!illegal_o) begin
          imm_sel_o        = IMM_S;
          ctrl_o.uses_rs1  = 1'b1;
          ctrl_o.uses_rs2  = 1'b1;
          ctrl_o.alu_op    = ALU_ADD;
          ctrl_o.op_a_sel  = OP_A_RS1;
          ctrl_o.op_b_sel  = OP_B_IMM;
          ctrl_o.mem_cmd   = MEM_STORE;
        end
      end

      OPCODE_OP_IMM: begin
        unique case (funct3)
          FUNCT3_ADD_SUB: begin ctrl_o.alu_op = ALU_ADD;  illegal_o = 1'b0; end
          FUNCT3_SLT:     begin ctrl_o.alu_op = ALU_SLT;  illegal_o = 1'b0; end
          FUNCT3_SLTU:    begin ctrl_o.alu_op = ALU_SLTU; illegal_o = 1'b0; end
          FUNCT3_XOR:     begin ctrl_o.alu_op = ALU_XOR;  illegal_o = 1'b0; end
          FUNCT3_OR:      begin ctrl_o.alu_op = ALU_OR;   illegal_o = 1'b0; end
          FUNCT3_AND:     begin ctrl_o.alu_op = ALU_AND;  illegal_o = 1'b0; end

          FUNCT3_SLL: begin
            if (funct7 == FUNCT7_BASE) begin
              ctrl_o.alu_op = ALU_SLL;
              illegal_o     = 1'b0;
            end
          end

          FUNCT3_SRL_SRA: begin
            unique case (funct7)
              FUNCT7_BASE: begin
                ctrl_o.alu_op = ALU_SRL;
                illegal_o     = 1'b0;
              end
              FUNCT7_SUB_SRA: begin
                ctrl_o.alu_op = ALU_SRA;
                illegal_o     = 1'b0;
              end
              default: ;
            endcase
          end

          default: ;
        endcase

        if (!illegal_o) begin
          imm_sel_o        = IMM_I;
          ctrl_o.uses_rs1  = 1'b1;
          ctrl_o.reg_write = 1'b1;
          ctrl_o.op_a_sel  = OP_A_RS1;
          ctrl_o.op_b_sel  = OP_B_IMM;
        end
      end

      OPCODE_OP: begin
        unique case (funct7)
          FUNCT7_BASE: begin
            unique case (funct3)
              FUNCT3_ADD_SUB: begin ctrl_o.alu_op = ALU_ADD;  illegal_o = 1'b0; end
              FUNCT3_SLL:     begin ctrl_o.alu_op = ALU_SLL;  illegal_o = 1'b0; end
              FUNCT3_SLT:     begin ctrl_o.alu_op = ALU_SLT;  illegal_o = 1'b0; end
              FUNCT3_SLTU:    begin ctrl_o.alu_op = ALU_SLTU; illegal_o = 1'b0; end
              FUNCT3_XOR:     begin ctrl_o.alu_op = ALU_XOR;  illegal_o = 1'b0; end
              FUNCT3_SRL_SRA: begin ctrl_o.alu_op = ALU_SRL;  illegal_o = 1'b0; end
              FUNCT3_OR:      begin ctrl_o.alu_op = ALU_OR;   illegal_o = 1'b0; end
              FUNCT3_AND:     begin ctrl_o.alu_op = ALU_AND;  illegal_o = 1'b0; end
              default: ;
            endcase
          end

          FUNCT7_SUB_SRA: begin
            unique case (funct3)
              FUNCT3_ADD_SUB: begin ctrl_o.alu_op = ALU_SUB; illegal_o = 1'b0; end
              FUNCT3_SRL_SRA: begin ctrl_o.alu_op = ALU_SRA; illegal_o = 1'b0; end
              default: ;
            endcase
          end

          default: ;
        endcase

        if (!illegal_o) begin
          ctrl_o.uses_rs1  = 1'b1;
          ctrl_o.uses_rs2  = 1'b1;
          ctrl_o.reg_write = 1'b1;
          ctrl_o.op_a_sel  = OP_A_RS1;
          ctrl_o.op_b_sel  = OP_B_RS2;
        end
      end

      OPCODE_MISC_MEM: begin
        // FENCE is a legal NOP for this single-hart blocking memory system.
        // FENCE.I (funct3 001) remains illegal because Zifencei is out of scope.
        if (funct3 == FUNCT3_FENCE) begin
          ctrl_o.is_fence = 1'b1;
          illegal_o       = 1'b0;
        end
      end

      OPCODE_SYSTEM: begin
        if ((insn_i == INSN_ECALL) || (insn_i == INSN_EBREAK)) illegal_o = 1'b0;
      end

      default: ;
    endcase
  end

endmodule
