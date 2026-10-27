`timescale 1ns / 1ps
`default_nettype none

// Indexed DDC history: fixed-delay PHY replay and one acquisition read port.
module Rx_DDC_Buffer #(
    parameter integer DELAY_CLKS = 6144
) (
    input wire clk,
    input wire rst_n,
    input wire [383:0] din_i,
    input wire [383:0] din_q,
    input wire din_v,
    input wire descriptor_v,
    input wire [63:0] descriptor_idx,
    input wire [63:0] descriptor_ploy_idx,
    input wire [3:0] descriptor_ploy,
    input wire [3:0] descriptor_delay,
    input wire aux_read,
    input wire [63:0] aux_read_idx,
    output reg [383:0] aux_dout_i,
    output reg [383:0] aux_dout_q,
    output reg aux_dout_v,
    output reg [63:0] aux_dout_idx,
    output wire [63:0] write_idx,
    output wire [383:0] dout_i,
    output wire [383:0] dout_q,
    output wire dout_v,
    output reg [3:0] dout_ploy,
    output reg phase_applied,
    output reg [23:0] applied_idx,
    output reg [3:0] active_delay,
    output reg phase_locked,
    output reg error
);
    reg [63:0] wr_idx;
    reg [63:0] rd_idx;
    reg started;
    reg [3:0] active_ploy;
    reg [3:0] current_delay;
    reg [63:0] idx_fifo[0:7];
    reg [63:0] ploy_idx_fifo[0:7];
    reg [3:0] ploy_fifo[0:7];
    reg [3:0] delay_fifo[0:7];
    reg [2:0] queue_wr;
    reg [2:0] queue_rd;
    reg [3:0] queue_count;
    reg head_ploy_applied;
    wire read_enable;
    wire apply_ploy;
    wire apply_phase;
    wire queue_push;
    wire [3:0] read_delay;
    wire [3:0] read_ploy;
    reg [12:0] request_address;
    reg [12:0] request_previous_address;
    reg [3:0] request_delay;
    reg [3:0] request_ploy;
    reg request_v;
    reg request_previous_zero;
    reg request_phase;
    reg [23:0] request_phase_idx;
    reg raw_dout_v;
    reg raw_previous_zero;
    reg raw_phase;
    reg [3:0] raw_delay;
    reg [3:0] raw_ploy;
    reg [23:0] raw_phase_idx;
    reg [3:0] read_delay_d1;
    reg [3:0] read_ploy_d1;
    reg ram_dout_v;
    reg select_dout_v;
    reg previous_zero_d1;
    wire [31:0] bank_dout[0:23];
    reg [31:0] selected_sample[0:23];
    wire aux_available;
    genvar lane;

    assign write_idx = wr_idx;
    assign read_enable = rst_n && started && rd_idx < wr_idx;
    assign apply_ploy = read_enable && queue_count != 0 && !head_ploy_applied &&
        rd_idx == ploy_idx_fifo[queue_rd];
    assign apply_phase = read_enable && queue_count != 0 && rd_idx == idx_fifo[queue_rd];
    assign read_delay = apply_phase ? delay_fifo[queue_rd] : current_delay;
    assign read_ploy = apply_ploy ? ploy_fifo[queue_rd] : active_ploy;
    assign queue_push = descriptor_v && queue_count < 8;
    assign aux_available = aux_read_idx < wr_idx && wr_idx - aux_read_idx <= 4096;
    assign dout_v = select_dout_v && rst_n;

    generate
        for (lane = 0; lane < 24; lane = lane + 1) begin : sample_bank
            (* ram_style = "block" *) reg [31:0] main_ram[0:8191];
            (* ram_style = "block" *) reg [31:0] acquire_ram[0:4095];
            reg [31:0] main_dout;
            reg [31:0] main_dout_d1;
            reg [31:0] acquire_dout;
            wire [12:0] read_address;
            // Select two registered addresses; no subtract after phase selection.
            assign read_address = (lane >= 24 - request_delay) ? request_previous_address : request_address;
            always @(posedge clk) begin
                if (rst_n && din_v) begin
                    main_ram[wr_idx[12:0]] <= {din_q[16*lane+:16], din_i[16*lane+:16]};
                    acquire_ram[wr_idx[11:0]] <= {din_q[16*lane+:16], din_i[16*lane+:16]};
                end
                if (request_v) main_dout <= main_ram[read_address];
                // Keep the BRAM output stage ahead of the lane rotation.
                if (!rst_n) main_dout_d1 <= 0;
                else if (raw_dout_v) main_dout_d1 <= main_dout;
                if (rst_n && aux_read && aux_available) acquire_dout <= acquire_ram[aux_read_idx[11:0]];
            end
            assign bank_dout[lane] = previous_zero_d1 && lane >= 24 - read_delay_d1 ? 32'd0 : main_dout_d1;
            always @(posedge clk) begin
                if (!rst_n) selected_sample[lane] <= 0;
                else if (ram_dout_v)
                    case (read_delay_d1)
                        0: selected_sample[lane] <= bank_dout[(lane+24-0)%24];
                        1: selected_sample[lane] <= bank_dout[(lane+24-1)%24];
                        2: selected_sample[lane] <= bank_dout[(lane+24-2)%24];
                        3: selected_sample[lane] <= bank_dout[(lane+24-3)%24];
                        4: selected_sample[lane] <= bank_dout[(lane+24-4)%24];
                        5: selected_sample[lane] <= bank_dout[(lane+24-5)%24];
                        6: selected_sample[lane] <= bank_dout[(lane+24-6)%24];
                        7: selected_sample[lane] <= bank_dout[(lane+24-7)%24];
                        8: selected_sample[lane] <= bank_dout[(lane+24-8)%24];
                        9: selected_sample[lane] <= bank_dout[(lane+24-9)%24];
                        10: selected_sample[lane] <= bank_dout[(lane+24-10)%24];
                        11: selected_sample[lane] <= bank_dout[(lane+24-11)%24];
                        12: selected_sample[lane] <= bank_dout[(lane+24-12)%24];
                        default: selected_sample[lane] <= bank_dout[lane];
                    endcase
                if (!rst_n) begin
                    aux_dout_i[16*lane+:16] <= 0;
                    aux_dout_q[16*lane+:16] <= 0;
                end else begin
                    aux_dout_i[16*lane+:16] <= acquire_dout[15:0];
                    aux_dout_q[16*lane+:16] <= acquire_dout[31:16];
                end
            end
            assign dout_i[16*lane+:16] = dout_v ? selected_sample[lane][15:0] : 16'd0;
            assign dout_q[16*lane+:16] = dout_v ? selected_sample[lane][31:16] : 16'd0;
        end
    endgenerate

    reg aux_read_d1;
    reg [63:0] aux_idx_d1;
    always @(posedge clk) begin
        if (!rst_n) begin
            wr_idx <= 0;
            rd_idx <= 0;
            started <= 0;
            active_ploy <= 2;
            current_delay <= 0;
            active_delay <= 0;
            queue_wr <= 0;
            queue_rd <= 0;
            queue_count <= 0;
            head_ploy_applied <= 0;
            request_address <= 0;
            request_previous_address <= 0;
            request_delay <= 0;
            request_ploy <= 2;
            request_v <= 0;
            request_previous_zero <= 1;
            request_phase <= 0;
            request_phase_idx <= 0;
            raw_dout_v <= 0;
            raw_previous_zero <= 1;
            raw_phase <= 0;
            raw_delay <= 0;
            raw_ploy <= 2;
            raw_phase_idx <= 0;
            ram_dout_v <= 0;
            select_dout_v <= 0;
            previous_zero_d1 <= 1;
            read_delay_d1 <= 0;
            read_ploy_d1 <= 2;
            dout_ploy <= 2;
            phase_applied <= 0;
            applied_idx <= 0;
            phase_locked <= 0;
            aux_read_d1 <= 0;
            aux_dout_v <= 0;
            aux_idx_d1 <= 0;
            aux_dout_idx <= 0;
            error <= 0;
        end else begin
            if (din_v) wr_idx <= wr_idx + 1'b1;
            if (wr_idx >= DELAY_CLKS) started <= 1;
            if (descriptor_v && queue_count == 8) error <= 1;
            if (queue_push) begin
                idx_fifo[queue_wr] <= descriptor_idx;
                ploy_idx_fifo[queue_wr] <= descriptor_ploy_idx;
                ploy_fifo[queue_wr] <= descriptor_ploy;
                delay_fifo[queue_wr] <= descriptor_delay;
                queue_wr <= queue_wr + 1'b1;
            end
            case ({
                queue_push, apply_phase
            })
                2'b10:   queue_count <= queue_count + 1'b1;
                2'b01:   queue_count <= queue_count - 1'b1;
                default: queue_count <= queue_count;
            endcase
            if (read_enable && queue_count != 0 &&
                ((!head_ploy_applied && ploy_idx_fifo[queue_rd] < rd_idx) || idx_fifo[queue_rd] < rd_idx))
                error <= 1;
            if (apply_ploy) begin
                active_ploy <= ploy_fifo[queue_rd];
                head_ploy_applied <= 1;
            end
            if (apply_phase) begin
                current_delay <= delay_fifo[queue_rd];
                queue_rd <= queue_rd + 1'b1;
                head_ploy_applied <= 0;
            end

            // Request stage: capture data and frame controls together.
            request_v <= read_enable;
            request_phase <= apply_phase;
            if (read_enable) begin
                rd_idx <= rd_idx + 1'b1;
                request_address <= rd_idx[12:0];
                request_previous_address <= rd_idx[12:0] - 13'd1;
                request_delay <= read_delay;
                request_ploy <= read_ploy;
                request_previous_zero <= rd_idx == 0;
                request_phase_idx <= idx_fifo[queue_rd][23:0];
            end

            // RAM stage and its optional output register.
            raw_dout_v <= request_v;
            raw_phase  <= request_v && request_phase;
            if (request_v) begin
                raw_delay <= request_delay;
                raw_ploy <= request_ploy;
                raw_previous_zero <= request_previous_zero;
                raw_phase_idx <= request_phase_idx;
            end
            ram_dout_v <= raw_dout_v;
            if (raw_dout_v) begin
                read_delay_d1 <= raw_delay;
                read_ploy_d1 <= raw_ploy;
                previous_zero_d1 <= raw_previous_zero;
            end
            phase_applied <= raw_dout_v && raw_phase;
            if (raw_dout_v && raw_phase) begin
                active_delay <= raw_delay;
                applied_idx  <= raw_phase_idx;
                phase_locked <= 1;
            end
            select_dout_v <= ram_dout_v;
            if (ram_dout_v) dout_ploy <= read_ploy_d1;
            aux_read_d1  <= aux_read && aux_available;
            aux_idx_d1   <= aux_read_idx;
            aux_dout_v   <= aux_read_d1;
            aux_dout_idx <= aux_idx_d1;
            if (aux_read && !aux_available) error <= 1;
        end
    end
endmodule
`default_nettype wire
