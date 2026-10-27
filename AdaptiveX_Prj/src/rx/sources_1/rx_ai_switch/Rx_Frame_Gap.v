`timescale 1ns / 1ps
`default_nettype none
// Missing continuous-frame opportunities from accepted source-clock anchors.
module Rx_Frame_Gap #(
    parameter integer MIN_INTERVAL   = 2154,
    parameter integer MAX_INTERVAL   = 2173,
    parameter integer TOLERANCE      = 160,
    parameter integer AGE_GUARD_BITS = 24
) (
    input wire clk,
    input wire rst_n,
    input wire commit,
    input wire [23:0] frame_idx,
    output wire [15:0] missed_before,
    output reg fault
);
    reg previous_valid;
    reg [23:0] previous_idx;
    reg [AGE_GUARD_BITS-1:0] age;
    wire [23:0] distance = frame_idx - previous_idx;
    wire [16:0] interval_match;
    wire long_gap = age[AGE_GUARD_BITS-1] || distance > 17 * MAX_INTERVAL + TOLERANCE;
    wire interval_valid = (|interval_match) || long_gap;
    reg [15:0] matched_missing;
    integer idx;
    genvar k;
    generate
        for (k = 1; k <= 17; k = k + 1) begin : intervals
            assign interval_match[k-1] = distance >= k * MIN_INTERVAL - TOLERANCE &&
                distance <= k * MAX_INTERVAL + TOLERANCE;
        end
    endgenerate
    // The 17 acceptance intervals are disjoint for the configured frame lengths.
    always @* begin
        matched_missing = 0;
        for (idx = 0; idx < 17; idx = idx + 1)
        if (interval_match[idx]) matched_missing = matched_missing | idx;
    end
    assign missed_before = !previous_valid ? 16'd0 : long_gap ? 16'd16 : matched_missing;
    always @(posedge clk) begin
        if (!rst_n) begin
            previous_valid <= 0;
            previous_idx <= 0;
            age <= 0;
            fault <= 0;
        end else if (commit) begin
            if (previous_valid && !interval_valid) fault <= 1;
            previous_valid <= 1;
            previous_idx <= frame_idx;
            age <= 0;
        end else if (previous_valid && !age[AGE_GUARD_BITS-1]) age <= age + 1'b1;
    end
endmodule
`default_nettype wire
