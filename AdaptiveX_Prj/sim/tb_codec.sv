`timescale 1ns/1fs
module tb_codec;
    reg clk = 0;
    reg clk_core = 0;
    reg rst_n = 0;
    reg [3:0] phy_p = 2;
    reg [1:0] phy_m = 0;
    reg [5:0] width = 2;
    reg [31:0] din = 0;
    reg din_valid = 0;
    reg [31:0] information [0:10367];
    reg [31:0] code_reference [0:13769];
    reg [3:0] block_p [0:53];
    reg [1:0] block_m [0:53];
    reg [5:0] block_width [0:53];
    wire [31:0] encoded;
    wire encoded_valid;
    wire [3:0] encoded_p;
    wire [1:0] encoded_m;
    wire [31:0] decoded;
    wire decoded_valid;
    wire [5:0] decoded_width;
    wire block_done;
    wire decode_ok;
    wire overflow;
    wire mode_error;
    reg [255:0] llr;
    wire [5:0] encoded_width = encoded_p << encoded_m;
    integer encoded_count = 0;
    integer decoded_count = 0;
    integer done_count = 0;
    integer mode;
    integer b;
    integer row;
    integer timeout;
    integer lane;
    integer block_number;
    integer f;
    reg [31:0] mask;

    always #2.44140625 clk = ~clk;
    always #1.627604167 clk_core = ~clk_core;

    ldpc_encoder u_encoder (
        .clk       (clk),
        .rst_n     (rst_n),
        .phy_width (width),
        .phy_ploy  (phy_p),
        .phy_mod   (phy_m),
        .din       (din),
        .din_v     (din_valid),
        .dout      (encoded),
        .dout_v    (encoded_valid),
        .dout_ploy (encoded_p),
        .dout_mod  (encoded_m)
    );

    always @(*) begin
        llr = 0;
        for (lane=0; lane<32; lane=lane+1)
            if (lane < encoded_width)
                llr[lane*8+:8] = encoded[lane] ? -8'sd63 : 8'sd63;
    end

    ldpc_decoder u_decoder (
        .clk            (clk),
        .clk_core       (clk_core),
        .rst_n          (rst_n),
        .phy_ploy       (encoded_p),
        .phy_mod        (encoded_m),
        .din_width      (encoded_width),
        .din_llr        (llr),
        .din_v          (encoded_valid),
        .dout           (decoded),
        .dout_v         (decoded_valid),
        .block_done     (block_done),
        .decode_ok      (decode_ok),
        .dout_width     (decoded_width),
        .overflow_error (overflow),
        .mode_error     (mode_error)
    );

    initial begin
        $readmemh("input.mem", information);
        $readmemh("encoded.mem", code_reference);
        $readmemh("p.mem", block_p);
        $readmemh("m.mem", block_m);
        $readmemh("width.mem", block_width);
        repeat (40) @(negedge clk);
        rst_n = 1;
        for (mode=0; mode<9; mode=mode+1) begin
            for (b=0; b<6; b=b+1) begin
                block_number = mode*6+b;
                phy_p = block_p[block_number];
                phy_m = block_m[block_number];
                width = block_width[block_number];
                for (row=0; row<192; row=row+1) begin
                    din_valid = 1;
                    din = information[block_number*192+row];
                    @(negedge clk);
                end
                din_valid = 0;
                repeat (360) @(negedge clk);
            end
            begin : drain_mode
                for (timeout=0; timeout<16000; timeout=timeout+1) begin
                    @(negedge clk);
                    if (done_count == 6*(mode+1)) disable drain_mode;
                end
                $fatal(1, "Codec timeout in mode %0d", mode);
            end
            $display("CODEC_MODE_PASS P=%0d M=%0d blocks=6", phy_p, phy_m);
        end
        repeat (100) @(negedge clk);
        if (encoded_count != 13770 || decoded_count != 10368 || done_count != 54)
            $fatal(1, "Codec counts mismatch %0d/%0d/%0d", encoded_count, decoded_count, done_count);
        if (overflow || mode_error) $fatal(1, "Codec control error");
        f = $fopen("codec_result.json", "w");
        $fdisplay(f, "{\"status\":\"PASS\",\"modes\":9,\"blocks\":54,\"encoded_words\":%0d,\"decoded_words\":%0d,\"bit_errors\":0}", encoded_count, decoded_count);
        $fclose(f);
        $display("CODEC_ALL_PASS MATLAB vectors: nine modes, 54 blocks, bit-exact encoder and decoder");
        $finish;
    end

    always @(negedge clk) begin
        if (rst_n) begin
            if (encoded_valid) begin
                if (encoded_p !== block_p[encoded_count/255] || encoded_m !== block_m[encoded_count/255])
                    $fatal(1, "Encoder metadata mismatch at word %0d: P=%0d M=%0d expected P=%0d M=%0d", encoded_count, encoded_p, encoded_m, block_p[encoded_count/255], block_m[encoded_count/255]);
                if (encoded_width !== block_width[encoded_count/255])
                    $fatal(1, "Encoder width mismatch at word %0d: width=%0d expected=%0d", encoded_count, encoded_width, block_width[encoded_count/255]);
                mask = 32'hffffffff >> (32-encoded_width);
                if (encoded_count >= 13770 || (encoded & mask) !== code_reference[encoded_count])
                    $fatal(1, "MATLAB encoder mismatch at word %0d", encoded_count);
                encoded_count = encoded_count + 1;
            end
            if (decoded_valid) begin
                if (decoded_width !== block_width[decoded_count/192])
                    $fatal(1, "Decoder width mismatch at word %0d: width=%0d expected=%0d", decoded_count, decoded_width, block_width[decoded_count/192]);
                mask = 32'hffffffff >> (32-decoded_width);
                if (decoded_count >= 10368 || (decoded & mask) !== information[decoded_count])
                    $fatal(1, "MATLAB decoder mismatch at word %0d width=%0d", decoded_count, decoded_width);
                decoded_count = decoded_count + 1;
            end
            if (block_done) begin
                if (!decode_ok) $fatal(1, "Failed LDPC check in noiseless codec test");
                done_count = done_count + 1;
            end
        end
    end
endmodule
