`timescale 1ns / 1ps
`default_nettype none

// Retain the original one-in-two sampling and rotating two-symbol lane choice.
// Every queued IQ word carries the metadata of that exact input clock.
module Constellation_Choose #(
    parameter PLOY = 8,
    parameter PLOY_WIDTH = 16
)(
    input wire clk,
    input wire rst_n,
    input wire [3:0] phy_ploy,
    input wire [1:0] cone_modulation,
    input wire [31:0] cone_frame_id,
    input wire [PLOY_WIDTH*PLOY-1:0] Din_i,
    input wire [PLOY_WIDTH*PLOY-1:0] Din_q,
    input wire Din_v,
    output wire [PLOY_WIDTH*2-1:0] Constellation_LEN_i,
    output wire [PLOY_WIDTH*2-1:0] Constellation_LEN_q,
    output wire Constellation_LEN_v,
    output wire [3:0] Constellation_LEN_ploy,
    output wire [1:0] Constellation_LEN_modulation,
    output wire [31:0] Constellation_LEN_frame_id
);
    reg sample_phase;
    reg [3:0] pair_count;
    reg [103:0] selected_word;
    reg selected_valid;
    wire [1:0] pair_index = (phy_ploy == 2) ? 2'd0 :
                            (phy_ploy == 4) ? {1'b0, pair_count[0]} : pair_count[1:0];
    wire [31:0] selected_i = Din_i[pair_index*32 +: 32];
    wire [31:0] selected_q = Din_q[pair_index*32 +: 32];
    wire [103:0] fifo_word;
    wire fifo_ready;

    always @(posedge clk) begin
        if (!rst_n) begin
            sample_phase <= 0;
            pair_count <= 0;
            selected_word <= 0;
            selected_valid <= 0;
        end else begin
            if (Din_v) sample_phase <= !sample_phase;
            selected_valid <= Din_v && sample_phase;
            if (Din_v && sample_phase) begin
                pair_count <= (pair_count == 11) ? 0 : pair_count + 1'b1;
                selected_word <= {2'b0, cone_frame_id, phy_ploy,
                                  cone_modulation, selected_q, selected_i};
            end
        end
    end

    // A display sample may be dropped when full, but its metadata can never
    // detach from it. This monitor does not backpressure the receive PHY.
    Constellation_Metadata_FIFO #(.ASYNC(0), .DEPTH(64)) u_sample_fifo (
        .wr_clk(clk), .rd_clk(clk), .rst(!rst_n),
        .wr_data(selected_word), .wr_valid(selected_valid), .wr_ready(fifo_ready),
        .rd_data(fifo_word), .rd_valid(Constellation_LEN_v), .rd_ready(1'b1)
    );
    assign Constellation_LEN_i = fifo_word[31:0];
    assign Constellation_LEN_q = fifo_word[63:32];
    assign Constellation_LEN_modulation = fifo_word[65:64];
    assign Constellation_LEN_ploy = fifo_word[69:66];
    assign Constellation_LEN_frame_id = fifo_word[101:70];
endmodule
`default_nettype wire
