// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.2 (lin64) Build 3367213 Tue Oct 19 02:47:39 MDT 2021
// Design      : ldpc_encoder
// Purpose     : Stub declaration of top-level module interface
// Device      : xczu47dr-ffve1156-2-i
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
module ldpc_encoder(clk, rst_n, phy_width, phy_ploy, phy_mod, din, din_v, 
  dout, dout_v, dout_ploy, dout_mod)
/* synthesis syn_black_box black_box_pad_pin="clk,rst_n,phy_width[5:0],phy_ploy[3:0],phy_mod[1:0],din[31:0],din_v,dout[31:0],dout_v,dout_ploy[3:0],dout_mod[1:0]" */;
  input clk;
  input rst_n;
  input [5:0]phy_width;
  input [3:0]phy_ploy;
  input [1:0]phy_mod;
  input [31:0]din;
  input din_v;
  output [31:0]dout;
  output dout_v;
  output [3:0]dout_ploy;
  output [1:0]dout_mod;
endmodule
