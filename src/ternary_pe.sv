// =============================================================================
// Module   : ternary_pe  (Ternary Processing Element)
// Purpose  : Integrates a ternary_mac and a ternary_quantizer into a single
//            processing element.  The MAC accumulates ternary multiply-results
//            each enabled clock cycle; the quantizer continuously maps the
//            running accumulator to a 2-bit ternary output.
//
// Data-flow:
//   (w, a) --> ternary_mac (ACC_W-bit signed acc)
//                               |
//                               v
//                        ternary_quantizer --> t_out (2-bit ternary)
//
// Encoding (shared by all three layers):
//   2'b01  = +1
//   2'b11  = -1
//   2'b00  =  0
//
// Parameters:
//   ACC_W   – accumulator width forwarded to ternary_mac  (default 16)
//   POS_TH  – positive quantizer threshold                (default +5)
//   NEG_TH  – negative quantizer threshold                (default -5)
//
// Ports:
//   clk    – clock (rising edge)
//   rst    – synchronous active-high reset (clears the accumulator)
//   en     – enable; MAC accumulates on this cycle when asserted
//   w      – 2-bit ternary weight
//   a      – 2-bit ternary activation
//   t_out  – 2-bit ternary quantized output
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module ternary_pe #(
    parameter int                      ACC_W  = 16,
    parameter logic signed [ACC_W-1:0] POS_TH = 16'sd5,
    parameter logic signed [ACC_W-1:0] NEG_TH = -16'sd5
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,
    input  wire [1:0]  w,       // ternary weight
    input  wire [1:0]  a,       // ternary activation
    output wire [1:0]  t_out    // quantized ternary output
);

    // -------------------------------------------------------------------------
    // Internal wire: ACC_W-bit signed accumulator from MAC to quantizer
    // -------------------------------------------------------------------------
    logic signed [ACC_W-1:0] acc_wire;

    // -------------------------------------------------------------------------
    // Sub-module: Multiplier-Less Ternary MAC
    // -------------------------------------------------------------------------
    ternary_mac #(
        .ACC_W(ACC_W)
    ) u_mac (
        .clk (clk),
        .rst (rst),
        .en  (en),
        .w   (w),
        .a   (a),
        .acc (acc_wire)
    );

    // -------------------------------------------------------------------------
    // Sub-module: Ternary Quantizer (combinational)
    // -------------------------------------------------------------------------
    ternary_quantizer #(
        .IN_W  (ACC_W),
        .POS_TH(POS_TH),
        .NEG_TH(NEG_TH)
    ) u_quant (
        .data_in (acc_wire),
        .data_out(t_out)
    );

endmodule

`default_nettype wire
