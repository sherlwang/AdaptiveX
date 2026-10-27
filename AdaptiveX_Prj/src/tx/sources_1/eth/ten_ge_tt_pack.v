`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2017/06/21 09:27:38
// Design Name: 
// Module Name: ten_ge_tt_pack
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


module ten_ge_tt_pack(
        input   mac_clk,
        input   arst_n,
        
        input   [63:0]  mac_core_rx_tdata,
        input   [7:0]   mac_core_rx_tkeep,
        input           mac_core_rx_tlast,
        input           mac_core_rx_tvalid,
        output          mac_core_rx_tready,
        output          user_fin_tready,
        
        input           tt_rx_tclk,
        output  [63:0]  tt_rx_tdata,
        output          tt_rx_tlast,
        output          tt_rx_tvalid,
        input           tt_rx_tready
    );
    
    wire    [63:0]  mac_fout_tdata;
    wire            mac_rst_n;
    Reset_Sync u_reset_mac(
        .clk                (mac_clk),
        .arst_n             (arst_n),
        .rst_n              (mac_rst_n)
    );
    wire    [7:0]   mac_fout_tkeep;
    wire            mac_fout_tlast;
    wire            mac_fout_tvalid;
    wire            mac_fout_tready;
    
//    wire    [14:0]  tt_rx_fifo_count;
    
    reg     [63:0]  user_fin_tdata;
    reg             user_fin_tlast;
    reg             user_fin_tvalid;
//    wire            user_fin_tready;
    
    parameter   ESCAP_CHAR  = 64'ha5a5a5a5_a5a5a5a5;
    parameter   START_CHAR  = 64'h33333333_33333333;
    parameter   STOP_CHAR   = 56'hf0f0f0f0_f0f0f0;
    
    parameter   P_IDLE          = 4'd0;
    parameter   P_START_ESCAP   = 4'd1;
    parameter   P_START_START   = 4'd2;
    parameter   P_DATA          = 4'd3;
    parameter   P_COL           = 4'd4;
    parameter   P_STOP_ESCAP    = 4'd5;
    parameter   P_STOP_STOP     = 4'd6;
    parameter   P_LAST          = 4'd7;
    (*KEEP = "TRUE"*) reg   [3:0]   state;
    
    xge_tt_rx_mac_fifo u_xge_tt_rx_mac_fifo (
    //   .wr_rst_busy(),          // output wire wr_rst_busy
    //   .rd_rst_busy(),          // output wire rd_rst_busy
      .s_aclk(mac_clk),                    // input wire s_aclk
      .s_aresetn(mac_rst_n),           // local source-domain reset
      .s_axis_tvalid(mac_core_rx_tvalid),      // input wire s_axis_tvalid
      .s_axis_tready(mac_core_rx_tready),      // output wire s_axis_tready
      .s_axis_tdata(mac_core_rx_tdata),        // input wire [63 : 0] s_axis_tdata
      .s_axis_tkeep(mac_core_rx_tkeep),        // input wire [7 : 0] s_axis_tkeep
      .s_axis_tlast(mac_core_rx_tlast),        // input wire s_axis_tlast
      .m_axis_tvalid(mac_fout_tvalid),      // output wire m_axis_tvalid
      .m_axis_tready(mac_fout_tready),      // input wire m_axis_tready
      .m_axis_tdata(mac_fout_tdata),        // output wire [63 : 0] m_axis_tdata
      .m_axis_tkeep(mac_fout_tkeep),        // output wire [7 : 0] m_axis_tkeep
      .m_axis_tlast(mac_fout_tlast),        // output wire m_axis_tlast
      .axis_data_count()  // output wire [14 : 0] axis_data_count
    );
//ILA_MAC ILA_MAC (
//	.clk(mac_clk), // input wire clk
//	.probe0(mac_core_rx_tdata), // input wire [63:0]  probe0  
//	.probe1(mac_core_rx_tkeep), // input wire [7:0]  probe1 
//	.probe2(mac_core_rx_tvalid), // input wire [0:0]  probe2 
//	.probe3(mac_core_rx_tready), // input wire [0:0]  probe3 
//	.probe4(mac_core_rx_tlast), // input wire [0:0]  probe4 
//	.probe5(tt_rx_fifo_count) // input wire [14:0]  probe5
//);
    // FSM controller
    always @ (posedge mac_clk or negedge mac_rst_n)
    begin
        if (!mac_rst_n)
            state <= P_IDLE;
        else
        begin
            if (user_fin_tready)
            begin
                case (state)
                    P_IDLE: begin
                        if (mac_fout_tvalid)
                            state <= P_START_ESCAP;
                        else ;
                    end
                    
                    P_START_ESCAP: state <= P_START_START;
                    
                    P_START_START: state <= P_DATA;
                    
                    P_DATA: begin
                        if (mac_fout_tvalid)
                        begin
                            if (mac_fout_tlast)
                                state <= P_STOP_ESCAP;
                            else if (mac_fout_tdata == ESCAP_CHAR)
                                state <= P_COL;
                            else ;
                        end
                        else ;
                    end
                    
                    P_COL: state <= P_DATA;
                    
                    P_STOP_ESCAP: state <= P_STOP_STOP;
                    
                    P_STOP_STOP: state <= P_LAST;
                    
                    P_LAST: begin
                        if (mac_fout_tvalid & mac_fout_tready & mac_fout_tlast)
                            state <= P_IDLE;
                        else ;
                    end
                    
                    default: state <= P_IDLE;
                endcase
            end
            else ;
        end
    end
    
    // read data from mac_fifo
    assign  mac_fout_tready = (user_fin_tready & ((state == P_LAST) | ((state == P_DATA) & !mac_fout_tlast))) ? 1'b1 : 1'b0;
    
    // pack mac frame
    always @ (posedge mac_clk or negedge mac_rst_n)
    begin
        if (!mac_rst_n)
        begin
            user_fin_tdata  <= 64'd0;
            user_fin_tlast  <= 1'b0;
            user_fin_tvalid <= 1'b0;
        end
        else
        begin
            if (user_fin_tready)
            begin
                if (state == P_START_ESCAP)
                begin
                    user_fin_tdata  <= ESCAP_CHAR;
                    user_fin_tlast  <= 1'b0;
                    user_fin_tvalid <= 1'b1;
                end
                else if (state == P_START_START)
                begin
                    user_fin_tdata  <= START_CHAR;
                    user_fin_tlast  <= 1'b0;
                    user_fin_tvalid <= 1'b1;
                end
                else if (state == P_DATA)
                begin
                    user_fin_tdata  <= mac_fout_tdata;
                    user_fin_tlast  <= 1'b0;
                    user_fin_tvalid <= mac_fout_tvalid & mac_fout_tready;
                end
                else if (state == P_COL)
                begin
                    user_fin_tdata  <= ESCAP_CHAR;
                    user_fin_tlast  <= 1'b0;
                    user_fin_tvalid <= 1'b1;
                end
                else if (state == P_STOP_ESCAP)
                begin
                    user_fin_tdata  <= ESCAP_CHAR;
                    user_fin_tlast  <= 1'b0;
                    user_fin_tvalid <= 1'b1;
                end
                else if (state == P_STOP_STOP)
                begin
                    user_fin_tdata  <= {STOP_CHAR,mac_fout_tkeep};
                    user_fin_tlast  <= 1'b0;
                    user_fin_tvalid <= 1'b1;
                end
                else if (state == P_LAST)
                begin
                    user_fin_tdata  <= mac_fout_tdata;
                    user_fin_tlast  <= 1'b1;
                    user_fin_tvalid <= mac_fout_tvalid & mac_fout_tready;
                end
                else
                    user_fin_tvalid <= 1'b0;
            end
            else ;
        end
    end
    
    xge_tt_rx_user_fifo u_xge_tt_rx_user_fifo (
    //   .wr_rst_busy(),          // output wire wr_rst_busy
    //   .rd_rst_busy(),          // output wire rd_rst_busy
      .m_aclk(tt_rx_tclk),                // input wire m_aclk
      .s_aclk(mac_clk),                // input wire s_aclk
      .s_aresetn(mac_rst_n),       // async-clock FIFO contains destination reset sync
      .s_axis_tvalid(user_fin_tvalid),  // input wire s_axis_tvalid
      .s_axis_tready(user_fin_tready),  // output wire s_axis_tready
      .s_axis_tdata(user_fin_tdata),    // input wire [63 : 0] s_axis_tdata
      .s_axis_tlast(user_fin_tlast),    // input wire s_axis_tlast
      .m_axis_tvalid(tt_rx_tvalid),  // output wire m_axis_tvalid
      .m_axis_tready(tt_rx_tready),  // input wire m_axis_tready
      .m_axis_tdata(tt_rx_tdata),    // output wire [63 : 0] m_axis_tdata
      .m_axis_tlast(tt_rx_tlast)    // output wire m_axis_tlast
    );
    
endmodule
