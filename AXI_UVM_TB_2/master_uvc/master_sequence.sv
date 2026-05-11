// =============================================================================
// master_sequence.sv  (WITH SEQUENCE-SIDE ID-REUSE GUARD)
//
// Every sequence that picks a write ID calls cfg.get_free_wr_id() before
// randomizing to get an ID that is not currently in-flight in the driver.
// Same pattern for read IDs via cfg.get_free_rd_id().
//
// This is the sequence-side half of the two-layer ID guard:
//   Layer 1 (sequence) – picks a free ID → avoids even attempting a reuse
//   Layer 2 (driver)   – stalls dispatch if the ID is somehow still busy
//
// Sequences:
//   base_sequence          – base class; fetches a_config
//   single_write_seq       – 1-beat write (AWLEN=0)
//   single_read_seq        – 1-beat read  (ARLEN=0)
//   fixed_burst_seq        – FIXED burst (AWBURST/ARBURST=0)
//   incr_burst_seq         – INCR  burst (AWBURST/ARBURST=1)
//   wrap_burst_seq         – WRAP  burst (AWBURST/ARBURST=2)
//   outstanding_write_seq  – back-to-back writes with unique IDs
//   outstanding_read_seq   – back-to-back reads  with unique IDs
// =============================================================================

// ---------------------------------------------------------------------------
// Base sequence
// ---------------------------------------------------------------------------
class base_sequence extends uvm_sequence #(axi_xtn);
  `uvm_object_utils(base_sequence)

  a_config cfg;

  function new(string name = "base_sequence");
    super.new(name);
  endfunction

  task body();
    if (!uvm_config_db #(a_config)::get(null, get_full_name(), "a_config", cfg))
      `uvm_fatal(get_full_name(), "Cannot get a_config")
  endtask
endclass

// ---------------------------------------------------------------------------
// Single write  (AWLEN=0, one beat)
// ---------------------------------------------------------------------------
class single_write_seq extends base_sequence;
  `uvm_object_utils(single_write_seq)

  function new(string name = "single_write_seq");
    super.new(name);
  endfunction

  task body();
    int free_id;
    super.body();
    repeat (cfg.no_of_transactions) begin
      cfg.get_free_wr_id(free_id);   // sequence-side ID guard
      req = axi_xtn::type_id::create("req");
      start_item(req);
      if (!req.randomize() with {
            is_read == 0;
            AWID    == free_id[3:0];
            AWLEN   == 0;
            AWBURST == 1;              // INCR cleanest for single beat
          })
        `uvm_fatal(get_type_name(), "Randomize failed")
      finish_item(req);
      `uvm_info(get_type_name(),
        $sformatf("SINGLE_WRITE: AWID=%0h AWADDR=0x%08h",
                  req.AWID, req.AWADDR), UVM_MEDIUM)
    end
  endtask
endclass

// ---------------------------------------------------------------------------
// Single read  (ARLEN=0, one beat)
// ---------------------------------------------------------------------------
class single_read_seq extends base_sequence;
  `uvm_object_utils(single_read_seq)

  function new(string name = "single_read_seq");
    super.new(name);
  endfunction

  task body();
    int free_id;
    super.body();
    repeat (cfg.no_of_transactions) begin
      cfg.get_free_rd_id(free_id);
      req = axi_xtn::type_id::create("req");
      start_item(req);
      if (!req.randomize() with {
            is_read == 1;
            ARID    == free_id[3:0];
            ARLEN   == 0;
            ARBURST == 1;
          })
        `uvm_fatal(get_type_name(), "Randomize failed")
      finish_item(req);
      `uvm_info(get_type_name(),
        $sformatf("SINGLE_READ:  ARID=%0h ARADDR=0x%08h",
                  req.ARID, req.ARADDR), UVM_MEDIUM)
    end
  endtask
endclass

