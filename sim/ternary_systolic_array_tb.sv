// =============================================================================
// Testbench : ternary_systolic_array_tb
// DUT       : ternary_systolic_array (ROWS=4, VECTOR_SIZE=16, ACT_WIDTH=8,
//                                     ACC_WIDTH=16)
//
// Clock     : 100 MHz (10 ns period)
// Pipeline  : 5 cycles  (1 Stage-1 multiply + 4 adder-tree levels)
//
// ─────────────────────────────────────────────────────────────────────────────
// Packed weight encoding (13 bytes → 65 weights, weight 64 unused)
// ─────────────────────────────────────────────────────────────────────────────
// Base-3 encoding used by weight_decoder:
//   +1 → digit 2    0 → digit 1    -1 → digit 0
//   V = d0·1 + d1·3 + d2·9 + d3·27 + d4·81
//
// Decoder d receives packed_weights_in[8d+7 : 8d] and produces:
//   w0=weight_5d, w1=weight_5d+1, ..., w4=weight_5d+4
//
// Weight assignment:
//   Row 0 (weights  0-15): all +1   (digit 2 everywhere)
//   Row 1 (weights 16-31): all -1   (digit 0 everywhere)
//   Row 2 (weights 32-47): all  0   (digit 1 everywhere)
//   Row 3 (weights 48-63): all +1   (digit 2 everywhere)
//   Weight 64 (extra):      0       (digit 1)
//
// Byte derivations (byte index = decoder index):
//
//   Byte  0 (dec  0, w  0- 4): all +1 → [d4..d0]=[2,2,2,2,2]
//                               V = 2+6+18+54+162 = 242  (0xF2)
//   Byte  1 (dec  1, w  5- 9): all +1 → V = 242  (0xF2)
//   Byte  2 (dec  2, w 10-14): all +1 → V = 242  (0xF2)
//   Byte  3 (dec  3, w 15-19): w15=+1(d0=2), w16-19=-1(d1-d4=0)
//                               V = 2+0+0+0+0 = 2  (0x02)
//   Byte  4 (dec  4, w 20-24): all -1 → [0,0,0,0,0] → V = 0  (0x00)
//   Byte  5 (dec  5, w 25-29): all -1 → V = 0  (0x00)
//   Byte  6 (dec  6, w 30-34): w30-31=-1(d0-d1=0), w32-34=0(d2-d4=1)
//                               V = 0+0+9+27+81 = 117  (0x75)
//   Byte  7 (dec  7, w 35-39): all  0 → [1,1,1,1,1] → V = 1+3+9+27+81 = 121 (0x79)
//   Byte  8 (dec  8, w 40-44): all  0 → V = 121  (0x79)
//   Byte  9 (dec  9, w 45-49): w45-47=0(d0-d2=1), w48-49=+1(d3-d4=2)
//                               V = 1+3+9+54+162 = 229  (0xE5)
//   Byte 10 (dec 10, w 50-54): all +1 → V = 242  (0xF2)
//   Byte 11 (dec 11, w 55-59): all +1 → V = 242  (0xF2)
//   Byte 12 (dec 12, w 60-64): w60-63=+1(d0-d3=2), w64=0(d4=1)
//                               V = 2+6+18+54+81 = 161  (0xA1)
//
// packed_weights_in = {byte12, byte11, ..., byte0}
//                   = {0xA1, 0xF2, 0xF2, 0xE5, 0x79, 0x79, 0x75,
//                      0x00, 0x00, 0x02, 0xF2, 0xF2, 0xF2}
//
// ─────────────────────────────────────────────────────────────────────────────
// Expected results  (all activations = +2)
// ─────────────────────────────────────────────────────────────────────────────
//   Row 0: 16 × (+1 × +2) = +32
//   Row 1: 16 × (-1 × +2) = -32
//   Row 2: 16 × ( 0 × +2) =   0
//   Row 3: 16 × (+1 × +2) = +32
//
//   matrix_out[15: 0] = +32
//   matrix_out[31:16] = -32
//   matrix_out[47:32] =   0
//   matrix_out[63:48] = +32
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module ternary_systolic_array_tb;

    // -------------------------------------------------------------------------
    // DUT parameters
    // -------------------------------------------------------------------------
    localparam int ROWS        = 4;
    localparam int VECTOR_SIZE = 16;
    localparam int ACT_WIDTH   = 8;
    localparam int ACC_WIDTH   = 16;

    // Pipeline depth: 1 Stage-1 register + log2(16)=4 adder-tree levels
    localparam int PIPE_DEPTH  = 1 + $clog2(VECTOR_SIZE);  // 5

    // -------------------------------------------------------------------------
    // Packed weight constant (see byte derivations above)
    // packed_weights_in[8*d +: 8] = byte d = input to decoder d
    // -------------------------------------------------------------------------
    localparam logic [103:0] TEST_WEIGHTS = {
        8'hA1,   // Byte 12: dec 12  w60-63=+1  w64=0    → V=161
        8'hF2,   // Byte 11: dec 11  w55-59=+1           → V=242
        8'hF2,   // Byte 10: dec 10  w50-54=+1           → V=242
        8'hE5,   // Byte  9: dec  9  w45-47=0   w48-49=+1→ V=229
        8'h79,   // Byte  8: dec  8  w40-44=0            → V=121
        8'h79,   // Byte  7: dec  7  w35-39=0            → V=121
        8'h75,   // Byte  6: dec  6  w30-31=-1  w32-34=0 → V=117
        8'h00,   // Byte  5: dec  5  w25-29=-1           → V=0
        8'h00,   // Byte  4: dec  4  w20-24=-1           → V=0
        8'h02,   // Byte  3: dec  3  w15=+1    w16-19=-1 → V=2
        8'hF2,   // Byte  2: dec  2  w10-14=+1           → V=242
        8'hF2,   // Byte  1: dec  1  w 5- 9=+1           → V=242
        8'hF2    // Byte  0: dec  0  w 0- 4=+1           → V=242
    };

    // All 16 activations = +2
    localparam logic [(VECTOR_SIZE * ACT_WIDTH)-1:0] TEST_ACT = {16{8'sd2}};

    // Expected signed row results
    localparam logic signed [ACC_WIDTH-1:0] EXP_ROW0 =  16'sd32;
    localparam logic signed [ACC_WIDTH-1:0] EXP_ROW1 = -16'sd32;
    localparam logic signed [ACC_WIDTH-1:0] EXP_ROW2 =  16'sd0;
    localparam logic signed [ACC_WIDTH-1:0] EXP_ROW3 =  16'sd32;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                                  clk              = 1'b0;
    logic                                  rst_n            = 1'b0;
    logic                                  en               = 1'b0;
    logic [(VECTOR_SIZE * ACT_WIDTH)-1:0]  act_vector_in    = '0;
    logic [103:0]                          packed_weights_in = '0;
    wire  [(ROWS * ACC_WIDTH)-1:0]         matrix_out;
    wire                                   valid_out;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    ternary_systolic_array #(
        .ROWS        (ROWS),
        .VECTOR_SIZE (VECTOR_SIZE),
        .ACT_WIDTH   (ACT_WIDTH),
        .ACC_WIDTH   (ACC_WIDTH)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .en               (en),
        .act_vector_in    (act_vector_in),
        .packed_weights_in(packed_weights_in),
        .matrix_out       (matrix_out),
        .valid_out        (valid_out)
    );

    // -------------------------------------------------------------------------
    // 100 MHz clock
    // -------------------------------------------------------------------------
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Scoreboard helpers
    // -------------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    task automatic check_row(
        input int                        row_idx,
        input logic signed [ACC_WIDTH-1:0] expected
    );
        logic signed [ACC_WIDTH-1:0] got;
        got = $signed(matrix_out[row_idx * ACC_WIDTH +: ACC_WIDTH]);
        if (got === expected) begin
            $display("  PASS | Row %0d : got %0d (expected %0d)",
                     row_idx, got, expected);
            pass_count++;
        end else begin
            $display("  FAIL | Row %0d : got %0d (expected %0d)",
                     row_idx, got, expected);
            fail_count++;
        end
    endtask

    // =========================================================================
    // Stimulus
    // =========================================================================
    initial begin
        $display("================================================================");
        $display("  Ternary Systolic Array Testbench");
        $display("  ROWS=%0d  VECTOR_SIZE=%0d  ACT_WIDTH=%0d  ACC_WIDTH=%0d",
                 ROWS, VECTOR_SIZE, ACT_WIDTH, ACC_WIDTH);
        $display("  Pipeline depth: %0d cycles", PIPE_DEPTH);
        $display("================================================================");

        // -----------------------------------------------------------------
        // Reset sequence (3 cycles active-low)
        // -----------------------------------------------------------------
        rst_n = 1'b0;
        en    = 1'b0;
        repeat (3) @(posedge clk);
        #1;
        rst_n = 1'b1;
        @(posedge clk); #1;

        // -----------------------------------------------------------------
        // Test: matrix-vector product
        //
        //   Apply stable inputs before asserting en.
        //   Assert en for exactly ONE rising edge (Stage 1 latches products).
        //   Adder tree free-runs; after PIPE_DEPTH edges valid_out = 1.
        // -----------------------------------------------------------------
        $display("-- Applying test vector: all act=+2, weights per derivation --");
        act_vector_in    = TEST_ACT;
        packed_weights_in = TEST_WEIGHTS;

        en = 1'b1;
        @(posedge clk);          // Edge 1/5: Stage 1 captures products
        en = 1'b0;

        repeat (PIPE_DEPTH - 1) @(posedge clk);   // Edges 2–5: tree drains
        #1;  // combinational settle

        // -----------------------------------------------------------------
        // Verify valid_out then all four rows
        // -----------------------------------------------------------------
        $display("-- Checking outputs at T=%0t ns --", $time);

        if (!valid_out) begin
            $display("  FAIL | valid_out not asserted after %0d cycles", PIPE_DEPTH);
            fail_count++;
        end else begin
            $display("  PASS | valid_out asserted correctly");
            pass_count++;
        end

        check_row(0, EXP_ROW0);   // Row 0: +32  (16 × +1 × +2)
        check_row(1, EXP_ROW1);   // Row 1: -32  (16 × -1 × +2)
        check_row(2, EXP_ROW2);   // Row 2:   0  (16 ×  0 × +2)
        check_row(3, EXP_ROW3);   // Row 3: +32  (16 × +1 × +2)

        // -----------------------------------------------------------------
        // Summary
        // -----------------------------------------------------------------
        $display("================================================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("  Overall: %s", (fail_count == 0) ? "PASS" : "FAIL");
        $display("================================================================");

        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout watchdog
    // -------------------------------------------------------------------------
    initial begin
        #2000;
        $display("FAIL | Watchdog timeout at %0t ns", $time);
        $finish;
    end

endmodule

`default_nettype wire
