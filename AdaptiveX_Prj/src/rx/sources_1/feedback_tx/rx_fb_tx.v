`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Module Name: rx_fb_tx
// Description: External events -> CRC/QPSK short frame -> complex RRC6.
//              DAC231 RFDC performs 20x interpolation and the +1.2GHz mixer.
//              clk_dac=40.96MHz, 192-bit IQ-interleaved AXIS, low I0,Q0.
//              FIFO reset is board/DAC enable controlled, independent of PHY mode.
// Tool Versions: Vivado 2021.2, Verilog-2001
//////////////////////////////////////////////////////////////////////////////////
module rx_fb_tx #(
    parameter integer USE_ILA=0
)(
    input  wire                    clk_src,
    input  wire                    clk_dac,
    input  wire                    arst_n,
    input  wire                    event_v,
    input  wire [15:0]             event_payload,
    output wire                    event_ready,
    input  wire                    dac_ready,
    output wire [191:0]            dac_data,
    output wire                    dac_valid,
    output wire                    frame_start,
    output wire                    frame_busy,
    output wire [23:0]             packet24,
    output wire [31:0]             frames_sent,
    output wire [5:0]              fifo_level,
    output wire                    event_overflow,
    output reg                     stall_seen
);
    wire rst_n;
    wire src_rst_n;
    wire in_pop,in_empty,in_full;
    wire [15:0] in_payload;
    wire advance=dac_ready;
    wire sym_ce,sym_v;
    wire signed [15:0] sym_i,sym_q;
    wire [8:0] symbol_index;
    wire [95:0] rrc_i,rrc_q;
    wire rrc_v;
    genvar iq_lane;
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [1:0] overflow_sync;
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [1:0] full_sync;
    reg full_src_status;
    reg have_ready;
    reg [31:0] stall_cycles;
    // Source-domain acceptance prevents the internal test source from losing
    // controller messages while the DAC interface is temporarily stalled.
    assign event_ready = src_rst_n && !in_full;
    rx_fb_reset_sync u_dac_reset(.clk(clk_dac),.arst_n(arst_n),.rst_n(rst_n));
    rx_fb_reset_sync u_src_reset(.clk(clk_src),.arst_n(arst_n),.rst_n(src_rst_n));
    // Register the diagnostic at its source before the two-flop CDC. wr_full
    // includes local reset-release logic, so crossing it directly adds a mux
    // ahead of the synchronizer. This status does not control the FIFO itself.
    always@(posedge clk_src or negedge src_rst_n)begin
        if(!src_rst_n) full_src_status<=1'b0;
        else full_src_status<=in_full;
    end
    rx_fb_event_fifo #(.ADDR_WIDTH(5)) u_event_fifo(
        .wr_clk(clk_src),.rd_clk(clk_dac),.arst_n(arst_n),
        .wr_v(event_v),.wr_data(event_payload),.wr_full(in_full),
        .overflow(event_overflow),.rd_en(in_pop),.rd_data(in_payload),
        .rd_empty(in_empty),.rd_level(fifo_level)
    );
    rx_fb_framer u_framer(
        .clk(clk_dac),.rst_n(rst_n),.advance(advance),.symbol_ce(sym_ce),
        .in_empty(in_empty),.in_payload16(in_payload),.in_pop(in_pop),
        .symbol_i(sym_i),.symbol_q(sym_q),.symbol_v(sym_v),
        .frame_start(frame_start),.frame_busy(frame_busy),.packet24(packet24),
        .frames_sent(frames_sent),.symbol_index(symbol_index)
    );
    rx_fb_rrc6 u_rrc(
        .clk(clk_dac),.rst_n(rst_n),.advance(advance),
        .din_i(sym_i),.din_q(sym_q),.din_v(sym_v),.symbol_ce(sym_ce),
        .dout_i(rrc_i),.dout_q(rrc_q),.dout_v(rrc_v)
    );
    // RFDC dual-DAC IQ->Real expects scalar words I0,Q0,I1,Q1,...,I5,Q5
    // from low bits to high bits; there are six complex samples per beat.
    generate
        for(iq_lane=0;iq_lane<6;iq_lane=iq_lane+1) begin: pack_iq
            assign dac_data[32*iq_lane+:16]=rrc_i[16*iq_lane+:16];
            assign dac_data[32*iq_lane+16+:16]=rrc_q[16*iq_lane+:16];
        end
    endgenerate
    assign dac_valid=rrc_v;
    // AXIS backpressure freezes digital sample time. A physical DAC may underflow;
    // expose any ready withdrawal instead of silently claiming RF continuity.
    always@(posedge clk_dac or negedge rst_n)begin
        if(!rst_n)begin
            overflow_sync<=2'd0;full_sync<=2'd0;have_ready<=1'b0;
            stall_seen<=1'b0;stall_cycles<=32'd0;
        end
        else begin
            overflow_sync<={overflow_sync[0],event_overflow};
            full_sync<={full_sync[0],full_src_status};
            if(dac_ready) have_ready<=1'b1;
            if(have_ready && !dac_ready)begin
                stall_seen<=1'b1;
                stall_cycles<=stall_cycles+1'b1;
            end
        end
    end
    // Board-level RF ILA observes the exact packed DAC interface and raw ADC.
    // USE_ILA remains a compatibility parameter; no legacy ILA is instantiated.
endmodule
`default_nettype wire
