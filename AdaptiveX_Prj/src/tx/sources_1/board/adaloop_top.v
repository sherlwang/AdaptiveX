`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/08/09 00:38:59
// Design Name: 
// Module Name: adaloop_top
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


module adaloop_top(

//eth 
// input                   gty_refclk0p_i  ,
// input                   gty_refclk0n_i  ,

//global clock
input   wire            pl_clk_n        ,
input   wire            pl_clk_p        ,
input   wire            pl_sysref_n     ,
input   wire            pl_sysref_p     ,
//eth 
input   wire            gt_refclk_p     ,
input   wire            gt_refclk_n     ,

//tx
input   wire            gt_rxp_in_0     ,
input   wire            gt_rxn_in_0     ,
output  wire            gt_txp_out_0    ,
output  wire            gt_txn_out_0    ,

input   wire            gt_rxp_in_1     ,
input   wire            gt_rxn_in_1     ,
output  wire            gt_txp_out_1    ,
output  wire            gt_txn_out_1    ,
//rf signal
input   wire            adc1_clk_n      ,
input   wire            adc1_clk_p      ,

input   wire            dac2_clk_n      ,
input   wire            dac2_clk_p      ,

input   wire            sysref_in_n     ,
input   wire            sysref_in_p     ,
input   wire            vin0_01_n       , 
input   wire            vin0_01_p       , 
input   wire            vin0_23_n       , 
input   wire            vin0_23_p       , 
input   wire            vin1_01_n       ,
input   wire            vin1_01_p       ,
input   wire            vin1_23_n       ,
input   wire            vin1_23_p       ,

output  wire            vout20_n        ,
output  wire            vout20_p        ,
output  wire            vout22_n        ,
output  wire            vout22_p        ,
output  wire            vout30_n        ,
output  wire            vout30_p        ,
output  wire            vout32_n        ,
output  wire            vout32_p        ,

//other
inout   wire            lmk_sync        ,
output  wire    [3:0]   led             ,
output  wire            user_io7        ,
output  wire            user_io6        ,
output  wire            user_io5        ,
output  wire            user_io4        ,
inout   wire    [3:0]   user_io         ,
inout   wire            trig_out        ,
input   wire            trig_in         ,
input   wire            gps_1pps        ,
input   wire            txd_gps          
);

wire                    data_clk        ;
wire                    data_clk1       ;
wire                    data_clk2       ;
wire                    locked          ;
wire                    fclk_100m       ;
wire                    fclk_reset0     ;
wire                    pl_clk          ;
wire                    pl_sysref       ;
wire                    config_done     ;
wire [7:0]              adc_freeze      ;
wire [7:0]              adc_clear_ov    ;
wire                    fddtdd_sw       ;
wire                    trx_sw_ps       ;
wire [191:0]            m10_axis_tdata  ;
wire [191:0]            m11_axis_tdata  ;
wire [191:0]            m12_axis_tdata  ;
wire [191:0]            m13_axis_tdata  ;
wire                    m10_axis_tvalid ;
wire                    m11_axis_tvalid ;
wire                    m12_axis_tvalid ;
wire                    m13_axis_tvalid ;
wire                    s30_axis_tready ;
wire                    s32_axis_tready ;
wire                    feedback_packet_v;
wire [23:0]             feedback_packet;
wire [31:0]             feedback_status;
wire [31:0]             feedback_received_count;
wire [31:0]             dac_metadata;
reg                     run_enable_ps;
wire                    feedback_arst_n;
wire                    tx_run;
wire    [12*16-1:0]     DAC_IQ          ;
wire    [12*16-1:0]     DAC_IQ_RX       ;
wire    [12*16-1:0]     m00_axis_tdata  ;
wire                    m00_axis_tready ;
wire                    m00_axis_tvalid ;
wire    [12*16-1:0]     m02_axis_tdata  ;
wire                    m02_axis_tready ;
wire                    m02_axis_tvalid ;

wire    [15:0]          gpio_tri_i      ;
wire    [15:0]          gpio_tri_o      ;
wire    [15:0]          gpio_tri_t      ;
wire    [ 6:0]          axi_rd_addr     ;
wire    [ 6:0]          axi_wr_addr     ;
wire    [31:0]          axi_rd_data     ;
wire    [31:0]          axi_wr_data     ;

wire                    up_rack         ;
wire    [15:0]          up_raddr        ;
wire    [31:0]          up_rdata        ;
wire                    up_rreq         ;
wire                    up_wack         ;
wire    [15:0]          up_waddr        ;
wire    [31:0]          up_wdata        ;
wire                    up_wreq         ;

//register defination
wire    [31:0]          sdr_info        ;
wire                    mtime_start     ;
wire    [ 1:0]          pps_select      ;
wire    [31:0]          clock_1pps      ;
wire    [11:0]          phase           ;
wire    [ 3:0]          rf_mode         ;

reg                     user_sysref_adc ;
reg                     pl_sysref_r     ;


wire [12*16-1:0]        s20_axis_tdata;
wire                    s20_axis_tready;
wire                    s20_axis_tvalid;
wire [12*16-1:0]        s22_axis_tdata;
wire                    s22_axis_tready;
wire                    s22_axis_tvalid;

// Local Parameters derived from user selection
wire [1:0]                dac_tvalid=2'b11;
wire [1:0]                dac_tready;
reg  [12*16-1:0]          dac_tdata;
//tx
assign s20_axis_tdata =  dac_tdata;
// Only Tx4 / JA5 / DAC Tile2 Block0 is driven by the business transmitter.
assign s22_axis_tdata =  192'd0;

assign s20_axis_tvalid = dac_tvalid[0];
assign s22_axis_tvalid = dac_tvalid[1];

assign dac_tready[0] = s20_axis_tready;
assign dac_tready[1] = s22_axis_tready;




//register defination
assign sdr_info = {16'h1000,16'd840};

assign m00_axis_tready = 1'b1;
assign m02_axis_tready = 1'b1;

assign DAC_IQ_RX =  m00_axis_tdata;

assign user_io7 = gpio_tri_o[4];
assign user_io6 = gpio_tri_o[4];
assign user_io5 = gpio_tri_o[4];
assign user_io4 = gpio_tri_o[4];
assign gpio_tri_i[15:7] = 9'd0;
assign trig_out = 1'bz;

// PS multi-bit mode is decoded only in its own register clock domain.
// Feedback reset has no connection to VIO manual reset or any business P/M.
always @(posedge fclk_100m or negedge fclk_reset0) begin
    if (!fclk_reset0) run_enable_ps <= 1'b0;
    else run_enable_ps <= mtime_start && rf_mode==4'd1;
end
assign feedback_arst_n = fclk_reset0 && locked && run_enable_ps;
Reset_Sync u_tx_run_reset (.clk(data_clk), .arst_n(feedback_arst_n), .rst_n(tx_run));

tx_feedback_receive #(.DEBUG_ILA(1)) u_tx_feedback_receive (
    .clk_adc(data_clk2), .clk_fast(data_clk), .clk_slow(data_clk1),
    .arst_n(feedback_arst_n),
    .adc_i(m10_axis_tdata), .adc_q(m11_axis_tdata),
    .adc_i_v(m10_axis_tvalid), .adc_q_v(m11_axis_tvalid),
    .packet_v(feedback_packet_v), .packet24(feedback_packet),
    .packet_cfo(), .packet_pn(), .packet_phase(),
    .status(feedback_status), .received_count(feedback_received_count)
);
ila_tx_dac u_ila_tx_dac (.clk(data_clk), .probe0(dac_tdata), .probe1(dac_metadata));
//*************************   Multi-tile sync logic   ***********************//
IBUFDS pl_clk_i (
    .I          (pl_clk_p),
    .IB         (pl_clk_n),
    .O          (pl_clk)
);

IBUFDS pl_sysref_i (
    .I          (pl_sysref_p),
    .IB         (pl_sysref_n),
    .O          (pl_sysref)
);

always @(posedge pl_clk) begin
    pl_sysref_r <= pl_sysref;
end

always @(posedge pl_clk) begin
    user_sysref_adc <= pl_sysref_r;
end

//**************************   Reference Module   **************************//

fmc_THz_test_top u_fmc_THz_test_top(

    //10G eth clk
    // .gty_refclk0p_i (gty_refclk0p_i),
    // .gty_refclk0n_i (gty_refclk0n_i),

    .clk1           (data_clk       ),    //409.6       
    .clk2           (data_clk1      ),    //204.8
    .locked         (locked         ),            
    .fclk           (fclk_100m      ),    //input                   
    .tx_run         (tx_run         ),
    .dac_ready      (s20_axis_tready),
    .feedback_packet_v(feedback_packet_v),
    .feedback_packet(feedback_packet),
    .feedback_status(feedback_status),
    .feedback_received_count(feedback_received_count),
    .dac_metadata   (dac_metadata),
    .DAC_IQ         (DAC_IQ         ),    //output [12*16-1 :0]      
    .DAC_IQ_RX      (DAC_IQ_RX      ),    //input       
    //10GE
    .gt_refclk_p    (gt_refclk_p    ),    //input   
    .gt_refclk_n    (gt_refclk_n    ),    //input   
    .gt_rxp_in_0    (gt_rxp_in_0    ),    //input   
    .gt_rxn_in_0    (gt_rxn_in_0    ),    //input   
    .gt_txp_out_0   (gt_txp_out_0   ),    //output  
    .gt_txn_out_0   (gt_txn_out_0   ),    //output  
    //start_points
    .gt_rxp_in_1    (gt_rxp_in_1    ),    //input   wire            gt_rxp_in_1     ,
    .gt_rxn_in_1    (gt_rxn_in_1    ),    //input   wire            gt_rxn_in_1     ,
    .gt_txp_out_1   (gt_txp_out_1   ),    //output  wire            gt_txp_out_1    ,
    .gt_txn_out_1   (gt_txn_out_1   )     //output  wire            gt_txn_out_1     
);

system system_i(
    .GPIO0_tri_i        (gpio_tri_i),
    .GPIO0_tri_o        (gpio_tri_o),
    .GPIO0_tri_t        (gpio_tri_t),
    .adc1_clk_clk_n     (adc1_clk_n),
    .adc1_clk_clk_p     (adc1_clk_p),

    .dac2_clk_clk_n     (dac2_clk_n),
    .dac2_clk_clk_p     (dac2_clk_p),

    .data_clk           (data_clk),
    .data_clk1          (data_clk1),
    .data_clk2          (data_clk2),
    .locked             (locked),
    .pl_resetn0         (fclk_reset0),
    .m00_axis_tdata     (m00_axis_tdata ), 
    .m00_axis_tready    (m00_axis_tready),
    .m00_axis_tvalid    (m00_axis_tvalid),
    .m02_axis_tdata     (m02_axis_tdata ), 
    .m02_axis_tready    (m02_axis_tready),
    .m02_axis_tvalid    (m02_axis_tvalid),
    .m10_axis_tdata     (m10_axis_tdata),
    .m10_axis_tready    (1'b1),
    .m10_axis_tvalid    (m10_axis_tvalid),
    .m11_axis_tdata     (m11_axis_tdata),
    .m11_axis_tready    (1'b1),
    .m11_axis_tvalid    (m11_axis_tvalid),
    .m12_axis_tdata     (m12_axis_tdata),
    .m12_axis_tready    (1'b1),
    .m12_axis_tvalid    (m12_axis_tvalid),
    .m13_axis_tdata     (m13_axis_tdata),
    .m13_axis_tready    (1'b1),
    .m13_axis_tvalid    (m13_axis_tvalid),

    .s20_axis_tdata     (s20_axis_tdata),
    .s20_axis_tready    (s20_axis_tready),
    .s20_axis_tvalid    (s20_axis_tvalid),
    .s22_axis_tdata     (s22_axis_tdata),
    .s22_axis_tready    (s22_axis_tready),
    .s22_axis_tvalid    (s22_axis_tvalid),
    .s30_axis_tdata     (192'd0),
    .s30_axis_tready    (s30_axis_tready),
    .s30_axis_tvalid    (1'b1),
    .s32_axis_tdata     (192'd0),
    .s32_axis_tready    (s32_axis_tready),
    .s32_axis_tvalid    (1'b1),

    .sysref_in_diff_n   (sysref_in_n),
    .sysref_in_diff_p   (sysref_in_p),
    .user_sysref_adc_0  (user_sysref_adc),
    .fclk_100m          (fclk_100m),
    .up_rack            (up_rack),
    .up_raddr           (up_raddr),
    .up_rdata           (up_rdata),
    .up_rreq            (up_rreq),
    .up_wack            (up_wack),
    .up_waddr           (up_waddr),
    .up_wdata           (up_wdata),
    .up_wreq            (up_wreq),
    .vin0_01_v_n        (vin0_01_n),
    .vin0_01_v_p        (vin0_01_p),
    .vin0_23_v_n        (vin0_23_n),
    .vin0_23_v_p        (vin0_23_p),
    .vin1_01_v_n        (vin1_01_n),
    .vin1_01_v_p        (vin1_01_p),
    .vin1_23_v_n        (vin1_23_n),
    .vin1_23_v_p        (vin1_23_p),

    .vout20_v_n         (vout20_n),
    .vout20_v_p         (vout20_p),
    .vout22_v_n         (vout22_n),
    .vout22_v_p         (vout22_p),
    .vout30_v_n         (vout30_n),
    .vout30_v_p         (vout30_p),
    .vout32_v_n         (vout32_n),
    .vout32_v_p         (vout32_p)
);

//gpio
ad_iobuf #(.DATA_WIDTH(7)) i_iobuf (
.dio_t (gpio_tri_t[6:0]),
.dio_i (gpio_tri_o[6:0]),
.dio_o (gpio_tri_i[6:0]),
.dio_p ({
user_io       ,//6:3
fddtdd_sw     ,//2
trx_sw_ps     ,//1
lmk_sync       //0
}));


user_control user_control(
.axi_gp_clk       (fclk_100m      ),//global
.axi_rst          (~fclk_reset0    ),
.up_rack          (up_rack),
.up_raddr         (up_raddr),
.up_rdata         (up_rdata),
.up_rreq          (up_rreq),
.up_wack          (up_wack),
.up_waddr         (up_waddr),
.up_wdata         (up_wdata),
.up_wreq          (up_wreq),
.mtime_start      (mtime_start    ),//register out
.pps_select       (pps_select     ),
.clock_1pps       (clock_1pps     ),
.phase            (phase          ),
.rf_mode          (rf_mode        ),
.config_done      (config_done    ),
.adc_freeze       (adc_freeze     ),
.adc_clear_ov     (adc_clear_ov   ),
.sdr_info         (sdr_info       ),//register in
.fw_ver           (32'h20261022   ),
.adc_over_volt    (8'd0           ),
.dev_clk_locked   (locked         )
);


always @ (posedge data_clk)
if(!tx_run)
  begin
    dac_tdata <= 192'd0;
  end
else
  begin
    
    dac_tdata <= DAC_IQ;
  end


//led
assign led[0]=mtime_start;
assign led[1]=& dac_tready;
assign led[2]=config_done;
assign led[3]=1'b1;




//chipscope
// ila_adc u_ila_adc (
// 	.clk(data_clk), // input wire clk
// 	.probe0(DAC_IQ_RX) // input wire [191:0] probe0
// );

endmodule
`default_nettype wire
