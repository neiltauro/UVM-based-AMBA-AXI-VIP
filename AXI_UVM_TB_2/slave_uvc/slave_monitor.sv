// =============================================================================
// slave_monitor.sv  (FIXED)
// Same fixes as master_monitor: fork-per-read + === 1 checks.
// =============================================================================
class slave_monitor extends uvm_monitor;
  `uvm_component_utils(slave_monitor)

  uvm_analysis_port #(axi_xtn) analysis_port_wr;
  uvm_analysis_port #(axi_xtn) analysis_port_rd;

  virtual axi.S_MON vif;
  s_config          s_cfg;

  axi_xtn wr_inflight [bit[3:0]];
  axi_xtn rd_inflight [bit[3:0]];

  semaphore wr_sem;
  semaphore rd_sem;

  function new(string name = "slave_monitor", uvm_component parent);
    super.new(name, parent);
    analysis_port_wr = new("analysis_port_wr", this);
    analysis_port_rd = new("analysis_port_rd", this);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db #(s_config)::get(this, "", "s_config", s_cfg))
      `uvm_fatal(get_type_name(), "Cannot get s_config")
    wr_sem = new(1);
    rd_sem = new(1);
  endfunction

  function void connect_phase(uvm_phase phase);
    vif = s_cfg.vif;
  endfunction

  task run_phase(uvm_phase phase);
    fork
      forever wr_addr_mon();
      forever wr_data_mon();
      forever wr_resp_mon();
      forever rd_addr_mon();
      // rd beat collection spawned per-read inside rd_addr_mon
    join
  endtask

  // ------------------------------------------------------------------
  task wr_addr_mon();
    axi_xtn xtn;
    @(vif.s_mon);
    while (!(vif.s_mon.AWVALID === 1 && vif.s_mon.AWREADY === 1)) @(vif.s_mon);

    xtn         = axi_xtn::type_id::create("s_wr_xtn");
    xtn.is_read = 0;
    xtn.AWID    = vif.s_mon.AWID;
    xtn.AWADDR  = vif.s_mon.AWADDR;
    xtn.AWLEN   = vif.s_mon.AWLEN;
    xtn.AWSIZE  = vif.s_mon.AWSIZE;
    xtn.AWBURST = vif.s_mon.AWBURST;
    xtn.WDATA   = new[xtn.AWLEN + 1];
    xtn.WSTRB   = new[xtn.AWLEN + 1];
    xtn.w_addr_calc();

    wr_sem.get(1);
    wr_inflight[xtn.AWID] = xtn;
    wr_sem.put(1);
  endtask

  // ------------------------------------------------------------------
  task wr_data_mon();
    bit [3:0] wid;
    int       beat;
    axi_xtn   xtn;

    @(vif.s_mon);
    while (!(vif.s_mon.WVALID === 1 && vif.s_mon.WREADY === 1)) @(vif.s_mon);
    wid = vif.s_mon.WID;

    wr_sem.get(1);
    while (!wr_inflight.exists(wid)) begin
      wr_sem.put(1); @(vif.s_mon); wr_sem.get(1);
    end
    xtn = wr_inflight[wid];
    wr_sem.put(1);

    beat = 0;
    while (beat <= xtn.AWLEN) begin
      if (vif.s_mon.WVALID === 1 && vif.s_mon.WREADY === 1 && vif.s_mon.WID === wid) begin
        xtn.WSTRB[beat] = vif.s_mon.WSTRB;
        case (vif.s_mon.WSTRB)
          4'b1111: xtn.WDATA[beat] = vif.s_mon.WDATA;
          4'b1000: xtn.WDATA[beat] = {vif.s_mon.WDATA[31:24], 24'b0};
          4'b0100: xtn.WDATA[beat] = {8'b0, vif.s_mon.WDATA[23:16], 16'b0};
          4'b0010: xtn.WDATA[beat] = {16'b0, vif.s_mon.WDATA[15:8], 8'b0};
          4'b0001: xtn.WDATA[beat] = {24'b0, vif.s_mon.WDATA[7:0]};
          4'b1100: xtn.WDATA[beat] = {vif.s_mon.WDATA[31:16], 16'b0};
          4'b0011: xtn.WDATA[beat] = {16'b0, vif.s_mon.WDATA[15:0]};
          4'b0110: xtn.WDATA[beat] = {8'b0, vif.s_mon.WDATA[23:8], 8'b0};
          4'b1110: xtn.WDATA[beat] = {vif.s_mon.WDATA[31:8], 8'b0};
          4'b0111: xtn.WDATA[beat] = {8'b0, vif.s_mon.WDATA[23:0]};
          default: xtn.WDATA[beat] = vif.s_mon.WDATA;
        endcase
        if (beat == xtn.AWLEN) xtn.WLAST = vif.s_mon.WLAST;
        beat++;
      end
      if (beat <= xtn.AWLEN) @(vif.s_mon);
    end
  endtask

  // ------------------------------------------------------------------
  task wr_resp_mon();
    bit [3:0] bid;
    axi_xtn   xtn;

    @(vif.s_mon);
    while (!(vif.s_mon.BVALID === 1 && vif.s_mon.BREADY === 1)) @(vif.s_mon);
    bid = vif.s_mon.BID;

    wr_sem.get(1);
    while (!wr_inflight.exists(bid)) begin
      wr_sem.put(1); @(vif.s_mon); wr_sem.get(1);
    end
    xtn = wr_inflight[bid];
    wr_inflight.delete(bid);
    wr_sem.put(1);

    xtn.BID    = vif.s_mon.BID;
    xtn.BRESP  = vif.s_mon.BRESP;
    xtn.BVALID = 1; xtn.BREADY = 1;

    `uvm_info(get_type_name(),
      $sformatf("SLV MON WR_RESP: AWID=%0h BRESP=%0b", xtn.AWID, xtn.BRESP), UVM_LOW)
    analysis_port_wr.write(xtn);
  endtask

  // ------------------------------------------------------------------
  // Read address monitor – spawns a dedicated beat collector per read
  // ------------------------------------------------------------------
  task rd_addr_mon();
    axi_xtn xtn;

    @(vif.s_mon);
    while (!(vif.s_mon.ARVALID === 1 && vif.s_mon.ARREADY === 1)) @(vif.s_mon);

    xtn         = axi_xtn::type_id::create("s_rd_xtn");
    xtn.is_read = 1;
    xtn.ARID    = vif.s_mon.ARID;
    xtn.ARADDR  = vif.s_mon.ARADDR;
    xtn.ARLEN   = vif.s_mon.ARLEN;
    xtn.ARSIZE  = vif.s_mon.ARSIZE;
    xtn.ARBURST = vif.s_mon.ARBURST;
    xtn.RDATA   = new[xtn.ARLEN + 1];
    xtn.r_addr_calc();
    xtn.r_strobe_calc();

    rd_sem.get(1);
    rd_inflight[xtn.ARID] = xtn;
    rd_sem.put(1);

    fork
      automatic axi_xtn rx = xtn;
      rd_beats_mon(rx);
    join_none
  endtask

  // ------------------------------------------------------------------
  // Read beat collector – one instance per read
  // ------------------------------------------------------------------
  task rd_beats_mon(axi_xtn xtn);
    int beat = 0;

    @(vif.s_mon);
    while (beat <= xtn.ARLEN) begin
      if (vif.s_mon.RVALID === 1 && vif.s_mon.RREADY === 1 &&
          vif.s_mon.RID     === xtn.ARID) begin
        case (xtn.RSTRB[beat])
          4'b1111: xtn.RDATA[beat] = vif.s_mon.RDATA;
          4'b1000: xtn.RDATA[beat] = {vif.s_mon.RDATA[31:24], 24'b0};
          4'b0100: xtn.RDATA[beat] = {8'b0, vif.s_mon.RDATA[23:16], 16'b0};
          4'b0010: xtn.RDATA[beat] = {16'b0, vif.s_mon.RDATA[15:8], 8'b0};
          4'b0001: xtn.RDATA[beat] = {24'b0, vif.s_mon.RDATA[7:0]};
          4'b1100: xtn.RDATA[beat] = {vif.s_mon.RDATA[31:16], 16'b0};
          4'b0011: xtn.RDATA[beat] = {16'b0, vif.s_mon.RDATA[15:0]};
          4'b0110: xtn.RDATA[beat] = {8'b0, vif.s_mon.RDATA[23:8], 8'b0};
          4'b1110: xtn.RDATA[beat] = {vif.s_mon.RDATA[31:8], 8'b0};
          4'b0111: xtn.RDATA[beat] = {8'b0, vif.s_mon.RDATA[23:0]};
          default: xtn.RDATA[beat] = vif.s_mon.RDATA;
        endcase
        if (beat == xtn.ARLEN) xtn.RLAST = vif.s_mon.RLAST;
        beat++;
      end
      if (beat <= xtn.ARLEN) @(vif.s_mon);
    end

    rd_sem.get(1);
    rd_inflight.delete(xtn.ARID);
    rd_sem.put(1);

    `uvm_info(get_type_name(),
      $sformatf("SLV MON RD_DATA: ARID=%0h beats=%0d", xtn.ARID, xtn.ARLEN+1), UVM_LOW)
    analysis_port_rd.write(xtn);
  endtask

endclass