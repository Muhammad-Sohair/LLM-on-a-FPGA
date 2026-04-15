// =============================================================================
// Testbench : rmsnorm_tb
// DUT       : rmsnorm (N=4, ACT_WIDTH=16, OUT_WIDTH=16, GAMMA_WIDTH=16)
//
// Strategy:
//   - Drive a sequence of 4-lane 16-bit signed vectors.
//   - Compute the floating-point golden reference (y_i = gamma * x_i / rms(x)).
//   - Wait 3 pipeline cycles, compare DUT output per-lane to golden within a
//     tolerance budget of +/- 48 LSBs (accommodating LUT + sqrt(1/2) error +
//     Q1.15 rounding + truncation in the final shift).
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module rmsnorm_tb;

    // -------------------------------------------------------------------------
    // Parameters (must match DUT defaults)
    // -------------------------------------------------------------------------
    localparam int N           = 4;
    localparam int ACT_WIDTH   = 16;
    localparam int OUT_WIDTH   = 16;
    localparam int GAMMA_WIDTH = 16;
    localparam int LOG2_N      = 2;
    localparam int TOLERANCE   = 48;     // LSBs
    localparam int PIPE_LAT    = 5;      // stages (square, sum, <<SCALE_UP,
                                         // LUT, multiply, >>SCALE_UP+gamma)

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                        clk = 1'b0;
    logic                        rst_n = 1'b0;
    logic                        en = 1'b1;
    logic                        valid_in = 1'b0;
    logic [(N*ACT_WIDTH)-1:0]    data_in = '0;
    logic [GAMMA_WIDTH-1:0]      gamma_in = 16'd32768;   // gamma = 1.0 in Q1.15
    logic [(N*OUT_WIDTH)-1:0]    data_out;
    logic                        valid_out;

    // 100 MHz clock
    always #5 clk = ~clk;

    rmsnorm #(
        .N           (N),
        .ACT_WIDTH   (ACT_WIDTH),
        .OUT_WIDTH   (OUT_WIDTH),
        .GAMMA_WIDTH (GAMMA_WIDTH),
        .LOG2_N      (LOG2_N)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .en        (en),
        .valid_in  (valid_in),
        .data_in   (data_in),
        .gamma_in  (gamma_in),
        .data_out  (data_out),
        .valid_out (valid_out)
    );

    // -------------------------------------------------------------------------
    // Counters
    // -------------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    // -------------------------------------------------------------------------
    // Golden reference (real domain)
    // -------------------------------------------------------------------------
    function automatic void golden(
        input  logic signed [ACT_WIDTH-1:0] x [N],
        input  real                         gamma_real,
        output logic signed [OUT_WIDTH-1:0] y [N]
    );
        real sum_sq;
        real mean_sq;
        real inv_rms;
        real scaled;
        int  s;
        sum_sq = 0.0;
        for (int i = 0; i < N; i++) sum_sq += real'(x[i]) * real'(x[i]);
        mean_sq = sum_sq / real'(N);
        if (mean_sq < 1.0) mean_sq = 1.0;   // match eps-floor behaviour
        inv_rms = 1.0 / $sqrt(mean_sq);
        for (int i = 0; i < N; i++) begin
            scaled = real'(x[i]) * inv_rms * gamma_real;
            s = int'(scaled);
            if (s >  32767) s =  32767;
            if (s < -32768) s = -32768;
            y[i] = s[OUT_WIDTH-1:0];
        end
    endfunction

    // -------------------------------------------------------------------------
    // Apply one vector and check after PIPE_LAT cycles
    // -------------------------------------------------------------------------
    task automatic apply_and_check(
        input logic signed [ACT_WIDTH-1:0] x [N],
        input real                         gamma_real,
        input string                       test_name
    );
        logic signed [OUT_WIDTH-1:0] exp_y [N];
        logic signed [OUT_WIDTH-1:0] got_y;
        int                          diff;
        logic                        lane_fail;

        golden(x, gamma_real, exp_y);
        gamma_in <= GAMMA_WIDTH'(int'(gamma_real * 32768.0));
        for (int i = 0; i < N; i++)
            data_in[i*ACT_WIDTH +: ACT_WIDTH] <= x[i];
        valid_in <= 1'b1;
        @(posedge clk);
        valid_in <= 1'b0;

        // Wait remaining PIPE_LAT-1 edges for output
        repeat (PIPE_LAT-1) @(posedge clk);
        #1;

        lane_fail = 1'b0;
        for (int i = 0; i < N; i++) begin
            got_y = data_out[i*OUT_WIDTH +: OUT_WIDTH];
            diff  = int'(got_y) - int'(exp_y[i]);
            if (diff < 0) diff = -diff;
            if (diff > TOLERANCE) lane_fail = 1'b1;
        end

        if (!valid_out) lane_fail = 1'b1;

        if (!lane_fail) begin
            $display("PASS | %-50s | x=[%0d %0d %0d %0d] got=[%0d %0d %0d %0d] exp=[%0d %0d %0d %0d]",
                     test_name,
                     x[0], x[1], x[2], x[3],
                     $signed(data_out[0*OUT_WIDTH +: OUT_WIDTH]),
                     $signed(data_out[1*OUT_WIDTH +: OUT_WIDTH]),
                     $signed(data_out[2*OUT_WIDTH +: OUT_WIDTH]),
                     $signed(data_out[3*OUT_WIDTH +: OUT_WIDTH]),
                     exp_y[0], exp_y[1], exp_y[2], exp_y[3]);
            pass_count++;
        end else begin
            $display("FAIL | %-50s | x=[%0d %0d %0d %0d] got=[%0d %0d %0d %0d] exp=[%0d %0d %0d %0d] valid=%0b",
                     test_name,
                     x[0], x[1], x[2], x[3],
                     $signed(data_out[0*OUT_WIDTH +: OUT_WIDTH]),
                     $signed(data_out[1*OUT_WIDTH +: OUT_WIDTH]),
                     $signed(data_out[2*OUT_WIDTH +: OUT_WIDTH]),
                     $signed(data_out[3*OUT_WIDTH +: OUT_WIDTH]),
                     exp_y[0], exp_y[1], exp_y[2], exp_y[3],
                     valid_out);
            fail_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    logic signed [ACT_WIDTH-1:0] vec [N];

    initial begin
        $display("========================================================");
        $display("  RMSNorm Testbench  (N=%0d, tol=+-%0d LSB)", N, TOLERANCE);
        $display("========================================================");

        // Reset
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // Vec 1 : uniform value (mean_sq=100, rms=10)
        vec = '{16'sd10, 16'sd10, 16'sd10, 16'sd10};
        apply_and_check(vec, 1.0, "Vec 1: uniform small (all 10)");

        // Vec 2 : mixed positive
        vec = '{16'sd50, 16'sd30, 16'sd70, 16'sd20};
        apply_and_check(vec, 1.0, "Vec 2: mixed positive");

        // Vec 3 : mixed signs
        vec = '{ 16'sd100, -16'sd80, 16'sd60, -16'sd40};
        apply_and_check(vec, 1.0, "Vec 3: mixed signs");

        // Vec 4 : large values (near rail)
        vec = '{16'sd30000, 16'sd20000, -16'sd25000, 16'sd15000};
        apply_and_check(vec, 1.0, "Vec 4: large magnitude");

        // Vec 5 : one dominant lane
        vec = '{16'sd4000, 16'sd1, -16'sd2, 16'sd3};
        apply_and_check(vec, 1.0, "Vec 5: one dominant lane");

        // Vec 6 : small values, eps floor engages
        vec = '{16'sd1, -16'sd1, 16'sd1, -16'sd1};
        apply_and_check(vec, 1.0, "Vec 6: tiny - eps floor");

        // Vec 7 : all zeros - eps floor engages, output should be zero
        vec = '{16'sd0, 16'sd0, 16'sd0, 16'sd0};
        apply_and_check(vec, 1.0, "Vec 7: all zeros");

        // Vec 8 : gamma = 2.0 (scales output 2x)
        vec = '{16'sd100, -16'sd100, 16'sd100, -16'sd100};
        apply_and_check(vec, 1.999969, "Vec 8: gamma ~ 2.0");

        // Vec 9 : gamma = 0.5
        vec = '{16'sd200, 16'sd200, -16'sd200, -16'sd200};
        apply_and_check(vec, 0.5, "Vec 9: gamma = 0.5");

        // Vec 10: symmetric around zero, moderate
        vec = '{16'sd500, -16'sd500, 16'sd500, -16'sd500};
        apply_and_check(vec, 1.0, "Vec 10: symmetric");

        // -------------------------------------------------------------------------
        // Summary
        // -------------------------------------------------------------------------
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
