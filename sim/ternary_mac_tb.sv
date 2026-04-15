// =============================================================================
// Testbench : ternary_mac_tb
// DUT       : ternary_mac (ACC_W = 16)
//
// Covers (≤ 10 active clock cycles):
//   Cycle 1 : w=+1, a=+1  -> acc expected +1
//   Cycle 2 : w=+1, a=+1  -> acc expected +2
//   Cycle 3 : w=-1, a=+1  -> acc expected +1
//   Cycle 4 : w=-1, a=-1  -> acc expected +2
//   Cycle 5 : w=+1, a=-1  -> acc expected +1
//   Cycle 6 : w= 0, a=+1  -> acc expected +1  (zero weight, no change)
//   Cycle 7 : w=+1, a= 0  -> acc expected +1  (zero activation, no change)
//   Cycle 8 : en=0, w=+1,a=+1 -> acc expected +1 (disabled, no change)
//   Cycle 9 : synchronous reset -> acc expected  0
//   Cycle 10: w=-1, a=-1  -> acc expected +1 (after reset)
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module ternary_mac_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam int ACC_W = 16;

    // Ternary encoding constants
    localparam logic [1:0] T_ZERO = 2'b00;
    localparam logic [1:0] T_POS  = 2'b01;  // +1
    localparam logic [1:0] T_NEG  = 2'b11;  // -1

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic        clk  = 1'b0;
    logic        rst  = 1'b0;
    logic        en   = 1'b0;
    logic [1:0]  w    = T_ZERO;
    logic [1:0]  a    = T_ZERO;
    logic signed [ACC_W-1:0] acc;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    ternary_mac #(
        .ACC_W(ACC_W)
    ) dut (
        .clk (clk),
        .rst (rst),
        .en  (en),
        .w   (w),
        .a   (a),
        .acc (acc)
    );

    // -------------------------------------------------------------------------
    // Clock generation: 10 ns period
    // -------------------------------------------------------------------------
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Task: apply one stimulus cycle and check expected accumulator value
    // -------------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    task automatic apply_and_check(
        input logic        t_en,
        input logic [1:0]  t_w,
        input logic [1:0]  t_a,
        input logic        t_rst,
        input logic signed [ACC_W-1:0] expected,
        input string       test_name
    );
        // Apply stimuli before rising edge
        en  = t_en;
        w   = t_w;
        a   = t_a;
        rst = t_rst;
        @(posedge clk);
        #1; // small delta to let outputs settle
        if (acc === expected) begin
            $display("PASS | %-35s | acc = %0d (expected %0d)", test_name, acc, expected);
            pass_count++;
        end else begin
            $display("FAIL | %-35s | acc = %0d (expected %0d)", test_name, acc, expected);
            fail_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        $display("========================================================");
        $display("  Ternary MAC Testbench  (ACC_W=%0d)", ACC_W);
        $display("========================================================");

        // --- Initial reset (not counted as a simulation cycle) ---
        rst = 1'b1;
        en  = 1'b0;
        @(posedge clk); #1;
        rst = 1'b0;

        // Cycle 1: +1 * +1 = +1  ->  acc: 0 + 1 = 1
        apply_and_check(1, T_POS,  T_POS,  0, 16'sd1,  "Cycle 1: (+1)(+1) -> +1");

        // Cycle 2: +1 * +1 = +1  ->  acc: 1 + 1 = 2
        apply_and_check(1, T_POS,  T_POS,  0, 16'sd2,  "Cycle 2: (+1)(+1) -> +2");

        // Cycle 3: -1 * +1 = -1  ->  acc: 2 - 1 = 1
        apply_and_check(1, T_NEG,  T_POS,  0, 16'sd1,  "Cycle 3: (-1)(+1) -> +1");

        // Cycle 4: -1 * -1 = +1  ->  acc: 1 + 1 = 2
        apply_and_check(1, T_NEG,  T_NEG,  0, 16'sd2,  "Cycle 4: (-1)(-1) -> +2");

        // Cycle 5: +1 * -1 = -1  ->  acc: 2 - 1 = 1
        apply_and_check(1, T_POS,  T_NEG,  0, 16'sd1,  "Cycle 5: (+1)(-1) -> +1");

        // Cycle 6: 0 * +1 = 0   ->  acc: 1 (no change)
        apply_and_check(1, T_ZERO, T_POS,  0, 16'sd1,  "Cycle 6: ( 0)(+1) -> +1 hold");

        // Cycle 7: +1 * 0 = 0   ->  acc: 1 (no change)
        apply_and_check(1, T_POS,  T_ZERO, 0, 16'sd1,  "Cycle 7: (+1)( 0) -> +1 hold");

        // Cycle 8: en=0 (disabled) -> acc: 1 (no change even though w,a non-zero)
        apply_and_check(0, T_POS,  T_POS,  0, 16'sd1,  "Cycle 8: en=0     -> +1 hold");

        // Cycle 9: synchronous reset -> acc = 0
        apply_and_check(1, T_POS,  T_POS,  1, 16'sd0,  "Cycle 9: rst=1    -> 0 reset");

        // Cycle 10: -1 * -1 = +1  ->  acc: 0 + 1 = 1 (fresh start after reset)
        apply_and_check(1, T_NEG,  T_NEG,  0, 16'sd1,  "Cycle 10: (-1)(-1) after rst");

        // -------------------------------------------------------------------------
        // Summary
        // -------------------------------------------------------------------------
        $display("========================================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0)
            $display("  Overall: PASS");
        else
            $display("  Overall: FAIL");
        $display("========================================================");

        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout watchdog
    // -------------------------------------------------------------------------
    initial begin
        #500;
        $display("FAIL | Watchdog timeout — simulation did not finish");
        $finish;
    end

endmodule

`default_nettype wire
