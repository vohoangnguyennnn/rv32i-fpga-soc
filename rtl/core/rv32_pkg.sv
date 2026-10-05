package rv32_pkg;

  localparam int XLEN       = 32;
  localparam int REG_ADDR_W = 5;

  typedef logic [XLEN-1:0]       word_t;
  typedef logic [REG_ADDR_W-1:0] reg_addr_t;

  // Major opcodes
  localparam logic [6:0] OPCODE_LOAD     = 7'b000_0011;
  localparam logic [6:0] OPCODE_MISC_MEM = 7'b000_1111;
  localparam logic [6:0] OPCODE_OP_IMM   = 7'b001_0011;
  localparam logic [6:0] OPCODE_AUIPC    = 7'b001_0111;
  localparam logic [6:0] OPCODE_STORE    = 7'b010_0011;
  localparam logic [6:0] OPCODE_OP       = 7'b011_0011;
  localparam logic [6:0] OPCODE_LUI      = 7'b011_0111;
  localparam logic [6:0] OPCODE_BRANCH   = 7'b110_0011;
  localparam logic [6:0] OPCODE_JALR     = 7'b110_0111;
  localparam logic [6:0] OPCODE_JAL      = 7'b110_1111;
  localparam logic [6:0] OPCODE_SYSTEM   = 7'b111_0011;

  // OP and OP-IMM funct fields.
  localparam logic [2:0] FUNCT3_ADD_SUB = 3'b000;
  localparam logic [2:0] FUNCT3_SLL     = 3'b001;
  localparam logic [2:0] FUNCT3_SLT     = 3'b010;
  localparam logic [2:0] FUNCT3_SLTU    = 3'b011;
  localparam logic [2:0] FUNCT3_XOR     = 3'b100;
  localparam logic [2:0] FUNCT3_SRL_SRA = 3'b101;
  localparam logic [2:0] FUNCT3_OR      = 3'b110;
  localparam logic [2:0] FUNCT3_AND     = 3'b111;

  localparam logic [6:0] FUNCT7_BASE    = 7'b000_0000;
  localparam logic [6:0] FUNCT7_SUB_SRA = 7'b010_0000;

  // Branch funct3 values.
  localparam logic [2:0] FUNCT3_BEQ  = 3'b000;
  localparam logic [2:0] FUNCT3_BNE  = 3'b001;
  localparam logic [2:0] FUNCT3_BLT  = 3'b100;
  localparam logic [2:0] FUNCT3_BGE  = 3'b101;
  localparam logic [2:0] FUNCT3_BLTU = 3'b110;
  localparam logic [2:0] FUNCT3_BGEU = 3'b111;

  // Load/store funct3 values.
  localparam logic [2:0] FUNCT3_LB  = 3'b000;
  localparam logic [2:0] FUNCT3_LH  = 3'b001;
  localparam logic [2:0] FUNCT3_LW  = 3'b010;
  localparam logic [2:0] FUNCT3_LBU = 3'b100;
  localparam logic [2:0] FUNCT3_LHU = 3'b101;

  localparam logic [2:0] FUNCT3_SB = 3'b000;
  localparam logic [2:0] FUNCT3_SH = 3'b001;
  localparam logic [2:0] FUNCT3_SW = 3'b010;

  localparam logic [2:0] FUNCT3_FENCE = 3'b000;
  localparam logic [2:0] FUNCT3_JALR  = 3'b000;

  localparam word_t INSN_ECALL = 32'h00000073;
  localparam word_t INSN_EBREAK = 32'h00100073;

  // Datapath and decode controls
  typedef enum logic [3:0] {
    ALU_NONE,
    ALU_ADD,
    ALU_SUB,
    ALU_SLL,
    ALU_SRL,
    ALU_SRA,
    ALU_SLT,
    ALU_SLTU,
    ALU_XOR,
    ALU_OR,
    ALU_AND
  } alu_op_e;

  typedef enum logic [2:0] {
    IMM_NONE,
    IMM_I,
    IMM_S,
    IMM_B,
    IMM_U,
    IMM_J
  } imm_sel_e;

  typedef enum logic [1:0] {
    OP_A_RS1,
    OP_A_PC,
    OP_A_ZERO
  } op_a_sel_e;

  typedef enum logic {
    OP_B_RS2,
    OP_B_IMM
  } op_b_sel_e;

  typedef enum logic [1:0] {
    WB_EX_RESULT,
    WB_LOAD,
    WB_PC4
  } wb_sel_e;

  typedef enum logic [3:0] {
    BR_NONE,
    BR_BEQ,
    BR_BNE,
    BR_BLT,
    BR_BGE,
    BR_BLTU,
    BR_BGEU,
    BR_JAL,
    BR_JALR
  } branch_e;

  typedef enum logic [1:0] {
    MEM_NONE,
    MEM_LOAD,
    MEM_STORE
  } mem_cmd_e;

  typedef enum logic [1:0] {
    MEM_BYTE,
    MEM_HALF,
    MEM_WORD
  } mem_size_e;

  typedef enum logic [1:0] {
    FWD_REGFILE,
    FWD_EX_MEM,
    FWD_MEM_WB
  } fwd_sel_e;

  typedef logic [4:0] fault_cause_t;

  // Synchronous fault codes for the coursework error-stop environment.
  typedef enum fault_cause_t {
    EXC_INST_ADDR_MISALIGNED  = 5'd0,
    EXC_INST_ACCESS_FAULT     = 5'd1,
    EXC_ILLEGAL_INSN          = 5'd2,
    EXC_BREAKPOINT            = 5'd3,
    EXC_LOAD_ADDR_MISALIGNED  = 5'd4,
    EXC_LOAD_ACCESS_FAULT     = 5'd5,
    EXC_STORE_ADDR_MISALIGNED = 5'd6,
    EXC_STORE_ACCESS_FAULT    = 5'd7,
    EXC_ENV_CALL               = 5'd11
  } exc_cause_e;

  // Shared control and pipeline bundles
  typedef struct packed {
    logic  valid;
    word_t target;
  } redirect_t;

  typedef struct packed {
    logic       valid;
    exc_cause_e cause;
    word_t      tval;
  } exc_t;

  typedef struct packed {
    logic      uses_rs1;
    logic      uses_rs2;
    logic      reg_write;
    alu_op_e   alu_op;
    op_a_sel_e op_a_sel;
    op_b_sel_e op_b_sel;
    wb_sel_e   wb_sel;
    branch_e   branch_kind;
    mem_cmd_e  mem_cmd;
    mem_size_e mem_size;
    logic      load_unsigned;
    logic      is_fence;
  } decode_ctrl_t;

  typedef struct packed {
    logic valid;
    word_t pc;
    word_t insn;
    exc_t exc;
  } if_id_t;

  typedef struct packed {
    logic         valid;
    word_t        pc;
    word_t        insn;
    reg_addr_t    rs1;
    reg_addr_t    rs2;
    reg_addr_t    rd;
    word_t        rs1_value;
    word_t        rs2_value;
    word_t        imm;
    decode_ctrl_t ctrl;
    exc_t         exc;
  } id_ex_t;

  typedef struct packed {
    logic      valid;
    word_t     pc;
    word_t     insn;
    reg_addr_t rd;
    logic      reg_write;
    wb_sel_e   wb_sel;
    word_t     ex_result;
    word_t     store_data;
    mem_cmd_e  mem_cmd;
    mem_size_e mem_size;
    logic      load_unsigned;
    logic      control;
    logic      control_taken;
    word_t     control_target;
    exc_t      exc;
  } ex_mem_t;

  typedef struct packed {
    logic      valid;
    word_t     pc;
    word_t     insn;
    reg_addr_t rd;
    logic      reg_write;
    word_t     wb_data;
    logic      mem_write;
    word_t     mem_addr;
    logic [3:0] mem_wstrb;
    word_t     mem_wdata;
    logic      control;
    logic      control_taken;
    word_t     control_target;
    exc_t      exc;
  } mem_wb_t;

endpackage
