`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Module Name: adaloop_top
// Project Name: Rx
// Target Devices: xczu47dr-ffve1156-2-i
// Tool Versions: Vivado 2021.2 / Verilog-2001
// Description: Main Rx0 + event-only Ada feedback Tx6 + constellation UDP.
// Dependencies: Local copy of Tx/system.bd, user_control, reset_sync, feedback link.
//////////////////////////////////////////////////////////////////////////////////

module adaloop_top (
    input  wire       gt_refclk_p,
    input  wire       gt_refclk_n,
    input  wire       gt_rxp_in_0,
    input  wire       gt_rxn_in_0,
    output wire       gt_txp_out_0,
    output wire       gt_txn_out_0,
    input  wire       gt_rxp_in_1,
    input  wire       gt_rxn_in_1,
    output wire       gt_txp_out_1,
    output wire       gt_txn_out_1,
    input  wire       pl_clk_n,
    input  wire       pl_clk_p,
    input  wire       pl_sysref_n,
    input  wire       pl_sysref_p,
    input  wire       adc1_clk_n,
    input  wire       adc1_clk_p,
    input  wire       dac2_clk_n,
    input  wire       dac2_clk_p,
    input  wire       sysref_in_n,
    input  wire       sysref_in_p,
    input  wire       vin0_01_n,
    input  wire       vin0_01_p,
    input  wire       vin0_23_n,
    input  wire       vin0_23_p,
    input  wire       vin1_01_n,
    input  wire       vin1_01_p,
    input  wire       vin1_23_n,
    input  wire       vin1_23_p,
    output wire       vout20_n,
    output wire       vout20_p,
    output wire       vout22_n,
    output wire       vout22_p,
    output wire       vout30_n,
    output wire       vout30_p,
    output wire       vout32_n,
    output wire       vout32_p,
    inout  wire       lmk_sync,
    output wire [3:0] led,
    output wire       user_io7,
    output wire       user_io6,
    output wire       user_io5,
    output wire       user_io4,
    inout  wire [3:0] user_io,
    inout  wire       trig_out,
    input  wire       trig_in,
    input  wire       gps_1pps,
    input  wire       txd_gps
);

    // All three clocks come from system_i/clk_wiz_0 and remain related:
    // data_clk=409.6 MHz decoder, data_clk1=204.8 MHz source/ILA,
    // data_clk2=40.96 MHz feedback RFDC AXI and complex RRC front ends.
    wire data_clk;
    wire data_clk1;
    wire data_clk2;
    wire locked;
    (* KEEP = "TRUE" *) wire fclk_100m;
    wire fclk_reset0;
    wire pl_clk;
    wire pl_sysref;
    reg pl_sysref_r;
    reg user_sysref_adc;

    wire [191:0] m00_axis_tdata;
    wire         m00_axis_tvalid;
    wire [191:0] m02_axis_tdata;
    wire         m02_axis_tvalid;
    wire         s20_axis_tready;
    wire         s22_axis_tready;
    wire [191:0] m10_axis_tdata;
    wire         m10_axis_tvalid;
    wire [191:0] m11_axis_tdata;
    wire         m11_axis_tvalid;
    wire [191:0] m12_axis_tdata;
    wire         m12_axis_tvalid;
    wire [191:0] m13_axis_tdata;
    wire         m13_axis_tvalid;
    wire [191:0] s30_axis_tdata;
    wire         s30_axis_tready;
    wire         s30_axis_tvalid;
    wire         s32_axis_tready;

    wire [15:0] gpio_tri_i;
    wire [15:0] gpio_tri_o;
    wire [15:0] gpio_tri_t;
    wire        up_rack;
    wire [15:0] up_raddr;
    wire [31:0] up_rdata;
    wire        up_rreq;
    wire        up_wack;
    wire [15:0] up_waddr;
    wire [31:0] up_wdata;
    wire        up_wreq;
    wire [31:0] feedback_status_ps, feedback_events_ps, feedback_sent_ps;
    wire main_frame_toggle;
    wire        mtime_start;
    wire [1:0]  pps_select;
    wire [31:0] clock_1pps;
    wire [11:0] phase;
    wire [3:0]  rf_mode;
    wire        config_done;
    wire [7:0]  adc_freeze;
    wire [7:0]  adc_clear_ov;
    wire        fddtdd_sw;
    wire        trx_sw_ps;

    // Decode the complete mode in its PS register clock domain. Only the
    // registered one-bit enable crosses to RF reset synchronizers; a changing
    // multi-bit rf_mode bus is never decoded in the RF clock domains.
    reg run_enable_ps;
    wire link_arst_n;
    always @(posedge fclk_100m or negedge fclk_reset0) begin
        if (!fclk_reset0)
            run_enable_ps <= 1'b0;
        else
            run_enable_ps <= mtime_start && (rf_mode == 4'd1);
    end
    assign link_arst_n = fclk_reset0 && locked && run_enable_ps;

    // Keep the established external SYSREF sampling topology from Tx.
    IBUFDS u_pl_clk (
        .I  (pl_clk_p),
        .IB (pl_clk_n),
        .O  (pl_clk)
    );
    IBUFDS u_pl_sysref (
        .I  (pl_sysref_p),
        .IB (pl_sysref_n),
        .O  (pl_sysref)
    );
    always @(posedge pl_clk) begin
        pl_sysref_r <= pl_sysref;
        user_sysref_adc <= pl_sysref_r;
    end

    // Feedback: Tile231 DAC0/DUC0 s30 -> vout30 -> TX_06 -> Tx6/JA7.
    //           Tile225 ADC0 vin1_01 -> RX_02/Rx2/JA11 -> m10(I),m11(Q).
    // Tile230 DAC20/22 and Tile224 ADC00/02 are reserved for communication.
    // Unused DACs transmit zero and all unused ADC streams are consumed.
    system system_i (
        .GPIO0_tri_i       (gpio_tri_i),
        .GPIO0_tri_o       (gpio_tri_o),
        .GPIO0_tri_t       (gpio_tri_t),
        .adc1_clk_clk_n    (adc1_clk_n),
        .adc1_clk_clk_p    (adc1_clk_p),
        .dac2_clk_clk_n    (dac2_clk_n),
        .dac2_clk_clk_p    (dac2_clk_p),
        .data_clk          (data_clk),
        .data_clk1         (data_clk1),
        .data_clk2         (data_clk2),
        .locked            (locked),
        .pl_resetn0        (fclk_reset0),
        .m00_axis_tdata    (m00_axis_tdata),
        .m00_axis_tready   (1'b1),
        .m00_axis_tvalid   (m00_axis_tvalid),
        .m02_axis_tdata    (m02_axis_tdata),
        .m02_axis_tready   (1'b1),
        .m02_axis_tvalid   (m02_axis_tvalid),
        .s20_axis_tdata    (192'd0),
        .s20_axis_tready   (s20_axis_tready),
        .s20_axis_tvalid   (1'b1),
        .s22_axis_tdata    (192'd0),
        .s22_axis_tready   (s22_axis_tready),
        .s22_axis_tvalid   (1'b1),
        .m10_axis_tdata    (m10_axis_tdata),
        .m10_axis_tready   (1'b1),
        .m10_axis_tvalid   (m10_axis_tvalid),
        .m11_axis_tdata    (m11_axis_tdata),
        .m11_axis_tready   (1'b1),
        .m11_axis_tvalid   (m11_axis_tvalid),
        .m12_axis_tdata    (m12_axis_tdata),
        .m12_axis_tready   (1'b1),
        .m12_axis_tvalid   (m12_axis_tvalid),
        .m13_axis_tdata    (m13_axis_tdata),
        .m13_axis_tready   (1'b1),
        .m13_axis_tvalid   (m13_axis_tvalid),
        .s30_axis_tdata    (s30_axis_tdata),
        .s30_axis_tready   (s30_axis_tready),
        .s30_axis_tvalid   (s30_axis_tvalid),
        .s32_axis_tdata    (192'd0),
        .s32_axis_tready   (s32_axis_tready),
        .s32_axis_tvalid   (1'b1),
        .sysref_in_diff_n  (sysref_in_n),
        .sysref_in_diff_p  (sysref_in_p),
        .user_sysref_adc_0 (user_sysref_adc),
        .fclk_100m         (fclk_100m),
        .up_rack           (up_rack),
        .up_raddr          (up_raddr),
        .up_rdata          (up_rdata),
        .up_rreq           (up_rreq),
        .up_wack           (up_wack),
        .up_waddr          (up_waddr),
        .up_wdata          (up_wdata),
        .up_wreq           (up_wreq),
        .vin0_01_v_n       (vin0_01_n),
        .vin0_01_v_p       (vin0_01_p),
        .vin0_23_v_n       (vin0_23_n),
        .vin0_23_v_p       (vin0_23_p),
        .vin1_01_v_n       (vin1_01_n),
        .vin1_01_v_p       (vin1_01_p),
        .vin1_23_v_n       (vin1_23_n),
        .vin1_23_v_p       (vin1_23_p),
        .vout20_v_n        (vout20_n),
        .vout20_v_p        (vout20_p),
        .vout22_v_n        (vout22_n),
        .vout22_v_p        (vout22_p),
        .vout30_v_n        (vout30_n),
        .vout30_v_p        (vout30_p),
        .vout32_v_n        (vout32_n),
        .vout32_v_p        (vout32_p)
    );

    ad_iobuf #(.DATA_WIDTH(7)) u_gpio_iobuf (
        .dio_t (gpio_tri_t[6:0]),
        .dio_i (gpio_tri_o[6:0]),
        .dio_o (gpio_tri_i[6:0]),
        .dio_p ({user_io, fddtdd_sw, trx_sw_ps, lmk_sync})
    );
    assign gpio_tri_i[15:7] = 9'd0;
    assign user_io7 = gpio_tri_o[4];
    assign user_io6 = gpio_tri_o[4];
    assign user_io5 = gpio_tri_o[4];
    assign user_io4 = gpio_tri_o[4];
    assign trig_out = 1'bz;

    // Retain Tx PS software's register map and its start/mode control contract.
    user_control u_user_control (
        .axi_gp_clk     (fclk_100m),
        .axi_rst        (~fclk_reset0),
        .up_rack        (up_rack),
        .up_raddr       (up_raddr),
        .up_rdata       (up_rdata),
        .up_rreq        (up_rreq),
        .up_wack        (up_wack),
        .up_waddr       (up_waddr),
        .up_wdata       (up_wdata),
        .up_wreq        (up_wreq),
        .mtime_start    (mtime_start),
        .pps_select     (pps_select),
        .clock_1pps     (clock_1pps),
        .phase          (phase),
        .rf_mode        (rf_mode),
        .config_done    (config_done),
        .adc_freeze     (adc_freeze),
        .adc_clear_ov   (adc_clear_ov),
        .sdr_info       ({16'h1000, 16'd840}),
        .fw_ver         (32'h20261021),
        .feedback_status(feedback_status_ps),
        .feedback_events(feedback_events_ps),
        .feedback_sent  (feedback_sent_ps),
        .adc_over_volt  (8'd0),
        .dev_clk_locked (locked)
    );

    // Main Rx0 keeps its 12-real-sample 409.6-MHz path and existing Ethernet.
    // No standalone feedback test source, receiver or additional ILA is present.
    fmc_THz_test_top u_fmc_THz_test_top (
        .clk1(data_clk), .clk2(data_clk1), .locked(locked), .fclk(fclk_100m),
        .gt_refclk_p(gt_refclk_p), .gt_refclk_n(gt_refclk_n),
        .gt_rxp_in_0(gt_rxp_in_0), .gt_rxn_in_0(gt_rxn_in_0),
        .gt_txp_out_0(gt_txp_out_0), .gt_txn_out_0(gt_txn_out_0),
        .gt_rxp_in_1(gt_rxp_in_1), .gt_rxn_in_1(gt_rxn_in_1),
        .gt_txp_out_1(gt_txp_out_1), .gt_txn_out_1(gt_txn_out_1),
        .DAC_IQ_RX(m00_axis_tdata), .adc_valid(m00_axis_tvalid),
        .clk_feedback(data_clk2), .feedback_arst_n(link_arst_n),
        .feedback_dac_ready(s30_axis_tready), .feedback_dac_data(s30_axis_tdata),
        .feedback_dac_valid(s30_axis_tvalid),
        .feedback_status_ps(feedback_status_ps), .feedback_events_ps(feedback_events_ps),
        .feedback_sent_ps(feedback_sent_ps), .overflow_error_fast(),
        .frame_toggle(main_frame_toggle)
    );
    assign led[0] = mtime_start;
    assign led[1] = s30_axis_tready;
    assign led[2] = config_done;
    assign led[3] = main_frame_toggle;
endmodule
`default_nettype wire
