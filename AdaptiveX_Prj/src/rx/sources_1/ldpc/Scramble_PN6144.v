`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
// Module Name: Scramble_PN6144
// Description: PN prefix restarts per 192-clock block, bit 0 is the first MATLAB bit.
// Revision: 2026/09/17 - Tx LDPC integration. Verilog-2001.
//////////////////////////////////////////////////////////////////////////////////

module Scramble_PN6144 #(
    parameter PN_FILE = "pn6144_lsb.mem"
) (
    input clk,
    input rst_n,
    input [3:0] phy_ploy,
    input [1:0] phy_mod,  // 0=BPSK, 1=QPSK, 2=16QAM
    input [32-1:0] phy_din,
    input phy_din_v,
    output reg [32-1:0] dout = 'd0,
    output reg dout_v = 'b0,
    output reg [5:0] dout_width = 6'd32
);
    //////////////////////////////////////////////////////
    //                Mode / PN Address                 //
    //////////////////////////////////////////////////////
    (* rom_style = "block" *) reg [31:0] pn_rom[0:191];
    reg [7:0] cnt_data = 'd0;
    reg [5:0] width_q = 6'd32;
    reg [5:0] requested_width;
    wire [5:0] active_width;
    reg [7:0] pn_addr;
    reg [4:0] pn_shift;
    reg [31:0] pn_dly = 'd0;
    reg [31:0] din_dly = 'd0;
    reg [4:0] shift_dly = 'd0;
    reg [5:0] width_dly = 6'd32;
    reg din_v_dly = 'b0;
    wire [31:0] width_mask;

    initial begin
        $readmemh(PN_FILE, pn_rom);
    end

    always @(*) begin
        case (phy_mod)
            2'd0: requested_width = {2'd0, phy_ploy};
            2'd1: requested_width = {2'd0, phy_ploy} << 1;
            2'd2: requested_width = {2'd0, phy_ploy} << 2;
            default: requested_width = 6'd0;
        endcase
    end
    assign active_width = (cnt_data == 0) ? requested_width : width_q;
    assign width_mask   = 32'hffffffff >> (32 - width_dly);

    always @(*) begin
        case (active_width)
            6'd2: begin
                pn_addr  = cnt_data >> 4;
                pn_shift = {cnt_data[3:0], 1'b0};
            end
            6'd4: begin
                pn_addr  = cnt_data >> 3;
                pn_shift = {cnt_data[2:0], 2'b0};
            end
            6'd8: begin
                pn_addr  = cnt_data >> 2;
                pn_shift = {cnt_data[1:0], 3'b0};
            end
            6'd16: begin
                pn_addr  = cnt_data >> 1;
                pn_shift = {cnt_data[0], 4'b0};
            end
            default: begin
                pn_addr  = cnt_data;
                pn_shift = 5'd0;
            end
        endcase
    end

    // Synchronous ROM; data, bit offset and width share the same pipeline.
    always @(posedge clk) begin
        if (phy_din_v) begin
            pn_dly <= pn_rom[pn_addr];
        end
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            cnt_data  <= 'd0;
            width_q   <= 6'd32;
            din_dly   <= 'd0;
            din_v_dly <= 'b0;
            shift_dly <= 'd0;
            width_dly <= 6'd32;
        end else begin
            din_dly   <= phy_din;
            din_v_dly <= phy_din_v;
            shift_dly <= pn_shift;
            width_dly <= active_width;
            if (phy_din_v) begin
                cnt_data <= (cnt_data == 8'd191) ? 8'd0 : cnt_data + 1'b1;
                if (cnt_data == 0) begin
                    width_q <= requested_width;
                end
            end
        end
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            dout <= 'd0;
            dout_v <= 'b0;
            dout_width <= 6'd32;
        end else begin
            dout <= (din_dly ^ (pn_dly >> shift_dly)) & width_mask;
            dout_v <= din_v_dly;
            dout_width <= width_dly;
        end
    end
endmodule
