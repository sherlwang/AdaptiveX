`timescale 1ns / 1ps
`default_nettype none

// Feedback TX pulse shaping before the RFDC 20x interpolator/fine mixer.
// One signed16 F13 complex symbol per accepted 40.96MHz beat produces six
// consecutive complex samples at 245.76Msample/s. Lane0 is earliest/low16.
// Span32, alpha0.15, 193 taps, sqrt(6)*unit-energy RRC, signed18 F16.
// Every accepted beat advances physical sample time: din_v=0 inserts a zero
// symbol and preserves filter tails. advance=0 freezes all history/pipelines.
// Ten accepted arithmetic register stages: input at edge k is visible after
// edge k+9. Pipeline delay is separate from the 16-symbol filter group delay.
module rx_fb_rrc6 #(
    parameter COEF_MEM = "fb_tx_rrc6_q16.mem"
)(
    input wire clk,
    input wire rst_n,
    input wire advance,
    input wire signed [15:0] din_i,
    input wire signed [15:0] din_q,
    input wire din_v,
    output wire symbol_ce,
    output wire [95:0] dout_i,
    output wire [95:0] dout_q,
    output wire dout_v
);
    reg [15:0] history_i[0:31];
    reg [15:0] history_q[0:31];
    reg [9:0] valid_dly;
    wire signed [15:0] current_i = din_v ? din_i : 16'sd0;
    wire signed [15:0] current_q = din_v ? din_q : 16'sd0;
    wire [33*16-1:0] window_i,window_q;
    wire [95:0] phase_i,phase_q;
    genvar tap,lane;

    assign symbol_ce = rst_n && advance;
    assign dout_v = rst_n && valid_dly[9];
    assign dout_i = dout_v ? phase_i : 96'd0;
    assign dout_q = dout_v ? phase_q : 96'd0;
    assign window_i[15:0] = current_i;
    assign window_q[15:0] = current_q;

    always @(posedge clk) begin
        if(!rst_n) valid_dly <= 10'd0;
        else if(advance) valid_dly <= {valid_dly[8:0],1'b1};
    end

    generate
        for(tap=0;tap<32;tap=tap+1) begin: symbol_history
            if(tap==0) begin: newest
                always @(posedge clk) begin
                    if(!rst_n) begin history_i[tap]<=0;history_q[tap]<=0;end
                    else if(advance) begin
                        history_i[tap]<=current_i;history_q[tap]<=current_q;
                    end
                end
            end else begin: older
                always @(posedge clk) begin
                    if(!rst_n) begin history_i[tap]<=0;history_q[tap]<=0;end
                    else if(advance) begin
                        history_i[tap]<=history_i[tap-1];
                        history_q[tap]<=history_q[tap-1];
                    end
                end
            end
            assign window_i[16*(tap+1)+:16] = history_i[tap];
            assign window_q[16*(tap+1)+:16] = history_q[tap];
        end
        for(lane=0;lane<6;lane=lane+1) begin: output_lane
            rx_fb_rrc6_phase #(.LANE(lane),.COEF_MEM(COEF_MEM)) u_phase(
                .clk(clk),.advance(advance),.din_i(window_i),.din_q(window_q),
                .dout_i(phase_i[16*lane+:16]),.dout_q(phase_q[16*lane+:16]));
        end
    endgenerate
endmodule
`default_nettype wire
