`timescale 1ns/1ps
`default_nettype none

module weight_buffer #(
    parameter int DATA_WIDTH = 104, // 13 packed bytes per row
    parameter int ADDR_WIDTH = 9    // 512 entries (enough for a few tiles)
) (
    // Port A: Write-only (From AXI DMA)
    input  wire                   clk_a,
    input  wire                   we_a,
    input  wire [ADDR_WIDTH-1:0]  addr_a,
    input  wire [DATA_WIDTH-1:0]  din_a,

    // Port B: Read-only (To Systolic Array)
    input  wire                   clk_b,
    input  wire                   en_b,
    input  wire [ADDR_WIDTH-1:0]  addr_b,
    output logic [DATA_WIDTH-1:0] dout_b
);

    // Force Vivado to map this array to physical Block RAM
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];

    // Port A (Write)
    always_ff @(posedge clk_a) begin
        if (we_a) begin
            ram[addr_a] <= din_a;
        end
    end

    // Port B (Read) - Native 1-cycle BRAM latency
    always_ff @(posedge clk_b) begin
        if (en_b) begin
            dout_b <= ram[addr_b];
        end
    end

endmodule
`default_nettype wire