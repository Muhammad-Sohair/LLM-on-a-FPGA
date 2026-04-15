// =============================================================================
// Testbench : tb_ternary_vector_dp
// DUT       : ternary_vector_dp (VECTOR_SIZE=16, ACT_WIDTH=8, ACC_WIDTH=16)
//
// Clock     : 100 MHz (10 ns period)
//
// Pipeline depth: PIPE_DEPTH = 1 + log2(16) = 5 clock cycles
//
// ─────────────────────────────────────────────────────────────────────────────
// Test 1 — Symmetric cancellation (expected result = 0)
//
//   All 16 activations         = 8'd10
//   Weights [0..7]  (low half) = 2'b01 (+1)
//   Weights [8..15] (hi  half) = 2'b11 (-1)
//
//   Partial products:
//     Lanes 0-7  : +1 × 10 = +10  →  8 × 10 = +80
//     Lanes 8-15 : -1 × 10 = -10  →  8 × 10 = -80
//     Sum        :  80 − 80 = 0
//
// ─────────────────────────────────────────────────────────────────────────────
// Test 2 — Asymmetric mix (expected result = +24)
//
//   All 16 activations          = 8'd3
//   Weights [0..11] (3 quarters)= 2'b01 (+1)
//   Weights [12..15](last quart)= 2'b11 (-1)
//
//   Partial products:
//     Lanes 0-11  : +1 × 3 = +3  →  12 × 3 = +36
//     Lanes 12-15 : -1 × 3 = -3  →   4 × 3 = -12
//     Sum         :  36 − 12 = +24
//
// Weight encoding (same as ternary_mac.sv):
//   2'b01 = +1   |   2'b11 = -1   |   2'b00 = 0
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module tb_ternary_vector_dp;

    // -------------------------------------------------------------------------
    // DUT parameters
    // -------------------------------------------------------------------------
    localparam int VECTOR_SIZE = 16;
    localparam int ACT_WIDTH   = 8;
    localparam int ACC_WIDTH   = 16;

    localparam int TREE_LEVELS = $clog2(VECTOR_SIZE);   // 4
    localparam int PIPE_DEPTH  = 1 + TREE_LEVELS;       // 5

    // Ternary weight encoding aliases
    localparam logic [1:0] W_POS  = 2'b01;   // +1
    localparam logic [1:0] W_NEG  = 2'b11;   // -1
    localparam logic [1:0] W_ZERO = 2'b00;   //  0

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                                  clk             = 1'b0;
    logic                                  rst_n           = 1'b0;
    logic                                  en              = 1'b0;
    logic [(VECTOR_SIZE * ACT_WIDTH)-1:0]  act_vector_in   = '0;
    logic [(VECTOR_SIZE * 2)-1:0]          weight_vector_in = '0;
    logic signed [ACC_WIDTH-1:0]           dot_product_out;
    logic                                  valid_out;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    ternary_vector_dp #(
        .VECTOR_SIZE(VECTOR_SIZE),
        .ACT_WIDTH  (ACT_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .en              (en),
        .act_vector_in   (act_vector_in),
        .weight_vector_in(weight_vector_in),
        .dot_product_out (dot_product_out),
        .valid_out       (valid_out)
    );

    // -------------------------------------------------------------------------
    // 100 MHz clock
    // -------------------------------------------------------------------------
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Scoreboard
    // -------------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    // -------------------------------------------------------------------------
    // Task: fire one vector, wait for pipeline to drain, check result.
    //
    //   Applies (act, wgt) with en=1 for exactly ONE rising edge, then holds
    //   en=0.  After PIPE_DEPTH posedges the result must be stable and
    //   valid_out must be asserted.
    // -------------------------------------------------------------------------
    task automatic fire_and_check (
        input logic [(VECTOR_SIZE * ACT_WIDTH)-1:0] t_act,
        input logic [(VECTOR_SIZE * 2)-1:0]         t_wgt,
        input logic signed [ACC_WIDTH-1:0]           expected,
        input string                                 label
    );
        // Drive inputs synchronously before the active clock edge
        act_vector_in    = t_act;
        weight_vector_in = t_wgt;
        en               = 1'b1;

        @(posedge clk);          // Edge 1/5 — Stage 1 latches products
        en = 1'b0;               // de-assert; pipeline free-runs from here

        repeat (PIPE_DEPTH - 1) @(posedge clk);   // Edges 2-5
        #1;  // small delta to allow combinational output assignments to settle

        // ---- Assertions ----
        if (!valid_out) begin
            $display("FAIL | %-45s | valid_out not asserted after %0d cycles",
                     label, PIPE_DEPTH);
            fail_count++;
        end else if (dot_product_out !== expected) begin
            $display("FAIL | %-45s | got %0d, expected %0d",
                     label, dot_product_out, expected);
            fail_count++;
        end else begin
            $display("PASS | %-45s | dot_product_out = %0d", label, dot_product_out);
            pass_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Task: apply synchronous reset between test cases
    // -------------------------------------------------------------------------
    task automatic do_reset ();
        rst_n = 1'b0;
        en    = 1'b0;
        repeat (3) @(posedge clk);
        #1;
        rst_n = 1'b1;
        @(posedge clk); #1;
    endtask

    // =========================================================================
    // Stimulus
    // =========================================================================
    initial begin
        $display("=============================================================");
        $display("  Ternary Vector Dot-Product Testbench");
        $display("  VECTOR_SIZE=%0d  ACT_WIDTH=%0d  ACC_WIDTH=%0d  PIPE_DEPTH=%0d",
                 VECTOR_SIZE, ACT_WIDTH, ACC_WIDTH, PIPE_DEPTH);
        $display("=============================================================");

        // Initial reset
        do_reset();

       // -----------------------------------------------------------------
        // Test 1: Symmetric cancellation -> expected 0
        //
        //   act_vector_in    = { 16 x 8'd10 }
        //   weight_vector_in = { 8 x W_NEG, 8 x W_POS }
        //   Manual check: (8 * -10) + (8 * +10) = 0
        // -----------------------------------------------------------------
        $display("-- Test 1: act=10 (all), w=[+1x8 | -1x8], expected = 0 --");
        fire_and_check(
            {16{8'd10}},                          // Correct: replication
            {{8{W_NEG}}, {8{W_POS}}},             // Fixed: Nested braces for concat
            16'sd0,
            "T1: symmetric cancel (80-80=0)"
        );

        // -----------------------------------------------------------------
        // Test 2: Asymmetric mix -> expected +24
        //
        //   act_vector_in    = { 16 x 8'd3 }
        //   weight_vector_in = { 4 x W_NEG, 12 x W_POS }
        //   Manual verification:
        //     Lanes  0-11: +1 * 3 = +3  -> 12 * 3 = +36
        //     Lanes 12-15: -1 * 3 = -3  ->  4 * 3 = -12
        //     Dot product: 36 - 12 = +24
        // -----------------------------------------------------------------
        do_reset();
        $display("-- Test 2: act=3 (all), w=[+1x12 | -1x4], expected = +24 --");
        fire_and_check(
            {16{8'd3}},                           // Correct: replication
            {{4{W_NEG}}, {12{W_POS}}},            // Fixed: Nested braces for concat
            16'sd24,
            "T2: asymmetric mix (36-12=24)"
        );

        // -----------------------------------------------------------------
        // Test 3: All-zero weights -> expected 0 (zero-weight gate)
        // -----------------------------------------------------------------
        do_reset();
        $display("-- Test 3: act=50 (all), w=0 (all), expected = 0 --");
        fire_and_check(
            {16{8'd50}},
            {16{W_ZERO}},
            16'sd0,
            "T3: all zero weights"                // No trailing comma here
        );

        // -----------------------------------------------------------------
        // Test 4: Single active lane → expected +7
        //   Only lane 0 has a non-zero weight (+1), activation = 7.
        //   All other lanes have zero weight.
        //
        //   Vector construction (inline):
        //     act_vector_in   = {16{8'd7}}
        //     weight_vector_in:
        //       bits [1:0]   = W_POS  → lane 0  = +1
        //       bits [31:2]  = 15×W_ZERO → lanes 1-15 = 0
        //       → {{(VECTOR_SIZE-1){W_ZERO}}, W_POS}
        //         (concatenation: MSB first, so W_ZERO occupies high bits,
        //          W_POS occupies the two LSBs that map to lane 0)
        // -----------------------------------------------------------------
        do_reset();
        $display("-- Test 4: single active lane (w[0]=+1, a[0]=7), expected = +7 --");
        fire_and_check(
            {16{8'd7}},
            {{(VECTOR_SIZE-1){W_ZERO}}, W_POS},
            16'sd7,
            "T4: single lane (1×7=7)"
        );

        // -----------------------------------------------------------------
        // Test 5: All-negative weights with large activation → expected -160
        //   All activations = 8'd10, all weights = -1
        //   16 × (−1 × 10) = −160
        // -----------------------------------------------------------------
        do_reset();
        $display("-- Test 5: act=10 (all), w=-1 (all), expected = -160 --");
        fire_and_check(
            {16{8'd10}},
            {16{W_NEG}},
            -16'sd160,                // -160 as signed 16-bit literal
            "T5: all -1 weights (16×-1×10=-160)"
        );

        // =====================================================================
        // Summary
        // =====================================================================
        $display("=============================================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("  Overall: %s", (fail_count == 0) ? "PASS" : "FAIL");
        $display("=============================================================");

        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout watchdog — prevent simulator hang on broken DUT
    // -------------------------------------------------------------------------
    initial begin
        #5000;
        $display("FAIL | Watchdog timeout at %0t ns", $time);
        $finish;
    end

endmodule

`default_nettype wire
