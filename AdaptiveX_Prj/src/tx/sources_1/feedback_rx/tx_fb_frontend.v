`timescale 1ns / 1ps
`default_nettype none
module tx_fb_frontend(
    input wire clk,input wire rst_n,
    input wire [191:0] adc_i,input wire [191:0] adc_q,input wire adc_valid,
    input wire [6:0] phase_select,
    output reg signed [15:0] symbol_i,output reg signed [15:0] symbol_q,
    output wire symbol_v,output reg [6:0] symbol_phase,output reg stream_error
);
    wire signed [15:0] raw_symbol_i,raw_symbol_q;
    wire raw_symbol_v;
    (* MAX_FANOUT=64,SHREG_EXTRACT="NO" *) reg symbol_v_q;
    reg stream_started;
    // Register the complete symbol transaction together. This boundary adds
    // one ADC-interface clock to I/Q/valid/phase. All four fields cross to
    // the fast decoder domain as one FIFO word. Never delay valid alone.
    always@(posedge clk)begin
        symbol_i<=raw_symbol_i;
        symbol_q<=raw_symbol_q;
        symbol_phase<=phase_select;
        if(!rst_n)symbol_v_q<=1'b0;
        else symbol_v_q<=raw_symbol_v;
    end
    assign symbol_v=symbol_v_q;
    always@(posedge clk)begin
        if(!rst_n)begin stream_started<=1'b0;stream_error<=1'b0;end
        else begin
            if(adc_valid)stream_started<=1'b1;
            if(stream_started && !adc_valid)stream_error<=1'b1;
            if(phase_select>=7'd12)stream_error<=1'b1;
        end
    end
    // Nominal carrier conversion is now RFDC Real->I/Q, NCO=-1.2 GHz.
    // I and Q each contain twelve chronological signed16 samples per beat.
    tx_fb_rrc12 u_rrc(.clk(clk),.rst_n(rst_n),.din_i(adc_i),.din_q(adc_q),
        .din_v(adc_valid),.phase_select(phase_select),.symbol_i(raw_symbol_i),
        .symbol_q(raw_symbol_q),.symbol_v(raw_symbol_v));
endmodule
`default_nettype wire
