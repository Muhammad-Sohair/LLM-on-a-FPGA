// =============================================================================
// Module   : ternary_mac
// Purpose  : Multiplier-Less Ternary Multiply-Accumulate unit.
//
// Encoding (2-bit):
//   2'b00  =  0  (zero weight / zero activation)
//   2'b01  = +1
//   2'b11  = -1
//
// Operation per clock (when en == 1):
//   acc <= acc + weight_mul(w, a)
//
//   weight_mul is performed WITHOUT the * operator:
//     w == 2'b01 (+1) : acc += a_signed
//     w == 2'b11 (-1) : acc -= a_signed
//     otherwise (0)   : acc unchanged
//
// Parameters:
//   ACC_W  – accumulator width (default 16)
//
// Ports:
//   clk    – clock (rising edge)
//   rst    – synchronous active-high reset
//   en     – enable; accumulates on the current cycle when asserted
//   w      – 2-bit ternary weight  {00,01,11}
//   a      – 2-bit ternary activation {00,01,11}
//   acc    – ACC_W-bit signed accumulator output
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module ternary_mac #(
    parameter int ACC_W = 16
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,
    input  wire [1:0]  w,      // ternary weight encoding
    input  wire [1:0]  a,      // ternary activation encoding
    output logic signed [ACC_W-1:0] acc
);

    // -------------------------------------------------------------------------
    // Decode ternary inputs to signed {-1, 0, +1}
    // Only 2'b01 (+1) and 2'b11 (-1) are valid non-zero values.
    // -------------------------------------------------------------------------
    logic w_pos, w_neg;   // weight is +1 or -1
    logic a_pos, a_neg;   // activation is +1 or -1

    assign w_pos = (w == 2'b01);
    assign w_neg = (w == 2'b11);
    assign a_pos = (a == 2'b01);
    assign a_neg = (a == 2'b11);

    // -------------------------------------------------------------------------
    // Multiplier-less ternary product:
    //   product(w, a) = sign(w) * sign(a)
    //   sign table:
    //     (+1)(+1) = +1  -> add +1
    //     (+1)(-1) = -1  -> add -1
    //     (-1)(+1) = -1  -> add -1
    //     (-1)(-1) = +1  -> add +1
    //     (0 )(*)  =  0  -> no change
    //     (*)(0 )  =  0  -> no change
    // -------------------------------------------------------------------------
    logic do_add, do_sub;   // final accumulator operation

    always_comb begin
        do_add = 1'b0;
        do_sub = 1'b0;
        if (en) begin
            // w=+1, a=+1  -> +1
            if (w_pos && a_pos) do_add = 1'b1;
            // w=+1, a=-1  -> -1
            else if (w_pos && a_neg) do_sub = 1'b1;
            // w=-1, a=+1  -> -1
            else if (w_neg && a_pos) do_sub = 1'b1;
            // w=-1, a=-1  -> +1
            else if (w_neg && a_neg) do_add = 1'b1;
            // all other cases (zero weight or zero activation): no change
        end
    end

    // -------------------------------------------------------------------------
    // Synchronous accumulator — no multiplier, only +1 / -1 increments
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            acc <= '0;
        end else if (do_add) begin
            acc <= acc + {{(ACC_W-1){1'b0}}, 1'b1};   // acc + 1
        end else if (do_sub) begin
            acc <= acc - {{(ACC_W-1){1'b0}}, 1'b1};   // acc - 1
        end
        // else: accumulator holds
    end

endmodule

`default_nettype wire
