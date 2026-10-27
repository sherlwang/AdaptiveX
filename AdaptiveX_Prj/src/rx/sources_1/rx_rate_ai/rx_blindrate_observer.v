`timescale 1ns / 1ps
`default_nettype none

// Observation only: join the actual three TRACK windows to their own PN job.
// SEARCH candidates are deliberately not represented as three windows of a frame.
module rx_blindrate_observer #(
    parameter integer ENABLE_DEBUG_DATA = 0,
    parameter integer MAX_WAIT_CLKS = 4095
) (
    input wire clk, rst_n,
    input wire [383:0] ddc_i, ddc_q,
    input wire ddc_v,
    input wire [63:0] ddc_write_idx,
    input wire group_v,
    input wire [31:0] group_id,
    input wire [63:0] group_anchor,
    input wire [3:0] group_p,
    input wire window_v,
    input wire [31:0] window_group,
    input wire [1:0] window_slot,
    input wire [63:0] window_idx,
    input wire result_v,
    input wire [31:0] result_group,
    input wire [1:0] result_slot,
    input wire [63:0] result_idx,
    input wire [3:0] result_p,
    input wire result_accepted,
    input wire confirm_v,
    input wire [31:0] confirm_group,
    input wire [63:0] confirm_anchor,
    input wire [3:0] confirm_p,
    input wire cancel_all,
    output reg summary_v,
    output reg [3:0] window_p0, window_p1, window_p2,
    output reg [2:0] window_valid, window_accepted,
    output reg [3:0] frame_p,
    output reg frame_p_valid,
    output wire [383:0] debug_data_i, debug_data_q,
    output wire debug_data_v, debug_frame_start,
    output wire [2:0] debug_window_active, debug_window_start,
    output wire debug_ready,
    output wire [3:0] debug_p0, debug_p1, debug_p2,
    output wire [2:0] debug_result_valid, debug_accepted,
    output wire [3:0] debug_frame_p,
    output wire debug_frame_p_valid
);
    reg [3:0] live, ready, triple_good, pn_seen;
    reg [31:0] ids[0:3];
    reg [63:0] anchors[0:3], pn_anchors[0:3];
    reg [3:0] source_p[0:3], pn_p[0:3];
    reg [191:0] window_indices[0:3];
    reg [2:0] windows_seen[0:3], results_seen[0:3], accepted[0:3];
    reg [11:0] ps[0:3];
    reg [12:0] age[0:3];
    reg [1:0] wr_slot, rd_slot;
    // Sticky internal integrity observation; it never changes the receiver.
    reg observer_overflow;
    integer j;
    reg [2:0] merged_seen, merged_accepted;
    reg [11:0] merged_ps;

    function [12:0] frame_length;
        input [3:0] p;
        begin frame_length = p == 2 ? 13'd2160 : p == 4 ? 13'd2156 : 13'd2154; end
    endfunction
    function physical_p;
        input [3:0] p;
        begin physical_p = p == 2 || p == 4 || p == 8; end
    endfunction
    function all_windows_in_frame;
        input [191:0] indices;
        input [63:0] anchor;
        input [3:0] p;
        integer n;
        reg good;
        begin
            good = 1;
            for (n = 0; n < 3; n = n + 1)
                if (indices[n*64+:64] < anchor ||
                    indices[n*64+:64] + 64'd48 > anchor + frame_length(p)) good = 0;
            all_windows_in_frame = good;
        end
    endfunction

    wire publish = live[rd_slot] && ready[rd_slot];
    wire published_good = pn_seen[rd_slot] && triple_good[rd_slot] &&
        results_seen[rd_slot] == 3'b111 && windows_seen[rd_slot] == 3'b111 &&
        physical_p(pn_p[rd_slot]) && pn_p[rd_slot] == ps[rd_slot][3:0] &&
        all_windows_in_frame(window_indices[rd_slot], pn_anchors[rd_slot], pn_p[rd_slot]);
    wire [63:0] published_anchor = pn_seen[rd_slot] ? pn_anchors[rd_slot] : anchors[rd_slot];
    wire [3:0] published_p = pn_seen[rd_slot] ? pn_p[rd_slot] : 4'd0;
    wire [3:0] published_length_p = pn_seen[rd_slot] && physical_p(pn_p[rd_slot]) ?
        pn_p[rd_slot] : source_p[rd_slot];

    always @(posedge clk) begin
        if (!rst_n) begin
            live <= 0; ready <= 0; triple_good <= 0; pn_seen <= 0;
            wr_slot <= 0; rd_slot <= 0; observer_overflow <= 0;
            summary_v <= 0; window_p0 <= 0; window_p1 <= 0; window_p2 <= 0;
            window_valid <= 0; window_accepted <= 0; frame_p <= 0; frame_p_valid <= 0;
            for (j = 0; j < 4; j = j + 1) begin
                ids[j] <= 0; anchors[j] <= 0; pn_anchors[j] <= 0;
                source_p[j] <= 2; pn_p[j] <= 0; window_indices[j] <= 0;
                windows_seen[j] <= 0; results_seen[j] <= 0; accepted[j] <= 0;
                ps[j] <= 0; age[j] <= 0;
            end
        end else begin
            summary_v <= 0;
            for (j = 0; j < 4; j = j + 1) begin
                if (live[j] && !ready[j]) begin
                    if (age[j] < MAX_WAIT_CLKS) age[j] <= age[j] + 1'b1;
                    else ready[j] <= 1;
                    if (cancel_all) ready[j] <= 1;
                    if (window_v && window_group == ids[j] && window_slot < 3) begin
                        windows_seen[j][window_slot] <= 1;
                        window_indices[j][window_slot*64+:64] <= window_idx;
                    end
                    if (result_v && result_group == ids[j] && result_slot < 3 &&
                        windows_seen[j][result_slot] &&
                        result_idx == window_indices[j][result_slot*64+:64]) begin
                        merged_seen = results_seen[j] | (3'b001 << result_slot);
                        merged_accepted = accepted[j];
                        merged_accepted[result_slot] = result_accepted;
                        merged_ps = ps[j];
                        merged_ps[result_slot*4+:4] = result_p;
                        results_seen[j] <= merged_seen;
                        accepted[j] <= merged_accepted;
                        ps[j] <= merged_ps;
                        if (merged_seen == 3'b111) begin
                            if (merged_accepted == 3'b111 && physical_p(merged_ps[3:0]) &&
                                merged_ps[3:0] == merged_ps[7:4] && merged_ps[7:4] == merged_ps[11:8]) begin
                                triple_good[j] <= 1;
                                if (pn_seen[j]) ready[j] <= 1;
                            end else ready[j] <= 1;
                        end
                    end
                    if (confirm_v && confirm_group == ids[j]) begin
                        pn_seen[j] <= 1;
                        pn_anchors[j] <= confirm_anchor;
                        pn_p[j] <= confirm_p;
                        if (results_seen[j] == 3'b111) ready[j] <= 1;
                    end
                end
            end
            if (group_v) begin
                if (!live[wr_slot]) begin
                    live[wr_slot] <= 1; ready[wr_slot] <= 0;
                    triple_good[wr_slot] <= 0; pn_seen[wr_slot] <= 0;
                    ids[wr_slot] <= group_id; anchors[wr_slot] <= group_anchor;
                    source_p[wr_slot] <= group_p; pn_anchors[wr_slot] <= 0; pn_p[wr_slot] <= 0;
                    window_indices[wr_slot] <= 0; windows_seen[wr_slot] <= 0;
                    results_seen[wr_slot] <= 0; accepted[wr_slot] <= 0; ps[wr_slot] <= 0;
                    age[wr_slot] <= 0; wr_slot <= wr_slot + 1'b1;
                end else observer_overflow <= 1;
            end
            if (publish) begin
                summary_v <= 1;
                window_p0 <= ps[rd_slot][3:0];
                window_p1 <= ps[rd_slot][7:4];
                window_p2 <= ps[rd_slot][11:8];
                window_valid <= results_seen[rd_slot];
                window_accepted <= accepted[rd_slot];
                frame_p <= published_p;
                frame_p_valid <= published_good;
                live[rd_slot] <= 0; ready[rd_slot] <= 0;
                rd_slot <= rd_slot + 1'b1;
            end
        end
    end

    generate
        if (ENABLE_DEBUG_DATA != 0) begin : full_source_capture
            rx_blindrate_ddc_replay u_replay (
                .clk(clk), .rst_n(rst_n), .ddc_i(ddc_i), .ddc_q(ddc_q),
                .ddc_v(ddc_v), .ddc_write_idx(ddc_write_idx), .packet_v(publish),
                .packet_anchor(published_anchor), .packet_length(frame_length(published_length_p)),
                .packet_window_indices(window_indices[rd_slot]), .packet_windows_seen(windows_seen[rd_slot]),
                .packet_ps(ps[rd_slot]), .packet_result_valid(results_seen[rd_slot]),
                .packet_accepted(accepted[rd_slot]), .packet_frame_p(published_p),
                .packet_frame_p_valid(published_good),
                .data_i(debug_data_i), .data_q(debug_data_q), .data_v(debug_data_v),
                .frame_start(debug_frame_start), .window_active(debug_window_active),
                .window_start(debug_window_start), .packet_ready(debug_ready),
                .p0(debug_p0), .p1(debug_p1), .p2(debug_p2),
                .result_valid(debug_result_valid), .accepted(debug_accepted),
                .frame_p(debug_frame_p), .frame_p_valid(debug_frame_p_valid)
            );
        end else begin : no_source_capture
            assign debug_data_i=0; assign debug_data_q=0; assign debug_data_v=0;
            assign debug_frame_start=0; assign debug_window_active=0; assign debug_window_start=0;
            assign debug_ready=0; assign debug_p0=0; assign debug_p1=0; assign debug_p2=0;
            assign debug_result_valid=0; assign debug_accepted=0;
            assign debug_frame_p=0; assign debug_frame_p_valid=0;
        end
    endgenerate
endmodule

// Single-shot packets from a continuously indexed, *unrotated* DDC history.
// While replaying, newer packets may be skipped; source processing never waits.
module rx_blindrate_ddc_replay (
    input wire clk, rst_n,
    input wire [383:0] ddc_i, ddc_q,
    input wire ddc_v,
    input wire [63:0] ddc_write_idx,
    input wire packet_v,
    input wire [63:0] packet_anchor,
    input wire [12:0] packet_length,
    input wire [191:0] packet_window_indices,
    input wire [2:0] packet_windows_seen,
    input wire [11:0] packet_ps,
    input wire [2:0] packet_result_valid, packet_accepted,
    input wire [3:0] packet_frame_p,
    input wire packet_frame_p_valid,
    output wire [383:0] data_i, data_q,
    output reg data_v, frame_start,
    output reg [2:0] window_active, window_start,
    output reg packet_ready,
    output reg [3:0] p0, p1, p2,
    output reg [2:0] result_valid, accepted,
    output reg [3:0] frame_p,
    output reg frame_p_valid
);
    (* ram_style="block" *) reg [767:0] source_ram[0:8191];
    reg [767:0] read_data;
    reg busy;
    reg [63:0] read_idx;
    reg [12:0] read_left, length_latched;
    reg [191:0] windows_latched;
    reg [2:0] windows_seen_latched;
    reg skipped_packet;
    integer n;
    wire packet_available = packet_length != 0 && packet_length <= 2160 &&
        ddc_write_idx >= packet_anchor + packet_length &&
        // Leave two words for packet acceptance -> first RAM read. Never
        // depend on vendor read-during-write behaviour at the wrap boundary.
        ddc_write_idx >= packet_anchor && ddc_write_idx - packet_anchor <= 8190;
    assign data_i = read_data[383:0];
    assign data_q = read_data[767:384];

    always @(posedge clk) begin
        if (rst_n && ddc_v) source_ram[ddc_write_idx[12:0]] <= {ddc_q,ddc_i};
        if (!rst_n) begin
            read_data <= 0; busy <= 0; read_idx <= 0; read_left <= 0; length_latched <= 0;
            windows_latched <= 0; windows_seen_latched <= 0;
            data_v <= 0; frame_start <= 0; window_active <= 0; window_start <= 0;
            packet_ready <= 0; p0 <= 0; p1 <= 0; p2 <= 0;
            result_valid <= 0; accepted <= 0; frame_p <= 0; frame_p_valid <= 0; skipped_packet <= 0;
        end else begin
            data_v <= 0; frame_start <= 0; window_active <= 0; window_start <= 0; packet_ready <= 0;
            if (packet_v) begin
                if (!busy && packet_available) begin
                    busy <= 1; read_idx <= packet_anchor; read_left <= packet_length;
                    length_latched <= packet_length; windows_latched <= packet_window_indices;
                    windows_seen_latched <= packet_windows_seen;
                    p0 <= packet_ps[3:0]; p1 <= packet_ps[7:4]; p2 <= packet_ps[11:8];
                    result_valid <= packet_result_valid; accepted <= packet_accepted;
                    frame_p <= packet_frame_p; frame_p_valid <= packet_frame_p_valid;
                    packet_ready <= 1;
                end else skipped_packet <= 1;
            end
            if (busy) begin
                // The writer advances by at most one source word per clock;
                // the replay reader advances every clock, so its age cannot grow.
                read_data <= source_ram[read_idx[12:0]];
                data_v <= 1; frame_start <= read_left == length_latched;
                for (n = 0; n < 3; n = n + 1) begin
                    window_start[n] <= windows_seen_latched[n] && read_idx == windows_latched[n*64+:64];
                    window_active[n] <= windows_seen_latched[n] && read_idx >= windows_latched[n*64+:64] &&
                        read_idx < windows_latched[n*64+:64] + 64'd48;
                end
                read_idx <= read_idx + 1'b1;
                read_left <= read_left - 1'b1;
                if (read_left == 1) busy <= 0;
            end
        end
    end
endmodule
`default_nettype wire
