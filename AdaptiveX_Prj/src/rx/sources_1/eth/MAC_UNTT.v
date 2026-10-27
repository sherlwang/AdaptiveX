`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/05/10 20:22:14
// Design Name: 
// Module Name: MAC_UNTT
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

module MAC_UNTT(
    input               clk_phy,
    input               rst_n,
    input               rst_n_mac,
    input               mac_core_1_clk ,
    output  [63:0]      mac_tx_1_tdata ,
    output  [7:0]       mac_tx_1_tkeep ,
    output              mac_tx_1_tlast ,
    output              mac_tx_1_tvalid,
    input               mac_tx_1_tready,
    input [63:0]        phy_out_data,
    input               phy_out_v,
    output[1:0]         tt_out_rdy
);

    wire    [64-1:0]    rx_1_out    ;
    wire                rx_1_out_v  ;
    ten_ge_tt_unpack ten_ge_tt_unpack_1(
        . mac_clk(mac_core_1_clk),
        . arst_n(rst_n),
        . mac_rst_n(rst_n_mac),
        
        . mac_core_tx_tdata (mac_tx_1_tdata ),
        . mac_core_tx_tkeep (mac_tx_1_tkeep ),
        . mac_core_tx_tlast (mac_tx_1_tlast ),
        . mac_core_tx_tvalid(mac_tx_1_tvalid),
        . mac_core_tx_tready(mac_tx_1_tready),
        
        .tt_tx_tclk(clk_phy),
        .tt_tx_tdata(rx_1_out),
        .tt_tx_tvalid(rx_1_out_v),
        .tt_tx_tready(tt_out_rdy[0])
    );

    assign rx_1_out     = phy_out_data;
    assign rx_1_out_v   = phy_out_v;

endmodule