`timescale 1ns / 1ps
`default_nettype none

// 25 symmetric tap products; eight engines share the three RRC modes.
module RRC_Rx_Engine #(
    parameter integer ENGINE = 0
) (
    input wire clk,
    input wire [3:0] phy_ploy,
    input wire [216 * 16 - 1:0] din_i,
    input wire [216 * 16 - 1:0] din_q,
    output wire signed [39:0] dout_i,
    output wire signed [39:0] dout_q
);

    reg signed [17:0] coef12[0:99];
    reg signed [17:0] coef6[0:49];
    reg signed [17:0] coef3[0:24];
    reg signed [15:0] sample_a_i[0:24];
    reg signed [15:0] sample_b_i[0:24];
    reg signed [15:0] sample_a_q[0:24];
    reg signed [15:0] sample_b_q[0:24];
    reg signed [17:0] selected_coef[0:24];
    reg signed [16:0] pair_i_d1[0:24];
    reg signed [16:0] pair_q_d1[0:24];
    reg signed [17:0] coef_d1[0:24];
    (* use_dsp = "yes" *) reg signed [34:0] product_i_d2[0:24];
    (* use_dsp = "yes" *) reg signed [34:0] product_q_d2[0:24];
    reg signed [35:0] sum_d3_i[0:12];
    reg signed [35:0] sum_d3_q[0:12];
    reg signed [36:0] sum_d4_i[0:6];
    reg signed [36:0] sum_d4_q[0:6];
    reg signed [37:0] sum_d5_i[0:3];
    reg signed [37:0] sum_d5_q[0:3];
    reg signed [38:0] sum_d6_i[0:1];
    reg signed [38:0] sum_d6_q[0:1];
    reg signed [39:0] sum_d7_i;
    reg signed [39:0] sum_d7_q;
    genvar t;
    genvar j;

    ////////////////////////// Logic //////////////////////////

    initial begin
        $readmemh("rx_rrc_l12_q16.mem", coef12);
        $readmemh("rx_rrc_l6_q16.mem", coef6);
        $readmemh("rx_rrc_l3_q16.mem", coef3);
    end
    assign dout_i = sum_d7_i;
    assign dout_q = sum_d7_q;

    generate
        for (t = 0; t < 25; t = t + 1) begin : tap
            localparam integer T12 = (ENGINE % 4) * 25 + t;
            localparam integer T6  = (ENGINE % 2) * 25 + t;
            localparam integer T3  = t;
            localparam integer M12 = (ENGINE / 4) * 12;
            localparam integer M6  = (ENGINE / 2) * 6;
            localparam integer M3  = ENGINE * 3;
            wire signed [15:0] a12_i;
            wire signed [15:0] a12_q;
            wire signed [15:0] b12_i;
            wire signed [15:0] b12_q;
            wire signed [17:0] c12;
            if (T12 <= 96) begin : active12
                assign a12_i = din_i[(23-M12+T12)*16+:16];
                assign b12_i = (T12 == 96) ? 16'sd0 : din_i[(23-M12+192-T12)*16+:16];
                assign a12_q = din_q[(23-M12+T12)*16+:16];
                assign b12_q = (T12 == 96) ? 16'sd0 : din_q[(23-M12+192-T12)*16+:16];
                assign c12   = coef12[T12];
            end else begin : pad12
                assign a12_i = 16'sd0;
                assign b12_i = 16'sd0;
                assign a12_q = 16'sd0;
                assign b12_q = 16'sd0;
                assign c12   = 18'sd0;
            end
            wire signed [15:0] a6_i;
            wire signed [15:0] a6_q;
            wire signed [15:0] b6_i;
            wire signed [15:0] b6_q;
            wire signed [17:0] c6;
            if (T6 <= 48) begin : active6
                assign a6_i = din_i[(23-M6+T6)*16+:16];
                assign b6_i = (T6 == 48) ? 16'sd0 : din_i[(23-M6+96-T6)*16+:16];
                assign a6_q = din_q[(23-M6+T6)*16+:16];
                assign b6_q = (T6 == 48) ? 16'sd0 : din_q[(23-M6+96-T6)*16+:16];
                assign c6   = coef6[T6];
            end else begin : pad6
                assign a6_i = 16'sd0;
                assign b6_i = 16'sd0;
                assign a6_q = 16'sd0;
                assign b6_q = 16'sd0;
                assign c6   = 18'sd0;
            end
            wire signed [15:0] a3_i;
            wire signed [15:0] a3_q;
            wire signed [15:0] b3_i;
            wire signed [15:0] b3_q;
            wire signed [17:0] c3;
            if (T3 <= 24) begin : active3
                assign a3_i = din_i[(23-M3+T3)*16+:16];
                assign b3_i = (T3 == 24) ? 16'sd0 : din_i[(23-M3+48-T3)*16+:16];
                assign a3_q = din_q[(23-M3+T3)*16+:16];
                assign b3_q = (T3 == 24) ? 16'sd0 : din_q[(23-M3+48-T3)*16+:16];
                assign c3   = coef3[T3];
            end else begin : pad3
                assign a3_i = 16'sd0;
                assign b3_i = 16'sd0;
                assign a3_q = 16'sd0;
                assign b3_q = 16'sd0;
                assign c3   = 18'sd0;
            end
            always @(posedge clk) begin
                // Select samples before the common preadder.
                case (phy_ploy)
                    4'd2: begin
                        sample_a_i[t] <= a12_i;
                        sample_b_i[t] <= b12_i;
                        sample_a_q[t] <= a12_q;
                        sample_b_q[t] <= b12_q;
                        selected_coef[t] <= c12;
                    end
                    4'd4: begin
                        sample_a_i[t] <= a6_i;
                        sample_b_i[t] <= b6_i;
                        sample_a_q[t] <= a6_q;
                        sample_b_q[t] <= b6_q;
                        selected_coef[t] <= c6;
                    end
                    4'd8: begin
                        sample_a_i[t] <= a3_i;
                        sample_b_i[t] <= b3_i;
                        sample_a_q[t] <= a3_q;
                        sample_b_q[t] <= b3_q;
                        selected_coef[t] <= c3;
                    end
                    default: begin
                        sample_a_i[t] <= 16'sd0;
                        sample_b_i[t] <= 16'sd0;
                        sample_a_q[t] <= 16'sd0;
                        sample_b_q[t] <= 16'sd0;
                        selected_coef[t] <= 18'sd0;
                    end
                endcase
                pair_i_d1[t] <= $signed({sample_a_i[t][15], sample_a_i[t]}) + $signed({sample_b_i[t][15], sample_b_i[t]});
                pair_q_d1[t] <= $signed({sample_a_q[t][15], sample_a_q[t]}) + $signed({sample_b_q[t][15], sample_b_q[t]});
                coef_d1[t] <= selected_coef[t];
                product_i_d2[t] <= pair_i_d1[t] * coef_d1[t];
                product_q_d2[t] <= pair_q_d1[t] * coef_d1[t];
            end
        end
    endgenerate

    generate
        for (j = 0; j < 13; j = j + 1) begin : add1
            if (2 * j + 1 < 25) begin : pair
                always @(posedge clk) begin
                    sum_d3_i[j] <= {{1{product_i_d2[2*j][34]}}, product_i_d2[2*j]} +
                        {{1{product_i_d2[2*j+1][34]}}, product_i_d2[2*j+1]};
                    sum_d3_q[j] <= {{1{product_q_d2[2*j][34]}}, product_q_d2[2*j]} +
                        {{1{product_q_d2[2*j+1][34]}}, product_q_d2[2*j+1]};
                end
            end else begin : tail
                always @(posedge clk) begin
                    sum_d3_i[j] <= {{1{product_i_d2[2*j][34]}}, product_i_d2[2*j]};
                    sum_d3_q[j] <= {{1{product_q_d2[2*j][34]}}, product_q_d2[2*j]};
                end
            end
        end
        for (j = 0; j < 7; j = j + 1) begin : add2
            if (2 * j + 1 < 13) begin : pair
                always @(posedge clk) begin
                    sum_d4_i[j] <= {{1{sum_d3_i[2*j][35]}}, sum_d3_i[2*j]} +
                        {{1{sum_d3_i[2*j+1][35]}}, sum_d3_i[2*j+1]};
                    sum_d4_q[j] <= {{1{sum_d3_q[2*j][35]}}, sum_d3_q[2*j]} +
                        {{1{sum_d3_q[2*j+1][35]}}, sum_d3_q[2*j+1]};
                end
            end else begin : tail
                always @(posedge clk) begin
                    sum_d4_i[j] <= {{1{sum_d3_i[2*j][35]}}, sum_d3_i[2*j]};
                    sum_d4_q[j] <= {{1{sum_d3_q[2*j][35]}}, sum_d3_q[2*j]};
                end
            end
        end
        for (j = 0; j < 4; j = j + 1) begin : add3
            if (2 * j + 1 < 7) begin : pair
                always @(posedge clk) begin
                    sum_d5_i[j] <= {{1{sum_d4_i[2*j][36]}}, sum_d4_i[2*j]} +
                        {{1{sum_d4_i[2*j+1][36]}}, sum_d4_i[2*j+1]};
                    sum_d5_q[j] <= {{1{sum_d4_q[2*j][36]}}, sum_d4_q[2*j]} +
                        {{1{sum_d4_q[2*j+1][36]}}, sum_d4_q[2*j+1]};
                end
            end else begin : tail
                always @(posedge clk) begin
                    sum_d5_i[j] <= {{1{sum_d4_i[2*j][36]}}, sum_d4_i[2*j]};
                    sum_d5_q[j] <= {{1{sum_d4_q[2*j][36]}}, sum_d4_q[2*j]};
                end
            end
        end
        for (j = 0; j < 2; j = j + 1) begin : add4
            always @(posedge clk) begin
                sum_d6_i[j] <= {{1{sum_d5_i[2*j][37]}}, sum_d5_i[2*j]} +
                    {{1{sum_d5_i[2*j+1][37]}}, sum_d5_i[2*j+1]};
                sum_d6_q[j] <= {{1{sum_d5_q[2*j][37]}}, sum_d5_q[2*j]} +
                    {{1{sum_d5_q[2*j+1][37]}}, sum_d5_q[2*j+1]};
            end
        end
    endgenerate

    always @(posedge clk) begin
        sum_d7_i <= {{1{sum_d6_i[0][38]}}, sum_d6_i[0]} + {{1{sum_d6_i[1][38]}}, sum_d6_i[1]};
        sum_d7_q <= {{1{sum_d6_q[0][38]}}, sum_d6_q[0]} + {{1{sum_d6_q[1][38]}}, sum_d6_q[1]};
    end

endmodule
`default_nettype wire
