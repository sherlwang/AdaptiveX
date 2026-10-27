`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Module Name: phy_64toW
// Description: Two six-block frame banks, with independent write/read modes.
// A bank starts at a constant offset from its request-frame virtual header.
// This removes the mode-dependent 18*W collection-time offset. All W retain
// 192 valid clocks per block, and 265 clocks between block starts.
// Revision: 2026/10/14 - Tx_No_Reset, Verilog-2001 / Vivado 2021.2.
//////////////////////////////////////////////////////////////////////////////////
module phy_64toW #(
    parameter integer FRAME_RELEASE_CLOCKS = 2048
) (
    input wire clk,
    input wire rst_n,
    input wire [3:0] phy_ploy,
    input wire [1:0] phy_mod,
    input wire [63:0] din,
    input wire din_v,
    output wire [31:0] dout,
    output wire dout_v,
    output wire [3:0] dout_ploy,
    output wire [1:0] dout_mod
);
    localparam IDLE  = 3'd0;
    localparam LOAD  = 3'd1;
    localparam PRIME = 3'd2;
    localparam DATA  = 3'd3;
    localparam GAP   = 3'd4;
    (* ram_style="block" *) reg [63:0] mem[0:1151];
    reg [63:0] ram_q;
    reg [63:0] word_buffer;
    reg wr_bank;
    reg rd_bank;
    reg [1:0] complete;
    reg [1:0] age_active;
    reg [5:0] bank_mode[0:1];
    reg [11:0] bank_age[0:1];
    reg [9:0] wr_count;
    reg [9:0] word_index;
    reg [2:0] state;
    reg [2:0] block_index;
    reg [8:0] slot_timer;
    reg [7:0] data_index;
    reg [4:0] slice_index;
    reg [5:0] read_mode;
    reg overflow_error;
    reg deadline_error;
    reg mode_error;
    wire [5:0] write_mode;
    wire [5:0] write_width;
    wire [5:0] read_width;
    wire [9:0] write_words;
    wire [9:0] read_words;
    wire [4:0] last_slice;
    wire [31:0] mask;
    wire read_enable;
    wire [10:0] write_address;
    wire [10:0] read_address;
    wire [11:0] release_age;
    integer b;

    assign write_mode = wr_count == 0 ? {phy_ploy, phy_mod} : bank_mode[wr_bank];
    assign write_width = {2'd0, write_mode[5:2]} << write_mode[1:0];
    assign read_width = {2'd0, read_mode[5:2]} << read_mode[1:0];
    assign write_words = (write_width << 4) + (write_width << 1);
    assign read_words = (read_width << 4) + (read_width << 1);
    assign last_slice = read_width == 2 ? 31 :
        read_width == 4 ? 15 : read_width == 8 ? 7 : read_width == 16 ? 3 : 1;
    assign mask = 32'hffffffff >> (32 - read_width);
    assign dout = word_buffer[31:0] & mask;
    assign dout_v = rst_n && state == DATA;
    assign dout_ploy = read_mode[5:2];
    assign dout_mod = read_mode[1:0];
    assign write_address = (wr_bank ? 11'd576 : 11'd0) + wr_count;
    assign read_address = (rd_bank ? 11'd576 : 11'd0) + (state == LOAD ? 11'd0 : {1'b0, word_index} + 11'd1);
    assign read_enable = rst_n &&
        (state == LOAD || (state == DATA && slice_index == 0 && word_index < read_words - 1));
    // First MAC word is header_length + the constant MAC pipeline after the
    // virtual frame start. Subtract header_length to obtain a common release.
    assign release_age = FRAME_RELEASE_CLOCKS -
        (bank_mode[rd_bank][5:2] == 2 ? 570 : bank_mode[rd_bank][5:2] == 4 ? 566 : 564);

    always @(posedge clk) begin
        if (rst_n && din_v) mem[write_address] <= din;
        if (read_enable) ram_q <= mem[read_address];
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_bank <= 1'b0;
            rd_bank <= 1'b0;
            complete <= 2'b00;
            age_active <= 2'b00;
            wr_count <= 10'd0;
            word_index <= 10'd0;
            state <= IDLE;
            block_index <= 3'd0;
            slot_timer <= 9'd0;
            data_index <= 8'd0;
            slice_index <= 5'd0;
            word_buffer <= 64'd0;
            read_mode <= {4'd2, 2'd0};
            overflow_error <= 1'b0;
            deadline_error <= 1'b0;
            mode_error <= 1'b0;
            for (b = 0; b < 2; b = b + 1) begin
                bank_mode[b] <= {4'd2, 2'd0};
                bank_age[b]  <= 12'd0;
            end
        end else begin
            for (b = 0; b < 2; b = b + 1) begin
                if (age_active[b] && bank_age[b] != 12'hfff) bank_age[b] <= bank_age[b] + 1'b1;
            end
            if (din_v) begin
                if (wr_count == 0) begin
                    bank_mode[wr_bank]  <= {phy_ploy, phy_mod};
                    bank_age[wr_bank]   <= 12'd0;
                    age_active[wr_bank] <= 1'b1;
                    if (complete[wr_bank] || (state != IDLE && wr_bank == rd_bank)) overflow_error <= 1'b1;
                end else if ({phy_ploy, phy_mod} != bank_mode[wr_bank]) mode_error <= 1'b1;
                if ((phy_ploy != 2 && phy_ploy != 4 && phy_ploy != 8) || phy_mod > 2) mode_error <= 1'b1;
                if (wr_count == write_words - 1) begin
                    complete[wr_bank] <= 1'b1;
                    wr_bank <= ~wr_bank;
                    wr_count <= 10'd0;
                end else wr_count <= wr_count + 1'b1;
            end
            if (age_active[rd_bank] && bank_age[rd_bank] == release_age && !complete[rd_bank])
                deadline_error <= 1'b1;
            case (state)
                IDLE:
                if (complete[rd_bank] && bank_age[rd_bank] >= release_age) begin
                    read_mode <= bank_mode[rd_bank];
                    age_active[rd_bank] <= 1'b0;
                    word_index <= 10'd0;
                    block_index <= 3'd0;
                    data_index <= 8'd0;
                    slice_index <= 5'd0;
                    slot_timer <= 9'd0;
                    state <= LOAD;
                end
                LOAD: state <= PRIME;
                PRIME: begin
                    word_buffer <= ram_q;
                    state <= DATA;
                end
                DATA: begin
                    slot_timer <= slot_timer + 1'b1;
                    if (slice_index == last_slice) begin
                        slice_index <= 5'd0;
                        word_index  <= word_index + 1'b1;
                        word_buffer <= ram_q;
                    end else begin
                        slice_index <= slice_index + 1'b1;
                        word_buffer <= word_buffer >> read_width;
                    end
                    if (data_index == 8'd191) begin
                        data_index <= 8'd0;
                        if (block_index == 3'd5) begin
                            complete[rd_bank] <= 1'b0;
                            rd_bank <= ~rd_bank;
                            state <= IDLE;
                        end else begin
                            block_index <= block_index + 1'b1;
                            state <= GAP;
                        end
                    end else data_index <= data_index + 1'b1;
                end
                GAP: begin
                    if (slot_timer == 9'd264) begin
                        slot_timer <= 9'd0;
                        state <= DATA;
                    end else slot_timer <= slot_timer + 1'b1;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
