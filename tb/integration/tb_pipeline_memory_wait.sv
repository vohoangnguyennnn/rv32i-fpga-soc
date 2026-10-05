module tb_pipeline_memory_wait;
  rv32_pipeline_test #(.REQ_DELAY(3),.RSP_DELAY(7)) test();
endmodule
