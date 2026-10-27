`timescale 1ns / 1ps
`default_nettype none

// 12ploy at 409.6 MHz to 24ploy at 204.8 MHz; low ploy arrives first.
module Rate_Convert_Rx12to24 #(
    parameter integer LANE_WIDTH = 16
) (
    input wire clk_400M,
    input wire clk_200M,
    input wire rst_n,
    input wire [12 * LANE_WIDTH - 1:0] din,
    input wire din_v,
    output reg [24 * LANE_WIDTH - 1:0] dout,
    output wire dout_v,
    output reg overflow_error
);

    localparam integer        AW            = 5;
    localparam         [AW:0] PREFILL_PAIRS = 6'd6;
    (* ram_style = "block" *) reg [24 * LANE_WIDTH - 1:0] mem[0:(1 << AW) - 1];
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [AW:0] rd_gray_w1;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [AW:0] rd_gray_w2;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [AW:0] wr_gray_r1;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [AW:0] wr_gray_r2;
    reg [12 * LANE_WIDTH - 1:0] first_word;
    reg second_word;
    // Capture RFDC data and valid together before pairing and RAM input.
    reg [12 * LANE_WIDTH - 1:0] adc_input_data;
    reg adc_input_valid;
    reg [AW:0] wr_bin;
    reg [AW:0] wr_gray;
    reg [AW:0] rd_bin;
    reg [AW:0] rd_gray;
    reg [AW:0] synced_wr_bin;
    reg [AW:0] rd_level;
    reg started;
    reg [24 * LANE_WIDTH - 1:0] ram_q;
    reg rd_valid_d1;
    reg dout_v_reg;
    wire wr_run;
    wire rd_run;
    wire full;
    wire empty;
    wire wr_accept;
    wire wr_pair_en;
    wire rd_enable;
    wire [AW:0] wr_next;
    wire [AW:0] rd_next;
    integer b;

    ////////////////////////// Logic //////////////////////////

    assign dout_v = rd_run && dout_v_reg;
    assign full = wr_gray == {~rd_gray_w2[AW:AW-1], rd_gray_w2[AW-2:0]};
    assign empty = rd_gray == wr_gray_r2;
    assign wr_accept = wr_run && adc_input_valid && !full && !overflow_error;
    assign wr_pair_en = wr_accept && second_word;
    assign rd_enable = rd_run && started && !empty;
    assign wr_next = wr_bin + {{AW{1'b0}}, 1'b1};
    assign rd_next = rd_bin + {{AW{1'b0}}, 1'b1};

    always @(*) begin
        synced_wr_bin[AW] = wr_gray_r2[AW];
        for (b = AW - 1; b >= 0; b = b - 1) begin
            synced_wr_bin[b] = synced_wr_bin[b+1] ^ wr_gray_r2[b];
        end
    end

    // Async assertion and two-clock release in each domain.
    xpm_cdc_async_rst #(
        .DEST_SYNC_FF   (2),
        .INIT_SYNC_FF   (0),
        .RST_ACTIVE_HIGH(0)
    ) u_wr_reset (
        .src_arst (rst_n),
        .dest_clk (clk_400M),
        .dest_arst(wr_run)
    );

    xpm_cdc_async_rst #(
        .DEST_SYNC_FF   (2),
        .INIT_SYNC_FF   (0),
        .RST_ACTIVE_HIGH(0)
    ) u_rd_reset (
        .src_arst (rst_n),
        .dest_clk (clk_200M),
        .dest_arst(rd_run)
    );

    // Data needs no reset: valid masks it through write-domain reset/release.
    always @(posedge clk_400M) begin
        adc_input_data <= din;
        if (!wr_run) adc_input_valid <= 1'b0;
        else         adc_input_valid <= din_v;
    end
    always @(posedge clk_400M) begin
        if (!wr_run) begin
            rd_gray_w1 <= {(AW + 1) {1'b0}};
            rd_gray_w2 <= {(AW + 1) {1'b0}};
        end else begin
            rd_gray_w1 <= rd_gray;
            rd_gray_w2 <= rd_gray_w1;
        end
    end

    always @(posedge clk_200M) begin
        if (!rd_run) begin
            wr_gray_r1 <= {(AW + 1) {1'b0}};
            wr_gray_r2 <= {(AW + 1) {1'b0}};
        end else begin
            wr_gray_r1 <= wr_gray;
            wr_gray_r2 <= wr_gray_r1;
        end
    end

    always @(posedge clk_400M) begin
        if (wr_pair_en) begin
            mem[wr_bin[AW-1:0]] <= {adc_input_data, first_word};
        end
    end

    always @(posedge clk_200M) begin
        if (rd_enable) begin
            ram_q <= mem[rd_bin[AW-1:0]];
        end
    end

    always @(posedge clk_400M) begin
        if (!wr_run) begin
            first_word <= {(12 * LANE_WIDTH) {1'b0}};
            second_word <= 1'b0;
            wr_bin <= {(AW + 1) {1'b0}};
            wr_gray <= {(AW + 1) {1'b0}};
            overflow_error <= 1'b0;
        end else begin
            if (adc_input_valid && full) begin
                overflow_error <= 1'b1;
            end
            if (!adc_input_valid) begin
                second_word <= 1'b0;
            end else if (wr_accept) begin
                if (!second_word) begin
                    first_word  <= adc_input_data;
                    second_word <= 1'b1;
                end else begin
                    second_word <= 1'b0;
                    wr_bin <= wr_next;
                    wr_gray <= (wr_next >> 1) ^ wr_next;
                end
            end
        end
    end

    always @(posedge clk_200M) begin
        if (!rd_run) begin
            rd_bin  <= {(AW + 1) {1'b0}};
            rd_gray <= {(AW + 1) {1'b0}};
        end else if (rd_enable) begin
            rd_bin  <= rd_next;
            rd_gray <= (rd_next >> 1) ^ rd_next;
        end
    end

    always @(posedge clk_200M) begin
        if (!rd_run) begin
            rd_level <= {(AW + 1) {1'b0}};
            started  <= 1'b0;
        end else begin
            rd_level <= synced_wr_bin - rd_bin;
            if (rd_level >= PREFILL_PAIRS) begin
                started <= 1'b1;
            end
        end
    end

    always @(posedge clk_200M) begin
        if (!rd_run) begin
            rd_valid_d1 <= 1'b0;
            dout <= {(24 * LANE_WIDTH) {1'b0}};
            dout_v_reg <= 1'b0;
        end else begin
            rd_valid_d1 <= rd_enable;
            dout_v_reg  <= rd_valid_d1;
            if (rd_valid_d1) dout <= ram_q;
            else dout <= {(24 * LANE_WIDTH) {1'b0}};
        end
    end

endmodule
`default_nettype wire
