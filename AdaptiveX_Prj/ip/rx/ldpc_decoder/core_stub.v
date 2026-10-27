// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.2 (lin64) Build 3367213 Tue Oct 19 02:47:39 MDT 2021
// Design      : ldpc_decoder
// Purpose     : Stub declaration of top-level module interface
// Device      : xczu47dr-ffve1156-2-i
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
module ldpc_decoder(clk, clk_core, rst_n, phy_ploy, phy_mod, din_width, 
  din_llr, din_v, dout, dout_v, block_done, decode_ok, iterations, group_ok, dout_width, 
  overflow_error, mode_error)
/* synthesis syn_black_box black_box_pad_pin="clk,clk_core,rst_n,phy_ploy[3:0],phy_mod[1:0],din_width[5:0],din_llr[255:0],din_v,dout[31:0],dout_v,block_done,decode_ok,iterations[3:0],group_ok[3:0],dout_width[5:0],overflow_error,mode_error" */;
  input clk;
  input clk_core;
  input rst_n;
  input [3:0]phy_ploy;
  input [1:0]phy_mod;
  input [5:0]din_width;
  input [255:0]din_llr;
  input din_v;
  output [31:0]dout;
  output dout_v;
  output block_done;
  output decode_ok;
  output [3:0]iterations;
  output [3:0]group_ok;
  output [5:0]dout_width;
  output overflow_error;
  output mode_error;
endmodule
