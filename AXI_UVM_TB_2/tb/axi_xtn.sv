// =============================================================================
// axi_xtn.sv  –  AXI4 Sequence Item
// Simple 1-master / 1-slave design.
// Carries all 5 channel fields for one complete write OR read transaction.
// post_randomize() computes burst address sequences and write strobes.
// =============================================================================
class axi_xtn extends uvm_sequence_item;
  `uvm_object_utils(axi_xtn)

  // ------------------------------------------------------------------
  // Write address channel
  // ------------------------------------------------------------------
  rand bit [3:0]  AWID;
  rand bit [31:0] AWADDR;
  rand bit [3:0]  AWLEN;
  rand bit [2:0]  AWSIZE;
  rand bit [1:0]  AWBURST;
  bit             AWVALID, AWREADY;

  // ------------------------------------------------------------------
  // Write data channel
  // ------------------------------------------------------------------
  rand bit [3:0]  WID;
  rand bit [31:0] WDATA[];
  rand bit [3:0]  WSTRB[];
  bit             WVALID, WREADY, WLAST;

  // ------------------------------------------------------------------
  // Write response channel
  // ------------------------------------------------------------------
  rand bit [3:0]  BID;
  rand bit [1:0]  BRESP;
  bit             BVALID, BREADY;

  // ------------------------------------------------------------------
  // Read address channel
  // ------------------------------------------------------------------
  rand bit [3:0]  ARID;
  rand bit [31:0] ARADDR;
  rand bit [3:0]  ARLEN;
  rand bit [2:0]  ARSIZE;
  rand bit [1:0]  ARBURST;
  bit             ARVALID, ARREADY;

  // ------------------------------------------------------------------
  // Read data / response channel
  // ------------------------------------------------------------------
  rand bit [3:0]  RID;
  rand bit [31:0] RDATA[];
  bit      [3:0]  RSTRB[];
  rand bit [1:0]  RRESP;
  bit             RVALID, RREADY, RLAST;

  // ------------------------------------------------------------------
  // Computed burst address arrays (filled by post_randomize)
  // ------------------------------------------------------------------
  int unsigned waddr[];
  int unsigned raddr[];

  // ------------------------------------------------------------------
  // Transaction type flag – set by sequence before randomization
  // 0 = write,  1 = read
  // ------------------------------------------------------------------
  rand bit is_read;

  // ------------------------------------------------------------------
  // Constraints
  // ------------------------------------------------------------------

  // Address fits within a single 64-KB slave window
  constraint AWADDR_range { AWADDR inside {[32'h0000_0000 : 32'h0000_FFFF]}; }
  constraint ARADDR_range { ARADDR inside {[32'h0000_0000 : 32'h0000_FFFF]}; }

  // Transfer size: byte(0), halfword(1), word(2) only (32-bit bus)
  constraint SIZE_W { AWSIZE inside {0, 1, 2}; }
  constraint SIZE_R { ARSIZE inside {0, 1, 2}; }

  // Burst type: FIXED(0), INCR(1), WRAP(2) – no reserved value 3
  constraint BURST_W { AWBURST inside {0, 1, 2}; }
  constraint BURST_R { ARBURST inside {0, 1, 2}; }

  // WRAP burst: length must be 2, 4, 8, or 16 beats (AWLEN = 1,3,7,15)
  constraint WRAP_LEN_W { AWBURST == 2 -> AWLEN inside {1, 3, 7, 15}; }
  constraint WRAP_LEN_R { ARBURST == 2 -> ARLEN inside {1, 3, 7, 15}; }

  // WRAP burst: address alignment
  constraint WRAP_ALIGN_WA { AWBURST == 2 && AWSIZE == 1 -> AWADDR[0]   == 0; }
  constraint WRAP_ALIGN_WB { AWBURST == 2 && AWSIZE == 2 -> AWADDR[1:0] == 0; }
  constraint WRAP_ALIGN_RA { ARBURST == 2 && ARSIZE == 1 -> ARADDR[0]   == 0; }
  constraint WRAP_ALIGN_RB { ARBURST == 2 && ARSIZE == 2 -> ARADDR[1:0] == 0; }

  // WDATA / WSTRB arrays sized to burst length
  constraint WDATA_sz { WDATA.size() == AWLEN + 1; }
  constraint WSTRB_sz { WSTRB.size() == AWLEN + 1; }
  constraint RDATA_sz { RDATA.size() == ARLEN + 1; }

  // AXI ID consistency on write path
  constraint ID_W { AWID == WID; WID == BID; }
  constraint ID_R { ARID == RID; }

  // ------------------------------------------------------------------
  function new(string name = "axi_xtn");
    super.new(name);
  endfunction

  // ------------------------------------------------------------------
  // post_randomize: compute addresses and write strobes
  // ------------------------------------------------------------------
  function void post_randomize();
    w_addr_calc();
    r_addr_calc();
    strobe_calc();
    r_strobe_calc();
  endfunction

  // ------------------------------------------------------------------
  // Write burst address calculation
  // ------------------------------------------------------------------
  function void w_addr_calc();
    int unsigned start_addr    = AWADDR;
    int unsigned num_bytes     = 1 << AWSIZE;
    int unsigned burst_len     = AWLEN + 1;
    int unsigned aligned_addr  = (start_addr / num_bytes) * num_bytes;
    int unsigned wrap_boundary = (start_addr / (num_bytes * burst_len)) * (num_bytes * burst_len);
    bit wrapped = 0;

    waddr    = new[burst_len];
    waddr[0] = start_addr;

    case (AWBURST)
      2'b00: begin // FIXED – every beat uses the same address
        for (int i = 1; i < burst_len; i++)
          waddr[i] = start_addr;
      end
      2'b01: begin // INCR – address increments by num_bytes each beat
        for (int i = 1; i < burst_len; i++)
          waddr[i] = aligned_addr + i * num_bytes;
      end
      default: begin // WRAP – wraps at wrap_boundary + burst_size
        for (int i = 1; i < burst_len; i++) begin
          if (!wrapped) begin
            waddr[i] = aligned_addr + i * num_bytes;
            if (waddr[i] == wrap_boundary + num_bytes * burst_len) begin
              waddr[i] = wrap_boundary;
              wrapped   = 1;
            end
          end else
            waddr[i] = waddr[i-1] + num_bytes;
        end
      end
    endcase
  endfunction

  // ------------------------------------------------------------------
  // Read burst address calculation
  // ------------------------------------------------------------------
  function void r_addr_calc();
    int unsigned start_addr    = ARADDR;
    int unsigned num_bytes     = 1 << ARSIZE;
    int unsigned burst_len     = ARLEN + 1;
    int unsigned aligned_addr  = (start_addr / num_bytes) * num_bytes;
    int unsigned wrap_boundary = (start_addr / (num_bytes * burst_len)) * (num_bytes * burst_len);
    bit wrapped = 0;

    raddr    = new[burst_len];
    raddr[0] = start_addr;

    case (ARBURST)
      2'b00: begin
        for (int i = 1; i < burst_len; i++)
          raddr[i] = start_addr;
      end
      2'b01: begin
        for (int i = 1; i < burst_len; i++)
          raddr[i] = aligned_addr + i * num_bytes;
      end
      default: begin
        for (int i = 1; i < burst_len; i++) begin
          if (!wrapped) begin
            raddr[i] = aligned_addr + i * num_bytes;
            if (raddr[i] == wrap_boundary + num_bytes * burst_len) begin
              raddr[i] = wrap_boundary;
              wrapped   = 1;
            end
          end else
            raddr[i] = raddr[i-1] + num_bytes;
        end
      end
    endcase
  endfunction

  // ------------------------------------------------------------------
  // Write strobe calculation (per AXI spec §A3.4)
  // ------------------------------------------------------------------
  function void strobe_calc();
    int unsigned start_addr   = AWADDR;
    int unsigned num_bytes    = 1 << AWSIZE;
    int unsigned burst_len    = AWLEN + 1;
    int unsigned aligned_addr = (start_addr / num_bytes) * num_bytes;
    int unsigned dbus_bytes   = 4;    // 32-bit data bus
    int unsigned lo, hi;

    lo = start_addr  - (start_addr / dbus_bytes) * dbus_bytes;
    hi = aligned_addr + (num_bytes - 1) - (start_addr / dbus_bytes) * dbus_bytes;

    for (int i = 0; i < burst_len; i++)
      WSTRB[i] = 4'b0000;

    for (int j = lo; j <= hi; j++)
      WSTRB[0][j] = 1'b1;

    for (int n = 1; n < burst_len; n++) begin
      lo = waddr[n] - (waddr[n] / dbus_bytes) * dbus_bytes;
      hi = lo + num_bytes - 1;
      for (int j = lo; j <= hi; j++)
        WSTRB[n][j] = 1'b1;
    end
  endfunction

  // ------------------------------------------------------------------
  // Read strobe calculation
  // ------------------------------------------------------------------
  function void r_strobe_calc();
    int unsigned start_addr   = ARADDR;
    int unsigned num_bytes    = 1 << ARSIZE;
    int unsigned burst_len    = ARLEN + 1;
    int unsigned aligned_addr = (start_addr / num_bytes) * num_bytes;
    int unsigned dbus_bytes   = 4;
    int unsigned lo, hi;

    lo = start_addr  - (start_addr / dbus_bytes) * dbus_bytes;
    hi = aligned_addr + (num_bytes - 1) - (start_addr / dbus_bytes) * dbus_bytes;

    RSTRB    = new[burst_len];
    RSTRB[0] = 4'b0000;
    for (int j = lo; j <= hi; j++)
      RSTRB[0][j] = 1'b1;

    for (int n = 1; n < burst_len; n++) begin
      lo = raddr[n] - (raddr[n] / dbus_bytes) * dbus_bytes;
      hi = lo + num_bytes - 1;
      RSTRB[n] = 4'b0000;
      for (int j = lo; j <= hi; j++)
        RSTRB[n][j] = 1'b1;
    end
  endfunction

  // ------------------------------------------------------------------
  // do_compare – used by scoreboard
  // ------------------------------------------------------------------
  function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    axi_xtn rhs_;
    if (!$cast(rhs_, rhs))
      `uvm_fatal(get_type_name(), "Cast failed in do_compare")

    if (is_read) begin
      // Compare read data beat by beat
      for (int i = 0; i <= ARLEN; i++)
        if (RDATA[i] !== rhs_.RDATA[i]) return 0;
      return (ARID == rhs_.ARID && ARLEN == rhs_.ARLEN &&
              ARSIZE == rhs_.ARSIZE && ARBURST == rhs_.ARBURST);
    end else begin
      // Compare write data and strobes
      for (int i = 0; i <= AWLEN; i++)
        if (WDATA[i] !== rhs_.WDATA[i] || WSTRB[i] !== rhs_.WSTRB[i])
          return 0;
      return (AWID == rhs_.AWID && AWLEN == rhs_.AWLEN &&
              AWSIZE == rhs_.AWSIZE && AWBURST == rhs_.AWBURST);
    end
  endfunction

  // ------------------------------------------------------------------
  // do_print
  // ------------------------------------------------------------------
  function void do_print(uvm_printer printer);
    string dir = is_read ? "READ" : "WRITE";
    printer.print_string("direction", dir);
    if (!is_read) begin
      printer.print_field("AWID",    AWID,    4,  UVM_HEX);
      printer.print_field("AWADDR",  AWADDR,  32, UVM_HEX);
      printer.print_field("AWLEN",   AWLEN,   4,  UVM_DEC);
      printer.print_field("AWSIZE",  AWSIZE,  3,  UVM_DEC);
      printer.print_field("AWBURST", AWBURST, 2,  UVM_DEC);
      foreach (WDATA[i])
        printer.print_field($sformatf("WDATA[%0d]", i), WDATA[i], 32, UVM_HEX);
      foreach (WSTRB[i])
        printer.print_field($sformatf("WSTRB[%0d]", i), WSTRB[i], 4,  UVM_BIN);
      printer.print_field("BRESP",   BRESP,   2,  UVM_DEC);
    end else begin
      printer.print_field("ARID",    ARID,    4,  UVM_HEX);
      printer.print_field("ARADDR",  ARADDR,  32, UVM_HEX);
      printer.print_field("ARLEN",   ARLEN,   4,  UVM_DEC);
      printer.print_field("ARSIZE",  ARSIZE,  3,  UVM_DEC);
      printer.print_field("ARBURST", ARBURST, 2,  UVM_DEC);
      foreach (RDATA[i])
        printer.print_field($sformatf("RDATA[%0d]", i), RDATA[i], 32, UVM_HEX);
      printer.print_field("RRESP",   RRESP,   2,  UVM_DEC);
    end
  endfunction

endclass
