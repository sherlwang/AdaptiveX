// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.2 (lin64) Build 3367213 Tue Oct 19 02:47:39 MDT 2021
// Design      : Rx_Demap_9
// Purpose     : Stub declaration of top-level module interface
// Device      : xczu47dr-ffve1156-2-i
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
module Rx_Demap_9(clk, rst_n, phy_ploy, modulation, din_i, din_q, 
  din_v, din_block, din_frame_id, coded_bits, coded_llr, coded_width, coded_v, coded_start, 
  coded_block, coded_frame_id)
/* synthesis syn_black_box black_box_pad_pin="clk,rst_n,phy_ploy[3:0],modulation[1:0],din_i[127:0],din_q[127:0],din_v,din_block[2:0],din_frame_id[31:0],coded_bits[31:0],coded_llr[255:0],coded_width[5:0],coded_v,coded_start,coded_block[2:0],coded_frame_id[31:0]" */;
  input clk;
  input rst_n;
  input [3:0]phy_ploy;
  input [1:0]modulation;
  input [127:0]din_i;
  input [127:0]din_q;
  input din_v;
  input [2:0]din_block;
  input [31:0]din_frame_id;
  output [31:0]coded_bits;
  output [255:0]coded_llr;
  output [5:0]coded_width;
  output coded_v;
  output coded_start;
  output [2:0]coded_block;
  output [31:0]coded_frame_id;
endmodule