// ---------------------------------------------------------------------------
// FIXED burst  (AWBURST/ARBURST = 0)
// Each iteration issues one write followed by one read – because the driver
// pipelines them in parallel, both are on the bus simultaneously.
// ---------------------------------------------------------------------------
class fixed_burst_seq extends base_sequence;
  `uvm_object_utils(fixed_burst_seq)

  function new(string name = "fixed_burst_seq");
    super.new(name);
  endfunction

  task body();
    int free_id;
    super.body();
    repeat (cfg.no_of_transactions) begin
      // Write
      cfg.get_free_wr_id(free_id);
      req = axi_xtn::type_id::create("req_w");
      start_item(req);
      if (!req.randomize() with {
            is_read == 0;
            AWID    == free_id[3:0];
            AWBURST == 0;
            AWLEN   inside {[1:15]};
          })
        `uvm_fatal(get_type_name(), "Randomize failed")
      finish_item(req);
      `uvm_info(get_type_name(),
        $sformatf("FIXED WR: AWID=%0h AWADDR=0x%08h AWLEN=%0d",
                  req.AWID, req.AWADDR, req.AWLEN), UVM_MEDIUM)

      // Read – issued immediately after; driver puts it on AR while
      // wr_pipeline is still handling the W/B phases above
      cfg.get_free_rd_id(free_id);
      req = axi_xtn::type_id::create("req_r");
      start_item(req);
      if (!req.randomize() with {
            is_read == 1;
            ARID    == free_id[3:0];
            ARBURST == 0;
            ARLEN   inside {[1:15]};
          })
        `uvm_fatal(get_type_name(), "Randomize failed")
      finish_item(req);
      `uvm_info(get_type_name(),
        $sformatf("FIXED RD: ARID=%0h ARADDR=0x%08h ARLEN=%0d",
                  req.ARID, req.ARADDR, req.ARLEN), UVM_MEDIUM)
    end
  endtask
endclass

// ---------------------------------------------------------------------------
// INCR burst  (AWBURST/ARBURST = 1)
// ---------------------------------------------------------------------------
class incr_burst_seq extends base_sequence;
  `uvm_object_utils(incr_burst_seq)

  function new(string name = "incr_burst_seq");
    super.new(name);
  endfunction

  task body();
    int free_id;
    super.body();
    repeat (cfg.no_of_transactions) begin
      cfg.get_free_wr_id(free_id);
      req = axi_xtn::type_id::create("req_w");
      start_item(req);
      if (!req.randomize() with {
            is_read == 0;
            AWID    == free_id[3:0];
            AWBURST == 1;
            AWLEN   inside {[1:15]};
          })
        `uvm_fatal(get_type_name(), "Randomize failed")
      finish_item(req);
      `uvm_info(get_type_name(),
        $sformatf("INCR WR: AWID=%0h AWADDR=0x%08h AWLEN=%0d",
                  req.AWID, req.AWADDR, req.AWLEN), UVM_MEDIUM)

      cfg.get_free_rd_id(free_id);
      req = axi_xtn::type_id::create("req_r");
      start_item(req);
      if (!req.randomize() with {
            is_read == 1;
            ARID    == free_id[3:0];
            ARBURST == 1;
            ARLEN   inside {[1:15]};
          })
        `uvm_fatal(get_type_name(), "Randomize failed")
      finish_item(req);
      `uvm_info(get_type_name(),
        $sformatf("INCR RD: ARID=%0h ARADDR=0x%08h ARLEN=%0d",
                  req.ARID, req.ARADDR, req.ARLEN), UVM_MEDIUM)
    end
  endtask
endclass

