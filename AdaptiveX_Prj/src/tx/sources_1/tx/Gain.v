`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/03/06 12:15:37
// Design Name: 
// Module Name: Gain
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module Gain #(
    parameter Ploy = 12
) (
    input clk,
    input rst_n,
    input [16*Ploy-1:0] din_i,  //16q14
    input [15:0] Vio_Gain,  //16q9

    output [16*Ploy-1:0] dout_i  //16q14
);

    genvar i;
    generate
        for (i = 0; i <= Ploy - 1; i = i + 1) begin : Mult_Gain
            Mult_Gain Mult_Gain_i (
                .CLK(clk),              // input wire CLK
                .A  (din_i[16*i+:16]),  // input wire [15 : 0] A
                .B  (Vio_Gain),         // input wire [15 : 0] B
                .P  (dout_i[16*i+:16])  // output wire [15 : 0] P
            );
        end
    endgenerate

endmodule
