`timescale 1ns / 1ps
`default_nettype none
// Spare ADC receiver and atomic transfers to the business/ILA clock domain.
// Reset is independent of business P/M changes. No received position/CFO hints.
module tx_fb_receiver #(
    parameter integer DEBUG_ILA = 0
)(
    input wire clk_adc,input wire clk_fast, input wire clk_slow, input wire arst_n,
    input wire [191:0] adc_i,input wire [191:0] adc_q,input wire adc_valid,
    output reg packet_v, output reg [23:0] packet24,
    output reg signed [31:0] packet_cfo,
    output reg [3:0] packet_pn, output reg [6:0] packet_phase,
    output reg const_v, output reg signed [15:0] const_i,
    output reg signed [15:0] const_q, output reg [5:0] const_index,
    output wire [31:0] status, output reg [31:0] received_count
);
    wire adc_rst_n,fast_rst_n,slow_rst_n;
    wire signed [15:0] adc_symbol_i,adc_symbol_q;
    wire adc_symbol_v,stream_error;
    wire [6:0] adc_symbol_phase;
    reg signed [15:0] sym_i,sym_q;
    reg sym_v;
    reg [6:0] phase_select;
    reg [6:0] phase_fast;
    wire adjust_v;
    wire [6:0] adjust;
    wire pkt_v,point_v,locked,bad_crc;
    wire [23:0] pkt;
    wire signed [15:0] point_i,point_q;
    wire [5:0] point_index;
    wire [3:0] pn_index;
    wire signed [31:0] cfo;
    wire [31:0] good_count,crc_count,reacquire_count;
    wire packet_empty,point_empty,packet_full,point_full;
    wire packet_overflow,point_overflow;
    wire [71:0] packet_head;
    wire [39:0] point_head;
    wire [4:0] packet_level;
    wire [7:0] point_level;
    reg bad_crc_seen,reacquire_seen;
    wire symbol_full,symbol_empty,symbol_overflow;
    wire adjustment_full,adjustment_empty,adjustment_overflow;
    wire [38:0] symbol_head;
    wire [6:0] adjustment_head;
    wire [5:0] symbol_level;
    wire [2:0] adjustment_level;
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [7:0] flags_meta,flags_sync;
    reset_sync u_adc_reset(.clk(clk_adc),.arst_n(arst_n),.rst_n(adc_rst_n));
    reset_sync u_fast_reset(.clk(clk_fast),.arst_n(arst_n),.rst_n(fast_rst_n));
    reset_sync u_slow_reset(.clk(clk_slow),.arst_n(arst_n),.rst_n(slow_rst_n));
    tx_fb_frontend u_frontend(
        .clk(clk_adc),.rst_n(adc_rst_n),.adc_i(adc_i),.adc_q(adc_q),.adc_valid(adc_valid),
        .phase_select(phase_select),.symbol_i(adc_symbol_i),.symbol_q(adc_symbol_q),
        .symbol_v(adc_symbol_v),.symbol_phase(adc_symbol_phase),.stream_error(stream_error)
    );
    // The decoder still needs ten 409.6-MHz clocks per arriving symbol for
    // its eight ZC issue groups, PN classification, CFO and real XFFT/FDE.
    // Crossing I/Q/phase as one transaction avoids incoherent phase metadata.
    tx_fb_async_fifo #(.WIDTH(39),.ADDR_BITS(5)) u_symbol_fifo(
        .wr_clk(clk_adc),.rd_clk(clk_fast),.arst_n(arst_n),
        .wr_v(adc_symbol_v),.wr_data({adc_symbol_phase,adc_symbol_q,adc_symbol_i}),
        .wr_full(symbol_full),.overflow(symbol_overflow),
        .rd_en(!symbol_empty),.rd_data(symbol_head),.rd_empty(symbol_empty),.rd_level(symbol_level)
    );
    // Registered FWFT-read transaction. These named destination registers are
    // the bounded payload CDC endpoints; decoder fanout starts after them.
    // I/Q/valid/phase are captured on the same fast edge, consumed one edge
    // later, and never sampled while the FIFO reports empty.
    always@(posedge clk_fast or negedge fast_rst_n)begin
        if(!fast_rst_n)begin sym_i<=0;sym_q<=0;sym_v<=0;phase_fast<=0;end
        else begin
            sym_v<=!symbol_empty;
            if(!symbol_empty)begin
                sym_i<=symbol_head[15:0];sym_q<=symbol_head[31:16];
                phase_fast<=symbol_head[38:32];
            end
        end
    end
    // An adjustment is an event with a seven-bit payload. A two-flop bus or
    // a one-cycle fast pulse would lose/corrupt it in the ten-times slower
    // ADC domain. The reverse async FIFO transfers each event exactly once.
    tx_fb_async_fifo #(.WIDTH(7),.ADDR_BITS(2)) u_timing_fifo(
        .wr_clk(clk_fast),.rd_clk(clk_adc),.arst_n(arst_n),
        .wr_v(adjust_v),.wr_data(adjust),
        .wr_full(adjustment_full),.overflow(adjustment_overflow),
        .rd_en(!adjustment_empty),.rd_data(adjustment_head),
        .rd_empty(adjustment_empty),.rd_level(adjustment_level)
    );
    always@(posedge clk_adc or negedge adc_rst_n)begin
        if(!adc_rst_n)phase_select<=0;
        else if(!adjustment_empty && adjustment_head<12)begin
            if(phase_select>=adjustment_head)phase_select<=phase_select-adjustment_head;
            else phase_select<=7'd12+phase_select-adjustment_head;
        end
    end
    tx_fb_decoder #(.DEBUG_ILA(DEBUG_ILA)) u_decoder(
        .clk(clk_fast),.rst_n(fast_rst_n),.sym_v(sym_v),.sym_i(sym_i),.sym_q(sym_q),
        .timing_adjust_v(adjust_v),.timing_adjust(adjust),
        .packet_v(pkt_v),.packet24(pkt),.const_v(point_v),
        .const_i(point_i),.const_q(point_q),.const_index(point_index),
        .sync_locked(locked),.pn_index(pn_index),.cfo_phase_debug(cfo),
        .bad_crc(bad_crc),.packet_count(good_count),.crc_error_count(crc_count),
        .timing_reacquire_count(reacquire_count)
    );
    always@(posedge clk_fast or negedge fast_rst_n)begin
        if(!fast_rst_n)begin bad_crc_seen<=0;reacquire_seen<=0;end
        else begin
            if(adjust_v && adjust<12)reacquire_seen<=1'b1;
            if(bad_crc) bad_crc_seen<=1'b1;
        end
    end
    tx_fb_async_fifo #(.WIDTH(72),.ADDR_BITS(4)) u_packet_fifo(
        .wr_clk(clk_fast),.rd_clk(clk_slow),.arst_n(arst_n),
        .wr_v(pkt_v),.wr_data({5'd0,phase_fast,pn_index,cfo,pkt}),
        .wr_full(packet_full),.overflow(packet_overflow),
        .rd_en(!packet_empty),.rd_data(packet_head),.rd_empty(packet_empty),.rd_level(packet_level)
    );
    tx_fb_async_fifo #(.WIDTH(40),.ADDR_BITS(7)) u_point_fifo(
        .wr_clk(clk_fast),.rd_clk(clk_slow),.arst_n(arst_n),
        .wr_v(point_v),.wr_data({2'd0,point_index,point_q,point_i}),
        .wr_full(point_full),.overflow(point_overflow),
        .rd_en(!point_empty),.rd_data(point_head),.rd_empty(point_empty),.rd_level(point_level)
    );
    // Observe the complete matched-filter transaction in its own 40.96-MHz
    // domain. These one-cycle capture registers never drive the receiver.
    generate if(DEBUG_ILA) begin: gen_debug_ila
        (* KEEP="TRUE", MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg rrc_v;
        (* KEEP="TRUE", MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg signed [15:0] rrc_i,rrc_q;
        (* KEEP="TRUE", MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg [6:0] rrc_phase,rrc_phase_request;
        (* KEEP="TRUE", MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg rrc_stream_error;
        (* KEEP="TRUE", MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg rrc_timing_update;
        (* KEEP="TRUE", MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg [6:0] rrc_timing_adjust;
        always @(posedge clk_adc or negedge adc_rst_n) begin
            if(!adc_rst_n) begin
                rrc_v<=0;rrc_i<=0;rrc_q<=0;rrc_phase<=0;rrc_phase_request<=0;
                rrc_stream_error<=0;rrc_timing_update<=0;rrc_timing_adjust<=0;
            end else begin
                rrc_v<=adc_symbol_v;rrc_i<=adc_symbol_i;rrc_q<=adc_symbol_q;
                rrc_phase<=adc_symbol_phase;rrc_phase_request<=phase_select;
                rrc_stream_error<=stream_error;rrc_timing_update<=!adjustment_empty;
                rrc_timing_adjust<=adjustment_head;
            end
        end
        (* DONT_TOUCH="TRUE" *) ila_feedback_rrc u_ila_rrc(
            .clk(clk_adc),.probe0(rrc_v),.probe1(rrc_i),.probe2(rrc_q),
            .probe3(rrc_phase),.probe4(rrc_phase_request),.probe5(rrc_stream_error),
            .probe6(rrc_timing_update),.probe7(rrc_timing_adjust)
        );
    end endgenerate

    // Synchronize every sticky source bit independently. Combine diagnostics
    // only after the slow-domain synchronizers, never before a CDC boundary.
    assign status={8'd0,point_level,3'd0,packet_level,2'd0,flags_sync[5:2],
                   flags_sync[1]|flags_sync[6]|flags_sync[7],flags_sync[0]};
    always@(posedge clk_slow or negedge slow_rst_n)begin
        if(!slow_rst_n)begin
            flags_meta<=0;flags_sync<=0;packet_v<=0;packet24<=0;
            packet_cfo<=0;packet_pn<=0;packet_phase<=0;
            const_v<=0;const_i<=0;const_q<=0;const_index<=0;received_count<=0;
        end else begin
            flags_meta<={adjustment_overflow,symbol_overflow,reacquire_seen,
                         point_overflow,packet_overflow,bad_crc_seen,stream_error,locked};
            flags_sync<=flags_meta;
            packet_v<=!packet_empty;
            if(!packet_empty)begin
                packet24<=packet_head[23:0];packet_cfo<=packet_head[55:24];
                packet_pn<=packet_head[59:56];packet_phase<=packet_head[66:60];
                received_count<=received_count+1'b1;
            end
            const_v<=!point_empty;
            if(!point_empty)begin
                const_i<=point_head[15:0];const_q<=point_head[31:16];const_index<=point_head[37:32];
            end
        end
    end
endmodule
`default_nettype wire
