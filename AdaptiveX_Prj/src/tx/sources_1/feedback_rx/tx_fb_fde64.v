`timescale 1ns/1ps
`default_nettype none
// 64-point SC-FDE, two training blocks and one data block.  One pipelined
// FFT IP is reused for three forward transforms and one inverse transform.
// All external samples are signed F13. Input is block0/train1, block1/train2,
// block2/data, each index0..63. The data input is the CP18-10 early window;
// output retains that circular order. The decoder restores its ten-symbol
// circular shift before pilot removal. No per-frame reset of the FFT is used.
module tx_fb_fde64 #(
    parameter TRAIN_MEM="fb_fde_train_spectrum_q13.mem",
    parameter RECIP_MEM="fb_fde_recip_q18.mem",
    // F26 |H|^2 floor = 1/4096; bounds inverse gain below |H|=1/64.
    parameter [40:0] DENOM_FLOOR=41'd16384
)(
    input wire clk, input wire rst_n, input wire start,
    input wire in_v, input wire [1:0] in_block,
    input wire [5:0] in_index,
    input wire signed [15:0] in_i, input wire signed [15:0] in_q,
    output reg out_v, output reg [5:0] out_index,
    output reg signed [15:0] out_i, output reg signed [15:0] out_q,
    output reg busy, output reg done, output reg fault
);
    (* ram_style="distributed" *) reg signed [15:0] sample_i[0:191];
    (* ram_style="distributed" *) reg signed [15:0] sample_q[0:191];
    (* ram_style="distributed" *) reg signed [19:0] train_i[0:63];
    (* ram_style="distributed" *) reg signed [19:0] train_q[0:63];
    (* ram_style="distributed" *) reg signed [19:0] channel_i[0:63];
    (* ram_style="distributed" *) reg signed [19:0] channel_q[0:63];
    (* ram_style="distributed" *) reg signed [23:0] equal_i[0:63];
    (* ram_style="distributed" *) reg signed [23:0] equal_q[0:63];
    (* rom_style="distributed" *) reg [31:0] local_t[0:63];
    (* rom_style="block" *) reg [18:0] recip_rom[0:1023];
    initial begin $readmemh(TRAIN_MEM,local_t);$readmemh(RECIP_MEM,recip_rom);end

    localparam IDLE=0, CFG_FWD=1, WAIT_BLOCK=2, SEND_FWD=3,
        WAIT_EQUAL=4, CFG_INV=5, SEND_INV=6, WAIT_RESULT=7;
    reg [3:0] state;
    reg [7:0] received;
    reg [1:0] send_block, result_block;
    reg [5:0] send_index;
    reg [6:0] equal_count;
    reg [6:0] floored_bins;
    reg [15:0] watchdog;
    wire cfg_v=(state==CFG_FWD)||(state==CFG_INV);
    wire [7:0] cfg_data=state==CFG_FWD ? 8'h01:8'h00;
    wire cfg_ready,fft_ready,fft_v,fft_last;
    wire [63:0] fft_data;
    wire [7:0] fft_user;
    wire data_v=(state==SEND_FWD)||(state==SEND_INV);
    wire [7:0] input_address={send_block,send_index};
    wire signed [23:0] fft_input_i=state==SEND_INV ? equal_i[send_index]:
        {{8{sample_i[input_address][15]}},sample_i[input_address]};
    wire signed [23:0] fft_input_q=state==SEND_INV ? equal_q[send_index]:
        {{8{sample_q[input_address][15]}},sample_q[input_address]};
    wire unexpected_last,missing_last;
    tx_fb_fft64_ip u_fft(
        .aclk(clk),.aresetn(rst_n),
        .s_axis_config_tdata(cfg_data),.s_axis_config_tvalid(cfg_v),
        .s_axis_config_tready(cfg_ready),
        .s_axis_data_tdata({fft_input_q,fft_input_i}),
        .s_axis_data_tvalid(data_v),.s_axis_data_tready(fft_ready),
        .s_axis_data_tlast(send_index==63),
        .m_axis_data_tdata(fft_data),.m_axis_data_tuser(fft_user),
        .m_axis_data_tvalid(fft_v),.m_axis_data_tready(1'b1),
        .m_axis_data_tlast(fft_last),.event_frame_started(),
        .event_tlast_unexpected(unexpected_last),
        .event_tlast_missing(missing_last),.event_status_channel_halt(),
        .event_data_in_channel_halt(),.event_data_out_channel_halt()
    );
    function signed [19:0] sat20;
        input signed [37:0] x;
        begin
            if(x>38'sd524287)sat20=20'sd524287;
            else if(x< -38'sd524288)sat20= -20'sd524288;
            else sat20=x[19:0];
        end
    endfunction
    function signed [23:0] sat24;
        input signed [60:0] x;
        begin
            if(x>61'sd8388607)sat24=24'sd8388607;
            else if(x< -61'sd8388608)sat24= -24'sd8388608;
            else sat24=x[23:0];
        end
    endfunction
    function signed [15:0] sat16;
        input signed [37:0] x;
        begin
            if(x>38'sd32767)sat16=16'sd32767;
            else if(x< -38'sd32768)sat16= -16'sd32768;
            else sat16=x[15:0];
        end
    endfunction
    // A balanced binary leading-one encoder, instead of a 41-deep priority
    // chain. Denominator normalization and reciprocal ROM have separate stages.
    function [5:0] leading_one;
        input [40:0] d;
        reg [40:0] x; reg [5:0] e;
        begin
            x=d;e=0;
            if(|x[40:32])begin x=x>>32;e=e+32;end
            if(|x[31:16])begin x=x>>16;e=e+16;end
            if(|x[15:8])begin x=x>>8;e=e+8;end
            if(|x[7:4])begin x=x>>4;e=e+4;end
            if(|x[3:2])begin x=x>>2;e=e+2;end
            if(x[1])e=e+1;
            leading_one=e;
        end
    endfunction
    wire signed [30:0] fft_raw_i=$signed(fft_data[30:0]);
    wire signed [30:0] fft_raw_q=$signed(fft_data[62:32]);
    wire signed [19:0] fft_unit_i=sat20(fft_raw_i>>>3);
    wire signed [19:0] fft_unit_q=sat20(fft_raw_q>>>3);
    wire [5:0] fft_index=fft_user[5:0];

    // H=(FFT(train1)/8+FFT(train2)/8)*conj(FFT(local)/8)/2.
    // The local even-length ZC has unit-magnitude unitary spectrum.
    reg hv0,hv1,hv2;
    reg [5:0] hi0,hi1,hi2;
    reg signed [20:0] sum_t_i,sum_t_q;
    reg signed [15:0] local_i,local_q;
    (* use_dsp="yes" *) reg signed [36:0] ht_ii,ht_qq,ht_qi,ht_iq;
    reg signed [37:0] hsum_i,hsum_q;

    // ZF numerator Y*conj(H) and denominator |H|^2 in F26.
    reg [12:0] zv;
    reg [5:0] zi[0:12];
    reg yv0,yv1;
    reg [5:0] yi0,yi1;
    reg signed [19:0] read_y_i,read_y_q,read_h_i,read_h_q;
    (* use_dsp="yes" *) reg signed [37:0] yl_ii,yl_qq,yl_qi,yl_iq,hl_ii,hl_qq;
    (* use_dsp="yes" *) reg signed [22:0] yh_ii,yh_qq,yh_qi,yh_iq,hh_ii,hh_qq;
    reg signed [39:0] yn_ii,yn_qq,yn_qi,yn_iq,hd_ii,hd_qq;
    reg signed [40:0] numerator_i,numerator_q;
    reg [40:0] denominator;
    reg signed [40:0] ni2,nq2,ni3,nq3,ni4,nq4,ni5,nq5,ni6,nq6;
    reg [40:0] den2,den3,normalized4;
    reg [5:0] exponent3,exponent4,shift5,shift6,shift7,shift8,shift9;
    // Round the Q18 table to unsigned17-bit Q17. Its positive signed18
    // representation fits the DSP48 B multiplier input without a DSP cascade.
    reg [18:0] reciprocal_raw5;
    reg signed [17:0] reciprocal6;
    // Split the 41x19 product across DSP-friendly pieces. Low twenty bits
    // are unsigned; the signed upper twenty-one bits preserve negative values.
    (* use_dsp="yes" *) reg signed [39:0] low_i6,low_q6;
    (* use_dsp="yes" *) reg signed [40:0] high_i6,high_q6;
    reg signed [60:0] quotient_i7,quotient_q7;
    reg signed [60:0] quotient_i8,quotient_q8,quotient_i9,quotient_q9;
    reg [2:0] low_shift8;
    reg signed [23:0] answer_i10,answer_q10;
    // Free-running operand registers isolate the reciprocal ROM region from
    // the four DSP multipliers. Valid/index/exponent are delayed one cycle.
    reg signed [20:0] mult_low_i,mult_low_q,mult_high_i,mult_high_q;
    reg signed [17:0] mult_reciprocal;
    always @(posedge clk)begin
        reciprocal_raw5<=recip_rom[normalized4[39:30]];
        mult_low_i<=$signed({1'b0,ni6[19:0]});
        mult_low_q<=$signed({1'b0,nq6[19:0]});
        mult_high_i<=$signed(ni6[40:20]);mult_high_q<=$signed(nq6[40:20]);
        mult_reciprocal<=reciprocal6;
        low_i6<=mult_low_i*mult_reciprocal;
        low_q6<=mult_low_q*mult_reciprocal;
        high_i6<=mult_high_i*mult_reciprocal;
        high_q6<=mult_high_q*mult_reciprocal;
    end
    // Local valid bits own this pure-data pipeline. A new start invalidates
    // zv in the control process below, so advancing stale data on the abort
    // edge is harmless. This avoids routing the parent decoder-state/start
    // decode into every arithmetic stage's enable without adding latency.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            numerator_i<=0;numerator_q<=0;denominator<=0;
            ni2<=0;nq2<=0;ni3<=0;nq3<=0;ni4<=0;nq4<=0;ni5<=0;nq5<=0;ni6<=0;nq6<=0;
            den2<=0;den3<=0;normalized4<=0;exponent3<=0;exponent4<=0;
            shift5<=0;shift6<=0;shift7<=0;shift8<=0;shift9<=0;reciprocal6<=0;
            quotient_i7<=0;quotient_q7<=0;quotient_i8<=0;quotient_q8<=0;
            quotient_i9<=0;quotient_q9<=0;low_shift8<=0;answer_i10<=0;answer_q10<=0;
        end else begin
            if(zv[0])begin
                numerator_i<={yn_ii[39],yn_ii}+{yn_qq[39],yn_qq};
                numerator_q<={yn_qi[39],yn_qi}-{yn_iq[39],yn_iq};
                denominator<={1'b0,hd_ii}+{1'b0,hd_qq};
            end
            if(zv[1])begin
                ni2<=numerator_i;nq2<=numerator_q;
                den2<=denominator<DENOM_FLOOR ? DENOM_FLOOR:denominator;
            end
            if(zv[2])begin ni3<=ni2;nq3<=nq2;den3<=den2;exponent3<=leading_one(den2);end
            if(zv[3])begin ni4<=ni3;nq4<=nq3;normalized4<=den3<<(40-exponent3);exponent4<=exponent3;end
            if(zv[4])begin ni5<=ni4;nq5<=nq4;
                shift5<=exponent4+6'd4;end
            if(zv[5])begin
                ni6<=ni5;nq6<=nq5;shift6<=shift5;
                reciprocal6<={1'b0,reciprocal_raw5[17:1]}+reciprocal_raw5[0];
            end
            if(zv[6])shift7<=shift6;
            if(zv[7])shift8<=shift7;
            if(zv[8])begin
                quotient_i7<=($signed({{20{high_i6[40]}},high_i6})<<<20)+$signed({21'b0,low_i6});
                quotient_q7<=($signed({{20{high_q6[40]}},high_q6})<<<20)+$signed({21'b0,low_q6});shift9<=shift8;
            end
            if(zv[9])begin quotient_i8<=quotient_i7>>>{shift9[5:3],3'b0};
                quotient_q8<=quotient_q7>>>{shift9[5:3],3'b0};low_shift8<=shift9[2:0];end
            if(zv[10])begin quotient_i9<=quotient_i8>>>low_shift8;quotient_q9<=quotient_q8>>>low_shift8;end
            if(zv[11])begin answer_i10<=sat24(quotient_i9);answer_q10<=sat24(quotient_q9);end
        end
    end
    integer k;
    // Memories have no reset. Explicit write ports permit LUT-RAM inference;
    // reset/start invalidate the addressing/valid counters instead.
    always @(posedge clk)begin
        // Stale writes on an abort/start cycle are harmless: start clears all
        // validity/counters and each subsequent FFT block is fully rewritten.
        // Avoid a parent decoder-state decode in local RAM write enables.
        if(rst_n&&busy)begin
            if(in_v&&in_block<3)begin
                sample_i[{in_block,in_index}]<=in_i;
                sample_q[{in_block,in_index}]<=in_q;
            end
            if(fft_v&&result_block==0)begin
                train_i[fft_index]<=fft_unit_i;train_q[fft_index]<=fft_unit_q;
            end
            if(hv2)begin channel_i[hi2]<=sat20(hsum_i>>>14);
                channel_q[hi2]<=sat20(hsum_q>>>14);end
            if(zv[12])begin equal_i[zi[12]]<=answer_i10;equal_q[zi[12]]<=answer_q10;end
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            state<=IDLE;received<=0;send_block<=0;send_index<=0;
            result_block<=0;equal_count<=0;floored_bins<=0;watchdog<=0;busy<=0;done<=0;fault<=0;
            out_v<=0;out_index<=0;out_i<=0;out_q<=0;
            hv0<=0;hv1<=0;hv2<=0;hi0<=0;hi1<=0;hi2<=0;
            sum_t_i<=0;sum_t_q<=0;local_i<=0;local_q<=0;
            ht_ii<=0;ht_qq<=0;ht_qi<=0;ht_iq<=0;hsum_i<=0;hsum_q<=0;
            zv<=0;yn_ii<=0;yn_qq<=0;yn_qi<=0;yn_iq<=0;hd_ii<=0;hd_qq<=0;
            yv0<=0;yv1<=0;yi0<=0;yi1<=0;
            read_y_i<=0;read_y_q<=0;read_h_i<=0;read_h_q<=0;
            yl_ii<=0;yl_qq<=0;yl_qi<=0;yl_iq<=0;hl_ii<=0;hl_qq<=0;
            yh_ii<=0;yh_qq<=0;yh_qi<=0;yh_iq<=0;hh_ii<=0;hh_qq<=0;
            for(k=0;k<=12;k=k+1)zi[k]<=0;
        end else begin
            done<=0;out_v<=0;
            hv0<=0;hv1<=hv0;hv2<=hv1;hi1<=hi0;hi2<=hi1;
            yv0<=0;yv1<=yv0;yi1<=yi0;
            zv<={zv[11:0],1'b0};for(k=1;k<=12;k=k+1)zi[k]<=zi[k-1];
            if(start)begin
                state<=CFG_FWD;received<=0;send_block<=0;send_index<=0;
                result_block<=0;equal_count<=0;floored_bins<=0;watchdog<=0;busy<=1;fault<=0;
                hv0<=0;hv1<=0;hv2<=0;zv<=0;
                yv0<=0;yv1<=0;
            end else if(busy)begin
                watchdog<=watchdog+1'b1;
                if(watchdog==16'd4095)begin fault<=1;busy<=0;done<=1;state<=IDLE;end
                if(unexpected_last||missing_last)fault<=1;
                if(in_v)begin
                    received<=received+1'b1;
                    if({in_block,in_index}!=received||received>=192)fault<=1;
                end
                case(state)
                    CFG_FWD:if(cfg_ready)state<=WAIT_BLOCK;
                    WAIT_BLOCK:if(received>={1'b0,send_block,6'b0}+8'd64)begin
                        send_index<=0;state<=SEND_FWD;end
                    SEND_FWD:if(fft_ready)begin
                        if(send_index==63)begin
                            if(send_block==2)state<=WAIT_EQUAL;
                            else begin send_block<=send_block+1'b1;state<=WAIT_BLOCK;end
                            send_index<=0;
                        end else send_index<=send_index+1'b1;
                    end
                    WAIT_EQUAL:if(equal_count==64)state<=CFG_INV;
                    CFG_INV:if(cfg_ready)begin send_index<=0;state<=SEND_INV;end
                    SEND_INV:if(fft_ready)begin
                        if(send_index==63)begin send_index<=0;state<=WAIT_RESULT;end
                        else send_index<=send_index+1'b1;
                    end
                    default:begin end
                endcase
                if(fft_v)begin
                    if(result_block==0)begin
                    end else if(result_block==1)begin
                        sum_t_i<={train_i[fft_index][19],train_i[fft_index]}+
                            {fft_unit_i[19],fft_unit_i};
                        sum_t_q<={train_q[fft_index][19],train_q[fft_index]}+
                            {fft_unit_q[19],fft_unit_q};
                        local_i<=$signed(local_t[fft_index][15:0]);
                        local_q<=$signed(local_t[fft_index][31:16]);
                        hv0<=1;hi0<=fft_index;
                    end else if(result_block==2)begin
                        read_y_i<=fft_unit_i;read_y_q<=fft_unit_q;
                        read_h_i<=channel_i[fft_index];read_h_q<=channel_q[fft_index];
                        yv0<=1;yi0<=fft_index;
                    end else begin
                        out_v<=1;out_index<=fft_index;
                        out_i<=sat16(fft_raw_i>>>3);out_q<=sat16(fft_raw_q>>>3);
                        if(fft_last)begin busy<=0;done<=1;state<=IDLE;end
                    end
                    if(fft_last)result_block<=result_block+1'b1;
                end
                if(hv0)begin
                    ht_ii<=sum_t_i*local_i;ht_qq<=sum_t_q*local_q;
                    ht_qi<=sum_t_q*local_i;ht_iq<=sum_t_i*local_q;
                end
                if(hv1)begin
                    hsum_i<={ht_ii[36],ht_ii}+{ht_qq[36],ht_qq};
                    hsum_q<={ht_qi[36],ht_qi}-{ht_iq[36],ht_iq};
                end
                if(yv0)begin
                    yl_ii<=read_y_i*$signed({1'b0,read_h_i[16:0]});
                    yl_qq<=read_y_q*$signed({1'b0,read_h_q[16:0]});
                    yl_qi<=read_y_q*$signed({1'b0,read_h_i[16:0]});
                    yl_iq<=read_y_i*$signed({1'b0,read_h_q[16:0]});
                    hl_ii<=read_h_i*$signed({1'b0,read_h_i[16:0]});
                    hl_qq<=read_h_q*$signed({1'b0,read_h_q[16:0]});
                    yh_ii<=read_y_i*$signed(read_h_i[19:17]);
                    yh_qq<=read_y_q*$signed(read_h_q[19:17]);
                    yh_qi<=read_y_q*$signed(read_h_i[19:17]);
                    yh_iq<=read_y_i*$signed(read_h_q[19:17]);
                    hh_ii<=read_h_i*$signed(read_h_i[19:17]);
                    hh_qq<=read_h_q*$signed(read_h_q[19:17]);
                end
                if(yv1)begin
                    yn_ii<=($signed({{17{yh_ii[22]}},yh_ii})<<<17)+$signed({{2{yl_ii[37]}},yl_ii});
                    yn_qq<=($signed({{17{yh_qq[22]}},yh_qq})<<<17)+$signed({{2{yl_qq[37]}},yl_qq});
                    yn_qi<=($signed({{17{yh_qi[22]}},yh_qi})<<<17)+$signed({{2{yl_qi[37]}},yl_qi});
                    yn_iq<=($signed({{17{yh_iq[22]}},yh_iq})<<<17)+$signed({{2{yl_iq[37]}},yl_iq});
                    hd_ii<=($signed({{17{hh_ii[22]}},hh_ii})<<<17)+$signed({{2{hl_ii[37]}},hl_ii});
                    hd_qq<=($signed({{17{hh_qq[22]}},hh_qq})<<<17)+$signed({{2{hl_qq[37]}},hl_qq});
                    zv[0]<=1;zi[0]<=yi1;
                end
                if(zv[1])begin
                    // A wholly absent training channel must not turn all-zero
                    // data into the accidentally CRC-valid all-zero message.
                    if(denominator<DENOM_FLOOR)begin
                        floored_bins<=floored_bins+1'b1;
                        if(zi[1]==63&&floored_bins==63)fault<=1;
                    end
                end
                if(zv[12])equal_count<=equal_count+1'b1;
            end
        end
    end
endmodule
`default_nettype wire
