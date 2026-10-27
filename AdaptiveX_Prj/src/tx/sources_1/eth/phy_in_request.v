`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Module Name: phy_in_request
// Description: Per-frame mode capture and fixed-rate MAC request windows.
// Six 265-clock slots; each requests 3*W words. A P change reserves 13/9/7
// clocks (old P=2/4/8) BEFORE the next frame's virtual header. No backpressure.
// Revision: 2026/10/14 - Tx_No_Reset, Verilog-2001 / Vivado 2021.2.
//////////////////////////////////////////////////////////////////////////////////
module phy_in_request #(
    parameter integer INITIAL = 82
)(
    input wire                          clk,
    input wire                          rst_n,
    input wire  [3:0]                   phy_ploy,
    input wire  [1:0]                   phy_mod,
    output wire                         phy_rdy,
    output reg  [3:0]                   dout_ploy,
    output reg  [1:0]                   dout_mod,
    output wire                        frame_commit
);
    localparam IDLE=3'd0, HEAD=3'd1, TRAIN=3'd2, DATA=3'd3;
    localparam GAP=3'd4, GUARD=3'd5;
    reg         [2:0]                   state;
    reg         [15:0]                  timer;
    reg         [2:0]                   block_index;
    reg         [4:0]                   guard_clocks;
    wire        [5:0]                   phy_width;
    wire        [7:0]                   load_clocks;
    wire        [5:0]                   head_clocks;
    wire                                mode_ok;

    assign mode_ok = (phy_ploy==2 || phy_ploy==4 || phy_ploy==8) && phy_mod<=2;
    assign phy_width = {2'd0,dout_ploy} << dout_mod;
    assign load_clocks = {2'd0,phy_width} + ({2'd0,phy_width} << 1);
    assign head_clocks = dout_ploy==2 ? 6'd40 : dout_ploy==4 ? 6'd36 : 6'd34;
    assign phy_rdy = rst_n && state==DATA;
    // This strobe is true BEFORE the edge that captures the next frame mode.
    // An external controller observes exactly the same request as this FSM.
    assign frame_commit = rst_n && mode_ok &&
        ((state==IDLE && timer==INITIAL-1) ||
         (state==GAP && block_index==3'd5 && timer==16'd264-load_clocks));

    always@(posedge clk)begin
        if(!rst_n)begin
            state <= IDLE;
            timer <= 16'd0;
            block_index <= 3'd0;
            guard_clocks <= 5'd0;
            dout_ploy <= 4'd2;
            dout_mod <= 2'd0;
        end
        else begin
            case(state)
                IDLE: begin
                    if(timer==INITIAL-1 && mode_ok)begin
                        dout_ploy <= phy_ploy;
                        dout_mod <= phy_mod;
                        timer <= 16'd0;
                        state <= HEAD;
                    end
                    else if(timer<INITIAL-1) timer <= timer+1'b1;
                end
                HEAD: begin
                    if(timer==head_clocks-1)begin
                        timer <= 16'd0;
                        state <= TRAIN;
                    end
                    else timer <= timer+1'b1;
                end
                TRAIN: begin
                    if(timer==16'd529)begin
                        timer <= 16'd0;
                        block_index <= 3'd0;
                        state <= DATA;
                    end
                    else timer <= timer+1'b1;
                end
                DATA: begin
                    if(timer==load_clocks-1)begin
                        timer <= 16'd0;
                        state <= GAP;
                    end
                    else timer <= timer+1'b1;
                end
                GAP: begin
                    if(timer==16'd264-load_clocks)begin
                        timer <= 16'd0;
                        if(block_index==3'd5)begin
                            block_index <= 3'd0;
                            if(mode_ok)begin
                                dout_ploy <= phy_ploy;
                                dout_mod <= phy_mod;
                            end
                            if(mode_ok && phy_ploy!=dout_ploy)begin
                                guard_clocks <= dout_ploy==2 ? 5'd13 : dout_ploy==4 ? 5'd9 : 5'd7;
                                state <= GUARD;
                            end
                            else state <= HEAD;
                        end
                        else begin
                            block_index <= block_index+1'b1;
                            state <= DATA;
                        end
                    end
                    else timer <= timer+1'b1;
                end
                GUARD: begin
                    if(timer==guard_clocks-1)begin
                        timer <= 16'd0;
                        state <= HEAD;
                    end
                    else timer <= timer+1'b1;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
