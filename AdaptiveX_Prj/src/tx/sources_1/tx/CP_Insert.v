`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: CP_Insert
// Description: Fixed 9clk CP: X[247..255], X[0..255]; two 256-word RAM banks.
// Tool Versions: Verilog-2001 / Vivado 2021.2
// Revision: 2026/10/14 - Each CP bank retains its own mode metadata.
//////////////////////////////////////////////////////////////////////////////////

module CP_Insert (
    input clk,
    input rst_n,
    input [3:0] phy_ploy,
    input [1:0] phy_mod,
    input [127:0] din_i,
    input [127:0] din_q,
    input din_v,
    output [127:0] dout_i,
    output [127:0] dout_q,
    output reg dout_v,
    output reg [3:0] dout_ploy,
    output reg [1:0] dout_mod
);
    (* ram_style = "block" *) reg [255:0] mem[0:511];
    reg [255:0] ram_q;
    reg [1:0] complete;
    reg [5:0] bank_mode[0:1];
    reg wr_bank;
    reg rd_bank;
    reg reading;
    reg [7:0] wr_index;
    reg [8:0] rd_index;
    wire [8:0] rd_offset;
    wire read_enable;

    assign rd_offset = (rd_index < 9) ? 9'd247 + rd_index : rd_index - 9'd9;
    assign read_enable = rst_n && reading;
    assign dout_i = dout_v ? ram_q[127:0] : 128'd0;
    assign dout_q = dout_v ? ram_q[255:128] : 128'd0;

    // No RAM reset: complete/reading bits invalidate old contents.
    always @(posedge clk) begin
        if (rst_n && din_v) mem[{wr_bank, wr_index}] <= {din_q, din_i};
        if (read_enable) ram_q <= mem[{rd_bank, rd_offset[7:0]}];
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            complete <= 2'b00;
            bank_mode[0] <= {4'd2, 2'd0};
            bank_mode[1] <= {4'd2, 2'd0};
            dout_ploy <= 4'd2;
            dout_mod <= 2'd0;
            wr_bank <= 1'b0;
            rd_bank <= 1'b0;
            reading <= 1'b0;
            wr_index <= 8'd0;
            rd_index <= 9'd0;
            dout_v <= 1'b0;
        end else begin
            dout_v <= read_enable;
            if (read_enable) begin
                dout_ploy <= bank_mode[rd_bank][5:2];
                dout_mod  <= bank_mode[rd_bank][1:0];
            end
            if (din_v) begin
                if (wr_index == 0) bank_mode[wr_bank] <= {phy_ploy, phy_mod};
                wr_index <= wr_index + 1'b1;
                if (wr_index == 8'd255) begin
                    complete[wr_bank] <= 1'b1;
                    wr_bank <= ~wr_bank;
                end
            end
            if (!reading && complete[rd_bank]) begin
                reading  <= 1'b1;
                rd_index <= 9'd0;
            end
            if (read_enable) begin
                if (rd_index == 9'd264) begin
                    complete[rd_bank] <= 1'b0;
                    rd_bank <= ~rd_bank;
                    rd_index <= 9'd0;
                    reading <= complete[~rd_bank];
                end else rd_index <= rd_index + 1'b1;
            end
        end
    end
endmodule
