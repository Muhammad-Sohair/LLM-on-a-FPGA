// =============================================================================
// Module   : ternary_vector_dp
// Purpose  : Parameterized Ternary Vector Dot-Product engine.
//
//   Computes:  dot_product = SUM_i( ternary_sign(w_i) * a_i )
//
//   The multiplier-less principle from ternary_mac is extended here to
//   ACT_WIDTH-bit activations: instead of accumulating ±1 per cycle, each
//   Stage-1 element performs a single-cycle conditional add/subtract of the
//   full-width activation value, then a registered binary adder tree reduces
//   all VECTOR_SIZE partial products to a single result.
//
// Weight encoding (2-bit, identical to ternary_mac.sv):
//   2'b01 = +1    2'b11 = -1    2'b00 / 2'b10 = 0
//
// Pipeline architecture (fully registered, active-low async reset):
//
//   ┌──────────────────────────────────────────────────────────────────┐
//   │  Stage 1  │  Stage 2  │  Stage 3  │  Stage 4  │  Stage 5       │
//   │  Ternary  │  Adder    │  Adder    │  Adder    │  Adder         │
//   │  Multiply │  Level 1  │  Level 2  │  Level 3  │  Level 4       │
//   │  (×16)    │  (16→8)   │  (8→4)    │  (4→2)    │  (2→1) = OUT   │
//   └──────────────────────────────────────────────────────────────────┘
//         ↑ en gated                     adder tree free-running
//
//   Total pipeline depth : PIPE_DEPTH = 1 + log2(VECTOR_SIZE)  = 5 cycles
//
// Parameters:
//   VECTOR_SIZE  – number of multiply-accumulate lanes  (default 16, must be
//                  a power-of-2 for the adder tree)
//   ACT_WIDTH    – activation operand width in bits     (default  8, signed)
//   ACC_WIDTH    – accumulator / output width in bits   (default 16, signed)
//
// Ports:
//   clk              – clock, rising edge
//   rst_n            – asynchronous active-low reset
//   en               – enable; Stage 1 captures new products on this cycle
//   act_vector_in    – flattened activations: {a[N-1], …, a[1], a[0]}
//                      a[i] = act_vector_in[ACT_WIDTH*i +: ACT_WIDTH]
//   weight_vector_in – flattened weights:     {w[N-1], …, w[1], w[0]}
//                      w[i] = weight_vector_in[2*i +: 2]
//   dot_product_out  – ACC_WIDTH-bit signed result, valid when valid_out=1
//   valid_out        – pulses high PIPE_DEPTH cycles after en was asserted
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module ternary_vector_dp #(
    parameter int VECTOR_SIZE = 16,
    parameter int ACT_WIDTH   = 8,
    parameter int ACC_WIDTH   = 16
) (
    input  wire                                  clk,
    input  wire                                  rst_n,
    input  wire                                  en,
    input  wire [(VECTOR_SIZE * ACT_WIDTH)-1:0] act_vector_in,
    input  wire [(VECTOR_SIZE * 2)-1:0]         weight_vector_in,
    output logic signed [ACC_WIDTH-1:0]         dot_product_out,
    output logic                                 valid_out
);

    // -------------------------------------------------------------------------
    // Derived constants
    // -------------------------------------------------------------------------
    localparam int TREE_LEVELS = $clog2(VECTOR_SIZE); // 4 for default N=16
    localparam int PIPE_DEPTH  = 1 + TREE_LEVELS;     // 5 total stages
    localparam int EXT_BITS    = ACC_WIDTH - ACT_WIDTH; // sign-extension width

    // -------------------------------------------------------------------------
    // Adder-tree register bank  [level 0..TREE_LEVELS][node 0..VECTOR_SIZE-1]
    //   Level 0 : VECTOR_SIZE products      (Stage 1 output)
    //   Level k : VECTOR_SIZE >> k sums     (each tree stage)
    //   Unused column entries are never driven → synthesised away.
    // -------------------------------------------------------------------------
    logic signed [ACC_WIDTH-1:0] tree_regs [0:TREE_LEVELS][0:VECTOR_SIZE-1];

    // =========================================================================
    // Stage 1 — Parallel multiplier-less ternary multiply
    //   One lane per vector element, registered on posedge clk when en=1.
    //   Operation (no * operator used):
    //     w_i == 2'b01 (+1) : product =  sign_ext(a_i)
    //     w_i == 2'b11 (-1) : product = -sign_ext(a_i)
    //     otherwise  ( 0)   : product =  0
    // =========================================================================
    genvar i;
    generate
        for (i = 0; i < VECTOR_SIZE; i++) begin : gen_stage1_lane

            // Unpack element i from the flattened input vectors
            wire [1:0]                  w_i;
            wire signed [ACT_WIDTH-1:0] a_i;
            wire signed [ACC_WIDTH-1:0] a_ext; // sign-extended activation

            assign w_i  = weight_vector_in[2*i +: 2];
            assign a_i  = act_vector_in[ACT_WIDTH*i +: ACT_WIDTH];

            // Explicit manual sign extension — avoids any tool-specific cast
            // ambiguity between signed/unsigned N'() semantics.
            assign a_ext = signed'({{EXT_BITS{a_i[ACT_WIDTH-1]}}, a_i});

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    tree_regs[0][i] <= '0;
                end else if (en) begin
                    case (w_i)
                        2'b01:   tree_regs[0][i] <=  a_ext;  // add activation
                        2'b11:   tree_regs[0][i] <= -a_ext;  // subtract activation
                        default: tree_regs[0][i] <= '0;      // zero weight
                    endcase
                end
                // en == 0: hold last captured value
            end

        end
    endgenerate

    // =========================================================================
    // Stage 2 … TREE_LEVELS+1 — Pipelined binary adder tree
    //   Each level halves the node count with one registered adder per pair.
    //   A single addition per register stage maximises Fmax (no carry chains
    //   span across levels).
    // =========================================================================
    genvar lvl, nd;
    generate
        for (lvl = 1; lvl <= TREE_LEVELS; lvl++) begin : gen_tree_level
            for (nd = 0; nd < (VECTOR_SIZE >> lvl); nd++) begin : gen_tree_node
                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n)
                        tree_regs[lvl][nd] <= '0;
                    else
                        tree_regs[lvl][nd] <= tree_regs[lvl-1][2*nd]
                                            + tree_regs[lvl-1][2*nd+1];
                end
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Output — root node of the fully reduced adder tree
    // -------------------------------------------------------------------------
    assign dot_product_out = tree_regs[TREE_LEVELS][0];

    // =========================================================================
    // Valid shift register
    //   en propagates through a PIPE_DEPTH-bit shift register; valid_out
    //   rises exactly PIPE_DEPTH cycles after en was sampled high.
    // =========================================================================
    logic [PIPE_DEPTH-1:0] valid_sr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            valid_sr <= '0;
        else
            valid_sr <= {valid_sr[PIPE_DEPTH-2:0], en};
    end

    assign valid_out = valid_sr[PIPE_DEPTH-1];

endmodule

`default_nettype wire
