// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.2 (lin64) Build 3367213 Tue Oct 19 02:47:39 MDT 2021
// Design      : Rx_FDE_Core_8
// Purpose     : Stub declaration of top-level module interface
// Device      : xczu47dr-ffve1156-2-i
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
module Rx_FDE_Core_8(clk, rst_n, phy_ploy, mov_zf_window_len, din_i, 
  din_q, din_v, din_start, din_frame_id, dout_i, dout_q, dout_v, dout_ploy, training_i, training_q, 
  training_idx, training_v, training_ploy, training_frame_id, dout_frame_id)
/* synthesis syn_black_box black_box_pad_pin="clk,rst_n,phy_ploy[3:0],mov_zf_window_len[4:0],din_i[127:0],din_q[127:0],din_v,din_start,din_frame_id[31:0],dout_i[127:0],dout_q[127:0],dout_v,dout_ploy[3:0],training_i[24:0],training_q[24:0],training_idx[10:0],training_v,training_ploy[3:0],training_frame_id[31:0],dout_frame_id[31:0]" */;
  input clk;
  input rst_n;
  input [3:0]phy_ploy;
  input [4:0]mov_zf_window_len;
  input [127:0]din_i;
  input [127:0]din_q;
  input din_v;
  input din_start;
  input [31:0]din_frame_id;
  output [127:0]dout_i;
  output [127:0]dout_q;
  output dout_v;
  output [3:0]dout_ploy;
  output [24:0]training_i;
  output [24:0]training_q;
  output [10:0]training_idx;
  output training_v;
  output [3:0]training_ploy;
  output [31:0]training_frame_id;
  output [31:0]dout_frame_id;
endmodule
