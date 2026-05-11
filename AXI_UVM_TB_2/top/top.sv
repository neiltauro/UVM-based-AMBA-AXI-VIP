// =============================================================================
// top.sv  –  Testbench top module
// Single AXI interface shared by the master and slave agents.
// =============================================================================
module top;
  import uvm_pkg::*;
  import Axi_pkg::*;

  bit ACLK;
  always #5 ACLK = ~ACLK;   // 100 MHz clock

  axi axi_bus (ACLK);

  initial begin
    `ifdef VCS
      $fsdbDumpvars(0, top);
    `endif

    uvm_config_db #(virtual axi)::set(null, "*", "axi", axi_bus);
    uvm_top.enable_print_topology = 1;
    run_test();
  end

endmodule
