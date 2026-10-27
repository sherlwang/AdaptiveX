`timescale 1ns / 1ps
`default_nettype none
// Status leaves the ordered decoder once per completed 255-word input block.
// Keep frame/block metadata outside its arithmetic and clock crossing.
module rx_ai_decode_tags (
    input wire clk,rst_n,
    input wire coded_v,coded_start,
    input wire [31:0] coded_frame_id,
    input wire [2:0] coded_block,
    input wire decode_done,
    output wire [31:0] decode_frame_id,
    output wire [2:0] decode_block,
    output wire tag_valid,
    output reg fault
);
    reg [34:0] mem[0:63];
    reg [5:0] wr,rd;
    reg [6:0] count;
    reg [7:0] word_count;
    wire push=coded_v && !coded_start && word_count==254;
    wire pop=decode_done && count!=0;
    assign tag_valid=count!=0;
    assign {decode_frame_id,decode_block}=mem[rd];
    always @(posedge clk) begin
        if(!rst_n) begin wr<=0;rd<=0;count<=0;word_count<=0;fault<=0;end
        else begin
            if(coded_v) word_count<=coded_start ? 1 : word_count==254 ? 0 : word_count+1'b1;
            if(push && (count<64 || pop)) begin mem[wr]<={coded_frame_id,coded_block};wr<=wr+1'b1;end
            if(pop) rd<=rd+1'b1;
            case({push && (count<64 || pop),pop})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:count<=count;
            endcase
            if((push && count==64 && !pop) || (decode_done && count==0)) fault<=1;
        end
    end
endmodule
`default_nettype wire
