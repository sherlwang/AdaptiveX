`timescale 1ns/1ps
module tb_rrc;
    reg clk = 0;
    reg rst_n = 0;
    reg [3:0] p = 2;
    reg [63:0] din_i = 0;
    reg [63:0] din_q = 0;
    reg din_valid = 0;
    wire [191:0] dout_i;
    wire [191:0] dout_q;
    wire dout_valid;
    reg [63:0] input_i [0:251];
    reg [63:0] input_q [0:251];
    reg [191:0] output_i [0:251];
    reg [191:0] output_q [0:251];
    integer sent = 0;
    integer received = 0;
    integer mode;
    integer row;
    integer words;
    integer f;
    integer capture_limit = 0;
    integer idle_checks = 0;

    always #1.220703125 clk = ~clk;
    RRC_Shared dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .phy_ploy(p),
        .din_i  (din_i),
        .din_q  (din_q),
        .din_v  (din_valid),
        .dout_i (dout_i),
        .dout_q (dout_q),
        .dout_v (dout_valid)
    );
    initial begin
        $readmemh("input_i.mem",input_i);
        $readmemh("input_q.mem",input_q);
        $readmemh("output_i.mem",output_i);
        $readmemh("output_q.mem",output_q);
        repeat (80) @(negedge clk);
        for (mode=0;mode<3;mode=mode+1) begin
            rst_n = 0;
            p = 2 << mode;
            repeat (24) @(negedge clk);
            rst_n = 1;
            words = 144 >> mode;
            capture_limit = sent + words;
            for (row=0;row<words;row=row+1) begin
                din_i = input_i[sent];
                din_q = input_q[sent];
                din_valid = 1;
                sent = sent+1;
                @(negedge clk);
            end
            din_valid = 0;
            repeat (24) @(negedge clk);
            if (sent != received) $fatal(1,"RRC length mismatch P=%0d",p);
            $display("RRC_MODE_PASS P=%0d words=%0d",p,words);
        end
        f=$fopen("rrc_result.json","w");
        $fdisplay(f,"{\"status\":\"PASS\",\"p_values\":3,\"output_words\":252,\"integer_mismatches\":0}");
        $fclose(f);
        $display("RRC_ALL_PASS MATLAB convolution: three interpolation factors");
        $finish;
    end
    // A legal P keeps the RF sample stream valid; invalid input inserts zeros.
    always @(negedge clk) begin
        #0.001;
        if (rst_n && dout_valid) begin
            if (received < capture_limit) begin
                if (dout_i!==output_i[received] || dout_q!==output_q[received])
                    $fatal(1,"RRC MATLAB mismatch at word %0d: I=%h ref=%h",received,dout_i,output_i[received]);
                received=received+1;
            end else begin
                if (dout_i!==192'd0 || dout_q!==192'd0)
                    $fatal(1,"Unexpected RRC idle tail");
                idle_checks=idle_checks+1;
            end
        end
    end
endmodule
