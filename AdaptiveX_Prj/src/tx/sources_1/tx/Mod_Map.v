`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: Mod_Map
// Description: Shared BPSK/QPSK/16QAM mapper; lane 0 in bits [15:0], signed Q14.
// Tool Versions: Verilog-2001 / Vivado 2021.2
// Revision: 2026/10/14 - Per-word data/mode alignment, no mode reset.
//////////////////////////////////////////////////////////////////////////////////

module Mod_Map (
    input clk,
    input rst_n,
    input [3:0] phy_ploy,
    input [1:0] phy_mod,
    input [31:0] din,
    input din_v,
    output reg [127:0] dout_i,
    output reg [127:0] dout_q,
    output reg dout_v,
    output reg [3:0] dout_ploy,
    output reg [1:0] dout_mod
);
    reg [127:0] map_i;
    reg [127:0] map_q;
    reg [3:0] bits_lane;
    reg signed [15:0] level_i;
    reg signed [15:0] level_q;
    integer lane;

    // Bit zero is the first scalar MATLAB bit. Unit mean constellation power.
    // Q14: BPSK=16384; QPSK=round(16384/sqrt(2)); 16QAM=round(16384*[1,3]/sqrt(10)).
    always @(*) begin
        map_i = 128'd0;
        map_q = 128'd0;
        bits_lane = 4'd0;
        level_i = 16'sd0;
        level_q = 16'sd0;
        for (lane = 0; lane < 8; lane = lane + 1) begin
            if (lane < phy_ploy) begin
                case (phy_mod)
                    2'd0: begin
                        map_i[16*lane+:16] = din[lane] ? -16'sd16384 : 16'sd16384;
                    end
                    2'd1: begin
                        map_i[16*lane+:16] = din[2*lane] ? -16'sd11585 : 16'sd11585;
                        map_q[16*lane+:16] = din[2*lane+1] ? -16'sd11585 : 16'sd11585;
                    end
                    2'd2: begin
                        bits_lane = din[4*lane+:4];
                        level_i = bits_lane[2] ? 16'sd5181 : 16'sd15543;
                        level_q = bits_lane[3] ? 16'sd5181 : 16'sd15543;
                        map_i[16*lane+:16] = bits_lane[0] ? -level_i : level_i;
                        map_q[16*lane+:16] = bits_lane[1] ? -level_q : level_q;
                    end
                    default: begin
                        map_i[16*lane+:16] = 16'd0;
                        map_q[16*lane+:16] = 16'd0;
                    end
                endcase
            end
        end
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            dout_i <= 128'd0;
            dout_q <= 128'd0;
            dout_v <= 1'b0;
            dout_ploy <= 4'd2;
            dout_mod <= 2'd0;
        end else begin
            dout_i <= din_v ? map_i : 128'd0;
            dout_q <= din_v ? map_q : 128'd0;
            dout_v <= din_v;
            if (din_v) begin
                dout_ploy <= phy_ploy;
                dout_mod  <= phy_mod;
            end
        end
    end
endmodule
