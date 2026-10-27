// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.2 (lin64) Build 3367213 Tue Oct 19 02:47:39 MDT 2021
// Design      : rx_ai_switch
// Purpose     : Stub declaration of top-level module interface
// Device      : xczu47dr-ffve1156-2-i
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
module rx_ai_switch(clk, rst_n, sync_p, cfo_p, h_p, pilot_p, mode_update, 
  mode_frame_id, mode_p, mode_m, frame_start, sync_frame_id, cfo_frame_id, 
  cfo_estimate_frame_id, h_frame_id, pilot_frame_id, llr_frame_id, decode_frame_id, 
  decode_block, sync_peak, sync_threshold, missed_before, cfo_step, cfo_valid, cfo_i, cfo_q, cfo_v, 
  cfo_start, h_i, h_q, h_index, h_valid, pilot_i, pilot_q, pilot_v, pilot_flag, pilot_block, llr, 
  llr_width, llr_v, llr_start, llr_block, decode_done, decode_ok, phy_fault, ai_result_valid, 
  ai_mode_predict, ai_confidence, ai_frame_id, ai_fault, skipped_vectors, feature_valid, 
  feature_debug, current_mode_debug, logits_debug, inference_busy, ai_result_fallback, 
  ai_result_reason, fallback_active, link_lost, sync_age, result_count, pending_count)
/* synthesis syn_black_box black_box_pad_pin="clk,rst_n,sync_p[3:0],cfo_p[3:0],h_p[3:0],pilot_p[3:0],mode_update,mode_frame_id[31:0],mode_p[3:0],mode_m[1:0],frame_start,sync_frame_id[31:0],cfo_frame_id[31:0],cfo_estimate_frame_id[31:0],h_frame_id[31:0],pilot_frame_id[31:0],llr_frame_id[31:0],decode_frame_id[31:0],decode_block[2:0],sync_peak[61:0],sync_threshold[61:0],missed_before[15:0],cfo_step[31:0],cfo_valid,cfo_i[127:0],cfo_q[127:0],cfo_v,cfo_start,h_i[24:0],h_q[24:0],h_index[10:0],h_valid,pilot_i[127:0],pilot_q[127:0],pilot_v,pilot_flag,pilot_block[2:0],llr[255:0],llr_width[5:0],llr_v,llr_start,llr_block[2:0],decode_done,decode_ok,phy_fault,ai_result_valid,ai_mode_predict[3:0],ai_confidence[31:0],ai_frame_id[31:0],ai_fault[10:0],skipped_vectors[31:0],feature_valid[8:0],feature_debug[359:0],current_mode_debug[3:0],logits_debug[287:0],inference_busy,ai_result_fallback,ai_result_reason[3:0],fallback_active,link_lost,sync_age[31:0],result_count[31:0],pending_count[4:0]" */;
  input clk;
  input rst_n;
  input [3:0]sync_p;
  input [3:0]cfo_p;
  input [3:0]h_p;
  input [3:0]pilot_p;
  input mode_update;
  input [31:0]mode_frame_id;
  input [3:0]mode_p;
  input [1:0]mode_m;
  input frame_start;
  input [31:0]sync_frame_id;
  input [31:0]cfo_frame_id;
  input [31:0]cfo_estimate_frame_id;
  input [31:0]h_frame_id;
  input [31:0]pilot_frame_id;
  input [31:0]llr_frame_id;
  input [31:0]decode_frame_id;
  input [2:0]decode_block;
  input [61:0]sync_peak;
  input [61:0]sync_threshold;
  input [15:0]missed_before;
  input [31:0]cfo_step;
  input cfo_valid;
  input [127:0]cfo_i;
  input [127:0]cfo_q;
  input cfo_v;
  input cfo_start;
  input [24:0]h_i;
  input [24:0]h_q;
  input [10:0]h_index;
  input h_valid;
  input [127:0]pilot_i;
  input [127:0]pilot_q;
  input pilot_v;
  input pilot_flag;
  input [2:0]pilot_block;
  input [255:0]llr;
  input [5:0]llr_width;
  input llr_v;
  input llr_start;
  input [2:0]llr_block;
  input decode_done;
  input decode_ok;
  input phy_fault;
  output ai_result_valid;
  output [3:0]ai_mode_predict;
  output [31:0]ai_confidence;
  output [31:0]ai_frame_id;
  output [10:0]ai_fault;
  output [31:0]skipped_vectors;
  output [8:0]feature_valid;
  output [359:0]feature_debug;
  output [3:0]current_mode_debug;
  output [287:0]logits_debug;
  output inference_busy;
  output ai_result_fallback;
  output [3:0]ai_result_reason;
  output fallback_active;
  output link_lost;
  output [31:0]sync_age;
  output [31:0]result_count;
  output [4:0]pending_count;
endmodule
