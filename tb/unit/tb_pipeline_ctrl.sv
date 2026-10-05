module tb_pipeline_ctrl;
  timeunit 1ns; timeprecision 1ps;
  import rv32_pkg::*;
  logic clk, rst, load_use, mem_wait, id_fault, wb_fault;
  redirect_t redirect;
  logic pc_en, if_en, id_en, ex_en, wb_en, if_flush, id_flush, ex_flush, wb_flush, redir, pending;
  logic [31:0] target;
  always #5 clk=~clk;
  pipeline_ctrl dut(.clk_i(clk),.rst_i(rst),.load_use_i(load_use),.ex_wait_i(1'b0),
    .mem_wait_i(mem_wait),.id_exception_i(id_fault),.ex_exception_i(1'b0),
    .mem_exception_i(1'b0),.wb_fault_i(wb_fault),.control_redirect_i(redirect),
    .pc_enable_o(pc_en),.if_id_enable_o(if_en),.id_ex_enable_o(id_en),
    .ex_mem_enable_o(ex_en),.mem_wb_enable_o(wb_en),.if_id_flush_o(if_flush),
    .id_ex_flush_o(id_flush),.ex_mem_flush_o(ex_flush),.mem_wb_flush_o(wb_flush),
    .redirect_valid_o(redir),.redirect_pc_o(target),.fault_pending_o(pending));
  initial begin
    clk=0;rst=1;load_use=0;mem_wait=0;id_fault=0;wb_fault=0;redirect='0;
    @(negedge clk);rst=0; #1; if(!pc_en || !ex_en) $fatal(1,"advance");
    load_use=1; #1; if(pc_en || if_en || !id_flush || !ex_en) $fatal(1,"load-use bubble");
    redirect.valid=1;redirect.target=32'h80; #1;
    if(!redir || !if_flush || !id_flush || target!=32'h80) $fatal(1,"redirect age priority");
    mem_wait=1; #1; if(redir || id_en || ex_en || !wb_flush) $fatal(1,"memory wait priority");
    mem_wait=0; redirect='0;load_use=0;id_fault=1;
    @(negedge clk);id_fault=0; #1; if(!pending || pc_en || !id_flush) $fatal(1,"fault isolation");
    wb_fault=1; #1; if(!ex_flush || !wb_flush || redir) $fatal(1,"fault halt");
    @(negedge clk); wb_fault=0; #1; if(!pending || pc_en) $fatal(1,"sticky halt");
    $display("PASS: pipeline priorities and fault-stop"); $finish;
  end
endmodule
