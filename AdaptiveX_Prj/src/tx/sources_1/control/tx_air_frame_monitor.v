`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tx_air_frame_monitor
// Description: Count complete frames in the real Rate output, excluding guards.
//              Follow the data to the registered physical DAC port, then convey
//              sparse frame events and stable mode mailboxes to 204.8 MHz.
// Pipeline: RRC 11 + Mult_Gain 3 + IQ register 1 + mixer 4 + DAC register 1.
// No data-path replacement, frame timer approximation or PHY reset on changes.
//////////////////////////////////////////////////////////////////////////////////
module tx_air_frame_monitor #(
    parameter integer DAC_STAGES = 20
) (
    input wire clk_fast,
    input wire clk_slow,
    input wire rst_n,
    input wire dac_run,
    input wire dac_ready,
    input wire rate_v,
    input wire rate_guard,
    input wire [3:0] rate_ploy,
    input wire [1:0] rate_mod,
    output wire dac_sof,
    output wire dac_eof,
    output wire dac_guard,
    output wire [3:0] dac_ploy,
    output wire [1:0] dac_mod,
    output reg frame_sof,
    output reg frame_done,
    output reg [3:0] frame_ploy,
    output reg [1:0] frame_mod,
    output reg [3:0] done_ploy,
    output reg [1:0] done_mod,
    output reg link_started,
    output reg stream_error
);
    wire rst_fast_n;
    wire rst_slow_n;
    reg [12:0] word_index;
    reg [5:0] frame_mode;
    reg frame_bad;
    reg [DAC_STAGES-1:0] sof_pipe;
    reg [DAC_STAGES-1:0] eof_pipe;
    reg [DAC_STAGES-1:0] good_pipe;
    reg [DAC_STAGES-1:0] guard_pipe;
    reg [5:0] mode_pipe [0:DAC_STAGES-1];
    reg physical_frame_run;
    reg dac_run_d;
    reg sof_toggle;
    reg done_toggle;
    reg [5:0] sof_mode_hold;
    reg [5:0] done_mode_hold;
    // Two extra event stages let the complete mode mailbox settle even when
    // a permitted source->payload path arrives one slow clock after its toggle.
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [3:0] sof_sync;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [3:0] done_sync;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [1:0] run_sync;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [5:0] sof_mode_sync1;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [5:0] sof_mode_sync2;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [5:0] done_mode_sync1;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [5:0] done_mode_sync2;
    reg sof_seen;
    reg done_seen;
    wire [12:0] frame_words = rate_ploy==4'd2 ? 13'd4320 :
                             rate_ploy==4'd4 ? 13'd4312 : 13'd4308;
    wire legal_mode = (rate_ploy==2 || rate_ploy==4 || rate_ploy==8) && rate_mod<=2;
    wire body_word = rate_v && !rate_guard && legal_mode;
    wire first_word = body_word && word_index==0;
    wire last_word = body_word && word_index==frame_words-1'b1;
    integer d;

    Reset_Sync u_fast_reset (.clk(clk_fast), .arst_n(rst_n), .rst_n(rst_fast_n));
    Reset_Sync u_slow_reset (.clk(clk_slow), .arst_n(rst_n), .rst_n(rst_slow_n));
    assign dac_sof = sof_pipe[DAC_STAGES-1];
    assign dac_eof = eof_pipe[DAC_STAGES-1];
    assign dac_guard = guard_pipe[DAC_STAGES-1];
    assign dac_ploy = mode_pipe[DAC_STAGES-1][5:2];
    assign dac_mod = mode_pipe[DAC_STAGES-1][1:0];

    always @(posedge clk_fast) begin
        if (!rst_fast_n) begin
            word_index <= 13'd0;
            frame_mode <= {4'd2,2'd0};
            frame_bad <= 1'b0;
            stream_error <= 1'b0;
            sof_pipe <= {DAC_STAGES{1'b0}};
            eof_pipe <= {DAC_STAGES{1'b0}};
            good_pipe <= {DAC_STAGES{1'b0}};
            guard_pipe <= {DAC_STAGES{1'b0}};
            for (d=0;d<DAC_STAGES;d=d+1) mode_pipe[d] <= {4'd2,2'd0};
        end else begin
            sof_pipe <= {sof_pipe[DAC_STAGES-2:0],first_word};
            eof_pipe <= {eof_pipe[DAC_STAGES-2:0],last_word};
            good_pipe <= {good_pipe[DAC_STAGES-2:0],last_word && !frame_bad && frame_mode=={rate_ploy,rate_mod}};
            guard_pipe <= {guard_pipe[DAC_STAGES-2:0],rate_v && rate_guard};
            mode_pipe[0] <= {rate_ploy,rate_mod};
            for (d=1;d<DAC_STAGES;d=d+1) mode_pipe[d] <= mode_pipe[d-1];
            if (first_word) begin
                frame_mode <= {rate_ploy,rate_mod};
                frame_bad <= 1'b0;
            end
            if (body_word) word_index <= last_word ? 13'd0 : word_index+1'b1;
            if (word_index!=0 && (!body_word || frame_mode!={rate_ploy,rate_mod})) begin
                stream_error <= 1'b1;
                frame_bad <= 1'b1;
            end
            if (rate_v && !legal_mode) stream_error <= 1'b1;
        end
    end

    // Mailboxes change only at sparse SOF/EOF events (>4300 fast clocks apart).
    // Every DAC cycle of the frame must have PS/RF transmission enabled.
    always @(posedge clk_fast or negedge rst_fast_n) begin
        if (!rst_fast_n) begin
            physical_frame_run <= 1'b0;
            dac_run_d <= 1'b0;
            sof_toggle <= 1'b0;
            done_toggle <= 1'b0;
            sof_mode_hold <= {4'd2,2'd0};
            done_mode_hold <= {4'd2,2'd0};
        end else begin
            // Markers identify the DAC register output after the preceding
            // edge. Use the enable sampled by that same DAC register, not the
            // new enable one edge later when the mailbox consumes the marker.
            dac_run_d <= dac_run;
            if (!dac_run_d || !dac_ready) physical_frame_run <= 1'b0;
            if (dac_sof) begin
                physical_frame_run <= dac_run_d && dac_ready;
                if (dac_run_d && dac_ready) begin
                    sof_mode_hold <= mode_pipe[DAC_STAGES-1];
                    sof_toggle <= !sof_toggle;
                end
            end
            if (dac_eof && good_pipe[DAC_STAGES-1] && physical_frame_run && dac_run_d && dac_ready) begin
                done_mode_hold <= mode_pipe[DAC_STAGES-1];
                done_toggle <= !done_toggle;
            end
        end
    end

    always @(posedge clk_slow or negedge rst_slow_n) begin
        if (!rst_slow_n) begin
            sof_sync <= 4'd0;
            done_sync <= 4'd0;
            run_sync <= 2'd0;
            sof_mode_sync1 <= {4'd2,2'd0};
            sof_mode_sync2 <= {4'd2,2'd0};
            done_mode_sync1 <= {4'd2,2'd0};
            done_mode_sync2 <= {4'd2,2'd0};
        end else begin
            sof_sync <= {sof_sync[2:0],sof_toggle};
            done_sync <= {done_sync[2:0],done_toggle};
            run_sync <= {run_sync[0],dac_run};
            sof_mode_sync1 <= sof_mode_hold;
            sof_mode_sync2 <= sof_mode_sync1;
            done_mode_sync1 <= done_mode_hold;
            done_mode_sync2 <= done_mode_sync1;
        end
    end
    always @(posedge clk_slow) begin
        if (!rst_slow_n) begin
            sof_seen <= 1'b0;
            done_seen <= 1'b0;
            frame_sof <= 1'b0;
            frame_done <= 1'b0;
            frame_ploy <= 4'd2;
            frame_mod <= 2'd0;
            done_ploy <= 4'd2;
            done_mod <= 2'd0;
            link_started <= 1'b0;
        end else begin
            sof_seen <= sof_sync[3];
            done_seen <= done_sync[3];
            frame_sof <= sof_sync[3]!=sof_seen && run_sync[1];
            frame_done <= done_sync[3]!=done_seen && run_sync[1];
            if (!run_sync[1]) link_started <= 1'b0;
            else if (sof_sync[3]!=sof_seen) begin
                frame_ploy <= sof_mode_sync2[5:2];
                frame_mod <= sof_mode_sync2[1:0];
                link_started <= 1'b1;
            end
            if (done_sync[3]!=done_seen) begin
                done_ploy <= done_mode_sync2[5:2];
                done_mod <= done_mode_sync2[1:0];
            end
        end
    end
endmodule
`default_nettype wire
