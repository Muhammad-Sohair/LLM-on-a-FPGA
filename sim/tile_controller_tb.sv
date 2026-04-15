// =============================================================================
// Testbench : tile_controller_tb
// DUT       : tile_controller (MAX_TILES = 256)
//
// Scenario
//   * total_tiles = 10
//   * Pulse start_inference for one cycle
//   * Verify bram_read_addr counts 0..9 with array_en high
//   * Verify array_en drops after the 10th address
//   * Verify inference_done asserts exactly 12 cycles after array_en drop
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module tile_controller_tb;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic        clk;
    logic        rst_n;
    logic        start_inference;
    logic [7:0]  total_tiles;
    logic [7:0]  bram_read_addr;
    logic        array_en;
    logic        inference_done;

    tile_controller #(
        .MAX_TILES (256)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .start_inference (start_inference),
        .total_tiles     (total_tiles),
        .bram_read_addr  (bram_read_addr),
        .array_en        (array_en),
        .inference_done  (inference_done)
    );

    // 100 MHz clock
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Scoreboard
    // -------------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    task automatic check(input bit cond, input string msg);
        if (cond) begin
            $display("PASS | %s", msg);
            pass_count++;
        end else begin
            $display("FAIL | %s", msg);
            fail_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        $display("========================================================");
        $display("  tile_controller Testbench");
        $display("========================================================");

        clk             = 1'b0;
        rst_n           = 1'b0;
        start_inference = 1'b0;
        total_tiles     = 8'd10;

        // Reset
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;
        check(array_en === 1'b0 && inference_done === 1'b0 &&
              bram_read_addr === 8'd0,
              "Post-reset: array_en=0, done=0, addr=0");

        // Pulse start_inference (NBA so the DUT samples cleanly on the edge)
        start_inference <= 1'b1;
        @(posedge clk);         // this edge captures start_inference=1
        start_inference <= 1'b0;

        // -------------------------------------------------------------------
        // COMPUTE phase : 10 cycles, bram_read_addr = 0..9, array_en = 1
        // -------------------------------------------------------------------
        for (int i = 0; i < 10; i++) begin
            #1;                 // settle after the edge that entered/advanced COMPUTE
            check(bram_read_addr === i[7:0] && array_en === 1'b1 &&
                  inference_done === 1'b0,
                  $sformatf("COMPUTE cycle %0d : bram_read_addr=%0d, array_en=1",
                            i, bram_read_addr));
            @(posedge clk);
        end

        // -------------------------------------------------------------------
        // DRAIN phase : array_en must drop and inference_done must stay low
        // for exactly 11 more edges, then pulse high on the 12th.
        // -------------------------------------------------------------------
        #1;
        check(array_en === 1'b0, "DRAIN entered: array_en dropped to 0");

        for (int k = 1; k <= 11; k++) begin
            check(inference_done === 1'b0,
                  $sformatf("DRAIN edge %0d : inference_done still 0", k));
            @(posedge clk);
            #1;
        end

        // 12th edge after the drop -- inference_done must be high
        @(posedge clk);
        #1;
        check(inference_done === 1'b1,
              "inference_done asserted exactly 12 cycles after array_en drop");

        // It should be a single-cycle pulse
        @(posedge clk);
        #1;
        check(inference_done === 1'b0, "inference_done is a 1-cycle pulse");
        check(array_en === 1'b0, "Back in IDLE: array_en low");

        // -------------------------------------------------------------------
        // Summary
        // -------------------------------------------------------------------
        $display("========================================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("  Overall: %s", (fail_count == 0) ? "PASS" : "FAIL");
        $display("========================================================");

        $finish;
    end

    // -------------------------------------------------------------------------
    // Watchdog
    // -------------------------------------------------------------------------
    initial begin
        #5000;
        $display("FAIL | Watchdog timeout");
        $finish;
    end

endmodule

`default_nettype wire
