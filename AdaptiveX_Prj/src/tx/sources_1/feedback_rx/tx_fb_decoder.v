`timescale 1ns / 1ps
`default_nettype none
// Coaxial-feedback receiver, one F13 complex symbol per ten 409.6-MHz clocks.
// The 40.96-MHz RRC domain crosses whole symbols through an async FIFO.
// Blind ZC64 correlation, exactly thirteen PN fractional-delay templates,
// repeated-training CFO estimation, and 64-point frequency-domain ZF.
// Two CP-stripped training blocks estimate the channel. The data window is
// ten symbols early, matching MATLAB remain_length=10; the IFFT output is
// circularly advanced ten positions before removing the two pilots.
// A nonzero PN delay requests a relative sampling-phase correction and drops
// that capture. Repeated subsequent frames are acquired without TX positions.
module tx_fb_decoder #(
    parameter integer DEBUG_ILA = 0,
    parameter HEADER_MEM = "fb_rx_header_q13.mem",
    parameter PN_MEM = "fb_rx_pn12_q13.mem",
    parameter COS_MEM = "fb_rx_nco_cos_q14.mem",
    parameter SIN_MEM = "fb_rx_nco_sin_q14.mem"
)(
    input wire clk, input wire rst_n,
    input wire sym_v,
    input wire signed [15:0] sym_i, input wire signed [15:0] sym_q,
    output reg timing_adjust_v, output reg [6:0] timing_adjust,
    output reg packet_v, output reg [23:0] packet24,
    output reg const_v, output reg signed [15:0] const_i,
    output reg signed [15:0] const_q, output reg [5:0] const_index,
    output reg sync_locked, output reg [3:0] pn_index,
    output reg signed [31:0] cfo_phase_debug,
    output reg bad_crc,
    output reg [31:0] packet_count, output reg [31:0] crc_error_count,
    output reg [31:0] timing_reacquire_count
);
    (* rom_style = "distributed" *) reg [31:0] header [0:243];
    (* rom_style = "distributed" *) reg [31:0] pn_rom [0:207];
    (* rom_style = "distributed" *) reg signed [15:0] cos_rom [0:511];
    (* rom_style = "distributed" *) reg signed [15:0] sin_rom [0:511];
    reg [9:0] wr_ptr;
    reg [31:0] sample_count;
    reg [6:0] acquired_samples;
    reg [9:0] base_addr, pn_addr, best_pn_addr;
    reg [31:0] base_stamp;
    // Signed elapsed-time comparisons remain valid across the 32-bit sample
    // counter rollover (about 105 seconds at the continuous symbol rate).
    // Separate the modulo32 subtract from threshold/state enables. A stamp
    // rewrite invalidates the age produced with the previous stamp, until a
    // full clock edge has sampled the replacement. Keep signed wrap semantics.
    reg signed [31:0] frame_age;
    reg frame_age_valid;
    (* max_fanout=64 *) reg [5:0] state;
    localparam S_SEARCH=0, S_PN_WAIT=1, S_PN_LOC=2, S_PN_LOC_SCORE=3,
        S_PN_REF=4, S_PN_REF_SCORE=5, S_PN_END=6, S_FRAME_WAIT=7,
        S_CFO=8, S_CFO_INIT=9, S_CORDIC=10, S_CFO_END=11,
        S_FDE_START=12, S_FDE_INIT=13, S_FDE_ROT=14, S_FDE_PUSH=15,
        S_FDE_WAIT=16, S_DATA_INIT=17, S_DATA_OUT=18,
        S_CHECK=20, S_HOLDOFF=21, S_CORR_WAIT=22,
        S_PN_LOC_METRIC=23,S_PN_REF_METRIC=24,S_CORDIC_SHIFT=25,
        S_CFO_DIVIDE=26,S_FDE_PHASE_BUILD=27,S_DATA_DRAIN=28,
        S_PN_METRIC_ISSUE=29;

    // Eight issue groups per symbol, with an independently pipelined balanced
    // product/add/metric path. A 64-symbol shift window avoids eight asynchronous
    // reads from the 1024-symbol frame ring. Exact full-width sums, thresholds
    // and the local-maximum rule are unchanged; base/time tags follow the math.
    reg signed [15:0] zc_window_i [0:63];
    reg signed [15:0] zc_window_q [0:63];
    reg corr_busy;
    reg [3:0] corr_group;
    reg [9:0] corr_base, prev_base;
    reg [31:0] corr_stamp, prev_stamp;
    reg signed [40:0] corr_r,corr_j;
    reg [40:0] corr_energy;
    reg [5:0] zc_pipe_v;
    reg [2:0] zc_group [0:5];
    reg [9:0] zc_base [0:5];
    reg [31:0] zc_stamp [0:5];
    reg signed [15:0] zc_si [0:7],zc_sq [0:7],zc_ri [0:7],zc_rq [0:7];
    reg signed [31:0] zc_ii [0:7],zc_qq [0:7],zc_qi [0:7],zc_iq [0:7];
    reg signed [31:0] zc_ei [0:7],zc_eq [0:7];
    reg signed [32:0] zc_pr [0:7],zc_pj [0:7];
    reg [32:0] zc_pe [0:7];
    reg signed [33:0] zc_pair_r [0:3],zc_pair_j [0:3];
    reg [33:0] zc_pair_e [0:3];
    reg signed [34:0] zc_quad_r [0:1],zc_quad_j [0:1];
    reg [34:0] zc_quad_e [0:1];
    reg signed [35:0] zc_chunk_r,zc_chunk_j;
    reg [35:0] zc_chunk_e;
    reg signed [40:0] zc_final_r,zc_final_j;
    reg [40:0] zc_final_energy;
    reg [9:0] zc_final_base;
    reg [31:0] zc_final_stamp;
    reg zc_final_v;
    wire zc_metric_v;
    wire [83:0] zc_metric_full;
    wire [53:0] zc_metric=zc_metric_full[53:0];
    reg [40:0] zc_energy_tag[0:5];
    reg [9:0] zc_base_tag[0:5];
    reg [31:0] zc_stamp_tag[0:5];
    wire [40:0] zc_metric_energy=zc_energy_tag[5];
    wire [9:0] zc_metric_base=zc_base_tag[5];
    wire [31:0] zc_metric_stamp=zc_stamp_tag[5];
    wire signed [26:0] zc_scaled_r=zc_final_r>>>13;
    wire signed [26:0] zc_scaled_j=zc_final_j>>>13;
    tx_fb_metric41 u_zc_metric(.clk(clk),.rst_n(rst_n),.in_v(zc_final_v),
        .in_i({{14{zc_scaled_r[26]}},zc_scaled_r}),
        .in_q({{14{zc_scaled_j[26]}},zc_scaled_j}),
        .out_v(zc_metric_v),.metric(zc_metric_full));
    wire zc_pass=zc_metric_energy>41'd262144 &&
                 zc_metric>{8'd0,zc_metric_energy,5'd0};
    reg [53:0] prev_metric,older_metric;
    reg prev_pass;
    integer zc_lane,zc_stage,zc_window_index;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            zc_pipe_v<=0;zc_final_v<=0;
            corr_r<=0;corr_j<=0;corr_energy<=0;
            zc_final_r<=0;zc_final_j<=0;zc_final_energy<=0;
            zc_final_base<=0;zc_final_stamp<=0;
            for(zc_stage=0;zc_stage<6;zc_stage=zc_stage+1) begin
                zc_group[zc_stage]<=0;zc_base[zc_stage]<=0;zc_stamp[zc_stage]<=0;
                zc_energy_tag[zc_stage]<=0;zc_base_tag[zc_stage]<=0;zc_stamp_tag[zc_stage]<=0;
            end
        end else begin
            if(sym_v) begin
                for(zc_window_index=0;zc_window_index<63;zc_window_index=zc_window_index+1) begin
                    zc_window_i[zc_window_index]<=zc_window_i[zc_window_index+1];
                    zc_window_q[zc_window_index]<=zc_window_q[zc_window_index+1];
                end
                zc_window_i[63]<=sym_i;zc_window_q[63]<=sym_q;
            end
            zc_pipe_v<={zc_pipe_v[4:0],corr_busy};
            zc_group[0]<=corr_group[2:0];zc_base[0]<=corr_base;zc_stamp[0]<=corr_stamp;
            for(zc_stage=1;zc_stage<6;zc_stage=zc_stage+1) begin
                zc_group[zc_stage]<=zc_group[zc_stage-1];
                zc_base[zc_stage]<=zc_base[zc_stage-1];
                zc_stamp[zc_stage]<=zc_stamp[zc_stage-1];
            end
            if(zc_pipe_v[0]) for(zc_lane=0;zc_lane<8;zc_lane=zc_lane+1) begin
                zc_ii[zc_lane]<=zc_si[zc_lane]*zc_ri[zc_lane];
                zc_qq[zc_lane]<=zc_sq[zc_lane]*zc_rq[zc_lane];
                zc_qi[zc_lane]<=zc_sq[zc_lane]*zc_ri[zc_lane];
                zc_iq[zc_lane]<=zc_si[zc_lane]*zc_rq[zc_lane];
                zc_ei[zc_lane]<=zc_si[zc_lane]*zc_si[zc_lane];
                zc_eq[zc_lane]<=zc_sq[zc_lane]*zc_sq[zc_lane];
            end
            if(zc_pipe_v[1]) for(zc_lane=0;zc_lane<8;zc_lane=zc_lane+1) begin
                zc_pr[zc_lane]<={zc_ii[zc_lane][31],zc_ii[zc_lane]}+{zc_qq[zc_lane][31],zc_qq[zc_lane]};
                zc_pj[zc_lane]<={zc_qi[zc_lane][31],zc_qi[zc_lane]}-{zc_iq[zc_lane][31],zc_iq[zc_lane]};
                zc_pe[zc_lane]<={1'b0,zc_ei[zc_lane]}+{1'b0,zc_eq[zc_lane]};
            end
            if(zc_pipe_v[2]) for(zc_lane=0;zc_lane<4;zc_lane=zc_lane+1) begin
                zc_pair_r[zc_lane]<=$signed(zc_pr[2*zc_lane])+$signed(zc_pr[2*zc_lane+1]);
                zc_pair_j[zc_lane]<=$signed(zc_pj[2*zc_lane])+$signed(zc_pj[2*zc_lane+1]);
                zc_pair_e[zc_lane]<={1'b0,zc_pe[2*zc_lane]}+{1'b0,zc_pe[2*zc_lane+1]};
            end
            if(zc_pipe_v[3]) for(zc_lane=0;zc_lane<2;zc_lane=zc_lane+1) begin
                zc_quad_r[zc_lane]<=$signed(zc_pair_r[2*zc_lane])+$signed(zc_pair_r[2*zc_lane+1]);
                zc_quad_j[zc_lane]<=$signed(zc_pair_j[2*zc_lane])+$signed(zc_pair_j[2*zc_lane+1]);
                zc_quad_e[zc_lane]<={1'b0,zc_pair_e[2*zc_lane]}+{1'b0,zc_pair_e[2*zc_lane+1]};
            end
            if(zc_pipe_v[4]) begin
                zc_chunk_r<=$signed(zc_quad_r[0])+$signed(zc_quad_r[1]);
                zc_chunk_j<=$signed(zc_quad_j[0])+$signed(zc_quad_j[1]);
                zc_chunk_e<={1'b0,zc_quad_e[0]}+{1'b0,zc_quad_e[1]};
            end
            zc_final_v<=zc_pipe_v[5] && zc_group[5]==7;
            if(zc_pipe_v[5]) begin
                if(zc_group[5]==0) begin
                    corr_r<=zc_chunk_r;corr_j<=zc_chunk_j;corr_energy<=zc_chunk_e;
                end else begin
                    corr_r<=corr_r+zc_chunk_r;corr_j<=corr_j+zc_chunk_j;
                    corr_energy<=corr_energy+zc_chunk_e;
                end
                if(zc_group[5]==7) begin
                    zc_final_r<=corr_r+zc_chunk_r;zc_final_j<=corr_j+zc_chunk_j;
                    zc_final_energy<=corr_energy+zc_chunk_e;
                    zc_final_base<=zc_base[5];zc_final_stamp<=zc_stamp[5];
                end
            end
            if(zc_final_v) begin
                zc_energy_tag[0]<=zc_final_energy;zc_base_tag[0]<=zc_final_base;zc_stamp_tag[0]<=zc_final_stamp;
            end
            for(zc_stage=1;zc_stage<6;zc_stage=zc_stage+1) begin
                zc_energy_tag[zc_stage]<=zc_energy_tag[zc_stage-1];
                zc_base_tag[zc_stage]<=zc_base_tag[zc_stage-1];
                zc_stamp_tag[zc_stage]<=zc_stamp_tag[zc_stage-1];
            end
        end
    end

    genvar zc_g;
    generate for(zc_g=0;zc_g<8;zc_g=zc_g+1) begin: zc_issue_lane
        localparam [2:0] LANE=zc_g;
        wire [5:0] tap_address={corr_group[2:0],LANE};
        always @(posedge clk) if(corr_busy) begin
            zc_si[zc_g]<=zc_window_i[tap_address];zc_sq[zc_g]<=zc_window_q[tap_address];
            zc_ri[zc_g]<=$signed(header[tap_address][15:0]);
            zc_rq[zc_g]<=$signed(header[tap_address][31:16]);
        end
    end endgenerate

    reg [6:0] n;
    reg [3:0] candidate;
    reg [2:0] location;
    reg signed [40:0] acc_r, acc_j;
    reg [83:0] score_best;
    reg [3:0] best_template;
    // Local PN input sampling separates the global accumulation registers
    // from the abs41 -> DSP operand route. The ZC metric is unchanged.
    reg signed [40:0] pn_input_i,pn_input_q;
    reg pn_metric_is_ref;
    wire [83:0] acc_metric;
    wire acc_metric_v;
    tx_fb_metric41 u_pn_metric(.clk(clk),.rst_n(rst_n),
        .in_v(state==S_PN_METRIC_ISSUE),
        .in_i(pn_input_i),.in_q(pn_input_q),.out_v(acc_metric_v),.metric(acc_metric));
    reg [9:0] a_addr, b_addr;
    reg signed [15:0] a_i,a_q,b_i,b_q;
    reg signed [41:0] cord_x,cord_y,cord_shift_x,cord_shift_y;
    reg signed [31:0] cord_angle;
    reg [4:0] cord_iter;
    reg signed [31:0] phase_step;
    reg [31:0] divide_numerator,divide_quotient;
    reg [6:0] divide_remainder;
    reg divide_negative;
    reg [5:0] divide_count;
    wire [7:0] divide_trial={divide_remainder,divide_numerator[31]};
    wire divide_bit=divide_trial>=8'd82;
    wire [31:0] divide_next_quotient={divide_quotient[30:0],divide_bit};
    reg [31:0] phase;
    reg [31:0] phase_sum0,phase_sum1a,phase_sum1b,phase_sum2;
    reg [31:0] phase_base0,phase_base1,phase_base2;
    reg [1:0] fde_block;
    wire fde_busy,fde_done,fde_fault,fde_out_v;
    wire [5:0] fde_out_index;
    wire signed [15:0] fde_out_i,fde_out_q;
    (* ram_style = "distributed" *) reg signed [15:0] fde_data_i [0:63];
    (* ram_style = "distributed" *) reg signed [15:0] fde_data_q [0:63];
    // Dedicated local read address avoids a global n -> (+12) -> 64-way
    // FDE-RAM -> constellation-register path. Data/index/valid share one stage.
    reg [5:0] data_read_addr;
    reg data_read_v;
    reg [5:0] data_read_index;
    reg signed [15:0] data_read_i,data_read_q;
    always @(posedge clk) if(state==S_DATA_OUT) begin
        data_read_i<=fde_data_i[data_read_addr];
        data_read_q<=fde_data_q[data_read_addr];
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin data_read_v<=0;data_read_index<=0;end
        else begin
            data_read_v<=state==S_DATA_OUT;
            if(state==S_DATA_OUT)data_read_index<=n[5:0];
        end
    end
    tx_fb_fde64 u_fde64(
        .clk(clk),.rst_n(rst_n),.start(state==S_FDE_START),
        .in_v(mac_rot_v),.in_block(mac_rot_block),.in_index(mac_rot_index),
        .in_i(mac_rot_i),.in_q(mac_rot_q),.out_v(fde_out_v),
        .out_index(fde_out_index),.out_i(fde_out_i),.out_q(fde_out_q),
        .busy(fde_busy),.done(fde_done),.fault(fde_fault));
    reg [23:0] shift_packet;
    // Packet bits precede the fill in the per-frame PN6144 stream. Retain the
    // actual scrambled QPSK constellation; only hard decisions are descrambled.
    localparam [123:0] SCRAMBLE_PN124 = 124'hFFF8024186B6A821DB8842F7FEC0CA5;
    wire [8:0] nco_addr=phase[31:23];
    function signed [15:0] sat16;
        input signed [47:0] x;
        begin
            if(x>48'sd32767) sat16=16'sd32767;
            else if(x< -48'sd32768) sat16= -16'sd32768;
            else sat16=x[15:0];
        end
    endfunction
    function [7:0] crc8;
        input [15:0] p;
        reg [7:0] c; reg f; integer k;
        begin
            c=0;
            for(k=15;k>=0;k=k-1) begin
                f=c[7]^p[k]; c={c[6:0],1'b0};
                if(f)c=c^8'h07;
            end
            crc8=c;
        end
    endfunction
    function [6:0] delay_value;
        input [3:0] c;
        begin
            case(c)
                // Units: one ADC complex sample at 12 samples/symbol.
                // This is T/12, the same resolution as ten old R120 points.
                // The two half-symbol windows map to the SAME six samples.
                0:delay_value=0; 1:delay_value=11; 2:delay_value=10;
                3:delay_value=9; 4:delay_value=8; 5:delay_value=7;
                6,7:delay_value=6; 8:delay_value=5; 9:delay_value=4;
                10:delay_value=3; 11:delay_value=2; default:delay_value=1;
            endcase
        end
    endfunction
    function signed [31:0] atan_phase;
        input [4:0] k;
        begin
            case(k)
                0:atan_phase=32'sd536870912;
                1:atan_phase=32'sd316933406;
                2:atan_phase=32'sd167458907;
                3:atan_phase=32'sd85004756;
                4:atan_phase=32'sd42667331;
                5:atan_phase=32'sd21354465;
                6:atan_phase=32'sd10679838;
                7:atan_phase=32'sd5340245;
                8:atan_phase=32'sd2670163;
                9:atan_phase=32'sd1335087;
                10:atan_phase=32'sd667544;
                11:atan_phase=32'sd333772;
                12:atan_phase=32'sd166886;
                13:atan_phase=32'sd83443;
                14:atan_phase=32'sd41722;
                default:atan_phase=32'sd20861;
            endcase
        end
    endfunction
    // PN correlation, repeated-training CFO and FDE derotation share a
    // six-stage tagged complex MAC. Address arithmetic, 4x256 registered
    // ring-bank reads, bank/reference selection, DSP products, complex sums,
    // and accumulation/saturation are distinct clock boundaries. Rotation
    // samples can issue every other clock without waiting for this latency.
    wire mac_issue=(state==S_PN_LOC)||(state==S_PN_REF)||
                   (state==S_CFO)||(state==S_FDE_ROT);
    wire [1:0] mac_issue_kind=state==S_PN_LOC?2'd0:
        state==S_PN_REF?2'd1:state==S_CFO?2'd2:2'd3;
    reg [4:0] mac_v;
    reg [1:0] mac_kind[0:4],mac_block[0:4];
    reg [5:0] mac_index[0:4];
    reg mac_first[0:4],mac_last[0:4];
    reg [9:0] mac_addr_a,mac_addr_b;
    reg [1:0] mac_bank_a,mac_bank_b;
    reg signed [15:0] mac_ref0_i,mac_ref0_q,mac_ref1_i,mac_ref1_q;
    wire signed [15:0] mac_ab_i[0:3],mac_ab_q[0:3];
    wire signed [15:0] mac_bb_i[0:3],mac_bb_q[0:3];
    reg signed [15:0] mac_a_i,mac_a_q,mac_b_i,mac_b_q;
    reg signed [31:0] mac_ii,mac_qq,mac_qi,mac_iq;
    reg signed [32:0] mac_real,mac_imag;
    reg mac_rot_v;
    reg [1:0] mac_rot_block;
    reg [5:0] mac_rot_index;
    reg signed [15:0] mac_rot_i,mac_rot_q;
    integer mac_stage;
    genvar mac_g;
    generate for(mac_g=0;mac_g<4;mac_g=mac_g+1) begin: frame_read_bank
        localparam [1:0] BANK=mac_g;
        (* ram_style="distributed" *) reg signed [15:0] ring_i[0:255];
        (* ram_style="distributed" *) reg signed [15:0] ring_q[0:255];
        reg signed [15:0] ai,aq,bi,bq;
        // Explicit write-bank decoding permits distributed dual-read RAM
        // inference; a monolithic asynchronous-reset process inferred 32768 FF.
        always @(posedge clk) begin
            if(rst_n && sym_v && wr_ptr[9:8]==BANK) begin
                ring_i[wr_ptr[7:0]]<=sym_i;ring_q[wr_ptr[7:0]]<=sym_q;
            end
            if(mac_v[0]) begin
                ai<=ring_i[mac_addr_a[7:0]];aq<=ring_q[mac_addr_a[7:0]];
                bi<=ring_i[mac_addr_b[7:0]];bq<=ring_q[mac_addr_b[7:0]];
            end
        end
        assign mac_ab_i[mac_g]=ai;assign mac_ab_q[mac_g]=aq;
        assign mac_bb_i[mac_g]=bi;assign mac_bb_q[mac_g]=bq;
    end endgenerate
    always @* begin
        a_addr=base_addr;b_addr=base_addr;b_i=0;b_q=0;
        if(state==S_PN_LOC) begin
            a_addr=pn_addr+location+n;
            b_i=$signed(header[64+n][15:0]);b_q=$signed(header[64+n][31:16]);
        end else if(state==S_PN_REF) begin
            a_addr=best_pn_addr+n;
            b_i=$signed(pn_rom[{candidate,n[3:0]}][15:0]);
            b_q=$signed(pn_rom[{candidate,n[3:0]}][31:16]);
        end else if(state==S_CFO) begin
            a_addr=base_addr+180+n;b_addr=base_addr+98+n;
        end else if(state==S_FDE_ROT) begin
            case(fde_block)
                0:a_addr=base_addr+98+n;
                1:a_addr=base_addr+180+n;
                default:a_addr=base_addr+252+n;
            endcase
            b_i=cos_rom[nco_addr];b_q=sin_rom[nco_addr];
        end
        a_i=0;a_q=0;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            mac_v<=0;mac_addr_a<=0;mac_addr_b<=0;mac_bank_a<=0;mac_bank_b<=0;
            mac_ref0_i<=0;mac_ref0_q<=0;mac_ref1_i<=0;mac_ref1_q<=0;
            mac_rot_v<=0;mac_rot_i<=0;mac_rot_q<=0;mac_rot_index<=0;mac_rot_block<=0;
            for(mac_stage=0;mac_stage<5;mac_stage=mac_stage+1) begin
                mac_kind[mac_stage]<=0;mac_block[mac_stage]<=0;mac_index[mac_stage]<=0;
                mac_first[mac_stage]<=0;mac_last[mac_stage]<=0;
            end
        end else begin
            mac_v<={mac_v[3:0],mac_issue};
            mac_kind[0]<=mac_issue_kind;mac_block[0]<=fde_block;mac_index[0]<=n[5:0];
            mac_first[0]<=n==0;
            mac_last[0]<=mac_issue_kind<2 ? n==15:n==63;
            for(mac_stage=1;mac_stage<5;mac_stage=mac_stage+1) begin
                mac_kind[mac_stage]<=mac_kind[mac_stage-1];mac_block[mac_stage]<=mac_block[mac_stage-1];
                mac_index[mac_stage]<=mac_index[mac_stage-1];
                mac_first[mac_stage]<=mac_first[mac_stage-1];mac_last[mac_stage]<=mac_last[mac_stage-1];
            end
            if(mac_issue) begin
                mac_addr_a<=a_addr;mac_addr_b<=b_addr;
                mac_ref0_i<=b_i;mac_ref0_q<=b_q;
            end
            if(mac_v[0]) begin
                mac_bank_a<=mac_addr_a[9:8];mac_bank_b<=mac_addr_b[9:8];
                mac_ref1_i<=mac_ref0_i;mac_ref1_q<=mac_ref0_q;
            end
            if(mac_v[1]) begin
                mac_a_i<=mac_ab_i[mac_bank_a];mac_a_q<=mac_ab_q[mac_bank_a];
                if(mac_kind[1]==2) begin mac_b_i<=mac_bb_i[mac_bank_b];mac_b_q<=mac_bb_q[mac_bank_b];end
                else begin mac_b_i<=mac_ref1_i;mac_b_q<=mac_ref1_q;end
            end
            if(mac_v[2]) begin
                mac_ii<=mac_a_i*mac_b_i;mac_qq<=mac_a_q*mac_b_q;
                mac_qi<=mac_a_q*mac_b_i;mac_iq<=mac_a_i*mac_b_q;
            end
            if(mac_v[3]) begin
                mac_real<={mac_ii[31],mac_ii}+{mac_qq[31],mac_qq};
                mac_imag<={mac_qi[31],mac_qi}-{mac_iq[31],mac_iq};
            end
            mac_rot_v<=mac_v[4] && mac_kind[4]==3;
            if(mac_v[4] && mac_kind[4]==3) begin
                mac_rot_i<=sat16(mac_real>>>14);mac_rot_q<=sat16(mac_imag>>>14);
                mac_rot_block<=mac_block[4];mac_rot_index<=mac_index[4];
            end
        end
    end

    initial begin
        $readmemh(HEADER_MEM,header);$readmemh(PN_MEM,pn_rom);
        $readmemh(COS_MEM,cos_rom);$readmemh(SIN_MEM,sin_rom);
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wr_ptr<=0;sample_count<=0;acquired_samples<=0;base_addr<=0;base_stamp<=0;
            frame_age<=0;frame_age_valid<=0;
            state<=S_SEARCH;corr_busy<=0;corr_group<=0;corr_base<=0;
            corr_stamp<=0;
            prev_base<=0;prev_stamp<=0;prev_metric<=0;older_metric<=0;prev_pass<=0;
            timing_adjust_v<=0;timing_adjust<=0;packet_v<=0;packet24<=0;
            const_v<=0;const_i<=0;const_q<=0;const_index<=0;sync_locked<=0;
            pn_index<=0;cfo_phase_debug<=0;bad_crc<=0;packet_count<=0;
            crc_error_count<=0;timing_reacquire_count<=0;
            pn_addr<=0;best_pn_addr<=0;n<=0;candidate<=0;location<=0;
            acc_r<=0;acc_j<=0;score_best<=0;best_template<=0;
            pn_input_i<=0;pn_input_q<=0;pn_metric_is_ref<=0;data_read_addr<=0;
            cord_x<=0;cord_y<=0;cord_shift_x<=0;cord_shift_y<=0;cord_angle<=0;cord_iter<=0;phase_step<=0;
            divide_numerator<=0;divide_quotient<=0;divide_remainder<=0;divide_negative<=0;divide_count<=0;
            phase<=0;phase_sum0<=0;phase_sum1a<=0;phase_sum1b<=0;phase_sum2<=0;
            phase_base0<=0;phase_base1<=0;phase_base2<=0;fde_block<=0;shift_packet<=0;
        end else begin
            timing_adjust_v<=0;packet_v<=0;const_v<=0;bad_crc<=0;
            frame_age<=sample_count-base_stamp;
            frame_age_valid<=1;
            if(data_read_v) begin
                const_v<=1;const_index<=data_read_index;
                const_i<=data_read_i;const_q<=data_read_q;
                if(data_read_index<12)shift_packet<={shift_packet[21:0],
                    data_read_i[15]^SCRAMBLE_PN124[123-2*data_read_index],
                    data_read_q[15]^SCRAMBLE_PN124[122-2*data_read_index]};
                if(data_read_index==61)state<=S_CHECK;
            end
            if(fde_out_v) begin
                fde_data_i[fde_out_index]<=fde_out_i;
                fde_data_q[fde_out_index]<=fde_out_q;
            end
            if(sym_v) begin
                wr_ptr<=wr_ptr+1'b1;sample_count<=sample_count+1'b1;
                if(acquired_samples<64)acquired_samples<=acquired_samples+1'b1;
                if(state==S_SEARCH && acquired_samples>=63 && !corr_busy) begin
                    corr_base<=wr_ptr-10'd63;corr_stamp<=sample_count;
                    corr_group<=0;corr_busy<=1;
                end
            end
            if(corr_busy) begin
                if(corr_group==7)corr_busy<=0;
                else corr_group<=corr_group+1'b1;
            end
            if(zc_metric_v) begin
                older_metric<=prev_metric;prev_metric<=zc_metric;
                prev_pass<=zc_pass;prev_base<=zc_metric_base;prev_stamp<=zc_metric_stamp;
                if(state==S_SEARCH && prev_pass && prev_metric>=zc_metric &&
                   prev_metric>older_metric) begin
                    base_addr<=prev_base;base_stamp<=prev_stamp-32'd63;
                    frame_age_valid<=0;
                    pn_addr<=prev_base+10'd62;state<=S_PN_WAIT;
                    sync_locked<=1;prev_pass<=0;
                end
            end
            if(mac_v[4] && mac_kind[4]!=3) begin
                if(mac_first[4]) begin acc_r<=mac_real;acc_j<=mac_imag;end
                else begin acc_r<=acc_r+mac_real;acc_j<=acc_j+mac_imag;end
                if(mac_last[4]) begin
                    case(mac_kind[4])
                        0:state<=S_PN_LOC_METRIC;
                        1:state<=S_PN_REF_METRIC;
                        default:state<=S_CFO_INIT;
                    endcase
                end
            end
            case(state)
                S_PN_WAIT: begin
                    // No PN MAC or score consumer runs in this wait state.
                    // Clear the inactive work registers locally every cycle,
                    // rather than routing the 32-bit age comparison into all
                    // 84 score bits and both 41-bit accumulator enables. The
                    // transition edge and all externally valid data are kept.
                    n<=0;location<=0;acc_r<=0;acc_j<=0;score_best<=0;
                    if(frame_age_valid && frame_age>=32'sd84)state<=S_PN_LOC;
                end
                S_PN_LOC: begin
                    if(n==15)state<=S_CORR_WAIT; else n<=n+1'b1;
                end
                S_PN_LOC_METRIC:begin
                    pn_input_i<=acc_r;pn_input_q<=acc_j;pn_metric_is_ref<=0;
                    state<=S_PN_METRIC_ISSUE;
                end
                S_PN_LOC_SCORE:if(acc_metric_v) begin
                    if(acc_metric>score_best) begin score_best<=acc_metric;best_pn_addr<=pn_addr+location;end
                    n<=0;acc_r<=0;acc_j<=0;
                    if(location==4)begin state<=S_PN_REF;candidate<=0;score_best<=0;end
                    else begin location<=location+1'b1;state<=S_PN_LOC;end
                end
                S_PN_REF: begin
                    if(n==15)state<=S_CORR_WAIT;else n<=n+1'b1;
                end
                S_PN_REF_METRIC:begin
                    pn_input_i<=acc_r;pn_input_q<=acc_j;pn_metric_is_ref<=1;
                    state<=S_PN_METRIC_ISSUE;
                end
                S_PN_METRIC_ISSUE:state<=pn_metric_is_ref ? S_PN_REF_SCORE:S_PN_LOC_SCORE;
                S_PN_REF_SCORE:if(acc_metric_v) begin
                    if(acc_metric>score_best)begin score_best<=acc_metric;best_template<=candidate;end
                    n<=0;acc_r<=0;acc_j<=0;
                    if(candidate==12)state<=S_PN_END;
                    else begin candidate<=candidate+1'b1;state<=S_PN_REF;end
                end
                S_PN_END: begin
                    pn_index<=best_template;
                    base_stamp<=base_stamp+((best_pn_addr-base_addr)&10'h3ff)-64;
                    frame_age_valid<=0;
                    base_addr<=best_pn_addr-10'd64;
                    if(best_template!=0)begin
                        timing_adjust<=delay_value(best_template);timing_adjust_v<=1;
                        timing_reacquire_count<=timing_reacquire_count+1'b1;
                        state<=S_HOLDOFF;sync_locked<=0;
                    end else state<=S_FRAME_WAIT;
                end
                S_FRAME_WAIT: begin
                    // PN scoring has drained before this wait state. Initialize
                    // the inactive CFO work registers locally, keeping the age
                    // comparison off their enables and the transition unchanged.
                    n<=0;acc_r<=0;acc_j<=0;
                    if(frame_age_valid && frame_age>=32'sd326)state<=S_CFO;
                end
                S_CFO: begin
                    if(n==63)state<=S_CORR_WAIT;else n<=n+1'b1;
                end
                S_CFO_INIT: begin
                    if(acc_r<0)begin cord_x<=-acc_r;cord_y<=-acc_j;cord_angle<=32'sh80000000;end
                    else begin cord_x<=acc_r;cord_y<=acc_j;cord_angle<=0;end
                    cord_iter<=0;state<=S_CORDIC_SHIFT;
                end
                S_CORDIC_SHIFT:begin cord_shift_x<=cord_x>>>cord_iter;cord_shift_y<=cord_y>>>cord_iter;state<=S_CORDIC;end
                S_CORDIC: begin
                    if(cord_y>=0)begin
                        cord_x<=cord_x+cord_shift_y;cord_y<=cord_y-cord_shift_x;
                        cord_angle<=cord_angle+atan_phase(cord_iter);
                    end else begin
                        cord_x<=cord_x-cord_shift_y;cord_y<=cord_y+cord_shift_x;
                        cord_angle<=cord_angle-atan_phase(cord_iter);
                    end
                    if(cord_iter==15)state<=S_CFO_END;else begin cord_iter<=cord_iter+1'b1;state<=S_CORDIC_SHIFT;end
                end
                S_CFO_END:begin
                    divide_numerator<=cord_angle[31] ? -cord_angle:cord_angle;
                    divide_negative<=cord_angle[31];divide_quotient<=0;divide_remainder<=0;divide_count<=0;
                    state<=S_CFO_DIVIDE;
                end
                S_CFO_DIVIDE:begin
                    divide_numerator<={divide_numerator[30:0],1'b0};
                    divide_remainder<=divide_bit ? divide_trial-8'd82:divide_trial;
                    divide_quotient<=divide_next_quotient;
                    if(divide_count==31)begin
                        phase_step<=divide_negative ? -$signed(divide_next_quotient):$signed(divide_next_quotient);
                        cfo_phase_debug<=divide_negative ? -$signed(divide_next_quotient):$signed(divide_next_quotient);
                        state<=S_FDE_START;
                    end else divide_count<=divide_count+1'b1;
                end
                S_FDE_START:begin
                    fde_block<=0;
                    phase_sum0<=(phase_step<<6)+(phase_step<<5);
                    phase_sum1a<=(phase_step<<7)+(phase_step<<5);
                    phase_sum1b<=(phase_step<<4)+(phase_step<<2);
                    phase_sum2<=(phase_step<<8)-(phase_step<<2);
                    state<=S_FDE_PHASE_BUILD;
                end
                S_FDE_PHASE_BUILD:begin
                    phase_base0<=phase_sum0+(phase_step<<1);
                    phase_base1<=phase_sum1a+phase_sum1b;phase_base2<=phase_sum2;
                    state<=S_FDE_INIT;
                end
                S_FDE_INIT:begin
                    n<=0;
                    case(fde_block)
                        0:phase<=phase_base0;
                        1:phase<=phase_base1;
                        default:phase<=phase_base2;
                    endcase
                    state<=S_FDE_ROT;
                end
                S_FDE_ROT:state<=S_FDE_PUSH;
                S_FDE_PUSH:begin
                    phase<=phase+phase_step;
                    if(n==63)begin
                        if(fde_block==2)state<=S_FDE_WAIT;
                        else begin fde_block<=fde_block+1'b1;state<=S_FDE_INIT;end
                    end else begin n<=n+1'b1;state<=S_FDE_ROT;end
                end
                S_FDE_WAIT:if(fde_done)begin
                    if(fde_fault)begin bad_crc<=1;crc_error_count<=crc_error_count+1'b1;state<=S_HOLDOFF;end
                    else state<=S_DATA_INIT;
                end
                S_DATA_INIT:begin
                    n<=0;shift_packet<=0;data_read_addr<=6'd12;state<=S_DATA_OUT;
                end
                S_DATA_OUT:begin
                    data_read_addr<=data_read_addr+1'b1;
                    if(n==61)state<=S_DATA_DRAIN;else n<=n+1'b1;
                end
                // Last tagged RAM-read sample commits before CRC checking.
                S_DATA_DRAIN:begin end
                S_CHECK:begin
                    if(crc8(shift_packet[23:8])==shift_packet[7:0] &&
                       shift_packet[23:20]<=8 && shift_packet[19:16]<=8)begin
                        packet24<=shift_packet;packet_v<=1;packet_count<=packet_count+1'b1;
                    end else begin bad_crc<=1;crc_error_count<=crc_error_count+1'b1;end
                    state<=S_HOLDOFF;
                end
                S_HOLDOFF:if(frame_age_valid && frame_age>=32'sd358)begin
                    state<=S_SEARCH;corr_busy<=0;prev_pass<=0;prev_metric<=0;older_metric<=0;sync_locked<=0;
                end
                default:begin end
            endcase
        end
    end

    // Debug-only copies never drive the receiver. Every I/Q transaction,
    // valid and identifying tag is captured on the same clock edge.
    generate if(DEBUG_ILA) begin: gen_debug_ila
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg dbg_sync_metric_v;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [53:0] dbg_sync_metric;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [53:0] dbg_sync_threshold;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [40:0] dbg_sync_energy;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [9:0] dbg_sync_base;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [31:0] dbg_sync_stamp;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg dbg_sync_pass;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg dbg_sync_peak_v;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [53:0] dbg_sync_peak_metric;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [53:0] dbg_sync_peak_threshold;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [9:0] dbg_sync_peak_base;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [31:0] dbg_sync_peak_stamp;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg dbg_sync_sym_v;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [15:0] dbg_sync_sym_i;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [15:0] dbg_sync_sym_q;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg dbg_sync_locked;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [5:0] dbg_sync_state;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg dbg_sync_adjust_v;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [6:0] dbg_sync_adjust;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [3:0] dbg_sync_pn_index;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [53:0] dbg_sync_previous_threshold;
        // The peak predicate is exactly the existing S_SEARCH lock predicate.
        // Its metric/threshold/base/stamp belong to the previous metric event.
        wire dbg_sync_peak_condition=zc_metric_v && state==S_SEARCH &&
            prev_pass && prev_metric>=zc_metric && prev_metric>older_metric;
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                dbg_sync_metric_v<=0;
                dbg_sync_metric<=0;
                dbg_sync_threshold<=0;
                dbg_sync_energy<=0;
                dbg_sync_base<=0;
                dbg_sync_stamp<=0;
                dbg_sync_pass<=0;
                dbg_sync_peak_v<=0;
                dbg_sync_peak_metric<=0;
                dbg_sync_peak_threshold<=0;
                dbg_sync_peak_base<=0;
                dbg_sync_peak_stamp<=0;
                dbg_sync_sym_v<=0;
                dbg_sync_sym_i<=0;
                dbg_sync_sym_q<=0;
                dbg_sync_locked<=0;
                dbg_sync_state<=0;
                dbg_sync_adjust_v<=0;
                dbg_sync_adjust<=0;
                dbg_sync_pn_index<=0;
                dbg_sync_previous_threshold<=0;
            end else begin
                dbg_sync_metric_v<=zc_metric_v;
                dbg_sync_metric<=zc_metric;
                dbg_sync_threshold<={8'd0,zc_metric_energy,5'd0};
                dbg_sync_energy<=zc_metric_energy;
                dbg_sync_base<=zc_metric_base;
                dbg_sync_stamp<=zc_metric_stamp;
                dbg_sync_pass<=zc_pass;
                dbg_sync_peak_v<=dbg_sync_peak_condition;
                if(zc_metric_v)
                    dbg_sync_previous_threshold<={8'd0,zc_metric_energy,5'd0};
                if(dbg_sync_peak_condition) begin
                    dbg_sync_peak_metric<=prev_metric;
                    dbg_sync_peak_threshold<=dbg_sync_previous_threshold;
                    dbg_sync_peak_base<=prev_base;
                    dbg_sync_peak_stamp<=prev_stamp;
                end
                dbg_sync_sym_v<=sym_v;
                dbg_sync_sym_i<=sym_i;
                dbg_sync_sym_q<=sym_q;
                dbg_sync_locked<=sync_locked;
                dbg_sync_state<=state;
                dbg_sync_adjust_v<=timing_adjust_v;
                dbg_sync_adjust<=timing_adjust;
                dbg_sync_pn_index<=pn_index;
            end
        end
        (* DONT_TOUCH="TRUE" *) ila_feedback_sync u_ila_feedback_sync(
            .clk(clk),
            .probe0(dbg_sync_metric_v),
            .probe1(dbg_sync_metric),
            .probe2(dbg_sync_threshold),
            .probe3(dbg_sync_energy),
            .probe4(dbg_sync_base),
            .probe5(dbg_sync_stamp),
            .probe6(dbg_sync_pass),
            .probe7(dbg_sync_peak_v),
            .probe8(dbg_sync_peak_metric),
            .probe9(dbg_sync_peak_threshold),
            .probe10(dbg_sync_peak_base),
            .probe11(dbg_sync_peak_stamp),
            .probe12(dbg_sync_sym_v),
            .probe13(dbg_sync_sym_i),
            .probe14(dbg_sync_sym_q),
            .probe15(dbg_sync_locked),
            .probe16(dbg_sync_state),
            .probe17(dbg_sync_adjust_v),
            .probe18(dbg_sync_adjust),
            .probe19(dbg_sync_pn_index)
        );

        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg dbg_pn_metric_v;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [83:0] dbg_pn_metric;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg dbg_pn_metric_is_ref;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [2:0] dbg_pn_location;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [3:0] dbg_pn_candidate;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [83:0] dbg_pn_best_metric;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [3:0] dbg_pn_best_template;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [9:0] dbg_pn_best_addr;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg dbg_pn_peak_v;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [83:0] dbg_pn_peak_metric;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [3:0] dbg_pn_peak_template;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [9:0] dbg_pn_peak_frame_base;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [9:0] dbg_pn_peak_addr;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg dbg_pn_sample_v;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [15:0] dbg_pn_sample_i;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [15:0] dbg_pn_sample_q;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [15:0] dbg_pn_sample_ref_i;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [15:0] dbg_pn_sample_ref_q;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [1:0] dbg_pn_sample_kind;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [2:0] dbg_pn_sample_location;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [3:0] dbg_pn_sample_candidate;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [5:0] dbg_pn_sample_index;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg dbg_pn_adjust_v;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [6:0] dbg_pn_adjust;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [5:0] dbg_pn_state;
        // PN sample tags follow the same three issue/read/select stages as
        // mac_a_i/q. This only annotates observation; it does not change MAC.
        reg [2:0] dbg_pn_location_tag[0:2];
        reg [3:0] dbg_pn_candidate_tag[0:2];
        integer dbg_pn_tag_stage;
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                dbg_pn_metric_v<=0;
                dbg_pn_metric<=0;
                dbg_pn_metric_is_ref<=0;
                dbg_pn_location<=0;
                dbg_pn_candidate<=0;
                dbg_pn_best_metric<=0;
                dbg_pn_best_template<=0;
                dbg_pn_best_addr<=0;
                dbg_pn_peak_v<=0;
                dbg_pn_peak_metric<=0;
                dbg_pn_peak_template<=0;
                dbg_pn_peak_frame_base<=0;
                dbg_pn_peak_addr<=0;
                dbg_pn_sample_v<=0;
                dbg_pn_sample_i<=0;
                dbg_pn_sample_q<=0;
                dbg_pn_sample_ref_i<=0;
                dbg_pn_sample_ref_q<=0;
                dbg_pn_sample_kind<=0;
                dbg_pn_sample_location<=0;
                dbg_pn_sample_candidate<=0;
                dbg_pn_sample_index<=0;
                dbg_pn_adjust_v<=0;
                dbg_pn_adjust<=0;
                dbg_pn_state<=0;
                for(dbg_pn_tag_stage=0;dbg_pn_tag_stage<3;
                    dbg_pn_tag_stage=dbg_pn_tag_stage+1) begin
                    dbg_pn_location_tag[dbg_pn_tag_stage]<=0;
                    dbg_pn_candidate_tag[dbg_pn_tag_stage]<=0;
                end
            end else begin
                dbg_pn_location_tag[0]<=location;
                dbg_pn_candidate_tag[0]<=candidate;
                for(dbg_pn_tag_stage=1;dbg_pn_tag_stage<3;
                    dbg_pn_tag_stage=dbg_pn_tag_stage+1) begin
                    dbg_pn_location_tag[dbg_pn_tag_stage]<=
                        dbg_pn_location_tag[dbg_pn_tag_stage-1];
                    dbg_pn_candidate_tag[dbg_pn_tag_stage]<=
                        dbg_pn_candidate_tag[dbg_pn_tag_stage-1];
                end
                // PN uses argmax only: there is no PN acceptance threshold.
                // location/candidate stay stable until this score is consumed.
                dbg_pn_metric_v<=acc_metric_v &&
                    (state==S_PN_LOC_SCORE || state==S_PN_REF_SCORE);
                dbg_pn_metric<=acc_metric;
                dbg_pn_metric_is_ref<=pn_metric_is_ref;
                dbg_pn_location<=location;
                dbg_pn_candidate<=candidate;
                dbg_pn_best_metric<=score_best;
                dbg_pn_best_template<=best_template;
                dbg_pn_best_addr<=best_pn_addr;
                dbg_pn_peak_v<=state==S_PN_END;
                if(state==S_PN_END) begin
                    dbg_pn_peak_metric<=score_best;
                    dbg_pn_peak_template<=best_template;
                    dbg_pn_peak_frame_base<=best_pn_addr-10'd64;
                    dbg_pn_peak_addr<=best_pn_addr;
                end
                dbg_pn_sample_v<=mac_v[2] && mac_kind[2]<2;
                dbg_pn_sample_i<=mac_a_i;
                dbg_pn_sample_q<=mac_a_q;
                dbg_pn_sample_ref_i<=mac_b_i;
                dbg_pn_sample_ref_q<=mac_b_q;
                dbg_pn_sample_kind<=mac_kind[2];
                dbg_pn_sample_location<=dbg_pn_location_tag[2];
                dbg_pn_sample_candidate<=dbg_pn_candidate_tag[2];
                dbg_pn_sample_index<=mac_index[2];
                dbg_pn_adjust_v<=timing_adjust_v;
                dbg_pn_adjust<=timing_adjust;
                dbg_pn_state<=state;
            end
        end
        (* DONT_TOUCH="TRUE" *) ila_feedback_pn u_ila_feedback_pn(
            .clk(clk),
            .probe0(dbg_pn_metric_v),
            .probe1(dbg_pn_metric),
            .probe2(dbg_pn_metric_is_ref),
            .probe3(dbg_pn_location),
            .probe4(dbg_pn_candidate),
            .probe5(dbg_pn_best_metric),
            .probe6(dbg_pn_best_template),
            .probe7(dbg_pn_best_addr),
            .probe8(dbg_pn_peak_v),
            .probe9(dbg_pn_peak_metric),
            .probe10(dbg_pn_peak_template),
            .probe11(dbg_pn_peak_frame_base),
            .probe12(dbg_pn_peak_addr),
            .probe13(dbg_pn_sample_v),
            .probe14(dbg_pn_sample_i),
            .probe15(dbg_pn_sample_q),
            .probe16(dbg_pn_sample_ref_i),
            .probe17(dbg_pn_sample_ref_q),
            .probe18(dbg_pn_sample_kind),
            .probe19(dbg_pn_sample_location),
            .probe20(dbg_pn_sample_candidate),
            .probe21(dbg_pn_sample_index),
            .probe22(dbg_pn_adjust_v),
            .probe23(dbg_pn_adjust),
            .probe24(dbg_pn_state)
        );

        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg dbg_fde_window_v;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [15:0] dbg_fde_window_i;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [15:0] dbg_fde_window_q;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [1:0] dbg_fde_window_block;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [5:0] dbg_fde_window_index;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg dbg_fde_rotated_v;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [15:0] dbg_fde_rotated_i;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [15:0] dbg_fde_rotated_q;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [1:0] dbg_fde_rotated_block;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [5:0] dbg_fde_rotated_index;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg dbg_fde_equalized_v;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [15:0] dbg_fde_equalized_i;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [15:0] dbg_fde_equalized_q;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [5:0] dbg_fde_equalized_index;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg dbg_fde_done;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg dbg_fde_fault;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg dbg_fde_busy;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [31:0] dbg_fde_cfo_phase_step;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg dbg_fde_packet_v;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [23:0] dbg_fde_packet24;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg dbg_fde_bad_crc;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [5:0] dbg_fde_state;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [9:0] dbg_fde_base;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [31:0] dbg_fde_stamp;
        (* KEEP="TRUE",MARK_DEBUG="TRUE",DONT_TOUCH="TRUE" *) reg [31:0] dbg_fde_sample_count;
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                dbg_fde_window_v<=0;
                dbg_fde_window_i<=0;
                dbg_fde_window_q<=0;
                dbg_fde_window_block<=0;
                dbg_fde_window_index<=0;
                dbg_fde_rotated_v<=0;
                dbg_fde_rotated_i<=0;
                dbg_fde_rotated_q<=0;
                dbg_fde_rotated_block<=0;
                dbg_fde_rotated_index<=0;
                dbg_fde_equalized_v<=0;
                dbg_fde_equalized_i<=0;
                dbg_fde_equalized_q<=0;
                dbg_fde_equalized_index<=0;
                dbg_fde_done<=0;
                dbg_fde_fault<=0;
                dbg_fde_busy<=0;
                dbg_fde_cfo_phase_step<=0;
                dbg_fde_packet_v<=0;
                dbg_fde_packet24<=0;
                dbg_fde_bad_crc<=0;
                dbg_fde_state<=0;
                dbg_fde_base<=0;
                dbg_fde_stamp<=0;
                dbg_fde_sample_count<=0;
            end else begin
                // mac_a at stage2 is the exact CP-stripped window operand
                // before carrier correction. block0/1=train, block2=data.
                dbg_fde_window_v<=mac_v[2] && mac_kind[2]==3;
                dbg_fde_window_i<=mac_a_i;
                dbg_fde_window_q<=mac_a_q;
                dbg_fde_window_block<=mac_block[2];
                dbg_fde_window_index<=mac_index[2];
                dbg_fde_rotated_v<=mac_rot_v;
                dbg_fde_rotated_i<=mac_rot_i;
                dbg_fde_rotated_q<=mac_rot_q;
                dbg_fde_rotated_block<=mac_rot_block;
                dbg_fde_rotated_index<=mac_rot_index;
                dbg_fde_equalized_v<=fde_out_v;
                dbg_fde_equalized_i<=fde_out_i;
                dbg_fde_equalized_q<=fde_out_q;
                dbg_fde_equalized_index<=fde_out_index;
                dbg_fde_done<=fde_done;
                dbg_fde_fault<=fde_fault;
                dbg_fde_busy<=fde_busy;
                dbg_fde_cfo_phase_step<=phase_step;
                dbg_fde_packet_v<=packet_v;
                dbg_fde_packet24<=packet24;
                dbg_fde_bad_crc<=bad_crc;
                dbg_fde_state<=state;
                dbg_fde_base<=base_addr;
                dbg_fde_stamp<=base_stamp;
                dbg_fde_sample_count<=sample_count;
            end
        end
        (* DONT_TOUCH="TRUE" *) ila_feedback_fde u_ila_feedback_fde(
            .clk(clk),
            .probe0(dbg_fde_window_v),
            .probe1(dbg_fde_window_i),
            .probe2(dbg_fde_window_q),
            .probe3(dbg_fde_window_block),
            .probe4(dbg_fde_window_index),
            .probe5(dbg_fde_rotated_v),
            .probe6(dbg_fde_rotated_i),
            .probe7(dbg_fde_rotated_q),
            .probe8(dbg_fde_rotated_block),
            .probe9(dbg_fde_rotated_index),
            .probe10(dbg_fde_equalized_v),
            .probe11(dbg_fde_equalized_i),
            .probe12(dbg_fde_equalized_q),
            .probe13(dbg_fde_equalized_index),
            .probe14(dbg_fde_done),
            .probe15(dbg_fde_fault),
            .probe16(dbg_fde_busy),
            .probe17(dbg_fde_cfo_phase_step),
            .probe18(dbg_fde_packet_v),
            .probe19(dbg_fde_packet24),
            .probe20(dbg_fde_bad_crc),
            .probe21(dbg_fde_state),
            .probe22(dbg_fde_base),
            .probe23(dbg_fde_stamp),
            .probe24(dbg_fde_sample_count)
        );
    end endgenerate

endmodule
`default_nettype wire
