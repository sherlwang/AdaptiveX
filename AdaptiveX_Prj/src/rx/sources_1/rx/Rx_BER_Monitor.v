`timescale 1ns / 1ps
`default_nettype none

// Zero-reference BER: disjoint packet intervals and optional cumulative VIO counts.
module Rx_BER_Monitor (
    input wire clk_phy,
    input wire rst_n_phy,
    input wire enable,
    input wire [31:0] din,
    input wire din_v,
    input wire [5:0] din_width,
    input wire clk_eth,
    input wire rst_n_eth,
    input wire packet_request,
    output reg [31:0] packet_errors,
    output reg [31:0] packet_bits,
    output reg [63:0] total_errors,
    output reg [63:0] total_bits,
    output reg window_full
);
    reg [31:0] bit_mask;
    wire [31:0] masked_din;
    reg [3:0] count_d1[0:3];
    reg [4:0] count_d2[0:1];
    reg [5:0] count_d3;
    reg [2:0] valid_d;
    reg [5:0] width_d1;
    reg [5:0] width_d2;
    reg [5:0] width_d3;
    reg [31:0] window_errors;
    reg [31:0] window_bits;
    wire request_phy;
    reg [63:0] snapshot_data;
    reg snapshot_send;
    wire snapshot_received;
    wire [63:0] snapshot_eth;
    wire snapshot_eth_v;
    wire include_now;
    wire [31:0] next_errors;
    wire [31:0] next_bits;
    integer lane;

    function [3:0] count8;
        input [7:0] bits;
        integer k;
        begin
            count8 = 0;
            for (k = 0; k < 8; k = k + 1) count8 = count8 + bits[k];
        end
    endfunction

    always @(*) begin
        case (din_width)
            2: bit_mask = 32'h00000003;
            4: bit_mask = 32'h0000000f;
            8: bit_mask = 32'h000000ff;
            16: bit_mask = 32'h0000ffff;
            32: bit_mask = 32'hffffffff;
            default: bit_mask = 0;
        endcase
    end
    assign masked_din = din & bit_mask;

    // Three stages, one input per clock.  Ignore unused high bits.
    always @(posedge clk_phy) begin
        if (!rst_n_phy || !enable) begin
            valid_d  <= 0;
            width_d1 <= 0;
            width_d2 <= 0;
            width_d3 <= 0;
            count_d3 <= 0;
            for (lane = 0; lane < 4; lane = lane + 1) count_d1[lane] <= 0;
            count_d2[0] <= 0;
            count_d2[1] <= 0;
        end else begin
            valid_d  <= {valid_d[1:0], din_v};
            width_d1 <= din_width;
            width_d2 <= width_d1;
            width_d3 <= width_d2;
            for (lane = 0; lane < 4; lane = lane + 1) count_d1[lane] <= count8(masked_din[lane*8+:8]);
            count_d2[0] <= {1'b0, count_d1[0]} + {1'b0, count_d1[1]};
            count_d2[1] <= {1'b0, count_d1[2]} + {1'b0, count_d1[3]};
            count_d3 <= {1'b0, count_d2[0]} + {1'b0, count_d2[1]};
        end
    end

    xpm_cdc_pulse #(
        .DEST_SYNC_FF(3),
        .INIT_SYNC_FF(1),
        .REG_OUTPUT  (1),
        .RST_USED    (1)
    ) u_packet_request (
        .src_clk   (clk_eth),
        .src_rst   (!rst_n_eth),
        .src_pulse (packet_request),
        .dest_clk  (clk_phy),
        .dest_rst  (!rst_n_phy),
        .dest_pulse(request_phy)
    );

    assign include_now = enable && valid_d[2] && !window_full && window_bits <= 32'hffffffdf;
    assign next_errors = window_errors + (include_now ? {26'd0, count_d3} : 32'd0);
    assign next_bits   = window_bits + (include_now ? {26'd0, width_d3} : 32'd0);

    // Snapshot both counts together; the next input starts a new interval.
    always @(posedge clk_phy) begin
        if (!rst_n_phy) begin
            total_errors <= 0;
            total_bits <= 0;
            window_errors <= 0;
            window_bits <= 0;
            window_full <= 0;
            snapshot_data <= 0;
            snapshot_send <= 0;
        end else begin
            if (snapshot_send && snapshot_received) snapshot_send <= 0;
            if (!enable) begin
                total_errors <= 0;
                total_bits <= 0;
                window_errors <= 0;
                window_bits <= 0;
                window_full <= 0;
            end else begin
                if (valid_d[2]) begin
                    total_errors <= total_errors + {58'd0, count_d3};
                    total_bits   <= total_bits + {58'd0, width_d3};
                    if (window_bits > 32'hffffffdf) window_full <= 1;
                end
                window_errors <= next_errors;
                window_bits   <= next_bits;
            end
            if (request_phy && !snapshot_send && !snapshot_received) begin
                snapshot_data <= enable ? {next_bits, next_errors} : 64'd0;
                snapshot_send <= 1;
                window_errors <= 0;
                window_bits   <= 0;
                window_full   <= 0;
            end
        end
    end

    xpm_cdc_handshake #(
        .DEST_EXT_HSK  (0),
        .DEST_SYNC_FF  (3),
        .SRC_SYNC_FF   (3),
        .INIT_SYNC_FF  (1),
        .SIM_ASSERT_CHK(1),
        .WIDTH         (64)
    ) u_packet_counts (
        .src_clk (clk_phy),
        .src_in  (snapshot_data),
        .src_send(snapshot_send),
        .src_rcv (snapshot_received),
        .dest_clk(clk_eth),
        .dest_out(snapshot_eth),
        .dest_req(snapshot_eth_v),
        .dest_ack(1'b0)
    );
    always @(posedge clk_eth) begin
        if (!rst_n_eth) begin
            packet_errors <= 0;
            packet_bits   <= 0;
        end else if (snapshot_eth_v) begin
            packet_errors <= snapshot_eth[31:0];
            packet_bits   <= snapshot_eth[63:32];
        end
    end
endmodule
`default_nettype wire
