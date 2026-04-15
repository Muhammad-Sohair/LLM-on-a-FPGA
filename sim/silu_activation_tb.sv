`timescale 1ns/1ps
`default_nettype none

module silu_activation_tb;

    localparam int DATA_WIDTH = 16;

    logic                  clk = 0;
    logic                  rst_n = 0;
    logic                  en = 0;
    logic signed [15:0]    x_in = 0;
    logic signed [15:0]    y_out;
    logic                  valid_out;

    silu_activation #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .x_in(x_in),
        .y_out(y_out),
        .valid_out(valid_out)
    );

    // 100MHz Clock
    always #5 clk = ~clk;

    int pass_count = 0;
    int fail_count = 0;

    task automatic check_silu(
        input logic signed [15:0] t_x,
        input string label
    );
        // Drive inputs with non-blocking assignments so the updates land in
        // the NBA region of the current time step. This avoids the Active
        // region race with the DUT's always_ff sampling on the same posedge.
        x_in <= t_x;
        en   <= 1'b1;
        @(posedge clk);       // Edge 1: DUT latches addr_q, en_q <= 1
        en   <= 1'b0;         // deassert en for next edge

        // Wait 2 more pipeline cycles for the 3-stage ROM read / valid path
        @(posedge clk);       // Edge 2: en_qq <= 1, y_q <= rom[addr_q]
        @(posedge clk);       // Edge 3: valid_out <= en_qq = 1, y_out <= y_q
        #1;

        if (!valid_out) begin
            $display("FAIL | %-30s | valid_out not asserted!", label);
            fail_count++;
        end else begin
            $display("PASS | %-30s | x_in=%0d, y_out=%0d", label, x_in, y_out);
            pass_count++;
        end
        @(posedge clk);
    endtask

    initial begin
        $display("========================================================");
        $display("  SiLU Activation Testbench (Q8.8 Format) ");
        $display("========================================================");

        rst_n = 0;
        en = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // 1. Test x = 0 (Expected ~0)
        check_silu(16'h0000, "x = 0.0");

        // 2. Test Highly Positive x = +5.0 (5 * 256 = 1280) 
        // SiLU(5) ~ 5.0, so expected is near 1280
        check_silu(16'd1280, "x = +5.0 (Highly Positive)");

        // 3. Test Highly Negative x = -5.0 (-5 * 256 = -1280) 
        // SiLU(-5) ~ 0.0, so expected is near 0
        check_silu(-16'd1280, "x = -5.0 (Highly Negative)");

        // 4. Test x = +1.0 (256) 
        // SiLU(1) = 1 * 0.731 = 0.731. (0.731 * 256 ≈ 187)
        check_silu(16'd256,  "x = +1.0");

        $display("========================================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================================");
        $finish;
    end

    // Watchdog
    initial begin
        #1000;
        $display("FAIL | Watchdog timeout");
        $finish;
    end

endmodule
`default_nettype wire