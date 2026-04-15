// =============================================================================
// Testbench : ternary_pe_tb
// DUT       : ternary_pe (ACC_W=16, POS_TH=+5, NEG_TH=-5)
//
// Strategy:
//   Two independent accumulation runs, each feeding 5 identical ternary pairs
//   so that the MAC crosses the threshold exactly on cycle 5.
//
//   Run A – positive saturation:
//     Feed w=+1, a=+1  for 5 cycles  -> acc goes 0,1,2,3,4,5
//     At cycle 5  acc == +5 == POS_TH  => quantizer outputs 2'b01 (+1)
//
//   Run B – negative saturation:
//     Feed w=+1, a=-1  for 5 cycles  -> acc goes 0,-1,-2,-3,-4,-5
//     At cycle 5  acc == -5 == NEG_TH  => quantizer outputs 2'b11 (-1)
//
//   Intermediate checks every cycle confirm the zero-region output (2'b00)
//   while the accumulator is still between the thresholds (cycles 1-4).
//
//   Cycle map (each run):
//     Cycle | acc after edge | Expected t_out
//     ------|----------------|----------------
//       1   |      ±1        |   00  (zero)
//       2   |      ±2        |   00  (zero)
//       3   |      ±3        |   00  (zero)
//       4   |      ±4        |   00  (zero)
//       5   |      ±5        |   01 / 11  (threshold crossed)
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module ternary_pe_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam int ACC_W  = 16;
    localparam int POS_TH =  5;
    localparam int NEG_TH = -5;

    localparam logic [1:0] T_POS  = 2'b01;
    localparam logic [1:0] T_NEG  = 2'b11;
    localparam logic [1:0] T_ZERO = 2'b00;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic        clk   = 1'b0;
    logic        rst   = 1'b0;
    logic        en    = 1'b0;
    logic [1:0]  w     = T_ZERO;
    logic [1:0]  a     = T_ZERO;
    wire  [1:0]  t_out;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    ternary_pe #(
        .ACC_W  (ACC_W),
        .POS_TH (16'(signed'(POS_TH))),
        .NEG_TH (16'(signed'(NEG_TH)))
    ) dut (
        .clk  (clk),
        .rst  (rst),
        .en   (en),
        .w    (w),
        .a    (a),
        .t_out(t_out)
    );

    // -------------------------------------------------------------------------
    // Clock: 10 ns period
    // -------------------------------------------------------------------------
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Scoreboard
    // -------------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    // -------------------------------------------------------------------------
    // Task: apply stimulus, clock once, sample and verify
    // -------------------------------------------------------------------------
    task automatic clk_and_check(
        input logic [1:0] t_w,
        input logic [1:0] t_a,
        input logic [1:0] expected,
        input string      label
    );
        w = t_w;
        a = t_a;
        @(posedge clk);
        #1; // delta settle
        if (t_out === expected) begin
            $display("PASS | %-50s | t_out=%02b (expected %02b)",
                     label, t_out, expected);
            pass_count++;
        end else begin
            $display("FAIL | %-50s | t_out=%02b (expected %02b)",
                     label, t_out, expected);
            fail_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Helper: synchronous reset between runs
    // -------------------------------------------------------------------------
    task automatic do_reset();
        en  = 1'b0;
        w   = T_ZERO;
        a   = T_ZERO;
        rst = 1'b1;
        @(posedge clk); #1;
        rst = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        $display("============================================================");
        $display("  Ternary PE Testbench  (POS_TH=%0d, NEG_TH=%0d)", POS_TH, NEG_TH);
        $display("============================================================");

        // Initial reset
        do_reset();
        en = 1'b1;

        // ----------------------------------------------------------------
        // Run A: positive saturation
        //   w=+1, a=+1 => +1 per cycle; threshold +5 crossed on cycle 5
        // ----------------------------------------------------------------
        $display("-- Run A: w=+1, a=+1 (positive accumulation) --");

        clk_and_check(T_POS, T_POS, T_ZERO, "A Cy1: acc=+1, below POS_TH  -> 0");
        clk_and_check(T_POS, T_POS, T_ZERO, "A Cy2: acc=+2, below POS_TH  -> 0");
        clk_and_check(T_POS, T_POS, T_ZERO, "A Cy3: acc=+3, below POS_TH  -> 0");
        clk_and_check(T_POS, T_POS, T_ZERO, "A Cy4: acc=+4, below POS_TH  -> 0");
        clk_and_check(T_POS, T_POS, T_POS,  "A Cy5: acc=+5, == POS_TH     -> +1");

        // ----------------------------------------------------------------
        // Run B: negative saturation
        //   w=+1, a=-1 => -1 per cycle; threshold -5 crossed on cycle 5
        // ----------------------------------------------------------------
        do_reset();
        en = 1'b1;
        $display("-- Run B: w=+1, a=-1 (negative accumulation) --");

        clk_and_check(T_POS, T_NEG, T_ZERO, "B Cy1: acc=-1, above NEG_TH  -> 0");
        clk_and_check(T_POS, T_NEG, T_ZERO, "B Cy2: acc=-2, above NEG_TH  -> 0");
        clk_and_check(T_POS, T_NEG, T_ZERO, "B Cy3: acc=-3, above NEG_TH  -> 0");
        clk_and_check(T_POS, T_NEG, T_ZERO, "B Cy4: acc=-4, above NEG_TH  -> 0");
        clk_and_check(T_POS, T_NEG, T_NEG,  "B Cy5: acc=-5, == NEG_TH     -> -1");

        // ----------------------------------------------------------------
        // Run C: en=0 mid-sequence — accumulator must not advance
        // ----------------------------------------------------------------
        do_reset();
        $display("-- Run C: enable gate check --");

        // Two enabled cycles -> acc = +2
        en = 1'b1;
        clk_and_check(T_POS, T_POS, T_ZERO, "C Cy1: en=1, acc=+1          -> 0");
        clk_and_check(T_POS, T_POS, T_ZERO, "C Cy2: en=1, acc=+2          -> 0");

        // Disable; three more presented inputs must not change accumulator
        en = 1'b0;
        clk_and_check(T_POS, T_POS, T_ZERO, "C Cy3: en=0, acc holds +2    -> 0");
        clk_and_check(T_POS, T_POS, T_ZERO, "C Cy4: en=0, acc holds +2    -> 0");
        clk_and_check(T_POS, T_POS, T_ZERO, "C Cy5: en=0, acc holds +2    -> 0");

        // ----------------------------------------------------------------
        // Summary
        // ----------------------------------------------------------------
        $display("============================================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("  Overall: %s", (fail_count == 0) ? "PASS" : "FAIL");
        $display("============================================================");

        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout watchdog
    // -------------------------------------------------------------------------
    initial begin
        #2000;
        $display("FAIL | Watchdog timeout — simulation did not finish");
        $finish;
    end

endmodule

`default_nettype wire
