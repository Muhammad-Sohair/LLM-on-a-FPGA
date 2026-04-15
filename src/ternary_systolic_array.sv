// =============================================================================
// Module   : ternary_systolic_array
// Purpose  : Top-level 4x16 ternary systolic array for the BitNet b1.58
//            LLM accelerator.
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module ternary_systolic_array #(
    parameter int ROWS        = 4,
    parameter int VECTOR_SIZE = 16,
    parameter int ACT_WIDTH   = 8,
    parameter int ACC_WIDTH   = 16
) (
    input  wire                                 clk,
    input  wire                                 rst_n,
    input  wire                                 en,
    input  wire [(VECTOR_SIZE * ACT_WIDTH)-1:0] act_vector_in,
    input  wire [103:0]                         packed_weights_in,
    output wire [(ROWS * ACC_WIDTH)-1:0]        matrix_out,
    output wire                                 valid_out
);

    // -------------------------------------------------------------------------
    // Derived constants
    // -------------------------------------------------------------------------
    localparam int NUM_DECODERS  = 13;               // ceil(ROWS*VECTOR_SIZE / 5)
    localparam int TOTAL_WEIGHTS = NUM_DECODERS * 5; // 65 (weight 64 unused)
    localparam int FLAT_W        = TOTAL_WEIGHTS * 2; // 130 bits

    // =========================================================================
    // Stage 1 — Weight Unpacking (purely combinational)
    // =========================================================================
    // BUG FIX: Completely eliminated 2D/unpacked arrays. We wire the decoder
    // outputs directly into the specific 2-bit slices of a single flat vector.
    // This guarantees Vivado XSIM routes the connections physically.
    wire [FLAT_W-1:0] unpacked_weights_flat;

    genvar d;
    generate
        for (d = 0; d < NUM_DECODERS; d++) begin : gen_weight_decoders
            weight_decoder u_wdec (
                .packed_byte_in (packed_weights_in[8*d +: 8]),
                .w0             (unpacked_weights_flat[(5*d + 0)*2 +: 2]),
                .w1             (unpacked_weights_flat[(5*d + 1)*2 +: 2]),
                .w2             (unpacked_weights_flat[(5*d + 2)*2 +: 2]),
                .w3             (unpacked_weights_flat[(5*d + 3)*2 +: 2]),
                .w4             (unpacked_weights_flat[(5*d + 4)*2 +: 2])
            );
        end
    endgenerate

    // =========================================================================
    // Stage 2 & 3 — Matrix Compute & Output Assembly
    // =========================================================================
    // BUG FIX: Removed the intermediate `row_result` array and always_comb block.
    // We now map the matrix_out packed array directly to the dot_product_out ports.
    wire [ROWS-1:0] vector_valid;

    genvar r;
    generate
        for (r = 0; r < ROWS; r++) begin : gen_dp_rows
            ternary_vector_dp #(
                .VECTOR_SIZE (VECTOR_SIZE),
                .ACT_WIDTH   (ACT_WIDTH),
                .ACC_WIDTH   (ACC_WIDTH)
            ) u_vdp (
                .clk             (clk),
                .rst_n           (rst_n),
                .en              (en),
                .act_vector_in   (act_vector_in),
                .weight_vector_in(unpacked_weights_flat[r * VECTOR_SIZE * 2 +: VECTOR_SIZE * 2]),
                .dot_product_out (matrix_out[r * ACC_WIDTH +: ACC_WIDTH]),
                .valid_out       (vector_valid[r])
            );
        end
    endgenerate

    assign valid_out = vector_valid[0];

endmodule

`default_nettype wire