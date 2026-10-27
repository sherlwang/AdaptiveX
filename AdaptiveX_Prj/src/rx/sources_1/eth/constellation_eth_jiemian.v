`timescale 1ns / 1ps
`default_nettype none

// MAC1: original 256 payload bytes followed by an 8-byte RX tag.
// Only a newly completed, same-frame 31-word constellation window can be sent.
module constellation_eth_jiemian #(
    parameter [23:0] cnt_cycle_max = 24'h1c2000,
    parameter integer PACKET_LEN = 306
)(
    input wire clk_phy,
    input wire [31:0] cone_i,
    input wire [31:0] cone_q,
    input wire cone_v,
    input wire [3:0] cone_ploy,
    input wire [1:0] cone_modulation,
    input wire [31:0] cone_frame_id,
    input wire [31:0] err_bit,
    input wire [31:0] all_bit,
    output wire stat_request,
    input wire clk_gen,
    input wire rst,
    input wire rst_phy,
    input wire gen_tready,
    output wire [63:0] gen_tdata,
    output wire gen_tvalid,
    output wire [7:0] gen_tkeep,
    output wire gen_tlast
);
    function [31:0] little32;
        input [31:0] value;
        begin little32 = {value[7:0], value[15:8], value[23:16], value[31:24]}; end
    endfunction
    function [63:0] mac_lanes;
        input [63:0] value;
        integer byte_index;
        begin
            for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1)
                mac_lanes[byte_index*8 +: 8] = value[63-byte_index*8 -: 8];
        end
    endfunction
    function [15:0] ipv4_checksum;
        input [159:0] header;
        reg [31:0] sum;
        integer word_index;
        begin
            sum = 0;
            for (word_index = 0; word_index < 10; word_index = word_index + 1)
                sum = sum + header[word_index*16 +: 16];
            sum = {16'd0, sum[15:0]} + {16'd0, sum[31:16]};
            sum = {16'd0, sum[15:0]} + {16'd0, sum[31:16]};
            ipv4_checksum = ~sum[15:0];
        end
    endfunction

    localparam [15:0] IP_LENGTH = PACKET_LEN - 14;
    localparam [15:0] UDP_LENGTH = PACKET_LEN - 34;
    localparam [111:0] ETH_HEADER = {48'hffffffffffff, 48'h000a35000102, 16'h0800};
    localparam [159:0] IP_ZERO_CHECK = {
        8'h45, 8'h01, IP_LENGTH, 16'd0, 16'd0, 8'd128, 8'd17,
        16'd0, 32'hc0a8024d, 32'hc0a80258};
    localparam [159:0] IP_HEADER = {
        IP_ZERO_CHECK[159:80], ipv4_checksum(IP_ZERO_CHECK), IP_ZERO_CHECK[63:0]};
    // IPv4 UDP checksum zero retains the previous protocol contract.
    localparam [63:0] UDP_HEADER = {16'd8001, 16'd8001, UDP_LENGTH, 16'd0};

    wire [103:0] input_word = {2'b0, cone_frame_id, cone_ploy,
                               cone_modulation, cone_q, cone_i};
    wire [103:0] sample_word;
    wire sample_valid, sample_ready;
    Constellation_Metadata_FIFO #(.ASYNC(1), .DEPTH(256)) u_sample_cdc (
        .wr_clk(clk_phy), .rd_clk(clk_gen), .rst(rst_phy || rst),
        .wr_data(input_word), .wr_valid(cone_v), .wr_ready(sample_ready),
        .rd_data(sample_word), .rd_valid(sample_valid), .rd_ready(1'b1)
    );
    wire [3:0] sample_p = sample_word[69:66];
    wire [1:0] sample_m = sample_word[65:64];
    wire [31:0] sample_frame = sample_word[101:70];
    wire sample_mode_valid = (sample_p == 2 || sample_p == 4 || sample_p == 8) && sample_m != 3;
    // Payload order: I0lo,I0hi,I1lo,I1hi,Q0lo,Q0hi,Q1lo,Q1hi.
    wire [63:0] sample_bytes = {little32(sample_word[31:0]), little32(sample_word[63:32])};
    reg [4:0] collected;
    reg [3:0] collect_p;
    reg [1:0] collect_m;
    reg [31:0] collect_frame;
    reg [1983:0] collect_iq;
    reg [1983:0] snapshot_iq;
    reg [3:0] snapshot_p;
    reg [1:0] snapshot_m;
    reg [31:0] snapshot_frame;
    reg snapshot_valid;
    reg [23:0] cycle_count;
    reg [2495:0] packet_shift;
    reg [5:0] beat_index;
    reg tx_active;
    wire launch = cycle_count == 24'd80 && snapshot_valid && !tx_active;
    assign stat_request = !rst && cycle_count == 24'd50;
    assign gen_tdata = mac_lanes(packet_shift[2495:2432]);
    assign gen_tvalid = tx_active;
    assign gen_tkeep = tx_active ? (beat_index == 38 ? 8'h03 : 8'hff) : 8'h00;
    assign gen_tlast = tx_active && beat_index == 38;

    always @(posedge clk_gen) begin
        if (rst) begin
            cycle_count <= 0;
            collected <= 0;
            collect_p <= 0;
            collect_m <= 0;
            collect_frame <= 0;
            collect_iq <= 0;
            snapshot_iq <= 0;
            snapshot_p <= 0;
            snapshot_m <= 0;
            snapshot_frame <= 0;
            snapshot_valid <= 0;
            packet_shift <= 0;
            beat_index <= 0;
            tx_active <= 0;
        end else begin
            // Fixed wall-clock interval. A MAC stall cannot advance its held beat.
            cycle_count <= cycle_count == cnt_cycle_max ? 0 : cycle_count + 1'b1;
            if (tx_active && gen_tready) begin
                if (beat_index == 38) begin
                    tx_active <= 0;
                    beat_index <= 0;
                end else begin
                    packet_shift <= {packet_shift[2431:0], 64'd0};
                    beat_index <= beat_index + 1'b1;
                end
            end
            if (launch) begin
                packet_shift <= {ETH_HEADER, IP_HEADER, UDP_HEADER,
                    snapshot_iq, little32(all_bit), little32(err_bit),
                    16'h5258, 8'd1, {1'b1, 1'b0, snapshot_p, snapshot_m},
                    little32(snapshot_frame), 48'd0};
                tx_active <= 1;
                beat_index <= 0;
                snapshot_valid <= 0;
            end

            // A complete window may replace an unsent one, never the active packet.
            // Publishing last preserves a fresh window on the same launch edge.
            if (sample_valid) begin
                if (!sample_mode_valid) begin
                    collected <= 0;
                end else if (collected == 0 || sample_frame != collect_frame ||
                             sample_p != collect_p || sample_m != collect_m) begin
                    collect_iq <= {1920'd0, sample_bytes};
                    collected <= 1;
                    collect_frame <= sample_frame;
                    collect_p <= sample_p;
                    collect_m <= sample_m;
                end else if (collected == 30) begin
                    snapshot_iq <= {collect_iq[1919:0], sample_bytes};
                    snapshot_p <= collect_p;
                    snapshot_m <= collect_m;
                    snapshot_frame <= collect_frame;
                    snapshot_valid <= 1;
                    collected <= 0;
                end else begin
                    collect_iq <= {collect_iq[1919:0], sample_bytes};
                    collected <= collected + 1'b1;
                end
            end
        end
    end
endmodule
`default_nettype wire
