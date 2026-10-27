`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/05/25 23:30:52
// Design Name: 
// Module Name: MAC_FIFO
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


module MAC_FIFO(
input               rst_n,
input               mac_rx_0_clk   ,  //mac_rx_1_clk   ,
input  [63:0]       mac_rx_0_tdata ,  //mac_rx_1_tdata ,
input  [7:0]        mac_rx_0_tkeep ,  //mac_rx_1_tkeep ,
input               mac_rx_0_tlast ,  //mac_rx_1_tlast ,
input               mac_rx_0_tvalid,  //mac_rx_1_tvalid,
//  
output  [63:0]      mac_tx_0_tdata ,  //mac_tx_1_tdata ,
output  [7:0]       mac_tx_0_tkeep ,  //mac_tx_1_tkeep ,
output              mac_tx_0_tlast ,  //mac_tx_1_tlast ,
output              mac_tx_0_tvalid,  //mac_tx_1_tvalid,
input               mac_tx_0_tready,  //mac_tx_1_tready,
output              Error_MACfifo_0,  //Error_MACfifo_1,

input               mac_tx_0_clk     ,     //mac_tx_1_clk,
input    [14:0]     VIO_FIFO_ASSERT_0,     //VIO_FIFO_ASSERT_1,
input    [14:0]     VIO_FIFO_NEGATE_0,     //VIO_FIFO_NEGATE_1,
output   [14:0]     MAC_Buffer_count_tx_0, //MAC_Buffer_count_tx_1,
output   [47:0]     MAC_SOURCE_ADDR_0,     //MAC_SOURCE_ADDR_1,
output              MAC_Pause_0           // MAC_Pause_1       
    );

// ILA_MAC_RX ILA_MAC_RX_0 (
// 	.clk(mac_rx_0_clk), // input wire clk
// 	.probe0(mac_rx_0_tdata ), // input wire [63:0]  probe0  
// 	.probe1(mac_rx_0_tkeep ), // input wire [7:0]  probe1 
// 	.probe2(mac_rx_0_tlast ), // input wire [0:0]  probe2 
// 	.probe3(mac_rx_0_tvalid) // input wire [0:0]  probe3
// );


// ILA_MAC_RX ILA_MAC_RX_1 (
// 	.clk(mac_rx_1_clk), // input wire clk
// 	.probe0(mac_rx_1_tdata ), // input wire [63:0]  probe0  
// 	.probe1(mac_rx_1_tkeep ), // input wire [7:0]  probe1 
// 	.probe2(mac_rx_1_tlast ), // input wire [0:0]  probe2 
// 	.probe3(mac_rx_1_tvalid) // input wire [0:0]  probe3
// );


MAC_BufferFlowControl MAC_BufferFlowControl_0(
    .rst_n          (rst_n        ),
    .mac_rx_clk     (mac_rx_0_clk   ),
    .mac_rx_tdata   (mac_rx_0_tdata ),
    .mac_rx_tkeep   (mac_rx_0_tkeep ),
    .mac_rx_tlast   (mac_rx_0_tlast ),
    .mac_rx_tvalid  (mac_rx_0_tvalid),
    .mac_tx_tdata   (mac_tx_0_tdata ),
    .mac_tx_tkeep   (mac_tx_0_tkeep ),
    .mac_tx_tlast   (mac_tx_0_tlast ),
    .mac_tx_tvalid  (mac_tx_0_tvalid),
    .mac_tx_tready  (mac_tx_0_tready),
    .Error_MACfifo  (Error_MACfifo_0),
    
    .mac_tx_clk     (mac_tx_0_clk     ),
    .VIO_FIFO_ASSERT(VIO_FIFO_ASSERT_0),
    .VIO_FIFO_NEGATE(VIO_FIFO_NEGATE_0),
    .MAC_Buffer_count_tx(MAC_Buffer_count_tx_0),
    .MAC_SOURCE_ADDR(MAC_SOURCE_ADDR_0),
    .MAC_Pause      (MAC_Pause_0      )
);

// MAC_BufferFlowControl MAC_BufferFlowControl_1(
//     .rst_n          (rst_n        ),
//     .mac_rx_clk     (mac_rx_1_clk   ),
//     .mac_rx_tdata   (mac_rx_1_tdata ),
//     .mac_rx_tkeep   (mac_rx_1_tkeep ),
//     .mac_rx_tlast   (mac_rx_1_tlast ),
//     .mac_rx_tvalid  (mac_rx_1_tvalid),
//     .mac_tx_tdata   (mac_tx_1_tdata ),
//     .mac_tx_tkeep   (mac_tx_1_tkeep ),
//     .mac_tx_tlast   (mac_tx_1_tlast ),
//     .mac_tx_tvalid  (mac_tx_1_tvalid),
//     .mac_tx_tready  (mac_tx_1_tready),
//     .Error_MACfifo  (Error_MACfifo_1),
    
//     .mac_tx_clk     (mac_tx_1_clk     ),
//     .VIO_FIFO_ASSERT(VIO_FIFO_ASSERT_1),
//     .VIO_FIFO_NEGATE(VIO_FIFO_NEGATE_1),
//     .MAC_Buffer_count_tx(MAC_Buffer_count_tx_1),
//     .MAC_SOURCE_ADDR(MAC_SOURCE_ADDR_1),
//     .MAC_Pause      (MAC_Pause_1      )
// );

endmodule