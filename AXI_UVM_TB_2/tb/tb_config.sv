// =============================================================================
// tb_config.sv
// =============================================================================
class a_config extends uvm_object;
  `uvm_object_utils(a_config)

  int no_of_masters         = 1;
  int no_of_slaves          = 1;
  int no_of_transactions    = 10;
  bit has_sb                = 1;
  bit has_virtual_sequencer = 0;
  int sb_timeout_cycles     = 10000;

  m_config m_cfg[];
  s_config s_cfg[];

  // ------------------------------------------------------------------
  // Shared driver state – driver's build_phase points these arrays at
  // its own wr_id_inflight / rd_id_inflight storage so sequences and
  // driver share the same physical bits.
  // Semaphores are constructed here in new() so they are never null.
  // ------------------------------------------------------------------
  bit       drv_wr_id_inflight[];
  bit       drv_rd_id_inflight[];
  semaphore drv_wr_id_sem;
  semaphore drv_rd_id_sem;

  function new(string name = "a_config");
    super.new(name);
    // Construct semaphores with 1 token – acts as a mutex
    drv_wr_id_sem = new(1);
    drv_rd_id_sem = new(1);
    // Pre-allocate inflight arrays to 16 entries, all free (0)
    drv_wr_id_inflight = new[16];
    drv_rd_id_inflight = new[16];
    foreach (drv_wr_id_inflight[i]) drv_wr_id_inflight[i] = 0;
    foreach (drv_rd_id_inflight[i]) drv_rd_id_inflight[i] = 0;
  endfunction

  // ------------------------------------------------------------------
  // get_free_wr_id / get_free_rd_id
  // Tasks because semaphore.get() is a blocking task call – functions
  // cannot contain task calls in SystemVerilog.
  // Returns via output argument the first ID (0-15) not in-flight.
  // ------------------------------------------------------------------
  task get_free_wr_id(output int id);
    id = -1;
    drv_wr_id_sem.get(1);
    for (int i = 0; i < 16; i++) begin
      if (!drv_wr_id_inflight[i]) begin id = i; break; end
    end
    drv_wr_id_sem.put(1);
    if (id < 0)
      `uvm_fatal("a_config", "get_free_wr_id: all 16 write IDs are in-flight")
  endtask

  task get_free_rd_id(output int id);
    id = -1;
    drv_rd_id_sem.get(1);
    for (int i = 0; i < 16; i++) begin
      if (!drv_rd_id_inflight[i]) begin id = i; break; end
    end
    drv_rd_id_sem.put(1);
    if (id < 0)
      `uvm_fatal("a_config", "get_free_rd_id: all 16 read IDs are in-flight")
  endtask

endclass