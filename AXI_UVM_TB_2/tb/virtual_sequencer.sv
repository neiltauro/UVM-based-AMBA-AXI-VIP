// =============================================================================
// virtual_sequencer.sv
// =============================================================================
class virtual_sequencer extends uvm_sequencer #(uvm_sequence_item);
  `uvm_component_utils(virtual_sequencer)
 
  master_sequencer m_seqrh;
  slave_sequencer  s_seqrh;
  a_config         cfg;
 
  function new(string name = "virtual_sequencer", uvm_component parent);
    super.new(name, parent);
  endfunction
 
  function void build_phase(uvm_phase phase);
    if (!uvm_config_db #(a_config)::get(this, "", "a_config", cfg))
      `uvm_fatal(get_type_name(), "Cannot get a_config in virtual_sequencer")
    m_seqrh = master_sequencer :: type_id :: create("m_seqrh", this);
    s_seqrh = slave_sequencer :: type_id :: create("s_seqrh", this);
  endfunction
endclass