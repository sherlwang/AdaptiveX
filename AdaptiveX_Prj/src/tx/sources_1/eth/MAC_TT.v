`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/05/07 20:58:32
// Design Name: 
// Module Name: MAC_TT
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


module MAC_TT(
input               clk_phy,
input               rst_n_phy,
input               mac_rx_1_clk   ,   //mac_rx_2_clk ,
input  [63:0]       mac_rx_1_tdata ,   //mac_rx_2_tdata ,
input  [7:0]        mac_rx_1_tkeep ,   //mac_rx_2_tkeep ,
input               mac_rx_1_tlast ,   //mac_rx_2_tlast ,
input               mac_rx_1_tvalid,   //mac_rx_2_tvalid,
output              mac_rx_1_tready,   //mac_rx_2_tready,

output [128-1:0]    tt_out_data,
output [64-1:0]     tt_out_1_data,  //tt_out_2_data,
output              tt_out_v,
output              tt_out_1_v   ,  //tt_out_2_v,
input               tt_out_rdy,
// output [3:0]        Error_MACfifo,
// input  [127:0]       phy_out  ,
output [1:0]        Error_MACfifo,
input  [64:0]       phy_out  ,
input               phy_out_v


);

//wire            tt_out_1_v;
wire            tt_out_1_last,tt_out_1_rdy;
//wire [63:0]     tt_out_1_data;
ten_ge_tt_pack ten_ge_tt_pack_1(
    .mac_clk(mac_rx_1_clk),
    .arst_n(rst_n_phy),
            
    .mac_core_rx_tdata (mac_rx_1_tdata), 
    .mac_core_rx_tkeep (mac_rx_1_tkeep), 
    .mac_core_rx_tlast (mac_rx_1_tlast), 
    .mac_core_rx_tvalid(mac_rx_1_tvalid),
    .mac_core_rx_tready(mac_rx_1_tready),
    .user_fin_tready(Error_MACfifo[1]),
    
    .tt_rx_tclk  (clk_phy),
    .tt_rx_tdata (tt_out_1_data),
    .tt_rx_tlast (tt_out_1_last),
    .tt_rx_tvalid(tt_out_1_v),
    .tt_rx_tready(tt_out_1_rdy)
);
assign Error_MACfifo[0] = mac_rx_1_tready;
// assign Error_MACfifo[2] = mac_rx_2_tready;


wire            tt_out_2_v;
wire            tt_out_2_last,tt_out_2_rdy;
//wire [63:0]     tt_out_2_data;
// ten_ge_tt_pack ten_ge_tt_pack_2(
//     .mac_clk(mac_rx_2_clk),
//     .arst_n(rst_n_phy),
            
//     .mac_core_rx_tdata (mac_rx_2_tdata), 
//     .mac_core_rx_tkeep (mac_rx_2_tkeep), 
//     .mac_core_rx_tlast (mac_rx_2_tlast), 
//     .mac_core_rx_tvalid(mac_rx_2_tvalid),
//     .mac_core_rx_tready(mac_rx_2_tready),
//     .user_fin_tready(Error_MACfifo[3]),
    
//     .tt_rx_tclk  (clk_phy),
//     .tt_rx_tdata (tt_out_2_data),
//     .tt_rx_tlast (tt_out_2_last),
//     .tt_rx_tvalid(tt_out_2_v),
//     .tt_rx_tready(tt_out_2_rdy)
// );

assign tt_out_data  = tt_out_1_data;
// assign tt_out_data  = {tt_out_2_data,tt_out_1_data};
assign tt_out_v     = (tt_out_2_v | tt_out_1_v);
assign tt_out_1_rdy = tt_out_rdy;
assign tt_out_2_rdy = tt_out_rdy;



// ILA_tt ILA_tt (
// 	.clk(clk_phy), // input wire clk
// 	.probe0(tt_out_1_data), // input wire [63:0]  probe0  
// 	.probe1(tt_out_1_v), // input wire [0:0]  probe1 
// 	.probe2(tt_out_2_data), // input wire [63:0]  probe2 
// 	.probe3(tt_out_2_v), // input wire [0:0]  probe3 
// 	.probe4(tt_out_rdy), // input wire [0:0]  probe4 
// 	.probe5(phy_out  ), // input wire [64:0]  probe5 
// 	.probe6(phy_out_v) // input wire [0:0]  probe6
// );





endmodule
