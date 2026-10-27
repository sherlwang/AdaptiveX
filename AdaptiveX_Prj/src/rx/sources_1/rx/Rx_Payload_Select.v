`timescale 1ns / 1ps
`default_nettype none

// Select P active ploys; keep the pilot for NLMS training.
module Rx_Payload_Select #(
    parameter integer DYNAMIC_MODE = 0
) (
    input wire clk,
    input wire rst_n,
    input wire [3:0] phy_ploy,
    input wire [127:0] din_i,
    input wire [127:0] din_q,
    input wire din_v,
    input wire [31:0] din_frame_id,
    output reg [127:0] dout_i,
    output reg [127:0] dout_q,
    output reg dout_v,
    output reg dout_pilot,
    output reg dout_start,
    output reg [2:0] dout_blk,
    output reg [3:0] dout_ploy,
    output reg [31:0] dout_frame_id
);

    reg [3:0] mode_cfg;
    wire [3:0] active_ploy;
    reg [7:0] din_clk_cnt;
    reg [2:0] din_blk_cnt;
    integer ploy_idx;
    integer source_ploy;

    ////////////////////////// Logic //////////////////////////

    assign active_ploy = (DYNAMIC_MODE != 0 && din_clk_cnt == 0) ? phy_ploy : mode_cfg;

    always @(posedge clk) begin
        if (!rst_n) begin
            mode_cfg <= phy_ploy;
            din_clk_cnt <= 0;
            din_blk_cnt <= 0;
            dout_i <= 0;
            dout_q <= 0;
            dout_v <= 0;
            dout_pilot <= 0;
            dout_start <= 0;
            dout_blk <= 0;
            dout_ploy <= 4'd2;
            dout_frame_id <= 0;
        end else begin
            dout_v <= din_v;
            dout_pilot <= din_v && din_clk_cnt == 0;
            dout_start <= din_v && din_clk_cnt == 1;
            if (din_v) begin
                if (DYNAMIC_MODE != 0 && din_clk_cnt == 0) mode_cfg <= phy_ploy;
                dout_ploy <= active_ploy;
                dout_frame_id <= din_frame_id;
                dout_i <= 0;
                dout_q <= 0;
                dout_blk <= din_blk_cnt;
                for (ploy_idx = 0; ploy_idx < 8; ploy_idx = ploy_idx + 1) begin
                    source_ploy = (active_ploy == 2) ?
                        4 * ploy_idx : (active_ploy == 4) ? 2 * ploy_idx : ploy_idx;
                    if (ploy_idx < active_ploy) begin
                        dout_i[ploy_idx*16+:16] <= din_i[source_ploy*16+:16];
                        dout_q[ploy_idx*16+:16] <= din_q[source_ploy*16+:16];
                    end
                end
                din_clk_cnt <= din_clk_cnt + 8'd1;
                if (din_clk_cnt == 255) din_blk_cnt <= (din_blk_cnt == 5) ? 3'd0 : din_blk_cnt + 3'd1;
            end
        end
    end


endmodule
`default_nettype wire
