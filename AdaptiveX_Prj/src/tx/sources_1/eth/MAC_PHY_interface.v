`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2020/12/15 15:52:35
// Design Name: 
// Module Name: MAC_PHY_interface
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


module MAC_PHY_interface(
input                   phy_clk,
input                   rst_n,
input       [3:0]       phy_ploy,
input       [1:0]       phy_mod,
output reg  [3:0]       dout_ploy,
output reg  [1:0]       dout_mod,

//input [64-1:0]          din_1_data,
//output                  din_ready_mac,
//input                   tt_out_1_v,

//output reg [64-1:0]     dout_data = 'd0,
//output reg              dout_valid = 1'b0,
//input                   dout_ready_mac
input [64-1:0]         din_data,
// input [128-1:0]         din_data,
input [64-1:0]          din_1_data,  //din_2_data,
input                   din_valid,
output                  din_ready_mac,
input                   tt_out_1_v,
// input                   tt_out_2_v,

output reg [64-1:0]    dout_data = 'd0,
// output reg [128-1:0]    dout_data = 'd0,
output reg              dout_valid = 1'b0,
input                   dout_ready_mac
);


//always@(posedge phy_clk or negedge rst_n)begin
//    if(!rst_n)
//        dout_data <= 'd0;
//    else if(din_ready_mac)
//        if(tt_out_1_v)
//            dout_data <= din_1_data;
//        else
//            dout_data <= 'd0;
//    else
//        dout_data <= 'd0;
//end

always@(posedge phy_clk or negedge rst_n)begin
    if(!rst_n)
        dout_data <= 'd0;
    else if(din_ready_mac)
        if(tt_out_1_v)
            dout_data <= din_1_data;
        else
            dout_data <= 'd0;
    else
        dout_data <= 'd0;
end

// always@(posedge phy_clk or negedge rst_n)begin
//     if(!rst_n)
//         dout_data <= 'd0;
//     else if(din_ready_mac)
//         if(tt_out_1_v & tt_out_2_v)
//             dout_data <= {din_2_data,din_1_data};
//         else if(tt_out_1_v)
//             dout_data <= {64'd0,din_1_data};
//         else if(tt_out_2_v)
//             dout_data <= {din_2_data,64'd0};
//         else
//             dout_data <= 'd0;
//     else
//         dout_data <= 'd0;
// end

reg        dout_ready_mac_d1;
reg        dout_ready_mac_d2;
reg [5:0] mode_d1,mode_d2;
always@(posedge phy_clk or negedge rst_n)begin
    if(!rst_n)begin
        mode_d1 <= {4'd2,2'd0};
        mode_d2 <= {4'd2,2'd0};
        dout_ploy <= 4'd2;
        dout_mod <= 2'd0;
    end
    else begin
        mode_d1 <= {phy_ploy,phy_mod};
        mode_d2 <= mode_d1;
        if(dout_ready_mac_d2)begin
            dout_ploy <= mode_d2[5:2];
            dout_mod <= mode_d2[1:0];
        end
    end
end

always@(posedge phy_clk or negedge rst_n)
    if(!rst_n)
        begin
            dout_ready_mac_d1 <= 1'd0;
            dout_ready_mac_d2 <= 1'd0;
        end
    else
        begin
            dout_ready_mac_d1 <= dout_ready_mac;
            dout_ready_mac_d2 <= dout_ready_mac_d1;
        end


always@(posedge phy_clk or negedge rst_n)
    if(!rst_n)
        dout_valid <= 'd0;
    else
        dout_valid <= dout_ready_mac_d2;

assign din_ready_mac = dout_ready_mac_d2;

endmodule
