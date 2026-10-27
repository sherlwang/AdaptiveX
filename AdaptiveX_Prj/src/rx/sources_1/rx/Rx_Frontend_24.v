`timescale 1ns / 1ps
`default_nettype none

// Rate acquisition and fixed-phase matched RRC. No sampling-phase estimator.
module Rx_Frontend_24 #(
    parameter integer ADC_INPUT_FRAC = 13,
    parameter integer AUTO_MODE      = 0,
    parameter integer ENABLE_PHASE   = 0,
    parameter integer ENABLE_BLIND_DEBUG_DATA = 0
) (
    input wire clk_400M,
    input wire clk_200M,
    input wire rst_n,
    input wire [3:0] phy_ploy,
    input wire [12 * 16 - 1:0] adc_data,
    input wire adc_valid,
    output wire phase_update,
    output wire [3:0] sample_delay,
    output wire [23:0] phase_frame_idx,
    output wire phase_locked,
    output wire sync_rst_n,
    output wire [8 * 16 - 1:0] dout_i,
    output wire [8 * 16 - 1:0] dout_q,
    output wire dout_v,
    output wire [3:0] dout_ploy,
    output wire rate_locked,
    output wire acquire_error,
    output wire overflow_error_fast,
    output wire rate_ai_valid, rate_ai_busy, rate_ai_accepted, rate_ai_fault,
    output wire [3:0] rate_ai_p,
    output wire [31:0] rate_ai_confidence,
    output wire [63:0] rate_ai_sample_idx,
    output wire blind_summary_v,
    output wire [3:0] blind_window_p0, blind_window_p1, blind_window_p2,
    output wire [2:0] blind_window_valid, blind_window_accepted,
    output wire [3:0] blind_frame_p,
    output wire blind_frame_p_valid,
    output wire [383:0] blind_debug_data_i, blind_debug_data_q,
    output wire blind_debug_data_v, blind_debug_frame_start,
    output wire [2:0] blind_debug_window_active, blind_debug_window_start,
    output wire blind_debug_ready,
    output wire [3:0] blind_debug_p0, blind_debug_p1, blind_debug_p2,
    output wire [2:0] blind_debug_result_valid, blind_debug_accepted,
    output wire [3:0] blind_debug_frame_p,
    output wire blind_debug_frame_p_valid
);

    wire [24 * 16 - 1:0] rate_dout;
    wire rate_dout_v;
    wire [24 * 16 - 1:0] ddc_dout_i;
    wire [24 * 16 - 1:0] ddc_dout_q;
    wire ddc_dout_v;
    wire [383:0] phase_dout_i;
    wire [383:0] phase_dout_q;
    wire phase_dout_v;

    wire [3:0] phase_ploy;

    ////////////////////////// Logic //////////////////////////

    Rate_Convert_Rx12to24 u_Rate_Convert_Rx12to24 (
        .clk_400M      (clk_400M),
        .clk_200M      (clk_200M),
        .rst_n         (rst_n),
        .din           (adc_data),
        .din_v         (adc_valid),
        .dout          (rate_dout),
        .dout_v        (rate_dout_v),
        .overflow_error(overflow_error_fast)
    );

    DDC_24ploy #(
        .INPUT_FRAC(ADC_INPUT_FRAC)
    ) u_DDC_24ploy (
        .clk   (clk_200M),
        .rst_n (rst_n),
        .din   (rate_dout),
        .din_v (rate_dout_v),
        .dout_i(ddc_dout_i),
        .dout_q(ddc_dout_q),
        .dout_v(ddc_dout_v)
    );

    generate
        if (AUTO_MODE != 0) begin : auto_rate
            wire [63:0] write_idx;
            wire [63:0] aux_read_idx;
            wire [63:0] aux_dout_idx;
            wire aux_read;
            wire aux_dout_v;
            wire descriptor_v;
            wire buffer_error;
            wire rate_error;
            wire [383:0] aux_i;
            wire [383:0] aux_q;
            wire [63:0] descriptor_idx;
            wire [63:0] descriptor_ploy_idx;
            wire [3:0] descriptor_ploy;
            wire [3:0] descriptor_delay;
            wire observe_group_v, observe_window_v, observe_result_v, observe_confirm_v, observe_cancel_all;
            wire [31:0] observe_group_id, observe_window_group, observe_result_group, observe_confirm_group;
            wire [63:0] observe_group_anchor, observe_window_idx, observe_result_idx, observe_confirm_anchor;
            wire [3:0] observe_group_p, observe_result_p, observe_confirm_p;
            wire [1:0] observe_window_slot, observe_result_slot;
            wire observe_result_accepted;
            Rx_Rate_Acquire u_acquire (
                .clk                (clk_200M),
                .rst_n              (rst_n),
                .write_idx          (write_idx),
                .din_i              (ddc_dout_i),
                .din_q              (ddc_dout_q),
                .din_v              (ddc_dout_v),
                .aux_read           (aux_read),
                .aux_read_idx       (aux_read_idx),
                .aux_dout_i         (aux_i),
                .aux_dout_q         (aux_q),
                .aux_dout_v         (aux_dout_v),
                .aux_dout_idx       (aux_dout_idx),
                .descriptor_v       (descriptor_v),
                .descriptor_idx     (descriptor_idx),
                .descriptor_ploy_idx(descriptor_ploy_idx),
                .descriptor_ploy    (descriptor_ploy),
                .descriptor_delay   (descriptor_delay),
                .rate_locked        (rate_locked),
                .error              (rate_error),
                .ai_valid(rate_ai_valid), .ai_busy(rate_ai_busy),
                .ai_accepted(rate_ai_accepted), .ai_fault(rate_ai_fault),
                .ai_p(rate_ai_p), .ai_confidence(rate_ai_confidence),
                .ai_sample_idx(rate_ai_sample_idx),
                .observe_group_v(observe_group_v), .observe_group_id(observe_group_id),
                .observe_group_anchor(observe_group_anchor), .observe_group_p(observe_group_p),
                .observe_window_v(observe_window_v), .observe_window_group(observe_window_group),
                .observe_window_slot(observe_window_slot), .observe_window_idx(observe_window_idx),
                .observe_result_v(observe_result_v), .observe_result_group(observe_result_group),
                .observe_result_slot(observe_result_slot), .observe_result_idx(observe_result_idx),
                .observe_result_p(observe_result_p), .observe_result_accepted(observe_result_accepted),
                .observe_confirm_v(observe_confirm_v), .observe_confirm_group(observe_confirm_group),
                .observe_confirm_anchor(observe_confirm_anchor), .observe_confirm_p(observe_confirm_p),
                .observe_cancel_all(observe_cancel_all)
            );
            rx_blindrate_observer #(.ENABLE_DEBUG_DATA(ENABLE_BLIND_DEBUG_DATA)) u_blind_observer (
                .clk(clk_200M), .rst_n(rst_n), .ddc_i(ddc_dout_i), .ddc_q(ddc_dout_q),
                .ddc_v(ddc_dout_v), .ddc_write_idx(write_idx),
                .group_v(observe_group_v), .group_id(observe_group_id),
                .group_anchor(observe_group_anchor), .group_p(observe_group_p),
                .window_v(observe_window_v), .window_group(observe_window_group),
                .window_slot(observe_window_slot), .window_idx(observe_window_idx),
                .result_v(observe_result_v), .result_group(observe_result_group),
                .result_slot(observe_result_slot), .result_idx(observe_result_idx),
                .result_p(observe_result_p), .result_accepted(observe_result_accepted),
                .confirm_v(observe_confirm_v), .confirm_group(observe_confirm_group),
                .confirm_anchor(observe_confirm_anchor), .confirm_p(observe_confirm_p),
                .cancel_all(observe_cancel_all),
                .summary_v(blind_summary_v), .window_p0(blind_window_p0), .window_p1(blind_window_p1),
                .window_p2(blind_window_p2), .window_valid(blind_window_valid),
                .window_accepted(blind_window_accepted), .frame_p(blind_frame_p), .frame_p_valid(blind_frame_p_valid),
                .debug_data_i(blind_debug_data_i), .debug_data_q(blind_debug_data_q),
                .debug_data_v(blind_debug_data_v), .debug_frame_start(blind_debug_frame_start),
                .debug_window_active(blind_debug_window_active), .debug_window_start(blind_debug_window_start),
                .debug_ready(blind_debug_ready), .debug_p0(blind_debug_p0),
                .debug_p1(blind_debug_p1), .debug_p2(blind_debug_p2),
                .debug_result_valid(blind_debug_result_valid), .debug_accepted(blind_debug_accepted),
                .debug_frame_p(blind_debug_frame_p), .debug_frame_p_valid(blind_debug_frame_p_valid)
            );
            Rx_DDC_Buffer u_buffer (
                .clk                (clk_200M),
                .rst_n              (rst_n),
                .din_i              (ddc_dout_i),
                .din_q              (ddc_dout_q),
                .din_v              (ddc_dout_v),
                .descriptor_v       (descriptor_v),
                .descriptor_idx     (descriptor_idx),
                .descriptor_ploy_idx(descriptor_ploy_idx),
                .descriptor_ploy    (descriptor_ploy),
                .descriptor_delay   (descriptor_delay),
                .aux_read           (aux_read),
                .aux_read_idx       (aux_read_idx),
                .aux_dout_i         (aux_i),
                .aux_dout_q         (aux_q),
                .aux_dout_v         (aux_dout_v),
                .aux_dout_idx       (aux_dout_idx),
                .write_idx          (write_idx),
                .dout_i             (phase_dout_i),
                .dout_q             (phase_dout_q),
                .dout_v             (phase_dout_v),
                .dout_ploy          (phase_ploy),
                .phase_applied      (phase_update),
                .applied_idx        (phase_frame_idx),
                .active_delay       (sample_delay),
                .phase_locked       (phase_locked),
                .error              (buffer_error)
            );
            assign sync_rst_n = rst_n;
            assign acquire_error = buffer_error || rate_error;
        end else begin : no_phase_buffer
            assign rate_ai_valid=0; assign rate_ai_busy=0; assign rate_ai_accepted=0;
            assign rate_ai_fault=0; assign rate_ai_p=0; assign rate_ai_confidence=0;
            assign rate_ai_sample_idx=0;
            assign phase_ploy = phy_ploy;
            assign rate_locked = 1'b1;
            assign acquire_error = 1'b0;
            assign phase_dout_i = ddc_dout_i;
            assign phase_dout_q = ddc_dout_q;
            assign phase_dout_v = ddc_dout_v;
            assign sync_rst_n = rst_n;
            assign phase_locked = 1'b1;
            assign phase_update = 1'b0;
            assign sample_delay = 4'd0;
            assign phase_frame_idx = 24'd0;
        end
    endgenerate
    generate if (AUTO_MODE == 0) begin : no_blind_observation
        assign blind_summary_v=0; assign blind_window_p0=0; assign blind_window_p1=0; assign blind_window_p2=0;
        assign blind_window_valid=0; assign blind_window_accepted=0; assign blind_frame_p=0; assign blind_frame_p_valid=0;
        assign blind_debug_data_i=0; assign blind_debug_data_q=0; assign blind_debug_data_v=0;
        assign blind_debug_frame_start=0; assign blind_debug_window_active=0; assign blind_debug_window_start=0;
        assign blind_debug_ready=0; assign blind_debug_p0=0; assign blind_debug_p1=0; assign blind_debug_p2=0;
        assign blind_debug_result_valid=0; assign blind_debug_accepted=0;
        assign blind_debug_frame_p=0; assign blind_debug_frame_p_valid=0;
    end endgenerate
    RRC_Rx_Shared #(
        .DYNAMIC_MODE(AUTO_MODE)
    ) u_RRC_Rx_Shared (
        .clk      (clk_200M),
        .rst_n    (sync_rst_n),
        .phy_ploy (phase_ploy),
        .din_i    (phase_dout_i),
        .din_q    (phase_dout_q),
        .din_v    (phase_dout_v),
        .dout_i   (dout_i),
        .dout_q   (dout_q),
        .dout_v   (dout_v),
        .dout_ploy(dout_ploy)
    );



endmodule
`default_nettype wire
