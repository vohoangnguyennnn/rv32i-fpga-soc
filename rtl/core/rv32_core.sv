// RV32I five-stage pipeline; synchronous faults stop execution.
module rv32_core #(
  parameter logic [31:0] RESET_VECTOR = 32'h0000_0000
) (
  input  logic clk_i,
  input  logic rst_i,

  // Live MTIP level; committed MIE/MTIE state controls eligibility.

  rv32_mem_if.master imem_m,
  rv32_mem_if.master dmem_m,

  output logic        trace_valid_o,
  output logic [31:0] trace_pc_o,
  output logic [31:0] trace_insn_o,
  output logic        trace_rd_we_o,
  output logic [4:0]  trace_rd_addr_o,
  output logic [31:0] trace_rd_data_o,
  output logic [31:0] trace_mem_addr_o,
  output logic [3:0]  trace_mem_wstrb_o,
  output logic [31:0] trace_mem_wdata_o,
  output logic        trace_trap_o,
  output logic [4:0]  trace_cause_o,
  output logic        trace_control_o,
  output logic        trace_taken_o,
  output logic [31:0] trace_target_o,

  // Read-only implementation-performance observability. These counters do
  // not feed pipeline control or architectural state.
  output logic [63:0] perf_cycle_o,
  output logic [63:0] perf_instret_o,
  output logic [63:0] perf_load_use_stall_o,
  output logic [63:0] perf_mem_stall_o,
  output logic [63:0] perf_redirect_o,
  output logic [63:0] perf_squash_o
);

  import rv32_pkg::*;

  // Pipeline state and stage-next packets.
  if_id_t  if_id_q;
  if_id_t  if_id_d;
  id_ex_t  id_ex_q;
  id_ex_t  id_ex_d;
  ex_mem_t ex_mem_q;
  ex_mem_t ex_mem_d;
  mem_wb_t mem_wb_q;
  mem_wb_t mem_wb_d;

  logic [1:0] fetch_squash_count;
  logic fetch_valid;
  word_t fetch_pc;
  word_t fetch_insn;
  exc_t  fetch_exc;
  logic  fetch_consume;

  // Central pipeline control.
  logic pc_enable;
  logic if_id_enable;
  logic id_ex_enable;
  logic ex_mem_enable;
  logic mem_wb_enable;
  logic if_id_flush;
  logic id_ex_flush;
  logic ex_mem_flush;
  logic mem_wb_flush;
  logic redirect_valid;
  word_t redirect_pc;

  redirect_t control_redirect;
  logic      id_exception;
  logic      ex_exception;
  logic      mem_exception;
  logic      wb_trap;
  logic      ex_wait;
  logic      mem_wait;

  fwd_sel_e ex_fwd_a_sel;
  fwd_sel_e ex_fwd_b_sel;
  word_t    ex_mem_fwd_value;
  word_t    mem_wb_fwd_value;
  logic     load_use_hazard;
  logic     fault_pending;

  logic effective_load_use_stall;
  logic effective_mem_stall;

  // WB/architectural commit.
  logic wb_retire;
  logic wb_reg_write;

  assign wb_trap       = mem_wb_q.valid && mem_wb_q.exc.valid;
  assign wb_retire     = mem_wb_q.valid && !mem_wb_q.exc.valid;
  assign wb_reg_write  = wb_retire && mem_wb_q.reg_write && (mem_wb_q.rd != 5'd0);

  // Match the centralized controller's age-priority selection so stall
  // categories are mutually exclusive. Exception/trap drain cycles are not
  // benchmark stalls and therefore remain outside this breakdown.
  assign effective_mem_stall = mem_wait && !wb_trap && !mem_exception;
  assign effective_load_use_stall = load_use_hazard
                                  && !wb_trap
                                  && !mem_exception
                                  && !mem_wait
                                  && !ex_exception
                                  && !ex_wait
                                  && !fault_pending
                                  && !control_redirect.valid
                                  && !id_exception;
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      perf_cycle_o          <= 64'b0;
      perf_instret_o        <= 64'b0;
      perf_load_use_stall_o <= 64'b0;
      perf_mem_stall_o      <= 64'b0;
      perf_redirect_o       <= 64'b0;
      perf_squash_o         <= 64'b0;
    end else begin
      perf_cycle_o <= perf_cycle_o + 64'd1;

      if (wb_retire)                 perf_instret_o        <= perf_instret_o + 64'd1;
      if (effective_load_use_stall)  perf_load_use_stall_o <= perf_load_use_stall_o + 64'd1;
      if (effective_mem_stall)       perf_mem_stall_o      <= perf_mem_stall_o + 64'd1;

      if (control_redirect.valid) begin
        perf_redirect_o <= perf_redirect_o + 64'd1;
        perf_squash_o   <= perf_squash_o + {63'b0, if_id_q.valid} + {62'b0, fetch_squash_count};
      end
    end
  end

  // MEM/WB is the only trace source; traps are events, not retirements.
  always_comb begin
    trace_valid_o      = mem_wb_q.valid;
    trace_pc_o         = mem_wb_q.pc;
    trace_insn_o       = mem_wb_q.insn;
    trace_rd_we_o      = wb_reg_write;
    trace_rd_addr_o    = mem_wb_q.rd;
    trace_rd_data_o    = mem_wb_q.wb_data;
    trace_mem_addr_o   = mem_wb_q.mem_addr;
    trace_mem_wstrb_o  = mem_wb_q.mem_wstrb;
    trace_mem_wdata_o  = mem_wb_q.mem_wdata;
    trace_trap_o       = wb_trap;
    trace_cause_o      = wb_trap ? mem_wb_q.exc.cause : 5'b0;
    trace_control_o    = wb_retire && mem_wb_q.control;
    trace_taken_o      = wb_retire && mem_wb_q.control_taken;
    trace_target_o     = mem_wb_q.control_target;
  end

  // IF and IF/ID next packet.
  assign fetch_consume = if_id_enable && !if_id_flush;

  if_stage #(
    .RESET_VECTOR (RESET_VECTOR)
  ) u_if_stage (
    .clk_i            (clk_i),
    .rst_i            (rst_i),
    .enable_i         (pc_enable),
    .consume_i        (fetch_consume),
    .flush_i          (if_id_flush),
    .redirect_valid_i (redirect_valid),
    .redirect_pc_i    (redirect_pc),
    .imem_m           (imem_m),
    .squash_count_o   (fetch_squash_count),
    .fetch_valid_o    (fetch_valid),
    .fetch_pc_o       (fetch_pc),
    .fetch_insn_o     (fetch_insn),
    .fetch_exc_o      (fetch_exc)
  );

  always_comb begin
    if_id_d       = '0;
    if_id_d.valid = fetch_valid;

    if (fetch_valid) begin
      if_id_d.pc   = fetch_pc;
      if_id_d.insn = fetch_insn;
      if_id_d.exc  = fetch_exc;
    end
  end

  // ID decode.
  id_stage u_id_stage (
    .clk_i     (clk_i),
    .if_id_i   (if_id_q),
    .wb_we_i   (wb_reg_write),
    .wb_rd_i   (mem_wb_q.rd),
    .wb_data_i (mem_wb_q.wb_data),
    .id_ex_o   (id_ex_d)
  );

  assign id_exception = id_ex_d.valid && id_ex_d.exc.valid;

  hazard_unit u_hazard_unit (
    .id_valid_i    (id_ex_d.valid),
    .id_rs1_i      (id_ex_d.rs1),
    .id_rs2_i      (id_ex_d.rs2),
    .id_ctrl_i     (id_ex_d.ctrl),
    .id_ex_i       (id_ex_q),
    .load_use_o    (load_use_hazard),
    .stall_id_o    ()
  );

  // EX.
  logic        ex_result_valid;
  logic        ex_result_ready;
  logic        ex_kill;

  assign mem_wb_fwd_value = mem_wb_q.wb_data;

  forwarding_unit u_forwarding_unit (
    .id_ex_i      (id_ex_q),
    .ex_mem_i     (ex_mem_q),
    .mem_wb_i     (mem_wb_q),
    .ex_a_sel_o   (ex_fwd_a_sel),
    .ex_b_sel_o   (ex_fwd_b_sel)
  );

  always_comb begin
    unique case (ex_mem_q.wb_sel)
      WB_EX_RESULT: ex_mem_fwd_value = ex_mem_q.ex_result;
      WB_PC4:       ex_mem_fwd_value = ex_mem_q.pc + 32'd4;
      default:      ex_mem_fwd_value = 32'b0;
    endcase
  end

  // Older WB/MEM events block EX. Backpressure removes readiness without
  // killing ID/EX, avoiding a loop through ex_wait/pipeline_ctrl.
  assign ex_kill         = wb_trap || mem_exception;
  assign ex_result_ready = !wb_trap && !mem_wait && !mem_exception;

  ex_stage u_ex_stage (
    .rst_i                  (rst_i),
    .kill_i                 (ex_kill),
    .id_ex_i                (id_ex_q),
    .fwd_a_sel_i            (ex_fwd_a_sel),
    .fwd_b_sel_i            (ex_fwd_b_sel),
    .ex_mem_fwd_value_i     (ex_mem_fwd_value),
    .mem_wb_fwd_value_i     (mem_wb_fwd_value),
    .result_ready_i         (ex_result_ready),
    .ex_mem_o               (ex_mem_d),
    .control_redirect_o     (control_redirect),
    .result_valid_o         (ex_result_valid),
    .wait_o                 (ex_wait)
  );

  // Only newly discovered EX faults enter controller arbitration.
  assign ex_exception = ex_result_valid && ex_mem_d.exc.valid && !id_ex_q.exc.valid && ex_result_ready;

  // MEM.
  logic lsu_req_valid;
  logic lsu_rsp_valid;
  logic lsu_rsp_ready;
  word_t lsu_load_data;
  exc_t  lsu_exception;
  logic [3:0] lsu_trace_wstrb;
  word_t      lsu_trace_wdata;
  logic       mem_is_memory;

  assign mem_is_memory = ex_mem_q.valid && !ex_mem_q.exc.valid && ((ex_mem_q.mem_cmd == MEM_LOAD) || (ex_mem_q.mem_cmd == MEM_STORE));
  assign lsu_req_valid = mem_is_memory && !wb_trap;
  assign lsu_rsp_ready = mem_wb_enable && !mem_wb_flush && !wb_trap;

  lsu u_lsu (
    .clk_i             (clk_i),
    .rst_i             (rst_i),
    .kill_i            (wb_trap),
    .req_valid_i       (lsu_req_valid),
    .req_ready_o       (),
    .cmd_i             (ex_mem_q.mem_cmd),
    .size_i            (ex_mem_q.mem_size),
    .load_unsigned_i   (ex_mem_q.load_unsigned),
    .addr_i            (ex_mem_q.ex_result),
    .store_data_i      (ex_mem_q.store_data),
    .dmem_m            (dmem_m),
    .rsp_valid_o       (lsu_rsp_valid),
    .rsp_ready_i       (lsu_rsp_ready),
    .load_data_o       (lsu_load_data),
    .exception_o       (lsu_exception),
    .trace_wstrb_o     (lsu_trace_wstrb),
    .trace_wdata_o     (lsu_trace_wdata)
  );

  // EX/MEM owns a blocking access until the LSU's sticky response; local and
  // bus faults deliberately use the same completion path.
  assign mem_wait = mem_is_memory && !lsu_rsp_valid;

  always_comb begin
    mem_wb_d = '0;

    if (ex_mem_q.valid) begin
      // Memory packets become valid only when the LSU responds.
      if (!mem_is_memory) begin
        mem_wb_d.valid          = 1'b1;
        mem_wb_d.pc             = ex_mem_q.pc;
        mem_wb_d.insn           = ex_mem_q.insn;
        mem_wb_d.rd             = ex_mem_q.rd;
        mem_wb_d.reg_write      = ex_mem_q.reg_write;
        mem_wb_d.control        = ex_mem_q.control;
        mem_wb_d.control_taken  = ex_mem_q.control_taken;
        mem_wb_d.control_target = ex_mem_q.control_target;
        mem_wb_d.exc            = ex_mem_q.exc;

        unique case (ex_mem_q.wb_sel)
          WB_EX_RESULT: mem_wb_d.wb_data = ex_mem_q.ex_result;
          WB_PC4:      mem_wb_d.wb_data = ex_mem_q.pc + 32'd4;
          default:     mem_wb_d.wb_data = 32'b0;
        endcase
      end else if (lsu_rsp_valid) begin
        mem_wb_d.valid          = 1'b1;
        mem_wb_d.pc             = ex_mem_q.pc;
        mem_wb_d.insn           = ex_mem_q.insn;
        mem_wb_d.rd             = ex_mem_q.rd;
        mem_wb_d.reg_write      = ex_mem_q.reg_write;
        mem_wb_d.wb_data        = (ex_mem_q.mem_cmd == MEM_LOAD) ? lsu_load_data : 32'b0;
        mem_wb_d.mem_write      = (ex_mem_q.mem_cmd == MEM_STORE);
        mem_wb_d.mem_addr       = ex_mem_q.ex_result;
        mem_wb_d.mem_wstrb      = lsu_trace_wstrb;
        mem_wb_d.mem_wdata      = lsu_trace_wdata;
        mem_wb_d.control        = ex_mem_q.control;
        mem_wb_d.control_taken  = ex_mem_q.control_taken;
        mem_wb_d.control_target = ex_mem_q.control_target;
        mem_wb_d.exc            = lsu_exception;

        if (lsu_exception.valid) begin
          mem_wb_d.reg_write = 1'b0;
          mem_wb_d.mem_write = 1'b0;
          mem_wb_d.mem_wstrb = 4'b0000;
          mem_wb_d.mem_wdata = 32'b0;
        end
      end

      // No exception packet may carry an architectural side effect into WB.
      if (mem_wb_d.valid && mem_wb_d.exc.valid) begin
        mem_wb_d.reg_write = 1'b0;
        mem_wb_d.mem_write = 1'b0;
      end
    end
  end

  // Only LSU-originated faults are new MEM exception events.
  assign mem_exception = mem_is_memory && lsu_rsp_valid && lsu_exception.valid;

  // Pipeline controller.
  pipeline_ctrl u_pipeline_ctrl (
    .clk_i                (clk_i),
    .rst_i                (rst_i),
    .load_use_i           (load_use_hazard),
    .ex_wait_i            (ex_wait),
    .mem_wait_i           (mem_wait),
    .id_exception_i       (id_exception),
    .ex_exception_i       (ex_exception),
    .mem_exception_i      (mem_exception),
    .wb_fault_i            (wb_trap),
    .control_redirect_i   (control_redirect),
    .pc_enable_o          (pc_enable),
    .if_id_enable_o       (if_id_enable),
    .id_ex_enable_o       (id_ex_enable),
    .ex_mem_enable_o      (ex_mem_enable),
    .mem_wb_enable_o      (mem_wb_enable),
    .if_id_flush_o        (if_id_flush),
    .id_ex_flush_o        (id_ex_flush),
    .ex_mem_flush_o       (ex_mem_flush),
    .mem_wb_flush_o       (mem_wb_flush),
    .redirect_valid_o     (redirect_valid),
    .redirect_pc_o        (redirect_pc),
    .fault_pending_o         (fault_pending)
  );

  // Pipeline-register priority: reset > flush > enable > hold.
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      if_id_q <= '0;
    end else if (if_id_flush) begin
      if_id_q <= '0;
    end else if (if_id_enable) begin
      if_id_q <= if_id_d;
    end
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      id_ex_q <= '0;
    end else if (id_ex_flush) begin
      id_ex_q <= '0;
    end else if (id_ex_enable) begin
      id_ex_q <= id_ex_d;
    end else if (id_ex_q.valid && wb_reg_write) begin
      // Refresh operands when a wait outlives the producer's forwarding slot.
      if (id_ex_q.ctrl.uses_rs1 && (id_ex_q.rs1 == mem_wb_q.rd)) begin
        id_ex_q.rs1_value <= mem_wb_q.wb_data;
      end
      if (id_ex_q.ctrl.uses_rs2 && (id_ex_q.rs2 == mem_wb_q.rd)) begin
        id_ex_q.rs2_value <= mem_wb_q.wb_data;
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      ex_mem_q <= '0;
    end else if (ex_mem_flush) begin
      ex_mem_q <= '0;
    end else if (ex_mem_enable) begin
      ex_mem_q <= ex_mem_d;
    end
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      mem_wb_q <= '0;
    end else if (mem_wb_flush) begin
      mem_wb_q <= '0;
    end else if (mem_wb_enable) begin
      mem_wb_q <= mem_wb_d;
    end
  end

endmodule
