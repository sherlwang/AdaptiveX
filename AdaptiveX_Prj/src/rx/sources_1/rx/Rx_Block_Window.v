`timescale 1ns / 1ps
`default_nettype none

// Take clocks 4 through 259 in every block; training and data both advance by 5.
module Rx_Block_Window #(
    parameter integer DYNAMIC_MODE = 0
) (
    input wire clk,
    input wire rst_n,
    input wire [3:0] phy_ploy,
    input wire [127:0] din_i,
    input wire [127:0] din_q,
    input wire din_v,
    input wire din_start,
    input wire [31:0] din_frame_id,
    output reg [127:0] dout_i,
    output reg [127:0] dout_q,
    output reg dout_v,
    output reg dout_start,
    output reg [3:0] dout_ploy,
    output reg [31:0] dout_frame_id
);

    reg [3:0] phy_ploy_cfg;
    reg [8:0] din_clk_cnt;
    reg [2:0] din_blk_cnt;
    reg frame_active;
    wire [8:0] din_clk_idx;
    wire [2:0] din_blk_idx;
    wire window_v;
    wire [3:0] active_ploy;
    integer ploy_idx;

    ////////////////////////// Logic //////////////////////////

    assign active_ploy = (DYNAMIC_MODE != 0 && din_start) ? phy_ploy : phy_ploy_cfg;
    assign din_clk_idx = din_start ? 9'd0 : din_clk_cnt;
    assign din_blk_idx = din_start ? 3'd0 : din_blk_cnt;
    assign window_v = (din_clk_idx >= 9'd4 && din_clk_idx < 9'd260);

    always @(posedge clk) begin
        if (!rst_n) begin
            phy_ploy_cfg <= phy_ploy;
            din_clk_cnt <= 9'd0;
            din_blk_cnt <= 3'd0;
            frame_active <= 1'b0;
            dout_i <= 128'd0;
            dout_q <= 128'd0;
            dout_v <= 1'b0;
            dout_start <= 1'b0;
            dout_ploy <= 4'd2;
            dout_frame_id <= 0;
        end else begin
            dout_v <= 1'b0;
            dout_start <= 1'b0;
            if (DYNAMIC_MODE != 0 && din_v && din_start) phy_ploy_cfg <= phy_ploy;
            if (din_start) begin
                frame_active <= 1'b1;
                din_blk_cnt  <= 3'd0;
            end
            if (din_v && (frame_active || din_start)) begin
                if (din_clk_idx == 9'd264) begin
                    din_clk_cnt <= 9'd0;
                    if (din_blk_idx == 3'd7) frame_active <= 1'b0;
                    else din_blk_cnt <= din_blk_idx + 3'd1;
                end else din_clk_cnt <= din_clk_idx + 9'd1;
                if (window_v) begin
                    dout_i <= 128'd0;
                    dout_q <= 128'd0;
                    for (ploy_idx = 0; ploy_idx < 8; ploy_idx = ploy_idx + 1) begin
                        if (active_ploy == 4'd2) begin
                            if (ploy_idx == 0 || ploy_idx == 4) begin
                                dout_i[ploy_idx*16+:16] <= din_i[(ploy_idx/4)*16+:16];
                                dout_q[ploy_idx*16+:16] <= din_q[(ploy_idx/4)*16+:16];
                            end
                        end else if (active_ploy == 4'd4) begin
                            if ((ploy_idx % 2) == 0) begin
                                dout_i[ploy_idx*16+:16] <= din_i[(ploy_idx/2)*16+:16];
                                dout_q[ploy_idx*16+:16] <= din_q[(ploy_idx/2)*16+:16];
                            end
                        end else begin
                            dout_i[ploy_idx*16+:16] <= din_i[ploy_idx*16+:16];
                            dout_q[ploy_idx*16+:16] <= din_q[ploy_idx*16+:16];
                        end
                    end
                    dout_v <= 1'b1;
                    dout_start <= din_clk_idx == 9'd4 && din_blk_idx == 3'd0;
                    dout_ploy <= active_ploy;
                    dout_frame_id <= din_frame_id;
                end
            end
        end
    end

endmodule
`default_nettype wire
