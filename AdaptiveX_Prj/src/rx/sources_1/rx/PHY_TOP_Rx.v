`timescale 1ns / 1ps
`default_nettype none

// Nine-mode receive PHY; LDPC decoding and descrambling use a replaceable core.
module PHY_TOP_Rx #(
    parameter integer AUTO_MODE        = 1,
    parameter integer ENABLE_RECOMMEND = 1,
    parameter integer ENABLE_ILA       = 1
) (
    input wire clk_400M,
    input wire clk_200M,
    input wire clk_ldpc,
    input wire rst_n,
    input wire [3:0] phy_ploy,
    input wire [1:0] modulation,
    input wire [191:0] adc_data,
    input wire adc_valid,
    input wire [4:0] mov_zf_window_len,
    output wire [31:0] coded_bits,
    output wire [255:0] coded_llr,
    output wire [5:0] coded_width,
    output wire coded_v,
    output wire coded_start,
    output wire [2:0] coded_block,
    output wire overflow_error_fast,
    output wire [31:0] dout,
    output wire dout_v,
    output wire [5:0] dout_width,
    output wire decode_done,
    output wire decode_ok,
    output wire [3:0] iterations,
    output wire [3:0] group_ok,
    output wire ldpc_overflow_error,
    output wire ldpc_mode_error,
    output wire [127:0] to_cone_i,
    output wire [127:0] to_cone_q,
    output wire to_cone_v,
    output wire [3:0] to_cone_ploy,
    output wire [1:0] to_cone_modulation,
    output wire [31:0] to_cone_frame,
    output reg [3:0] detected_p,
    output reg [1:0] detected_m,
    output wire rate_locked,
    output wire acquire_error,
    output wire [3:0] recommended_mode,
    output wire recommendation_v,
    output wire [31:0] recommendation_frame,
    output wire [31:0] recommendation_confidence,
    output wire [10:0] recommendation_fault,
    output wire [3:0] raw_recommended_mode,
    output wire raw_recommendation_v,
    output wire raw_recommendation_fallback,
    output wire [3:0] raw_recommendation_reason,
    output wire [31:0] raw_recommendation_frame,
    output wire [3:0] recommendation_current_mode,
    output wire [1:0] recommendation_action,
    output wire [3:0] recommendation_reason,
    output wire ai_link_lost
);

    reg [3:0] mode_cfg;
    reg [1:0] mod_cfg;
    wire frontend_rst_n;
    wire cfo_rst_n;
    wire fde_rst_n;
    wire nlms_rst_n;
    wire demap_rst_n;
    wire legal_mode;
    wire [127:0] frontend_dout_i;
    wire [127:0] frontend_dout_q;
    wire frontend_dout_v;
    wire phase_update;
    wire [23:0] phase_frame_idx;
    wire phase_locked;
    wire sync_rst_n;
    wire [3:0] sample_delay;
    // One atomic BlindRate summary per source-frame transaction. Source tags
    // stay inside the observer; only P and validity are exposed to the ILA.
    wire blind_summary_v_obs;
    wire [3:0] blind_window_p0_obs;
    wire [3:0] blind_window_p1_obs;
    wire [3:0] blind_window_p2_obs;
    wire [2:0] blind_window_valid_obs;
    wire [2:0] blind_window_accepted_obs;
    wire [3:0] blind_frame_p_obs;
    wire blind_frame_p_valid_obs;
    (* KEEP = "TRUE", DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg blind_summary_v;
    (* KEEP = "TRUE", DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg [3:0] blind_window_p0;
    (* KEEP = "TRUE", DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg [3:0] blind_window_p1;
    (* KEEP = "TRUE", DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg [3:0] blind_window_p2;
    (* KEEP = "TRUE", DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg [2:0] blind_window_valid;
    (* KEEP = "TRUE", DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg [2:0] blind_window_accepted;
    (* KEEP = "TRUE", DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg [3:0] blind_frame_p;
    (* KEEP = "TRUE", DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg blind_frame_p_valid;
    wire [127:0] sync_dout_i;
    wire [127:0] sync_dout_q;
    wire sync_dout_v;
    wire sync_dout_start;
    wire [127:0] cfo_dout_i;
    wire [127:0] cfo_dout_q;
    wire cfo_dout_v;
    wire cfo_dout_start;
    wire [127:0] window_dout_i;
    wire [127:0] window_dout_q;
    wire window_dout_v;
    wire [127:0] fde_dout_i;
    wire [127:0] fde_dout_q;
    wire fde_dout_v;
    wire [127:0] payload_dout_i;
    wire [127:0] payload_dout_q;
    wire payload_dout_v;
    wire payload_dout_start;
    wire [2:0] payload_dout_blk;

    wire [127:0] select_dout_i;
    wire [127:0] select_dout_q;
    wire select_dout_v;
    wire select_dout_pilot;
    wire select_dout_start;
    wire [2:0] select_dout_blk;
    wire [1:0] pilot_mode_dout;
    wire pilot_mode_v;
    wire [3:0] frontend_ploy;
    wire [3:0] sync_ploy;
    wire [3:0] cfo_ploy;
    wire [3:0] window_ploy;
    wire [3:0] fde_ploy;
    wire [3:0] select_ploy;
    wire [3:0] payload_ploy;
    wire [1:0] payload_modulation;
    wire window_start;
    wire [61:0] sync_peak;
    wire [61:0] sync_threshold;
    wire [23:0] sync_frame_idx;
    wire signed [31:0] cfo_estimate_step;
    wire cfo_estimate_v;
    wire signed [24:0] training_i;
    wire signed [24:0] training_q;
    wire [10:0] training_idx;
    wire training_v;
    wire [3:0] training_ploy;
    reg [31:0] pilot_frame_count;
    reg [31:0] source_frame_id;
    wire [31:0] cfo_frame_id, cfo_estimate_frame_id, window_frame_id;
    wire [31:0] fde_frame_id, training_frame_id, select_frame_id, payload_frame_id, coded_frame_id;
    wire [31:0] decode_frame_id;
    wire [2:0] decode_block_id;
    wire decode_tag_valid, decode_tag_fault;
    wire [31:0] raw_confidence;
    // Dedicated result observation registers. Preserve the real FFs and their
    // Q nets, rather than relying on aliases of packed or synthesized nets.
    (* KEEP = "TRUE", MARK_DEBUG = "TRUE", DONT_TOUCH = "TRUE" *) reg ada_result_valid;
    (* KEEP = "TRUE", MARK_DEBUG = "TRUE", DONT_TOUCH = "TRUE" *) reg [3:0] ada_recommend_mode;
    (* KEEP = "TRUE", MARK_DEBUG = "TRUE", DONT_TOUCH = "TRUE" *) reg [31:0] ada_confidence_q20;
    always @(posedge clk_200M) begin
        if(!fde_rst_n) begin
            ada_result_valid<=0;ada_recommend_mode<=0;ada_confidence_q20<=0;
        end else begin
            ada_result_valid<=raw_recommendation_v;
            if(raw_recommendation_v) begin
                ada_recommend_mode<=raw_recommended_mode;
                ada_confidence_q20<=raw_confidence;
            end
        end
    end
    wire [3:0] raw_current_mode;
    wire [359:0] ai_feature_debug;
    wire [287:0] ai_logits_debug;
    wire [8:0] ai_feature_valid;
    wire ai_busy, ai_fallback_active;
    wire [31:0] ai_sync_age, ai_result_count, ai_fallback_count;
    wire [4:0] ai_pending_count;
    wire rate_ai_valid,rate_ai_busy,rate_ai_accepted,rate_ai_fault;
    wire [3:0] rate_ai_p;
    wire [31:0] rate_ai_confidence;
    wire [63:0] rate_ai_sample_idx;
    always @(posedge clk_200M) begin
        if(!rst_n) source_frame_id<=0;
        else if(sync_dout_start) source_frame_id<=source_frame_id+1'b1;
    end
    reg [31:0] pilot_frame_id;
    reg [3:0] pilot_frame_ploy;


    assign legal_mode = (phy_ploy == 2 || phy_ploy == 4 || phy_ploy == 8) && modulation <= 2;
    always @(posedge clk_200M) begin
        if (!rst_n) begin
            mode_cfg <= legal_mode ? phy_ploy : 4'd2;
            mod_cfg  <= legal_mode ? modulation : 2'd0;
        end
    end
    // Each region releases reset on its own local clock registers.
    Rx_PHY_Reset u_frontend_reset (
        .clk   (clk_200M),
        .rst_n (rst_n),
        .dout_n(frontend_rst_n)
    );
    Rx_PHY_Reset u_cfo_reset (
        .clk   (clk_200M),
        .rst_n (rst_n),
        .dout_n(cfo_rst_n)
    );
    Rx_PHY_Reset u_fde_reset (
        .clk   (clk_200M),
        .rst_n (rst_n),
        .dout_n(fde_rst_n)
    );
    Rx_PHY_Reset u_nlms_reset (
        .clk   (clk_200M),
        .rst_n (rst_n),
        .dout_n(nlms_rst_n)
    );
    Rx_PHY_Reset u_demap_reset (
        .clk   (clk_200M),
        .rst_n (rst_n),
        .dout_n(demap_rst_n)
    );

    assign to_cone_i = payload_dout_i;
    assign to_cone_q = payload_dout_q;
    assign to_cone_v = payload_dout_v;
    assign to_cone_ploy = payload_ploy;
    assign to_cone_modulation = payload_modulation;
    assign to_cone_frame = payload_frame_id;

    // The result belongs to this pilot's frame, not to the latest front end.
    always @(posedge clk_200M) begin
        if (!nlms_rst_n) begin
            pilot_frame_count <= 0;
            pilot_frame_id <= 0;
            pilot_frame_ploy <= 2;
            detected_p <= 0;
            detected_m <= 3;
        end else begin
            if (select_dout_v && select_dout_pilot && select_dout_blk == 0) begin
                pilot_frame_id <= select_frame_id;
                pilot_frame_count <= pilot_frame_count + 1'b1;
                pilot_frame_ploy <= select_ploy;
            end
            if (pilot_mode_v) begin
                detected_p <= pilot_frame_ploy;
                detected_m <= pilot_mode_dout;
            end
        end
    end

    ////////////////////////// Logic //////////////////////////

    Rx_Frontend_24 #(
        .ENABLE_PHASE(1),
        .AUTO_MODE   (AUTO_MODE)
    ) u_Rx_Frontend_24 (
        .clk_400M           (clk_400M),
        .clk_200M           (clk_200M),
        .rst_n              (frontend_rst_n),
        .phy_ploy           (mode_cfg),
        .adc_data           (adc_data),
        .adc_valid          (adc_valid),
        .dout_i             (frontend_dout_i),
        .dout_q             (frontend_dout_q),
        .dout_v             (frontend_dout_v),
        .dout_ploy          (frontend_ploy),
        .rate_locked        (rate_locked),
        .acquire_error      (acquire_error),
        .phase_update       (phase_update),
        .sample_delay       (sample_delay),
        .phase_frame_idx    (phase_frame_idx),
        .phase_locked       (phase_locked),
        .sync_rst_n         (sync_rst_n),
        .overflow_error_fast(overflow_error_fast),
        .rate_ai_valid(rate_ai_valid), .rate_ai_busy(rate_ai_busy),
        .rate_ai_accepted(rate_ai_accepted), .rate_ai_fault(rate_ai_fault),
        .rate_ai_p(rate_ai_p), .rate_ai_confidence(rate_ai_confidence),
        .rate_ai_sample_idx(rate_ai_sample_idx),
        .blind_summary_v(blind_summary_v_obs),
        .blind_window_p0(blind_window_p0_obs),
        .blind_window_p1(blind_window_p1_obs),
        .blind_window_p2(blind_window_p2_obs),
        .blind_window_valid(blind_window_valid_obs),
        .blind_window_accepted(blind_window_accepted_obs),
        .blind_frame_p(blind_frame_p_obs),
        .blind_frame_p_valid(blind_frame_p_valid_obs)
    );

    Rx_Header_Sync u_Rx_Header_Sync (
        .clk                (clk_200M),
        .rst_n              (sync_rst_n),
        .phy_ploy           (frontend_ploy),
        .source_base_idx    (64'd0),
        .phase_locked       (phase_locked),
        .phase_update_in    (phase_update),
        .confirmed_frame_idx(phase_frame_idx),
        .sample_delay_in    (sample_delay),
        .phase_update       (),
        .sample_delay       (),
        .phase_frame_idx    (),
        .din_i              (frontend_dout_i),
        .din_q              (frontend_dout_q),
        .din_v              (frontend_dout_v),
        .dout_i             (sync_dout_i),
        .dout_q             (sync_dout_q),
        .dout_v             (sync_dout_v),
        .dout_start         (sync_dout_start),
        .dout_ploy          (sync_ploy),
        .dout_frame_idx     (sync_frame_idx),
        .frame_peak         (sync_peak),
        .frame_threshold    (sync_threshold)
    );

    Rx_Frequency_Correct #(
        .DYNAMIC_MODE(AUTO_MODE)
    ) u_Rx_Frequency_Correct (
        .clk          (clk_200M),
        .rst_n        (cfo_rst_n),
        .phy_ploy     (sync_ploy),
        .din_i        (sync_dout_i),
        .din_q        (sync_dout_q),
        .din_v        (sync_dout_v),
        .din_start    (sync_dout_start),
        .din_frame_id (source_frame_id),
        .dout_frame_id(cfo_frame_id),
        .estimate_frame_id(cfo_estimate_frame_id),
        .dout_i       (cfo_dout_i),
        .dout_q       (cfo_dout_q),
        .dout_v       (cfo_dout_v),
        .dout_start   (cfo_dout_start),
        .dout_ploy    (cfo_ploy),
        .estimate_step(cfo_estimate_step),
        .estimate_v   (cfo_estimate_v)
    );

    Rx_Block_Window #(
        .DYNAMIC_MODE(AUTO_MODE)
    ) u_Rx_Block_Window (
        .clk       (clk_200M),
        .rst_n     (cfo_rst_n),
        .phy_ploy  (cfo_ploy),
        .din_i     (cfo_dout_i),
        .din_q     (cfo_dout_q),
        .din_v     (cfo_dout_v),
        .din_start (cfo_dout_start),
        .din_frame_id(cfo_frame_id),
        .dout_frame_id(window_frame_id),
        .dout_i    (window_dout_i),
        .dout_q    (window_dout_q),
        .dout_v    (window_dout_v),
        .dout_start(window_start),
        .dout_ploy (window_ploy)
    );

    Rx_FDE_Core_8 u_Rx_FDE_Core_8 (
        .clk          (clk_200M),
        .rst_n        (fde_rst_n),
        .phy_ploy     (window_ploy),
        .mov_zf_window_len(mov_zf_window_len),
        .din_i        (window_dout_i),
        .din_q        (window_dout_q),
        .din_v        (window_dout_v),
        .din_start    (window_start),
        .din_frame_id(window_frame_id),
        .dout_frame_id(fde_frame_id),
        .training_frame_id(training_frame_id),
        .dout_i       (fde_dout_i),
        .dout_q       (fde_dout_q),
        .dout_v       (fde_dout_v),
        .dout_ploy    (fde_ploy),
        .training_i   (training_i),
        .training_q   (training_q),
        .training_idx (training_idx),
        .training_v   (training_v),
        .training_ploy(training_ploy)
    );

    Rx_Payload_Select #(
        .DYNAMIC_MODE(AUTO_MODE)
    ) u_Rx_Payload_Select (
        .clk       (clk_200M),
        .rst_n     (fde_rst_n),
        .phy_ploy  (fde_ploy),
        .din_i     (fde_dout_i),
        .din_q     (fde_dout_q),
        .din_v     (fde_dout_v),
        .din_frame_id(fde_frame_id),
        .dout_frame_id(select_frame_id),
        .dout_i    (select_dout_i),
        .dout_q    (select_dout_q),
        .dout_v    (select_dout_v),
        .dout_pilot(select_dout_pilot),
        .dout_start(select_dout_start),
        .dout_blk  (select_dout_blk),
        .dout_ploy (select_ploy)
    );

    // Identify M before Normalize releases this frame to NLMS Update.
    Rx_Pilot_Mode u_pilot_mode (
        .clk      (clk_200M),
        .rst_n    (nlms_rst_n),
        .phy_ploy (select_ploy),
        .din_i    (select_dout_i),
        .din_q    (select_dout_q),
        .din_v    (select_dout_v),
        .din_pilot(select_dout_pilot),
        .din_blk  (select_dout_blk),
        .dout     (pilot_mode_dout),
        .dout_v   (pilot_mode_v)
    );

    Rx_NLMS u_Rx_NLMS (
        .clk                (clk_200M),
        .rst_n              (nlms_rst_n),
        .phy_ploy           (select_ploy),
        .modulation         (mod_cfg),
        .mode_update        (pilot_mode_v),
        .detected_modulation(pilot_mode_dout),
        .din_i              (select_dout_i),
        .din_q              (select_dout_q),
        .din_v              (select_dout_v),
        .din_pilot          (select_dout_pilot),
        .din_start          (select_dout_start),
        .din_blk            (select_dout_blk),
        .din_frame_id       (select_frame_id),
        .dout_frame_id      (payload_frame_id),
        .dout_i             (payload_dout_i),
        .dout_q             (payload_dout_q),
        .dout_v             (payload_dout_v),
        .dout_start         (payload_dout_start),
        .dout_blk           (payload_dout_blk),
        .dout_ploy          (payload_ploy),
        .dout_modulation    (payload_modulation)
    );

    Rx_Demap_9 u_Rx_Demap_9 (
        .clk        (clk_200M),
        .rst_n      (demap_rst_n),
        .phy_ploy   (payload_ploy),
        .modulation (payload_modulation),
        .din_i      (payload_dout_i),
        .din_q      (payload_dout_q),
        .din_v      (payload_dout_v),
        .din_block  (payload_dout_blk),
        .din_frame_id(payload_frame_id),
        .coded_frame_id(coded_frame_id),
        .coded_bits (coded_bits),
        .coded_llr  (coded_llr),
        .coded_width(coded_width),
        .coded_v    (coded_v),
        .coded_start(coded_start),
        .coded_block(coded_block)
    );

    PHY_LDPC_DEC #(
        .DYNAMIC_WIDTH(1)
    ) u_PHY_LDPC_DEC (
        .clk           (clk_200M),
        .clk_core      (clk_ldpc),
        .rst_n         (rst_n),
        .phy_ploy      (mode_cfg),
        .phy_mod       (mod_cfg),
        .din_width     (coded_width),
        .din_llr       (coded_llr),
        .din_v         (coded_v),
        .dout          (dout),
        .dout_v        (dout_v),
        .dout_width    (dout_width),
        .decode_done   (decode_done),
        .decode_ok     (decode_ok),
        .iterations    (iterations),
        .group_ok      (group_ok),
        .overflow_error(ldpc_overflow_error),
        .mode_error    (ldpc_mode_error)
    );

    rx_ai_decode_tags u_ai_decode_tags (
        .clk(clk_200M), .rst_n(rst_n), .coded_v(coded_v), .coded_start(coded_start),
        .coded_frame_id(coded_frame_id), .coded_block(coded_block), .decode_done(decode_done),
        .decode_frame_id(decode_frame_id), .decode_block(decode_block_id),
        .tag_valid(decode_tag_valid), .fault(decode_tag_fault)
    );
    generate
        if (ENABLE_RECOMMEND != 0) begin : recommendation
            wire [15:0] missed_before;
            wire frame_gap_fault;
            Rx_Frame_Gap u_frame_gap (
                .clk          (clk_200M),
                .rst_n        (fde_rst_n),
                .commit       (sync_dout_start),
                .frame_idx    (sync_frame_idx),
                .missed_before(missed_before),
                .fault        (frame_gap_fault)
            );
            rx_ai_switch u_rx_ai_switch (
                .clk(clk_200M),
                .rst_n(fde_rst_n),
                .sync_p(sync_ploy),
                .cfo_p(cfo_ploy),
                .h_p(training_ploy),
                .pilot_p(select_ploy),
                .mode_update(pilot_mode_v),
                .mode_frame_id(pilot_frame_id),
                .mode_p(pilot_frame_ploy),
                .mode_m(pilot_mode_dout),
                .frame_start(sync_dout_start),
                .sync_frame_id(source_frame_id), .cfo_frame_id(cfo_frame_id),
                .cfo_estimate_frame_id(cfo_estimate_frame_id), .h_frame_id(training_frame_id),
                .pilot_frame_id(select_frame_id), .llr_frame_id(coded_frame_id),
                .decode_frame_id(decode_frame_id), .decode_block(decode_block_id),
                .sync_peak(sync_peak),
                .sync_threshold(sync_threshold),
                .missed_before(missed_before),
                .cfo_step(cfo_estimate_step),
                .cfo_valid(cfo_estimate_v),
                .cfo_i(cfo_dout_i),
                .cfo_q(cfo_dout_q),
                .cfo_v(cfo_dout_v),
                .cfo_start(cfo_dout_start),
                .h_i(training_i),
                .h_q(training_q),
                .h_index(training_idx),
                .h_valid(training_v),
                .pilot_i(select_dout_i),
                .pilot_q(select_dout_q),
                .pilot_v(select_dout_v),
                .pilot_flag(select_dout_pilot),
                .pilot_block(select_dout_blk),
                .llr(coded_llr),
                .llr_width(coded_width),
                .llr_v(coded_v),
                .llr_start(coded_start),
                .llr_block(coded_block),
                .decode_done(decode_done && decode_tag_valid),
                .decode_ok(decode_ok),
                .phy_fault(acquire_error || ldpc_overflow_error || ldpc_mode_error || frame_gap_fault || decode_tag_fault),
                .ai_result_valid(raw_recommendation_v),
                .ai_mode_predict(raw_recommended_mode),
                .ai_confidence(raw_confidence),
                .ai_frame_id(raw_recommendation_frame),
                .ai_fault(recommendation_fault),
                .skipped_vectors(ai_fallback_count),
                .feature_valid(ai_feature_valid),
                .feature_debug(ai_feature_debug),
                .current_mode_debug(raw_current_mode),
                .logits_debug(ai_logits_debug),
                .inference_busy(ai_busy),
                .ai_result_fallback(raw_recommendation_fallback),
                .ai_result_reason(raw_recommendation_reason),
                .fallback_active(ai_fallback_active), .link_lost(ai_link_lost),
                .sync_age(ai_sync_age), .result_count(ai_result_count), .pending_count(ai_pending_count)
            );
            // Compatibility observation ports now expose the raw successful
            // Ada transaction directly. There is no mode confirmation policy
            // or mode-switch controller in the receiver.
            assign recommendation_v=raw_recommendation_v;
            assign recommended_mode=raw_recommended_mode;
            assign recommendation_frame=raw_recommendation_frame;
            assign recommendation_confidence=raw_confidence;
            assign recommendation_current_mode=raw_current_mode;
            assign recommendation_action=2'd0;
            assign recommendation_reason=4'd0;
        end else begin : no_recommendation
            assign recommendation_v = 1'b0;
            assign recommended_mode = 4'd0;
            assign recommendation_frame = 32'd0;
            assign recommendation_confidence = 32'd0;
            assign recommendation_fault = 11'd0;
            assign raw_recommended_mode=0; assign raw_recommendation_v=0;
            assign raw_recommendation_fallback=0; assign raw_recommendation_reason=0;
            assign raw_recommendation_frame=0; assign recommendation_current_mode=0;
            assign recommendation_action=0; assign recommendation_reason=0; assign ai_link_lost=0;
            assign raw_confidence=0; assign raw_current_mode=0;
            assign ai_feature_debug=0; assign ai_logits_debug=0; assign ai_feature_valid=0;
            assign ai_busy=0; assign ai_fallback_active=0; assign ai_sync_age=0;
            assign ai_result_count=0; assign ai_fallback_count=0; assign ai_pending_count=0;
        end
    endgenerate

    // Keep named observation FFs so implemented ILA names remain readable.
    // These registers observe the transaction and never drive the PHY mode.
    always @(posedge clk_200M) begin
        if (!frontend_rst_n) begin
            blind_summary_v <= 1'b0;
            blind_window_p0 <= 0; blind_window_p1 <= 0; blind_window_p2 <= 0;
            blind_window_valid <= 0; blind_window_accepted <= 0;
            blind_frame_p <= 0; blind_frame_p_valid <= 0;
        end else begin
            blind_summary_v <= blind_summary_v_obs;
            if (blind_summary_v_obs) begin
                blind_window_p0 <= blind_window_p0_obs;
                blind_window_p1 <= blind_window_p1_obs;
                blind_window_p2 <= blind_window_p2_obs;
                blind_window_valid <= blind_window_valid_obs;
                blind_window_accepted <= blind_window_accepted_obs;
                blind_frame_p <= blind_frame_p_obs;
                blind_frame_p_valid <= blind_frame_p_valid_obs;
            end
        end
    end

    // Ada ILA/VIO retain their original 37-bit result interface. The separate
    // small BlindRate ILA contains only the four P values and validity bits.
    generate
        if (ENABLE_ILA != 0) begin : debug_capture
            // Probe successful Ada output only, with no packed status fields.
            ILA_Rx_AI_Result u_ila_ai (
                .clk(clk_200M),
                .probe0(ada_result_valid),
                .probe1(ada_recommend_mode),
                .probe2(ada_confidence_q20)
            );
            VIO_Rx_AI_Result u_vio_ai (
                .clk(clk_200M),
                .probe_in0(ada_result_valid),
                .probe_in1(ada_recommend_mode),
                .probe_in2(ada_confidence_q20)
            );
            ILA_Rx_BlindRate_Summary u_ila_blindrate (
                .clk(clk_200M),
                .probe0(blind_summary_v),
                .probe1(blind_window_p0),
                .probe2(blind_window_p1),
                .probe3(blind_window_p2),
                .probe4(blind_window_valid),
                .probe5(blind_window_accepted),
                .probe6(blind_frame_p),
                .probe7(blind_frame_p_valid)
            );
        end
    endgenerate

endmodule

(* KEEP_HIERARCHY = "yes" *)
module Rx_PHY_Reset (
    input wire clk,
    input wire rst_n,
    output wire dout_n
);
    (* ASYNC_REG = "TRUE", DONT_TOUCH = "TRUE" *) reg [2:0] release_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) release_q <= 0;
        else release_q <= {release_q[1:0], 1'b1};
    end
    assign dout_n = release_q[2];
endmodule
`default_nettype wire
