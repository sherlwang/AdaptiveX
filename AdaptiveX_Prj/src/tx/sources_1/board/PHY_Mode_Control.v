`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
// Create Date: 2026/09/21
// Module Name: PHY_Mode_Control
// Project Name: rfevm_rf_adaloop
// Target Devices: ZU47DR
// Tool Versions: Verilog-2001 / Vivado 2021.2
// Description: Load a stable legal VIO mode before releasing the physical layer.
// Dependencies: Reset_Sync. VIO mode outputs are clocked by this 204.8MHz clock.
// Revision: 0.01 - Four matching observations, then eight configuration clocks.
// Additional Comments: Runtime requests are debounced without a PHY reset.
// Each consumer synchronizes release in its own clock domain. No backpressure.
//////////////////////////////////////////////////////////////////////////////////

module PHY_Mode_Control (
    input wire clk,
    input wire locked,
    input wire vio_rst_n,
    input wire [3:0] vio_ploy,
    input wire [1:0] vio_mod,
    output reg [3:0] phy_ploy,
    output reg [1:0] phy_mod,
    output wire phy_reset_n,
    output reg mode_loaded
);
    wire request_n;
    wire control_rst_n;
    wire mode_legal;
    reg [5:0] candidate;
    reg [2:0] stable_count;
    reg [3:0] settle_count;
    reg run_enable;

    assign request_n = locked && vio_rst_n;
    assign mode_legal = ((vio_ploy == 4'd2) || (vio_ploy == 4'd4) || (vio_ploy == 4'd8)) && (vio_mod <= 2'd2);
    assign phy_reset_n = request_n && run_enable;

    Reset_Sync u_control_reset (
        .clk   (clk),
        .arst_n(request_n),
        .rst_n (control_rst_n)
    );

    //////////////////////////////////////////////////////
    //                    Load / Hold / Release         //
    //////////////////////////////////////////////////////
    always @(posedge clk or negedge control_rst_n) begin
        if (!control_rst_n) begin
            phy_ploy <= 4'd8;
            phy_mod <= 2'd2;
            candidate <= 6'd0;
            stable_count <= 3'd0;
            settle_count <= 4'd0;
            mode_loaded <= 1'b0;
            run_enable <= 1'b0;
        end else if (!mode_loaded) begin
            if (!mode_legal) begin
                stable_count <= 3'd0;
            end else if (candidate != {vio_ploy, vio_mod}) begin
                candidate <= {vio_ploy, vio_mod};
                stable_count <= 3'd1;
            end else if (stable_count == 3'd3) begin
                phy_ploy <= candidate[5:2];
                phy_mod <= candidate[1:0];
                mode_loaded <= 1'b1;
                settle_count <= 4'd0;
            end else begin
                stable_count <= stable_count + 3'd1;
            end
        end else if (!run_enable) begin
            if (settle_count == 4'd7) begin
                run_enable <= 1'b1;
            end else begin
                settle_count <= settle_count + 4'd1;
            end
        end else begin
            // Publish a stable next-frame request. The request scheduler, not
            // this VIO controller, defines the frame boundary for consumers.
            if (!mode_legal) stable_count <= 3'd0;
            else if (candidate != {vio_ploy, vio_mod}) begin
                candidate <= {vio_ploy, vio_mod};
                stable_count <= 3'd1;
            end else if (stable_count == 3'd3) begin
                phy_ploy <= candidate[5:2];
                phy_mod  <= candidate[1:0];
            end else stable_count <= stable_count + 3'd1;
        end
    end
endmodule
`default_nettype wire
