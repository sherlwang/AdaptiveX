// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.2 (lin64) Build 3367213 Tue Oct 19 02:47:39 MDT 2021
// Design      : Rx_Header_Sync
// Purpose     : Stub declaration of top-level module interface
// Device      : xczu47dr-ffve1156-2-i
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
module Rx_Header_Sync(clk, rst_n, phy_ploy, source_base_idx, din_i, 
  din_q, din_v, phase_locked, phase_update_in, confirmed_frame_idx, sample_delay_in, 
  phase_update, phase_pending, phase_frame_idx, sample_delay, dout_i, dout_q, dout_v, dout_ploy, 
  frame_peak, frame_threshold, dout_frame_idx, dout_start)
/* synthesis syn_black_box black_box_pad_pin="clk,rst_n,phy_ploy[3:0],source_base_idx[63:0],din_i[127:0],din_q[127:0],din_v,phase_locked,phase_update_in,confirmed_frame_idx[23:0],sample_delay_in[3:0],phase_update,phase_pending,phase_frame_idx[23:0],sample_delay[3:0],dout_i[127:0],dout_q[127:0],dout_v,dout_ploy[3:0],frame_peak[61:0],frame_threshold[61:0],dout_frame_idx[23:0],dout_start" */;
  input clk;
  input rst_n;
  input [3:0]phy_ploy;
  input [63:0]source_base_idx;
  input [127:0]din_i;
  input [127:0]din_q;
  input din_v;
  input phase_locked;
  input phase_update_in;
  input [23:0]confirmed_frame_idx;
  input [3:0]sample_delay_in;
  output phase_update;
  output phase_pending;
  output [23:0]phase_frame_idx;
  output [3:0]sample_delay;
  output [127:0]dout_i;
  output [127:0]dout_q;
  output dout_v;
  output [3:0]dout_ploy;
  output [61:0]frame_peak;
  output [61:0]frame_threshold;
  output [23:0]dout_frame_idx;
  output dout_start;
endmodule
