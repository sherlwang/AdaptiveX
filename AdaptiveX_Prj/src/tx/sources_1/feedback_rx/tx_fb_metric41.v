`timescale 1ns / 1ps
`default_nettype none
// Exact full-width I^2+Q^2 for the PN score. Six registered stages, one
// input per clock. Fourteen-bit limbs keep every product in one DSP48E2.
// No truncation, rounding or saturation is used in this score calculation.
module tx_fb_metric41(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_v,
    input  wire signed [40:0] in_i,
    input  wire signed [40:0] in_q,
    output wire               out_v,
    output reg [83:0]         metric
);
    reg [5:0] valid_dly;
    reg [40:0] abs_i,abs_q;
    (* use_dsp="yes" *) reg [27:0] prod_i[0:5],prod_q[0:5];
    reg [83:0] pair_i[0:2],pair_q[0:2];
    reg [83:0] sum_i,sum_q,tail_i,tail_q;
    reg [83:0] square_i,square_q;
    always@(posedge clk)begin
        if(!rst_n) valid_dly<=6'd0;
        else valid_dly<={valid_dly[4:0],in_v};
        abs_i<=in_i[40] ? (~in_i+41'd1) : in_i;
        abs_q<=in_q[40] ? (~in_q+41'd1) : in_q;
        prod_i[0]<=abs_i[13:0]*abs_i[13:0];
        prod_i[1]<=abs_i[13:0]*abs_i[27:14];
        prod_i[2]<=abs_i[13:0]*{1'b0,abs_i[40:28]};
        prod_i[3]<=abs_i[27:14]*abs_i[27:14];
        prod_i[4]<=abs_i[27:14]*{1'b0,abs_i[40:28]};
        prod_i[5]<={1'b0,abs_i[40:28]}*{1'b0,abs_i[40:28]};
        prod_q[0]<=abs_q[13:0]*abs_q[13:0];
        prod_q[1]<=abs_q[13:0]*abs_q[27:14];
        prod_q[2]<=abs_q[13:0]*{1'b0,abs_q[40:28]};
        prod_q[3]<=abs_q[27:14]*abs_q[27:14];
        prod_q[4]<=abs_q[27:14]*{1'b0,abs_q[40:28]};
        prod_q[5]<={1'b0,abs_q[40:28]}*{1'b0,abs_q[40:28]};
        pair_i[0]<={56'd0,prod_i[0]}+{41'd0,prod_i[1],15'd0};
        pair_i[1]<={28'd0,prod_i[3],28'd0}+{27'd0,prod_i[2],29'd0};
        pair_i[2]<={13'd0,prod_i[4],43'd0}+{prod_i[5],56'd0};
        pair_q[0]<={56'd0,prod_q[0]}+{41'd0,prod_q[1],15'd0};
        pair_q[1]<={28'd0,prod_q[3],28'd0}+{27'd0,prod_q[2],29'd0};
        pair_q[2]<={13'd0,prod_q[4],43'd0}+{prod_q[5],56'd0};
        sum_i<=pair_i[0]+pair_i[1];tail_i<=pair_i[2];
        sum_q<=pair_q[0]+pair_q[1];tail_q<=pair_q[2];
        square_i<=sum_i+tail_i;square_q<=sum_q+tail_q;
        metric<=square_i+square_q;
    end
    assign out_v=valid_dly[5] && rst_n;
endmodule
`default_nettype wire
