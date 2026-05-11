// =============================================================================
// slave_driver.sv  (FIXED)
//
// Key fixes:
//  1. R channel serialised via rd_channel_sem so only one rd_data_send
//     thread drives RVALID/RDATA/RID at a time.  AR acceptance remains
//     parallel (fork/join_none per AR), but rd_data_send acquires the
//     semaphore before driving beats and releases it after RLAST.
//     Without this, concurrent rd_data_send threads contend on the same
//     physical signal wires causing random beat drops.
//  2. All VALID checks use !== 1'b1 / === 1'b1 (4-state X-safe).
// =============================================================================
class slave_driver extends uvm_driver #(axi_xtn);
  `uvm_component_utils(slave_driver)

  virtual axi.S_DRV vif;
  s_config          s_cfg;

  // Byte-addressed slave memory
  int unsigned smem [int unsigned];

  // Serialises R-channel beat driving across concurrent read transactions.
  // AR acceptance is still fully parallel – only the actual RDATA driving
  // is serialised, which is correct because the physical R channel is shared.
  semaphore rd_channel_sem;

  function new(string name = "slave_driver", uvm_component parent);
    super.new(name, parent);
    rd_channel_sem = new(1);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db #(s_config)::get(this, "", "s_config", s_cfg))
      `uvm_fatal(get_type_name(), "Cannot get s_config")
  endfunction

  function void connect_phase(uvm_phase phase);
    vif = s_cfg.vif;
  endfunction

  task run_phase(uvm_phase phase);
    vif.s_drv.AWREADY <= 0;
    vif.s_drv.WREADY  <= 0;
    vif.s_drv.BVALID  <= 0;
    vif.s_drv.BRESP   <= 2'b00;
    vif.s_drv.BID     <= 0;
    vif.s_drv.ARREADY <= 0;
    vif.s_drv.RVALID  <= 0;
    vif.s_drv.RDATA   <= 0;
    vif.s_drv.RRESP   <= 2'b00;
    vif.s_drv.RLAST   <= 0;
    vif.s_drv.RID     <= 0;

    fork
      forever wr_channel();
      forever rd_channel();
    join
  endtask

  // ------------------------------------------------------------------
  // Write channel: accept AW → spawn data+response thread
  // ------------------------------------------------------------------
  task wr_channel();
    axi_xtn wxtn;

    @(vif.s_drv);
    while (vif.s_drv.AWVALID !== 1'b1) @(vif.s_drv);

    repeat ($urandom_range(0, 3)) @(vif.s_drv);

    wxtn         = axi_xtn::type_id::create("s_wxtn");
    wxtn.AWID    = vif.s_drv.AWID;
    wxtn.AWADDR  = vif.s_drv.AWADDR;
    wxtn.AWLEN   = vif.s_drv.AWLEN;
    wxtn.AWSIZE  = vif.s_drv.AWSIZE;
    wxtn.AWBURST = vif.s_drv.AWBURST;
    wxtn.w_addr_calc();

    vif.s_drv.AWREADY <= 1;
    @(vif.s_drv);
    vif.s_drv.AWREADY <= 0;

    `uvm_info(get_type_name(),
      $sformatf("SLV WR_ADDR: AWID=%0h AWADDR=0x%08h AWBURST=%0d AWLEN=%0d",
                wxtn.AWID, wxtn.AWADDR, wxtn.AWBURST, wxtn.AWLEN), UVM_HIGH)

    fork
      automatic axi_xtn wx = wxtn;
      wr_data_and_resp(wx);
    join_none
  endtask

  // ------------------------------------------------------------------
  task wr_data_and_resp(axi_xtn xtn);
    for (int i = 0; i <= xtn.AWLEN; i++) begin
      @(vif.s_drv);
      while (!(vif.s_drv.WVALID === 1'b1 && vif.s_drv.WID === xtn.AWID))
        @(vif.s_drv);

      case (vif.s_drv.WSTRB)
        4'b1111: smem[xtn.waddr[i]] = vif.s_drv.WDATA;
        4'b1000: smem[xtn.waddr[i]] = vif.s_drv.WDATA[31:24];
        4'b0100: smem[xtn.waddr[i]] = vif.s_drv.WDATA[23:16];
        4'b0010: smem[xtn.waddr[i]] = vif.s_drv.WDATA[15:8];
        4'b0001: smem[xtn.waddr[i]] = vif.s_drv.WDATA[7:0];
        4'b1100: smem[xtn.waddr[i]] = vif.s_drv.WDATA[31:16];
        4'b0011: smem[xtn.waddr[i]] = vif.s_drv.WDATA[15:0];
        4'b0110: smem[xtn.waddr[i]] = vif.s_drv.WDATA[23:8];
        4'b1110: smem[xtn.waddr[i]] = vif.s_drv.WDATA[31:8];
        4'b0111: smem[xtn.waddr[i]] = vif.s_drv.WDATA[23:0];
        default: smem[xtn.waddr[i]] = vif.s_drv.WDATA;
      endcase

      repeat ($urandom_range(0, 3)) @(vif.s_drv);
      vif.s_drv.WREADY <= 1;
      @(vif.s_drv);
      vif.s_drv.WREADY <= 0;

      `uvm_info(get_type_name(),
        $sformatf("SLV WR_DATA[%0d]: addr=0x%08h data=0x%08h strb=%04b",
                  i, xtn.waddr[i], smem[xtn.waddr[i]], vif.s_drv.WSTRB), UVM_HIGH)
    end

    repeat ($urandom_range(1, 4)) @(vif.s_drv);
    @(vif.s_drv);
    vif.s_drv.BID    <= xtn.AWID;
    vif.s_drv.BVALID <= 1;
    vif.s_drv.BRESP  <= 2'b00;
    @(vif.s_drv);
    while (vif.s_drv.BREADY !== 1'b1) @(vif.s_drv);
    vif.s_drv.BVALID <= 0;
    vif.s_drv.BID    <= 4'bx;
    vif.s_drv.BRESP  <= 2'bx;

    `uvm_info(get_type_name(),
      $sformatf("SLV WR_RESP: AWID=%0h BRESP=OKAY", xtn.AWID), UVM_HIGH)
  endtask

  // ------------------------------------------------------------------
  // Read channel: accept AR immediately → spawn data thread
  // The data thread queues on rd_channel_sem before driving beats.
  // ------------------------------------------------------------------
  task rd_channel();
    axi_xtn rxtn;

    @(vif.s_drv);
    while (vif.s_drv.ARVALID !== 1'b1) @(vif.s_drv);

    repeat ($urandom_range(0, 3)) @(vif.s_drv);

    rxtn         = axi_xtn::type_id::create("s_rxtn");
    rxtn.ARID    = vif.s_drv.ARID;
    rxtn.ARADDR  = vif.s_drv.ARADDR;
    rxtn.ARLEN   = vif.s_drv.ARLEN;
    rxtn.ARSIZE  = vif.s_drv.ARSIZE;
    rxtn.ARBURST = vif.s_drv.ARBURST;
    rxtn.r_addr_calc();
    rxtn.r_strobe_calc();
    rxtn.RDATA   = new[rxtn.ARLEN + 1];

    vif.s_drv.ARREADY <= 1;
    @(vif.s_drv);
    vif.s_drv.ARREADY <= 0;

    `uvm_info(get_type_name(),
      $sformatf("SLV RD_ADDR: ARID=%0h ARADDR=0x%08h ARBURST=%0d ARLEN=%0d",
                rxtn.ARID, rxtn.ARADDR, rxtn.ARBURST, rxtn.ARLEN), UVM_HIGH)

    // Spawn data thread – it will wait on rd_channel_sem before driving
    fork
      automatic axi_xtn rx = rxtn;
      rd_data_send(rx);
    join_none
  endtask

  // ------------------------------------------------------------------
  // Drive R beats for one read.
  // Acquires rd_channel_sem so only one instance drives R signals at a time.
  // ------------------------------------------------------------------
  task rd_data_send(axi_xtn xtn);
    // Wait for our turn to use the R channel
    rd_channel_sem.get(1);

    repeat ($urandom_range(1, 3)) @(vif.s_drv);

    for (int i = 0; i <= xtn.ARLEN; i++) begin
      int unsigned rdata_val;
      @(vif.s_drv);

      rdata_val = smem.exists(xtn.raddr[i]) ? smem[xtn.raddr[i]] : xtn.raddr[i];

      vif.s_drv.RID    <= xtn.ARID;
      vif.s_drv.RVALID <= 1;
      vif.s_drv.RDATA  <= rdata_val;
      vif.s_drv.RRESP  <= 2'b00;
      vif.s_drv.RLAST  <= (i == xtn.ARLEN);

      @(vif.s_drv);
      while (vif.s_drv.RREADY !== 1'b1) @(vif.s_drv);

      vif.s_drv.RVALID <= 0;
      vif.s_drv.RDATA  <= 'bx;
      vif.s_drv.RLAST  <= 0;

      `uvm_info(get_type_name(),
        $sformatf("SLV RD_DATA[%0d]: ARID=%0h addr=0x%08h data=0x%08h",
                  i, xtn.ARID, xtn.raddr[i], rdata_val), UVM_HIGH)

      repeat ($urandom_range(0, 2)) @(vif.s_drv);
    end

    // Release R channel for the next queued read
    rd_channel_sem.put(1);
  endtask

endclass