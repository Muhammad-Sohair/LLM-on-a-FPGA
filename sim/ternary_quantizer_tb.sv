// =============================================================================
// Testbench : ternary_quantizer_tb
// DUT       : ternary_quantizer (IN_W=16, POS_TH=+5, NEG_TH=-5)
//
// Test vectors (combinational — no clock required):
//
//  #  | data_in | Expected out | Reason
//  ---|---------|--------------|--------------------------------------
//  1  |    +5   |   01 (+1)    | exactly at POS_TH  (boundary >= )
//  2  |   +10   |   01 (+1)    | well above POS_TH
//  3  |  +32767 |   01 (+1)    | max positive 16-bit signed
//  4  |    +4   |   00 ( 0)    | one below POS_TH
//  5  |     0   |   00 ( 0)    | mid-range zero
//  6  |    -4   |   00 ( 0)    | one above NEG_TH
//  7  |    -5   |   11 (-1)    | exactly at NEG_TH  (boundary <=)
//  8  |   -10   |   11 (-1)    | well below NEG_TH
//  9  | -32768  |   11 (-1)    | min negative 16-bit signed
//  10 |    +6   |   01 (+1)    | just above POS_TH
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module ternary_quantizer_tb;

    // -------------------------------------------------------------------------
    // Parameters (must match DUT defaults)
    // -------------------------------------------------------------------------
    localparam int IN_W   = 16;
    localparam int POS_TH =  5;
    localparam int NEG_TH = -5;

    // Ternary output encoding
    localparam logic [1:0] T_POS  = 2'b01;
    localparam logic [1:0] T_NEG  = 2'b11;
    localparam logic [1:0] T_ZERO = 2'b00;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic signed [IN_W-1:0] data_in  = '0;
    logic        [1:0]      data_out;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    ternary_quantizer #(
        .IN_W  (IN_W),
        .POS_TH(16'(signed'(POS_TH))),
        .NEG_TH(16'(signed'(NEG_TH)))
    ) dut (
        .data_in (data_in),
        .data_out(data_out)
    );

    // -------------------------------------------------------------------------
    // Counters
    // -------------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    // -------------------------------------------------------------------------
    // Task: drive input, wait for propagation, compare output
    // -------------------------------------------------------------------------
    task automatic apply_and_check(
        input logic signed [IN_W-1:0] t_in,
        input logic        [1:0]      expected,
        input string                  test_name
    );
        data_in = t_in;
        #10; // combinational propagation delay
        if (data_out === expected) begin
            $display("PASS | %-40s | data_in=%0d  out=%02b (expected %02b)",
                     test_name, t_in, data_out, expected);
            pass_count++;
        end else begin
            $display("FAIL | %-40s | data_in=%0d  out=%02b (expected %02b)",
                     test_name, t_in, data_out, expected);
            fail_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        $display("========================================================");
        $display("  Ternary Quantizer Testbench  (POS_TH=%0d, NEG_TH=%0d)",
                 POS_TH, NEG_TH);
        $display("========================================================");

        // --- Positive region ---
        apply_and_check( 16'sd5,     T_POS,  "Vec  1: in= +5  (== POS_TH)  -> +1");
        apply_and_check( 16'sd10,    T_POS,  "Vec  2: in=+10  (> POS_TH)   -> +1");
        apply_and_check( 16'sd32767, T_POS,  "Vec  3: in=MAX  (>> POS_TH)  -> +1");
        apply_and_check( 16'sd6,     T_POS,  "Vec 10: in= +6  (> POS_TH)   -> +1");

        // --- Zero region ---
        apply_and_check( 16'sd4,     T_ZERO, "Vec  4: in= +4  (< POS_TH)   ->  0");
        apply_and_check( 16'sd0,     T_ZERO, "Vec  5: in=  0  (mid-range)   ->  0");
        apply_and_check(-16'sd4,     T_ZERO, "Vec  6: in= -4  (> NEG_TH)   ->  0");

        // --- Negative region ---
        apply_and_check(-16'sd5,     T_NEG,  "Vec  7: in= -5  (== NEG_TH)  -> -1");
        apply_and_check(-16'sd10,    T_NEG,  "Vec  8: in=-10  (< NEG_TH)   -> -1");
        apply_and_check(-16'sd32768, T_NEG,  "Vec  9: in=MIN  (<< NEG_TH)  -> -1");

        // -------------------------------------------------------------------------
        // Summary
        // -------------------------------------------------------------------------
        $display("========================================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("  Overall: %s", (fail_count == 0) ? "PASS" : "FAIL");
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
