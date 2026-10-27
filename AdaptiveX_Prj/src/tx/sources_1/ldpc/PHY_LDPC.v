`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: PHY_LDPC
// Description: 192clk input -> PN6144 scrambling -> 255clk LDPC codeword.
// Tool Versions: Verilog-2001 / Vivado 2021.2
// Revision: 2026/09/20 - Fixed frame, no metadata or backpressure ports.
// Mode metadata is aligned through scrambling and both codeword banks.
//////////////////////////////////////////////////////////////////////////////////

module PHY_LDPC #(
    parameter PN_FILE  = "pn6144_lsb.mem",
    parameter ROM_FILE = "enc_edges.mem"
) (
    input clk,
    input rst_n,
    input [3:0] phy_ploy,
    input [1:0] phy_mod,
    input [31:0] phy_din,
    input phy_din_v,
    output [31:0] dout,
    output dout_v,
    output [3:0] dout_ploy,
    output [1:0] dout_mod
);
    wire [31:0] scra_data;
    wire scra_v;
    wire [5:0] scra_width;
    wire [3:0] scra_ploy;
    wire [1:0] scra_mod;

    Scramble_PN6144 #(
        .PN_FILE(PN_FILE)
    ) u_Scramble_PN6144 (
        .clk       (clk),
        .rst_n     (rst_n),
        .phy_ploy  (phy_ploy),
        .phy_mod   (phy_mod),
        .phy_din   (phy_din),
        .phy_din_v (phy_din_v),
        .dout      (scra_data),
        .dout_v    (scra_v),
        .dout_width(scra_width),
        .dout_ploy (scra_ploy),
        .dout_mod  (scra_mod)
    );
    ldpc_encoder u_ldpc_encoder (
        .clk      (clk),
        .rst_n    (rst_n),
        .phy_width(scra_width),
        .phy_ploy (scra_ploy),
        .phy_mod  (scra_mod),
        .din      (scra_data),
        .din_v    (scra_v),
        .dout     (dout),
        .dout_v   (dout_v),
        .dout_ploy(dout_ploy),
        .dout_mod (dout_mod)
    );
endmodule
