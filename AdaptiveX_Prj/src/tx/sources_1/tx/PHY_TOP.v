`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/06/28 21:04:33
// Design Name: 
// Module Name: PHY_TOP
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module PHY_TOP #(
    parameter integer        USE_VIO         = 1,
    parameter         [15:0] FIXED_GAIN      = 16'h0100,
    parameter         [11:0] FIXED_PHASE_INC = 12'd1000,
    parameter                FIXED_REVERSE   = 1'b0
) (
    input clk_200M,
    input clk_400M,
    input rst_n,
    input [3:0] phy_ploy,
    input [1:0] phy_mod,
    input [31:0] phy_din,
    input phy_din_v,
    output [191:0] DAC_IQ,
    output wire tx_rate_v,
    output wire tx_rate_guard,
    output wire [3:0] tx_rate_ploy,
    output wire [1:0] tx_rate_mod
);
    localparam PLOY       = 8;
    localparam PLOY_WIDTH = 16;
    wire [31:0] ldpc_dout;
    wire ldpc_dout_v;
    wire [3:0] ldpc_ploy;
    wire [3:0] head_ploy;
    wire [3:0] dout_fifo_ploy;
    wire [1:0] ldpc_mod;
    wire [1:0] head_mod;
    wire [1:0] dout_fifo_mod;
    wire head_guard;
    wire dout_fifo_guard;
    wire [127:0] add_Head_i;
    wire [127:0] add_Head_q;
    wire add_Head_v;
    wire [63:0] dout_fifo_i;
    wire [63:0] dout_fifo_q;
    wire dout_fifo_v;
    wire [191:0] dout_Rcos_i;
    wire [191:0] dout_Rcos_q;
    wire [191:0] Gain_out_i;
    wire [191:0] Gain_out_q;
    wire rst_slow_n;
    wire rst_fast_n;

    // Observe the emitted tagged words, including valid old-P drain zeros.
    // The air-frame monitor follows these words through the DSP/DAC latency.
    assign tx_rate_v = dout_fifo_v;
    assign tx_rate_guard = dout_fifo_guard;
    assign tx_rate_ploy = dout_fifo_ploy;
    assign tx_rate_mod = dout_fifo_mod;

    Reset_Sync u_reset_slow (
        .clk   (clk_200M),
        .arst_n(rst_n),
        .rst_n (rst_slow_n)
    );
    Reset_Sync u_reset_fast (
        .clk   (clk_400M),
        .arst_n(rst_n),
        .rst_n (rst_fast_n)
    );
    // Mode metadata crosses with the data word in Rate_Convert RAM.

    PHY_LDPC u_PHY_LDPC (
        .clk      (clk_200M),
        .rst_n    (rst_slow_n),
        .phy_ploy (phy_ploy),
        .phy_mod  (phy_mod),
        .phy_din  (phy_din),
        .phy_din_v(phy_din_v),
        .dout     (ldpc_dout),
        .dout_v   (ldpc_dout_v),
        .dout_ploy(ldpc_ploy),
        .dout_mod (ldpc_mod)
    );
    PHY_SYMBOL u_PHY_SYMBOL (
        .clk       (clk_200M),
        .rst_n     (rst_slow_n),
        .phy_ploy  (ldpc_ploy),
        .phy_mod   (ldpc_mod),
        .din       (ldpc_dout),
        .din_v     (ldpc_dout_v),
        .dout_i    (add_Head_i),
        .dout_q    (add_Head_q),
        .dout_v    (add_Head_v),
        .dout_ploy (head_ploy),
        .dout_mod  (head_mod),
        .dout_guard(head_guard)
    );

    ///////////////////////////////////////////////
    //                  add_Head                 //
    ///////////////////////////////////////////////

    // Header insertion is inside PHY_SYMBOL, alongside CP_Insert.

    reg [8*16-1:0] Time_out_i = 'b0;
    reg [8*16-1:0] Time_out_q = 'b0;
    reg Time_out_v;
    reg [3:0] Time_out_ploy;
    reg [1:0] Time_out_mod;
    reg Time_out_guard;
    genvar k;
    generate
        for (k = 0; k < 8; k = k + 1) begin
            always @(posedge clk_200M) begin
                Time_out_i[16*k+:16] <= {add_Head_i[16*k+15], add_Head_i[16*k+15-:15]};  //16q13
                Time_out_q[16*k+:16] <= {add_Head_q[16*k+15], add_Head_q[16*k+15-:15]};  //16q13     
            end
        end
    endgenerate

    always @(posedge clk_200M) begin
        if (~rst_slow_n) begin
            Time_out_v <= 'b0;
            Time_out_ploy <= 4'd2;
            Time_out_mod <= 2'd0;
            Time_out_guard <= 1'b0;
        end else begin
            Time_out_v <= add_Head_v;
            Time_out_ploy <= head_ploy;
            Time_out_mod <= head_mod;
            Time_out_guard <= head_guard;
        end
    end


    ///////////////////////////////////////////////
    //                fifo                       //
    ///////////////////////////////////////////////

    //    wire [2*16-1:0] dout_fifo_i  ;
    //    wire [2*16-1:0] dout_fifo_q  ;
    //    wire            dout_fifo_v  ;

    Rate_Convert u_Rate_Convert (
        .clk_400M  (clk_400M),
        .clk_200M  (clk_200M),
        .din_i     (Time_out_i),
        .din_q     (Time_out_q),
        .rst_n     (rst_n),
        .din_v     (Time_out_v),
        .phy_ploy  (Time_out_ploy),
        .phy_mod   (Time_out_mod),
        .din_guard (Time_out_guard),
        .dout_ploy (dout_fifo_ploy),
        .dout_mod  (dout_fifo_mod),
        .dout_guard(dout_fifo_guard),
        .dout_i    (dout_fifo_i),
        .dout_q    (dout_fifo_q),
        .dout_v    (dout_fifo_v)
    );


    ///////////////////////////////////////////////
    //                    Rcos                   //
    ///////////////////////////////////////////////
    // All modes use the same 12-lane output engine, signed16 F13.
    // Invalid input advances zero symbol slots; filter tails are not discarded.
    wire dout_Rcos_v;
    RRC_Shared u_RRC_Shared (
        .clk     (clk_400M),
        .rst_n   (rst_fast_n),
        .phy_ploy(dout_fifo_ploy),
        .din_i   (dout_fifo_i),
        .din_q   (dout_fifo_q),
        .din_v   (dout_fifo_v),
        .dout_i  (dout_Rcos_i),
        .dout_q  (dout_Rcos_q),
        .dout_v  (dout_Rcos_v)
    );


    ///////////////////////////////////////////////
    //                    Gain                   //
    ///////////////////////////////////////////////

    wire [15:0] Vio_Gain;  //16q9
    wire [11:0] Vio_Up_convert;
    wire VIO_REVERSE;
    generate
        if (USE_VIO != 0) begin : control_vio
            vio_gain vio_gain (
                .clk       (clk_400M),
                .probe_out0(Vio_Gain),
                .probe_out1(Vio_Up_convert),
                .probe_out2(VIO_REVERSE)
            );
        end else begin : control_fixed
            // Offline simulation uses the same defaults as the VIO XCI.
            assign Vio_Gain = FIXED_GAIN;
            assign Vio_Up_convert = FIXED_PHASE_INC;
            assign VIO_REVERSE = FIXED_REVERSE;
        end
    endgenerate

    //    wire    [12*16-1:0]  Gain_out_i;
    //    wire    [12*16-1:0]  Gain_out_q;
    Gain #(
        .Ploy(12)
    ) Gain_i (
        .clk     (clk_400M),
        .rst_n   (rst_fast_n),
        .din_i   (dout_Rcos_i),  //16q13
        .Vio_Gain(Vio_Gain),     //16q9
        .dout_i  (Gain_out_i)    //16q13
    );

    Gain #(
        .Ploy(12)
    ) Gain_q (
        .clk     (clk_400M),
        .rst_n   (rst_fast_n),
        .din_i   (dout_Rcos_q),  //16q13
        .Vio_Gain(Vio_Gain),     //16q9
        .dout_i  (Gain_out_q)    //16q13
    );

    // BEGIN GAIN_REVERSE_TIMING_SLICE
    // Preserve the original whole-192-bit two's complement exactly. Carry into
    // lane N is one iff every original bit below that lane is zero; derive each
    // prefix independently so no carry chain crosses all twelve 16-bit lanes.
    wire [12*16-1:0] Gain_out_q_reverse;
    genvar reverse_lane;
    generate
        for(reverse_lane=0;reverse_lane<12;reverse_lane=reverse_lane+1)begin:g_gain_reverse
            wire carry_in;
            if(reverse_lane==0)begin:g_first
                assign carry_in=1'b1;
            end else begin:g_prefix
                assign carry_in=~(|Gain_out_q[16*reverse_lane-1:0]);
            end
            assign Gain_out_q_reverse[16*reverse_lane +: 16] =
                ~Gain_out_q[16*reverse_lane +: 16] + {15'd0,carry_in};
        end
    endgenerate
    reg [12*16-1:0] Gain_out_i_d1 = 'b0;
    reg [12*16-1:0] Gain_out_q_d1 = 'b0;
    always @(posedge clk_400M) begin
        Gain_out_i_d1 <= Gain_out_i;  //16q13
        Gain_out_q_d1 <= (VIO_REVERSE) ? Gain_out_q_reverse : Gain_out_q;  //16q13
    end
    // END GAIN_REVERSE_TIMING_SLICE


    ///////////////////////////////////////////////
    //               Up_Conversion               //
    ///////////////////////////////////////////////

    up_12ploy u_up_12ploy (
        .clk       (clk_400M),
        .rst_n     (rst_fast_n),
        .clk_enable(1'b1),
        .Din_re_0  (Gain_out_i_d1[0*16+:16]),
        .Din_re_1  (Gain_out_i_d1[1*16+:16]),
        .Din_re_2  (Gain_out_i_d1[2*16+:16]),
        .Din_re_3  (Gain_out_i_d1[3*16+:16]),
        .Din_re_4  (Gain_out_i_d1[4*16+:16]),
        .Din_re_5  (Gain_out_i_d1[5*16+:16]),
        .Din_re_6  (Gain_out_i_d1[6*16+:16]),
        .Din_re_7  (Gain_out_i_d1[7*16+:16]),
        .Din_re_8  (Gain_out_i_d1[8*16+:16]),
        .Din_re_9  (Gain_out_i_d1[9*16+:16]),
        .Din_re_10 (Gain_out_i_d1[10*16+:16]),
        .Din_re_11 (Gain_out_i_d1[11*16+:16]),
        .Din_im_0  (Gain_out_q_d1[0*16+:16]),
        .Din_im_1  (Gain_out_q_d1[1*16+:16]),
        .Din_im_2  (Gain_out_q_d1[2*16+:16]),
        .Din_im_3  (Gain_out_q_d1[3*16+:16]),
        .Din_im_4  (Gain_out_q_d1[4*16+:16]),
        .Din_im_5  (Gain_out_q_d1[5*16+:16]),
        .Din_im_6  (Gain_out_q_d1[6*16+:16]),
        .Din_im_7  (Gain_out_q_d1[7*16+:16]),
        .Din_im_8  (Gain_out_q_d1[8*16+:16]),
        .Din_im_9  (Gain_out_q_d1[9*16+:16]),
        .Din_im_10 (Gain_out_q_d1[10*16+:16]),
        .Din_im_11 (Gain_out_q_d1[11*16+:16]),
        .Phase_Inc ({4'd0, Vio_Up_convert}),
        .ce_out    (),
        .Dout_0    (DAC_IQ[0*16+:16]),
        .Dout_1    (DAC_IQ[1*16+:16]),
        .Dout_2    (DAC_IQ[2*16+:16]),
        .Dout_3    (DAC_IQ[3*16+:16]),
        .Dout_4    (DAC_IQ[4*16+:16]),
        .Dout_5    (DAC_IQ[5*16+:16]),
        .Dout_6    (DAC_IQ[6*16+:16]),
        .Dout_7    (DAC_IQ[7*16+:16]),
        .Dout_8    (DAC_IQ[8*16+:16]),
        .Dout_9    (DAC_IQ[9*16+:16]),
        .Dout_10   (DAC_IQ[10*16+:16]),
        .Dout_11   (DAC_IQ[11*16+:16])
    );

endmodule
