`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: fmc_THz_test_top
// Description: Receive PHY, Ethernet data and constellation outputs.
// Tool Versions: Vivado 2021.2
//////////////////////////////////////////////////////////////////////////////////
module fmc_THz_test_top (
    input wire clk1,  // 409.6 MHz
    input wire clk2,  // 204.8 MHz
    input wire locked,
    input wire fclk,
    input wire gt_refclk_p,
    input wire gt_refclk_n,
    input wire gt_rxp_in_0,
    input wire gt_rxn_in_0,
    output wire gt_txp_out_0,
    output wire gt_txn_out_0,
    input wire gt_rxp_in_1,
    input wire gt_rxn_in_1,
    output wire gt_txp_out_1,
    output wire gt_txn_out_1,
    input wire [12*16-1:0] DAC_IQ_RX,
    input wire adc_valid,
    input wire clk_feedback,
    input wire feedback_arst_n,
    input wire feedback_dac_ready,
    output wire [191:0] feedback_dac_data,
    output wire feedback_dac_valid,
    output wire [31:0] feedback_status_ps,
    output wire [31:0] feedback_events_ps,
    output wire [31:0] feedback_sent_ps,
    output wire overflow_error_fast,
    output reg frame_toggle
);
    wire [31:0] coded_bits;
    wire [5:0] coded_width;
    wire coded_v;
    wire coded_start;
    wire [2:0] coded_block;
    wire vio_rst_n;
    wire [4:0] vio_mov_zf_window_len;
    wire ber_control;
    wire [3:0] vio_phy_ploy;
    wire [1:0] vio_phy_mode;
    wire ber_window_full;
    wire [63:0] ber_total_bits;
    wire [63:0] ber_total_errors;
    wire clk_ldpc;
    wire ldpc_locked;
    wire [31:0] phy_dout;
    wire [5:0] phy_dout_width;
    wire phy_dout_v;
    wire decode_done;
    wire decode_ok;
    wire [3:0] iterations;
    wire [3:0] group_ok;
    wire ldpc_overflow_error;
    wire ldpc_mode_error;
    wire rx_resetn = locked && ldpc_locked && vio_rst_n;
    wire eth_reset_n;
    wire [127:0] to_cone_i;
    wire [127:0] to_cone_q;
    wire to_cone_v;
    wire [3:0] to_cone_ploy;
    wire [1:0] to_cone_modulation;
    wire [31:0] to_cone_frame;
    wire ada_event_v;
    wire [3:0] ada_current_mode, ada_recommended_mode;
    wire [31:0] ada_frame;
    wire fb_ready, fb_busy, fb_overflow, fb_stall;
    wire [31:0] fb_events, fb_sent;
    wire [3:0] fb_flags_ps;
    wire mac_tx_0_clk;
    wire mac_tx_1_clk;
    wire mac_tx_0_tready;
    wire mac_tx_1_tready;
    wire [63:0] mac_tx_0_tdata;
    wire [63:0] mac_tx_1_tdata;
    wire [7:0] mac_tx_0_tkeep;
    wire [7:0] mac_tx_1_tkeep;
    wire mac_tx_0_tlast;
    wire mac_tx_1_tlast;
    wire mac_tx_0_tvalid;
    wire mac_tx_1_tvalid;

    clk_ldpc_wiz u_clk_ldpc_wiz (
        .clk_in1 (clk2),
        .reset   (!locked),
        .clk_out1(clk_ldpc),
        .locked  (ldpc_locked)
    );
    always @(posedge clk2 or negedge rx_resetn) begin
        if (!rx_resetn) frame_toggle <= 1'b0;
        else if (coded_v && coded_start && coded_block == 3'd0) frame_toggle <= ~frame_toggle;
    end
    // Manual reset, BER control and received-frame observations.
    vio_rx_control u_vio_rx_control (
        .clk       (clk2),
        .probe_out0(vio_rst_n),
        .probe_out1(ber_control),
        .probe_out2(vio_mov_zf_window_len),
        .probe_in0 (vio_phy_ploy),
        .probe_in1 (vio_phy_mode),
        .probe_in2 (ber_total_bits),
        .probe_in3 (ber_total_errors),
        .probe_in4 (ber_window_full)
    );
    PHY_TOP_Rx #(
        .AUTO_MODE       (1),
        .ENABLE_RECOMMEND(1)
    ) u_PHY_TOP_Rx (
        .clk_400M                 (clk1),
        .clk_200M                 (clk2),
        .clk_ldpc                 (clk_ldpc),
        .rst_n                    (rx_resetn),
        .phy_ploy                 (4'd8),
        .modulation               (2'd2),
        .adc_data                 (DAC_IQ_RX),
        .adc_valid                (adc_valid),
        .mov_zf_window_len        (vio_mov_zf_window_len),
        .coded_bits               (coded_bits),
        .coded_llr                (),
        .coded_width              (coded_width),
        .coded_v                  (coded_v),
        .coded_start              (coded_start),
        .coded_block              (coded_block),
        .overflow_error_fast      (overflow_error_fast),
        .dout                     (phy_dout),
        .dout_v                   (phy_dout_v),
        .dout_width               (phy_dout_width),
        .decode_done              (decode_done),
        .decode_ok                (decode_ok),
        .iterations               (iterations),
        .group_ok                 (group_ok),
        .ldpc_overflow_error      (ldpc_overflow_error),
        .ldpc_mode_error          (ldpc_mode_error),
        .to_cone_i                (to_cone_i),
        .to_cone_q                (to_cone_q),
        .to_cone_v                (to_cone_v),
        .to_cone_ploy             (to_cone_ploy),
        .to_cone_modulation       (to_cone_modulation),
        .to_cone_frame            (to_cone_frame),
        .detected_p               (vio_phy_ploy),
        .detected_m               (vio_phy_mode),
        .rate_locked              (),
        .acquire_error            (),
        .recommended_mode         (ada_recommended_mode),
        .recommendation_v         (ada_event_v),
        .recommendation_frame     (ada_frame),
        .recommendation_current_mode(ada_current_mode),
        .recommendation_confidence(),
        .recommendation_fault     ()
    );

    // Whole Ada transactions cross into the 40.96-MHz feedback transmitter.
    // Its reset is board/PS controlled, independent of the Ada loss watchdog.
    rx_ada_feedback_tx u_feedback_tx (
        .clk_src(clk2), .clk_dac(clk_feedback), .arst_n(feedback_arst_n),
        .event_v(ada_event_v), .current_mode(ada_current_mode),
        .recommended_mode(ada_recommended_mode), .frame_id(ada_frame),
        .dac_ready(feedback_dac_ready), .dac_data(feedback_dac_data),
        .dac_valid(feedback_dac_valid), .tx_ready(fb_ready),
        .frame_start(), .frame_busy(fb_busy), .packet24(),
        .events_accepted(fb_events), .frames_sent(fb_sent), .fifo_level(),
        .event_overflow(fb_overflow), .stall_seen(fb_stall)
    );
    // PS diagnostic registers do not add ILA probes. Gray counters preserve
    // atomic multi-bit observations across the independent AXI clock.
    xpm_cdc_gray #(.DEST_SYNC_FF(2), .INIT_SYNC_FF(0), .REG_OUTPUT(1),
        .SIM_ASSERT_CHK(0), .SIM_LOSSLESS_GRAY_CHK(0), .WIDTH(32)) u_fb_events_ps (
        .src_clk(clk2), .src_in_bin(fb_events), .dest_clk(fclk), .dest_out_bin(feedback_events_ps)
    );
    xpm_cdc_gray #(.DEST_SYNC_FF(2), .INIT_SYNC_FF(0), .REG_OUTPUT(1),
        .SIM_ASSERT_CHK(0), .SIM_LOSSLESS_GRAY_CHK(0), .WIDTH(32)) u_fb_sent_ps (
        .src_clk(clk_feedback), .src_in_bin(fb_sent), .dest_clk(fclk), .dest_out_bin(feedback_sent_ps)
    );
    xpm_cdc_array_single #(.DEST_SYNC_FF(2), .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0), .SRC_INPUT_REG(0), .WIDTH(4)) u_fb_flags_ps (
        .src_clk(1'b0), .src_in({fb_stall,fb_overflow,fb_busy,fb_ready}),
        .dest_clk(fclk), .dest_out(fb_flags_ps)
    );
    assign feedback_status_ps = {28'd0, fb_flags_ps};

    Reset_Sync u_eth_core_reset (
        .clk   (fclk),
        .arst_n(locked),
        .rst_n (eth_reset_n)
    );

    ETH_TOP u_ETH_TOP (
        .clk_phy         (clk2),
        .rst_n_phy       (rx_resetn),
        .phy_ploy        (to_cone_ploy),
        .phy_din         (phy_dout),
        .phy_din_v       (phy_dout_v),
        .phy_din_width   (phy_dout_width),
        .ber_enable      (ber_control),
        .ber_total_bits  (ber_total_bits),
        .ber_total_errors(ber_total_errors),
        .ber_window_full (ber_window_full),
        .cone_i          (to_cone_i),
        .cone_q          (to_cone_q),
        .cone_v          (to_cone_v),
        .cone_modulation (to_cone_modulation),
        .cone_frame_id   (to_cone_frame),
        .mac_tx_0_clk    (mac_tx_0_clk),
        .mac_tx_0_tready (mac_tx_0_tready),
        .mac_tx_0_tdata  (mac_tx_0_tdata),
        .mac_tx_0_tkeep  (mac_tx_0_tkeep),
        .mac_tx_0_tlast  (mac_tx_0_tlast),
        .mac_tx_0_tvalid (mac_tx_0_tvalid),
        .mac_tx_1_clk    (mac_tx_1_clk),
        .mac_tx_1_tready (mac_tx_1_tready),
        .mac_tx_1_tdata  (mac_tx_1_tdata),
        .mac_tx_1_tkeep  (mac_tx_1_tkeep),
        .mac_tx_1_tlast  (mac_tx_1_tlast),
        .mac_tx_1_tvalid (mac_tx_1_tvalid)
    );

    ethernet_tx_rx u_ethernet_tx_rx (
        .gt_rxp_in_0          (gt_rxp_in_0),
        .gt_rxn_in_0          (gt_rxn_in_0),
        .gt_txp_out_0         (gt_txp_out_0),
        .gt_txn_out_0         (gt_txn_out_0),
        .gt_rxp_in_1          (gt_rxp_in_1),
        .gt_rxn_in_1          (gt_rxn_in_1),
        .gt_txp_out_1         (gt_txp_out_1),
        .gt_txn_out_1         (gt_txn_out_1),
        .sys_reset            (!eth_reset_n),
        .gt_refclk_p          (gt_refclk_p),
        .gt_refclk_n          (gt_refclk_n),
        .dclk                 (fclk),
        .tx_clk_out_0         (mac_tx_0_clk),
        .tx_clk_out_1         (mac_tx_1_clk),
        .rx_clk_out_0         (),
        .rx_clk_out_1         (),
        .rx_axis_tvalid_0     (),
        .rx_axis_tdata_0      (),
        .rx_axis_tlast_0      (),
        .rx_axis_tkeep_0      (),
        .tx_axis_tready_0     (mac_tx_0_tready),
        .tx_axis_tvalid_0     (mac_tx_0_tvalid),
        .tx_axis_tdata_0      (mac_tx_0_tdata),
        .tx_axis_tlast_0      (mac_tx_0_tlast),
        .tx_axis_tkeep_0      (mac_tx_0_tkeep),
        .rx_axis_tvalid_1     (),
        .rx_axis_tdata_1      (),
        .rx_axis_tlast_1      (),
        .rx_axis_tkeep_1      (),
        .tx_axis_tready_1     (mac_tx_1_tready),
        .tx_axis_tvalid_1     (mac_tx_1_tvalid),
        .tx_axis_tdata_1      (mac_tx_1_tdata),
        .tx_axis_tlast_1      (mac_tx_1_tlast),
        .tx_axis_tkeep_1      (mac_tx_1_tkeep),
        .VIO_FIFO_ASSERT_0    (),
        .VIO_FIFO_NEGATE_0    (),
        .MAC_Buffer_count_tx_0(15'd0),
        .MAC_SOURCE_ADDR_0    (48'd0),
        .MAC_Pause_0          (1'b0),
        .Error_MACfifo_0      (1'b0)
    );

endmodule
