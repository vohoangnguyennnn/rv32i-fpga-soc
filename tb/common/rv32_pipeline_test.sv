module rv32_pipeline_test #(parameter int REQ_DELAY=0, RSP_DELAY=0, SCENARIO=0);
  timeunit 1ns; timeprecision 1ps;
  import rv32_pkg::*; import rv32_tb_pkg::*;
  logic clk, rst;
  rv32_mem_if imem(); rv32_mem_if dmem();
  logic valid, fault, rd_we; logic [31:0] pc, addr, data, value; logic [3:0] strb;
  logic [4:0] rd; logic [63:0] instret, cycle_count, stalls, mem_stalls, redirects;
  int retired, stores;
  rv32_core dut(.clk_i(clk),.rst_i(rst),.imem_m(imem),.dmem_m(dmem),
    .trace_valid_o(valid),.trace_pc_o(pc),.trace_insn_o(),.trace_rd_we_o(rd_we),
    .trace_rd_addr_o(rd),.trace_rd_data_o(value),.trace_mem_addr_o(addr),
    .trace_mem_wstrb_o(strb),.trace_mem_wdata_o(data),.trace_trap_o(fault),
    .trace_cause_o(),.trace_control_o(),.trace_taken_o(),.trace_target_o(),
    .perf_cycle_o(cycle_count),.perf_instret_o(instret),.perf_load_use_stall_o(stalls),
    .perf_mem_stall_o(mem_stalls),.perf_redirect_o(redirects),.perf_squash_o());
  rv32_delayed_mem #(.DMEM_REQ_DELAY(REQ_DELAY),.DMEM_RSP_DELAY(RSP_DELAY)) u_mem(
    .clk_i(clk),.rst_i(rst),.imem_s(imem),.dmem_s(dmem));
  always #5 clk=~clk;
  initial begin
    clk=0;rst=1;retired=0;stores=0;
    for(int i=0;i<512;i++) u_mem.mem[i]=TB_NOP;
    // RAW chain, store-data forwarding, load-use, taken branch squash, JAL link.
    u_mem.mem[0]=enc_addi(1,0,12'd5);
    u_mem.mem[1]=enc_addi(2,1,12'd7);
    u_mem.mem[2]=enc_add(3,1,2);
    u_mem.mem[3]=enc_sw(3,0,12'h400);
    u_mem.mem[4]=enc_lw(4,0,12'h400);
    u_mem.mem[5]=enc_add(5,4,2);
    u_mem.mem[6]=enc_branch(FUNCT3_BEQ,5,5,13'd12);
    u_mem.mem[7]=enc_sw(0,0,12'h400); // Must never issue.
    u_mem.mem[8]=32'hffffffff; // Wrong-path fault must never commit.
    u_mem.mem[9]=enc_jal(6,21'd12);
    u_mem.mem[10]=enc_sw(0,0,12'h400);
    u_mem.mem[11]=enc_addi(5,0,12'd99);
    u_mem.mem[12]=enc_add(7,6,5); // 40 + 29 = 69
    u_mem.mem[13]=enc_sw(7,0,12'h404);
    u_mem.mem[14]=enc_addi(0,0,12'd77);
    u_mem.mem[15]=enc_addi(8,0,12'd31);
    if(SCENARIO==1) begin
      u_mem.mem[16]=32'h02000033; // Unsupported OP; younger store blocked.
      u_mem.mem[17]=enc_sw(0,0,12'h404);
    end else u_mem.mem[16]=enc_sw(8,0,12'h408);
    repeat(5) @(negedge clk);rst=0;
  end
  always @(posedge clk) if(!rst) begin
    if(cycle_count>2000) $fatal(1,"directed timeout");
    if(instret!=64'(retired)) $fatal(1,"retirement counter mismatch");
    if(valid && !fault) begin
      retired++;
      if(pc==28 || pc==32 || pc==40 || pc==44) $fatal(1,"wrong-path retirement");
      if(strb!=0) stores++;
      if(rd_we && rd==0) $fatal(1,"x0 write");
      if(addr==32'h408 && strb==4'hf) begin
        if(u_mem.mem[256]!=17 || u_mem.mem[257]!=69 || data!=31 || stores!=3 || redirects!=2) $fatal(1,"pipeline signature");
        $display("PASS: pipeline forwarding, load/store, redirects, x0 delay=%0d/%0d",REQ_DELAY,RSP_DELAY);$finish;
      end
    end
    if(valid && fault) begin
      if(SCENARIO!=1 || pc!=64 || stores!=2 || u_mem.mem[257]!=69) $fatal(1,"fault ordering");
      fork begin
        repeat(10) @(negedge clk);
        if(u_mem.mem[257]!=69 || valid || dmem.req_valid || !dut.fault_pending) $fatal(1,"fault-stop younger side effect");
        $display("PASS: unsupported instruction stops with no younger store");$finish;
      end join_none
    end
  end
endmodule
