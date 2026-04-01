// =============================================================================
// env.sv  –  1 master / 1 slave environment
// =============================================================================
class env extends uvm_env;
  `uvm_component_utils(env)

  a_config         cfg;
  master_agent     m_agenth;
  slave_agent      s_agenth;
  score_board      sb;
  virtual_sequencer seqrh;   // top-level sequencer handle for test

  function new(string name = "env", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db #(a_config)::get(this, "", "a_config", cfg))
      `uvm_fatal(get_type_name(), "Cannot get a_config")

    m_agenth = master_agent::type_id::create("m_agenth", this);
    s_agenth = slave_agent ::type_id::create("s_agenth", this);

    if (cfg.has_sb)
      sb = score_board::type_id::create("sb", this);
	  
	seqrh = virtual_sequencer ::type_id::create("seqrh", this);
	
  endfunction

  function void connect_phase(uvm_phase phase);
    if (cfg.has_sb) begin
      // Master write completions → write FIFO pair
      m_agenth.monh.analysis_port_wr.connect(sb.m_wr_fifo.analysis_export);
      s_agenth.monh.analysis_port_wr.connect(sb.s_wr_fifo.analysis_export);

      // Master read completions → read FIFO pair
      m_agenth.monh.analysis_port_rd.connect(sb.m_rd_fifo.analysis_export);
      s_agenth.monh.analysis_port_rd.connect(sb.s_rd_fifo.analysis_export);
    end

    // Expose sequencer for tests
    seqrh.m_seqrh = m_agenth.seqrh;
  endfunction

endclass
