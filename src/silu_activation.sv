// =============================================================================
// Module   : silu_activation
// Purpose  : ROM-based SiLU / Swish activation for the BitNet accelerator.
//
//   y = x / (1 + e^(-x))  =  x * sigmoid(x)
//
// Architecture
// ------------
//   * Input x_in is treated as a Q8.8 signed fixed-point value: the upper 8
//     bits are the integer part, the lower 8 are fractional.
//   * The ROM is addressed by x_in[15:8] (an 8-bit field, naturally signed:
//     0x00..0x7F -> 0..+127, 0x80..0xFF -> -128..-1).  This is a deliberately
//     coarse approximation: we ignore the fractional part of x, giving 256
//     integer-spaced samples of SiLU(x) across the [-128, +127] range.
//   * ROM entries are pre-computed as round( x * sigmoid(x) * 256 ) so they
//     land back in Q8.8 signed.  For |x| >= 11 the function approaches x
//     (positive) or 0 (negative) quickly enough that those regions collapse
//     to the linear tail (x * 256) or to zero.
//   * A single pipeline register delays the ROM output by 1 cycle.  valid_out
//     is the 1-cycle-delayed `en`.
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module silu_activation #(
    parameter int DATA_WIDTH = 16
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         en,
    input  wire signed [DATA_WIDTH-1:0] x_in,
    output logic signed [DATA_WIDTH-1:0] y_out,
    output logic                         valid_out
);

    // -------------------------------------------------------------------------
    // ROM
    // -------------------------------------------------------------------------
    logic signed [DATA_WIDTH-1:0] rom [0:255];

    initial begin
        // Default: anything in the deep-negative tail is zero
        for (int i = 0; i < 256; i++) rom[i] = '0;

        // --- Positive half: index 0..127  (x = 0, 1, 2, ..., 127) -----------
        // Small-x region where SiLU differs meaningfully from the identity.
        rom[  0] = 16'sd0;      //  x =  0  -> 0.0000
        rom[  1] = 16'sd187;    //  x =  1  -> 0.7311
        rom[  2] = 16'sd451;    //  x =  2  -> 1.7616
        rom[  3] = 16'sd732;    //  x =  3  -> 2.8577
        rom[  4] = 16'sd1006;   //  x =  4  -> 3.9281
        rom[  5] = 16'sd1271;   //  x =  5  -> 4.9665
        rom[  6] = 16'sd1532;   //  x =  6  -> 5.9851
        rom[  7] = 16'sd1790;   //  x =  7  -> 6.9937
        rom[  8] = 16'sd2047;   //  x =  8  -> 7.9973
        rom[  9] = 16'sd2304;   //  x =  9  -> 8.9989
        rom[ 10] = 16'sd2560;   //  x = 10  -> 9.9995
        // Linear tail: SiLU(x) -> x for x >> 0
        for (int i = 11; i <= 127; i++) rom[i] = 16'(i * 256);

        // --- Negative half: index 128..255  (x = -128..-1) ------------------
        // For x <= -10 the product x*sigmoid(x) is below 1 LSB in Q8.8.
        // Only the near-origin entries hold non-zero values.
        rom[248] = -16'sd1;     //  x = -8  -> -0.00268
        rom[249] = -16'sd2;     //  x = -7  -> -0.00638
        rom[250] = -16'sd4;     //  x = -6  -> -0.01485
        rom[251] = -16'sd9;     //  x = -5  -> -0.03346
        rom[252] = -16'sd18;    //  x = -4  -> -0.07196
        rom[253] = -16'sd36;    //  x = -3  -> -0.14228
        rom[254] = -16'sd61;    //  x = -2  -> -0.23840
        rom[255] = -16'sd69;    //  x = -1  -> -0.26894
    end

    // -------------------------------------------------------------------------
    // Three-stage pipeline (synchronous reset).
    //
    //   Stage 1 (addr_q / en_q)  : register the ROM address and the en strobe.
    //   Stage 2 (y_q    / en_qq) : do the ROM read using the registered
    //                              address; keep the en strobe marching.
    //   Stage 3 (y_out  / valid) : register the ROM output and drive
    //                              valid_out from the stage-2 en register.
    //
    //   Total latency from a single-cycle en pulse to valid_out rising is
    //   three clocks, with y_out aligned to valid_out.
    // -------------------------------------------------------------------------
    wire [7:0] rom_addr = x_in[DATA_WIDTH-1 -: 8];   // top 8 bits of x_in

    logic [7:0]                  addr_q;
    logic                        en_q;
    logic                        en_qq;
    logic signed [DATA_WIDTH-1:0] y_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            addr_q    <= 8'h00;
            en_q      <= 1'b0;
            en_qq     <= 1'b0;
            y_q       <= '0;
            y_out     <= '0;
            valid_out <= 1'b0;
        end else begin
            // Stage 1 : capture inputs
            addr_q    <= rom_addr;
            en_q      <= en;
            // Stage 2 : ROM read, propagate en
            y_q       <= rom[addr_q];
            en_qq     <= en_q;
            // Stage 3 : drive registered outputs
            y_out     <= y_q;
            valid_out <= en_qq;
        end
    end

endmodule

`default_nettype wire
