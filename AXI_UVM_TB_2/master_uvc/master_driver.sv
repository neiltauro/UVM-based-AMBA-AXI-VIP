// =============================================================================
// master_driver.sv  (PARALLEL W/R PIPELINES + TRUE OUTSTANDING + ID GUARD)
//
// Architecture
// ─────────────────────────────────────────────────────────────────────────────
//  dispatch_loop()    – gets items from sequencer, enforces ID guard,
//                       routes into wr_mbox or rd_mbox, calls item_done()
//                       immediately (non-blocking to sequencer).
//
//  Write side – THREE independent forever-threads:
//    aw_stage()       – drains wr_mbox; drives AW channel only; hands xtn
//                       to w_mbox as soon as AWREADY is seen.
//    w_stage()        – drains w_mbox; drives all W beats; hands xtn to
//                       b_mbox when WLAST is accepted.
//    b_stage()        – drains b_mbox; asserts BREADY, waits for BVALID;
//                       clears the ID from the inflight table.
//
//  Read side – TWO independent forever-threads:
//    ar_stage()       – drains rd_mbox; drives AR channel; hands xtn to
//                       r_mbox when ARREADY is seen.
//    r_stage()        – drains r_mbox; drives RREADY per beat until RLAST;
//                       clears the ID.
//
// Because each stage is an independent thread, a new AW can be issued while
// W beats from the previous transaction are still on the bus – producing
// genuine multiple-outstanding AXI behaviour visible in waveforms.
//
// ID-reuse guard
// ─────────────────────────────────────────────────────────────────────────────
//  wr_id_inflight[16] – set in dispatch_loop before routing, cleared in
//                       b_stage after BVALID/BREADY.
//  rd_id_inflight[16] – set in dispatch_loop, cleared in r_stage after RLAST.
//  Both shared with a_config for sequence-side guard.
// =============================================================================
class master_driver extends uvm_driver #(axi_xtn);
  `uvm_component_utils(master_driver)

  virtual axi.M_DRV vif;
  m_config          m_cfg;
  a_config          a_cfg;

  // Dispatch → AW / AR
  mailbox #(axi_xtn) wr_mbox;
  mailbox #(axi_xtn) rd_mbox;

  // AW done → W stage
  mailbox #(axi_xtn) w_mbox;

  // W done → B stage
  mailbox #(axi_xtn) b_mbox;

  // AR done → R stage
  mailbox #(axi_xtn) r_mbox;

  // ID inflight trackers
  bit wr_id_inflight [16];
  bit rd_id_inflight [16];

  semaphore wr_id_sem;
  semaphore rd_id_sem;
  semaphore rd_rdy_sem;   // serialises RREADY on the shared R channel

  function new(string name = "master_driver", uvm_component parent);
    super.new(name, parent);
    wr_mbox   = new();
    rd_mbox   = new();
    w_mbox    = new();
    b_mbox    = new();
    r_mbox    = new();
    wr_id_sem  = new(1);
    rd_id_sem  = new(1);
    rd_rdy_sem = new(1);
    foreach (wr_id_inflight[i]) wr_id_inflight[i] = 0;
    foreach (rd_id_inflight[i]) rd_id_inflight[i] = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db #(m_config)::get(this, "", "m_config", m_cfg))
      `uvm_fatal(get_type_name(), "Cannot get m_config")
    if (!uvm_config_db #(a_config)::get(this, "", "a_config", a_cfg))
      `uvm_fatal(get_type_name(), "Cannot get a_config")
    // Share inflight arrays with sequences via a_config
    a_cfg.drv_wr_id_inflight = wr_id_inflight;
    a_cfg.drv_rd_id_inflight = rd_id_inflight;
    a_cfg.drv_wr_id_sem      = wr_id_sem;
    a_cfg.drv_rd_id_sem      = rd_id_sem;
  endfunction

  function void connect_phase(uvm_phase phase);
    vif = m_cfg.vif;
  endfunction

  // ─────────────────────────────────────────────────────────────────────────
  // run_phase
  // ─────────────────────────────────────────────────────────────────────────
  task run_phase(uvm_phase phase);
    vif.m_drv.AWVALID <= 0;  vif.m_drv.AWID    <= 0;
    vif.m_drv.AWADDR  <= 0;  vif.m_drv.AWLEN   <= 0;
    vif.m_drv.AWSIZE  <= 0;  vif.m_drv.AWBURST <= 0;
    vif.m_drv.WVALID  <= 0;  vif.m_drv.WID     <= 0;
    vif.m_drv.WDATA   <= 0;  vif.m_drv.WSTRB   <= 0;
    vif.m_drv.WLAST   <= 0;
    vif.m_drv.BREADY  <= 0;
    vif.m_drv.ARVALID <= 0;  vif.m_drv.ARID    <= 0;
    vif.m_drv.ARADDR  <= 0;  vif.m_drv.ARLEN   <= 0;
    vif.m_drv.ARSIZE  <= 0;  vif.m_drv.ARBURST <= 0;
    vif.m_drv.RREADY  <= 0;

    fork
      dispatch_loop();   // sequencer → wr_mbox / rd_mbox
      aw_stage();        // wr_mbox → AW channel → w_mbox
      w_stage();         // w_mbox  → W  channel → b_mbox
      b_stage();         // b_mbox  → B  channel (BREADY/BVALID)
      ar_stage();        // rd_mbox → AR channel → r_mbox
      r_stage();         // r_mbox  → R  channel (RREADY/RVALID)
    join
  endtask

  // ─────────────────────────────────────────────────────────────────────────
  // Dispatch loop
  // ─────────────────────────────────────────────────────────────────────────
  task dispatch_loop();
    forever begin
      axi_xtn xtn;
      seq_item_port.get_next_item(xtn);

      if (!xtn.is_read) begin
        wr_id_sem.get(1);
        while (wr_id_inflight[xtn.AWID]) begin
          wr_id_sem.put(1);
          `uvm_info(get_type_name(),
            $sformatf("ID GUARD: AWID=%0h in-flight, stalling", xtn.AWID), UVM_MEDIUM)
          @(posedge vif.m_drv);
          wr_id_sem.get(1);
        end
        wr_id_inflight[xtn.AWID]           = 1;
        a_cfg.drv_wr_id_inflight[xtn.AWID] = 1;
        wr_id_sem.put(1);
        wr_mbox.put(xtn);
      end else begin
        rd_id_sem.get(1);
        while (rd_id_inflight[xtn.ARID]) begin
          rd_id_sem.put(1);
          `uvm_info(get_type_name(),
            $sformatf("ID GUARD: ARID=%0h in-flight, stalling", xtn.ARID), UVM_MEDIUM)
          @(posedge vif.m_drv);
          rd_id_sem.get(1);
        end
        rd_id_inflight[xtn.ARID]           = 1;
        a_cfg.drv_rd_id_inflight[xtn.ARID] = 1;
        rd_id_sem.put(1);
        rd_mbox.put(xtn);
      end

      seq_item_port.item_done();
    end
  endtask

  // ─────────────────────────────────────────────────────────────────────────
  // AW stage – issues address only, immediately passes to W stage
  // A new AW can start as soon as the previous AWREADY is received,
  // regardless of whether the W beats have started.
  // ─────────────────────────────────────────────────────────────────────────
  task aw_stage();
    forever begin
      axi_xtn xtn;
      wr_mbox.get(xtn);

      @(vif.m_drv);
      vif.m_drv.AWVALID <= 1;
      vif.m_drv.AWID    <= xtn.AWID;
      vif.m_drv.AWADDR  <= xtn.AWADDR;
      vif.m_drv.AWLEN   <= xtn.AWLEN;
      vif.m_drv.AWSIZE  <= xtn.AWSIZE;
      vif.m_drv.AWBURST <= xtn.AWBURST;

      @(vif.m_drv);
      while (vif.m_drv.AWREADY !== 1'b1) @(vif.m_drv);

      vif.m_drv.AWVALID <= 0;
      vif.m_drv.AWID    <= 4'bx;
      vif.m_drv.AWADDR  <= 'bx;
      vif.m_drv.AWLEN   <= 4'bx;
      vif.m_drv.AWSIZE  <= 3'bx;
      vif.m_drv.AWBURST <= 2'bx;

      `uvm_info(get_type_name(),
        $sformatf("AW done: AWID=%0h AWADDR=0x%08h AWBURST=%0d AWLEN=%0d",
                  xtn.AWID, xtn.AWADDR, xtn.AWBURST, xtn.AWLEN), UVM_HIGH)

      // Hand off to W stage – AW stage is now free for next transaction
      w_mbox.put(xtn);
    end
  endtask

  // ─────────────────────────────────────────────────────────────────────────
  // W stage – drives all data beats, then passes to B stage
  // ─────────────────────────────────────────────────────────────────────────
  task w_stage();
    forever begin
      axi_xtn xtn;
      w_mbox.get(xtn);

      for (int i = 0; i <= xtn.AWLEN; i++) begin
        @(vif.m_drv);
        vif.m_drv.WID    <= xtn.AWID;
        vif.m_drv.WVALID <= 1;
        vif.m_drv.WDATA  <= xtn.WDATA[i];
        vif.m_drv.WSTRB  <= xtn.WSTRB[i];
        vif.m_drv.WLAST  <= (i == xtn.AWLEN);

        @(vif.m_drv);
        while (vif.m_drv.WREADY !== 1'b1) @(vif.m_drv);

        vif.m_drv.WVALID <= 0;
        vif.m_drv.WLAST  <= 0;
        vif.m_drv.WDATA  <= 'bx;
        vif.m_drv.WSTRB  <= 4'bx;

        `uvm_info(get_type_name(),
          $sformatf("W[%0d]: AWID=%0h WDATA=0x%08h WSTRB=%04b WLAST=%0b",
                    i, xtn.AWID, xtn.WDATA[i], xtn.WSTRB[i], (i==xtn.AWLEN)), UVM_HIGH)
      end

      b_mbox.put(xtn);
    end
  endtask

  // ─────────────────────────────────────────────────────────────────────────
  // B stage – waits for write response, clears ID
  // ─────────────────────────────────────────────────────────────────────────
  task b_stage();
    forever begin
      axi_xtn xtn;
      b_mbox.get(xtn);

      @(vif.m_drv);
      vif.m_drv.BREADY <= 1;
      @(vif.m_drv);
      while (vif.m_drv.BVALID !== 1'b1) @(vif.m_drv);

      `uvm_info(get_type_name(),
        $sformatf("B: BID=%0h BRESP=%02b", vif.m_drv.BID, vif.m_drv.BRESP), UVM_HIGH)

      vif.m_drv.BREADY <= 0;

      wr_id_sem.get(1);
      wr_id_inflight[xtn.AWID]           = 0;
      a_cfg.drv_wr_id_inflight[xtn.AWID] = 0;
      wr_id_sem.put(1);

      `uvm_info(get_type_name(),
        $sformatf("WR COMPLETE: AWID=%0h freed", xtn.AWID), UVM_MEDIUM)
    end
  endtask

  // ─────────────────────────────────────────────────────────────────────────
  // AR stage – issues read address, passes to R stage
  // ─────────────────────────────────────────────────────────────────────────
  task ar_stage();
    forever begin
      axi_xtn xtn;
      rd_mbox.get(xtn);

      @(vif.m_drv);
      vif.m_drv.ARVALID <= 1;
      vif.m_drv.ARID    <= xtn.ARID;
      vif.m_drv.ARADDR  <= xtn.ARADDR;
      vif.m_drv.ARLEN   <= xtn.ARLEN;
      vif.m_drv.ARSIZE  <= xtn.ARSIZE;
      vif.m_drv.ARBURST <= xtn.ARBURST;

      @(vif.m_drv);
      while (vif.m_drv.ARREADY !== 1'b1) @(vif.m_drv);

      vif.m_drv.ARVALID <= 0;
      vif.m_drv.ARID    <= 4'bx;
      vif.m_drv.ARADDR  <= 'bx;
      vif.m_drv.ARLEN   <= 4'bx;
      vif.m_drv.ARSIZE  <= 3'bx;
      vif.m_drv.ARBURST <= 2'bx;

      `uvm_info(get_type_name(),
        $sformatf("AR done: ARID=%0h ARADDR=0x%08h ARBURST=%0d ARLEN=%0d",
                  xtn.ARID, xtn.ARADDR, xtn.ARBURST, xtn.ARLEN), UVM_HIGH)

      r_mbox.put(xtn);
    end
  endtask

  // ─────────────────────────────────────────────────────────────────────────
  // R stage – drains r_mbox; forks a dedicated beat thread per read so
  // multiple reads can receive interleaved R data concurrently (valid AXI).
  // This prevents the sequential bottleneck where r_stage blocked on one
  // read's beats while the monitor's per-read threads missed their beats.
  // ─────────────────────────────────────────────────────────────────────────
  task r_stage();
    forever begin
      axi_xtn xtn;
      r_mbox.get(xtn);
      fork
        automatic axi_xtn rx = xtn;
        r_beats(rx);
      join_none
    end
  endtask

  task r_beats(axi_xtn xtn);
    // Acquire R-channel token so only one r_beats thread drives RREADY at a time.
    // Without this, concurrent threads overwrite each other's RREADY and random
    // beats are missed (seen as fewer beats than ARLEN+1 in the waveform).
    rd_rdy_sem.get(1);

    for (int i = 0; i <= xtn.ARLEN; i++) begin
      @(vif.m_drv);
      vif.m_drv.RREADY <= 1;
      @(vif.m_drv);
      while (vif.m_drv.RVALID !== 1'b1) @(vif.m_drv);

      `uvm_info(get_type_name(),
        $sformatf("R[%0d]: ARID=%0h RDATA=0x%08h RRESP=%02b RLAST=%0b",
                  i, xtn.ARID, vif.m_drv.RDATA, vif.m_drv.RRESP, vif.m_drv.RLAST),
        UVM_HIGH)

      vif.m_drv.RREADY <= 0;
    end

    rd_rdy_sem.put(1);   // release R channel for next read

    rd_id_sem.get(1);
    rd_id_inflight[xtn.ARID]           = 0;
    a_cfg.drv_rd_id_inflight[xtn.ARID] = 0;
    rd_id_sem.put(1);

    `uvm_info(get_type_name(),
      $sformatf("RD COMPLETE: ARID=%0h freed", xtn.ARID), UVM_MEDIUM)
  endtask

endclass