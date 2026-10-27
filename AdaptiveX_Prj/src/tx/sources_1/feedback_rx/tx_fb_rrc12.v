`timescale 1ns / 1ps
`default_nettype none
// RFDC supplies twelve complex samples per clk (491.52 Msamples/s).
// Causal RRC: alpha=.15, span=32 symbols, 385 taps; decimate by twelve.
// Coefficients are round(h_unit_energy/sqrt(12)*65536), not old R120 taps.
// A symmetric preadder uses 193 real multipliers per I/Q component. Every
// adder-tree level is registered; no 409.6 MHz RF-rate multiply bank is used.
// phase_select is an extraction phase in 0..11. Delay (12-phase)%12 before
// filtering implements the original high-rate zero-padding correction, at
// T/12 resolution. This is fractional SYMBOL timing, not an arbitrary
// continuous fractional-ADC-sample interpolator. Phase changes flush history
// and the complete arithmetic pipeline so the decoder must acquire anew.
module tx_fb_rrc12 #(
    parameter COEFFICIENT_MEM="fb_rx_rrc12_q16.mem"
)(
    input wire clk,input wire rst_n,
    input wire [191:0] din_i,input wire [191:0] din_q,input wire din_v,
    input wire [6:0] phase_select,
    output reg signed [15:0] symbol_i,output reg signed [15:0] symbol_q,
    output wire symbol_v
);
    reg signed [17:0] coefficients[0:384];
    reg signed [15:0] history_i[0:383],history_q[0:383];
    reg [191:0] previous_i,previous_q;
    reg [6:0] phase_latched;
    wire [6:0] phase_requested=phase_select<12 ? phase_select:7'd0;
    wire flush=!rst_n || !din_v || phase_requested!=phase_latched;
    wire [3:0] delay_samples=phase_latched==0 ? 4'd0:4'd12-phase_latched[3:0];
    reg [191:0] routed_i,routed_q;
    integer lane,k,source_lane;
    always@*begin
        routed_i=0;routed_q=0;source_lane=0;
        for(lane=0;lane<12;lane=lane+1)begin
            source_lane=lane-delay_samples;
            if(source_lane>=0)begin
                routed_i[16*lane+:16]=din_i[16*source_lane+:16];
                routed_q[16*lane+:16]=din_q[16*source_lane+:16];
            end else begin
                routed_i[16*lane+:16]=previous_i[16*(source_lane+12)+:16];
                routed_q[16*lane+:16]=previous_q[16*(source_lane+12)+:16];
            end
        end
    end
    initial $readmemh(COEFFICIENT_MEM,coefficients);
    always@(posedge clk)begin
        if(flush)begin
            phase_latched<=phase_requested;previous_i<=0;previous_q<=0;
            for(k=0;k<384;k=k+1)begin history_i[k]<=0;history_q[k]<=0;end
        end else begin
            previous_i<=din_i;previous_q<=din_q;
            for(k=383;k>=12;k=k-1)begin
                history_i[k]<=history_i[k-12];history_q[k]<=history_q[k-12];
            end
            for(k=0;k<12;k=k+1)begin
                history_i[k]<=routed_i[16*(11-k)+:16];
                history_q[k]<=routed_q[16*(11-k)+:16];
            end
        end
    end
    reg [10:0] valid_pipeline;
    always@(posedge clk)begin
        if(flush)valid_pipeline<=0;
        else valid_pipeline<={valid_pipeline[9:0],1'b1};
    end
    // Full-width preadd/product, then an eight-level registered binary tree.
    wire signed [42:0] sum_i[0:510],sum_q[0:510];
    genvar tap,node;
    generate for(tap=0;tap<193;tap=tap+1)begin: symmetric_tap
        wire signed [15:0] left_i,left_q,right_i,right_q;
        if(tap==0)begin: newest
            assign left_i=routed_i[15:0];assign left_q=routed_q[15:0];
            assign right_i=history_i[383];assign right_q=history_q[383];
        end else if(tap==192)begin: center
            assign left_i=history_i[191];assign left_q=history_q[191];
            assign right_i=16'sd0;assign right_q=16'sd0;
        end else begin: pair
            assign left_i=history_i[tap-1];assign left_q=history_q[tap-1];
            assign right_i=history_i[383-tap];assign right_q=history_q[383-tap];
        end
        reg signed [16:0] preadd_i,preadd_q;
        (* use_dsp="yes" *) reg signed [34:0] product_i,product_q;
        always@(posedge clk)begin
            preadd_i<={left_i[15],left_i}+{right_i[15],right_i};
            preadd_q<={left_q[15],left_q}+{right_q[15],right_q};
            product_i<=preadd_i*coefficients[tap];
            product_q<=preadd_q*coefficients[tap];
        end
        assign sum_i[255+tap]={{8{product_i[34]}},product_i};
        assign sum_q[255+tap]={{8{product_q[34]}},product_q};
    end
    for(tap=193;tap<256;tap=tap+1)begin: padding
        assign sum_i[255+tap]=43'sd0;assign sum_q[255+tap]=43'sd0;
    end
    for(node=0;node<255;node=node+1)begin: adder_tree
        (* use_dsp="no" *) reg signed [42:0] value_i,value_q;
        always@(posedge clk)begin
            value_i<=sum_i[2*node+1]+sum_i[2*node+2];
            value_q<=sum_q[2*node+1]+sum_q[2*node+2];
        end
        assign sum_i[node]=value_i;assign sum_q[node]=value_q;
    end endgenerate
    function signed [15:0] rounded_saturated;
        input signed [42:0] value;
        reg [42:0] magnitude;
        reg [42:0] rounded;
        begin
            magnitude=value[42] ? -value:value;
            rounded=(magnitude+43'd32768)>>16;
            if(value[42])begin
                if(rounded>=32768)rounded_saturated=16'sh8000;
                else rounded_saturated=-$signed({1'b0,rounded[14:0]});
            end else begin
                if(rounded>32767)rounded_saturated=16'sh7fff;
                else rounded_saturated=rounded[15:0];
            end
        end
    endfunction
    always@(posedge clk)begin
        symbol_i<=rounded_saturated(sum_i[0]);
        symbol_q<=rounded_saturated(sum_q[0]);
    end
    assign symbol_v=rst_n && !flush && valid_pipeline[10];
endmodule
`default_nettype wire
