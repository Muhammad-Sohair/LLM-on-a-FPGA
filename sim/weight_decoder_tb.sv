// =============================================================================
// Testbench : weight_decoder_tb
// DUT       : weight_decoder
//
// Purely combinational DUT — no clock required.
// Each vector drives packed_byte_in, waits for propagation (#10 ns), then
// compares all five 2-bit weight outputs against hand-calculated expectations.
//
// Hardware encoding reference (ternary_mac.sv alignment):
//   2'b11 = −1   (base-3 digit 0)
//   2'b00 =  0   (base-3 digit 1)
//   2'b01 = +1   (base-3 digit 2)
//
// Pre-computed expected values:
//
//   V = 0   → digits [0,0,0,0,0] → all 2'b11 (−1)
//   V = 121 → digits [1,1,1,1,1] → all 2'b00 ( 0)
//             Derivation: 1 + 1×3 + 1×9 + 1×27 + 1×81 = 121  ✓
//   V = 242 → digits [2,2,2,2,2] → all 2'b01 (+1)
//             Derivation: 2 + 2×3 + 2×9 + 2×27 + 2×81 = 242  ✓
//   V = 83  → digits [2,0,0,0,1] → w0=01 w1=11 w2=11 w3=11 w4=00
//             Derivation: 2 + 0 + 0 + 0 + 1×81 = 83           ✓
//   V = 112 → digits [1,2,0,1,0] → w0=00 w1=01 w2=11 w3=00 w4=11
//             Derivation: 1 + 2×3 + 0×9 + 1×27 + 0×81
//                       = 1 + 6   + 0   + 27   + 0  = 34  ✗ — recompute:
//             Actually derive forward: want d=[1,2,0,1,0]
//               V = 1 + 6 + 0 + 27 + 0 = 34  → use V=34 instead
//   V = 34  → digits [1,2,0,1,0] → w0=00 w1=01 w2=11 w3=00 w4=11
//             Derivation:
//               34 % 3  = 1  → d0=1 (2'b00)
//               34 / 3  = 11;  11 % 3 = 2  → d1=2 (2'b01)
//               11 / 3  =  3;   3 % 3 = 0  → d2=0 (2'b11)
//                3 / 3  =  1;   1 % 3 = 1  → d3=1 (2'b00)
//                1 / 3  =  0;   0 % 3 = 0  → d4=0 (2'b11)
//             Recheck: 1 + 2×3 + 0×9 + 1×27 + 0×81 = 1+6+0+27+0 = 34  ✓
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module weight_decoder_tb;

    // -------------------------------------------------------------------------
    // Hardware encoding constants
    // -------------------------------------------------------------------------
    localparam logic [1:0] HW_NEG  = 2'b11;  // −1
    localparam logic [1:0] HW_ZERO = 2'b00;  //  0
    localparam logic [1:0] HW_POS  = 2'b01;  // +1

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic [7:0]  packed_byte_in = 8'd0;
    wire  [1:0]  w0, w1, w2, w3, w4;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    weight_decoder dut (
        .packed_byte_in (packed_byte_in),
        .w0             (w0),
        .w1             (w1),
        .w2             (w2),
        .w3             (w3),
        .w4             (w4)
    );

    // -------------------------------------------------------------------------
    // Scoreboard
    // -------------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    // -------------------------------------------------------------------------
    // Task: drive one input, wait for combinational propagation, check outputs
    // -------------------------------------------------------------------------
    task automatic apply_and_check (
        input logic [7:0]  t_in,
        input logic [1:0]  exp_w0, exp_w1, exp_w2, exp_w3, exp_w4,
        input string       label
    );
        packed_byte_in = t_in;
        #10; // combinational propagation window

        if (   w0 === exp_w0
            && w1 === exp_w1
            && w2 === exp_w2
            && w3 === exp_w3
            && w4 === exp_w4) begin

            $display("PASS | %-42s | in=%0d  w={%02b,%02b,%02b,%02b,%02b}",
                     label, t_in, w4, w3, w2, w1, w0);
            pass_count++;

        end else begin

            $display("FAIL | %-42s | in=%0d", label, t_in);
            $display("     |   got     w={%02b,%02b,%02b,%02b,%02b}  (w4..w0)",
                     w4,     w3,     w2,     w1,     w0);
            $display("     |   expected w={%02b,%02b,%02b,%02b,%02b}",
                     exp_w4, exp_w3, exp_w2, exp_w1, exp_w0);
            fail_count++;

        end
    endtask

    // =========================================================================
    // Stimulus
    // =========================================================================
    initial begin
        $display("========================================================");
        $display("  Weight Decoder Testbench");
        $display("  Encoding: 2'b11=-1  2'b00=0  2'b01=+1");
        $display("========================================================");

        // -----------------------------------------------------------------
        // Test Case 1 — V = 0  (all-minimum vector)
        //   All five base-3 digits are 0 → all outputs must be 2'b11 (−1)
        //   Derivation: 0 = 0 + 0·3 + 0·9 + 0·27 + 0·81
        // -----------------------------------------------------------------
        apply_and_check(
            8'd0,
            HW_NEG, HW_NEG, HW_NEG, HW_NEG, HW_NEG,
            "TC1: V=0   digits=[0,0,0,0,0] all -1"
        );

        // -----------------------------------------------------------------
        // Test Case 2 — V = 121  (all-zero vector)
        //   All five base-3 digits are 1 → all outputs must be 2'b00 (0)
        //   Derivation: 1 + 1·3 + 1·9 + 1·27 + 1·81 = 121
        //     d0 = 121 % 3 = 1   (121 = 40·3 + 1)
        //     d1 =  40 % 3 = 1   ( 40 = 13·3 + 1)
        //     d2 =  13 % 3 = 1   ( 13 =  4·3 + 1)
        //     d3 =   4 % 3 = 1   (  4 =  1·3 + 1)
        //     d4 =   1 % 3 = 1
        // -----------------------------------------------------------------
        apply_and_check(
            8'd121,
            HW_ZERO, HW_ZERO, HW_ZERO, HW_ZERO, HW_ZERO,
            "TC2: V=121 digits=[1,1,1,1,1] all  0"
        );

        // -----------------------------------------------------------------
        // Test Case 3 — V = 242  (all-maximum vector)
        //   All five base-3 digits are 2 → all outputs must be 2'b01 (+1)
        //   Derivation: 2 + 2·3 + 2·9 + 2·27 + 2·81 = 242
        // -----------------------------------------------------------------
        apply_and_check(
            8'd242,
            HW_POS, HW_POS, HW_POS, HW_POS, HW_POS,
            "TC3: V=242 digits=[2,2,2,2,2] all +1"
        );

        // -----------------------------------------------------------------
        // Test Case 4 — V = 83  (mixed: only d0=+1 and d4=0)
        //   d0 = 83 % 3 = 2   (83 = 27·3 + 2)  → 2'b01 (+1)
        //   d1 = 27 % 3 = 0   (27 =  9·3 + 0)  → 2'b11 (−1)
        //   d2 =  9 % 3 = 0   ( 9 =  3·3 + 0)  → 2'b11 (−1)
        //   d3 =  3 % 3 = 0   ( 3 =  1·3 + 0)  → 2'b11 (−1)
        //   d4 =  1 % 3 = 1                     → 2'b00 ( 0)
        //   Recheck: 2 + 0·3 + 0·9 + 0·27 + 1·81 = 83  ✓
        // -----------------------------------------------------------------
        apply_and_check(
            8'd83,
            HW_POS, HW_NEG, HW_NEG, HW_NEG, HW_ZERO,
            "TC4: V=83  digits=[2,0,0,0,1]"
        );

        // -----------------------------------------------------------------
        // Test Case 5 — V = 34  (fully mixed digits)
        //   d0 = 34 % 3 = 1   (34 = 11·3 + 1)  → 2'b00 ( 0)
        //   d1 = 11 % 3 = 2   (11 =  3·3 + 2)  → 2'b01 (+1)
        //   d2 =  3 % 3 = 0   ( 3 =  1·3 + 0)  → 2'b11 (−1)
        //   d3 =  1 % 3 = 1                     → 2'b00 ( 0)
        //   d4 =  0 % 3 = 0                     → 2'b11 (−1)
        //   Recheck: 1 + 2·3 + 0·9 + 1·27 + 0·81 = 1+6+0+27+0 = 34  ✓
        // -----------------------------------------------------------------
        apply_and_check(
            8'd34,
            HW_ZERO, HW_POS, HW_NEG, HW_ZERO, HW_NEG,
            "TC5: V=34  digits=[1,2,0,1,0]"
        );

        // -----------------------------------------------------------------
        // Test Case 6 — V = 1  (only d0 is non-minimum)
        //   d0 = 1 → 2'b00 (0),  d1..d4 = 0 → 2'b11 (-1)
        //   Recheck: 1 + 0 + 0 + 0 + 0 = 1  ✓
        // -----------------------------------------------------------------
        apply_and_check(
            8'd1,
            HW_ZERO, HW_NEG, HW_NEG, HW_NEG, HW_NEG,
            "TC6: V=1   digits=[1,0,0,0,0]"
        );

        // =====================================================================
        // Summary
        // =====================================================================
        $display("========================================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("  Overall: %s", (fail_count == 0) ? "PASS" : "FAIL");
        $display("========================================================");

        $finish;
    end

    // -------------------------------------------------------------------------
    // Watchdog — combinational DUT should resolve long before this fires
    // -------------------------------------------------------------------------
    initial begin
        #1000;
        $display("FAIL | Watchdog timeout");
        $finish;
    end

endmodule

`default_nettype wire
