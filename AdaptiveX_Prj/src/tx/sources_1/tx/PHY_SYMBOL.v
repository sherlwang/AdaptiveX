`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Module Name: PHY_SYMBOL
// Description: Tagged bits -> mapper -> pilot -> CP -> header/valid-zero guard.
// The first of each frame's 1530 coded words supplies the header mode ahead of
// CP data; each FIFO/bank still carries its own data mode. No backpressure.
// Revision: 2026/10/14 - Tx_No_Reset, Verilog-2001 / Vivado 2021.2.
//////////////////////////////////////////////////////////////////////////////////
module PHY_SYMBOL (
    input wire clk,
    input wire rst_n,
    input wire [3:0] phy_ploy,
    input wire [1:0] phy_mod,
    input wire [31:0] din,
    input wire din_v,
    output wire [127:0] dout_i,
    output wire [127:0] dout_q,
    output wire dout_v,
    output wire [3:0] dout_ploy,
    output wire [1:0] dout_mod,
    output wire dout_guard
);
    wire [127:0] mod_i;
    wire [127:0] mod_q;
    wire [127:0] pilot_i;
    wire [127:0] pilot_q;
    wire [127:0] cp_i;
    wire [127:0] cp_q;
    wire mod_v;
    wire pilot_v;
    wire cp_v;
    wire [3:0] mod_ploy;
    wire [3:0] pilot_ploy;
    wire [3:0] cp_ploy;
    wire [1:0] mod_mod;
    wire [1:0] pilot_mod;
    wire [1:0] cp_mod;
    reg [10:0] coded_frame_count;
    wire frame_mode_v = din_v && coded_frame_count == 0;

    always @(posedge clk) begin
        if (!rst_n) coded_frame_count <= 11'd0;
        else if (din_v) coded_frame_count <= coded_frame_count == 1529 ? 0 : coded_frame_count + 1'b1;
    end
    Mod_Map u_Mod_Map (
        .clk      (clk),
        .rst_n    (rst_n),
        .phy_ploy (phy_ploy),
        .phy_mod  (phy_mod),
        .din      (din),
        .din_v    (din_v),
        .dout_i   (mod_i),
        .dout_q   (mod_q),
        .dout_v   (mod_v),
        .dout_ploy(mod_ploy),
        .dout_mod (mod_mod)
    );
    Pilot_Insert u_Pilot_Insert (
        .clk      (clk),
        .rst_n    (rst_n),
        .phy_ploy (mod_ploy),
        .phy_mod  (mod_mod),
        .din_i    (mod_i),
        .din_q    (mod_q),
        .din_v    (mod_v),
        .dout_i   (pilot_i),
        .dout_q   (pilot_q),
        .dout_v   (pilot_v),
        .dout_ploy(pilot_ploy),
        .dout_mod (pilot_mod)
    );
    CP_Insert u_CP_Insert (
        .clk      (clk),
        .rst_n    (rst_n),
        .phy_ploy (pilot_ploy),
        .phy_mod  (pilot_mod),
        .din_i    (pilot_i),
        .din_q    (pilot_q),
        .din_v    (pilot_v),
        .dout_i   (cp_i),
        .dout_q   (cp_q),
        .dout_v   (cp_v),
        .dout_ploy(cp_ploy),
        .dout_mod (cp_mod)
    );
    Head_Insert u_Head_Insert (
        .clk         (clk),
        .rst_n       (rst_n),
        .phy_ploy    (cp_ploy),
        .phy_mod     (cp_mod),
        .frame_ploy  (phy_ploy),
        .frame_mod   (phy_mod),
        .frame_mode_v(frame_mode_v),
        .din_i       (cp_i),
        .din_q       (cp_q),
        .din_v       (cp_v),
        .dout_i      (dout_i),
        .dout_q      (dout_q),
        .dout_v      (dout_v),
        .dout_ploy   (dout_ploy),
        .dout_mod    (dout_mod),
        .dout_guard  (dout_guard)
    );
endmodule
`default_nettype wire
