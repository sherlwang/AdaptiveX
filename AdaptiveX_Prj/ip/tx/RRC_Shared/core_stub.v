// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.2 (lin64) Build 3367213 Tue Oct 19 02:47:39 MDT 2021
// Design      : RRC_Shared
// Purpose     : Stub declaration of top-level module interface
// Device      : xczu47dr-ffve1156-2-i
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
module RRC_Shared(clk, rst_n, phy_ploy, din_i, din_q, din_v, dout_i, 
  dout_q, dout_v)
/* synthesis syn_black_box black_box_pad_pin="clk,rst_n,phy_ploy[3:0],din_i[63:0],din_q[63:0],din_v,dout_i[191:0],dout_q[191:0],dout_v" */;
  input clk;
  input rst_n;
  input [3:0]phy_ploy;
  input [63:0]din_i;
  input [63:0]din_q;
  input din_v;
  output [191:0]dout_i;
  output [191:0]dout_q;
  output dout_v;
endmodule
