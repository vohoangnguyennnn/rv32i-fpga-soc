module hazard_unit (
  input  logic                         id_valid_i,
  input  logic [4:0]                   id_rs1_i,
  input  logic [4:0]                   id_rs2_i,
  input  wire rv32_pkg::decode_ctrl_t  id_ctrl_i,

  input  wire rv32_pkg::id_ex_t        id_ex_i,

  output logic                         load_use_o,
  output logic                         stall_id_o
);

  import rv32_pkg::*;

  logic id_ex_is_load;

  function automatic logic raw_match(
    input logic      producer_valid,
    input logic      producer_writes,
    input reg_addr_t producer_rd,
    input logic      consumer_uses,
    input reg_addr_t consumer_rs
  );
    begin
      raw_match = producer_valid && producer_writes && (producer_rd != 5'd0) && consumer_uses && (producer_rd == consumer_rs);
    end
  endfunction

  always_comb begin
    id_ex_is_load = id_ex_i.valid && !id_ex_i.exc.valid && id_ex_i.ctrl.reg_write && (id_ex_i.ctrl.mem_cmd == MEM_LOAD);

    load_use_o = 1'b0;
    if (id_valid_i) begin
      load_use_o = raw_match(
        id_ex_is_load,
        id_ex_i.ctrl.reg_write,
        id_ex_i.rd,
        id_ctrl_i.uses_rs1,
        id_rs1_i
      ) || raw_match(
        id_ex_is_load,
        id_ex_i.ctrl.reg_write,
        id_ex_i.rd,
        id_ctrl_i.uses_rs2,
        id_rs2_i
      );
    end

    stall_id_o = load_use_o;
  end
endmodule
