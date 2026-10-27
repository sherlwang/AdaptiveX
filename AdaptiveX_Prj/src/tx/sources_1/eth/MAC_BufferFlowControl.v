`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/05/30 15:09:57
// Design Name: 
// Module Name: MAC_BufferFlowControl
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


module MAC_BufferFlowControl(
input               rst_n,
input               mac_rx_clk   ,
input  [63:0]       mac_rx_tdata ,
input  [7:0]        mac_rx_tkeep ,
input               mac_rx_tlast ,
input               mac_rx_tvalid,
output  [63:0]      mac_tx_tdata ,
output  [7:0]       mac_tx_tkeep ,
output              mac_tx_tlast ,
output              mac_tx_tvalid,
input               mac_tx_tready,
output  reg         Error_MACfifo='d0,

input               mac_tx_clk     ,
input   [14:0]      VIO_FIFO_ASSERT,
input   [14:0]      VIO_FIFO_NEGATE,
output  [47:0]      MAC_SOURCE_ADDR,
output  [14:0]      MAC_Buffer_count_tx,
output              MAC_Pause      
);
    
reg    [14:0]       reg_FIFO_ASSERT = 'd10000;
wire                rst_rx_n;
wire                rst_tx_n;
Reset_Sync u_reset_rx(
    .clk                (mac_rx_clk),
    .arst_n             (rst_n),
    .rst_n              (rst_rx_n)
);
Reset_Sync u_reset_tx(
    .clk                (mac_tx_clk),
    .arst_n             (rst_n),
    .rst_n              (rst_tx_n)
);
reg    [14:0]       reg_FIFO_NEGATE = 'd6000;
wire   [14:0]       MAC_Buffer_count;
wire                mac_rx_tready;
always@(posedge mac_rx_clk)
    Error_MACfifo <= !mac_rx_tready;
MAC_Buffer MAC_Buffer (
//   .wr_rst_busy(),      // output wire wr_rst_busy
//   .rd_rst_busy(),      // output wire rd_rst_busy
  .s_aclk(mac_rx_clk),                // input wire s_aclk
  .s_aresetn(rst_rx_n),       // release synchronous to FIFO source clock
  .s_axis_tvalid(mac_rx_tvalid),  // input wire s_axis_tvalid
  .s_axis_tready(mac_rx_tready),  // output wire s_axis_tready
  .s_axis_tdata (mac_rx_tdata),    // input wire [63 : 0] s_axis_tdata
  .s_axis_tkeep (mac_rx_tkeep),     // input wire [7 : 0] s_axis_tkeep
  .s_axis_tlast (mac_rx_tlast),    // input wire s_axis_tlast
  .m_axis_tvalid(mac_tx_tvalid),  // output wire m_axis_tvalid
  .m_axis_tready(mac_tx_tready),  // input wire m_axis_tready
  .m_axis_tdata (mac_tx_tdata),    // output wire [63 : 0] m_axis_tdata
  .m_axis_tkeep (mac_tx_tkeep),    // output wire [7 : 0] m_axis_tkeep
  .m_axis_tlast (mac_tx_tlast),        // output wire m_axis_tlast
  .axis_data_count(MAC_Buffer_count)  // output wire [14 : 0] axis_data_count
);



//////////////////////////////////////////////////////
//                    Mac_FlowControl               //
//////////////////////////////////////////////////////
reg MAC_Buffer_count_v='d0;
always@(posedge mac_rx_clk, negedge rst_rx_n)begin
    if(!rst_rx_n)
        MAC_Buffer_count_v <= 'd0;
    else
        MAC_Buffer_count_v <= ~MAC_Buffer_count_v;
end
FIFO_IndepClk_FlowC FIFO_IndepClk_FlowC (
  .rst(!rst_rx_n),               // vendor IP synchronizes both clock domains
  .wr_clk(mac_rx_clk),            // input wire wr_clk
  .rd_clk(mac_tx_clk),            // input wire rd_clk
  .din(MAC_Buffer_count),                  // input wire [14 : 0] din
  .wr_en(MAC_Buffer_count_v),              // input wire wr_en
  .rd_en(1'd1),              // input wire rd_en
  .dout(MAC_Buffer_count_tx),                // output wire [14 : 0] dout
  .full(),                // output wire full
  .empty(),              // output wire empty
  .wr_rst_busy(),  // output wire wr_rst_busy
  .rd_rst_busy()  // output wire rd_rst_busy
);

localparam  IDLE  = 1'b0;
localparam  PAUSE = 1'b1;
reg state = IDLE;
always@(posedge mac_tx_clk)begin
    reg_FIFO_ASSERT <= VIO_FIFO_ASSERT;
    reg_FIFO_NEGATE <= VIO_FIFO_NEGATE;
end
always@(posedge mac_tx_clk, negedge rst_tx_n)begin
   if(!rst_tx_n)
        state <= IDLE;
   else
       case(state)
           IDLE:    state <= (MAC_Buffer_count_tx >= reg_FIFO_ASSERT)?PAUSE:state;
           PAUSE:   state <= (MAC_Buffer_count_tx <= reg_FIFO_NEGATE)?IDLE:state;
           default: state <= IDLE;
       endcase 
end
assign MAC_Pause = state;

//////////////////////////////////////////////////////
//                     Mac_Address                  //
//////////////////////////////////////////////////////
reg [47:0]  MAC_Source_Address_Windows='d0;
reg [47:0]  MAC_Source_Address        ='d0;
reg         mac_rx_tvalid_dly='d0;
wire        mac_rx_begin;
reg         mac_rx_begin_dly='d0;
reg         MAC_Source_Address_Windows_v='d0;
reg         MAC_Source_Address_v='d0;
assign mac_rx_begin = mac_rx_tvalid & (~mac_rx_tvalid_dly);
always@(posedge mac_rx_clk)begin
    mac_rx_tvalid_dly <= mac_rx_tvalid;
    mac_rx_begin_dly <= mac_rx_begin;
    
    MAC_Source_Address_Windows_v <= mac_rx_begin_dly;
    MAC_Source_Address_v <= MAC_Source_Address_Windows_v;
end

always@(posedge mac_rx_clk)begin
    MAC_Source_Address_Windows[  0+:2*8] <=     mac_rx_begin?mac_rx_tdata[64-1-:2*8]:MAC_Source_Address_Windows[  0+:2*8];
    MAC_Source_Address_Windows[2*8+:4*8] <= mac_rx_begin_dly?mac_rx_tdata[   0+:4*8]:MAC_Source_Address_Windows[2*8+:4*8];
end

genvar i;
generate
    for(i=0;i<6;i=i+1)begin
        always@(posedge mac_rx_clk)
            MAC_Source_Address[i*8+:8] <= MAC_Source_Address_Windows[(5-i)*8+:8];
    end
endgenerate
FIFO_IndepClk_MACaddr FIFO_IndepClk_MACaddr (
  .rst(!rst_rx_n),               // vendor IP synchronizes both clock domains
  .wr_clk(mac_rx_clk),            // input wire wr_clk
  .rd_clk(mac_tx_clk),            // input wire rd_clk
  .din(MAC_Source_Address),                  // input wire [47 : 0] din
  .wr_en(MAC_Source_Address_v),              // input wire wr_en
  .rd_en(1'd1),              // input wire rd_en
  .dout(MAC_SOURCE_ADDR),                // output wire [47 : 0] dout
  .full(),                // output wire full
  .empty(),              // output wire empty
  .wr_rst_busy(),  // output wire wr_rst_busy
  .rd_rst_busy()  // output wire rd_rst_busy
);

endmodule
