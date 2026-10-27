`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/05/29 21:05:14
// Design Name: 
// Module Name: MAC_TX_FlowControl
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


module MAC_TX_FlowControl#(
    parameter   FPGA_TX_MAC_ADDR = 48'h00_00_00_33_22_11
)(
input               clk,

output reg [8:0]    ctl_tx_pause_req           ,
output              ctl_tx_resend_pause        ,
output reg [8:0]    ctl_tx_pause_enable        ,
output  [15:0]      ctl_tx_pause_quanta0       ,
output  [15:0]      ctl_tx_pause_quanta1       ,
output  [15:0]      ctl_tx_pause_quanta2       ,
output  [15:0]      ctl_tx_pause_quanta3       ,
output  [15:0]      ctl_tx_pause_quanta4       ,
output  [15:0]      ctl_tx_pause_quanta5       ,
output  [15:0]      ctl_tx_pause_quanta6       ,
output  [15:0]      ctl_tx_pause_quanta7       ,
output reg [15:0]   ctl_tx_pause_quanta8       ,
output  [15:0]      ctl_tx_pause_refresh_timer0,
output  [15:0]      ctl_tx_pause_refresh_timer1,
output  [15:0]      ctl_tx_pause_refresh_timer2,
output  [15:0]      ctl_tx_pause_refresh_timer3,
output  [15:0]      ctl_tx_pause_refresh_timer4,
output  [15:0]      ctl_tx_pause_refresh_timer5,
output  [15:0]      ctl_tx_pause_refresh_timer6,
output  [15:0]      ctl_tx_pause_refresh_timer7,
output reg [15:0]   ctl_tx_pause_refresh_timer8,
output reg  [47:0]  ctl_tx_da_gpp               ='d0,
output reg  [47:0]  ctl_tx_sa_gpp               ='d0,
//output reg  [15:0]  ctl_tx_ethertype_gpp        ='h8808,
//output reg  [15:0]  ctl_tx_opcode_gpp           ='h0001,
output  [15:0]      ctl_tx_ethertype_gpp       ,
output  [15:0]      ctl_tx_opcode_gpp          ,
output  [47:0]      ctl_tx_da_ppp              ,
output  [47:0]      ctl_tx_sa_ppp              ,
output  [15:0]      ctl_tx_ethertype_ppp       ,
output  [15:0]      ctl_tx_opcode_ppp          ,

output  [14:0]      VIO_FIFO_ASSERT            ,       
output  [14:0]      VIO_FIFO_NEGATE            ,       
input   [47:0]      MAC_SOURCE_ADDR            ,       
input               MAC_Pause      
);


wire               VIO_Pause_req              ;
wire   [47:0]      VIO_Pause_da_MAC            ;
wire   [47:0]      VIO_Pause_sa_MAC            ;
wire   [15:0]      VIO_Pause_quanta           ;
wire   [15:0]      VIO_Pause_timer            ;
wire   [15:0]      VIO_Pause_ethertype        ;
wire   [15:0]      VIO_Pause_opcode           ;

Vio_MAC_FlowControl Vio_MAC_FlowControl (
 .clk(clk),                // input wire clk
 .probe_out0(VIO_FIFO_ASSERT   ),  // output wire [47 : 0] probe_out0
 .probe_out1(VIO_FIFO_NEGATE    ),  // output wire [47 : 0] probe_out1
 .probe_out2(VIO_Pause_quanta   ),  // output wire [45 : 0] probe_out2
 .probe_out3(VIO_Pause_timer    ),  // output wire [15 : 0] probe_out3
 .probe_out4(VIO_Pause_sa_MAC    ), // output wire [15 : 0] probe_out3
 .probe_out5(VIO_Pause_da_MAC    )  // output wire [15 : 0] probe_out3
);




always@(posedge clk)begin
//    ctl_tx_da_gpp <= 48'h0180_C200_0001;
    ctl_tx_da_gpp <= VIO_Pause_da_MAC;
    ctl_tx_sa_gpp <= VIO_Pause_sa_MAC;
    
    ctl_tx_pause_req    <= {MAC_Pause,8'd0};
    ctl_tx_pause_enable <= {MAC_Pause,8'd0};
    
    ctl_tx_pause_quanta8        <= VIO_Pause_quanta;
    ctl_tx_pause_refresh_timer8 <= VIO_Pause_timer ; 
    

end   
assign ctl_tx_ethertype_gpp = 16'h8808;//Pause Frame
assign ctl_tx_opcode_gpp    = 16'h0001;  





assign ctl_tx_resend_pause = 'd0;

assign ctl_tx_pause_quanta0        = 'd0;
assign ctl_tx_pause_quanta1        = 'd0;
assign ctl_tx_pause_quanta2        = 'd0;
assign ctl_tx_pause_quanta3        = 'd0;
assign ctl_tx_pause_quanta4        = 'd0;
assign ctl_tx_pause_quanta5        = 'd0;
assign ctl_tx_pause_quanta6        = 'd0;
assign ctl_tx_pause_quanta7        = 'd0;
assign ctl_tx_pause_refresh_timer0 = 'd0;
assign ctl_tx_pause_refresh_timer1 = 'd0;
assign ctl_tx_pause_refresh_timer2 = 'd0;
assign ctl_tx_pause_refresh_timer3 = 'd0;
assign ctl_tx_pause_refresh_timer4 = 'd0;
assign ctl_tx_pause_refresh_timer5 = 'd0;
assign ctl_tx_pause_refresh_timer6 = 'd0;
assign ctl_tx_pause_refresh_timer7 = 'd0;

assign ctl_tx_da_ppp               = 'd0;
assign ctl_tx_sa_ppp               = 'd0;
assign ctl_tx_ethertype_ppp        = 'd0;
assign ctl_tx_opcode_ppp           = 'd0;


endmodule
