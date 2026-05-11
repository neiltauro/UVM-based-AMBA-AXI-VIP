// =============================================================================
// virtual_sequence.sv
//
// base_v_seq    : casts m_sequencer → virtual_sequencer, fetches a_config,
//                 populates m_seqrh handle from v_seqr.m_seqrh
// *_v_seq       : individual virtual sequences – each starts its specific
//                 master sequence on m_seqrh
// regression_v_seq : runs all 7 master sequences in order on m_seqrh
// =============================================================================

class base_v_seq extends uvm_sequence #(uvm_sequence_item);
  `uvm_object_utils(base_v_seq)

  virtual_sequencer v_seqr;
  master_sequencer  m_seqrh;
  a_config          cfg;

  function new(string name = "base_v_seq");
    super.new(name);
  endfunction

  task body();
    if (!$cast(v_seqr, m_sequencer))
      `uvm_fatal(get_type_name(), "Cast to virtual_sequencer failed")

    if (!uvm_config_db #(a_config)::get(null, get_full_name(), "a_config", cfg))
      `uvm_fatal(get_type_name(), "Cannot get a_config")

    m_seqrh = v_seqr.m_seqrh;
  endtask

endclass

// ---------------------------------------------------------------------------
// single_write_v_seq
// ---------------------------------------------------------------------------
class single_write_v_seq extends base_v_seq;
  `uvm_object_utils(single_write_v_seq)

  single_write_seq seq;

  function new(string name = "single_write_v_seq");
    super.new(name);
  endfunction

  task body();
    super.body();
    seq = single_write_seq::type_id::create("seq");
    seq.start(m_seqrh);
    `uvm_info(get_type_name(), "single_write_v_seq completed", UVM_LOW)
  endtask
endclass

// ---------------------------------------------------------------------------
// single_read_v_seq
// ---------------------------------------------------------------------------
class single_read_v_seq extends base_v_seq;
  `uvm_object_utils(single_read_v_seq)

  single_read_seq seq;

  function new(string name = "single_read_v_seq");
    super.new(name);
  endfunction

  task body();
    super.body();
    seq = single_read_seq::type_id::create("seq");
    seq.start(m_seqrh);
    `uvm_info(get_type_name(), "single_read_v_seq completed", UVM_LOW)
  endtask
endclass

// ---------------------------------------------------------------------------
// fixed_burst_v_seq
// ---------------------------------------------------------------------------
class fixed_burst_v_seq extends base_v_seq;
  `uvm_object_utils(fixed_burst_v_seq)

  fixed_burst_seq seq;

  function new(string name = "fixed_burst_v_seq");
    super.new(name);
  endfunction

  task body();
    super.body();
    seq = fixed_burst_seq::type_id::create("seq");
    seq.start(m_seqrh);
    `uvm_info(get_type_name(), "fixed_burst_v_seq completed", UVM_LOW)
  endtask
endclass

// ---------------------------------------------------------------------------
// incr_burst_v_seq
// ---------------------------------------------------------------------------
class incr_burst_v_seq extends base_v_seq;
  `uvm_object_utils(incr_burst_v_seq)

  incr_burst_seq seq;

  function new(string name = "incr_burst_v_seq");
    super.new(name);
  endfunction

  task body();
    super.body();
    seq = incr_burst_seq::type_id::create("seq");
    seq.start(m_seqrh);
    `uvm_info(get_type_name(), "incr_burst_v_seq completed", UVM_LOW)
  endtask
endclass

// ---------------------------------------------------------------------------
// wrap_burst_v_seq
// ---------------------------------------------------------------------------
class wrap_burst_v_seq extends base_v_seq;
  `uvm_object_utils(wrap_burst_v_seq)

  wrap_burst_seq seq;

  function new(string name = "wrap_burst_v_seq");
    super.new(name);
  endfunction

  task body();
    super.body();
    seq = wrap_burst_seq::type_id::create("seq");
    seq.start(m_seqrh);
    `uvm_info(get_type_name(), "wrap_burst_v_seq completed", UVM_LOW)
  endtask
endclass

// ---------------------------------------------------------------------------
// outstanding_write_v_seq
// ---------------------------------------------------------------------------
class outstanding_write_v_seq extends base_v_seq;
  `uvm_object_utils(outstanding_write_v_seq)

  outstanding_write_seq seq;

  function new(string name = "outstanding_write_v_seq");
    super.new(name);
  endfunction

  task body();
    super.body();
    seq = outstanding_write_seq::type_id::create("seq");
    seq.start(m_seqrh);
    `uvm_info(get_type_name(), "outstanding_write_v_seq completed", UVM_LOW)
  endtask
endclass

// ---------------------------------------------------------------------------
// outstanding_read_v_seq
// ---------------------------------------------------------------------------
class outstanding_read_v_seq extends base_v_seq;
  `uvm_object_utils(outstanding_read_v_seq)

  outstanding_read_seq seq;

  function new(string name = "outstanding_read_v_seq");
    super.new(name);
  endfunction

  task body();
    super.body();
    seq = outstanding_read_seq::type_id::create("seq");
    seq.start(m_seqrh);
    `uvm_info(get_type_name(), "outstanding_read_v_seq completed", UVM_LOW)
  endtask
endclass

// ---------------------------------------------------------------------------
// regression_v_seq : runs all 7 master sequences in order on m_seqrh
// ---------------------------------------------------------------------------
class regression_v_seq extends base_v_seq;
  `uvm_object_utils(regression_v_seq)

  single_write_seq      sw_seq;
  single_read_seq       sr_seq;
  fixed_burst_seq       fb_seq;
  incr_burst_seq        ib_seq;
  wrap_burst_seq        wb_seq;
  outstanding_write_seq ow_seq;
  outstanding_read_seq  or_seq;

  function new(string name = "regression_v_seq");
    super.new(name);
  endfunction

  task body();
    super.body();   // cast + config fetch + m_seqrh assignment

    sw_seq = single_write_seq     ::type_id::create("sw_seq");
    sr_seq = single_read_seq      ::type_id::create("sr_seq");
    fb_seq = fixed_burst_seq      ::type_id::create("fb_seq");
    ib_seq = incr_burst_seq       ::type_id::create("ib_seq");
    wb_seq = wrap_burst_seq       ::type_id::create("wb_seq");
    ow_seq = outstanding_write_seq::type_id::create("ow_seq");
    or_seq = outstanding_read_seq ::type_id::create("or_seq");

    `uvm_info(get_type_name(), "\n=== regression_v_seq START ===", UVM_LOW)

    `uvm_info(get_type_name(), "--- Phase 1: single_write_seq ---", UVM_LOW)
    sw_seq.start(m_seqrh);

    `uvm_info(get_type_name(), "--- Phase 2: single_read_seq ---", UVM_LOW)
    sr_seq.start(m_seqrh);

    `uvm_info(get_type_name(), "--- Phase 3: fixed_burst_seq ---", UVM_LOW)
    fb_seq.start(m_seqrh);

    `uvm_info(get_type_name(), "--- Phase 4: incr_burst_seq ---", UVM_LOW)
    ib_seq.start(m_seqrh);

    `uvm_info(get_type_name(), "--- Phase 5: wrap_burst_seq ---", UVM_LOW)
    wb_seq.start(m_seqrh);

    `uvm_info(get_type_name(), "--- Phase 6: outstanding_write_seq ---", UVM_LOW)
    ow_seq.start(m_seqrh);

    `uvm_info(get_type_name(), "--- Phase 7: outstanding_read_seq ---", UVM_LOW)
    or_seq.start(m_seqrh);

    `uvm_info(get_type_name(), "=== regression_v_seq DONE ===\n", UVM_LOW)
  endtask

endclass