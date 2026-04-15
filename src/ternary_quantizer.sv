// =============================================================================
// Module   : ternary_quantizer
// Purpose  : Purely combinational ternary activation function.
//            Maps a 16-bit signed accumulator value to a 2-bit ternary code
//            using two parameterizable thresholds.
//
// Encoding (output):
//   2'b01  = +1   (input >= POS_TH)
//   2'b11  = -1   (input <= NEG_TH)
//   2'b00  =  0   (NEG_TH < input < POS_TH)
//
// Parameters:
//   IN_W    – input width in bits         (default 16, signed)
//   POS_TH  – positive threshold value    (default +5)
//   NEG_TH  – negative threshold value    (default -5)
//
// Ports:
//   data_in  – IN_W-bit signed input (accumulator result)
//   data_out – 2-bit ternary encoded output
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module ternary_quantizer #(
    parameter  int                    IN_W   = 16,
    parameter  logic signed [IN_W-1:0] POS_TH = 16'sd5,
    parameter  logic signed [IN_W-1:0] NEG_TH = -16'sd5
) (
    input  wire  signed [IN_W-1:0] data_in,
    output logic        [1:0]      data_out
);

    // Encoding constants (local, not parameters, so they don't pollute the
    // parameter namespace of instantiating modules)
    localparam logic [1:0] T_POS  = 2'b01;   // +1
    localparam logic [1:0] T_NEG  = 2'b11;   // -1
    localparam logic [1:0] T_ZERO = 2'b00;   //  0

    always_comb begin
        if      (data_in >= POS_TH) data_out = T_POS;
        else if (data_in <= NEG_TH) data_out = T_NEG;
        else                        data_out = T_ZERO;
    end

endmodule

`default_nettype wire
