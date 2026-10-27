`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/05/14 21:22:10
// Design Name: 
// Module Name: fmc_THz_test_top
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


module fmc_THz_test_top (

    //TX
    //10G eth clk
    // input                     gty_refclk0p_i  ,
    // input                     gty_refclk0n_i  ,   
    output wire [12*16-1 : 0] DAC_IQ,

    //RX
    input wire clk1,  //409.6
    input wire clk2,  //204.8
    input wire locked,
    input wire fclk,
    input wire tx_run,
    input wire dac_ready,
    input wire feedback_packet_v,
    input wire [23:0] feedback_packet,
    input wire [31:0] feedback_status,
    input wire [31:0] feedback_received_count,
    output wire [31:0] dac_metadata,
    input wire [12*16-1 : 0] DAC_IQ_RX,
    //10GE
    input wire gt_refclk_p,
    input wire gt_refclk_n,
    input wire gt_rxp_in_0,
    input wire gt_rxn_in_0,
    output wire gt_txp_out_0,
    output wire gt_txn_out_0,
    input wire gt_rxp_in_1,
    input wire gt_rxn_in_1,
    output wire gt_txp_out_1,
    output wire gt_txn_out_1
);

    wire vio_rst_n;
    wire phy_reset_n;
    wire phy_slow_rst_n;
    wire eth_core_rst_n;

    //////////////////////////////////////////////////////
    //                         MAC                      //
    //////////////////////////////////////////////////////
    wire [64-1:0] mac_out;
    wire mac_out_v;

    wire [14:0] VIO_FIFO_ASSERT_0;  //VIO_FIFO_ASSERT_1,
    wire [14:0] VIO_FIFO_NEGATE_0;  //VIO_FIFO_NEGATE_1,
    wire [14:0] MAC_Buffer_count_tx_0;
    wire [47:0] MAC_SOURCE_ADDR_0;
    wire MAC_Pause_0;
    wire Error_MACfifo_0;

    wire video_mac_rx_0_clk;
    wire star_mac_rx_1_clk;
    wire video_mac_tx_0_clk;
    wire star_mac_tx_1_clk;
    wire [63:0] video_mac_rx_0_tdata;
    wire [63:0] star_mac_rx_1_tdata;
    wire [7:0] video_mac_rx_0_tkeep;
    wire [7:0] star_mac_rx_1_tkeep;
    wire video_mac_rx_0_tlast;
    wire star_mac_rx_1_tlast;
    wire video_mac_rx_0_tvalid;
    wire star_mac_rx_1_tvalid;

    wire video_mac_rx_0_tready;
    wire star_mac_rx_1_tready;
    wire [63:0] video_mac_tx_0_tdata;
    wire [63:0] star_mac_tx_1_tdata;
    wire [7:0] video_mac_tx_0_tkeep;
    wire [7:0] star_mac_tx_1_tkeep;
    wire video_mac_tx_0_tlast;
    wire star_mac_tx_1_tlast;
    wire video_mac_tx_0_tvalid;
    wire star_mac_tx_1_tvalid;
    wire video_mac_tx_0_tready;
    wire star_mac_tx_1_tready;

    // This board consumes Ethernet payload for RF transmission. Its unused
    // Ethernet payload return inputs must be deterministic idle AXI streams.
    // MAC pause control still uses its original independent sideband signals.
    assign video_mac_tx_0_tdata = 64'd0;
    assign video_mac_tx_0_tkeep = 8'd0;
    assign video_mac_tx_0_tlast = 1'b0;
    assign video_mac_tx_0_tvalid = 1'b0;
    assign star_mac_tx_1_tdata = 64'd0;
    assign star_mac_tx_1_tkeep = 8'd0;
    assign star_mac_tx_1_tlast = 1'b0;
    assign star_mac_tx_1_tvalid = 1'b0;


    wire [3:0] vio_phy_ploy;
    wire [1:0] vio_phy_mode;
    wire [3:0] phy_ploy;
    wire [1:0] phy_mod;
    wire [3:0] mac_ploy;
    wire [3:0] stream_ploy;
    wire [1:0] mac_mod;
    wire [1:0] stream_mod;
    wire mode_loaded;
    wire auto_enable;
    wire [3:0] requested_ploy;
    wire [1:0] requested_mod;
    wire frame_commit;
    wire [3:0] source_ploy;
    wire [1:0] source_mod;
    wire rate_v;
    wire rate_guard;
    wire [3:0] rate_ploy;
    wire [1:0] rate_mod;
    wire dac_sof;
    wire dac_eof;
    wire dac_guard;
    wire [3:0] dac_ploy;
    wire [1:0] dac_mod;
    wire tx_frame_sof;
    wire tx_frame_done;
    wire [3:0] tx_frame_ploy;
    wire [1:0] tx_frame_mod;
    wire [3:0] tx_done_ploy;
    wire [1:0] tx_done_mod;
    wire link_started;
    wire stream_error;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [1:0] stream_error_sync;
    wire [3:0] applied_mode;
    wire [3:0] pending_mode;
    wire pending;
    wire protect_active;
    wire [3:0] protect_count;
    wire feedback_timeout;
    wire timeout_pulse;
    wire [15:0] watchdog;
    wire packet_accept;
    wire vote_accept;
    wire [2:0] reject_reason;
    wire decision_pulse;
    wire adopt_pulse;
    wire [14:0] vote_up;
    wire [14:0] vote_down;
    wire [31:0] candidate_history;
    wire [3:0] candidate_count;
    wire recovery_pending;
    wire seq_valid;
    wire [5:0] last_seq;
    wire [255:0] control_observe;
    reg [23:0] feedback_packet_d;
    reg feedback_packet_v_d;
    reg frame_commit_d;
    reg tx_frame_sof_d;
    reg tx_frame_done_d;
    (* KEEP="TRUE", MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg [255:0] control_capture;

    // Manual P/M VIO is unchanged. The separate auto VIO defaults to zero.
    vio_tx_auto u_vio_tx_auto (.clk(clk2), .probe_out0(auto_enable));
    tx_feedback_controller u_tx_feedback_controller (
        .clk(clk2), .rst_n(phy_slow_rst_n),
        .auto_enable(auto_enable), .link_started(link_started),
        .manual_ploy(phy_ploy), .manual_mod(phy_mod),
        .frame_commit(frame_commit),
        .packet_v(feedback_packet_v), .packet(feedback_packet),
        .tx_frame_done(tx_frame_done),
        .tx_frame_ploy(tx_done_ploy), .tx_frame_mod(tx_done_mod),
        .requested_ploy(requested_ploy), .requested_mod(requested_mod),
        .applied_mode(applied_mode), .pending_mode(pending_mode), .pending(pending),
        .protect_active(protect_active), .protect_count(protect_count),
        .timeout(feedback_timeout), .timeout_pulse(timeout_pulse), .watchdog(watchdog),
        .packet_accept(packet_accept), .vote_accept(vote_accept), .reject_reason(reject_reason),
        .decision_pulse(decision_pulse), .adopt_pulse(adopt_pulse),
        .vote_up(vote_up), .vote_down(vote_down),
        .candidate_history(candidate_history), .candidate_count(candidate_count),
        .recovery_pending(recovery_pending), .seq_valid(seq_valid), .last_seq(last_seq)
    );
    tx_air_frame_monitor u_tx_air_frame_monitor (
        .clk_fast(clk1), .clk_slow(clk2), .rst_n(phy_reset_n),
        .dac_run(tx_run), .dac_ready(dac_ready), .rate_v(rate_v), .rate_guard(rate_guard),
        .rate_ploy(rate_ploy), .rate_mod(rate_mod),
        .dac_sof(dac_sof), .dac_eof(dac_eof), .dac_guard(dac_guard),
        .dac_ploy(dac_ploy), .dac_mod(dac_mod),
        .frame_sof(tx_frame_sof), .frame_done(tx_frame_done),
        .frame_ploy(tx_frame_ploy), .frame_mod(tx_frame_mod),
        .done_ploy(tx_done_ploy), .done_mod(tx_done_mod),
        .link_started(link_started), .stream_error(stream_error)
    );
    always @(posedge clk2 or negedge phy_slow_rst_n) begin
        if (!phy_slow_rst_n) stream_error_sync <= 2'd0;
        else stream_error_sync <= {stream_error_sync[0],stream_error};
    end
    assign dac_metadata = {20'd0,dac_ready,stream_error,tx_run,dac_guard,dac_eof,dac_sof,dac_mod,dac_ploy};
    // Decode responses are registered in the controller. Delay their packet
    // context by the same edge, including back-to-back packet-valid cycles.
    always @(posedge clk2) begin
        if (!phy_slow_rst_n) begin
            feedback_packet_d <= 24'd0;
            feedback_packet_v_d <= 1'b0;
            frame_commit_d <= 1'b0;
            tx_frame_sof_d <= 1'b0;
            tx_frame_done_d <= 1'b0;
        end else begin
            feedback_packet_d <= feedback_packet;
            feedback_packet_v_d <= feedback_packet_v;
            frame_commit_d <= frame_commit;
            tx_frame_sof_d <= tx_frame_sof;
            tx_frame_done_d <= tx_frame_done;
        end
    end
    assign control_observe[23:0] = feedback_packet_d;
    assign control_observe[24] = feedback_packet_v_d;
    assign control_observe[25] = packet_accept;
    assign control_observe[26] = vote_accept;
    assign control_observe[29:27] = reject_reason;
    assign control_observe[30] = auto_enable;
    assign control_observe[31] = link_started;
    assign control_observe[35:32] = applied_mode;
    assign control_observe[39:36] = pending_mode;
    assign control_observe[40] = pending;
    assign control_observe[41] = decision_pulse;
    assign control_observe[42] = adopt_pulse;
    assign control_observe[43] = protect_active;
    assign control_observe[47:44] = protect_count;
    assign control_observe[63:48] = watchdog;
    assign control_observe[64] = feedback_timeout;
    assign control_observe[65] = timeout_pulse;
    assign control_observe[66] = recovery_pending;
    assign control_observe[67] = seq_valid;
    assign control_observe[73:68] = last_seq;
    assign control_observe[88:74] = vote_up;
    assign control_observe[103:89] = vote_down;
    assign control_observe[135:104] = candidate_history;
    assign control_observe[139:136] = candidate_count;
    assign control_observe[143:140] = phy_ploy;
    assign control_observe[145:144] = phy_mod;
    assign control_observe[149:146] = requested_ploy;
    assign control_observe[151:150] = requested_mod;
    assign control_observe[152] = frame_commit_d;
    assign control_observe[156:153] = source_ploy;
    assign control_observe[158:157] = source_mod;
    assign control_observe[159] = tx_frame_sof_d;
    assign control_observe[160] = tx_frame_done_d;
    assign control_observe[164:161] = tx_frame_ploy;
    assign control_observe[166:165] = tx_frame_mod;
    assign control_observe[167] = stream_error_sync[1];
    assign control_observe[199:168] = feedback_status;
    assign control_observe[231:200] = feedback_received_count;
    assign control_observe[235:232] = tx_done_ploy;
    assign control_observe[237:236] = tx_done_mod;
    assign control_observe[255:238] = 18'd0;
    always @(posedge clk2) begin
        if (!phy_slow_rst_n) control_capture <= 256'd0;
        else control_capture <= control_observe;
    end
    ila_tx_feedback_control u_ila_tx_feedback_control (.clk(clk2), .probe0(control_capture));

    // Manual reset and next-frame mode request.
    vio_tx_control u_vio_tx_control (
        .clk       (clk2),
        .probe_out0(vio_rst_n),
        .probe_out1(vio_phy_ploy),
        .probe_out2(vio_phy_mode)
    );
    PHY_Mode_Control u_PHY_Mode_Control (
        .clk        (clk2),
        .locked     (locked),
        .vio_rst_n  (vio_rst_n),
        .vio_ploy   (vio_phy_ploy),
        .vio_mod    (vio_phy_mode),
        .phy_ploy   (phy_ploy),
        .phy_mod    (phy_mod),
        .phy_reset_n(phy_reset_n),
        .mode_loaded(mode_loaded)
    );
    Reset_Sync u_phy_slow_reset (
        .clk   (clk2),
        .arst_n(phy_reset_n),
        .rst_n (phy_slow_rst_n)
    );
    Reset_Sync u_eth_core_reset (
        .clk   (fclk),
        .arst_n(locked),
        .rst_n (eth_core_rst_n)
    );

    ETH_TOP u_ETH_TOP (
        .phy_ploy      (requested_ploy),
        .phy_mod       (requested_mod),
        .frame_commit  (frame_commit),
        .frame_ploy    (source_ploy),
        .frame_mod     (source_mod),
        .fpga_sysclk_in(fclk),
        // .ten_ge_refclk_1_p(gty_refclk0p_i   ),       
        // .ten_ge_refclk_1_n(gty_refclk0n_i   ),       
        .clk_phy       (clk2),
        .rst_n_phy     (phy_slow_rst_n),
        // .sys_reset        (!locked      ),

        .mac_rx_0_clk         (video_mac_rx_0_clk),
        .mac_tx_0_clk         (video_mac_tx_0_clk),
        .mac_rx_0_tvalid      (video_mac_rx_0_tvalid),
        .mac_rx_0_tdata       (video_mac_rx_0_tdata),
        .mac_rx_0_tlast       (video_mac_rx_0_tlast),
        .mac_rx_0_tkeep       (video_mac_rx_0_tkeep),
        .VIO_FIFO_ASSERT_0    (VIO_FIFO_ASSERT_0),
        .VIO_FIFO_NEGATE_0    (VIO_FIFO_NEGATE_0),
        .MAC_Buffer_count_tx_0(MAC_Buffer_count_tx_0),
        .MAC_SOURCE_ADDR_0    (MAC_SOURCE_ADDR_0),
        .MAC_Pause_0          (MAC_Pause_0),
        .Error_MACfifo_0      (Error_MACfifo_0),
        // .gt_rxp_in_0      (gt_rxp_in_0      ),
        // .gt_rxn_in_0      (gt_rxn_in_0      ),
        // .gt_txp_out_0     (gt_txp_out_0     ),
        // .gt_txn_out_0     (gt_txn_out_0     ),
        .phy_out              (mac_out),
        .phy_out_v            (mac_out_v),
        .phy_out_ploy         (mac_ploy),
        .phy_out_mod          (mac_mod)

    );



    wire [32-1:0] phy_din;
    wire phy_din_v;

    phy_64toW u_phy_64toW (
        .clk      (clk2),
        .rst_n    (phy_slow_rst_n),
        .phy_ploy (mac_ploy),
        .phy_mod  (mac_mod),
        .din      (mac_out),
        .din_v    (mac_out_v),
        .dout     (phy_din),
        .dout_v   (phy_din_v),
        .dout_ploy(stream_ploy),
        .dout_mod (stream_mod)
    );

    // wire [12*16-1 :0]     DAC_IQ  ;
    // assign     DAC_IQ  = 'd0;

    PHY_TOP u_PHY_TOP_Tx (
        .clk_200M (clk2),
        .clk_400M (clk1),
        .rst_n    (phy_reset_n),
        .phy_ploy (stream_ploy),
        .phy_mod  (stream_mod),
        .phy_din  (phy_din),
        .phy_din_v(phy_din_v),
        .DAC_IQ   (DAC_IQ),
        .tx_rate_v(rate_v),
        .tx_rate_guard(rate_guard),
        .tx_rate_ploy(rate_ploy),
        .tx_rate_mod(rate_mod)
    );


    ethernet_tx_rx u_ethernet_tx_rx (
        //GTY_0
        .gt_rxp_in_0          (gt_rxp_in_0),            //input  wire         
        .gt_rxn_in_0          (gt_rxn_in_0),            //input  wire         
        .gt_txp_out_0         (gt_txp_out_0),           //output wire         
        .gt_txn_out_0         (gt_txn_out_0),           //output wire         
        //GTY_1 
        .gt_rxp_in_1          (gt_rxp_in_1),            //input  wire         
        .gt_rxn_in_1          (gt_rxn_in_1),            //input  wire         
        .gt_txp_out_1         (gt_txp_out_1),           //output wire         
        .gt_txn_out_1         (gt_txn_out_1),           //output wire         
        //CLK_SYSRST_REF    
        .sys_reset            (!eth_core_rst_n),        // synchronized to dclk
        .gt_refclk_p          (gt_refclk_p),            //input  wire  //???gty_refclk0p_i       
        .gt_refclk_n          (gt_refclk_n),            //input  wire         
        .dclk                 (fclk),                   //input  wire         
        .tx_clk_out_0         (video_mac_tx_0_clk),     //output wire         
        .tx_clk_out_1         (star_mac_tx_1_clk),      //output wire         
        .rx_clk_out_0         (video_mac_rx_0_clk),     //output wire         
        .rx_clk_out_1         (star_mac_rx_1_clk),      //output wire         
        //AXI_4 RX_0    
        .rx_axis_tvalid_0     (video_mac_rx_0_tvalid),  //output wire         
        .rx_axis_tdata_0      (video_mac_rx_0_tdata),   //output wire [63:0]  
        .rx_axis_tlast_0      (video_mac_rx_0_tlast),   //output wire         
        .rx_axis_tkeep_0      (video_mac_rx_0_tkeep),   //output wire [7:0]   
        //AXI_4 TX_0    
        .tx_axis_tready_0     (video_mac_tx_0_tready),  //output wire         
        .tx_axis_tvalid_0     (video_mac_tx_0_tvalid),  //input  wire         
        .tx_axis_tdata_0      (video_mac_tx_0_tdata),   //input  wire [63:0]  
        .tx_axis_tlast_0      (video_mac_tx_0_tlast),   //input  wire         
        .tx_axis_tkeep_0      (video_mac_tx_0_tkeep),   //input  wire [7:0]   
        //AXI_4 RX_1    
        .rx_axis_tvalid_1     (star_mac_rx_1_tvalid),   //output wire         
        .rx_axis_tdata_1      (star_mac_rx_1_tdata),    //output wire [63:0]  
        .rx_axis_tlast_1      (star_mac_rx_1_tlast),    //output wire         
        .rx_axis_tkeep_1      (star_mac_rx_1_tkeep),    //output wire [7:0]   
        //AXI_4 TX_1    
        .tx_axis_tready_1     (star_mac_tx_1_tready),   //output wire         
        .tx_axis_tvalid_1     (star_mac_tx_1_tvalid),   //input  wire         
        .tx_axis_tdata_1      (star_mac_tx_1_tdata),    //input  wire [63:0]  
        .tx_axis_tlast_1      (star_mac_tx_1_tlast),    //input  wire         
        .tx_axis_tkeep_1      (star_mac_tx_1_tkeep),    //input  wire [7:0]   
        .VIO_FIFO_ASSERT_0    (VIO_FIFO_ASSERT_0),      //VIO_FIFO_ASSERT_1,
        .VIO_FIFO_NEGATE_0    (VIO_FIFO_NEGATE_0),      //VIO_FIFO_NEGATE_1,
        .MAC_Buffer_count_tx_0(MAC_Buffer_count_tx_0),  //MAC_Buffer_count_tx_1,
        .MAC_SOURCE_ADDR_0    (MAC_SOURCE_ADDR_0),      //MAC_SOURCE_ADDR_1,
        .MAC_Pause_0          (MAC_Pause_0),            //MAC_Pause_1   ,
        .Error_MACfifo_0      (Error_MACfifo_0)         //Error_MACfifo_1   

    );



endmodule
`default_nettype wire
