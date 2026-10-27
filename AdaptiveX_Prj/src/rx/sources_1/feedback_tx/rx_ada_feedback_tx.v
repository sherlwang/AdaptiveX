`timescale 1ns / 1ps
`default_nettype none

// One accepted Ada result creates one short feedback frame; held result fields
// alone never create an event. All input metadata must accompany event_v in
// clk_src (204.8 MHz). The whole 16-bit message crosses one 32-entry FIFO.
// arst_n is the board/startup reset, never the Ada-only 2273-clock reset.
// tx_ready includes local reset release and queue space. A pulse while full
// is dropped and raises sticky event_overflow; the source is not backpressured.
// Idle AXIS remains valid and carries zero after the completed RRC tail.
module rx_ada_feedback_tx (
    input wire clk_src,
    input wire clk_dac,
    input wire arst_n,
    input wire event_v,
    input wire [3:0] current_mode,
    input wire [3:0] recommended_mode,
    input wire [31:0] frame_id,
    input wire dac_ready,
    output wire tx_ready,
    output wire [191:0] dac_data,
    output wire dac_valid,
    output wire frame_start,
    output wire frame_busy,
    output wire [23:0] packet24,
    output reg [31:0] events_accepted,
    output wire [31:0] frames_sent,
    output wire [5:0] fifo_level,
    output wire event_overflow,
    output wire stall_seen
);
    wire src_rst_n;
    wire [15:0] event_payload =
        {current_mode, recommended_mode, 2'b00, frame_id[5:0]};

    rx_fb_reset_sync u_count_reset (
        .clk(clk_src), .arst_n(arst_n), .rst_n(src_rst_n));
    always @(posedge clk_src or negedge src_rst_n) begin
        if (!src_rst_n) events_accepted <= 32'd0;
        else if (event_v && tx_ready)
            events_accepted <= events_accepted + 1'b1;
    end

    // Do not gate wr_v with tx_ready: the FIFO must observe full-queue pulses
    // to report overflow. Its own reset/full logic qualifies actual writes.
    rx_fb_tx #(.USE_ILA(0)) u_tx (
        .clk_src(clk_src), .clk_dac(clk_dac), .arst_n(arst_n),
        .event_v(event_v), .event_payload(event_payload), .event_ready(tx_ready),
        .dac_ready(dac_ready), .dac_data(dac_data), .dac_valid(dac_valid),
        .frame_start(frame_start), .frame_busy(frame_busy), .packet24(packet24),
        .frames_sent(frames_sent), .fifo_level(fifo_level),
        .event_overflow(event_overflow), .stall_seen(stall_seen));
endmodule
`default_nettype wire
