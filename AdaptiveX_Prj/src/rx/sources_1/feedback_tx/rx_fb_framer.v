`timescale 1ns / 1ps
`default_nettype none

// Q13 x2-QPSK short feedback frame, started only by a queued external event.
// No periodic source, repeated payload, or mode-dependent deadline is used.
// RRC and this module share clk. At a rising edge with advance && symbol_ce,
// consume combinational symbol_i/q and symbol_v; in_pop consumes the FWFT head
// on that very same edge. frame_start is the registered observation of this
// edge, while packet24 is the latched complete payload and CRC.
module rx_fb_framer #(
    parameter HEADER_MEM = "fb_short_header_q13.mem"
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               advance,
    input  wire               symbol_ce,
    input  wire               in_empty,
    input  wire [15:0]        in_payload16,
    output wire               in_pop,
    output reg signed [15:0]  symbol_i,
    output reg signed [15:0]  symbol_q,
    output wire               symbol_v,
    output reg                frame_start,
    output reg                frame_busy,
    output reg [23:0]         packet24,
    output reg [31:0]         frames_sent,
    output wire [8:0]         symbol_index
);
    localparam integer FRAME_SYMBOLS = 326;
    localparam integer FLUSH_SYMBOLS = 32;
    localparam integer TOTAL_SYMBOLS = FRAME_SYMBOLS + FLUSH_SYMBOLS;
    // Exact PN6144 prefix used by the business Tx/Rx and MATLAB feedback link.
    // Bit 123 is sent first; reset/restart the sequence for every short frame.
    // CRC is formed first, then all 124 packet/fill bits are XOR scrambled.
    localparam [123:0] SCRAMBLE_PN124 = 124'hFFF8024186B6A821DB8842F7FEC0CA5;
    (* rom_style = "distributed" *) reg [31:0] frame_rom [0:325];
    integer rom_pair;
    reg [8:0] next_symbol;
    reg head_prepared;
    reg [23:0] prepared_packet24;
    wire launch = rst_n && advance && symbol_ce && !frame_busy &&
                  !in_empty && head_prepared;
    wire emitting = frame_busy && next_symbol < FRAME_SYMBOLS;
    wire [8:0] current_symbol = frame_busy ? next_symbol : 9'd0;
    reg [1:0] raw_pair;

    function [7:0] crc8_payload;
        input [15:0] payload;
        reg [7:0] crc;
        reg feedback_bit;
        integer bit_index;
        begin
            crc = 8'd0;
            for(bit_index = 15; bit_index >= 0; bit_index = bit_index-1) begin
                feedback_bit = crc[7] ^ payload[bit_index];
                crc = {crc[6:0], 1'b0};
                if(feedback_bit) crc = crc ^ 8'h07;
            end
            crc8_payload = crc;
        end
    endfunction

    initial begin
        $readmemh(HEADER_MEM, frame_rom, 0, 243);
        // Vivado 2021.2 requires complete constant ROM words here. Initial
        // writes to memory bit slices are ignored during synthesis.
        for(rom_pair=0;rom_pair<62;rom_pair=rom_pair+1) begin
            frame_rom[264+rom_pair] = {
                SCRAMBLE_PN124[122-2*rom_pair] ? 16'hE95F : 16'h16A1,
                SCRAMBLE_PN124[123-2*rom_pair] ? 16'hE95F : 16'h16A1};
        end
        // CP is data-pair44..61. Construct the same PN constants directly;
        // an initial memory-to-memory copy is also ignored by this tool.
        for(rom_pair=0;rom_pair<18;rom_pair=rom_pair+1)
            frame_rom[244+rom_pair] = {
                SCRAMBLE_PN124[34-2*rom_pair] ? 16'hE95F : 16'h16A1,
                SCRAMBLE_PN124[35-2*rom_pair] ? 16'hE95F : 16'h16A1};
        frame_rom[262] = 32'h00002000;
        frame_rom[263] = 32'h0000E000;
    end

    // Prepare metadata without consuming the FWFT head. This breaks the RAM
    // read/CRC path; launch uses only registered metadata.
    // The FIFO head remains unchanged until launch asserts in_pop. After that
    // edge, the next head can be prepared while the current frame is emitted.
    // Preparation may run during a ready stall, but cannot advance sample time
    // or consume a message: launch still requires advance and symbol_ce.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            head_prepared <= 1'b0;
            prepared_packet24 <= 24'd0;
        end else if(launch) begin
            head_prepared <= 1'b0;
        end else if(!head_prepared && !in_empty) begin
            prepared_packet24 <= {in_payload16, crc8_payload(in_payload16)};
            head_prepared <= 1'b1;
        end
    end

    assign in_pop = launch;
    assign symbol_v = rst_n && advance && symbol_ce && (launch || emitting);
    assign symbol_index = current_symbol;

    // Symbols 0..243 come from the exact MATLAB short-frame sequences:
    // ZC64 + PN16 + (CP18, Train64) + (CP18, Train64).
    // 244..261: CP copied from the last 18 SCRAMBLED data symbols.
    // 262..325: +1, -1, then 124 scrambled packet/fill bits as 62 QPSK symbols.
    // The two pilots are never scrambled. CP data-pair indexes are 44..61.
    always @* begin
        case(current_symbol)
            9'd264: raw_pair = packet24[23:22];
            9'd265: raw_pair = packet24[21:20];
            9'd266: raw_pair = packet24[19:18];
            9'd267: raw_pair = packet24[17:16];
            9'd268: raw_pair = packet24[15:14];
            9'd269: raw_pair = packet24[13:12];
            9'd270: raw_pair = packet24[11:10];
            9'd271: raw_pair = packet24[9:8];
            9'd272: raw_pair = packet24[7:6];
            9'd273: raw_pair = packet24[5:4];
            9'd274: raw_pair = packet24[3:2];
            9'd275: raw_pair = packet24[1:0];
            default: raw_pair = 2'b00;
        endcase
        symbol_i = 16'sd0;
        symbol_q = 16'sd0;
        if(launch || emitting) begin
            symbol_i = frame_rom[current_symbol][15:0] ^ {{15{raw_pair[1]}},1'b0};
            symbol_q = frame_rom[current_symbol][31:16] ^ {{15{raw_pair[0]}},1'b0};
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            frame_start <= 0;
            frame_busy <= 0;
            packet24 <= 0;
            frames_sent <= 0;
            next_symbol <= 0;
        end else begin
            frame_start <= 0;
            if(advance) begin
                if(launch) begin
                    packet24 <= prepared_packet24;
                    frame_start <= 1'b1;
                    frame_busy <= 1'b1;
                    next_symbol <= 9'd1; // Symbol zero is consumed on this edge.
                end else if(frame_busy && symbol_ce) begin
                    if(next_symbol == TOTAL_SYMBOLS-1) begin
                        frame_busy <= 1'b0;
                        next_symbol <= 0;
                        frames_sent <= frames_sent + 1'b1;
                    end else next_symbol <= next_symbol + 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
