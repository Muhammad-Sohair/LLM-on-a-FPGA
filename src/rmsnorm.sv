// =============================================================================
// Module   : rmsnorm
// Purpose  : Integer Root-Mean-Square Normalization for the BitNet accelerator.
//
//   y_i = gamma * x_i / sqrt( (1/N) * sum_i(x_i^2) + eps )
//
// Datapath (5 register stages, each exactly one clock):
//   Stage 1  Square    :  xi_s1[i]  = register(xi)
//                        sq_s1[i]  = xi*xi
//   Stage 2  Sum/Mean  :  mean_sq_s2 = (Sum(sq_s1) >> LOG2_N) | eps
//   Stage 3  InvSqrt   :  mean_wide  = mean_sq_s2 << SCALE_UP   (precision up)
//                        leading-one -> mantissa idx -> LUT ->
//                        sqrt(1/2) parity correction
//                        inv_rms_s3, lead_s3
//   Stage 4  Multiply  :  prod_s4[i] = x_s3[i] * inv_rms_s3
//   Stage 5  Scale     :  shift_down = 15 + (lead_s4>>1) - SCALE_UP/2
//                        scaled  = prod_s4[i] >>> shift_down   (precision down)
//                        gscaled = (scaled * gamma) >>> 15
//                        data_out[i] = saturate(gscaled)
//
// Control path:
//   A dedicated valid_shift register captures `en` each cycle and shifts it
//   down PIPE_DEPTH stages. valid_out taps the last bit, so it rises exactly
//   PIPE_DEPTH cycles after `en` is first seen -- aligned with the first
//   valid sample emerging from stage 5.
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module rmsnorm #(
    parameter int N           = 4,     // lanes (power of 2)
    parameter int ACT_WIDTH   = 16,    // signed input element width
    parameter int OUT_WIDTH   = 16,    // signed output element width
    parameter int GAMMA_WIDTH = 16,    // Q1.15 unsigned gamma
    parameter int LOG2_N      = 2      // must equal $clog2(N)
) (
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        en,
    input  wire                        valid_in,   // retained for API compat
    input  wire [(N*ACT_WIDTH)-1:0]    data_in,
    input  wire [GAMMA_WIDTH-1:0]      gamma_in,
    output logic [(N*OUT_WIDTH)-1:0]   data_out,
    output wire                        valid_out
);

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------
    localparam int PIPE_DEPTH = 5;                       // Square/Sum/InvSqrt/Mul/Scale
    localparam int SCALE_UP   = 16;                      // precision head-room
    localparam int HALF_SCALE = SCALE_UP / 2;
    localparam int SQ_W       = 2*ACT_WIDTH;             // 32 bits per square
    localparam int SUM_W      = SQ_W + LOG2_N + 1;       // 35
    localparam int WIDE_W     = SUM_W + SCALE_UP;        // 51
    localparam int LEAD_W     = $clog2(WIDE_W) + 1;      // 7
    localparam int INV_W      = 16;                      // Q1.15 inv-sqrt
    localparam int PROD_W     = ACT_WIDTH + INV_W + 1;   // 33
    localparam int GMUL_W     = PROD_W + GAMMA_WIDTH;    // 49
    localparam logic [15:0] SQRT_HALF_Q15 = 16'd23170;   // round(2^15/sqrt(2))

    // -------------------------------------------------------------------------
    // Dedicated valid shift register (drives valid_out)
    // -------------------------------------------------------------------------
    logic [PIPE_DEPTH-1:0] valid_shift;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            valid_shift <= '0;
        else
            valid_shift <= {valid_shift[PIPE_DEPTH-2:0], en};
    end

    assign valid_out = valid_shift[PIPE_DEPTH-1];

    // -------------------------------------------------------------------------
    // Gamma pipeline (aligned so the gamma seen in stage 5 is the one that
    // arrived with the data in stage 1)
    // -------------------------------------------------------------------------
    logic [GAMMA_WIDTH-1:0] gamma_pipe [PIPE_DEPTH];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int s = 0; s < PIPE_DEPTH; s++) gamma_pipe[s] <= '0;
        end else if (en) begin
            gamma_pipe[0] <= gamma_in;
            for (int s = 1; s < PIPE_DEPTH; s++) gamma_pipe[s] <= gamma_pipe[s-1];
        end
    end

    // =========================================================================
    // Stage 1 : Square
    // =========================================================================
    logic signed [ACT_WIDTH-1:0] x_s1  [N];
    logic        [SQ_W-1:0]      sq_s1 [N];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < N; i++) begin
                x_s1[i]  <= '0;
                sq_s1[i] <= '0;
            end
        end else if (en) begin
            for (int i = 0; i < N; i++) begin
                logic signed [ACT_WIDTH-1:0] xi;
                xi       = data_in[i*ACT_WIDTH +: ACT_WIDTH];
                x_s1[i]  <= xi;
                sq_s1[i] <= SQ_W'(xi * xi);
            end
        end
    end

    // =========================================================================
    // Stage 2 : Sum / Mean  (adder tree + >> LOG2_N + eps floor)
    // =========================================================================
    logic signed [ACT_WIDTH-1:0] x_s2 [N];
    logic        [SUM_W-1:0]     mean_sq_s2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mean_sq_s2 <= '0;
            for (int i = 0; i < N; i++) x_s2[i] <= '0;
        end else if (en) begin
            logic [SUM_W-1:0] acc;
            acc = '0;
            for (int i = 0; i < N; i++) acc += SUM_W'(sq_s1[i]);
            mean_sq_s2 <= (acc >> LOG2_N) | SUM_W'(1);   // eps floor
            for (int i = 0; i < N; i++) x_s2[i] <= x_s1[i];
        end
    end

    // =========================================================================
    // Stage 3 : InvSqrt  (scale-up -> leading-one -> LUT -> parity correction)
    // =========================================================================
    function automatic [LEAD_W-1:0] lead_one(input [WIDE_W-1:0] v);
        logic [LEAD_W-1:0] pos;
        pos = '0;
        for (int i = 0; i < WIDE_W; i++) if (v[i]) pos = i[LEAD_W-1:0];
        return pos;
    endfunction

    function automatic [15:0] inv_sqrt_lut(input [5:0] idx);
        case (idx)
            6'd00: inv_sqrt_lut = 16'd32768; 6'd01: inv_sqrt_lut = 16'd32514;
            6'd02: inv_sqrt_lut = 16'd32269; 6'd03: inv_sqrt_lut = 16'd32030;
            6'd04: inv_sqrt_lut = 16'd31799; 6'd05: inv_sqrt_lut = 16'd31574;
            6'd06: inv_sqrt_lut = 16'd31355; 6'd07: inv_sqrt_lut = 16'd31142;
            6'd08: inv_sqrt_lut = 16'd30935; 6'd09: inv_sqrt_lut = 16'd30733;
            6'd10: inv_sqrt_lut = 16'd30535; 6'd11: inv_sqrt_lut = 16'd30343;
            6'd12: inv_sqrt_lut = 16'd30155; 6'd13: inv_sqrt_lut = 16'd29971;
            6'd14: inv_sqrt_lut = 16'd29792; 6'd15: inv_sqrt_lut = 16'd29616;
            6'd16: inv_sqrt_lut = 16'd29445; 6'd17: inv_sqrt_lut = 16'd29277;
            6'd18: inv_sqrt_lut = 16'd29112; 6'd19: inv_sqrt_lut = 16'd28951;
            6'd20: inv_sqrt_lut = 16'd28793; 6'd21: inv_sqrt_lut = 16'd28638;
            6'd22: inv_sqrt_lut = 16'd28486; 6'd23: inv_sqrt_lut = 16'd28337;
            6'd24: inv_sqrt_lut = 16'd28191; 6'd25: inv_sqrt_lut = 16'd28048;
            6'd26: inv_sqrt_lut = 16'd27907; 6'd27: inv_sqrt_lut = 16'd27769;
            6'd28: inv_sqrt_lut = 16'd27633; 6'd29: inv_sqrt_lut = 16'd27500;
            6'd30: inv_sqrt_lut = 16'd27369; 6'd31: inv_sqrt_lut = 16'd27240;
            6'd32: inv_sqrt_lut = 16'd27114; 6'd33: inv_sqrt_lut = 16'd26989;
            6'd34: inv_sqrt_lut = 16'd26866; 6'd35: inv_sqrt_lut = 16'd26746;
            6'd36: inv_sqrt_lut = 16'd26627; 6'd37: inv_sqrt_lut = 16'd26510;
            6'd38: inv_sqrt_lut = 16'd26395; 6'd39: inv_sqrt_lut = 16'd26281;
            6'd40: inv_sqrt_lut = 16'd26169; 6'd41: inv_sqrt_lut = 16'd26059;
            6'd42: inv_sqrt_lut = 16'd25951; 6'd43: inv_sqrt_lut = 16'd25844;
            6'd44: inv_sqrt_lut = 16'd25738; 6'd45: inv_sqrt_lut = 16'd25634;
            6'd46: inv_sqrt_lut = 16'd25532; 6'd47: inv_sqrt_lut = 16'd25431;
            6'd48: inv_sqrt_lut = 16'd25331; 6'd49: inv_sqrt_lut = 16'd25233;
            6'd50: inv_sqrt_lut = 16'd25136; 6'd51: inv_sqrt_lut = 16'd25040;
            6'd52: inv_sqrt_lut = 16'd24946; 6'd53: inv_sqrt_lut = 16'd24852;
            6'd54: inv_sqrt_lut = 16'd24760; 6'd55: inv_sqrt_lut = 16'd24669;
            6'd56: inv_sqrt_lut = 16'd24580; 6'd57: inv_sqrt_lut = 16'd24491;
            6'd58: inv_sqrt_lut = 16'd24403; 6'd59: inv_sqrt_lut = 16'd24317;
            6'd60: inv_sqrt_lut = 16'd24232; 6'd61: inv_sqrt_lut = 16'd24147;
            6'd62: inv_sqrt_lut = 16'd24064; 6'd63: inv_sqrt_lut = 16'd23981;
            default: inv_sqrt_lut = 16'd32768;
        endcase
    endfunction

    logic signed [ACT_WIDTH-1:0] x_s3       [N];
    logic        [INV_W-1:0]     inv_rms_s3;
    logic        [LEAD_W-1:0]    lead_s3;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inv_rms_s3 <= '0;
            lead_s3    <= '0;
            for (int i = 0; i < N; i++) x_s3[i] <= '0;
        end else if (en) begin
            logic [WIDE_W-1:0] wide;
            logic [LEAD_W-1:0] lead;
            logic [WIDE_W-1:0] aligned;
            logic [5:0]        idx6;
            logic [15:0]       inv_base;
            logic [31:0]       inv_corr;

            wide     = WIDE_W'(mean_sq_s2) << SCALE_UP;
            lead     = lead_one(wide);
            aligned  = wide << (WIDE_W - 1 - lead);
            idx6     = aligned[WIDE_W-2 -: 6];
            inv_base = inv_sqrt_lut(idx6);

            if (lead[0]) begin
                inv_corr   = inv_base * SQRT_HALF_Q15;  // Q2.30
                inv_rms_s3 <= inv_corr[30:15];          // back to Q1.15
            end else begin
                inv_rms_s3 <= inv_base;
            end

            lead_s3 <= lead;
            for (int i = 0; i < N; i++) x_s3[i] <= x_s2[i];
        end
    end

    // =========================================================================
    // Stage 4 : Multiply  (x_i * inv_rms)
    // =========================================================================
    logic signed [PROD_W-1:0] prod_s4 [N];
    logic        [LEAD_W-1:0] lead_s4;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lead_s4 <= '0;
            for (int i = 0; i < N; i++) prod_s4[i] <= '0;
        end else if (en) begin
            for (int i = 0; i < N; i++)
                prod_s4[i] <= $signed(x_s3[i]) * $signed({1'b0, inv_rms_s3});
            lead_s4 <= lead_s3;
        end
    end

    // =========================================================================
    // Stage 5 : Scale down + gamma + saturate
    // =========================================================================
    function automatic signed [OUT_WIDTH-1:0] saturate(input signed [GMUL_W-1:0] v);
        logic signed [OUT_WIDTH-1:0] max_v;
        logic signed [OUT_WIDTH-1:0] min_v;
        max_v = {1'b0, {(OUT_WIDTH-1){1'b1}}};
        min_v = {1'b1, {(OUT_WIDTH-1){1'b0}}};
        if      (v > $signed({{(GMUL_W-OUT_WIDTH){1'b0}}, max_v})) saturate = max_v;
        else if (v < $signed({{(GMUL_W-OUT_WIDTH){1'b1}}, min_v})) saturate = min_v;
        else saturate = v[OUT_WIDTH-1:0];
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out <= '0;
        end else if (en) begin
            int                     shift_down;
            logic [GAMMA_WIDTH-1:0] gamma_stage;

            shift_down  = 15 + int'(lead_s4 >> 1) - HALF_SCALE;
            gamma_stage = gamma_pipe[PIPE_DEPTH-1];

            for (int i = 0; i < N; i++) begin
                logic signed [PROD_W-1:0] scaled;
                logic signed [GMUL_W-1:0] gscaled;
                scaled  = prod_s4[i] >>> shift_down;
                gscaled = ($signed(scaled) * $signed({1'b0, gamma_stage})) >>> 15;
                data_out[i*OUT_WIDTH +: OUT_WIDTH] <= saturate(gscaled);
            end
        end
    end

    // Keep tools from flagging valid_in unused at this layer -- it is part of
    // the upstream interface contract even though valid_out is derived from en.
    wire _unused_ok = &{1'b0, valid_in};

endmodule

`default_nettype wire
