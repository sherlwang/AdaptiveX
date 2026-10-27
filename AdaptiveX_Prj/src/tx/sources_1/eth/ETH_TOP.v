`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/06/28 15:50:12
// Design Name: 
// Module Name: ETH_TOP
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


module ETH_TOP(
    input       [3:0]      phy_ploy,
    input       [1:0]      phy_mod,
    input                  fpga_sysclk_in    ,
    // input                   ten_ge_refclk_1_p,
    // input                   ten_ge_refclk_1_n,
    input                  clk_phy           ,
    input                  rst_n_phy         ,
    // input                   sys_reset        ,
    input                  mac_rx_0_clk      ,
    input  wire            mac_tx_0_clk      ,
    input  wire [63:0]     mac_rx_0_tdata    ,
    input  wire [ 7:0]     mac_rx_0_tkeep    ,
    input                  mac_rx_0_tlast    ,
    input                  mac_rx_0_tvalid   ,

    input  wire [14:0]     VIO_FIFO_ASSERT_0 ,
    input  wire [14:0]     VIO_FIFO_NEGATE_0 ,
    // input                   gt_rxp_in_0      ,
    // input                   gt_rxn_in_0      ,
    // output                  gt_txp_out_0     ,
    // output                  gt_txn_out_0     ,
    output  [64-1:0]        phy_out          ,
    output                  phy_out_v        ,
    output      [3:0]       phy_out_ploy     ,
    output      [1:0]       phy_out_mod      ,
    output wire            frame_commit     ,
    output wire [3:0]      frame_ploy       ,
    output wire [1:0]      frame_mod        ,

    output wire [14:0]  MAC_Buffer_count_tx_0,
    output wire [47:0]  MAC_SOURCE_ADDR_0    ,
    output wire         MAC_Pause_0          ,
    output wire         Error_MACfifo_0      
);

//////////////////////////////////////////////////////
//                         MAC                      //
//////////////////////////////////////////////////////
    wire    [1:0]           Error_MACfifo;
    // wire                    Error_MACfifo_0;
    
    
    wire    [63:0]          mac_fifo_0_tdata  ;
    wire    [7:0]           mac_fifo_0_tkeep  ;
    wire                    mac_fifo_0_tlast  ;
    wire                    mac_fifo_0_tvalid ;
    wire                    mac_fifo_0_tready ;
    
    wire    [64-1:0]        tt_out_data        ;
    wire                    tt_out_v,tt_out_rdy;
    wire                    tt_out_1_v         ;
    wire    [64-1:0]        tt_out_1_data      ;
//    wire    [64-1:0]       phy_out;
//    wire                   phy_out_v;
    wire                    phy_rdy_encodein   ;
    wire [3:0]              request_ploy;
    wire [1:0]              request_mod;


//    ila_macrx ila_txeth_macrx (
//        .clk(mac_rx_0_clk), // input wire clk
//        .probe0(mac_rx_0_tvalid), // input wire [0:0]  probe0  
//        .probe1(mac_rx_0_tdata ), // input wire [63:0]  probe1 
//        .probe2(mac_rx_0_tkeep ), // input wire [7:0]  probe2 
//        .probe3(mac_rx_0_tlast ) // input wire [0:0]  probe3
//    );

    MAC_FIFO MAC_FIFO(
        .rst_n                  (rst_n_phy              ),//input
        .mac_rx_0_clk           (mac_rx_0_clk           ),//input
        .mac_rx_0_tdata         (mac_rx_0_tdata         ),//input
        .mac_rx_0_tkeep         (mac_rx_0_tkeep         ),//input
        .mac_rx_0_tlast         (mac_rx_0_tlast         ),//input
        .mac_rx_0_tvalid        (mac_rx_0_tvalid        ),//input
        .mac_tx_0_tdata         (mac_fifo_0_tdata       ),
        .mac_tx_0_tkeep         (mac_fifo_0_tkeep       ),
        .mac_tx_0_tlast         (mac_fifo_0_tlast       ),
        .mac_tx_0_tvalid        (mac_fifo_0_tvalid      ),
        .mac_tx_0_tready        (mac_fifo_0_tready      ),//input
        .mac_tx_0_clk           (mac_tx_0_clk           ),//input
        .VIO_FIFO_ASSERT_0      (VIO_FIFO_ASSERT_0      ),//input
        .VIO_FIFO_NEGATE_0      (VIO_FIFO_NEGATE_0      ),//input
        .MAC_Buffer_count_tx_0  (MAC_Buffer_count_tx_0  ),
        .MAC_SOURCE_ADDR_0      (MAC_SOURCE_ADDR_0      ),
        .MAC_Pause_0            (MAC_Pause_0            ),
        .Error_MACfifo_0        (Error_MACfifo_0        )
    );

//    ila_txmac_fifodata ila_txmac_fifodata (
//        .clk( mac_tx_0_clk ), // input wire clk
//        .probe0( mac_fifo_0_tdata  ), // input wire [63:0]  probe0  
//        .probe1( mac_fifo_0_tkeep  ), // input wire [7:0]  probe1 
//        .probe2( mac_fifo_0_tlast  ), // input wire [0:0]  probe2 
//        .probe3( mac_fifo_0_tvalid ), // input wire [0:0]  probe3 
//        .probe4( mac_fifo_0_tready ) // input wire [0:0]  probe4
//    );
    
    MAC_TT MAC_TT(
        .clk_phy        (clk_phy),
        .rst_n_phy      (rst_n_phy),
        .mac_rx_1_clk   (mac_rx_0_clk ),    //input
        .mac_rx_1_tdata (mac_fifo_0_tdata ),//input
        .mac_rx_1_tkeep (mac_fifo_0_tkeep ),//input
        .mac_rx_1_tlast (mac_fifo_0_tlast ),//input
        .mac_rx_1_tvalid(mac_fifo_0_tvalid),//input
        .mac_rx_1_tready(mac_fifo_0_tready),//output
        .tt_out_data    (tt_out_data),
        .tt_out_1_data  (tt_out_1_data),
        .tt_out_v       (tt_out_v   ),
        .tt_out_1_v     (tt_out_1_v ),
        .tt_out_rdy     (tt_out_rdy ),
        .Error_MACfifo  (Error_MACfifo),
        .phy_out        (phy_out  ),
        .phy_out_v      (phy_out_v)
    );
        
    MAC_PHY_interface MAC_PHY_interface(
        .phy_clk        (clk_phy       ),
        .phy_ploy       (request_ploy),
        .phy_mod        (request_mod),
        .dout_ploy      (phy_out_ploy),
        .dout_mod       (phy_out_mod),
        .rst_n          (rst_n_phy      ),
        .din_data       (tt_out_data    ),
        .din_1_data     (tt_out_1_data  ),
        .din_valid      (tt_out_v       ),
        .tt_out_1_v     (tt_out_1_v     ),
        .din_ready_mac  (tt_out_rdy     ), 
        .dout_data     (phy_out         ),  //64bit  //实锟斤拷锟斤拷锟斤拷128bit=>64
        .dout_valid    (phy_out_v       ),
        .dout_ready_mac(phy_rdy_encodein)
    );
    
//    ila_interface u_ila_interface (
//	.clk(clk_phy), // input wire clk


//	.probe0(tt_out_data), // input wire [63:0]  probe0  
//	.probe1(tt_out_v), // input wire [0:0]  probe1 
//	.probe2(tt_out_1_data), // input wire [63:0]  probe2 
//	.probe3(tt_out_1_v), // input wire [0:0]  probe3 
//	.probe4(tt_out_rdy), // input wire [0:0]  probe4 
//	.probe5(phy_rdy_encodein), // input wire [0:0]  probe5 
//	.probe6(phy_out), // input wire [63:0]  probe6 
//	.probe7(phy_out_v) // input wire [0:0]  probe7
//);

    assign frame_ploy = request_ploy;
    assign frame_mod = request_mod;
    phy_in_request u_phy_in_request(
        .clk(clk_phy),
        .rst_n(rst_n_phy),
        .phy_ploy(phy_ploy),
        .phy_mod(phy_mod),
        .phy_rdy(phy_rdy_encodein),
        .dout_ploy(request_ploy),
        .dout_mod(request_mod),
        .frame_commit(frame_commit)
    );
endmodule
