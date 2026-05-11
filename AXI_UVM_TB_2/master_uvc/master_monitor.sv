// =============================================================================
// master_monitor.sv  (FIXED)
//
// Fix 1: rd_addr_mon now spawns a dedicated rd_beats_mon thread per read
//        immediately after capturing the AR handshake.  This eliminates the
//        race condition where the single rd_data_mon thread missed beat 0
//        of real reads because it was still processing a spurious read.
//
// Fix 2: All VALID/READY checks use === 1 (4-state safe) so X values at
//        simulation start do not cause spurious captures.
//
// Run phase no longer forks a forever rd_data_mon – beats are collected
// by per-read threads spawned from rd_addr_mon.
// =============================================================================
class master_monitor extends uvm_monitor;
  `uvm_component_utils(master_monitor)

  uvm_analysis_port #(axi_xtn) analysis_port_wr;
  uvm_analysis_port #(axi_xtn) analysis_port_rd;

  virtual axi.M_MON vif;
  m_config          m_cfg;

  axi_xtn wr_inflight [bit[3:0]];
  axi_xtn rd_inflight [bit[3:0]];

  semaphore wr_sem;
  semaphore rd_sem;

  function new(string name = "master_monitor", uvm_component parent);
    super.new(name, parent);
    analysis_port_wr = new("analysis_port_wr", this);
    analysis_port_rd = new("analysis_port_rd", this);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db #(m_config)::get(this, "", "m_config", m_cfg))
      `uvm_fatal(get_type_name(), "Cannot get m_config")
    wr_sem = new(1);
    rd_sem = new(1);
  endfunction

  function void connect_phase(uvm_phase phase);
    vif = m_cfg.vif;
  endfunction

  task run_phase(uvm_phase phase);
    fork
      forever wr_addr_mon();
      forever wr_data_mon();
      forever wr_resp_mon();
      forever rd_addr_mon();
      // NOTE: rd_data collection is spawned per-read inside rd_addr_mon
    join
  endtask

  // ------------------------------------------------------------------
  // Write address monitor
  // ------------------------------------------------------------------
  task wr_addr_mon();
    axi_xtn xtn;
    @(vif.m_mon);
    while (!(vif.m_mon.AWVALID === 1 && vif.m_mon.AWREADY === 1)) @(vif.m_mon);

    xtn         = axi_xtn::type_id::create("m_wr_xtn");
    xtn.is_read = 0;
    xtn.AWID    = vif.m_mon.AWID;
    xtn.AWADDR  = vif.m_mon.AWADDR;
    xtn.AWLEN   = vif.m_mon.AWLEN;
    xtn.AWSIZE  = vif.m_mon.AWSIZE;
    xtn.AWBURST = vif.m_mon.AWBURST;
    xtn.WDATA   = new[xtn.AWLEN + 1];
    xtn.WSTRB   = new[xtn.AWLEN + 1];
    xtn.w_addr_calc();

    wr_sem.get(1);
    wr_inflight[xtn.AWID] = xtn;
    wr_sem.put(1);

    `uvm_info(get_type_name(),
      $sformatf("MON WR_ADDR: AWID=%0h AWADDR=0x%08h AWBURST=%0d AWLEN=%0d",
                xtn.AWID, xtn.AWADDR, xtn.AWBURST, xtn.AWLEN), UVM_HIGH)
  endtask

  // ------------------------------------------------------------------
  // Write data monitor
  // ------------------------------------------------------------------
  task wr_data_mon();
    bit [3:0] wid;
    int       beat;
    axi_xtn   xtn;

    @(vif.m_mon);
    while (!(vif.m_mon.WVALID === 1 && vif.m_mon.WREADY === 1)) @(vif.m_mon);
    wid = vif.m_mon.WID;

    wr_sem.get(1);
    while (!wr_inflight.exists(wid)) begin
      wr_sem.put(1); @(vif.m_mon); wr_sem.get(1);
    end
    xtn = wr_inflight[wid];
    wr_sem.put(1);

    beat = 0;
    while (beat <= xtn.AWLEN) begin
      if (vif.m_mon.WVALID === 1 && vif.m_mon.WREADY === 1 && vif.m_mon.WID === wid) begin
        xtn.WSTRB[beat] = vif.m_mon.WSTRB;
        case (vif.m_mon.WSTRB)
          4'b1111: xtn.WDATA[beat] = vif.m_mon.WDATA;
          4'b1000: xtn.WDATA[beat] = {vif.m_mon.WDATA[31:24], 24'b0};
          4'b0100: xtn.WDATA[beat] = {8'b0, vif.m_mon.WDATA[23:16], 16'b0};
          4'b0010: xtn.WDATA[beat] = {16'b0, vif.m_mon.WDATA[15:8], 8'b0};
          4'b0001: xtn.WDATA[beat] = {24'b0, vif.m_mon.WDATA[7:0]};
          4'b1100: xtn.WDATA[beat] = {vif.m_mon.WDATA[31:16], 16'b0};
          4'b0011: xtn.WDATA[beat] = {16'b0, vif.m_mon.WDATA[15:0]};
          4'b0110: xtn.WDATA[beat] = {8'b0, vif.m_mon.WDATA[23:8], 8'b0};
          4'b1110: xtn.WDATA[beat] = {vif.m_mon.WDATA[31:8], 8'b0};
          4'b0111: xtn.WDATA[beat] = {8'b0, vif.m_mon.WDATA[23:0]};
          default: xtn.WDATA[beat] = vif.m_mon.WDATA;
        endcase
        if (beat == xtn.AWLEN) xtn.WLAST = vif.m_mon.WLAST;
        beat++;
      end
      if (beat <= xtn.AWLEN) @(vif.m_mon);
    end
  endtask

  // ------------------------------------------------------------------
  // Write response monitor – publishes on analysis_port_wr
  // ------------------------------------------------------------------
  task wr_resp_mon();
    bit [3:0] bid;
    axi_xtn   xtn;

    @(vif.m_mon);
    while (!(vif.m_mon.BVALID === 1 && vif.m_mon.BREADY === 1)) @(vif.m_mon);
    bid = vif.m_mon.BID;

    wr_sem.get(1);
    while (!wr_inflight.exists(bid)) begin
      wr_sem.put(1); @(vif.m_mon); wr_sem.get(1);
    end
    xtn = wr_inflight[bid];
    wr_inflight.delete(bid);
    wr_sem.put(1);

    xtn.BID    = vif.m_mon.BID;
    xtn.BRESP  = vif.m_mon.BRESP;
    xtn.BVALID = 1; xtn.BREADY = 1;

    `uvm_info(get_type_name(),
      $sformatf("MON WR_RESP: AWID=%0h BRESP=%0b", xtn.AWID, xtn.BRESP), UVM_LOW)
    analysis_port_wr.write(xtn);
  endtask

  // ------------------------------------------------------------------
  // Read address monitor
  // Spawns a dedicated rd_beats_mon thread per read immediately after
  // capturing AR – guarantees the collector is live before beat 0 arrives.
  // ------------------------------------------------------------------
  task rd_addr_mon();
    axi_xtn xtn;

    @(vif.m_mon);
    while (!(vif.m_mon.ARVALID === 1 && vif.m_mon.ARREADY === 1)) @(vif.m_mon);

    xtn         = axi_xtn::type_id::create("m_rd_xtn");
    xtn.is_read = 1;
    xtn.ARID    = vif.m_mon.ARID;
    xtn.ARADDR  = vif.m_mon.ARADDR;
    xtn.ARLEN   = vif.m_mon.ARLEN;
    xtn.ARSIZE  = vif.m_mon.ARSIZE;
    xtn.ARBURST = vif.m_mon.ARBURST;
    xtn.ARVALID = 1;
    xtn.ARREADY = 1;
    xtn.RDATA   = new[xtn.ARLEN + 1];
    xtn.r_addr_calc();
    xtn.r_strobe_calc();

    rd_sem.get(1);
    rd_inflight[xtn.ARID] = xtn;
    rd_sem.put(1);

    `uvm_info(get_type_name(),
      $sformatf("MON RD_ADDR: ARID=%0h ARADDR=0x%08h ARBURST=%0d ARLEN=%0d",
                xtn.ARID, xtn.ARADDR, xtn.ARBURST, xtn.ARLEN), UVM_HIGH)

    // Spawn dedicated beat collector for this read right away.
    // Because it starts immediately after AR, it can never miss beat 0.
    fork
      automatic axi_xtn rx = xtn;
      rd_beats_mon(rx);
    join_none
  endtask

  // ------------------------------------------------------------------
  // Read beat collector – one instance per read transaction
  // Started by rd_addr_mon; collects all R beats then publishes.
  // ------------------------------------------------------------------
  task rd_beats_mon(axi_xtn xtn);
    int beat = 0;

    @(vif.m_mon);   // advance one clock from the AR handshake edge
    while (beat <= xtn.ARLEN) begin
      if (vif.m_mon.RVALID === 1 && vif.m_mon.RREADY === 1 &&
          vif.m_mon.RID     === xtn.ARID) begin
        case (xtn.RSTRB[beat])
          4'b1111: xtn.RDATA[beat] = vif.m_mon.RDATA;
          4'b1000: xtn.RDATA[beat] = {vif.m_mon.RDATA[31:24], 24'b0};
          4'b0100: xtn.RDATA[beat] = {8'b0, vif.m_mon.RDATA[23:16], 16'b0};
          4'b0010: xtn.RDATA[beat] = {16'b0, vif.m_mon.RDATA[15:8], 8'b0};
          4'b0001: xtn.RDATA[beat] = {24'b0, vif.m_mon.RDATA[7:0]};
          4'b1100: xtn.RDATA[beat] = {vif.m_mon.RDATA[31:16], 16'b0};
          4'b0011: xtn.RDATA[beat] = {16'b0, vif.m_mon.RDATA[15:0]};
          4'b0110: xtn.RDATA[beat] = {8'b0, vif.m_mon.RDATA[23:8], 8'b0};
          4'b1110: xtn.RDATA[beat] = {vif.m_mon.RDATA[31:8], 8'b0};
          4'b0111: xtn.RDATA[beat] = {8'b0, vif.m_mon.RDATA[23:0]};
          default: xtn.RDATA[beat] = vif.m_mon.RDATA;
        endcase
        if (beat == xtn.ARLEN) xtn.RLAST = vif.m_mon.RLAST;
        beat++;
      end
      if (beat <= xtn.ARLEN) @(vif.m_mon);
    end

    rd_sem.get(1);
    rd_inflight.delete(xtn.ARID);
    rd_sem.put(1);

    `uvm_info(get_type_name(),
      $sformatf("MON RD_DATA: ARID=%0h beats=%0d", xtn.ARID, xtn.ARLEN+1), UVM_LOW)
    analysis_port_rd.write(xtn);
  endtask

endclass