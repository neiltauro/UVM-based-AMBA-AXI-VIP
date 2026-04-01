// =============================================================================
// score_board.sv
//
// Simple in-order scoreboard for 1-master / 1-slave.
// Two separate FIFO pairs:
//   m_wr_fifo / s_wr_fifo  – matched write completions
//   m_rd_fifo / s_rd_fifo  – matched read  completions
//
// Checker tasks pop one master xtn and one slave xtn from each FIFO
// in arrival order and compare them. A timeout watchdog fires uvm_fatal
// if a FIFO entry waits too long without a matching pair arriving.
// =============================================================================
class score_board extends uvm_scoreboard;
  `uvm_component_utils(score_board)

  // Analysis FIFOs
  uvm_tlm_analysis_fifo #(axi_xtn) m_wr_fifo;
  uvm_tlm_analysis_fifo #(axi_xtn) s_wr_fifo;
  uvm_tlm_analysis_fifo #(axi_xtn) m_rd_fifo;
  uvm_tlm_analysis_fifo #(axi_xtn) s_rd_fifo;

  a_config cfg;

  int wr_matched,  wr_mismatched;
  int rd_matched,  rd_mismatched;
  int wr_total,    rd_total;

  // Coverage sample handle
  axi_xtn cov_xtn;

  // ------------------------------------------------------------------
  // Coverage groups
  // ------------------------------------------------------------------
  covergroup wr_addr_cov;
    AWSIZE  : coverpoint cov_xtn.AWSIZE  {bins sz[]  = {0,1,2};}
    AWBURST : coverpoint cov_xtn.AWBURST {bins bst[] = {0,1,2};
                                           illegal_bins res = {3};}
    AWLEN   : coverpoint cov_xtn.AWLEN   {bins len = {[0:15]};}
    SxBxL   : cross AWSIZE, AWBURST, AWLEN;
  endgroup

  covergroup rd_addr_cov;
    ARSIZE  : coverpoint cov_xtn.ARSIZE  {bins sz[]  = {0,1,2};}
    ARBURST : coverpoint cov_xtn.ARBURST {bins bst[] = {0,1,2};
                                           illegal_bins res = {3};}
    ARLEN   : coverpoint cov_xtn.ARLEN   {bins len = {[0:15]};}
    SxBxL   : cross ARSIZE, ARBURST, ARLEN;
  endgroup

  covergroup wr_data_cov with function sample(int i);
    WSTRB : coverpoint cov_xtn.WSTRB[i] {
      bins all_bytes  = {4'b1111};
      bins byte0      = {4'b0001};
      bins byte1      = {4'b0010};
      bins byte2      = {4'b0100};
      bins byte3      = {4'b1000};
      bins low_half   = {4'b0011};
      bins high_half  = {4'b1100};
    }
  endgroup

  covergroup rd_data_cov with function sample(int i);
    RDATA : coverpoint cov_xtn.RDATA[i] {bins data = {[32'h0:32'hFFFF_FFFF]};}
  endgroup

  // ------------------------------------------------------------------
  function new(string name = "score_board", uvm_component parent);
    super.new(name, parent);
    wr_addr_cov = new;
    rd_addr_cov = new;
    wr_data_cov = new;
    rd_data_cov = new;
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db #(a_config)::get(this, "", "a_config", cfg))
      `uvm_fatal(get_type_name(), "Cannot get a_config")

    m_wr_fifo = new("m_wr_fifo", this);
    s_wr_fifo = new("s_wr_fifo", this);
    m_rd_fifo = new("m_rd_fifo", this);
    s_rd_fifo = new("s_rd_fifo", this);
  endfunction

  // ------------------------------------------------------------------
  // run_phase: checkers run detached; test controls simulation end
  // ------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    fork
      wr_checker();
      rd_checker();
      wr_watchdog();
      rd_watchdog();
    join_none
  endtask

  // ------------------------------------------------------------------
  // Write checker
  // ------------------------------------------------------------------
  task wr_checker();
    axi_xtn m_xtn, s_xtn;
    forever begin
      m_wr_fifo.get(m_xtn);
      wr_total++;
      s_wr_fifo.get(s_xtn);

      `uvm_info(get_type_name(),
        $sformatf("WRITE compare: AWID=%0h AWADDR=0x%08h AWBURST=%0d AWLEN=%0d",
                  m_xtn.AWID, m_xtn.AWADDR, m_xtn.AWBURST, m_xtn.AWLEN), UVM_LOW)

      if (!m_xtn.compare(s_xtn)) begin
        wr_mismatched++;
        `uvm_error(get_type_name(),
          $sformatf("WRITE MISMATCH: AWID=%0h AWADDR=0x%08h\n  Master:\n%s\n  Slave:\n%s",
                    m_xtn.AWID, m_xtn.AWADDR, m_xtn.sprint(), s_xtn.sprint()))
      end else begin
        wr_matched++;
        `uvm_info(get_type_name(),
          $sformatf("WRITE MATCH: AWID=%0h AWADDR=0x%08h AWBURST=%0d",
                    m_xtn.AWID, m_xtn.AWADDR, m_xtn.AWBURST), UVM_LOW)
        cov_xtn = m_xtn;
        wr_addr_cov.sample();
        foreach (m_xtn.WDATA[i]) wr_data_cov.sample(i);
      end
    end
  endtask

  // ------------------------------------------------------------------
  // Read checker
  // ------------------------------------------------------------------
  task rd_checker();
    axi_xtn m_xtn, s_xtn;
    forever begin
      m_rd_fifo.get(m_xtn);
      rd_total++;
      s_rd_fifo.get(s_xtn);

      `uvm_info(get_type_name(),
        $sformatf("READ  compare: ARID=%0h ARADDR=0x%08h ARBURST=%0d ARLEN=%0d",
                  m_xtn.ARID, m_xtn.ARADDR, m_xtn.ARBURST, m_xtn.ARLEN), UVM_LOW)

      if (!m_xtn.compare(s_xtn)) begin
        rd_mismatched++;
        `uvm_error(get_type_name(),
          $sformatf("READ  MISMATCH: ARID=%0h ARADDR=0x%08h\n  Master:\n%s\n  Slave:\n%s",
                    m_xtn.ARID, m_xtn.ARADDR, m_xtn.sprint(), s_xtn.sprint()))
      end else begin
        rd_matched++;
        `uvm_info(get_type_name(),
          $sformatf("READ  MATCH: ARID=%0h ARADDR=0x%08h ARBURST=%0d",
                    m_xtn.ARID, m_xtn.ARADDR, m_xtn.ARBURST), UVM_LOW)
        cov_xtn = m_xtn;
        rd_addr_cov.sample();
        foreach (m_xtn.RDATA[i]) rd_data_cov.sample(i);
      end
    end
  endtask

  // ------------------------------------------------------------------
  // Watchdog: fires uvm_fatal if a FIFO entry stalls past timeout
  // ------------------------------------------------------------------
  task wr_watchdog();
    forever begin
      @(posedge cfg.m_cfg[0].vif.ACLK);
      if (m_wr_fifo.used() > 0 || s_wr_fifo.used() > 0) begin
        // Wait up to sb_timeout_cycles for the matching side
        repeat (cfg.sb_timeout_cycles) @(posedge cfg.m_cfg[0].vif.ACLK);
        if (m_wr_fifo.used() > 0 && s_wr_fifo.used() == 0)
          `uvm_fatal(get_type_name(),
            "WRITE TIMEOUT: master write observation has no matching slave response")
        if (s_wr_fifo.used() > 0 && m_wr_fifo.used() == 0)
          `uvm_fatal(get_type_name(),
            "WRITE TIMEOUT: slave write observation has no matching master request")
      end
    end
  endtask

  task rd_watchdog();
    forever begin
      @(posedge cfg.m_cfg[0].vif.ACLK);
      if (m_rd_fifo.used() > 0 || s_rd_fifo.used() > 0) begin
        repeat (cfg.sb_timeout_cycles) @(posedge cfg.m_cfg[0].vif.ACLK);
        if (m_rd_fifo.used() > 0 && s_rd_fifo.used() == 0)
          `uvm_fatal(get_type_name(),
            "READ  TIMEOUT: master read  observation has no matching slave response")
        if (s_rd_fifo.used() > 0 && m_rd_fifo.used() == 0)
          `uvm_fatal(get_type_name(),
            "READ  TIMEOUT: slave read  observation has no matching master request")
      end
    end
  endtask

  // ------------------------------------------------------------------
  // Report
  // ------------------------------------------------------------------
  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf({
      "\n\n============================================\n",
      "  AXI VIP SCOREBOARD REPORT\n",
      "============================================\n",
      "  Write seen      : %0d\n",
      "  Write matched   : %0d\n",
      "  Write mismatched: %0d\n",
      "--------------------------------------------\n",
      "  Read  seen      : %0d\n",
      "  Read  matched   : %0d\n",
      "  Read  mismatched: %0d\n",
      "============================================\n\n"},
      wr_total, wr_matched, wr_mismatched,
      rd_total,  rd_matched,  rd_mismatched), UVM_LOW)

    if (wr_mismatched > 0 || rd_mismatched > 0)
      `uvm_error(get_type_name(), "TEST FAILED – mismatches detected")
    else
      `uvm_info(get_type_name(), "TEST PASSED – all transactions matched", UVM_LOW)
  endfunction

endclass
