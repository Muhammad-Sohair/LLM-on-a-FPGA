// =============================================================================
// Module   : weight_decoder
// Purpose  : Purely combinational base-3 weight decoder for the BitNet b1.58
//            accelerator memory interface.
//
// Packing scheme:
//   packed_byte_in encodes an integer V in [0, 242] representing five
//   ternary weights as base-3 digits:
//
//     V = d0 + d1·3 + d2·9 + d3·27 + d4·81
//
//   where each digit d_i ∈ {0, 1, 2}.
//
// Hardware encoding (aligned with ternary_mac.sv / ternary_vector_dp.sv):
//   base-3 digit 0  →  2'b11  (−1)
//   base-3 digit 1  →  2'b00  ( 0)
//   base-3 digit 2  →  2'b01  (+1)
//
// Synthesis note:
//   Division and modulo by the constants 3, 9, 27, 81 are implemented here
//   with the / and % operators.  Vivado and Quartus synthesise constant-
//   divisor integer division via reciprocal-multiply + shift, which maps
//   entirely to carry-chain-free LUT logic on 7-series / UltraScale devices.
//   The valid input range (0–242) keeps every intermediate value ≤ 8 bits,
//   bounding the LUT depth to approximately log2(243) ≈ 8 LUT levels.
//
//   Inputs beyond 242 (243–255) are architecturally invalid; the digit
//   mapping defaults to 2'b11 (−1) for any out-of-range remainder.
//
// Ports:
//   packed_byte_in  – 8-bit packed base-3 weight value (valid range 0–242)
//   w0 .. w4        – 2-bit ternary-encoded weight outputs (LSB-first order)
//                     w0 corresponds to digit d0 (coefficient of 3^0)
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module weight_decoder (
    input  wire  [7:0] packed_byte_in,
    output logic [1:0] w0,
    output logic [1:0] w1,
    output logic [1:0] w2,
    output logic [1:0] w3,
    output logic [1:0] w4
);

    // -------------------------------------------------------------------------
    // Local function: map one base-3 digit (0, 1, or 2) to the 2-bit hardware
    // encoding used throughout this accelerator.
    // -------------------------------------------------------------------------
    function automatic logic [1:0] digit_to_hw (input logic [1:0] digit);
        case (digit)
            2'd0:    digit_to_hw = 2'b11;   // base-3 zero  → −1
            2'd1:    digit_to_hw = 2'b00;   // base-3 one   →  0
            2'd2:    digit_to_hw = 2'b01;   // base-3 two   → +1
            default: digit_to_hw = 2'b11;   // out-of-range → clamp to −1
        endcase
    endfunction

    // -------------------------------------------------------------------------
    // Intermediate base-3 digit wires (2 bits each; values 0–2 fit in 2 bits)
    // -------------------------------------------------------------------------
    logic [1:0] d0, d1, d2, d3, d4;

    // -------------------------------------------------------------------------
    // Combinational digit extraction and hardware encoding
    //
    //   Cascaded constant division (3, 9, 27, 81) extracts each base-3 digit.
    //   All divisors are powers of 3, so synthesis collapses the chain into
    //   five independent LUT-mapped reciprocal paths with no shared state.
    // -------------------------------------------------------------------------
    always_comb begin
        // --- Extract base-3 digits ---
        d0 = 2'(  packed_byte_in        % 3 );   // coefficient of 3^0
        d1 = 2'( (packed_byte_in /  3)  % 3 );   // coefficient of 3^1
        d2 = 2'( (packed_byte_in /  9)  % 3 );   // coefficient of 3^2
        d3 = 2'( (packed_byte_in / 27)  % 3 );   // coefficient of 3^3
        d4 = 2'( (packed_byte_in / 81)  % 3 );   // coefficient of 3^4

        // --- Map each digit to its 2-bit hardware code ---
        w0 = digit_to_hw(d0);
        w1 = digit_to_hw(d1);
        w2 = digit_to_hw(d2);
        w3 = digit_to_hw(d3);
        w4 = digit_to_hw(d4);
    end

endmodule

`default_nettype wire
