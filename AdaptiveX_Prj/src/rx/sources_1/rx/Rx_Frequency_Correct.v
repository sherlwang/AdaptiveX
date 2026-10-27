`timescale 1ns / 1ps
`default_nettype none

// Delay each frame until its CFO estimate is ready, then rotate its samples.
module Rx_Frequency_Correct #(
    parameter integer DYNAMIC_MODE = 0
) (
    input wire clk,
    input wire rst_n,
    input wire [3:0] phy_ploy,
    input wire [127:0] din_i,
    input wire [127:0] din_q,
    input wire din_v,
    input wire din_start,
    input wire [31:0] din_frame_id,
    output wire [127:0] dout_i,
    output wire [127:0] dout_q,
    output wire dout_v,
    output wire dout_start,
    output wire [3:0] dout_ploy,
    output wire signed [31:0] estimate_step,
    output wire estimate_v,
    output wire [31:0] estimate_frame_id,
    output wire [31:0] dout_frame_id
);

    reg [3:0] mode_cfg;
    reg signed [31:0] step_pending;
    reg signed [31:0] step_active;
    reg signed [31:0] phase_base;
    wire signed [31:0] estimate_dout;
    wire estimate_dout_v;
    genvar ploy_idx;
    (* ram_style = "block" *) reg [293:0] frame_ram[0:1023];
    reg [9:0] wr_addr;
    reg [9:0] filled_clks;
    reg [293:0] frame_ram_dout;
    reg [31:0] input_frame_id;
    reg [31:0] frame_id_d[0:4];
    assign estimate_frame_id = input_frame_id;
    assign dout_frame_id = frame_id_d[4];
    wire [9:0] rd_addr;
    wire delayed_v;
    wire delayed_start;
    wire [3:0] input_ploy;
    wire [3:0] delayed_ploy;
    reg [3:0] ploy_d[0:4];
    integer stage_idx;
    wire signed [31:0] chosen_step;
    wire signed [31:0] lane_step;
    wire signed [31:0] current_phase;
    reg [4:0] din_v_d;
    reg [4:0] din_start_d;

    ////////////////////////// Logic //////////////////////////

    // Frame CFO estimate
    Rx_CFO_Estimate u_estimate (
        .clk      (clk),
        .rst_n    (rst_n),
        .din_i    (din_i),
        .din_q    (din_q),
        .din_v    (din_v),
        .din_start(din_start),
        .dout     (estimate_dout),
        .dout_v   (estimate_dout_v)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            mode_cfg <= phy_ploy;
            input_frame_id <= 0;
            step_pending <= 0;
        end else begin
            if (din_v && din_start) input_frame_id <= din_frame_id;
            if (DYNAMIC_MODE != 0 && din_v && din_start) mode_cfg <= phy_ploy;
            if (estimate_dout_v) step_pending <= estimate_dout;
        end
    end
    assign input_ploy = (DYNAMIC_MODE != 0 && din_start) ? phy_ploy : mode_cfg;
    assign delayed_ploy = (DYNAMIC_MODE != 0) ? frame_ram_dout[261:258] : mode_cfg;
    assign rd_addr = wr_addr - 10'd599;
    assign delayed_v = (filled_clks == 10'd600) && frame_ram_dout[256];
    assign delayed_start = delayed_v && frame_ram_dout[257];

    always @(posedge clk) begin
        frame_ram[wr_addr] <= {din_start ? din_frame_id : input_frame_id, input_ploy, din_start, din_v, din_q, din_i};
        frame_ram_dout <= frame_ram[rd_addr];
        if (!rst_n) begin
            wr_addr <= 10'd0;
            filled_clks <= 10'd0;
        end else begin
            wr_addr <= wr_addr + 10'd1;
            if (filled_clks < 10'd600) filled_clks <= filled_clks + 10'd1;
        end
    end
    assign chosen_step = delayed_start ? step_pending : step_active;
    assign lane_step = (delayed_ploy == 4'd2) ?
        (chosen_step >>> 1) : (delayed_ploy == 4'd4) ? (chosen_step >>> 2) : (chosen_step >>> 3);
    assign current_phase = delayed_start ? 32'sd0 : phase_base;

    always @(posedge clk) begin
        if (!rst_n) begin
            step_active <= 32'sd0;
            phase_base <= 32'sd0;
            din_v_d <= 5'd0;
            din_start_d <= 5'd0;
            for (stage_idx = 0; stage_idx < 5; stage_idx = stage_idx + 1) begin ploy_d[stage_idx] <= 4'd2; frame_id_d[stage_idx] <= 0; end
        end else begin
            din_v_d <= {din_v_d[3:0], delayed_v};
            if (delayed_v) begin ploy_d[0] <= delayed_ploy; frame_id_d[0] <= frame_ram_dout[293:262]; end
            for (stage_idx = 1; stage_idx < 5; stage_idx = stage_idx + 1) begin
                ploy_d[stage_idx] <= ploy_d[stage_idx-1];
                frame_id_d[stage_idx] <= frame_id_d[stage_idx-1];
            end
            din_start_d <= {din_start_d[3:0], delayed_v && delayed_start};
            if (delayed_v) begin
                if (delayed_start) begin
                    step_active <= step_pending;
                    phase_base  <= step_pending;
                end else phase_base <= phase_base + step_active;
            end
        end
    end
    assign dout_v = din_v_d[4];
    assign dout_start = din_start_d[4];
    assign dout_ploy = (DYNAMIC_MODE != 0) ? ploy_d[4] : mode_cfg;
    assign estimate_step = estimate_dout;
    assign estimate_v = estimate_dout_v;

    generate
        for (ploy_idx = 0; ploy_idx < 8; ploy_idx = ploy_idx + 1) begin : rotate_lane
            reg [31:0] phase_d1;
            reg signed [15:0] din_i_d1;
            reg signed [15:0] din_q_d1;
            wire signed [15:0] rotate_dout_i;
            wire signed [15:0] rotate_dout_q;
            always @(posedge clk) begin
                if (!rst_n || !delayed_v) begin
                    phase_d1 <= 0;
                    din_i_d1 <= 0;
                    din_q_d1 <= 0;
                end else begin
                    phase_d1 <= current_phase + lane_step * ploy_idx;
                    din_i_d1 <= frame_ram_dout[ploy_idx*16+:16];
                    din_q_d1 <= frame_ram_dout[128+ploy_idx*16+:16];
                end
            end
            Rx_CFO_Rotate_Lane u_rotate (
                .clk       (clk),
                .rst_n     (rst_n),
                .phase_turn(phase_d1),
                .din_i     (din_i_d1),
                .din_q     (din_q_d1),
                .dout_i    (rotate_dout_i),
                .dout_q    (rotate_dout_q)
            );
            assign dout_i[ploy_idx*16+:16] = rotate_dout_i;
            assign dout_q[ploy_idx*16+:16] = rotate_dout_q;
        end
    endgenerate


endmodule
`default_nettype wire
