`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
// Create Date: 2026/09/21
// Module Name: Reset_Sync
// Project Name: rfevm_rf_adaloop
// Target Devices: ZU47DR
// Tool Versions: Verilog-2001 / Vivado 2021.2
// Description: Asynchronous assertion, three destination-clock release stages.
// Dependencies: Targeted reset-synchronizer CLR exceptions only.
// Revision: 0.02 - Two synchronizer stages and one replicated release stage.
// Additional Comments: Clock must be running before reset can be released.
//////////////////////////////////////////////////////////////////////////////////

module reset_sync (
    input wire clk,
    input wire arst_n,
    output wire rst_n
);
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [1:0] release_dly;
    (* MAX_FANOUT = 128, SHREG_EXTRACT = "NO" *) reg release_out;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            release_dly <= 2'b00;
            release_out <= 1'b0;
        end else begin
            release_dly <= {release_dly[0], 1'b1};
            release_out <= release_dly[1];
        end
    end
    assign rst_n = release_out;
endmodule
`default_nettype wire
