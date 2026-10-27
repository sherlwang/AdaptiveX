`timescale 1ns / 1ps
`default_nettype none

// Rotate one 16q13 sample using phase in turns.
module Rx_CFO_Rotate_Lane (
    input wire clk,
    input wire rst_n,
    input wire [31:0] phase_turn,
    input wire signed [15:0] din_i,
    input wire signed [15:0] din_q,
    output reg signed [15:0] dout_i,
    output reg signed [15:0] dout_q
);

    (* rom_style = "block" *) reg [15:0] quarter[0:1024];
    reg [15:0] sin_mag;
    reg [15:0] cos_mag;
    reg sin_neg;
    reg cos_neg;
    reg signed [15:0] din_i_d1;
    reg signed [15:0] din_q_d1;
    reg signed [31:0] xi_cos_d2;
    reg signed [31:0] xq_sin_d2;
    reg signed [31:0] xi_sin_d2;
    reg signed [31:0] xq_cos_d2;
    reg signed [32:0] rotate_d3_i;
    reg signed [32:0] rotate_d3_q;
    wire [1:0] quadrant;
    wire [9:0] offset;
    wire [10:0] direct;
    wire [10:0] reverse;
    wire [10:0] sin_addr;
    wire [10:0] cos_addr;
    wire signed [15:0] sin_value;
    wire signed [15:0] cos_value;

    ////////////////////////// Logic //////////////////////////

    function [15:0] sat_q13;
        input signed [32:0] product;
        reg signed [32:0] rounded;
        reg signed [32:0] shifted;
        begin
            rounded = product + (product[32] ? 33'sd16383 : 33'sd16384);
            shifted = rounded >>> 15;
            if (shifted > 33'sd32767) sat_q13 = 16'h7fff;
            else if (shifted < -33'sd32768) sat_q13 = 16'h8000;
            else sat_q13 = shifted[15:0];
        end
    endfunction

    initial $readmemh("rx_cfo_quarter_q15.mem", quarter);
    assign quadrant = phase_turn[31:30];
    assign offset = phase_turn[29:20];
    assign direct = {1'b0, offset};
    assign reverse = 11'd1024 - {1'b0, offset};
    assign sin_addr = quadrant[0] ? reverse : direct;
    assign cos_addr = quadrant[0] ? direct : reverse;
    assign sin_value = sin_neg ? -$signed(sin_mag) : $signed(sin_mag);
    assign cos_value = cos_neg ? -$signed(cos_mag) : $signed(cos_mag);

    always @(posedge clk) begin
        sin_mag <= quarter[sin_addr];
        cos_mag <= quarter[cos_addr];
        sin_neg <= quadrant[1];
        cos_neg <= quadrant[1] ^ quadrant[0];
        din_i_d1 <= din_i;
        din_q_d1 <= din_q;
        xi_cos_d2 <= din_i_d1 * cos_value;
        xq_sin_d2 <= din_q_d1 * sin_value;
        xi_sin_d2 <= din_i_d1 * sin_value;
        xq_cos_d2 <= din_q_d1 * cos_value;
        rotate_d3_i <= {xi_cos_d2[31], xi_cos_d2} - {xq_sin_d2[31], xq_sin_d2};
        rotate_d3_q <= {xi_sin_d2[31], xi_sin_d2} + {xq_cos_d2[31], xq_cos_d2};
        if (!rst_n) begin
            dout_i <= 16'sd0;
            dout_q <= 16'sd0;
        end else begin
            dout_i <= sat_q13(rotate_d3_i);
            dout_q <= sat_q13(rotate_d3_q);
        end
    end

endmodule
`default_nettype wire
