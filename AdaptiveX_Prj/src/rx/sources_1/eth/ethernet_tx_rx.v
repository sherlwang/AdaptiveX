`timescale 1fs/1fs

(* DowngradeIPIdentifiedWarnings="yes" *)
module ethernet_tx_rx(
    //GTY_0
    input  wire         gt_rxp_in_0     ,
    input  wire         gt_rxn_in_0     ,
    output wire         gt_txp_out_0    ,
    output wire         gt_txn_out_0    ,
    //GTY_1
    input  wire         gt_rxp_in_1     ,
    input  wire         gt_rxn_in_1     ,
    output wire         gt_txp_out_1    ,
    output wire         gt_txn_out_1    ,
    //CLK_SYSRST_REF
    input  wire         sys_reset       ,
    input  wire         gt_refclk_p     ,
    input  wire         gt_refclk_n     ,
    input  wire         dclk            ,
    output wire         tx_clk_out_0    ,
    output wire         tx_clk_out_1    ,
    output wire         rx_clk_out_0    ,
    output wire         rx_clk_out_1    ,

    //AXI_4 RX_0
    output wire         rx_axis_tvalid_0,
    output wire [63:0]  rx_axis_tdata_0 ,
    output wire         rx_axis_tlast_0 ,
    output wire [7:0]   rx_axis_tkeep_0 ,
    //AXI_4 TX_0
    output wire         tx_axis_tready_0,
    input  wire         tx_axis_tvalid_0,
    input  wire [63:0]  tx_axis_tdata_0 ,
    input  wire         tx_axis_tlast_0 ,
    input  wire [7:0]   tx_axis_tkeep_0 ,
    //AXI_4 RX_1
    output wire         rx_axis_tvalid_1,
    output wire [63:0]  rx_axis_tdata_1 ,
    output wire         rx_axis_tlast_1 ,
    output wire [7:0]   rx_axis_tkeep_1 ,
    //AXI_4 TX_1
    output wire         tx_axis_tready_1,
    input  wire         tx_axis_tvalid_1,
    input  wire [63:0]  tx_axis_tdata_1 ,
    input  wire         tx_axis_tlast_1 ,
    input  wire [7:0]   tx_axis_tkeep_1 ,

///////////////////////////////////////////////////

    output   [14:0]   VIO_FIFO_ASSERT_0,     //VIO_FIFO_ASSERT_1,
    output   [14:0]   VIO_FIFO_NEGATE_0,     //VIO_FIFO_NEGATE_1,
    input    [14:0]   MAC_Buffer_count_tx_0, //MAC_Buffer_count_tx_1,
    input    [47:0]   MAC_SOURCE_ADDR_0,     //MAC_SOURCE_ADDR_1,
    input             MAC_Pause_0      ,     //MAC_Pause_1   ,
    input             Error_MACfifo_0     //Error_MACfifo_1   

);



//***********************************  ETH CORE 0   ***********************************//

wire  gt_refclk_out;
wire [2:0] gt_loopback_in_0;
wire rx_core_clk_0;
//// RX_0 Signals
wire rx_reset_0;
wire user_rx_reset_0;
wire rxrecclkout_0;
//// RX_0 User Interface Signals
wire rx_axis_tuser_0;
wire [55:0] rx_preambleout_0;
//// RX_0 Control Signals
wire ctl_rx_test_pattern_0;
wire ctl_rx_test_pattern_enable_0;
wire ctl_rx_data_pattern_select_0;
wire ctl_rx_enable_0;
wire ctl_rx_delete_fcs_0;
wire ctl_rx_ignore_fcs_0;
wire [14:0] ctl_rx_max_packet_len_0;
wire [7:0] ctl_rx_min_packet_len_0;
wire ctl_rx_custom_preamble_enable_0;
wire ctl_rx_check_sfd_0;
wire ctl_rx_check_preamble_0;
wire ctl_rx_process_lfi_0;
wire ctl_rx_force_resync_0;
//// RX_0 Stats Signals
wire stat_rx_block_lock_0;
wire stat_rx_framing_err_valid_0;
wire stat_rx_framing_err_0;
wire stat_rx_hi_ber_0;
wire stat_rx_valid_ctrl_code_0;
wire stat_rx_bad_code_0;
wire [1:0] stat_rx_total_packets_0;
wire stat_rx_total_good_packets_0;
wire [3:0] stat_rx_total_bytes_0;
wire [13:0] stat_rx_total_good_bytes_0;
wire stat_rx_packet_small_0;
wire stat_rx_jabber_0;
wire stat_rx_packet_large_0;
wire stat_rx_oversize_0;
wire stat_rx_undersize_0;
wire stat_rx_toolong_0;
wire stat_rx_fragment_0;
wire stat_rx_packet_64_bytes_0;
wire stat_rx_packet_65_127_bytes_0;
wire stat_rx_packet_128_255_bytes_0;
wire stat_rx_packet_256_511_bytes_0;
wire stat_rx_packet_512_1023_bytes_0;
wire stat_rx_packet_1024_1518_bytes_0;
wire stat_rx_packet_1519_1522_bytes_0;
wire stat_rx_packet_1523_1548_bytes_0;
wire [1:0] stat_rx_bad_fcs_0;
wire stat_rx_packet_bad_fcs_0;
wire [1:0] stat_rx_stomped_fcs_0;
wire stat_rx_packet_1549_2047_bytes_0;
wire stat_rx_packet_2048_4095_bytes_0;
wire stat_rx_packet_4096_8191_bytes_0;
wire stat_rx_packet_8192_9215_bytes_0;
wire stat_rx_unicast_0;
wire stat_rx_multicast_0;
wire stat_rx_broadcast_0;
wire stat_rx_vlan_0;
wire stat_rx_inrangeerr_0;
wire stat_rx_bad_preamble_0;
wire stat_rx_bad_sfd_0;
wire stat_rx_got_signal_os_0;
wire stat_rx_test_pattern_mismatch_0;
wire stat_rx_truncated_0;
wire stat_rx_local_fault_0;
wire stat_rx_remote_fault_0;
wire stat_rx_internal_local_fault_0;
wire stat_rx_received_local_fault_0;
wire stat_rx_status_0;
//// TX_0 Signals
wire tx_reset_0;
wire user_tx_reset_0;
//// TX_0 User Interface Signals
wire tx_axis_tuser_0;
wire tx_unfout_0;
wire [55:0] tx_preamblein_0;
//// TX_0 Control Signals
wire ctl_tx_test_pattern_0;
wire ctl_tx_test_pattern_enable_0;
wire ctl_tx_test_pattern_select_0;
wire ctl_tx_data_pattern_select_0;
wire [57:0] ctl_tx_test_pattern_seed_a_0;
wire [57:0] ctl_tx_test_pattern_seed_b_0;
wire ctl_tx_enable_0;
wire ctl_tx_fcs_ins_enable_0;
wire [3:0] ctl_tx_ipg_value_0;
wire ctl_tx_send_lfi_0;
wire ctl_tx_send_rfi_0;
wire ctl_tx_send_idle_0;
wire ctl_tx_custom_preamble_enable_0;
wire ctl_tx_ignore_fcs_0;
//// TX_0 Stats Signals
wire stat_tx_total_packets_0;
wire [3:0] stat_tx_total_bytes_0;
wire stat_tx_total_good_packets_0;
wire [13:0] stat_tx_total_good_bytes_0;
wire stat_tx_packet_64_bytes_0;
wire stat_tx_packet_65_127_bytes_0;
wire stat_tx_packet_128_255_bytes_0;
wire stat_tx_packet_256_511_bytes_0;
wire stat_tx_packet_512_1023_bytes_0;
wire stat_tx_packet_1024_1518_bytes_0;
wire stat_tx_packet_1519_1522_bytes_0;
wire stat_tx_packet_1523_1548_bytes_0;
wire stat_tx_packet_small_0;
wire stat_tx_packet_large_0;
wire stat_tx_packet_1549_2047_bytes_0;
wire stat_tx_packet_2048_4095_bytes_0;
wire stat_tx_packet_4096_8191_bytes_0;
wire stat_tx_packet_8192_9215_bytes_0;
wire stat_tx_unicast_0;
wire stat_tx_multicast_0;
wire stat_tx_broadcast_0;
wire stat_tx_vlan_0;
wire stat_tx_bad_fcs_0;
wire stat_tx_frame_error_0;
wire stat_tx_local_fault_0;
wire gtwiz_reset_tx_datapath_0;
wire gtwiz_reset_rx_datapath_0;
wire  [4:0 ]completion_status_0;
wire gtpowergood_out_0;
wire [2:0] txoutclksel_in_0;
wire [2:0] rxoutclksel_in_0;

assign rx_core_clk_0 = rx_clk_out_0;
assign gtwiz_reset_tx_datapath_0 = 1'b0; 
assign gtwiz_reset_rx_datapath_0 = 1'b0; 
assign gt_loopback_in_0 = 3'b000;
assign txoutclksel_in_0 = 3'b101;    // this value should not be changed as per gtwizard 
assign rxoutclksel_in_0 = 3'b101;    // this value should not be changed as per gtwizard

assign rx_reset_0                   = 1'b0;
assign ctl_rx_enable_0              = 1'b1;
assign ctl_rx_check_preamble_0      = 1'b1;
assign ctl_rx_check_sfd_0           = 1'b1;
assign ctl_rx_force_resync_0        = 1'b0;
assign ctl_rx_delete_fcs_0          = 1'b1;
assign ctl_rx_ignore_fcs_0          = 1'b0;
assign ctl_rx_process_lfi_0         = 1'b0;
assign ctl_rx_test_pattern_0        = 1'b0;
assign ctl_rx_test_pattern_enable_0 = 1'b0;
assign ctl_rx_data_pattern_select_0 = 1'b0;
assign ctl_rx_max_packet_len_0      = 15'd1536;
assign ctl_rx_min_packet_len_0      = 8'd42;
assign ctl_rx_custom_preamble_enable_0 = 1'b0;

assign tx_reset_0                    = 1'b0;
assign ctl_tx_enable_0                = 1'b1;
assign ctl_tx_send_rfi_0              = 1'b0;
assign ctl_tx_send_lfi_0              = 1'b0;
assign ctl_tx_send_idle_0             = 1'b0;
assign ctl_tx_fcs_ins_enable_0        = 1'b1;
assign ctl_tx_ignore_fcs_0            = 1'b0;
assign ctl_tx_test_pattern_0          = 1'b0;
assign ctl_tx_test_pattern_enable_0   = 1'b0;
assign ctl_tx_data_pattern_select_0   = 1'b0;
assign ctl_tx_test_pattern_select_0   = 1'b0;
assign ctl_tx_test_pattern_seed_a_0   = 58'h0;
assign ctl_tx_test_pattern_seed_b_0   = 58'h0;
assign ctl_tx_custom_preamble_enable_0 = 1'b0;
assign ctl_tx_ipg_value_0             = 4'd12;

//***********************************  ETH CORE 1   ***********************************//

wire [2:0] gt_loopback_in_1; 
//// RX_1 Signals
wire rx_core_clk_1;
wire rx_reset_1;
wire user_rx_reset_1;
wire rxrecclkout_1;
//// RX_1 User Interface Signals
wire rx_axis_tuser_1;
wire [55:0] rx_preambleout_1;
//// RX_1 Control Signals
wire ctl_rx_test_pattern_1;
wire ctl_rx_test_pattern_enable_1;
wire ctl_rx_data_pattern_select_1;
wire ctl_rx_enable_1;
wire ctl_rx_delete_fcs_1;
wire ctl_rx_ignore_fcs_1;
wire [14:0] ctl_rx_max_packet_len_1;
wire [7:0] ctl_rx_min_packet_len_1;
wire ctl_rx_custom_preamble_enable_1;
wire ctl_rx_check_sfd_1;
wire ctl_rx_check_preamble_1;
wire ctl_rx_process_lfi_1;
wire ctl_rx_force_resync_1;
//// RX_1 Stats Signals
wire stat_rx_block_lock_1;
wire stat_rx_framing_err_valid_1;
wire stat_rx_framing_err_1;
wire stat_rx_hi_ber_1;
wire stat_rx_valid_ctrl_code_1;
wire stat_rx_bad_code_1;
wire [1:0] stat_rx_total_packets_1;
wire stat_rx_total_good_packets_1;
wire [3:0] stat_rx_total_bytes_1;
wire [13:0] stat_rx_total_good_bytes_1;
wire stat_rx_packet_small_1;
wire stat_rx_jabber_1;
wire stat_rx_packet_large_1;
wire stat_rx_oversize_1;
wire stat_rx_undersize_1;
wire stat_rx_toolong_1;
wire stat_rx_fragment_1;
wire stat_rx_packet_64_bytes_1;
wire stat_rx_packet_65_127_bytes_1;
wire stat_rx_packet_128_255_bytes_1;
wire stat_rx_packet_256_511_bytes_1;
wire stat_rx_packet_512_1023_bytes_1;
wire stat_rx_packet_1024_1518_bytes_1;
wire stat_rx_packet_1519_1522_bytes_1;
wire stat_rx_packet_1523_1548_bytes_1;
wire [1:0] stat_rx_bad_fcs_1;
wire stat_rx_packet_bad_fcs_1;
wire [1:0] stat_rx_stomped_fcs_1;
wire stat_rx_packet_1549_2047_bytes_1;
wire stat_rx_packet_2048_4095_bytes_1;
wire stat_rx_packet_4096_8191_bytes_1;
wire stat_rx_packet_8192_9215_bytes_1;
wire stat_rx_unicast_1;
wire stat_rx_multicast_1;
wire stat_rx_broadcast_1;
wire stat_rx_vlan_1;
wire stat_rx_inrangeerr_1;
wire stat_rx_bad_preamble_1;
wire stat_rx_bad_sfd_1;
wire stat_rx_got_signal_os_1;
wire stat_rx_test_pattern_mismatch_1;
wire stat_rx_truncated_1;
wire stat_rx_local_fault_1;
wire stat_rx_remote_fault_1;
wire stat_rx_internal_local_fault_1;
wire stat_rx_received_local_fault_1;
wire stat_rx_status_1;
//// TX_1 Signals
wire tx_reset_1;
wire user_tx_reset_1;
//// TX_1 User Interface Signals
wire tx_axis_tuser_1;
wire tx_unfout_1;
wire [55:0] tx_preamblein_1;
//// TX_1 Control Signals
wire ctl_tx_test_pattern_1;
wire ctl_tx_test_pattern_enable_1;
wire ctl_tx_test_pattern_select_1;
wire ctl_tx_data_pattern_select_1;
wire [57:0] ctl_tx_test_pattern_seed_a_1;
wire [57:0] ctl_tx_test_pattern_seed_b_1;
wire ctl_tx_enable_1;
wire ctl_tx_fcs_ins_enable_1;
wire [3:0] ctl_tx_ipg_value_1;
wire ctl_tx_send_lfi_1;
wire ctl_tx_send_rfi_1;
wire ctl_tx_send_idle_1;
wire ctl_tx_custom_preamble_enable_1;
wire ctl_tx_ignore_fcs_1;
//// TX_1 Stats Signals
wire stat_tx_total_packets_1;
wire [3:0] stat_tx_total_bytes_1;
wire stat_tx_total_good_packets_1;
wire [13:0] stat_tx_total_good_bytes_1;
wire stat_tx_packet_64_bytes_1;
wire stat_tx_packet_65_127_bytes_1;
wire stat_tx_packet_128_255_bytes_1;
wire stat_tx_packet_256_511_bytes_1;
wire stat_tx_packet_512_1023_bytes_1;
wire stat_tx_packet_1024_1518_bytes_1;
wire stat_tx_packet_1519_1522_bytes_1;
wire stat_tx_packet_1523_1548_bytes_1;
wire stat_tx_packet_small_1;
wire stat_tx_packet_large_1;
wire stat_tx_packet_1549_2047_bytes_1;
wire stat_tx_packet_2048_4095_bytes_1;
wire stat_tx_packet_4096_8191_bytes_1;
wire stat_tx_packet_8192_9215_bytes_1;
wire stat_tx_unicast_1;
wire stat_tx_multicast_1;
wire stat_tx_broadcast_1;
wire stat_tx_vlan_1;
wire stat_tx_bad_fcs_1;
wire stat_tx_frame_error_1;
wire stat_tx_local_fault_1;
wire gtwiz_reset_tx_datapath_1;
wire gtwiz_reset_rx_datapath_1;
wire gtpowergood_out_1;
wire [2:0] txoutclksel_in_1;
wire [2:0] rxoutclksel_in_1;
wire  [4:0 ]completion_status_1;

assign rx_core_clk_1 = rx_clk_out_1;
assign gtwiz_reset_tx_datapath_1 = 1'b0; 
assign gtwiz_reset_rx_datapath_1 = 1'b0; 
assign gt_loopback_in_1 = 3'b000;
assign txoutclksel_in_1 = 3'b101;    // this value should not be changed as per gtwizard 
assign rxoutclksel_in_1 = 3'b101;    // this value should not be changed as per gtwizard

assign rx_reset_1                   = 1'b0;
assign ctl_rx_enable_1              = 1'b1;
assign ctl_rx_check_preamble_1      = 1'b1;
assign ctl_rx_check_sfd_1           = 1'b1;
assign ctl_rx_force_resync_1        = 1'b0;
assign ctl_rx_delete_fcs_1          = 1'b1;
assign ctl_rx_ignore_fcs_1          = 1'b0;
assign ctl_rx_process_lfi_1         = 1'b0;
assign ctl_rx_test_pattern_1        = 1'b0;
assign ctl_rx_test_pattern_enable_1 = 1'b0;
assign ctl_rx_data_pattern_select_1 = 1'b0;
assign ctl_rx_max_packet_len_1      = 15'd1536;
assign ctl_rx_min_packet_len_1      = 8'd42;
assign ctl_rx_custom_preamble_enable_1 = 1'b0;

assign tx_reset_1                    = 1'b0;
assign ctl_tx_enable_1                = 1'b1;
assign ctl_tx_send_rfi_1              = 1'b0;
assign ctl_tx_send_lfi_1              = 1'b0;
assign ctl_tx_send_idle_1             = 1'b0;
assign ctl_tx_fcs_ins_enable_1        = 1'b1;
assign ctl_tx_ignore_fcs_1            = 1'b0;
assign ctl_tx_test_pattern_1          = 1'b0;
assign ctl_tx_test_pattern_enable_1   = 1'b0;
assign ctl_tx_data_pattern_select_1   = 1'b0;
assign ctl_tx_test_pattern_select_1   = 1'b0;
assign ctl_tx_test_pattern_seed_a_1   = 58'h0;
assign ctl_tx_test_pattern_seed_b_1   = 58'h0;
assign ctl_tx_custom_preamble_enable_1 = 1'b0;
assign ctl_tx_ipg_value_1             = 4'd12;

assign tx_preamblein_0 = 'd0;
assign tx_preamblein_1 = 'd0;
assign tx_unfout_0 = 'd0;
assign tx_unfout_1 = 'd0;
assign tx_axis_tuser_0 = 'd0;
assign tx_axis_tuser_1 = 'd0;


wire[8:0]       ctl_tx_pause_req_0           ;
wire            ctl_tx_resend_pause_0        ;
wire[8:0]       ctl_tx_pause_enable_0        ;
wire[15:0]      ctl_tx_pause_quanta0_0       ;
wire[15:0]      ctl_tx_pause_quanta1_0       ;
wire[15:0]      ctl_tx_pause_quanta2_0       ;
wire[15:0]      ctl_tx_pause_quanta3_0       ;
wire[15:0]      ctl_tx_pause_quanta4_0       ;
wire[15:0]      ctl_tx_pause_quanta5_0       ;
wire[15:0]      ctl_tx_pause_quanta6_0       ;
wire[15:0]      ctl_tx_pause_quanta7_0       ;
wire[15:0]      ctl_tx_pause_quanta8_0       ;
wire[15:0]      ctl_tx_pause_refresh_timer0_0;
wire[15:0]      ctl_tx_pause_refresh_timer1_0;
wire[15:0]      ctl_tx_pause_refresh_timer2_0;
wire[15:0]      ctl_tx_pause_refresh_timer3_0;
wire[15:0]      ctl_tx_pause_refresh_timer4_0;
wire[15:0]      ctl_tx_pause_refresh_timer5_0;
wire[15:0]      ctl_tx_pause_refresh_timer6_0;
wire[15:0]      ctl_tx_pause_refresh_timer7_0;
wire[15:0]      ctl_tx_pause_refresh_timer8_0;
wire[47:0]      ctl_tx_da_gpp_0              ;
wire[47:0]      ctl_tx_sa_gpp_0              ;
wire[15:0]      ctl_tx_ethertype_gpp_0       ;
wire[15:0]      ctl_tx_opcode_gpp_0          ;
wire[47:0]      ctl_tx_da_ppp_0              ;
wire[47:0]      ctl_tx_sa_ppp_0              ;
wire[15:0]      ctl_tx_ethertype_ppp_0       ;
wire[15:0]      ctl_tx_opcode_ppp_0          ;
wire[8:0]       ctl_tx_pause_req_1     = 'd0     ;
wire            ctl_tx_resend_pause_1  = 'd0     ;
wire[8:0]       ctl_tx_pause_enable_1  = 'd0     ;
wire[15:0]      ctl_tx_pause_quanta0_1 = 'd0     ;
wire[15:0]      ctl_tx_pause_quanta1_1 = 'd0     ;
wire[15:0]      ctl_tx_pause_quanta2_1 = 'd0     ;
wire[15:0]      ctl_tx_pause_quanta3_1 = 'd0     ;
wire[15:0]      ctl_tx_pause_quanta4_1 = 'd0     ;
wire[15:0]      ctl_tx_pause_quanta5_1 = 'd0     ;
wire[15:0]      ctl_tx_pause_quanta6_1 = 'd0     ;
wire[15:0]      ctl_tx_pause_quanta7_1 = 'd0     ;
wire[15:0]      ctl_tx_pause_quanta8_1 = 'd0     ;
wire[15:0]      ctl_tx_pause_refresh_timer0_1  = 'd0;
wire[15:0]      ctl_tx_pause_refresh_timer1_1  = 'd0;
wire[15:0]      ctl_tx_pause_refresh_timer2_1  = 'd0;
wire[15:0]      ctl_tx_pause_refresh_timer3_1  = 'd0;
wire[15:0]      ctl_tx_pause_refresh_timer4_1  = 'd0;
wire[15:0]      ctl_tx_pause_refresh_timer5_1  = 'd0;
wire[15:0]      ctl_tx_pause_refresh_timer6_1  = 'd0;
wire[15:0]      ctl_tx_pause_refresh_timer7_1  = 'd0;
wire[15:0]      ctl_tx_pause_refresh_timer8_1  = 'd0;
wire[47:0]      ctl_tx_da_gpp_1          = 'd0    ;
wire[47:0]      ctl_tx_sa_gpp_1          = 'd0    ;
wire[15:0]      ctl_tx_ethertype_gpp_1   = 'd0    ;
wire[15:0]      ctl_tx_opcode_gpp_1      = 'd0    ;
wire[47:0]      ctl_tx_da_ppp_1          = 'd0    ;
wire[47:0]      ctl_tx_sa_ppp_1          = 'd0    ;
wire[15:0]      ctl_tx_ethertype_ppp_1   = 'd0    ;
wire[15:0]      ctl_tx_opcode_ppp_1      = 'd0    ;


wire        stat_tx_pause_0      ;
wire        stat_tx_user_pause_0 ;
wire [8:0]  stat_tx_pause_valid_0;
wire        stat_tx_pause_1      ;
wire        stat_tx_user_pause_1 ;
wire [8:0]  stat_tx_pause_valid_1;



MAC_TX_FlowControl#(
    .FPGA_TX_MAC_ADDR(48'h00_00_00_11_11_11)
) MAC_TX_FlowControl_0(
    .clk                        (tx_clk_out_0),
    .ctl_tx_pause_req           (ctl_tx_pause_req_0           ),//output
    .ctl_tx_resend_pause        (ctl_tx_resend_pause_0        ),//output
    .ctl_tx_pause_enable        (ctl_tx_pause_enable_0        ),//output
    .ctl_tx_pause_quanta0       (ctl_tx_pause_quanta0_0       ),//output
    .ctl_tx_pause_quanta1       (ctl_tx_pause_quanta1_0       ),//output
    .ctl_tx_pause_quanta2       (ctl_tx_pause_quanta2_0       ),//output
    .ctl_tx_pause_quanta3       (ctl_tx_pause_quanta3_0       ),//output
    .ctl_tx_pause_quanta4       (ctl_tx_pause_quanta4_0       ),//output
    .ctl_tx_pause_quanta5       (ctl_tx_pause_quanta5_0       ),//output
    .ctl_tx_pause_quanta6       (ctl_tx_pause_quanta6_0       ),//output
    .ctl_tx_pause_quanta7       (ctl_tx_pause_quanta7_0       ),//output
    .ctl_tx_pause_quanta8       (ctl_tx_pause_quanta8_0       ),//output
    .ctl_tx_pause_refresh_timer0(ctl_tx_pause_refresh_timer0_0),//output
    .ctl_tx_pause_refresh_timer1(ctl_tx_pause_refresh_timer1_0),//output
    .ctl_tx_pause_refresh_timer2(ctl_tx_pause_refresh_timer2_0),//output
    .ctl_tx_pause_refresh_timer3(ctl_tx_pause_refresh_timer3_0),//output
    .ctl_tx_pause_refresh_timer4(ctl_tx_pause_refresh_timer4_0),//output
    .ctl_tx_pause_refresh_timer5(ctl_tx_pause_refresh_timer5_0),//output
    .ctl_tx_pause_refresh_timer6(ctl_tx_pause_refresh_timer6_0),//output
    .ctl_tx_pause_refresh_timer7(ctl_tx_pause_refresh_timer7_0),//output
    .ctl_tx_pause_refresh_timer8(ctl_tx_pause_refresh_timer8_0),//output
    .ctl_tx_da_gpp              (ctl_tx_da_gpp_0              ),//output
    .ctl_tx_sa_gpp              (ctl_tx_sa_gpp_0              ),//output
    .ctl_tx_ethertype_gpp       (ctl_tx_ethertype_gpp_0       ),//output
    .ctl_tx_opcode_gpp          (ctl_tx_opcode_gpp_0          ),//output
    .ctl_tx_da_ppp              (ctl_tx_da_ppp_0              ),//output
    .ctl_tx_sa_ppp              (ctl_tx_sa_ppp_0              ),//output
    .ctl_tx_ethertype_ppp       (ctl_tx_ethertype_ppp_0       ),//output
    .ctl_tx_opcode_ppp          (ctl_tx_opcode_ppp_0          ),//output
    .VIO_FIFO_ASSERT            (VIO_FIFO_ASSERT_0            ),//output
    .VIO_FIFO_NEGATE            (VIO_FIFO_NEGATE_0            ),//output
    .MAC_SOURCE_ADDR            (MAC_SOURCE_ADDR_0            ),//input
    .MAC_Pause                  (MAC_Pause_0                  ) //input
);


xxv_ethernet_2 u_xxv_ethernet_2 (
  .gt_rxp_in_0(gt_rxp_in_0),                                            // input wire gt_rxp_in_0
  .gt_rxp_in_1(gt_rxp_in_1),                                            // input wire gt_rxp_in_1
  .gt_rxn_in_0(gt_rxn_in_0),                                            // input wire gt_rxn_in_0
  .gt_rxn_in_1(gt_rxn_in_1),                                            // input wire gt_rxn_in_1
  .gt_txp_out_0(gt_txp_out_0),                                          // output wire gt_txp_out_0
  .gt_txp_out_1(gt_txp_out_1),                                          // output wire gt_txp_out_1
  .gt_txn_out_0(gt_txn_out_0),                                          // output wire gt_txn_out_0
  .gt_txn_out_1(gt_txn_out_1),                                          // output wire gt_txn_out_1
  .rx_core_clk_0(rx_core_clk_0),                                        // input wire rx_core_clk_0
  .rx_core_clk_1(rx_core_clk_1),                                        // input wire rx_core_clk_1
  .txoutclksel_in_0(txoutclksel_in_0),                                  // input wire [2 : 0] txoutclksel_in_0
  .rxoutclksel_in_0(rxoutclksel_in_0),                                  // input wire [2 : 0] rxoutclksel_in_0
  .txoutclksel_in_1(txoutclksel_in_1),                                  // input wire [2 : 0] txoutclksel_in_1
  .rxoutclksel_in_1(rxoutclksel_in_1),                                  // input wire [2 : 0] rxoutclksel_in_1
  .gtwiz_reset_tx_datapath_0(gtwiz_reset_tx_datapath_0),                // input wire gtwiz_reset_tx_datapath_0
  .gtwiz_reset_tx_datapath_1(gtwiz_reset_tx_datapath_1),                // input wire gtwiz_reset_tx_datapath_1
  .gtwiz_reset_rx_datapath_0(gtwiz_reset_rx_datapath_0),                // input wire gtwiz_reset_rx_datapath_0
  .gtwiz_reset_rx_datapath_1(gtwiz_reset_rx_datapath_1),                // input wire gtwiz_reset_rx_datapath_1
  .rxrecclkout_0(rxrecclkout_0),                                        // output wire rxrecclkout_0
  .rxrecclkout_1(rxrecclkout_1),                                        // output wire rxrecclkout_1
  .sys_reset(sys_reset),                                                // input wire sys_reset
  .dclk(dclk),                                                          // input wire dclk
  .tx_clk_out_0(tx_clk_out_0),                                          // output wire tx_clk_out_0
  .tx_clk_out_1(tx_clk_out_1),                                          // output wire tx_clk_out_1
  .rx_clk_out_0(rx_clk_out_0),                                          // output wire rx_clk_out_0
  .rx_clk_out_1(rx_clk_out_1),                                          // output wire rx_clk_out_1
  .gt_refclk_p(gt_refclk_p),                                            // input wire gt_refclk_p
  .gt_refclk_n(gt_refclk_n),                                            // input wire gt_refclk_n
  .gt_refclk_out(gt_refclk_out),                                        // output wire gt_refclk_out
  .gtpowergood_out_0(gtpowergood_out_0),                                // output wire gtpowergood_out_0
  .gtpowergood_out_1(gtpowergood_out_1),                                // output wire gtpowergood_out_1
  .rx_reset_0(rx_reset_0),                                              // input wire rx_reset_0
  .rx_reset_1(rx_reset_1),                                              // input wire rx_reset_1
  .user_rx_reset_0(user_rx_reset_0),                                    // output wire user_rx_reset_0
  .user_rx_reset_1(user_rx_reset_1),                                    // output wire user_rx_reset_1
  .rx_axis_tvalid_0(rx_axis_tvalid_0),                                  // output wire rx_axis_tvalid_0
  .rx_axis_tvalid_1(rx_axis_tvalid_1),                                  // output wire rx_axis_tvalid_1
  .rx_axis_tdata_0(rx_axis_tdata_0),                                    // output wire [63 : 0] rx_axis_tdata_0
  .rx_axis_tdata_1(rx_axis_tdata_1),                                    // output wire [63 : 0] rx_axis_tdata_1
  .rx_axis_tlast_0(rx_axis_tlast_0),                                    // output wire rx_axis_tlast_0
  .rx_axis_tlast_1(rx_axis_tlast_1),                                    // output wire rx_axis_tlast_1
  .rx_axis_tkeep_0(rx_axis_tkeep_0),                                    // output wire [7 : 0] rx_axis_tkeep_0
  .rx_axis_tkeep_1(rx_axis_tkeep_1),                                    // output wire [7 : 0] rx_axis_tkeep_1
  .rx_axis_tuser_0(rx_axis_tuser_0),                                    // output wire rx_axis_tuser_0
  .rx_axis_tuser_1(rx_axis_tuser_1),                                    // output wire rx_axis_tuser_1
  .ctl_rx_enable_0(ctl_rx_enable_0),                                    // input wire ctl_rx_enable_0
  .ctl_rx_enable_1(ctl_rx_enable_1),                                    // input wire ctl_rx_enable_1
  .ctl_rx_check_preamble_0(ctl_rx_check_preamble_0),                    // input wire ctl_rx_check_preamble_0
  .ctl_rx_check_preamble_1(ctl_rx_check_preamble_1),                    // input wire ctl_rx_check_preamble_1
  .ctl_rx_check_sfd_0(ctl_rx_check_sfd_0),                              // input wire ctl_rx_check_sfd_0
  .ctl_rx_check_sfd_1(ctl_rx_check_sfd_1),                              // input wire ctl_rx_check_sfd_1
  .ctl_rx_force_resync_0(ctl_rx_force_resync_0),                        // input wire ctl_rx_force_resync_0
  .ctl_rx_force_resync_1(ctl_rx_force_resync_1),                        // input wire ctl_rx_force_resync_1
  .ctl_rx_delete_fcs_0(ctl_rx_delete_fcs_0),                            // input wire ctl_rx_delete_fcs_0
  .ctl_rx_delete_fcs_1(ctl_rx_delete_fcs_1),                            // input wire ctl_rx_delete_fcs_1
  .ctl_rx_ignore_fcs_0(ctl_rx_ignore_fcs_0),                            // input wire ctl_rx_ignore_fcs_0
  .ctl_rx_ignore_fcs_1(ctl_rx_ignore_fcs_1),                            // input wire ctl_rx_ignore_fcs_1
  .ctl_rx_max_packet_len_0(ctl_rx_max_packet_len_0),                    // input wire [14 : 0] ctl_rx_max_packet_len_0
  .ctl_rx_max_packet_len_1(ctl_rx_max_packet_len_1),                    // input wire [14 : 0] ctl_rx_max_packet_len_1
  .ctl_rx_min_packet_len_0(ctl_rx_min_packet_len_0),                    // input wire [7 : 0] ctl_rx_min_packet_len_0
  .ctl_rx_min_packet_len_1(ctl_rx_min_packet_len_1),                    // input wire [7 : 0] ctl_rx_min_packet_len_1
  .ctl_rx_process_lfi_0(ctl_rx_process_lfi_0),                          // input wire ctl_rx_process_lfi_0
  .ctl_rx_process_lfi_1(ctl_rx_process_lfi_1),                          // input wire ctl_rx_process_lfi_1
  .ctl_rx_test_pattern_0(ctl_rx_test_pattern_0),                        // input wire ctl_rx_test_pattern_0
  .ctl_rx_test_pattern_1(ctl_rx_test_pattern_1),                        // input wire ctl_rx_test_pattern_1
  .ctl_rx_data_pattern_select_0(ctl_rx_data_pattern_select_0),          // input wire ctl_rx_data_pattern_select_0
  .ctl_rx_data_pattern_select_1(ctl_rx_data_pattern_select_1),          // input wire ctl_rx_data_pattern_select_1
  .ctl_rx_test_pattern_enable_0(ctl_rx_test_pattern_enable_0),          // input wire ctl_rx_test_pattern_enable_0
  .ctl_rx_test_pattern_enable_1(ctl_rx_test_pattern_enable_1),          // input wire ctl_rx_test_pattern_enable_1
  .ctl_rx_custom_preamble_enable_0(ctl_rx_custom_preamble_enable_0),    // input wire ctl_rx_custom_preamble_enable_0
  .ctl_rx_custom_preamble_enable_1(ctl_rx_custom_preamble_enable_1),    // input wire ctl_rx_custom_preamble_enable_1
  .stat_rx_framing_err_0(stat_rx_framing_err_0),                        // output wire stat_rx_framing_err_0
  .stat_rx_framing_err_1(stat_rx_framing_err_1),                        // output wire stat_rx_framing_err_1
  .stat_rx_framing_err_valid_0(stat_rx_framing_err_valid_0),            // output wire stat_rx_framing_err_valid_0
  .stat_rx_framing_err_valid_1(stat_rx_framing_err_valid_1),            // output wire stat_rx_framing_err_valid_1
  .stat_rx_local_fault_0(stat_rx_local_fault_0),                        // output wire stat_rx_local_fault_0
  .stat_rx_local_fault_1(stat_rx_local_fault_1),                        // output wire stat_rx_local_fault_1
  .stat_rx_block_lock_0(stat_rx_block_lock_0),                          // output wire stat_rx_block_lock_0
  .stat_rx_block_lock_1(stat_rx_block_lock_1),                          // output wire stat_rx_block_lock_1
  .stat_rx_valid_ctrl_code_0(stat_rx_valid_ctrl_code_0),                // output wire stat_rx_valid_ctrl_code_0
  .stat_rx_valid_ctrl_code_1(stat_rx_valid_ctrl_code_1),                // output wire stat_rx_valid_ctrl_code_1
  .stat_rx_status_0(stat_rx_status_0),                                  // output wire stat_rx_status_0
  .stat_rx_status_1(stat_rx_status_1),                                  // output wire stat_rx_status_1
  .stat_rx_remote_fault_0(stat_rx_remote_fault_0),                      // output wire stat_rx_remote_fault_0
  .stat_rx_remote_fault_1(stat_rx_remote_fault_1),                      // output wire stat_rx_remote_fault_1
  .stat_rx_bad_fcs_0(stat_rx_bad_fcs_0),                                // output wire [1 : 0] stat_rx_bad_fcs_0
  .stat_rx_bad_fcs_1(stat_rx_bad_fcs_1),                                // output wire [1 : 0] stat_rx_bad_fcs_1
  .stat_rx_stomped_fcs_0(stat_rx_stomped_fcs_0),                        // output wire [1 : 0] stat_rx_stomped_fcs_0
  .stat_rx_stomped_fcs_1(stat_rx_stomped_fcs_1),                        // output wire [1 : 0] stat_rx_stomped_fcs_1
  .stat_rx_truncated_0(stat_rx_truncated_0),                            // output wire stat_rx_truncated_0
  .stat_rx_truncated_1(stat_rx_truncated_1),                            // output wire stat_rx_truncated_1
  .stat_rx_internal_local_fault_0(stat_rx_internal_local_fault_0),      // output wire stat_rx_internal_local_fault_0
  .stat_rx_internal_local_fault_1(stat_rx_internal_local_fault_1),      // output wire stat_rx_internal_local_fault_1
  .stat_rx_received_local_fault_0(stat_rx_received_local_fault_0),      // output wire stat_rx_received_local_fault_0
  .stat_rx_received_local_fault_1(stat_rx_received_local_fault_1),      // output wire stat_rx_received_local_fault_1
  .stat_rx_hi_ber_0(stat_rx_hi_ber_0),                                  // output wire stat_rx_hi_ber_0
  .stat_rx_hi_ber_1(stat_rx_hi_ber_1),                                  // output wire stat_rx_hi_ber_1
  .stat_rx_got_signal_os_0(stat_rx_got_signal_os_0),                    // output wire stat_rx_got_signal_os_0
  .stat_rx_got_signal_os_1(stat_rx_got_signal_os_1),                    // output wire stat_rx_got_signal_os_1
  .stat_rx_test_pattern_mismatch_0(stat_rx_test_pattern_mismatch_0),    // output wire stat_rx_test_pattern_mismatch_0
  .stat_rx_test_pattern_mismatch_1(stat_rx_test_pattern_mismatch_1),    // output wire stat_rx_test_pattern_mismatch_1
  .stat_rx_total_bytes_0(stat_rx_total_bytes_0),                        // output wire [3 : 0] stat_rx_total_bytes_0
  .stat_rx_total_bytes_1(stat_rx_total_bytes_1),                        // output wire [3 : 0] stat_rx_total_bytes_1
  .stat_rx_total_packets_0(stat_rx_total_packets_0),                    // output wire [1 : 0] stat_rx_total_packets_0
  .stat_rx_total_packets_1(stat_rx_total_packets_1),                    // output wire [1 : 0] stat_rx_total_packets_1
  .stat_rx_total_good_bytes_0(stat_rx_total_good_bytes_0),              // output wire [13 : 0] stat_rx_total_good_bytes_0
  .stat_rx_total_good_bytes_1(stat_rx_total_good_bytes_1),              // output wire [13 : 0] stat_rx_total_good_bytes_1
  .stat_rx_total_good_packets_0(stat_rx_total_good_packets_0),          // output wire stat_rx_total_good_packets_0
  .stat_rx_total_good_packets_1(stat_rx_total_good_packets_1),          // output wire stat_rx_total_good_packets_1
  .stat_rx_packet_bad_fcs_0(stat_rx_packet_bad_fcs_0),                  // output wire stat_rx_packet_bad_fcs_0
  .stat_rx_packet_bad_fcs_1(stat_rx_packet_bad_fcs_1),                  // output wire stat_rx_packet_bad_fcs_1
  .stat_rx_packet_64_bytes_0(stat_rx_packet_64_bytes_0),                // output wire stat_rx_packet_64_bytes_0
  .stat_rx_packet_64_bytes_1(stat_rx_packet_64_bytes_1),                // output wire stat_rx_packet_64_bytes_1
  .stat_rx_packet_65_127_bytes_0(stat_rx_packet_65_127_bytes_0),        // output wire stat_rx_packet_65_127_bytes_0
  .stat_rx_packet_65_127_bytes_1(stat_rx_packet_65_127_bytes_1),        // output wire stat_rx_packet_65_127_bytes_1
  .stat_rx_packet_128_255_bytes_0(stat_rx_packet_128_255_bytes_0),      // output wire stat_rx_packet_128_255_bytes_0
  .stat_rx_packet_128_255_bytes_1(stat_rx_packet_128_255_bytes_1),      // output wire stat_rx_packet_128_255_bytes_1
  .stat_rx_packet_256_511_bytes_0(stat_rx_packet_256_511_bytes_0),      // output wire stat_rx_packet_256_511_bytes_0
  .stat_rx_packet_256_511_bytes_1(stat_rx_packet_256_511_bytes_1),      // output wire stat_rx_packet_256_511_bytes_1
  .stat_rx_packet_512_1023_bytes_0(stat_rx_packet_512_1023_bytes_0),    // output wire stat_rx_packet_512_1023_bytes_0
  .stat_rx_packet_512_1023_bytes_1(stat_rx_packet_512_1023_bytes_1),    // output wire stat_rx_packet_512_1023_bytes_1
  .stat_rx_packet_1024_1518_bytes_0(stat_rx_packet_1024_1518_bytes_0),  // output wire stat_rx_packet_1024_1518_bytes_0
  .stat_rx_packet_1024_1518_bytes_1(stat_rx_packet_1024_1518_bytes_1),  // output wire stat_rx_packet_1024_1518_bytes_1
  .stat_rx_packet_1519_1522_bytes_0(stat_rx_packet_1519_1522_bytes_0),  // output wire stat_rx_packet_1519_1522_bytes_0
  .stat_rx_packet_1519_1522_bytes_1(stat_rx_packet_1519_1522_bytes_1),  // output wire stat_rx_packet_1519_1522_bytes_1
  .stat_rx_packet_1523_1548_bytes_0(stat_rx_packet_1523_1548_bytes_0),  // output wire stat_rx_packet_1523_1548_bytes_0
  .stat_rx_packet_1523_1548_bytes_1(stat_rx_packet_1523_1548_bytes_1),  // output wire stat_rx_packet_1523_1548_bytes_1
  .stat_rx_packet_1549_2047_bytes_0(stat_rx_packet_1549_2047_bytes_0),  // output wire stat_rx_packet_1549_2047_bytes_0
  .stat_rx_packet_1549_2047_bytes_1(stat_rx_packet_1549_2047_bytes_1),  // output wire stat_rx_packet_1549_2047_bytes_1
  .stat_rx_packet_2048_4095_bytes_0(stat_rx_packet_2048_4095_bytes_0),  // output wire stat_rx_packet_2048_4095_bytes_0
  .stat_rx_packet_2048_4095_bytes_1(stat_rx_packet_2048_4095_bytes_1),  // output wire stat_rx_packet_2048_4095_bytes_1
  .stat_rx_packet_4096_8191_bytes_0(stat_rx_packet_4096_8191_bytes_0),  // output wire stat_rx_packet_4096_8191_bytes_0
  .stat_rx_packet_4096_8191_bytes_1(stat_rx_packet_4096_8191_bytes_1),  // output wire stat_rx_packet_4096_8191_bytes_1
  .stat_rx_packet_8192_9215_bytes_0(stat_rx_packet_8192_9215_bytes_0),  // output wire stat_rx_packet_8192_9215_bytes_0
  .stat_rx_packet_8192_9215_bytes_1(stat_rx_packet_8192_9215_bytes_1),  // output wire stat_rx_packet_8192_9215_bytes_1
  .stat_rx_packet_small_0(stat_rx_packet_small_0),                      // output wire stat_rx_packet_small_0
  .stat_rx_packet_small_1(stat_rx_packet_small_1),                      // output wire stat_rx_packet_small_1
  .stat_rx_packet_large_0(stat_rx_packet_large_0),                      // output wire stat_rx_packet_large_0
  .stat_rx_packet_large_1(stat_rx_packet_large_1),                      // output wire stat_rx_packet_large_1
  .stat_rx_unicast_0(stat_rx_unicast_0),                                // output wire stat_rx_unicast_0
  .stat_rx_unicast_1(stat_rx_unicast_1),                                // output wire stat_rx_unicast_1
  .stat_rx_multicast_0(stat_rx_multicast_0),                            // output wire stat_rx_multicast_0
  .stat_rx_multicast_1(stat_rx_multicast_1),                            // output wire stat_rx_multicast_1
  .stat_rx_broadcast_0(stat_rx_broadcast_0),                            // output wire stat_rx_broadcast_0
  .stat_rx_broadcast_1(stat_rx_broadcast_1),                            // output wire stat_rx_broadcast_1
  .stat_rx_oversize_0(stat_rx_oversize_0),                              // output wire stat_rx_oversize_0
  .stat_rx_oversize_1(stat_rx_oversize_1),                              // output wire stat_rx_oversize_1
  .stat_rx_toolong_0(stat_rx_toolong_0),                                // output wire stat_rx_toolong_0
  .stat_rx_toolong_1(stat_rx_toolong_1),                                // output wire stat_rx_toolong_1
  .stat_rx_undersize_0(stat_rx_undersize_0),                            // output wire stat_rx_undersize_0
  .stat_rx_undersize_1(stat_rx_undersize_1),                            // output wire stat_rx_undersize_1
  .stat_rx_fragment_0(stat_rx_fragment_0),                              // output wire stat_rx_fragment_0
  .stat_rx_fragment_1(stat_rx_fragment_1),                              // output wire stat_rx_fragment_1
  .stat_rx_vlan_0(stat_rx_vlan_0),                                      // output wire stat_rx_vlan_0
  .stat_rx_vlan_1(stat_rx_vlan_1),                                      // output wire stat_rx_vlan_1
  .stat_rx_inrangeerr_0(stat_rx_inrangeerr_0),                          // output wire stat_rx_inrangeerr_0
  .stat_rx_inrangeerr_1(stat_rx_inrangeerr_1),                          // output wire stat_rx_inrangeerr_1
  .stat_rx_jabber_0(stat_rx_jabber_0),                                  // output wire stat_rx_jabber_0
  .stat_rx_jabber_1(stat_rx_jabber_1),                                  // output wire stat_rx_jabber_1
  .stat_rx_bad_code_0(stat_rx_bad_code_0),                              // output wire stat_rx_bad_code_0
  .stat_rx_bad_code_1(stat_rx_bad_code_1),                              // output wire stat_rx_bad_code_1
  .stat_rx_bad_sfd_0(stat_rx_bad_sfd_0),                                // output wire stat_rx_bad_sfd_0
  .stat_rx_bad_sfd_1(stat_rx_bad_sfd_1),                                // output wire stat_rx_bad_sfd_1
  .stat_rx_bad_preamble_0(stat_rx_bad_preamble_0),                      // output wire stat_rx_bad_preamble_0
  .stat_rx_bad_preamble_1(stat_rx_bad_preamble_1),                      // output wire stat_rx_bad_preamble_1
  .tx_reset_0(tx_reset_0),                                              // input wire tx_reset_0
  .tx_reset_1(tx_reset_1),                                              // input wire tx_reset_1
  .user_tx_reset_0(user_tx_reset_0),                                    // output wire user_tx_reset_0
  .user_tx_reset_1(user_tx_reset_1),                                    // output wire user_tx_reset_1
  .tx_axis_tready_0(tx_axis_tready_0),                                  // output wire tx_axis_tready_0
  .tx_axis_tready_1(tx_axis_tready_1),                                  // output wire tx_axis_tready_1
  .tx_axis_tvalid_0(tx_axis_tvalid_0),                                  // input wire tx_axis_tvalid_0
  .tx_axis_tvalid_1(tx_axis_tvalid_1),                                  // input wire tx_axis_tvalid_1
  .tx_axis_tdata_0(tx_axis_tdata_0),                                    // input wire [63 : 0] tx_axis_tdata_0
  .tx_axis_tdata_1(tx_axis_tdata_1),                                    // input wire [63 : 0] tx_axis_tdata_1
  .tx_axis_tlast_0(tx_axis_tlast_0),                                    // input wire tx_axis_tlast_0
  .tx_axis_tlast_1(tx_axis_tlast_1),                                    // input wire tx_axis_tlast_1
  .tx_axis_tkeep_0(tx_axis_tkeep_0),                                    // input wire [7 : 0] tx_axis_tkeep_0
  .tx_axis_tkeep_1(tx_axis_tkeep_1),                                    // input wire [7 : 0] tx_axis_tkeep_1
  .tx_axis_tuser_0(tx_axis_tuser_0),                                    // input wire tx_axis_tuser_0
  .tx_axis_tuser_1(tx_axis_tuser_1),                                    // input wire tx_axis_tuser_1
  .tx_unfout_0(tx_unfout_0),                                            // output wire tx_unfout_0
  .tx_unfout_1(tx_unfout_1),                                            // output wire tx_unfout_1
  .tx_preamblein_0(tx_preamblein_0),                                    // input wire [55 : 0] tx_preamblein_0
  .rx_preambleout_0(rx_preambleout_0),                                  // output wire [55 : 0] rx_preambleout_0
  .tx_preamblein_1(tx_preamblein_1),                                    // input wire [55 : 0] tx_preamblein_1
  .rx_preambleout_1(rx_preambleout_1),                                  // output wire [55 : 0] rx_preambleout_1
  .stat_tx_local_fault_0(stat_tx_local_fault_0),                        // output wire stat_tx_local_fault_0
  .stat_tx_local_fault_1(stat_tx_local_fault_1),                        // output wire stat_tx_local_fault_1
  .stat_tx_total_bytes_0(stat_tx_total_bytes_0),                        // output wire [3 : 0] stat_tx_total_bytes_0
  .stat_tx_total_bytes_1(stat_tx_total_bytes_1),                        // output wire [3 : 0] stat_tx_total_bytes_1
  .stat_tx_total_packets_0(stat_tx_total_packets_0),                    // output wire stat_tx_total_packets_0
  .stat_tx_total_packets_1(stat_tx_total_packets_1),                    // output wire stat_tx_total_packets_1
  .stat_tx_total_good_bytes_0(stat_tx_total_good_bytes_0),              // output wire [13 : 0] stat_tx_total_good_bytes_0
  .stat_tx_total_good_bytes_1(stat_tx_total_good_bytes_1),              // output wire [13 : 0] stat_tx_total_good_bytes_1
  .stat_tx_total_good_packets_0(stat_tx_total_good_packets_0),          // output wire stat_tx_total_good_packets_0
  .stat_tx_total_good_packets_1(stat_tx_total_good_packets_1),          // output wire stat_tx_total_good_packets_1
  .stat_tx_bad_fcs_0(stat_tx_bad_fcs_0),                                // output wire stat_tx_bad_fcs_0
  .stat_tx_bad_fcs_1(stat_tx_bad_fcs_1),                                // output wire stat_tx_bad_fcs_1
  .stat_tx_packet_64_bytes_0(stat_tx_packet_64_bytes_0),                // output wire stat_tx_packet_64_bytes_0
  .stat_tx_packet_64_bytes_1(stat_tx_packet_64_bytes_1),                // output wire stat_tx_packet_64_bytes_1
  .stat_tx_packet_65_127_bytes_0(stat_tx_packet_65_127_bytes_0),        // output wire stat_tx_packet_65_127_bytes_0
  .stat_tx_packet_65_127_bytes_1(stat_tx_packet_65_127_bytes_1),        // output wire stat_tx_packet_65_127_bytes_1
  .stat_tx_packet_128_255_bytes_0(stat_tx_packet_128_255_bytes_0),      // output wire stat_tx_packet_128_255_bytes_0
  .stat_tx_packet_128_255_bytes_1(stat_tx_packet_128_255_bytes_1),      // output wire stat_tx_packet_128_255_bytes_1
  .stat_tx_packet_256_511_bytes_0(stat_tx_packet_256_511_bytes_0),      // output wire stat_tx_packet_256_511_bytes_0
  .stat_tx_packet_256_511_bytes_1(stat_tx_packet_256_511_bytes_1),      // output wire stat_tx_packet_256_511_bytes_1
  .stat_tx_packet_512_1023_bytes_0(stat_tx_packet_512_1023_bytes_0),    // output wire stat_tx_packet_512_1023_bytes_0
  .stat_tx_packet_512_1023_bytes_1(stat_tx_packet_512_1023_bytes_1),    // output wire stat_tx_packet_512_1023_bytes_1
  .stat_tx_packet_1024_1518_bytes_0(stat_tx_packet_1024_1518_bytes_0),  // output wire stat_tx_packet_1024_1518_bytes_0
  .stat_tx_packet_1024_1518_bytes_1(stat_tx_packet_1024_1518_bytes_1),  // output wire stat_tx_packet_1024_1518_bytes_1
  .stat_tx_packet_1519_1522_bytes_0(stat_tx_packet_1519_1522_bytes_0),  // output wire stat_tx_packet_1519_1522_bytes_0
  .stat_tx_packet_1519_1522_bytes_1(stat_tx_packet_1519_1522_bytes_1),  // output wire stat_tx_packet_1519_1522_bytes_1
  .stat_tx_packet_1523_1548_bytes_0(stat_tx_packet_1523_1548_bytes_0),  // output wire stat_tx_packet_1523_1548_bytes_0
  .stat_tx_packet_1523_1548_bytes_1(stat_tx_packet_1523_1548_bytes_1),  // output wire stat_tx_packet_1523_1548_bytes_1
  .stat_tx_packet_1549_2047_bytes_0(stat_tx_packet_1549_2047_bytes_0),  // output wire stat_tx_packet_1549_2047_bytes_0
  .stat_tx_packet_1549_2047_bytes_1(stat_tx_packet_1549_2047_bytes_1),  // output wire stat_tx_packet_1549_2047_bytes_1
  .stat_tx_packet_2048_4095_bytes_0(stat_tx_packet_2048_4095_bytes_0),  // output wire stat_tx_packet_2048_4095_bytes_0
  .stat_tx_packet_2048_4095_bytes_1(stat_tx_packet_2048_4095_bytes_1),  // output wire stat_tx_packet_2048_4095_bytes_1
  .stat_tx_packet_4096_8191_bytes_0(stat_tx_packet_4096_8191_bytes_0),  // output wire stat_tx_packet_4096_8191_bytes_0
  .stat_tx_packet_4096_8191_bytes_1(stat_tx_packet_4096_8191_bytes_1),  // output wire stat_tx_packet_4096_8191_bytes_1
  .stat_tx_packet_8192_9215_bytes_0(stat_tx_packet_8192_9215_bytes_0),  // output wire stat_tx_packet_8192_9215_bytes_0
  .stat_tx_packet_8192_9215_bytes_1(stat_tx_packet_8192_9215_bytes_1),  // output wire stat_tx_packet_8192_9215_bytes_1
  .stat_tx_packet_small_0(stat_tx_packet_small_0),                      // output wire stat_tx_packet_small_0
  .stat_tx_packet_small_1(stat_tx_packet_small_1),                      // output wire stat_tx_packet_small_1
  .stat_tx_packet_large_0(stat_tx_packet_large_0),                      // output wire stat_tx_packet_large_0
  .stat_tx_packet_large_1(stat_tx_packet_large_1),                      // output wire stat_tx_packet_large_1
  .stat_tx_unicast_0(stat_tx_unicast_0),                                // output wire stat_tx_unicast_0
  .stat_tx_unicast_1(stat_tx_unicast_1),                                // output wire stat_tx_unicast_1
  .stat_tx_multicast_0(stat_tx_multicast_0),                            // output wire stat_tx_multicast_0
  .stat_tx_multicast_1(stat_tx_multicast_1),                            // output wire stat_tx_multicast_1
  .stat_tx_broadcast_0(stat_tx_broadcast_0),                            // output wire stat_tx_broadcast_0
  .stat_tx_broadcast_1(stat_tx_broadcast_1),                            // output wire stat_tx_broadcast_1
  .stat_tx_vlan_0(stat_tx_vlan_0),                                      // output wire stat_tx_vlan_0
  .stat_tx_vlan_1(stat_tx_vlan_1),                                      // output wire stat_tx_vlan_1
  .stat_tx_frame_error_0(stat_tx_frame_error_0),                        // output wire stat_tx_frame_error_0
  .stat_tx_frame_error_1(stat_tx_frame_error_1),                        // output wire stat_tx_frame_error_1
  .stat_tx_pause_0(stat_tx_pause_0),                                    // output wire stat_tx_pause_0
  .stat_tx_pause_1(stat_tx_pause_1),                                    // output wire stat_tx_pause_1
  .stat_tx_user_pause_0(stat_tx_user_pause_0),                          // output wire stat_tx_user_pause_0
  .stat_tx_user_pause_1(stat_tx_user_pause_1),                          // output wire stat_tx_user_pause_1
  .stat_tx_pause_valid_0(stat_tx_pause_valid_0),                        // output wire [8 : 0] stat_tx_pause_valid_0
  .stat_tx_pause_valid_1(stat_tx_pause_valid_1),                        // output wire [8 : 0] stat_tx_pause_valid_1
  .ctl_tx_pause_req_0(ctl_tx_pause_req_0),                              // input wire [8 : 0] ctl_tx_pause_req_0
  .ctl_tx_pause_req_1(ctl_tx_pause_req_1),                              // input wire [8 : 0] ctl_tx_pause_req_1
  .ctl_tx_resend_pause_0(ctl_tx_resend_pause_0),                        // input wire ctl_tx_resend_pause_0
  .ctl_tx_resend_pause_1(ctl_tx_resend_pause_1),                        // input wire ctl_tx_resend_pause_1
  .ctl_tx_pause_enable_0(ctl_tx_pause_enable_0),                        // input wire [8 : 0] ctl_tx_pause_enable_0
  .ctl_tx_pause_enable_1(ctl_tx_pause_enable_1),                        // input wire [8 : 0] ctl_tx_pause_enable_1
  .ctl_tx_pause_quanta0_0(ctl_tx_pause_quanta0_0),                      // input wire [15 : 0] ctl_tx_pause_quanta0_0
  .ctl_tx_pause_quanta0_1(ctl_tx_pause_quanta0_1),                      // input wire [15 : 0] ctl_tx_pause_quanta0_1
  .ctl_tx_pause_quanta1_0(ctl_tx_pause_quanta1_0),                      // input wire [15 : 0] ctl_tx_pause_quanta1_0
  .ctl_tx_pause_quanta1_1(ctl_tx_pause_quanta1_1),                      // input wire [15 : 0] ctl_tx_pause_quanta1_1
  .ctl_tx_pause_quanta2_0(ctl_tx_pause_quanta2_0),                      // input wire [15 : 0] ctl_tx_pause_quanta2_0
  .ctl_tx_pause_quanta2_1(ctl_tx_pause_quanta2_1),                      // input wire [15 : 0] ctl_tx_pause_quanta2_1
  .ctl_tx_pause_quanta3_0(ctl_tx_pause_quanta3_0),                      // input wire [15 : 0] ctl_tx_pause_quanta3_0
  .ctl_tx_pause_quanta3_1(ctl_tx_pause_quanta3_1),                      // input wire [15 : 0] ctl_tx_pause_quanta3_1
  .ctl_tx_pause_quanta4_0(ctl_tx_pause_quanta4_0),                      // input wire [15 : 0] ctl_tx_pause_quanta4_0
  .ctl_tx_pause_quanta4_1(ctl_tx_pause_quanta4_1),                      // input wire [15 : 0] ctl_tx_pause_quanta4_1
  .ctl_tx_pause_quanta5_0(ctl_tx_pause_quanta5_0),                      // input wire [15 : 0] ctl_tx_pause_quanta5_0
  .ctl_tx_pause_quanta5_1(ctl_tx_pause_quanta5_1),                      // input wire [15 : 0] ctl_tx_pause_quanta5_1
  .ctl_tx_pause_quanta6_0(ctl_tx_pause_quanta6_0),                      // input wire [15 : 0] ctl_tx_pause_quanta6_0
  .ctl_tx_pause_quanta6_1(ctl_tx_pause_quanta6_1),                      // input wire [15 : 0] ctl_tx_pause_quanta6_1
  .ctl_tx_pause_quanta7_0(ctl_tx_pause_quanta7_0),                      // input wire [15 : 0] ctl_tx_pause_quanta7_0
  .ctl_tx_pause_quanta7_1(ctl_tx_pause_quanta7_1),                      // input wire [15 : 0] ctl_tx_pause_quanta7_1
  .ctl_tx_pause_quanta8_0(ctl_tx_pause_quanta8_0),                      // input wire [15 : 0] ctl_tx_pause_quanta8_0
  .ctl_tx_pause_quanta8_1(ctl_tx_pause_quanta8_1),  
  .ctl_tx_pause_refresh_timer0_0(ctl_tx_pause_refresh_timer0_0),        // input wire [15 : 0] ctl_tx_pause_refresh_timer0_0
  .ctl_tx_pause_refresh_timer0_1(ctl_tx_pause_refresh_timer0_1),        // input wire [15 : 0] ctl_tx_pause_refresh_timer0_1
  .ctl_tx_pause_refresh_timer1_0(ctl_tx_pause_refresh_timer1_0),        // input wire [15 : 0] ctl_tx_pause_refresh_timer1_0
  .ctl_tx_pause_refresh_timer1_1(ctl_tx_pause_refresh_timer1_1),        // input wire [15 : 0] ctl_tx_pause_refresh_timer1_1
  .ctl_tx_pause_refresh_timer2_0(ctl_tx_pause_refresh_timer2_0),        // input wire [15 : 0] ctl_tx_pause_refresh_timer2_0
  .ctl_tx_pause_refresh_timer2_1(ctl_tx_pause_refresh_timer2_1),        // input wire [15 : 0] ctl_tx_pause_refresh_timer2_1
  .ctl_tx_pause_refresh_timer3_0(ctl_tx_pause_refresh_timer3_0),        // input wire [15 : 0] ctl_tx_pause_refresh_timer3_0
  .ctl_tx_pause_refresh_timer3_1(ctl_tx_pause_refresh_timer3_1),        // input wire [15 : 0] ctl_tx_pause_refresh_timer3_1
  .ctl_tx_pause_refresh_timer4_0(ctl_tx_pause_refresh_timer4_0),        // input wire [15 : 0] ctl_tx_pause_refresh_timer4_0
  .ctl_tx_pause_refresh_timer4_1(ctl_tx_pause_refresh_timer4_1),        // input wire [15 : 0] ctl_tx_pause_refresh_timer4_1
  .ctl_tx_pause_refresh_timer5_0(ctl_tx_pause_refresh_timer5_0),        // input wire [15 : 0] ctl_tx_pause_refresh_timer5_0
  .ctl_tx_pause_refresh_timer5_1(ctl_tx_pause_refresh_timer5_1),        // input wire [15 : 0] ctl_tx_pause_refresh_timer5_1
  .ctl_tx_pause_refresh_timer6_0(ctl_tx_pause_refresh_timer6_0),        // input wire [15 : 0] ctl_tx_pause_refresh_timer6_0
  .ctl_tx_pause_refresh_timer6_1(ctl_tx_pause_refresh_timer6_1),        // input wire [15 : 0] ctl_tx_pause_refresh_timer6_1
  .ctl_tx_pause_refresh_timer7_0(ctl_tx_pause_refresh_timer7_0),        // input wire [15 : 0] ctl_tx_pause_refresh_timer7_0
  .ctl_tx_pause_refresh_timer7_1(ctl_tx_pause_refresh_timer7_1),        // input wire [15 : 0] ctl_tx_pause_refresh_timer7_1
  .ctl_tx_pause_refresh_timer8_0(ctl_tx_pause_refresh_timer8_0),        // input wire [15 : 0] ctl_tx_pause_refresh_timer8_0
  .ctl_tx_pause_refresh_timer8_1(ctl_tx_pause_refresh_timer8_1),        // input wire [15 : 0] ctl_tx_pause_refresh_timer8_1
  .ctl_tx_da_gpp_0(ctl_tx_da_gpp_0),                                    // input wire [47 : 0] ctl_tx_da_gpp_0
  .ctl_tx_da_gpp_1(ctl_tx_da_gpp_1),                                    // input wire [47 : 0] ctl_tx_da_gpp_1
  .ctl_tx_sa_gpp_0(ctl_tx_sa_gpp_0),                                    // input wire [47 : 0] ctl_tx_sa_gpp_0
  .ctl_tx_sa_gpp_1(ctl_tx_sa_gpp_1),                                    // input wire [47 : 0] ctl_tx_sa_gpp_1
  .ctl_tx_ethertype_gpp_0(ctl_tx_ethertype_gpp_0),                      // input wire [15 : 0] ctl_tx_ethertype_gpp_0
  .ctl_tx_ethertype_gpp_1(ctl_tx_ethertype_gpp_1),                      // input wire [15 : 0] ctl_tx_ethertype_gpp_1
  .ctl_tx_opcode_gpp_0(ctl_tx_opcode_gpp_0),                            // input wire [15 : 0] ctl_tx_opcode_gpp_0
  .ctl_tx_opcode_gpp_1(ctl_tx_opcode_gpp_1),                            // input wire [15 : 0] ctl_tx_opcode_gpp_1
  .ctl_tx_da_ppp_0(ctl_tx_da_ppp_0),                                    // input wire [47 : 0] ctl_tx_da_ppp_0
  .ctl_tx_da_ppp_1(ctl_tx_da_ppp_1),                                    // input wire [47 : 0] ctl_tx_da_ppp_1
  .ctl_tx_sa_ppp_0(ctl_tx_sa_ppp_0),                                    // input wire [47 : 0] ctl_tx_sa_ppp_0
  .ctl_tx_sa_ppp_1(ctl_tx_sa_ppp_1),                                    // input wire [47 : 0] ctl_tx_sa_ppp_1
  .ctl_tx_ethertype_ppp_0(ctl_tx_ethertype_ppp_0),                      // input wire [15 : 0] ctl_tx_ethertype_ppp_0
  .ctl_tx_ethertype_ppp_1(ctl_tx_ethertype_ppp_1),                      // input wire [15 : 0] ctl_tx_ethertype_ppp_1
  .ctl_tx_opcode_ppp_0(ctl_tx_opcode_ppp_0),                            // input wire [15 : 0] ctl_tx_opcode_ppp_0
  .ctl_tx_opcode_ppp_1(ctl_tx_opcode_ppp_1),      
  .ctl_tx_enable_0(ctl_tx_enable_0),                                    // input wire ctl_tx_enable_0
  .ctl_tx_enable_1(ctl_tx_enable_1),                                    // input wire ctl_tx_enable_1
  .ctl_tx_send_rfi_0(ctl_tx_send_rfi_0),                                // input wire ctl_tx_send_rfi_0
  .ctl_tx_send_rfi_1(ctl_tx_send_rfi_1),                                // input wire ctl_tx_send_rfi_1
  .ctl_tx_send_lfi_0(ctl_tx_send_lfi_0),                                // input wire ctl_tx_send_lfi_0
  .ctl_tx_send_lfi_1(ctl_tx_send_lfi_1),                                // input wire ctl_tx_send_lfi_1
  .ctl_tx_send_idle_0(ctl_tx_send_idle_0),                              // input wire ctl_tx_send_idle_0
  .ctl_tx_send_idle_1(ctl_tx_send_idle_1),                              // input wire ctl_tx_send_idle_1
  .ctl_tx_fcs_ins_enable_0(ctl_tx_fcs_ins_enable_0),                    // input wire ctl_tx_fcs_ins_enable_0
  .ctl_tx_fcs_ins_enable_1(ctl_tx_fcs_ins_enable_1),                    // input wire ctl_tx_fcs_ins_enable_1
  .ctl_tx_ignore_fcs_0(ctl_tx_ignore_fcs_0),                            // input wire ctl_tx_ignore_fcs_0
  .ctl_tx_ignore_fcs_1(ctl_tx_ignore_fcs_1),                            // input wire ctl_tx_ignore_fcs_1
  .ctl_tx_test_pattern_0(ctl_tx_test_pattern_0),                        // input wire ctl_tx_test_pattern_0
  .ctl_tx_test_pattern_1(ctl_tx_test_pattern_1),                        // input wire ctl_tx_test_pattern_1
  .ctl_tx_test_pattern_enable_0(ctl_tx_test_pattern_enable_0),          // input wire ctl_tx_test_pattern_enable_0
  .ctl_tx_test_pattern_enable_1(ctl_tx_test_pattern_enable_1),          // input wire ctl_tx_test_pattern_enable_1
  .ctl_tx_test_pattern_select_0(ctl_tx_test_pattern_select_0),          // input wire ctl_tx_test_pattern_select_0
  .ctl_tx_test_pattern_select_1(ctl_tx_test_pattern_select_1),          // input wire ctl_tx_test_pattern_select_1
  .ctl_tx_data_pattern_select_0(ctl_tx_data_pattern_select_0),          // input wire ctl_tx_data_pattern_select_0
  .ctl_tx_data_pattern_select_1(ctl_tx_data_pattern_select_1),          // input wire ctl_tx_data_pattern_select_1
  .ctl_tx_test_pattern_seed_a_0(ctl_tx_test_pattern_seed_a_0),          // input wire [57 : 0] ctl_tx_test_pattern_seed_a_0
  .ctl_tx_test_pattern_seed_a_1(ctl_tx_test_pattern_seed_a_1),          // input wire [57 : 0] ctl_tx_test_pattern_seed_a_1
  .ctl_tx_test_pattern_seed_b_0(ctl_tx_test_pattern_seed_b_0),          // input wire [57 : 0] ctl_tx_test_pattern_seed_b_0
  .ctl_tx_test_pattern_seed_b_1(ctl_tx_test_pattern_seed_b_1),          // input wire [57 : 0] ctl_tx_test_pattern_seed_b_1
  .ctl_tx_ipg_value_0(ctl_tx_ipg_value_0),                              // input wire [3 : 0] ctl_tx_ipg_value_0
  .ctl_tx_ipg_value_1(ctl_tx_ipg_value_1),                              // input wire [3 : 0] ctl_tx_ipg_value_1
  .ctl_tx_custom_preamble_enable_0(ctl_tx_custom_preamble_enable_0),    // input wire ctl_tx_custom_preamble_enable_0
  .ctl_tx_custom_preamble_enable_1(ctl_tx_custom_preamble_enable_1),    // input wire ctl_tx_custom_preamble_enable_1
  .gt_loopback_in_0(gt_loopback_in_0),                                  // input wire [2 : 0] gt_loopback_in_0
  .gt_loopback_in_1(gt_loopback_in_1),                                  // input wire [2 : 0] gt_loopback_in_1
  .qpllreset_in_0(1'b0)                                      // input wire qpllreset_in_0
);



endmodule