// ---------------------------------------------------------------------------
// WRAP burst  (AWBURST/ARBURST = 2) – length must be in {1,3,7,15}
// ---------------------------------------------------------------------------
class wrap_burst_seq extends base_sequence;
  `uvm_object_utils(wrap_burst_seq)

  function new(string name = "wrap_burst_seq");
    super.new(name);
  endfunction

  task body();
    int free_id;
    super.body();
    repeat (cfg.no_of_transactions) begin
      cfg.get_free_wr_id(free_id);
      req = axi_xtn::type_id::create("req_w");
      start_item(req);
      if (!req.randomize() with {
            is_read == 0;
            AWID    == free_id[3:0];
            AWBURST == 2;
            AWLEN   inside {1, 3, 7, 15};
          })
        `uvm_fatal(get_type_name(), "Randomize failed")
      finish_item(req);
      `uvm_info(get_type_name(),
        $sformatf("WRAP WR: AWID=%0h AWADDR=0x%08h AWLEN=%0d",
                  req.AWID, req.AWADDR, req.AWLEN), UVM_MEDIUM)

      cfg.get_free_rd_id(free_id);
      req = axi_xtn::type_id::create("req_r");
      start_item(req);
      if (!req.randomize() with {
            is_read == 1;
            ARID    == free_id[3:0];
            ARBURST == 2;
            ARLEN   inside {1, 3, 7, 15};
          })
        `uvm_fatal(get_type_name(), "Randomize failed")
      finish_item(req);
      `uvm_info(get_type_name(),
        $sformatf("WRAP RD: ARID=%0h ARADDR=0x%08h ARLEN=%0d",
                  req.ARID, req.ARADDR, req.ARLEN), UVM_MEDIUM)
    end
  endtask
endclass

// ---------------------------------------------------------------------------
// Outstanding writes
// Issues no_of_transactions writes back-to-back, each with a unique free ID.
// Because the driver's dispatch_loop calls item_done() immediately after
// routing each item into wr_mbox, the sequencer issues all transactions
// without waiting for any BRESP – they queue up in wr_mbox and the
// wr_pipeline processes them one at a time while the reads (from any
// parallel sequence) progress simultaneously on the read channels.
// ---------------------------------------------------------------------------
class outstanding_write_seq extends base_sequence;
  `uvm_object_utils(outstanding_write_seq)

  function new(string name = "outstanding_write_seq");
    super.new(name);
  endfunction

  task body();
    int free_id;
    super.body();
    for (int i = 0; i < cfg.no_of_transactions; i++) begin
      cfg.get_free_wr_id(free_id);   // guaranteed unique & not in-flight
      req = axi_xtn::type_id::create("req");
      start_item(req);
      if (!req.randomize() with {
            is_read == 0;
            AWID    == free_id[3:0];
            AWBURST inside {0, 1, 2};
            AWLEN   inside {[1:7]};
          })
        `uvm_fatal(get_type_name(), "Randomize failed")
      finish_item(req);
      `uvm_info(get_type_name(),
        $sformatf("OUTSTANDING_WR[%0d]: AWID=%0h AWADDR=0x%08h AWLEN=%0d AWBURST=%0d",
                  i, req.AWID, req.AWADDR, req.AWLEN, req.AWBURST), UVM_MEDIUM)
    end
  endtask
endclass

// ---------------------------------------------------------------------------
// Outstanding reads
// ---------------------------------------------------------------------------
class outstanding_read_seq extends base_sequence;
  `uvm_object_utils(outstanding_read_seq)

  function new(string name = "outstanding_read_seq");
    super.new(name);
  endfunction

  task body();
    int free_id;
    super.body();
    for (int i = 0; i < cfg.no_of_transactions; i++) begin
      cfg.get_free_rd_id(free_id);
      req = axi_xtn::type_id::create("req");
      start_item(req);
      if (!req.randomize() with {
            is_read == 1;
            ARID    == free_id[3:0];
            ARBURST inside {0, 1, 2};
            ARLEN   inside {[1:7]};
          })
        `uvm_fatal(get_type_name(), "Randomize failed")
      finish_item(req);
      `uvm_info(get_type_name(),
        $sformatf("OUTSTANDING_RD[%0d]: ARID=%0h ARADDR=0x%08h ARLEN=%0d ARBURST=%0d",
                  i, req.ARID, req.ARADDR, req.ARLEN, req.ARBURST), UVM_MEDIUM)
    end
  endtask
endclass
