`timescale 1ns / 1ps
`default_nettype none

// Whole-controller-message CDC. The data bank is not reset; only pointers are.
// rd_data is FWFT: sample it on rd_clk when rd_en && !rd_empty.
module rx_fb_event_fifo #(
    parameter integer ADDR_WIDTH = 5
)(
    input  wire                  wr_clk,
    input  wire                  rd_clk,
    input  wire                  arst_n,
    input  wire                  wr_v,
    input  wire [15:0]           wr_data,
    output wire                  wr_full,
    output reg                   overflow,
    input  wire                  rd_en,
    output wire [15:0]           rd_data,
    output wire                  rd_empty,
    output wire [ADDR_WIDTH:0]   rd_level
);
    localparam integer PTR_WIDTH = ADDR_WIDTH + 1;
    localparam integer DEPTH = 1 << ADDR_WIDTH;
    (* ram_style = "distributed" *) reg [15:0] messages [0:DEPTH-1];
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [2:0] wr_release, rd_release;
    wire wr_run_n = wr_release[2];
    wire rd_run_n = rd_release[2];
    reg [PTR_WIDTH-1:0] wr_binary, wr_gray;
    reg [PTR_WIDTH-1:0] rd_binary, rd_gray;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [PTR_WIDTH-1:0] rd_gray_w1, rd_gray_w2;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [PTR_WIDTH-1:0] wr_gray_r1, wr_gray_r2;
    reg full_q, empty_q;
    wire write_take = wr_v && !wr_full;
    wire read_take = rd_en && !rd_empty;
    wire [PTR_WIDTH-1:0] wr_binary_next = wr_binary + write_take;
    wire [PTR_WIDTH-1:0] rd_binary_next = rd_binary + read_take;
    wire [PTR_WIDTH-1:0] wr_gray_next = (wr_binary_next >> 1) ^ wr_binary_next;
    wire [PTR_WIDTH-1:0] rd_gray_next = (rd_binary_next >> 1) ^ rd_binary_next;
    wire full_next = wr_gray_next == {~rd_gray_w2[PTR_WIDTH-1:PTR_WIDTH-2],
                                      rd_gray_w2[PTR_WIDTH-3:0]};
    wire empty_next = rd_gray_next == wr_gray_r2;

    function [PTR_WIDTH-1:0] gray_to_binary;
        input [PTR_WIDTH-1:0] gray_value;
        integer bit_index;
        begin
            gray_to_binary[PTR_WIDTH-1] = gray_value[PTR_WIDTH-1];
            for(bit_index = PTR_WIDTH-2; bit_index >= 0; bit_index = bit_index-1)
                gray_to_binary[bit_index] = gray_to_binary[bit_index+1] ^ gray_value[bit_index];
        end
    endfunction

    assign wr_full = !wr_run_n || full_q;
    assign rd_empty = !rd_run_n || empty_q;
    assign rd_data = rd_empty ? 16'd0 : messages[rd_binary[ADDR_WIDTH-1:0]];
    // A conservative read-domain occupancy; newly written words take two CDC
    // synchronizer stages to become visible. Never use this on the write side.
    assign rd_level = !rd_run_n ? {PTR_WIDTH{1'b0}} :
                      gray_to_binary(wr_gray_r2) - rd_binary;

    initial begin
        if(ADDR_WIDTH < 2) begin
            $error("rx_fb_event_fifo: ADDR_WIDTH must be at least 2");
            $finish;
        end
    end

    // Common asynchronous assertion, independent local synchronous release.
    always @(posedge wr_clk or negedge arst_n) begin
        if(!arst_n) wr_release <= 0;
        else wr_release <= {wr_release[1:0], 1'b1};
    end
    always @(posedge rd_clk or negedge arst_n) begin
        if(!arst_n) rd_release <= 0;
        else rd_release <= {rd_release[1:0], 1'b1};
    end
    // Only the release chains consume raw arst_n. Every functional and CDC
    // register deasserts reset on its own local clock. Source pointers remain
    // zero until that local release, with no mux before either CDC first stage.
    always @(posedge wr_clk or negedge wr_run_n) begin
        if(!wr_run_n) begin rd_gray_w1 <= 0; rd_gray_w2 <= 0; end
        else begin rd_gray_w1 <= rd_gray; rd_gray_w2 <= rd_gray_w1; end
    end
    always @(posedge rd_clk or negedge rd_run_n) begin
        if(!rd_run_n) begin wr_gray_r1 <= 0; wr_gray_r2 <= 0; end
        else begin wr_gray_r1 <= wr_gray; wr_gray_r2 <= wr_gray_r1; end
    end

    always @(posedge wr_clk) begin
        if(write_take) messages[wr_binary[ADDR_WIDTH-1:0]] <= wr_data;
    end
    always @(posedge wr_clk or negedge wr_run_n) begin
        if(!wr_run_n) begin
            wr_binary <= 0; wr_gray <= 0; full_q <= 0; overflow <= 0;
        end else begin
            wr_binary <= wr_binary_next;
            wr_gray <= wr_gray_next;
            full_q <= full_next;
            // The controller is never backpressured. A full queue drops the
            // arriving complete message and raises this sticky observation.
            if(wr_v && full_q) overflow <= 1'b1;
        end
    end
    always @(posedge rd_clk or negedge rd_run_n) begin
        if(!rd_run_n) begin rd_binary <= 0; rd_gray <= 0; empty_q <= 1; end
        else begin
            rd_binary <= rd_binary_next;
            rd_gray <= rd_gray_next;
            empty_q <= empty_next;
        end
    end
endmodule

`default_nettype wire
