`timescale 1ns / 1ps
`default_nettype none
// Whole-word CDC. Common asynchronous assertion, local three-clock release.
// FWFT output is consumed only with rd_en && !rd_empty. No producer backpressure.
module tx_fb_async_fifo #(
    parameter integer WIDTH=40,
    parameter integer ADDR_BITS=5
)(
    input wire wr_clk, input wire rd_clk, input wire arst_n,
    input wire wr_v, input wire [WIDTH-1:0] wr_data,
    output wire wr_full, output reg overflow,
    input wire rd_en, output wire [WIDTH-1:0] rd_data,
    output wire rd_empty, output wire [ADDR_BITS:0] rd_level
);
    (* ram_style="distributed" *) reg [WIDTH-1:0] words [0:(1<<ADDR_BITS)-1];
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [2:0] wr_release,rd_release;
    reg [ADDR_BITS:0] wr_binary,rd_binary,wr_gray,rd_gray;
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [ADDR_BITS:0] rd_gray_w1,rd_gray_w2;
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [ADDR_BITS:0] wr_gray_r1,wr_gray_r2;
    reg full_q,empty_q;
    wire write_take=wr_v && !wr_full;
    wire read_take=rd_en && !rd_empty;
    wire [ADDR_BITS:0] wr_next=wr_binary+write_take;
    wire [ADDR_BITS:0] rd_next=rd_binary+read_take;
    wire [ADDR_BITS:0] wr_gray_next=(wr_next>>1)^wr_next;
    wire [ADDR_BITS:0] rd_gray_next=(rd_next>>1)^rd_next;
    function [ADDR_BITS:0] gray_to_binary;
        input [ADDR_BITS:0] value;
        integer k;
        begin
            gray_to_binary[ADDR_BITS]=value[ADDR_BITS];
            for(k=ADDR_BITS-1;k>=0;k=k-1)
                gray_to_binary[k]=gray_to_binary[k+1]^value[k];
        end
    endfunction
    assign wr_full=!wr_release[2] || full_q;
    assign rd_empty=!rd_release[2] || empty_q;
    assign rd_data=rd_empty ? {WIDTH{1'b0}} : words[rd_binary[ADDR_BITS-1:0]];
    assign rd_level=!rd_release[2] ? {(ADDR_BITS+1){1'b0}} : gray_to_binary(wr_gray_r2)-rd_binary;
    always@(posedge wr_clk or negedge arst_n)begin
        if(!arst_n) wr_release<=0;
        else wr_release<={wr_release[1:0],1'b1};
    end
    always@(posedge rd_clk or negedge arst_n)begin
        if(!arst_n) rd_release<=0;
        else rd_release<={rd_release[1:0],1'b1};
    end
    always@(posedge wr_clk or negedge arst_n)begin
        if(!arst_n)begin rd_gray_w1<=0;rd_gray_w2<=0;end
        else begin rd_gray_w1<=rd_gray;rd_gray_w2<=rd_gray_w1;end
    end
    always@(posedge rd_clk or negedge arst_n)begin
        if(!arst_n)begin wr_gray_r1<=0;wr_gray_r2<=0;end
        else begin wr_gray_r1<=wr_gray;wr_gray_r2<=wr_gray_r1;end
    end
    always@(posedge wr_clk)begin
        if(write_take) words[wr_binary[ADDR_BITS-1:0]]<=wr_data;
    end
    always@(posedge wr_clk or negedge arst_n)begin
        if(!arst_n)begin wr_binary<=0;wr_gray<=0;full_q<=0;overflow<=0;end
        else if(!wr_release[2])begin wr_binary<=0;wr_gray<=0;full_q<=0;overflow<=0;end
        else begin
            wr_binary<=wr_next;wr_gray<=wr_gray_next;
            full_q<=wr_gray_next=={~rd_gray_w2[ADDR_BITS:ADDR_BITS-1],rd_gray_w2[ADDR_BITS-2:0]};
            if(wr_v && full_q) overflow<=1'b1;
        end
    end
    always@(posedge rd_clk or negedge arst_n)begin
        if(!arst_n)begin rd_binary<=0;rd_gray<=0;empty_q<=1;end
        else if(!rd_release[2])begin rd_binary<=0;rd_gray<=0;empty_q<=1;end
        else begin
            rd_binary<=rd_next;rd_gray<=rd_gray_next;
            empty_q<=rd_gray_next==wr_gray_r2;
        end
    end
endmodule
`default_nettype wire
