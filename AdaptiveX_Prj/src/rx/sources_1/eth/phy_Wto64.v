`timescale 1ns / 1ps
`default_nettype none

// Restore the LSB-first 64-bit MAC stream after descrambling.
module phy_Wto64 (
    input wire clk,
    input wire rst_n,
    input wire [31:0] din,
    input wire din_v,
    input wire [5:0] din_width,
    output reg [63:0] dout,
    output reg dout_v
);
    reg [63:0] data_buffer;
    reg [5:0] din_bit_cnt;
    wire [31:0] din_mask;
    wire [63:0] din_shifted;
    wire [6:0] next_bit_cnt;

    assign din_mask = 32'hffffffff >> (32 - din_width);
    assign din_shifted = {32'd0, (din & din_mask)} << din_bit_cnt;
    assign next_bit_cnt = {1'b0, din_bit_cnt} + {1'b0, din_width};

    always @(posedge clk) begin
        if (!rst_n) begin
            data_buffer <= 64'd0;
            din_bit_cnt <= 6'd0;
            dout <= 64'd0;
            dout_v <= 1'b0;
        end else begin
            dout_v <= 1'b0;
            if (din_v) begin
                if (next_bit_cnt == 7'd64) begin
                    dout <= data_buffer | din_shifted;
                    dout_v <= 1'b1;
                    data_buffer <= 64'd0;
                    din_bit_cnt <= 6'd0;
                end else begin
                    data_buffer <= data_buffer | din_shifted;
                    din_bit_cnt <= next_bit_cnt[5:0];
                end
            end
        end
    end
endmodule
`default_nettype wire
