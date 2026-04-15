`timescale 1ns/1ps
`default_nettype none

module weight_buffer_tb;

    localparam int DATA_WIDTH = 104;
    localparam int ADDR_WIDTH = 9;

    logic clk = 0;
    
    // Port A signals
    logic                   we_a = 0;
    logic [ADDR_WIDTH-1:0]  addr_a = 0;
    logic [DATA_WIDTH-1:0]  din_a = 0;

    // Port B signals
    logic                   en_b = 0;
    logic [ADDR_WIDTH-1:0]  addr_b = 0;
    logic [DATA_WIDTH-1:0]  dout_b;

    weight_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk_a(clk), .we_a(we_a), .addr_a(addr_a), .din_a(din_a),
        .clk_b(clk), .en_b(en_b), .addr_b(addr_b), .dout_b(dout_b)
    );

    // 100MHz Clock
    always #5 clk = ~clk;

    initial begin
        $display("========================================================");
        $display("  Weight Buffer (True Dual-Port BRAM) Testbench ");
        $display("========================================================");

        // 1. Write Phase (Simulating DMA pushing data to Port A)
        @(posedge clk);
        we_a = 1'b1; 
        addr_a = 9'd5; 
        din_a = 104'h00000000_00000000_AABBCCDDEEFF;
        @(posedge clk);
        
        addr_a = 9'd6; 
        din_a = 104'h00000000_00000000_112233445566;
        @(posedge clk);
        we_a = 1'b0;

        // 2. Read Phase (Simulating Systolic Array pulling from Port B)
        en_b = 1'b1; 
        addr_b = 9'd5;
        @(posedge clk); // Address clocked in
        
        addr_b = 9'd6;
        @(posedge clk); // Data 5 is out, Address 6 clocked in
        
        if (dout_b[47:0] == 48'hAABBCCDDEEFF) 
            $display("PASS | Cycle 1: Successfully read Address 5");
        else 
            $display("FAIL | Cycle 1: Data mismatch");

        @(posedge clk); // Data 6 is out
        en_b = 1'b0;
        
        if (dout_b[47:0] == 48'h112233445566) 
            $display("PASS | Cycle 2: Successfully read Address 6");
        else 
            $display("FAIL | Cycle 2: Data mismatch");

        $display("========================================================");
        $finish;
    end

endmodule
`default_nettype wire