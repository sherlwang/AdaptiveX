`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 2026/09/20
// Design Name: Multi-rate single-carrier Tx
// Module Name: Rate_Convert
// Project Name: rfevm_rf_adaloop
// Target Devices: ZU47DR
// Tool Versions: Verilog-2001 / Vivado 2021.2
// Description: P symbols @204.8MHz -> P/2 symbols @409.6MHz, P=2/4/8.
//              One 512 x 263bit tagged dual-clock RAM; no backpressure.
// Dependencies: rate_convert_cdc.xdc for Gray pointer delay / bus skew.
// Revision:
// Revision 0.03 - Registered RAM output; delay all reshape metadata together.
// Additional Comments: Common asynchronous active-low reset. Control release
//                      is synchronized separately in the two clock domains.
//                      Mode/guard accompany each RAM word; clocks exactly 2:1.
//                      Lane0 is earliest; inactive/invalid output lanes are zero.
//                      16bit signed samples are preserved without rescaling.
//////////////////////////////////////////////////////////////////////////////////

module Rate_Convert (
    input wire clk_200M,
    input wire clk_400M,
    input wire rst_n,
    input wire [3:0] phy_ploy,
    input wire [1:0] phy_mod,
    input wire din_guard,

    input wire [127:0] din_i,
    input wire [127:0] din_q,
    input wire din_v,

    (* DONT_TOUCH = "TRUE" *) output reg [63:0] dout_i,
    (* DONT_TOUCH = "TRUE" *) output reg [63:0] dout_q,
    (* DONT_TOUCH = "TRUE" *) output reg dout_v,
    (* DONT_TOUCH = "TRUE" *) output reg [3:0] dout_ploy,
    (* DONT_TOUCH = "TRUE" *) output reg [1:0] dout_mod,
    (* DONT_TOUCH = "TRUE" *) output reg dout_guard
);

    //---------------parameter
    localparam integer        AW            = 9;
    localparam         [ 2:0] IDLE          = 3'b001;
    localparam         [ 2:0] FIRST         = 3'b010;
    localparam         [ 2:0] SECOND        = 3'b100;
    localparam         [AW:0] PREFILL_WORDS = 10'd8;
    localparam         [ 4:0] START_TIMEOUT = 5'd31;
    //---------------parameter

    (* ram_style = "block" *) reg [262:0] mem[0:511];
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [AW:0] rd_gray_w1;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [AW:0] rd_gray_w2;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [AW:0] wr_gray_r1;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [AW:0] wr_gray_r2;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [1:0] wr_reset;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [1:0] rd_reset;

    reg [262:0] ram_q;
    reg [262:0] ram_pipe;
    reg [2:0] state_pipe;
    wire [3:0] word_ploy = ram_pipe[261:258];
    reg [AW:0] wr_bin;
    reg [AW:0] rd_bin;
    reg [AW:0] wr_gray;
    reg [AW:0] rd_gray;
    reg [AW:0] rd_level;
    reg [AW:0] synced_wr_bin;
    reg [2:0] state;
    reg [4:0] cnt_wait;
    reg overflow_error;
    reg mode_error;

    wire wr_run;
    wire rd_run;
    wire full;
    wire empty;
    wire wr_enable;
    wire rd_enable;
    wire start_read;
    wire [AW:0] wr_next;
    wire [AW:0] rd_next;
    integer b;

    //////////////////////////////////////////////////////
    //                    FIFO Control                  //
    //////////////////////////////////////////////////////
    assign wr_run     = wr_reset[1];
    assign rd_run     = rd_reset[1];
    assign full       = wr_gray == {~rd_gray_w2[AW:AW-1], rd_gray_w2[AW-2:0]};
    assign empty      = rd_gray == wr_gray_r2;
    assign wr_enable  = wr_run && din_v && !full;
    // Prefill covers synchronization latency; timeout drains bursts <8 words.
    assign start_read = !empty && ((rd_level >= PREFILL_WORDS) || (cnt_wait == START_TIMEOUT));
    assign rd_enable  = rd_run && (((state == IDLE) && start_read) || ((state == SECOND) && !empty));
    assign wr_next    = wr_bin + 10'd1;
    assign rd_next    = rd_bin + 10'd1;

    always @(*) begin
        synced_wr_bin[AW] = wr_gray_r2[AW];
        for (b = AW - 1; b >= 0; b = b - 1) begin
            synced_wr_bin[b] = synced_wr_bin[b+1] ^ wr_gray_r2[b];
        end
    end

    //////////////////////////////////////////////////////
    //                    Reset Release                 //
    //////////////////////////////////////////////////////
    always @(posedge clk_200M or negedge rst_n) begin
        if (!rst_n) begin
            wr_reset <= 2'b00;
        end else begin
            wr_reset <= {wr_reset[0], 1'b1};
        end
    end

    always @(posedge clk_400M or negedge rst_n) begin
        if (!rst_n) begin
            rd_reset <= 2'b00;
        end else begin
            rd_reset <= {rd_reset[0], 1'b1};
        end
    end

    //////////////////////////////////////////////////////
    //                    CDC Synchronizers             //
    //////////////////////////////////////////////////////
    // Direct two-register chains: do not insert enable or reset-release muxes
    // between stages. Local pointer/control processes are held by wr/rd_run.
    always @(posedge clk_200M or negedge wr_run) begin
        if (!wr_run) begin
            rd_gray_w1 <= 10'd0;
            rd_gray_w2 <= 10'd0;
        end else begin
            rd_gray_w1 <= rd_gray;
            rd_gray_w2 <= rd_gray_w1;
        end
    end

    always @(posedge clk_400M or negedge rd_run) begin
        if (!rd_run) begin
            wr_gray_r1 <= 10'd0;
            wr_gray_r2 <= 10'd0;
        end else begin
            wr_gray_r1 <= wr_gray;
            wr_gray_r2 <= wr_gray_r1;
        end
    end


    //////////////////////////////////////////////////////
    //                    Dual-clock RAM                //
    //////////////////////////////////////////////////////
    // RAM has no reset. Pointer reset invalidates all old entries.
    always @(posedge clk_200M) begin
        if (wr_enable) begin
            mem[wr_bin[AW-1:0]] <= {din_guard, phy_ploy, phy_mod, din_q, din_i};
        end
    end

    always @(posedge clk_400M) begin
        if (rd_enable) begin
            ram_q <= mem[rd_bin[AW-1:0]];
        end
    end

    // Use the BRAM output register before wide reshape selection.
    always @(posedge clk_400M) begin
        ram_pipe <= ram_q;
    end

    always @(posedge clk_400M or negedge rd_run) begin
        if (!rd_run) begin
            state_pipe <= IDLE;
        end else begin
            state_pipe <= state;
        end
    end

    //////////////////////////////////////////////////////
    //                    Write Pointer                 //
    //////////////////////////////////////////////////////
    always @(posedge clk_200M or negedge wr_run) begin
        if (!wr_run) begin
            wr_bin  <= 10'd0;
            wr_gray <= 10'd0;
        end else if (wr_enable) begin
            wr_bin  <= wr_next;
            wr_gray <= (wr_next >> 1) ^ wr_next;
        end
    end

    //////////////////////////////////////////////////////
    //                    Read Pointer / Level          //
    //////////////////////////////////////////////////////
    always @(posedge clk_400M or negedge rd_run) begin
        if (!rd_run) begin
            rd_bin  <= 10'd0;
            rd_gray <= 10'd0;
        end else if (rd_enable) begin
            rd_bin  <= rd_next;
            rd_gray <= (rd_next >> 1) ^ rd_next;
        end
    end

    always @(posedge clk_400M or negedge rd_run) begin
        if (!rd_run) begin
            rd_level <= 10'd0;
        end else begin
            rd_level <= synced_wr_bin - rd_bin;
        end
    end

    //////////////////////////////////////////////////////
    //                    State / Start Counter         //
    //////////////////////////////////////////////////////
    always @(posedge clk_400M or negedge rd_run) begin
        if (!rd_run) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (start_read) begin
                        state <= FIRST;
                    end
                end
                FIRST: begin
                    state <= SECOND;
                end
                SECOND: begin
                    state <= empty ? IDLE : FIRST;
                end
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    always @(posedge clk_400M or negedge rd_run) begin
        if (!rd_run) begin
            cnt_wait <= 5'd0;
        end else if (state == IDLE) begin
            if (start_read || empty) begin
                cnt_wait <= 5'd0;
            end else begin
                cnt_wait <= cnt_wait + 5'd1;
            end
        end
    end

    //////////////////////////////////////////////////////
    //                    Output ReShape                //
    //////////////////////////////////////////////////////
    // FIRST/SECOND follow the registered RAM data by the same delay.
    // The stream still emits one half every clock.
    always @(posedge clk_400M or negedge rd_run) begin
        if (!rd_run) begin
            dout_i <= 64'd0;
            dout_q <= 64'd0;
            dout_v <= 1'b0;
            dout_ploy <= 4'd2;
            dout_mod <= 2'd0;
            dout_guard <= 1'b0;
        end else begin
            dout_i <= 64'd0;
            dout_q <= 64'd0;
            dout_v <= state_pipe != IDLE;
            dout_guard <= state_pipe != IDLE && ram_pipe[262];
            if (state_pipe != IDLE) begin
                dout_ploy <= word_ploy;
                dout_mod  <= ram_pipe[257:256];
                case (word_ploy)
                    4'd2: begin
                        dout_i <= {48'd0, (state_pipe == FIRST) ? ram_pipe[15:0] : ram_pipe[31:16]};
                        dout_q <= {48'd0, (state_pipe == FIRST) ? ram_pipe[143:128] : ram_pipe[159:144]};
                    end
                    4'd4: begin
                        dout_i <= {32'd0, (state_pipe == FIRST) ? ram_pipe[31:0] : ram_pipe[63:32]};
                        dout_q <= {32'd0, (state_pipe == FIRST) ? ram_pipe[159:128] : ram_pipe[191:160]};
                    end
                    4'd8: begin
                        dout_i <= (state_pipe == FIRST) ? ram_pipe[63:0] : ram_pipe[127:64];
                        dout_q <= (state_pipe == FIRST) ? ram_pipe[191:128] : ram_pipe[255:192];
                    end
                    default: begin
                        dout_v <= 1'b0;
                    end
                endcase
            end
        end
    end

    //////////////////////////////////////////////////////
    //                    Diagnostics                   //
    //////////////////////////////////////////////////////
    always @(posedge clk_200M or negedge wr_run) begin
        if (!wr_run) begin
            overflow_error <= 1'b0;
        end else if (din_v && full) begin
            overflow_error <= 1'b1;
        end
    end

    always @(posedge clk_400M or negedge rd_run) begin
        if (!rd_run) begin
            mode_error <= 1'b0;
        end else if ((state_pipe != IDLE) && (word_ploy != 4'd2) && (word_ploy != 4'd4) &&
                     (word_ploy != 4'd8)) begin
            mode_error <= 1'b1;
        end
    end

endmodule
`default_nettype wire
