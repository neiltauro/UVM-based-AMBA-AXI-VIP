// =============================================================================
// master_config.sv
// =============================================================================
class m_config extends uvm_object;
  `uvm_object_utils(m_config)

  virtual axi             vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  function new(string name = "m_config");
    super.new(name);
  endfunction
endclass
