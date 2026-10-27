`timescale 1ns / 1ps
`default_nettype none

// Span-16 matched RRC; 24ploy in, P consecutive symbols out.
module RRC_Rx_Shared #(
    parameter integer DYNAMIC_MODE = 0
) (
    input wire clk,
    input wire rst_n,
    input wire [3:0] phy_ploy,
    input wire [24 * 16 - 1:0] din_i,
    input wire [24 * 16 - 1:0] din_q,
    input wire din_v,
    output wire [8 * 16 - 1:0] dout_i,
    output wire [8 * 16 - 1:0] dout_q,
    output wire [3:0] dout_ploy,
    output wire dout_v
);

    reg [3:0] mode_cfg;
    reg [3:0] mode_d[0:11];
    wire [3:0] active_mode;
    integer mode_idx;
    reg [11:0] din_v_d;
    reg [15:0] history_i[0:191];
    reg [15:0] history_q[0:191];
    wire [24 * 16 - 1:0] current_i;
    wire [24 * 16 - 1:0] current_q;
    wire [216 * 16 - 1:0] window_i;
    wire [216 * 16 - 1:0] window_q;
    wire signed [39:0] engine_dout_i[0:7];
    wire signed [39:0] engine_dout_q[0:7];
    reg signed [40:0] pair_a_d9_i[0:7];
    reg signed [40:0] pair_b_d9_i[0:7];
    reg signed [40:0] pair_a_d9_q[0:7];
    reg signed [40:0] pair_b_d9_q[0:7];
    reg signed [41:0] sum_d10_i[0:7];
    reg signed [41:0] sum_d10_q[0:7];
    reg signed [41:0] rounded_d11_i[0:7];
    reg signed [41:0] rounded_d11_q[0:7];
    reg signed [15:0] dout_i_reg[0:7];
    reg signed [15:0] dout_q_reg[0:7];
    integer sample_idx;
    genvar ploy_idx;

    ////////////////////////// Logic //////////////////////////

    assign active_mode = (DYNAMIC_MODE != 0) ? phy_ploy : mode_cfg;
    assign dout_ploy   = mode_d[11];

    assign current_i = (rst_n && din_v) ? din_i : 384'd0;
    assign current_q = (rst_n && din_v) ? din_q : 384'd0;

    always @(posedge clk) begin
        if (!rst_n) begin
            mode_cfg <= phy_ploy;
            din_v_d  <= 12'd0;
            for (mode_idx = 0; mode_idx < 12; mode_idx = mode_idx + 1) mode_d[mode_idx] <= phy_ploy;
            for (sample_idx = 0; sample_idx < 192; sample_idx = sample_idx + 1) begin
                history_i[sample_idx] <= 16'd0;
                history_q[sample_idx] <= 16'd0;
            end
        end else begin
            din_v_d   <= {din_v_d[10:0], din_v};
            mode_d[0] <= active_mode;
            for (mode_idx = 1; mode_idx < 12; mode_idx = mode_idx + 1) mode_d[mode_idx] <= mode_d[mode_idx-1];
            for (sample_idx = 0; sample_idx < 24; sample_idx = sample_idx + 1) begin
                history_i[sample_idx] <= current_i[(23-sample_idx)*16+:16];
                history_q[sample_idx] <= current_q[(23-sample_idx)*16+:16];
            end
            for (sample_idx = 24; sample_idx < 192; sample_idx = sample_idx + 1) begin
                history_i[sample_idx] <= history_i[sample_idx-24];
                history_q[sample_idx] <= history_q[sample_idx-24];
            end
        end
    end
    assign dout_v = din_v_d[11] && rst_n;

    generate
        for (ploy_idx = 0; ploy_idx < 216; ploy_idx = ploy_idx + 1) begin : sample_window
            if (ploy_idx < 24) begin : now
                assign window_i[ploy_idx*16+:16] = current_i[(23-ploy_idx)*16+:16];
                assign window_q[ploy_idx*16+:16] = current_q[(23-ploy_idx)*16+:16];
            end else begin : past
                assign window_i[ploy_idx*16+:16] = history_i[ploy_idx-24];
                assign window_q[ploy_idx*16+:16] = history_q[ploy_idx-24];
            end
        end
        for (ploy_idx = 0; ploy_idx < 8; ploy_idx = ploy_idx + 1) begin : engine
            RRC_Rx_Engine #(
                .ENGINE(ploy_idx)
            ) u_engine (
                .clk     (clk),
                .phy_ploy(active_mode),
                .din_i   (window_i),
                .din_q   (window_q),
                .dout_i  (engine_dout_i[ploy_idx]),
                .dout_q  (engine_dout_q[ploy_idx])
            );
        end
        for (ploy_idx = 0; ploy_idx < 8; ploy_idx = ploy_idx + 1) begin : result_lane
            always @(posedge clk) begin
                case (mode_d[7])
                    4'd2: begin
                        if (ploy_idx < 2) begin
                            pair_a_d9_i[ploy_idx] <= $signed(engine_dout_i[4*ploy_idx]) + $signed(engine_dout_i[4*ploy_idx+1]);
                            pair_b_d9_i[ploy_idx] <= $signed(engine_dout_i[4*ploy_idx+2]) + $signed(engine_dout_i[4*ploy_idx+3]);
                            pair_a_d9_q[ploy_idx] <= $signed(engine_dout_q[4*ploy_idx]) + $signed(engine_dout_q[4*ploy_idx+1]);
                            pair_b_d9_q[ploy_idx] <= $signed(engine_dout_q[4*ploy_idx+2]) + $signed(engine_dout_q[4*ploy_idx+3]);
                        end else begin
                            pair_a_d9_i[ploy_idx] <= 41'sd0;
                            pair_b_d9_i[ploy_idx] <= 41'sd0;
                            pair_a_d9_q[ploy_idx] <= 41'sd0;
                            pair_b_d9_q[ploy_idx] <= 41'sd0;
                        end
                    end
                    4'd4: begin
                        if (ploy_idx < 4) begin
                            pair_a_d9_i[ploy_idx] <= $signed(engine_dout_i[2*ploy_idx]) + $signed(engine_dout_i[2*ploy_idx+1]);
                            pair_a_d9_q[ploy_idx] <= $signed(engine_dout_q[2*ploy_idx]) + $signed(engine_dout_q[2*ploy_idx+1]);
                        end else begin
                            pair_a_d9_i[ploy_idx] <= 41'sd0;
                            pair_a_d9_q[ploy_idx] <= 41'sd0;
                        end
                        pair_b_d9_i[ploy_idx] <= 41'sd0;
                        pair_b_d9_q[ploy_idx] <= 41'sd0;
                    end
                    4'd8: begin
                        pair_a_d9_i[ploy_idx] <= {{1{engine_dout_i[ploy_idx][39]}}, engine_dout_i[ploy_idx]};
                        pair_a_d9_q[ploy_idx] <= {{1{engine_dout_q[ploy_idx][39]}}, engine_dout_q[ploy_idx]};
                        pair_b_d9_i[ploy_idx] <= 41'sd0;
                        pair_b_d9_q[ploy_idx] <= 41'sd0;
                    end
                    default: begin
                        pair_a_d9_i[ploy_idx] <= 41'sd0;
                        pair_b_d9_i[ploy_idx] <= 41'sd0;
                        pair_a_d9_q[ploy_idx] <= 41'sd0;
                        pair_b_d9_q[ploy_idx] <= 41'sd0;
                    end
                endcase
                sum_d10_i[ploy_idx] <= {{1{pair_a_d9_i[ploy_idx][40]}}, pair_a_d9_i[ploy_idx]} +
                    {{1{pair_b_d9_i[ploy_idx][40]}}, pair_b_d9_i[ploy_idx]};
                sum_d10_q[ploy_idx] <= {{1{pair_a_d9_q[ploy_idx][40]}}, pair_a_d9_q[ploy_idx]} +
                    {{1{pair_b_d9_q[ploy_idx][40]}}, pair_b_d9_q[ploy_idx]};
                rounded_d11_i[ploy_idx] <= sum_d10_i[ploy_idx] +
                    (sum_d10_i[ploy_idx][41] ? 42'sd32767 : 42'sd32768);
                rounded_d11_q[ploy_idx] <= sum_d10_q[ploy_idx] +
                    (sum_d10_q[ploy_idx][41] ? 42'sd32767 : 42'sd32768);
                if ($signed(rounded_d11_i[ploy_idx] >>> 16) > 42'sd32767) dout_i_reg[ploy_idx] <= 16'sh7fff;
                else if ($signed(rounded_d11_i[ploy_idx] >>> 16) < -42'sd32768)
                    dout_i_reg[ploy_idx] <= 16'sh8000;
                else dout_i_reg[ploy_idx] <= rounded_d11_i[ploy_idx][31:16];
                if ($signed(rounded_d11_q[ploy_idx] >>> 16) > 42'sd32767) dout_q_reg[ploy_idx] <= 16'sh7fff;
                else if ($signed(rounded_d11_q[ploy_idx] >>> 16) < -42'sd32768)
                    dout_q_reg[ploy_idx] <= 16'sh8000;
                else dout_q_reg[ploy_idx] <= rounded_d11_q[ploy_idx][31:16];
            end
            assign dout_i[ploy_idx*16+:16] = dout_v ? dout_i_reg[ploy_idx] : 16'd0;
            assign dout_q[ploy_idx*16+:16] = dout_v ? dout_q_reg[ploy_idx] : 16'd0;
        end
    endgenerate

endmodule
`default_nettype wire
