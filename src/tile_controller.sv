// =============================================================================
// Module   : tile_controller
// Purpose  : Top-level sequencer for the BitNet b1.58 accelerator.
//
//   Walks `total_tiles` addresses out of the weight BRAM into the systolic
//   array, then holds for a fixed pipeline-drain window before announcing
//   that the inference has completed.
//
// FSM
// ---
//   IDLE    : counters cleared, array_en low.  Waits for start_inference.
//   COMPUTE : drives bram_read_addr = 0,1,..,total_tiles-1 on successive
//             clocks with array_en high.  Transitions to DRAIN the clock
//             after the last address is presented.
//   DRAIN   : holds array_en low while 12 clocks pass for the data to fall
//             out of the downstream pipelines (systolic array = 5, RMSNorm +
//             SiLU = 7).  On the 12th clock it pulses inference_done and
//             returns to IDLE.
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module tile_controller #(
    parameter int MAX_TILES = 256
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start_inference,
    input  wire [7:0]  total_tiles,
    output logic [7:0] bram_read_addr,
    output logic       array_en,
    output logic       inference_done
);

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------
    // 5 (systolic) + 7 (RMSNorm + SiLU) = 12 drain cycles.
    localparam int DRAIN_CYCLES = 12;

    typedef enum logic [1:0] {
        IDLE    = 2'd0,
        COMPUTE = 2'd1,
        DRAIN   = 2'd2
    } state_t;

    state_t      state;
    logic [7:0]  addr_cnt;
    logic [3:0]  drain_cnt;     // 0..11 fits in 4 bits

    // bram_read_addr is driven directly from the address counter.
    assign bram_read_addr = addr_cnt;

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= IDLE;
            addr_cnt       <= 8'd0;
            drain_cnt      <= 4'd0;
            array_en       <= 1'b0;
            inference_done <= 1'b0;
        end else begin
            // Default: inference_done is a one-cycle pulse
            inference_done <= 1'b0;

            unique case (state)
                // -----------------------------------------------------------
                IDLE: begin
                    array_en  <= 1'b0;
                    addr_cnt  <= 8'd0;
                    drain_cnt <= 4'd0;
                    if (start_inference && (total_tiles != 8'd0)) begin
                        state    <= COMPUTE;
                        array_en <= 1'b1;
                        // addr_cnt already 0; bram_read_addr = 0 on next edge
                    end
                end

                // -----------------------------------------------------------
                COMPUTE: begin
                    // Present addresses 0..total_tiles-1 on successive clocks.
                    if (addr_cnt == total_tiles - 8'd1) begin
                        state     <= DRAIN;
                        array_en  <= 1'b0;
                        drain_cnt <= 4'd0;
                    end else begin
                        addr_cnt <= addr_cnt + 8'd1;
                    end
                end

                // -----------------------------------------------------------
                DRAIN: begin
                    if (drain_cnt == DRAIN_CYCLES[3:0] - 4'd1) begin
                        // 12th drain edge reached -- signal done and idle
                        state          <= IDLE;
                        inference_done <= 1'b1;
                    end else begin
                        drain_cnt <= drain_cnt + 4'd1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
