// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.2 (lin64) Build 3367213 Tue Oct 19 02:47:39 MDT 2021
// Design      : Rx_NLMS
// Purpose     : Stub declaration of top-level module interface
// Device      : xczu47dr-ffve1156-2-i
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
module Rx_NLMS(clk, rst_n, phy_ploy, modulation, mode_update, 
  detected_modulation, din_i, din_q, din_v, din_pilot, din_start, din_blk, din_frame_id, dout_i, 
  dout_q, dout_v, dout_start, dout_blk, dout_ploy, dout_modulation, dout_frame_id)
/* synthesis syn_black_box black_box_pad_pin="clk,rst_n,phy_ploy[3:0],modulation[1:0],mode_update,detected_modulation[1:0],din_i[127:0],din_q[127:0],din_v,din_pilot,din_start,din_blk[2:0],din_frame_id[31:0],dout_i[127:0],dout_q[127:0],dout_v,dout_start,dout_blk[2:0],dout_ploy[3:0],dout_modulation[1:0],dout_frame_id[31:0]" */;
  input clk;
  input rst_n;
  input [3:0]phy_ploy;
  input [1:0]modulation;
  input mode_update;
  input [1:0]detected_modulation;
  input [127:0]din_i;
  input [127:0]din_q;
  input din_v;
  input din_pilot;
  input din_start;
  input [2:0]din_blk;
  input [31:0]din_frame_id;
  output [127:0]dout_i;
  output [127:0]dout_q;
  output dout_v;
  output dout_start;
  output [2:0]dout_blk;
  output [3:0]dout_ploy;
  output [1:0]dout_modulation;
  output [31:0]dout_frame_id;
endmodule
