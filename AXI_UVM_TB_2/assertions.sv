// =============================================================================
//  AHB-APB Bridge – Waveform-Derived Assertions
//  Based on:
//    Figure 5-10  : Burst of Read  Transfers (4 reads, 1 wait-state each)
//    Figure 5-12  : Burst of Write Transfers (4 writes, pipelined)
//
//  Every assertion is tied directly to the observed timing shown in the
//  waveform diagrams.  Signal names match the rtl_top port list.
// =============================================================================

`include "definitions.v"

module ahb_apb_waveform_assertions (
    input               Hclk,
    input               Hresetn,
    // AHB side
    input  [1:0]        Htrans,
    input               Hwrite,
    input  [31:0]       Haddr,
    input  [31:0]       Hwdata,
    input               Hreadyout,   // HREADY in waveform
    input  [31:0]       Hrdata,
    // APB side
    input  [31:0]       Paddr,
    input               Pwrite,
    input  [3:0]        Pselx,       // PSEL in waveform (any bit)
    input               Penable,
    input  [31:0]       Prdata,
    input  [31:0]       Pwdata
);

    // -----------------------------------------------------------------------
    //  Convenience wires
    // -----------------------------------------------------------------------
    wire psel_active  = (Pselx != 4'b0);           // any slave selected
    wire apb_transfer = psel_active && !Penable;    // setup  phase
    wire apb_enable   = psel_active &&  Penable;    // access phase

    // =========================================================================
    //  ASSERTION 1 (Read waveform – T2→T3)
    //  PSEL must be asserted exactly ONE cycle before PENABLE.
    //  Waveform: PSEL rises at T2; PENABLE rises at T3.
    // =========================================================================
    property p_psel_one_cycle_before_penable;
        @(posedge Hclk) disable iff (!Hresetn)
        $rose(psel_active) |=> $rose(Penable);
    endproperty
    assert_psel_one_cycle_before_penable :
        assert property (p_psel_one_cycle_before_penable)
        else $error("FAIL [A1]: PENABLE did not rise exactly 1 cycle after PSEL");

    // =========================================================================
    //  ASSERTION 2 (Read waveform – T2 through T3)
    //  During a READ transfer PWRITE must remain LOW throughout the entire
    //  APB cycle (setup + access).
    //  Waveform: PWRITE stays low across all read beats (T2-T10).
    // =========================================================================
    property p_pwrite_low_during_read_apb;
        @(posedge Hclk) disable iff (!Hresetn)
        (psel_active && !Hwrite) |-> !Pwrite;
    endproperty
    assert_pwrite_low_during_read_apb :
        assert property (p_pwrite_low_during_read_apb)
        else $error("FAIL [A2]: PWRITE asserted during an APB read transfer");

    // =========================================================================
    //  ASSERTION 3 (Read waveform – T3)
    //  HRDATA must be captured (non-zero / same as PRDATA) in the same cycle
    //  that PENABLE is high during a read — i.e., the access phase delivers data.
    //  Waveform: HRDATA = Data1 appears at T3 when PENABLE is high.
    // =========================================================================
    property p_hrdata_valid_on_penable_read;
        @(posedge Hclk) disable iff (!Hresetn)
        (Penable && psel_active && !Pwrite) |-> (Hrdata == Prdata);
    endproperty
    assert_hrdata_valid_on_penable_read :
        assert property (p_hrdata_valid_on_penable_read)
        else $error("FAIL [A3]: HRDATA does not match PRDATA during APB read access phase");

    // =========================================================================
    //  ASSERTION 4 (Read waveform – T2→T3)
    //  HREADY must be LOW while APB read is in progress (wait state), then
    //  return HIGH one cycle after PENABLE (access phase complete).
    //  Waveform: HREADY drops at T2, returns at T3 (end of wait state).
    // =========================================================================
    property p_hready_low_during_apb_read_setup;
        @(posedge Hclk) disable iff (!Hresetn)
        (psel_active && !Penable && !Pwrite) |-> !Hreadyout;
    endproperty
    assert_hready_low_during_apb_read_setup :
        assert property (p_hready_low_during_apb_read_setup)
        else $error("FAIL [A4]: HREADY not deasserted during APB read setup phase");

    // =========================================================================
    //  ASSERTION 5 (Read waveform – T3 end)
    //  After PENABLE falls at end of read access phase, HREADY must go HIGH,
    //  indicating the wait state is over and the next AHB beat may proceed.
    //  Waveform: HREADY rises at T3 (falling edge window of PENABLE).
    // =========================================================================
    property p_hready_high_after_read_access;
        @(posedge Hclk) disable iff (!Hresetn)
        $fell(Penable) && !Pwrite |=> Hreadyout;
    endproperty
    assert_hready_high_after_read_access :
        assert property (p_hready_high_after_read_access)
        else $error("FAIL [A5]: HREADY did not return high after APB read access phase");

    // =========================================================================
    //  ASSERTION 6 (Read waveform – T2→T3, pipelined)
    //  PADDR must be stable (not change) from the setup phase through the
    //  access phase (PSEL high and PENABLE high on the next cycle).
    //  Waveform: PADDR=Addr1 holds from T2 through T3 without change.
    // =========================================================================
    property p_paddr_stable_across_apb_read;
        @(posedge Hclk) disable iff (!Hresetn)
        (psel_active && !Penable && !Pwrite) |=> $stable(Paddr);
    endproperty
    assert_paddr_stable_across_apb_read :
        assert property (p_paddr_stable_across_apb_read)
        else $error("FAIL [A6]: PADDR changed between APB read setup and access phases");

    // =========================================================================
    //  ASSERTION 7 (Read waveform – AHB-to-APB address pipeline delay)
    //  PADDR must appear exactly TWO AHB clock cycles after the corresponding
    //  HADDR is presented — the AHB slave registers HADDR (1 cycle) and the
    //  APB controller samples it (1 more cycle) before driving PADDR.
    //  Waveform: HADDR=Addr1 at T1 → PADDR=Addr1 at T3.
    // =========================================================================
    property p_paddr_two_cycle_delay_from_haddr;
        @(posedge Hclk) disable iff (!Hresetn)
        (Htrans == 2'b10 && !Hwrite) // NONSEQ read
        |-> ##2 (Paddr == $past(Haddr, 2));
    endproperty
    assert_paddr_two_cycle_delay_from_haddr :
        assert property (p_paddr_two_cycle_delay_from_haddr)
        else $error("FAIL [A7]: PADDR does not match HADDR delayed by 2 cycles (read)");

    // =========================================================================
    //  ASSERTION 8 (Write waveform – T3→T4→T5 pipeline)
    //  For a WRITE transfer, PWDATA must match HWDATA delayed by TWO cycles.
    //  AHB pipelining: HWDATA is valid one cycle after HADDR; the APB
    //  controller then samples it one more cycle before driving PWDATA.
    //  Waveform: HWDATA=Data1 at T2 → PWDATA=Data1 at T4 (access phase).
    // =========================================================================
    property p_pwdata_two_cycle_delay_from_hwdata;
        @(posedge Hclk) disable iff (!Hresetn)
        (Penable && Pwrite)
        |-> (Pwdata == $past(Hwdata, 2));
    endproperty
    assert_pwdata_two_cycle_delay_from_hwdata :
        assert property (p_pwdata_two_cycle_delay_from_hwdata)
        else $error("FAIL [A8]: PWDATA does not match HWDATA delayed by 2 cycles (write)");

    // =========================================================================
    //  ASSERTION 9 (Write waveform – T3→T5, back-to-back beats)
    //  PENABLE must pulse for exactly ONE clock cycle per APB write transfer;
    //  it must be low both before (setup) and after (inter-beat gap) the pulse.
    //  Waveform: PENABLE is high only at T4, then low at T5 before next setup.
    // =========================================================================
    property p_penable_single_cycle_pulse_write;
        @(posedge Hclk) disable iff (!Hresetn)
        (Penable && Pwrite) |=> !Penable;
    endproperty
    assert_penable_single_cycle_pulse_write :
        assert property (p_penable_single_cycle_pulse_write)
        else $error("FAIL [A9]: PENABLE held high for more than one cycle on a write transfer");

    // =========================================================================
    //  ASSERTION 10 (Write waveform – T3 onward)
    //  PWRITE must remain HIGH for the entire duration of a burst write —
    //  from first PSEL through final PENABLE — and must not toggle mid-burst.
    //  Waveform: PWRITE is high continuously from T3 through T11 for all
    //  four write beats.
    // =========================================================================
    property p_pwrite_high_stable_during_write_burst;
        @(posedge Hclk) disable iff (!Hresetn)
        (psel_active && Pwrite) |=> (psel_active -> Pwrite);
    endproperty
    assert_pwrite_high_stable_during_write_burst :
        assert property (p_pwrite_high_stable_during_write_burst)
        else $error("FAIL [A10]: PWRITE deasserted mid-burst during consecutive write transfers");

endmodule


// =============================================================================
//  Bind block – attaches assertions to the DUT without modifying RTL
// =============================================================================
bind rtl_top ahb_apb_waveform_assertions u_waveform_assertions (
    .Hclk       (Hclk),
    .Hresetn    (Hresetn),
    .Htrans     (Htrans),
    .Hwrite     (Hwrite),
    .Haddr      (Haddr),
    .Hwdata     (Hwdata),
    .Hreadyout  (Hreadyout),
    .Hrdata     (Hrdata),
    .Paddr      (Paddr),
    .Pwrite     (Pwrite),
    .Pselx      (Pselx),
    .Penable    (Penable),
    .Prdata     (Prdata),
    .Pwdata     (Pwdata)
);