`timescale 1ns / 1ps
`default_nettype none

// Atomic word: {reserved[1:0], frame_id[31:0], P[3:0], M[1:0], Q[31:0], I[31:0]}.
// Standard-read XPM BRAM FIFO: rd_ready issues read requests; rd_valid marks
// the resulting registered data one clock later (not an AXI elastic output).
module Constellation_Metadata_FIFO #(
    parameter ASYNC = 0,
    parameter DEPTH = 64
)(
    input wire wr_clk,
    input wire rd_clk,
    input wire rst,
    input wire [103:0] wr_data,
    input wire wr_valid,
    output wire wr_ready,
    output wire [103:0] rd_data,
    output wire rd_valid,
    input wire rd_ready
);
    localparam COUNT_WIDTH = $clog2(DEPTH) + 1;
    reg [2:0] reset_pipe = 3'b111;
    always @(posedge wr_clk or posedge rst) begin
        if (rst) reset_pipe <= 3'b111;
        else reset_pipe <= {reset_pipe[1:0], 1'b0};
    end
    reg [2:0] read_reset_pipe = 3'b111;
    always @(posedge rd_clk or posedge rst) begin
        if (rst) read_reset_pipe <= 3'b111;
        else read_reset_pipe <= {read_reset_pipe[1:0], 1'b0};
    end
    wire fifo_reset = reset_pipe[2];
    wire full, empty, wr_busy, rd_busy, data_valid;
    wire write_enable = wr_valid && wr_ready;
    wire read_enable = rd_ready && !empty && !rd_busy && !read_reset_pipe[2];
    assign wr_ready = !full && !wr_busy && !fifo_reset;
    assign rd_valid = data_valid && !rd_busy && !read_reset_pipe[2];

    // Keep the optional 2021.2 XPM SVA off: its EMPTY_CHECK requires a rising
    // empty flag even when already empty; its zero-cycle sleep check also fires
    // with sleep tied low. Real vendor FIFO logic and parameter checks remain.

    generate
        if (ASYNC != 0) begin : g_async
            xpm_fifo_async #(
                .CDC_SYNC_STAGES(3), .DOUT_RESET_VALUE("0"),
                .ECC_MODE("no_ecc"), .FIFO_MEMORY_TYPE("block"),
                .FIFO_READ_LATENCY(1), .FIFO_WRITE_DEPTH(DEPTH),
                .FULL_RESET_VALUE(0), .PROG_EMPTY_THRESH(10),
                .PROG_FULL_THRESH(DEPTH-10), .RD_DATA_COUNT_WIDTH(COUNT_WIDTH),
                .READ_DATA_WIDTH(104), .READ_MODE("std"), .RELATED_CLOCKS(0),
                .SIM_ASSERT_CHK(0), .USE_ADV_FEATURES("1000"),
                .WAKEUP_TIME(0), .WRITE_DATA_WIDTH(104),
                .WR_DATA_COUNT_WIDTH(COUNT_WIDTH)
            ) u_fifo (
                .rst(fifo_reset), .wr_clk(wr_clk), .rd_clk(rd_clk),
                .din(wr_data), .wr_en(write_enable), .rd_en(read_enable),
                .dout(rd_data), .data_valid(data_valid),
                .full(full), .empty(empty), .wr_rst_busy(wr_busy), .rd_rst_busy(rd_busy),
                .sleep(1'b0), .injectdbiterr(1'b0), .injectsbiterr(1'b0),
                .almost_empty(), .almost_full(), .dbiterr(), .sbiterr(),
                .overflow(), .underflow(), .prog_empty(), .prog_full(),
                .rd_data_count(), .wr_data_count(), .wr_ack()
            );
        end else begin : g_sync
            xpm_fifo_sync #(
                .DOUT_RESET_VALUE("0"), .ECC_MODE("no_ecc"),
                .FIFO_MEMORY_TYPE("block"), .FIFO_READ_LATENCY(1),
                .FIFO_WRITE_DEPTH(DEPTH), .FULL_RESET_VALUE(0),
                .PROG_EMPTY_THRESH(10), .PROG_FULL_THRESH(DEPTH-10),
                .RD_DATA_COUNT_WIDTH(COUNT_WIDTH), .READ_DATA_WIDTH(104),
                .READ_MODE("std"), .SIM_ASSERT_CHK(0), .USE_ADV_FEATURES("1000"),
                .WAKEUP_TIME(0), .WRITE_DATA_WIDTH(104),
                .WR_DATA_COUNT_WIDTH(COUNT_WIDTH)
            ) u_fifo (
                .rst(fifo_reset), .wr_clk(wr_clk),
                .din(wr_data), .wr_en(write_enable), .rd_en(read_enable),
                .dout(rd_data), .data_valid(data_valid),
                .full(full), .empty(empty), .wr_rst_busy(wr_busy), .rd_rst_busy(rd_busy),
                .sleep(1'b0), .injectdbiterr(1'b0), .injectsbiterr(1'b0),
                .almost_empty(), .almost_full(), .dbiterr(), .sbiterr(),
                .overflow(), .underflow(), .prog_empty(), .prog_full(),
                .rd_data_count(), .wr_data_count(), .wr_ack()
            );
        end
    endgenerate
endmodule
`default_nettype wire
