`timescale 1ns / 1ps
`default_nettype none

// Correlate the two 265-clock training blocks and estimate phase increment.
module Rx_CFO_Estimate (
    input wire clk,
    input wire rst_n,
    input wire [127:0] din_i,
    input wire [127:0] din_q,
    input wire din_v,
    input wire din_start,
    output wire signed [31:0] dout,
    output wire dout_v
);

    reg [11:0] din_clk_cnt;
    wire [11:0] din_clk_idx;
    reg [255:0] training_ram[0:264];
    reg [255:0] training_ram_dout;
    reg [127:0] din_i_d1;
    reg [127:0] din_q_d1;
    reg pair_v;
    reg pair_last;
    reg [4:0] pair_v_d;
    reg [4:0] pair_last_d;
    reg signed [31:0] ri_ri_d2[0:7];
    reg signed [31:0] rq_rq_d2[0:7];
    reg signed [31:0] rq_ri_d2[0:7];
    reg signed [31:0] ri_rq_d2[0:7];
    reg signed [32:0] corr_d3_i[0:7];
    reg signed [32:0] corr_d3_q[0:7];
    reg signed [33:0] corr_d4_i[0:3];
    reg signed [33:0] corr_d4_q[0:3];
    reg signed [34:0] corr_d5_i[0:1];
    reg signed [34:0] corr_d5_q[0:1];
    reg signed [35:0] corr_d6_i;
    reg signed [35:0] corr_d6_q;
    reg signed [47:0] accum_re;
    reg signed [47:0] accum_im;
    wire signed [47:0] final_re;
    wire signed [47:0] final_im;
    reg signed [47:0] correlation_re;
    reg signed [47:0] correlation_im;
    reg correlation_v;
    reg [47:0] correlation_magnitude;
    reg [1:0] normalize_v;
    reg signed [6:0] normalize_shift;
    wire [47:0] magnitude_re;
    wire [47:0] magnitude_im;
    wire signed [47:0] normalized_re;
    wire signed [47:0] normalized_im;
    reg [63:0] angle_input;
    reg angle_input_v;
    wire [31:0] angle_q13;
    wire angle_v;
    reg signed [15:0] angle_to_mult;
    reg [3:0] angle_valid_sr;
    wire signed [33:0] step_mult;
    reg signed [31:0] step_per_virtual_sample;
    reg step_valid;
    genvar ploy_idx;
    genvar group_idx;

    ////////////////////////// Logic //////////////////////////

    function signed [6:0] common_shift;
        input [47:0] magnitude;
        integer bit_idx;
        begin
            common_shift = 7'sd0;
            for (bit_idx = 0; bit_idx < 48; bit_idx = bit_idx + 1)
            if (magnitude[bit_idx]) common_shift = bit_idx - 26;
        end
    endfunction
    assign din_clk_idx = din_start ? 12'd0 : din_clk_cnt;
    assign final_re = accum_re + {{12{corr_d6_i[35]}}, corr_d6_i};
    assign final_im = accum_im + {{12{corr_d6_q[35]}}, corr_d6_q};
    assign magnitude_re = correlation_re[47] ? -correlation_re : correlation_re;
    assign magnitude_im = correlation_im[47] ? -correlation_im : correlation_im;
    assign normalized_re = (normalize_shift >= 0) ?
        (correlation_re >>> normalize_shift) : (correlation_re <<< -normalize_shift);
    assign normalized_im = (normalize_shift >= 0) ?
        (correlation_im >>> normalize_shift) : (correlation_im <<< -normalize_shift);

    always @(posedge clk) begin
        if (din_v && din_clk_idx < 12'd265) training_ram[din_clk_idx[8:0]] <= {din_q, din_i};
        if (!rst_n) training_ram_dout <= 0;
        else if (din_v && din_clk_idx >= 12'd265 && din_clk_idx < 12'd530)
            training_ram_dout <= training_ram[din_clk_idx-12'd265];
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            din_clk_cnt <= 12'd0;
            pair_v <= 1'b0;
            pair_last <= 1'b0;
            din_i_d1 <= 128'd0;
            din_q_d1 <= 128'd0;
        end else begin
            pair_v <= din_v && din_clk_idx >= 12'd265 && din_clk_idx < 12'd530;
            pair_last <= din_v && din_clk_idx == 12'd529;
            if (din_v) begin
                din_clk_cnt <= (din_clk_idx == 12'd2119) ? 12'd0 : (din_clk_idx + 12'd1);
                din_i_d1 <= din_i;
                din_q_d1 <= din_q;
            end
        end
    end

    generate
        for (ploy_idx = 0; ploy_idx < 8; ploy_idx = ploy_idx + 1) begin : correlation_lane
            wire signed [15:0] a_i;
            wire signed [15:0] a_q;
            wire signed [15:0] b_i;
            wire signed [15:0] b_q;
            assign a_i = $signed(training_ram_dout[ploy_idx*16+:16]);
            assign a_q = $signed(training_ram_dout[128+ploy_idx*16+:16]);
            assign b_i = $signed(din_i_d1[ploy_idx*16+:16]);
            assign b_q = $signed(din_q_d1[ploy_idx*16+:16]);
            always @(posedge clk) begin
                ri_ri_d2[ploy_idx] <= a_i * b_i;
                rq_rq_d2[ploy_idx] <= a_q * b_q;
                rq_ri_d2[ploy_idx] <= a_q * b_i;
                ri_rq_d2[ploy_idx] <= a_i * b_q;
                corr_d3_i[ploy_idx] <= {ri_ri_d2[ploy_idx][31], ri_ri_d2[ploy_idx]} +
                    {rq_rq_d2[ploy_idx][31], rq_rq_d2[ploy_idx]};
                corr_d3_q[ploy_idx] <= {rq_ri_d2[ploy_idx][31], rq_ri_d2[ploy_idx]} -
                    {ri_rq_d2[ploy_idx][31], ri_rq_d2[ploy_idx]};
            end
        end
        for (group_idx = 0; group_idx < 4; group_idx = group_idx + 1) begin : pair_tree
            always @(posedge clk) begin
                corr_d4_i[group_idx] <= {corr_d3_i[2*group_idx][32], corr_d3_i[2*group_idx]} +
                    {corr_d3_i[2*group_idx+1][32], corr_d3_i[2*group_idx+1]};
                corr_d4_q[group_idx] <= {corr_d3_q[2*group_idx][32], corr_d3_q[2*group_idx]} +
                    {corr_d3_q[2*group_idx+1][32], corr_d3_q[2*group_idx+1]};
            end
        end
        for (group_idx = 0; group_idx < 2; group_idx = group_idx + 1) begin : quad_tree
            always @(posedge clk) begin
                corr_d5_i[group_idx] <= {corr_d4_i[2*group_idx][33], corr_d4_i[2*group_idx]} +
                    {corr_d4_i[2*group_idx+1][33], corr_d4_i[2*group_idx+1]};
                corr_d5_q[group_idx] <= {corr_d4_q[2*group_idx][33], corr_d4_q[2*group_idx]} +
                    {corr_d4_q[2*group_idx+1][33], corr_d4_q[2*group_idx+1]};
            end
        end
    endgenerate

    always @(posedge clk) begin
        corr_d6_i <= {corr_d5_i[0][34], corr_d5_i[0]} + {corr_d5_i[1][34], corr_d5_i[1]};
        corr_d6_q <= {corr_d5_q[0][34], corr_d5_q[0]} + {corr_d5_q[1][34], corr_d5_q[1]};
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            pair_v_d <= 5'd0;
            pair_last_d <= 5'd0;
            accum_re <= 48'sd0;
            accum_im <= 48'sd0;
            correlation_re <= 48'sd0;
            correlation_im <= 48'sd0;
            correlation_v <= 1'b0;
        end else begin
            pair_v_d <= {pair_v_d[3:0], pair_v};
            pair_last_d <= {pair_last_d[3:0], pair_last};
            correlation_v <= 1'b0;
            if (din_v && din_start) begin
                accum_re <= 48'sd0;
                accum_im <= 48'sd0;
            end else if (pair_v_d[4]) begin
                accum_re <= final_re;
                accum_im <= final_im;
                if (pair_last_d[4]) begin
                    correlation_re <= final_re;
                    correlation_im <= final_im;
                    correlation_v  <= 1'b1;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            correlation_magnitude <= 48'd0;
            normalize_v <= 2'b0;
            normalize_shift <= 7'sd0;
            angle_input <= 64'd0;
            angle_input_v <= 1'b0;
        end else begin
            normalize_v   <= {normalize_v[0], correlation_v};
            angle_input_v <= normalize_v[1];
            if (correlation_v) correlation_magnitude <= magnitude_re | magnitude_im;
            if (normalize_v[0]) normalize_shift <= common_shift(correlation_magnitude);
            if (normalize_v[1]) angle_input <= {normalized_im[31:0], normalized_re[31:0]};
        end
    end
    // Correlation angle
    cordic_FreOffEst u_angle (
        .aclk                   (clk),
        .aresetn                (rst_n),
        .s_axis_cartesian_tvalid(angle_input_v),
        .s_axis_cartesian_tdata (angle_input),
        .m_axis_dout_tvalid     (angle_v),
        .m_axis_dout_tdata      (angle_q13)
    );

    // Angle to phase increment
    mult_16xconst u_angle_scale (
        .CLK(clk),
        .A  (angle_to_mult),
        .P  (step_mult)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            angle_to_mult <= 16'sd0;
            angle_valid_sr <= 4'd0;
            step_per_virtual_sample <= 32'sd0;
            step_valid <= 1'b0;
        end else begin
            angle_to_mult <= angle_q13[31:16];
            angle_valid_sr <= {angle_valid_sr[2:0], angle_v};
            step_per_virtual_sample <= {{9{step_mult[33]}}, step_mult[33:11]};
            step_valid <= angle_valid_sr[3];
        end
    end
    assign dout   = step_per_virtual_sample <<< 4;
    assign dout_v = step_valid;

endmodule
`default_nettype wire
