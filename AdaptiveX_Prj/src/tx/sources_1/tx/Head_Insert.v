`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Module Name: Head_Insert
// Description: Per-frame header and old-P valid-zero guard before a new P.
// Mode descriptors arrive with the first coded word, ahead of CP data. This
// lookahead allows guard output at the old frame's EOF while the front end
// reserves the SAME interval, without inserting a second idle interval.
// Data input/output mode contexts are independent. Six CP blocks = 1590 words.
// Revision: 2026/10/14 - Tx_No_Reset / Vivado 2021.2 / Verilog-2001.
//////////////////////////////////////////////////////////////////////////////////
module Head_Insert #(
    parameter HEAD_FILE = "head_all.mem"
) (
    input wire clk,
    input wire rst_n,
    input wire [3:0] phy_ploy,
    input wire [1:0] phy_mod,
    input wire [3:0] frame_ploy,
    input wire [1:0] frame_mod,
    input wire frame_mode_v,
    input wire [127:0] din_i,
    input wire [127:0] din_q,
    input wire din_v,
    output wire [127:0] dout_i,
    output wire [127:0] dout_q,
    output reg dout_v,
    output reg [3:0] dout_ploy,
    output reg [1:0] dout_mod,
    output reg dout_guard
);
    localparam [ 3:0] IDLE        = 4'b0001;
    localparam [ 3:0] ZERO        = 4'b0010;
    localparam [ 3:0] HEAD        = 4'b0100;
    localparam [ 3:0] DATA        = 4'b1000;
    localparam [10:0] DATA_CLOCKS = 11'd1590;
    localparam [10:0] DATA_DEPTH  = 11'd1024;
    (* rom_style="block" *) reg [255:0] head_rom[0:2047];
    (* ram_style="block" *) reg [255:0] data_mem[0:1023];
    reg [5:0] mode_mem[0:3];
    reg [255:0] head_q;
    reg [255:0] data_q;
    reg [3:0] state;
    reg [9:0] cnt_head;
    reg [9:0] wr_addr;
    reg [9:0] rd_addr;
    reg [10:0] cnt_data;
    reg [10:0] used_words;
    reg [10:0] wr_frame_count;
    reg [4:0] cnt_zero;
    reg [4:0] guard_clocks;
    reg [2:0] mode_wr;
    reg [2:0] mode_rd;
    reg [3:0] active_ploy;
    reg [3:0] previous_ploy;
    reg [1:0] active_mod;
    reg [1:0] previous_mod;
    reg [5:0] input_mode;
    reg previous_valid;
    reg select_head;
    reg select_zero;
    reg overflow_error;
    reg underflow_error;
    reg mode_error;
    wire [9:0] head_length;
    wire [10:0] head_base;
    wire [10:0] head_addr;
    wire [127:0] lane_mask;
    wire [5:0] next_mode;
    wire [3:0] ending_ploy;
    wire mode_ok;
    wire write_enable;
    wire read_enable;
    wire head_enable;
    wire zero_enable;
    wire mode_empty;
    wire mode_full;
    wire start_next;
    wire need_guard;

    assign mode_ok = (phy_ploy == 2 || phy_ploy == 4 || phy_ploy == 8) && phy_mod <= 2;
    assign head_length = active_ploy == 2 ? 570 : active_ploy == 4 ? 566 : 564;
    assign head_base = active_ploy == 2 ? 0 : active_ploy == 4 ? 570 : 1136;
    assign head_addr = head_base + {1'b0, cnt_head};
    assign lane_mask = phy_ploy == 2 ? {96'd0, 32'hffffffff} :
        phy_ploy == 4 ? {64'd0, 64'hffffffffffffffff} : {128{1'b1}};
    assign read_enable = rst_n && state == DATA && used_words != 0;
    assign write_enable = rst_n && din_v && mode_ok && (used_words != DATA_DEPTH || read_enable);
    assign head_enable = rst_n && state == HEAD;
    assign zero_enable = rst_n && state == ZERO;
    assign mode_empty = mode_wr == mode_rd;
    assign mode_full = mode_wr == {~mode_rd[2], mode_rd[1:0]};
    assign next_mode = mode_mem[mode_rd[1:0]];
    assign ending_ploy = state == DATA ? active_ploy : previous_ploy;
    assign start_next = rst_n && !mode_empty &&
        ((state == IDLE && used_words != 0) || (state == DATA && read_enable && cnt_data == DATA_CLOCKS - 1));
    assign need_guard = (state == DATA || previous_valid) && next_mode[5:2] != ending_ploy;

    initial $readmemh(HEAD_FILE, head_rom);
    always @(posedge clk) begin
        if (head_enable) head_q <= head_rom[head_addr];
        if (write_enable) data_mem[wr_addr] <= {din_q & lane_mask, din_i & lane_mask};
        if (read_enable) data_q <= data_mem[rd_addr];
        if (rst_n && frame_mode_v && !mode_full) mode_mem[mode_wr[1:0]] <= {frame_ploy, frame_mod};
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            active_ploy <= 4'd2;
            active_mod <= 2'd0;
            previous_ploy <= 4'd2;
            previous_mod <= 2'd0;
            previous_valid <= 1'b0;
            guard_clocks <= 5'd0;
            mode_wr <= 3'd0;
            mode_rd <= 3'd0;
        end else begin
            if (frame_mode_v && !mode_full) mode_wr <= mode_wr + 1'b1;
            if (start_next) begin
                active_ploy <= next_mode[5:2];
                active_mod <= next_mode[1:0];
                mode_rd <= mode_rd + 1'b1;
                guard_clocks <= ending_ploy == 2 ? 13 : ending_ploy == 4 ? 9 : 7;
                state <= need_guard ? ZERO : HEAD;
            end else begin
                case (state)
                    ZERO: if (cnt_zero == guard_clocks - 1) state <= HEAD;
                    HEAD: if (cnt_head == head_length - 1) state <= DATA;
                    DATA: if (read_enable && cnt_data == DATA_CLOCKS - 1) state <= IDLE;
                    default: state <= IDLE;
                endcase
            end
            if (state == DATA && read_enable && cnt_data == DATA_CLOCKS - 1) begin
                previous_ploy  <= active_ploy;
                previous_mod   <= active_mod;
                previous_valid <= 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            cnt_head <= 10'd0;
            cnt_data <= 11'd0;
            cnt_zero <= 5'd0;
            wr_addr <= 10'd0;
            rd_addr <= 10'd0;
            used_words <= 11'd0;
            wr_frame_count <= 11'd0;
            input_mode <= {4'd2, 2'd0};
        end else begin
            cnt_head <= state == HEAD && cnt_head != head_length - 1 ? cnt_head + 1'b1 : 10'd0;
            if (state != DATA || (read_enable && cnt_data == DATA_CLOCKS - 1)) cnt_data <= 11'd0;
            else if (read_enable) cnt_data <= cnt_data + 1'b1;
            cnt_zero <= state == ZERO && cnt_zero != guard_clocks - 1 ? cnt_zero + 1'b1 : 5'd0;
            if (write_enable) begin
                wr_addr <= wr_addr + 1'b1;
                wr_frame_count <= wr_frame_count == DATA_CLOCKS - 1 ? 0 : wr_frame_count + 1'b1;
                if (wr_frame_count == 0) input_mode <= {phy_ploy, phy_mod};
            end
            if (read_enable) rd_addr <= rd_addr + 1'b1;
            case ({
                write_enable, read_enable
            })
                2'b10:   used_words <= used_words + 1'b1;
                2'b01:   used_words <= used_words - 1'b1;
                default: used_words <= used_words;
            endcase
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            select_head <= 1'b0;
            select_zero <= 1'b0;
            dout_v <= 1'b0;
            dout_guard <= 1'b0;
            dout_ploy <= 4'd2;
            dout_mod <= 2'd0;
            overflow_error <= 1'b0;
            underflow_error <= 1'b0;
            mode_error <= 1'b0;
        end else begin
            select_head <= head_enable;
            select_zero <= zero_enable;
            dout_v <= head_enable || zero_enable || read_enable;
            dout_guard <= zero_enable;
            if (head_enable || zero_enable || read_enable) begin
                dout_ploy <= zero_enable ? previous_ploy : active_ploy;
                dout_mod  <= zero_enable ? previous_mod : active_mod;
            end
            if ((din_v && !mode_ok) ||
                (write_enable && wr_frame_count != 0 && input_mode != {phy_ploy, phy_mod}) ||
                (frame_mode_v && ((frame_ploy != 2 && frame_ploy != 4 && frame_ploy != 8) || frame_mod > 2)))
                mode_error <= 1'b1;
            if ((din_v && mode_ok && !write_enable) || (frame_mode_v && mode_full)) overflow_error <= 1'b1;
            if (state == DATA && !read_enable) underflow_error <= 1'b1;
        end
    end
    assign dout_i = !dout_v || select_zero ? 128'd0 : select_head ? head_q[127:0] : data_q[127:0];
    assign dout_q = !dout_v || select_zero ? 128'd0 : select_head ? head_q[255:128] : data_q[255:128];
endmodule
`default_nettype wire
