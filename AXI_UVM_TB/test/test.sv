// =============================================================================
// test.sv
//
// base_test         : builds the environment (1 master, 1 slave, 10 xtns)
// single_write_test : single-beat write transfers
// single_read_test  : single-beat read  transfers
// fixed_burst_test  : FIXED burst write + read
// incr_burst_test   : INCR  burst write + read
// wrap_burst_test   : WRAP  burst write + read
// outstanding_write_test : multiple outstanding writes
// outstanding_read_test  : multiple outstanding reads
// =============================================================================

// ---------------------------------------------------------------------------
// Base test
// ---------------------------------------------------------------------------
class base_test extends uvm_test;
  `uvm_component_utils(base_test)

  env       envh;
  a_config  a_cfg;
  m_config  m_cfg;
  s_config  s_cfg;
  
 
  function new(string name = "base_test", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
	virtual axi vif;
    // --- build top-level config ---
    a_cfg = a_config::type_id::create("a_cfg");
    a_cfg.no_of_transactions = 10;
    a_cfg.has_sb             = 1;
    a_cfg.sb_timeout_cycles  = 5000;

    // --- master config ---
    m_cfg           = m_config::type_id::create("m_cfg");
    m_cfg.is_active = UVM_ACTIVE;
    if (!uvm_config_db #(virtual axi)::get(this, "", "axi", m_cfg.vif))
      `uvm_fatal(get_type_name(), "Cannot get virtual axi interface for master")
    a_cfg.m_cfg    = new[1];
    a_cfg.m_cfg[0] = m_cfg;

    // --- slave config ---
    s_cfg           = s_config::type_id::create("s_cfg");
    s_cfg.is_active = UVM_ACTIVE;
    if (!uvm_config_db #(virtual axi)::get(this, "", "axi", s_cfg.vif))
      `uvm_fatal(get_type_name(), "Cannot get virtual axi interface for slave")
    a_cfg.s_cfg    = new[1];
    a_cfg.s_cfg[0] = s_cfg;

    // --- push configs into config DB ---
    uvm_config_db #(a_config)::set(this, "*", "a_config", a_cfg);
    uvm_config_db #(m_config)::set(this, "envh.m_agenth*", "m_config", m_cfg);
    uvm_config_db #(s_config)::set(this, "envh.s_agenth*", "s_config", s_cfg);

    envh = env::type_id::create("envh", this);
  endfunction

endclass

// ---------------------------------------------------------------------------
// Helper macro – all derived tests only need to name their sequence
// ---------------------------------------------------------------------------
`define AXI_TEST(TEST_NAME, SEQ_TYPE) \
class TEST_NAME extends base_test; \
  `uvm_component_utils(TEST_NAME) \
  function new(string name = `"TEST_NAME`", uvm_component parent); \
    super.new(name, parent); \
  endfunction \
  task run_phase(uvm_phase phase); \
    SEQ_TYPE seq; \
    phase.raise_objection(this); \
    seq = SEQ_TYPE::type_id::create("seq"); \
    seq.start(envh.seqrh); \
    repeat (700) @(posedge m_cfg.vif.ACLK); \
    phase.drop_objection(this); \
  endtask \
endclass

`AXI_TEST(single_write_test,      single_write_v_seq)
`AXI_TEST(single_read_test,       single_read_v_seq)
`AXI_TEST(fixed_burst_test,       fixed_burst_v_seq)
`AXI_TEST(incr_burst_test,        incr_burst_v_seq)
`AXI_TEST(wrap_burst_test,        wrap_burst_v_seq)
`AXI_TEST(outstanding_write_test, outstanding_write_v_seq)
`AXI_TEST(outstanding_read_test,  outstanding_read_v_seq)
