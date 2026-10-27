// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.2 (lin64) Build 3367213 Tue Oct 19 02:47:39 MDT 2021
// Design      : Rx_Rate_Acquire
// Purpose     : Stub declaration of top-level module interface
// Device      : xczu47dr-ffve1156-2-i
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
module Rx_Rate_Acquire(clk, rst_n, write_idx, din_i, din_q, din_v, aux_read, 
  aux_read_idx, aux_dout_i, aux_dout_q, aux_dout_v, aux_dout_idx, descriptor_v, descriptor_idx, 
  descriptor_ploy_idx, descriptor_ploy, descriptor_delay, rate_locked, error, ai_valid, 
  ai_busy, ai_accepted, ai_fault, ai_p, ai_confidence, ai_sample_idx, observe_group_v, 
  observe_group_id, observe_group_anchor, observe_group_p, observe_window_v, 
  observe_window_group, observe_window_slot, observe_window_idx, observe_result_v, 
  observe_result_group, observe_result_slot, observe_result_idx, observe_result_p, 
  observe_result_accepted, observe_confirm_v, observe_confirm_group, 
  observe_confirm_anchor, observe_confirm_p, observe_cancel_all)
/* synthesis syn_black_box black_box_pad_pin="clk,rst_n,write_idx[63:0],din_i[383:0],din_q[383:0],din_v,aux_read,aux_read_idx[63:0],aux_dout_i[383:0],aux_dout_q[383:0],aux_dout_v,aux_dout_idx[63:0],descriptor_v,descriptor_idx[63:0],descriptor_ploy_idx[63:0],descriptor_ploy[3:0],descriptor_delay[3:0],rate_locked,error,ai_valid,ai_busy,ai_accepted,ai_fault,ai_p[3:0],ai_confidence[31:0],ai_sample_idx[63:0],observe_group_v,observe_group_id[31:0],observe_group_anchor[63:0],observe_group_p[3:0],observe_window_v,observe_window_group[31:0],observe_window_slot[1:0],observe_window_idx[63:0],observe_result_v,observe_result_group[31:0],observe_result_slot[1:0],observe_result_idx[63:0],observe_result_p[3:0],observe_result_accepted,observe_confirm_v,observe_confirm_group[31:0],observe_confirm_anchor[63:0],observe_confirm_p[3:0],observe_cancel_all" */;
  input clk;
  input rst_n;
  input [63:0]write_idx;
  input [383:0]din_i;
  input [383:0]din_q;
  input din_v;
  output aux_read;
  output [63:0]aux_read_idx;
  input [383:0]aux_dout_i;
  input [383:0]aux_dout_q;
  input aux_dout_v;
  input [63:0]aux_dout_idx;
  output descriptor_v;
  output [63:0]descriptor_idx;
  output [63:0]descriptor_ploy_idx;
  output [3:0]descriptor_ploy;
  output [3:0]descriptor_delay;
  output rate_locked;
  output error;
  output ai_valid;
  output ai_busy;
  output ai_accepted;
  output ai_fault;
  output [3:0]ai_p;
  output [31:0]ai_confidence;
  output [63:0]ai_sample_idx;
  output observe_group_v;
  output [31:0]observe_group_id;
  output [63:0]observe_group_anchor;
  output [3:0]observe_group_p;
  output observe_window_v;
  output [31:0]observe_window_group;
  output [1:0]observe_window_slot;
  output [63:0]observe_window_idx;
  output observe_result_v;
  output [31:0]observe_result_group;
  output [1:0]observe_result_slot;
  output [63:0]observe_result_idx;
  output [3:0]observe_result_p;
  output observe_result_accepted;
  output observe_confirm_v;
  output [31:0]observe_confirm_group;
  output [63:0]observe_confirm_anchor;
  output [3:0]observe_confirm_p;
  output observe_cancel_all;
endmodule
