`timescale 1ns/1ps
`default_nettype none

module ternary_accelerator_wrapper #(
    parameter VECTOR_SIZE = 16,
    parameter ACT_WIDTH   = 8,
    parameter ROWS        = 4,
    parameter ACC_WIDTH   = 16,
    parameter RMSNORM_N   = 4,
    parameter RMSNORM_W   = 16
) (
    input  wire                               clk,
    input  wire                               rst_n,
    input  wire                               start_inference,
    input  wire [7:0]                         total_tiles,

    // AXI-Stream Slave
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TVALID" *)
    input  wire                               s_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TDATA" *)
    input  wire [103:0]                       s_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TREADY" *)
    output wire                               s_axis_tready,

    input  wire [127:0]                       s_axis_act_data,

    // AXI-Stream Master
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TVALID" *)
    output wire                               m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TDATA" *)
    output wire [15:0]                        m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TLAST" *)
    output wire                               m_axis_tlast,

    output wire                               inference_done
);

    // Clock interface attributes
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axis:m_axis, ASSOCIATED_RESET rst_n" *)
    wire clk_internal;
    assign clk_internal = clk;

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    wire rst_n_internal;
    assign rst_n_internal = rst_n;

    ternary_accelerator_top #(
        .VECTOR_SIZE (VECTOR_SIZE),
        .ACT_WIDTH   (ACT_WIDTH),
        .ROWS        (ROWS),
        .ACC_WIDTH   (ACC_WIDTH),
        .RMSNORM_N   (RMSNORM_N),
        .RMSNORM_W   (RMSNORM_W)
    ) u_top (
        .clk              (clk_internal),
        .rst_n            (rst_n_internal),
        .start_inference  (start_inference),
        .total_tiles      (total_tiles),
        .s_axis_tvalid    (s_axis_tvalid),
        .s_axis_tdata     (s_axis_tdata),
        .s_axis_act_data  (s_axis_act_data),
        .s_axis_tready    (s_axis_tready),
        .m_axis_tvalid    (m_axis_tvalid),
        .m_axis_tdata     (m_axis_tdata),
        .m_axis_tlast     (m_axis_tlast),
        .inference_done   (inference_done)
    );

endmodule

`default_nettype wire
