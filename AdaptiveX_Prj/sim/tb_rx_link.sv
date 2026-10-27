`timescale 1ns/1fs
module tb_rx_link;
    reg clk_fast = 0;
    reg clk_phy = 0;
    reg clk_ldpc = 0;
    reg rst_n = 0;
    reg adc_valid = 0;
    reg [191:0] adc_data = 0;
    reg [191:0] stimulus [0:131071];
    integer input_words = 69162;
    integer drain_clocks = 16000;
    integer mov_window = 5;
    integer cycle = 0;
    integer frame_count = 0;
    integer decode_count = 0;
    integer decode_bad = 0;
    integer recommendation_count = 0;
    integer n;
    integer f_coded;
    integer f_decoded;
    integer f_fde;
    integer f_window;
    integer f_nlms;
    integer f_events;
    integer f_summary;
    wire [31:0] coded_bits;
    wire [255:0] coded_llr;
    wire [5:0] coded_width;
    wire coded_valid;
    wire coded_start;
    wire [2:0] coded_block;
    wire [31:0] decoded_bits;
    wire [5:0] decoded_width;
    wire decoded_valid;
    wire decode_done;
    wire decode_ok;
    wire [3:0] detected_p;
    wire [1:0] detected_m;
    wire [127:0] constellation_i;
    wire [127:0] constellation_q;
    wire constellation_valid;
    wire [3:0] constellation_p;
    wire [1:0] constellation_m;
    wire [31:0] constellation_frame;
    wire overflow_fast;
    wire overflow_ldpc;
    wire ldpc_mode_error;
    wire acquire_error;
    wire recommendation_valid;
    wire [3:0] recommendation;

    always #1.220703125 clk_fast = ~clk_fast;
    always #2.44140625 clk_phy = ~clk_phy;
    always #1.627604167 clk_ldpc = ~clk_ldpc;

    PHY_TOP_Rx #(
        .AUTO_MODE        (1),
        .ENABLE_RECOMMEND (1),
        .ENABLE_ILA       (0)
    ) dut (
        .clk_400M              (clk_fast),
        .clk_200M              (clk_phy),
        .clk_ldpc              (clk_ldpc),
        .rst_n                 (rst_n),
        .phy_ploy              (4'd2),
        .modulation            (2'd0),
        .adc_data              (adc_data),
        .adc_valid             (adc_valid),
        .mov_zf_window_len      (mov_window[4:0]),
        .coded_bits            (coded_bits),
        .coded_llr             (coded_llr),
        .coded_width           (coded_width),
        .coded_v               (coded_valid),
        .coded_start           (coded_start),
        .coded_block           (coded_block),
        .dout                  (decoded_bits),
        .dout_v                (decoded_valid),
        .dout_width            (decoded_width),
        .decode_done           (decode_done),
        .decode_ok             (decode_ok),
        .to_cone_i             (constellation_i),
        .to_cone_q             (constellation_q),
        .to_cone_v             (constellation_valid),
        .to_cone_ploy          (constellation_p),
        .to_cone_modulation    (constellation_m),
        .to_cone_frame         (constellation_frame),
        .detected_p            (detected_p),
        .detected_m            (detected_m),
        .overflow_error_fast   (overflow_fast),
        .ldpc_overflow_error   (overflow_ldpc),
        .ldpc_mode_error       (ldpc_mode_error),
        .acquire_error         (acquire_error),
        .raw_recommendation_v  (recommendation_valid),
        .raw_recommended_mode  (recommendation)
    );

    initial begin
        if ($value$plusargs("WORDS=%d", input_words)) begin end
        if ($value$plusargs("DRAIN=%d", drain_clocks)) begin end
        if ($value$plusargs("WINDOW=%d", mov_window)) begin end
        if (input_words < 1 || input_words > 131072) $fatal(1, "Invalid input length");
        $readmemh("adc_input.mem", stimulus, 0, input_words-1);
        f_coded = $fopen("coded.txt", "w");
        f_decoded = $fopen("decoded.txt", "w");
        f_window = $fopen("window.txt", "w");
        f_fde = $fopen("fde.txt", "w");
        f_nlms = $fopen("nlms.txt", "w");
        f_events = $fopen("events.txt", "w");
        repeat (80) @(negedge clk_fast);
        rst_n = 1;
        repeat (20) @(negedge clk_fast);
        for (n=0; n<input_words; n=n+1) begin
            adc_data = stimulus[n];
            adc_valid = 1;
            @(negedge clk_fast);
        end
        adc_data = 0;
        repeat (drain_clocks) @(negedge clk_phy);
        $fclose(f_coded);
        $fclose(f_decoded);
        $fclose(f_fde);
        $fclose(f_window);
        $fclose(f_nlms);
        $fclose(f_events);
        f_summary = $fopen("counts.json", "w");
        $fdisplay(f_summary, "{\"frames\":%0d,\"ldpc_blocks\":%0d,\"ldpc_failed_checks\":%0d,\"ai_recommendations\":%0d,\"overflow_fast\":%0d,\"overflow_ldpc\":%0d,\"ldpc_mode_error\":%0d,\"acquire_error\":%0d}", frame_count, decode_count, decode_bad, recommendation_count, overflow_fast, overflow_ldpc, ldpc_mode_error, acquire_error);
        $fclose(f_summary);
        if (!frame_count || !decode_count) $fatal(1, "No complete frame/LDPC output");
        if (overflow_fast || overflow_ldpc || ldpc_mode_error || acquire_error)
            $fatal(1, "Receiver control error");
        $display("RX_EXECUTION_COMPLETE frames=%0d blocks=%0d; run MATLAB verification for bit errors and MER", frame_count, decode_count);
        $finish;
    end

    // Observe algorithm-stage ports and PHY-level tags only.
    always @(negedge clk_phy) begin
        if (rst_n) begin
            cycle = cycle + 1;
            if (dut.sync_dout_start && dut.sync_dout_v) begin
                $fdisplay(f_events, "%0d FRAME %0d %0d", cycle, frame_count, detected_p);
                $fflush(f_events);
                $display("RX_FRAME %0d at clock %0d", frame_count, cycle);
                frame_count = frame_count + 1;
            end
            if (coded_valid) begin
                if (^coded_bits === 1'bx) $fatal(1, "Undefined valid coded output");
                $fdisplay(f_coded, "%0d %0d %0d %0d %08h", dut.coded_frame_id, coded_block, coded_width, coded_start, coded_bits);
            end
            if (decoded_valid) begin
                if (^decoded_bits === 1'bx) $fatal(1, "Undefined valid decoded output");
                $fdisplay(f_decoded, "%0d %08h", decoded_width, decoded_bits);
            end
            if (dut.window_dout_v)
                $fdisplay(f_window, "%0d %0d %032h %032h", dut.window_frame_id, dut.window_ploy, dut.window_dout_i, dut.window_dout_q);
            if (dut.select_dout_v && !dut.select_dout_pilot)
                $fdisplay(f_fde, "%0d %0d %032h %032h", dut.select_frame_id, dut.select_ploy, dut.select_dout_i, dut.select_dout_q);
            if (constellation_valid)
                $fdisplay(f_nlms, "%0d %0d %032h %032h", constellation_frame, constellation_p, constellation_i, constellation_q);
            if (decode_done) begin
                decode_count = decode_count + 1;
                if (!decode_ok) decode_bad = decode_bad + 1;
            end
            if (recommendation_valid) begin
                recommendation_count = recommendation_count + 1;
                $fdisplay(f_events, "%0d RECOMMEND %0d", cycle, recommendation);
            end
        end
    end
endmodule
