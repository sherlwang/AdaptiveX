`timescale 1ns / 1ps
`default_nettype none

// Board reset assertion is asynchronous; release needs three local clocks.
// This reset is independent of the Ada core's no-sync watchdog reset.
module rx_fb_reset_sync (
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
