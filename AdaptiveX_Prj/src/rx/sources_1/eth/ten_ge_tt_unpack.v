`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2017/06/21 18:27:33
// Design Name: 
// Module Name: ten_ge_tt_unpack
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


module ten_ge_tt_unpack(
        input   mac_clk,
        input   arst_n,
        input   mac_rst_n,
        
        output  [63:0]  mac_core_tx_tdata,
        output  [7:0]   mac_core_tx_tkeep,
        output          mac_core_tx_tlast,
        output          mac_core_tx_tvalid,
        input           mac_core_tx_tready,
        
        input           tt_tx_tclk,
        input   [63:0]  tt_tx_tdata,
        input           tt_tx_tvalid,
        output          tt_tx_tready
    );
    
(* mark_debug="true" *)    wire    [63:0]  user_fout_tdata;
(* mark_debug="true" *)    wire            user_fout_tvalid;
(* mark_debug="true" *)    wire            user_fout_tready;
(* mark_debug="true" *)    wire    [12:0]  user_fout_wr_cnt;
(* mark_debug="true" *)    wire    [12:0]  user_fout_rd_cnt;
//    wire [11:0]     mac_fifo_cnt;
    
    parameter   ESCAP_CHAR  = 64'ha5a5a5a5_a5a5a5a5;
    parameter   START_CHAR  = 64'h33333333_33333333;
    parameter   STOP_CHAR   = 56'hf0f0f0f0_f0f0f0;
    
    parameter   P_IDLE          = 8'b0000_0001;
    parameter   P_START_ESCAP   = 8'b0000_0010;
    parameter   P_START_START   = 8'b0000_0100;
    parameter   P_DATA          = 8'b0000_1000;
    parameter   P_STOP_STOP     = 8'b0001_0000;
    parameter   P_LAST          = 8'b0010_0000;
//    parameter   P_RST_RST       = 8'b0100_0000;
//    parameter   P_RST           = 8'b1000_0000;
    (* mark_debug="true" *) reg   [7:0]   state;
    
(* mark_debug="true" *)    reg     [63:0]  mac_fin_tdata;
(* mark_debug="true" *)    reg     [7:0]   mac_fin_tkeep;
(* mark_debug="true" *)    reg             mac_fin_tlast;
(* mark_debug="true" *)    reg             mac_fin_tvalid;
(* mark_debug="true" *)   wire            mac_fin_tready;
    
    reg     [7:0]   last_tkeep_latch;
//    reg [3:0] timer='d0;
//    reg fifo_rstn = 1'b1;
    
    xge_tt_tx_user_fifo u_xge_tt_tx_user_fifo (
      .wr_rst_busy(),          // output wire wr_rst_busy
      .rd_rst_busy(),          // output wire rd_rst_busy
      .m_aclk(mac_clk),                          // input wire m_aclk
      .s_aclk(tt_tx_tclk),                          // input wire s_aclk
      .s_aresetn(arst_n),                    // input wire s_aresetn
      .s_axis_tvalid(tt_tx_tvalid),            // input wire s_axis_tvalid
      .s_axis_tready(tt_tx_tready),            // output wire s_axis_tready
      .s_axis_tdata(tt_tx_tdata),              // input wire [63 : 0] s_axis_tdata
      .m_axis_tvalid(user_fout_tvalid),            // output wire m_axis_tvalid
      .m_axis_tready(user_fout_tready),            // input wire m_axis_tready
      .m_axis_tdata (user_fout_tdata ),              // output wire [63 : 0] m_axis_tdata
      .axis_wr_data_count(user_fout_wr_cnt),  // output wire [12 : 0] axis_wr_data_count
      .axis_rd_data_count(user_fout_rd_cnt)  // output wire [12 : 0] axis_rd_data_count
    );
    
    // FSM controller
    always @ (posedge mac_clk or negedge mac_rst_n)
    begin
        if (!mac_rst_n)
            state <= P_IDLE;
        else
        begin
//            if (mac_fin_tready)
            begin
                case (state)
                    P_IDLE: begin
                        if (mac_fin_tready & user_fout_tvalid)
                            state <= P_START_ESCAP;
                        else ;
                    end
                    
                    P_START_ESCAP: begin
                        if (user_fout_tvalid & user_fout_tready & (user_fout_tdata == ESCAP_CHAR))
                            state <= P_START_START;
                        else ;
                    end
                    
                    P_START_START: begin
                        if (user_fout_tvalid & user_fout_tready)
                        begin
                            if (user_fout_tdata == START_CHAR)
                                state <= P_DATA;
                            else
                                state <= P_START_ESCAP;
                        end
                        else ;
                    end
                    
                    P_DATA: begin
                        if (user_fout_tvalid & user_fout_tready & (user_fout_tdata == ESCAP_CHAR))
                            state <= P_STOP_STOP;
                        else ;
                    end
                    
                    P_STOP_STOP: begin
                        if (user_fout_tvalid & user_fout_tready)
                        begin
                            if (user_fout_tdata[63:8] == STOP_CHAR)
                                state <= P_LAST;
                            else
                                state <= P_DATA;
                        end
                        else ;
                    end
                    
                    P_LAST: begin
                        if (user_fout_tvalid & user_fout_tready)
                            state <= P_IDLE;
                        else ;
                    end
                    
//                    P_RST_RST : begin
//                        if (mac_core_tx_tlast)
//                            state <= P_RST;
//                        else ;
                        
//                    end
                    
//                    P_RST : begin
//                        if (timer == 'd11)
//                            state <= P_IDLE;
//                        else ;
                        
//                    end
                    
                    default: state <= P_IDLE;
                endcase
            end
//            else ;
        end
    end
    
//    always@(posedge mac_clk)
//        timer <= (state[7])?timer+'d1:'d0;
//    always@(posedge mac_clk)
//        fifo_rstn <= !((state[7]) & timer <= 'd1);
    
    // latch last tkeep
    always @ (posedge mac_clk or negedge mac_rst_n)
    begin
        if (!mac_rst_n)
            last_tkeep_latch <= 8'd0;
        else
        begin
            if ((state[4]) & user_fout_tvalid & user_fout_tready &
                (user_fout_tdata[63:8] == STOP_CHAR))
                last_tkeep_latch <= user_fout_tdata[7:0];
            else ;
        end
    end
    
    // read data from user fifo
//    assign  user_fout_tready = ((state != P_IDLE) & mac_fin_tready) ? 1'b1 : 1'b0;
//    assign  user_fout_tready = (~(|({state[7],state[6],state[0]})) & mac_fin_tready) ? 1'b1 : 1'b0;
    assign  user_fout_tready = (~(state[0]) & mac_fin_tready) ? 1'b1 : 1'b0;
    
    // write data to mac fifo
    always @ (posedge mac_clk or negedge mac_rst_n)
    begin
        if (!mac_rst_n)
        begin
            mac_fin_tdata  <= 64'd0;
            mac_fin_tkeep  <= 8'd0;
            mac_fin_tlast  <= 1'b0;
            mac_fin_tvalid <= 1'b0;
        end
        else if (mac_fin_tready)
        begin
            if (state[3])
            begin
                if (user_fout_tdata != ESCAP_CHAR)
                begin
                    mac_fin_tdata  <= user_fout_tdata;
                    mac_fin_tkeep  <= 8'hFF;
                    mac_fin_tlast  <= 1'b0;
                    mac_fin_tvalid <= user_fout_tvalid;
                end
                else
                    mac_fin_tvalid <= 1'b0;
            end
            else if (state[4])
            begin
                if (user_fout_tdata[63:8] != STOP_CHAR)
                begin
                    mac_fin_tdata  <= user_fout_tdata;
                    mac_fin_tkeep  <= 8'hFF;
                    mac_fin_tlast  <= 1'b0;
                    mac_fin_tvalid <= user_fout_tvalid;
                end
                else
                    mac_fin_tvalid <= 1'b0;
            end
            else if (state[5])
            begin
                mac_fin_tdata  <= user_fout_tdata;
                mac_fin_tkeep  <= last_tkeep_latch;
                mac_fin_tlast  <= 1'b1;
                mac_fin_tvalid <= user_fout_tvalid;
            end
            else
                mac_fin_tvalid <= 1'b0;
        end
    end
    
//    xge_tt_tx_mac_fifo u_xge_tt_tx_mac_fifo (
//      .wr_rst_busy(),          // output wire wr_rst_busy
//      .rd_rst_busy(),          // output wire rd_rst_busy
//      .s_aclk(mac_clk),                // input wire s_aclk
//      .s_aresetn(arst_n),          // input wire s_aresetn
//      .s_axis_tvalid(mac_fin_tvalid),  // input wire s_axis_tvalid
//      .s_axis_tready(mac_fin_tready),  // output wire s_axis_tready
//      .s_axis_tdata(mac_fin_tdata),    // input wire [63 : 0] s_axis_tdata
//      .s_axis_tkeep(mac_fin_tkeep),    // input wire [7 : 0] s_axis_tkeep
//      .s_axis_tlast(mac_fin_tlast),    // input wire s_axis_tlast
//      .m_axis_tvalid(mac_core_tx_tvalid),  // output wire m_axis_tvalid
//      .m_axis_tready(mac_core_tx_tready),  // input wire m_axis_tready
//      .m_axis_tdata(mac_core_tx_tdata),    // output wire [63 : 0] m_axis_tdata
//      .m_axis_tkeep(mac_core_tx_tkeep),    // output wire [7 : 0] m_axis_tkeep
//      .m_axis_tlast(mac_core_tx_tlast),   // output wire m_axis_tlast
//      .axis_data_count(mac_fifo_cnt)  // output wire [11 : 0] axis_data_count
//    );
Sync_FIFO Sync_FIFO (
  .s_aclk(mac_clk),                // input wire s_aclk
  .s_aresetn(mac_rst_n),          // input wire s_aresetn
  .s_axis_tvalid(mac_fin_tvalid),  // input wire s_axis_tvalid
  .s_axis_tready(mac_fin_tready),  // output wire s_axis_tready
  .s_axis_tdata (mac_fin_tdata ),    // input wire [63 : 0] s_axis_tdata
  .s_axis_tkeep (mac_fin_tkeep ),    // input wire [7 : 0] s_axis_tkeep
  .s_axis_tlast (mac_fin_tlast ),    // input wire s_axis_tlast
  .m_axis_tvalid(mac_core_tx_tvalid),  // output wire m_axis_tvalid
  .m_axis_tready(mac_core_tx_tready),  // input wire m_axis_tready
  .m_axis_tdata (mac_core_tx_tdata ),    // output wire [63 : 0] m_axis_tdata
  .m_axis_tkeep (mac_core_tx_tkeep ),    // output wire [7 : 0] m_axis_tkeep
  .m_axis_tlast (mac_core_tx_tlast )    // output wire m_axis_tlast
);


//Async_Packet_FIFO Async_Packet_FIFO(
//    .rst_n(arst_n),
    
//    .clk(mac_clk),
//    .wr_en(mac_fin_tvalid),
//    .wr_data(mac_fin_tdata),
//    .wr_keep(mac_fin_tkeep),
//    .wr_last(mac_fin_tlast),
//    .wr_rdy(mac_fin_tready),
    
//    .rd_data(mac_core_tx_tdata),
//    .rd_keep(mac_core_tx_tkeep),
//    .rd_data_v(mac_core_tx_tvalid),
//    .rd_last(mac_core_tx_tlast),
//    .rd_en(mac_core_tx_tready)      
//    );

//ila_tt_intenal ila_tt_intenal (
//	.clk(mac_clk), // input wire clk


//	.probe0(user_fout_tdata),  // input wire [63:0]  probe0  
//	.probe1(user_fout_tvalid), // input wire [0:0]  probe1 
//	.probe2(user_fout_tready), // input wire [0:0]  probe2 
//	.probe3(user_fout_wr_cnt), // input wire [10:0]  probe3 
//	.probe4(user_fout_rd_cnt), // input wire [10:0]  probe4 
//	.probe5(state),            // input wire [3:0]  probe5 
//	.probe6(mac_fin_tvalid),   // input wire [0:0]  probe6 
//	.probe7(mac_fin_tdata),    // input wire [63:0]  probe7 
//	.probe8(mac_fin_tkeep),    // input wire [7:0]  probe8 
//	.probe9(mac_fin_tready),   // input wire [0:0]  probe9 
//	.probe10(mac_fin_tlast),   // input wire [0:0]  probe10 
//	.probe11(mac_core_tx_tdata), // input wire [63:0]  probe11 
//	.probe12(mac_core_tx_tready), // input wire [0:0]  probe12 
//	.probe13(mac_core_tx_tvalid), // input wire [0:0]  probe13 
//	.probe14(mac_core_tx_tkeep), // input wire [7:0]  probe14 
//	.probe15(mac_core_tx_tlast),// input wire [0:0]  probe15
//	.probe16(mac_fifo_cnt)
endmodule
