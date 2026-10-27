`timescale 1ns / 1ps
`default_nettype none

// Constant phase p of the six-way RRC: y[6*n+p]=sum_t x[n-t]*h[6*t+p].
// 33-tap window; only phase0 has tap32, other phase tails are exactly zero.
// signed16 F13 * signed18 F16 -> signed34 F29, full-width balanced sums.
// Registered input, product, 6 add levels, rounding, saturation = 10 stages.
// Round nearest/ties away from zero; saturate only once to signed16 F13.
// Arithmetic has no reset. The parent masks ten accepted startup beats.
module rx_fb_rrc6_phase #(
    parameter integer LANE=0,
    parameter COEF_MEM="fb_tx_rrc6_q16.mem"
)(
    input wire clk,
    input wire advance,
    input wire [33*16-1:0] din_i,
    input wire [33*16-1:0] din_q,
    output reg signed [15:0] dout_i,
    output reg signed [15:0] dout_q
);
    reg signed [17:0] coefficients[0:192];
    reg signed [15:0] sample_i[0:32],sample_q[0:32];
    (* use_dsp="yes" *) reg signed [33:0] product_i[0:32],product_q[0:32];
    reg signed [34:0] sum1_i[0:16],sum1_q[0:16];
    reg signed [35:0] sum2_i[0:8],sum2_q[0:8];
    reg signed [36:0] sum3_i[0:4],sum3_q[0:4];
    reg signed [37:0] sum4_i[0:2],sum4_q[0:2];
    reg signed [38:0] sum5_i[0:1],sum5_q[0:1];
    reg signed [39:0] sum6_i,sum6_q,round_i,round_q;
    wire signed [23:0] rounded_i=round_i[39:16];
    wire signed [23:0] rounded_q=round_q[39:16];
    genvar tap;
    initial $readmemh(COEF_MEM,coefficients);

    generate
        for(tap=0;tap<33;tap=tap+1) begin: coefficient_tap
            wire signed [17:0] coefficient;
            if(6*tap+LANE<=192) begin: used
                assign coefficient=coefficients[6*tap+LANE];
            end else begin: padding
                assign coefficient=18'sd0;
            end
            always @(posedge clk) if(advance) begin
                sample_i[tap]<=$signed(din_i[16*tap+:16]);
                sample_q[tap]<=$signed(din_q[16*tap+:16]);
                product_i[tap]<=sample_i[tap]*coefficient;
                product_q[tap]<=sample_q[tap]*coefficient;
            end
        end
        for(tap=0;tap<16;tap=tap+1) begin: add1
            always @(posedge clk) if(advance) begin
                sum1_i[tap]<={product_i[2*tap][33],product_i[2*tap]}+{product_i[2*tap+1][33],product_i[2*tap+1]};
                sum1_q[tap]<={product_q[2*tap][33],product_q[2*tap]}+{product_q[2*tap+1][33],product_q[2*tap+1]};
            end
        end
        for(tap=0;tap<8;tap=tap+1) begin: add2
            always @(posedge clk) if(advance) begin
                sum2_i[tap]<={sum1_i[2*tap][34],sum1_i[2*tap]}+{sum1_i[2*tap+1][34],sum1_i[2*tap+1]};
                sum2_q[tap]<={sum1_q[2*tap][34],sum1_q[2*tap]}+{sum1_q[2*tap+1][34],sum1_q[2*tap+1]};
            end
        end
        for(tap=0;tap<4;tap=tap+1) begin: add3
            always @(posedge clk) if(advance) begin
                sum3_i[tap]<={sum2_i[2*tap][35],sum2_i[2*tap]}+{sum2_i[2*tap+1][35],sum2_i[2*tap+1]};
                sum3_q[tap]<={sum2_q[2*tap][35],sum2_q[2*tap]}+{sum2_q[2*tap+1][35],sum2_q[2*tap+1]};
            end
        end
        for(tap=0;tap<2;tap=tap+1) begin: add4
            always @(posedge clk) if(advance) begin
                sum4_i[tap]<={sum3_i[2*tap][36],sum3_i[2*tap]}+{sum3_i[2*tap+1][36],sum3_i[2*tap+1]};
                sum4_q[tap]<={sum3_q[2*tap][36],sum3_q[2*tap]}+{sum3_q[2*tap+1][36],sum3_q[2*tap+1]};
            end
        end
    endgenerate

    always @(posedge clk) if(advance) begin
        sum1_i[16]<={product_i[32][33],product_i[32]};
        sum1_q[16]<={product_q[32][33],product_q[32]};
        sum2_i[8]<={sum1_i[16][34],sum1_i[16]};
        sum2_q[8]<={sum1_q[16][34],sum1_q[16]};
        sum3_i[4]<={sum2_i[8][35],sum2_i[8]};
        sum3_q[4]<={sum2_q[8][35],sum2_q[8]};
        sum4_i[2]<={sum3_i[4][36],sum3_i[4]};
        sum4_q[2]<={sum3_q[4][36],sum3_q[4]};
        sum5_i[0]<={sum4_i[0][37],sum4_i[0]}+{sum4_i[1][37],sum4_i[1]};
        sum5_q[0]<={sum4_q[0][37],sum4_q[0]}+{sum4_q[1][37],sum4_q[1]};
        sum5_i[1]<={sum4_i[2][37],sum4_i[2]};
        sum5_q[1]<={sum4_q[2][37],sum4_q[2]};
        sum6_i<={sum5_i[0][38],sum5_i[0]}+{sum5_i[1][38],sum5_i[1]};
        sum6_q<={sum5_q[0][38],sum5_q[0]}+{sum5_q[1][38],sum5_q[1]};
        round_i<=sum6_i+(sum6_i[39] ? 40'sd32767 : 40'sd32768);
        round_q<=sum6_q+(sum6_q[39] ? 40'sd32767 : 40'sd32768);
        if(rounded_i>24'sd32767) dout_i<=16'sh7fff;
        else if(rounded_i< -24'sd32768) dout_i<=16'sh8000;
        else dout_i<=rounded_i[15:0];
        if(rounded_q>24'sd32767) dout_q<=16'sh7fff;
        else if(rounded_q< -24'sd32768) dout_q<=16'sh8000;
        else dout_q<=rounded_q[15:0];
    end
endmodule
`default_nettype wire
