`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: Pilot_Insert
// Description: One pilot clock + 255 data clocks = 256 valid clocks.
// Tool Versions: Verilog-2001 / Vivado 2021.2
// Revision: 2026/10/14 - Pilot and held-data modes follow their own samples.
//////////////////////////////////////////////////////////////////////////////////

module Pilot_Insert (
    input clk,
    input rst_n,
    input [3:0] phy_ploy,
    input [1:0] phy_mod,
    input [127:0] din_i,
    input [127:0] din_q,
    input din_v,
    output reg [127:0] dout_i,
    output reg [127:0] dout_q,
    output reg dout_v,
    output reg [3:0] dout_ploy,
    output reg [1:0] dout_mod
);
    reg [127:0] held_i;
    reg [127:0] held_q;
    reg held_v;
    reg [5:0] held_mode;
    reg [7:0] cnt_data;
    reg [127:0] pilot_i;
    reg [127:0] pilot_q;
    reg signed [15:0] pilot_u_i;
    reg signed [15:0] pilot_u_q;
    integer lane;

    // First half is 1; second half identifies modulation.
    always @(*) begin
        pilot_i = 128'd0;
        pilot_q = 128'd0;
        case (phy_mod)
            2'd0: begin
                pilot_u_i = 16'sd16384;
                pilot_u_q = 16'sd0;
            end
            2'd1: begin
                pilot_u_i = -16'sd8192;
                pilot_u_q = 16'sd14189;
            end
            2'd2: begin
                pilot_u_i = -16'sd8192;
                pilot_u_q = -16'sd14189;
            end
            default: begin
                pilot_u_i = 16'sd0;
                pilot_u_q = 16'sd0;
            end
        endcase
        for (lane = 0; lane < 8; lane = lane + 1) begin
            if (lane < phy_ploy) begin
                if (lane < (phy_ploy >> 1)) begin
                    pilot_i[16*lane+:16] = 16'sd16384;
                end else begin
                    pilot_i[16*lane+:16] = pilot_u_i;
                    pilot_q[16*lane+:16] = pilot_u_q;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            held_i <= 128'd0;
            held_q <= 128'd0;
            held_v <= 1'b0;
            held_mode <= {4'd2, 2'd0};
            dout_ploy <= 4'd2;
            dout_mod <= 2'd0;
            cnt_data <= 8'd0;
            dout_i <= 128'd0;
            dout_q <= 128'd0;
            dout_v <= 1'b0;
        end else begin
            held_v <= din_v;
            dout_v <= held_v || (din_v && cnt_data == 0);
            if (din_v) begin
                held_i <= din_i;
                held_q <= din_q;
                held_mode <= {phy_ploy, phy_mod};
                cnt_data <= (cnt_data == 8'd254) ? 8'd0 : cnt_data + 1'b1;
            end
            if (din_v && cnt_data == 0) begin
                dout_i <= pilot_i;
                dout_q <= pilot_q;
                dout_ploy <= phy_ploy;
                dout_mod <= phy_mod;
            end else if (held_v) begin
                dout_i <= held_i;
                dout_q <= held_q;
                dout_ploy <= held_mode[5:2];
                dout_mod <= held_mode[1:0];
            end else begin
                dout_i <= 128'd0;
                dout_q <= 128'd0;
            end
        end
    end
endmodule
