`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tx_feedback_receive
// Target Devices: xczu47dr-ffve1156-2-i
// Tool Versions: Vivado 2021.2 / Verilog-2001
// Description: Independent Rx2 feedback receiver and all six receive ILAs.
// ADC1/0 RFDC outputs twelve signed16 I/Q samples per 40.96-MHz clock.
// The RFDC performs the nominal -1.2-GHz DDC; no second PL mixer is used.
// arst_n is the board/RF-start reset, independent of business P/M changes.
//////////////////////////////////////////////////////////////////////////////////
module tx_feedback_receive #(
    parameter integer DEBUG_ILA = 1
)(
    input  wire                 clk_adc,
    input  wire                 clk_fast,
    input  wire                 clk_slow,
    input  wire                 arst_n,
    input  wire [191:0]         adc_i,
    input  wire [191:0]         adc_q,
    input  wire                 adc_i_v,
    input  wire                 adc_q_v,
    output wire                 packet_v,
    output wire [23:0]          packet24,
    output wire signed [31:0]   packet_cfo,
    output wire [3:0]           packet_pn,
    output wire [6:0]           packet_phase,
    output wire [31:0]          status,
    output wire [31:0]          received_count
);
    wire constellation_rst_n;
    wire rf_capture_rst_n;
    wire link_const_v;
    wire signed [15:0] link_const_i;
    wire signed [15:0] link_const_q;
    wire [5:0] link_const_index;

    reset_sync u_constellation_reset (
        .clk    (clk_slow),
        .arst_n (arst_n),
        .rst_n  (constellation_rst_n)
    );
    reset_sync u_rf_capture_reset (
        .clk    (clk_adc),
        .arst_n (arst_n),
        .rst_n  (rf_capture_rst_n)
    );

    tx_fb_receiver #(.DEBUG_ILA(DEBUG_ILA)) u_rx (
        .clk_adc        (clk_adc),
        .clk_fast       (clk_fast),
        .clk_slow       (clk_slow),
        .arst_n         (arst_n),
        .adc_i          (adc_i),
        .adc_q          (adc_q),
        .adc_valid      (adc_i_v && adc_q_v),
        .packet_v       (packet_v),
        .packet24       (packet24),
        .packet_cfo     (packet_cfo),
        .packet_pn      (packet_pn),
        .packet_phase   (packet_phase),
        .const_v        (link_const_v),
        .const_i        (link_const_i),
        .const_q        (link_const_q),
        .const_index    (link_const_index),
        .status         (status),
        .received_count (received_count)
    );

    // Preserve the established constellation names, widths and qualified hold.
    (* KEEP = "TRUE", MARK_DEBUG = "TRUE", DONT_TOUCH = "TRUE" *) reg const_v;
    (* KEEP = "TRUE", MARK_DEBUG = "TRUE", DONT_TOUCH = "TRUE" *) reg signed [15:0] const_i;
    (* KEEP = "TRUE", MARK_DEBUG = "TRUE", DONT_TOUCH = "TRUE" *) reg signed [15:0] const_q;
    (* KEEP = "TRUE", MARK_DEBUG = "TRUE", DONT_TOUCH = "TRUE" *) reg [5:0] const_index;
    always @(posedge clk_slow or negedge constellation_rst_n) begin
        if (!constellation_rst_n) begin
            const_v <= 1'b0;
            const_i <= 16'sd0;
            const_q <= 16'sd0;
            const_index <= 6'd0;
        end else begin
            const_v <= link_const_v;
            if (link_const_v) begin
                const_i <= link_const_i;
                const_q <= link_const_q;
                const_index <= link_const_index;
            end
        end
    end

    // These former local feedback-Tx6 slots retain their names and widths.
    // Tx4 uses a different 409.6-MHz clock and is observed by its own Tx ILA;
    // sampling that bus here would create an incoherent 40.96-MHz capture.
    (* KEEP = "TRUE", MARK_DEBUG = "TRUE", DONT_TOUCH = "TRUE" *) reg tx_dac_v;
    (* KEEP = "TRUE", MARK_DEBUG = "TRUE", DONT_TOUCH = "TRUE" *) reg tx_dac_ready;
    (* KEEP = "TRUE", MARK_DEBUG = "TRUE", DONT_TOUCH = "TRUE" *) reg [95:0] tx_dac_i;
    (* KEEP = "TRUE", MARK_DEBUG = "TRUE", DONT_TOUCH = "TRUE" *) reg [95:0] tx_dac_q;
    (* KEEP = "TRUE", MARK_DEBUG = "TRUE", DONT_TOUCH = "TRUE" *) reg [191:0] rx_adc_i;
    (* KEEP = "TRUE", MARK_DEBUG = "TRUE", DONT_TOUCH = "TRUE" *) reg [191:0] rx_adc_q;
    (* KEEP = "TRUE", MARK_DEBUG = "TRUE", DONT_TOUCH = "TRUE" *) reg rx_adc_i_v;
    (* KEEP = "TRUE", MARK_DEBUG = "TRUE", DONT_TOUCH = "TRUE" *) reg rx_adc_q_v;
    (* KEEP = "TRUE", MARK_DEBUG = "TRUE", DONT_TOUCH = "TRUE" *) reg rx_adc_v;
    always @(posedge clk_adc or negedge rf_capture_rst_n) begin
        if (!rf_capture_rst_n) begin
            tx_dac_v <= 1'b0;
            tx_dac_ready <= 1'b0;
            tx_dac_i <= 96'd0;
            tx_dac_q <= 96'd0;
            rx_adc_i <= 192'd0;
            rx_adc_q <= 192'd0;
            rx_adc_i_v <= 1'b0;
            rx_adc_q_v <= 1'b0;
            rx_adc_v <= 1'b0;
        end else begin
            tx_dac_v <= 1'b0;
            tx_dac_ready <= 1'b0;
            tx_dac_i <= 96'd0;
            tx_dac_q <= 96'd0;
            rx_adc_i <= adc_i;
            rx_adc_q <= adc_q;
            rx_adc_i_v <= adc_i_v;
            rx_adc_q_v <= adc_q_v;
            rx_adc_v <= adc_i_v && adc_q_v;
        end
    end

    generate if (DEBUG_ILA) begin: gen_boundary_ila
        (* DONT_TOUCH = "TRUE" *) ila_feedback_constellation u_ila_constellation (
            .clk    (clk_slow),
            .probe0 (const_v),
            .probe1 (const_i),
            .probe2 (const_q),
            .probe3 (const_index)
        );
        (* DONT_TOUCH = "TRUE" *) ila_feedback_rf u_ila_rf (
            .clk    (clk_adc),
            .probe0 (tx_dac_v),
            .probe1 (tx_dac_ready),
            .probe2 (tx_dac_i),
            .probe3 (tx_dac_q),
            .probe4 (rx_adc_i),
            .probe5 (rx_adc_q),
            .probe6 (rx_adc_i_v),
            .probe7 (rx_adc_q_v),
            .probe8 (rx_adc_v)
        );
    end endgenerate
endmodule
`default_nettype wire
