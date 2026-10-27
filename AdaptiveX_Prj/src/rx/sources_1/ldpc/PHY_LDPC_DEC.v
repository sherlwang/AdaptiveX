`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Module Name: PHY_LDPC_DEC
// Tool Versions: Verilog-2001 / Vivado 2021.2
// Description: Soft LLR -> ordered LDPC hard information -> PN6144 descramble.
//              Status aligns with the final output word of each 192-clock block.
//////////////////////////////////////////////////////////////////////////////////
module PHY_LDPC_DEC #(
    parameter         PN_FILE        = "pn6144_lsb.mem",
    parameter integer FORCE_MAX_ITER = 0,
    parameter integer DYNAMIC_WIDTH  = 0
) (
    input wire clk,
    input wire clk_core,
    input wire rst_n,
    input wire [3:0] phy_ploy,
    input wire [1:0] phy_mod,
    input wire [5:0] din_width,
    input wire [255:0] din_llr,
    input wire din_v,
    output wire [31:0] dout,
    output wire dout_v,
    output wire decode_done,
    output wire decode_ok,
    output wire [3:0] iterations,
    output wire [3:0] group_ok,
    output wire [5:0] dout_width,
    output wire overflow_error,
    output wire mode_error
);
    wire [31:0] decoded_data;
    wire decoded_v;
    wire raw_done;
    wire raw_ok;
    wire [3:0] raw_iterations;
    wire [3:0] raw_groups;
    wire [5:0] output_width;
    wire [5:0] decoded_width;
    wire [3:0] result_ploy;
    wire [1:0] result_mod;
    reg [9:0] status_dly;
    reg [9:0] status_dly2;

    // Result mode belongs to the output block, not the external next group.
    assign result_ploy = (decoded_width >= 8) ? 4'd8 : decoded_width[3:0];
    assign result_mod  = (decoded_width == 32) ? 2'd2 : (decoded_width == 16) ? 2'd1 : 2'd0;
    assign dout_width  = output_width;

    ldpc_decoder u_ldpc_decoder (
        .clk           (clk),
        .clk_core      (clk_core),
        .rst_n         (rst_n),
        .phy_ploy      (phy_ploy),
        .phy_mod       (phy_mod),
        .din_width     (din_width),
        .din_llr       (din_llr),
        .din_v         (din_v),
        .dout          (decoded_data),
        .dout_v        (decoded_v),
        .block_done    (raw_done),
        .decode_ok     (raw_ok),
        .iterations    (raw_iterations),
        .group_ok      (raw_groups),
        .dout_width    (decoded_width),
        .overflow_error(overflow_error),
        .mode_error    (mode_error)
    );
    // XOR with the same PN prefix is its own inverse; reuse existing Tx RTL.
    Scramble_PN6144 #(
        .PN_FILE(PN_FILE)
    ) u_Descramble_PN6144 (
        .clk       (clk),
        .rst_n     (rst_n),
        .phy_ploy  (result_ploy),
        .phy_mod   (result_mod),
        .phy_din   (decoded_data),
        .phy_din_v (decoded_v),
        .dout      (dout),
        .dout_v    (dout_v),
        .dout_width(output_width)
    );
    always @(posedge clk) begin
        if (!rst_n) begin
            status_dly  <= 0;
            status_dly2 <= 0;
        end else begin
            status_dly  <= {raw_done, raw_ok, raw_iterations, raw_groups};
            status_dly2 <= status_dly;
        end
    end
    assign {decode_done, decode_ok, iterations, group_ok} = status_dly2;
endmodule
`default_nettype wire
