// =============================================================================
// Module    : ternary_accelerator_top
// Purpose   : Top-level integration for the BitNet b1.58 accelerator.
//
//   DMA  --AXI-Stream-->  weight_buffer (BRAM)  --+
//                                                 +--> ternary_systolic_array
//                         s_axis_act_data  -------+             |
//                                                               v
//                                          rmsnorm --> silu_activation --> DMA
//
//   tile_controller walks BRAM addresses 0..total_tiles-1 into the array.
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module ternary_accelerator_top #(
    parameter int VECTOR_SIZE = 16,
    parameter int ACT_WIDTH   = 8,
    parameter int ROWS        = 4,
    parameter int ACC_WIDTH   = 16,
    parameter int RMSNORM_N   = 4,  
    parameter int RMSNORM_W   = 16  
) (
    input  wire                               clk,
    input  wire                               rst_n,
    input  wire                               start_inference,
    input  wire [7:0]                         total_tiles,

    // AXI-Stream Slave (ingress: weights + activations from DMA)
    input  wire                               s_axis_tvalid,
    input  wire [103:0]                       s_axis_tdata,        // packed weights
    input  wire [(VECTOR_SIZE*ACT_WIDTH)-1:0] s_axis_act_data,   // 16x8b activations
    output wire                               s_axis_tready,

    // AXI-Stream Master (egress: post-SiLU activations to DMA)
    output wire                               m_axis_tvalid,
    output wire [15:0]                        m_axis_tdata,
    output wire                               m_axis_tlast,      // ADDED: Required for DMA S2MM

    // Status
    output wire                               inference_done
);

    // -------------------------------------------------------------------------
    // Local constants
    // -------------------------------------------------------------------------
    localparam int BRAM_ADDR_W   = 9;
    localparam logic [15:0] GAMMA_Q115 = 16'd32768;     // gamma = 1.0 (Q1.15)

    // -------------------------------------------------------------------------
    // Ingress write-address counter for the weight BRAM (Port A)
    //    We accept one packed-weight beat per cycle when the upstream DMA is
    //    valid.  s_axis_tready mirrors the write enable so the handshake is
    //    never stalled by this block.
    // -------------------------------------------------------------------------
    logic                       we_a;
    logic [BRAM_ADDR_W-1:0]   waddr_a;

    assign we_a           = s_axis_tvalid;
    assign s_axis_tready = we_a;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            waddr_a <= '0;
        else if (we_a)
            waddr_a <= waddr_a + 1'b1;
    end

    // -------------------------------------------------------------------------
    // Tile controller
    // -------------------------------------------------------------------------
    wire [7:0] bram_read_addr;
    wire       array_en;

    tile_controller #(
        .MAX_TILES (256)
    ) u_tile_ctrl (
        .clk             (clk),
        .rst_n           (rst_n),
        .start_inference (start_inference),
        .total_tiles     (total_tiles),
        .bram_read_addr  (bram_read_addr),
        .array_en        (array_en),
        .inference_done  (inference_done)
    );

    // -------------------------------------------------------------------------
    // Weight BRAM
    // -------------------------------------------------------------------------
    wire [103:0] packed_weights;

    weight_buffer #(
        .DATA_WIDTH (104),
        .ADDR_WIDTH (BRAM_ADDR_W)
    ) u_wbuf (
        .clk_a  (clk),
        .we_a   (we_a),
        .addr_a (waddr_a),
        .din_a  (s_axis_tdata),

        .clk_b  (clk),
        .en_b   (array_en),
        .addr_b ({1'b0, bram_read_addr}),
        .dout_b (packed_weights)
    );

    // -------------------------------------------------------------------------
    // Systolic array (4x16 ternary)
    // -------------------------------------------------------------------------
    wire [(ROWS*ACC_WIDTH)-1:0] matrix_out;
    wire                        array_valid;

    ternary_systolic_array #(
        .ROWS        (ROWS),
        .VECTOR_SIZE (VECTOR_SIZE),
        .ACT_WIDTH   (ACT_WIDTH),
        .ACC_WIDTH   (ACC_WIDTH)
    ) u_array (
        .clk                 (clk),
        .rst_n               (rst_n),
        .en                  (array_en),
        .act_vector_in       (s_axis_act_data),
        .packed_weights_in (packed_weights),
        .matrix_out        (matrix_out),
        .valid_out           (array_valid)
    );

    // -------------------------------------------------------------------------
    // RMSNorm : takes the full ROWS-lane matrix_out as its vector input.
    //            Row 0 of its normalized output feeds the SiLU.
    // -------------------------------------------------------------------------
    wire [(RMSNORM_N*RMSNORM_W)-1:0] rms_data_out;
    wire                               rms_valid_out;

    rmsnorm #(
        .N           (RMSNORM_N),
        .ACT_WIDTH   (RMSNORM_W),
        .OUT_WIDTH   (RMSNORM_W),
        .GAMMA_WIDTH (16),
        .LOG2_N      (2)
    ) u_rms (
        .clk       (clk),
        .rst_n     (rst_n),
        .en        (array_valid),
        .valid_in  (array_valid),
        .data_in   (matrix_out),
        .gamma_in  (GAMMA_Q115),
        .data_out  (rms_data_out),
        .valid_out (rms_valid_out)
    );

    wire signed [RMSNORM_W-1:0] rms_row0 = rms_data_out[0 +: RMSNORM_W];

    // -------------------------------------------------------------------------
    // SiLU activation (ROM-based, Q8.8)
    // -------------------------------------------------------------------------
    wire signed [15:0] silu_y;
    wire                silu_valid;

    silu_activation #(
        .DATA_WIDTH (16)
    ) u_silu (
        .clk       (clk),
        .rst_n     (rst_n),
        .en        (rms_valid_out),
        .x_in      (rms_row0),
        .y_out     (silu_y),
        .valid_out (silu_valid)
    );

    // -------------------------------------------------------------------------
    // AXI-Stream egress
    // -------------------------------------------------------------------------
    assign m_axis_tdata  = silu_y;
    assign m_axis_tvalid = silu_valid;
    assign m_axis_tlast  = silu_valid; // ADDED: Required for DMA transfer end

endmodule

`default_nettype wire