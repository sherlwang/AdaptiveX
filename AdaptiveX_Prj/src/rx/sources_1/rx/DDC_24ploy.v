`timescale 1ns / 1ps
`default_nettype none

// 24ploy real input to complex baseband, signed 16q13.
module DDC_24ploy #(
    parameter integer INPUT_FRAC = 13,
    parameter integer ENABLE_ILA = 1
) (
    input wire clk,
    input wire rst_n,
    input wire [24 * 16 - 1:0] din,
    input wire din_v,
    output wire [24 * 16 - 1:0] dout_i,
    output wire [24 * 16 - 1:0] dout_q,
    output wire dout_v
);

    reg [11:0] phase_base;
    reg [2:0] valid_pipe;
    reg [23:0] adc_clk_cnt;
    genvar lane;

    ////////////////////////// Logic //////////////////////////

    function signed [15:0] cos_q14;
        input [8:0] phase;
        reg [7:0] a;
        reg signed [15:0] mag;
        begin
            if (phase[7]) a = 8'd128 - {1'b0, phase[6:0]};
            else a = {1'b0, phase[6:0]};
            case (a)
                8'd0: mag = 16'sd16384;
                8'd1: mag = 16'sd16383;
                8'd2: mag = 16'sd16379;
                8'd3: mag = 16'sd16373;
                8'd4: mag = 16'sd16364;
                8'd5: mag = 16'sd16353;
                8'd6: mag = 16'sd16340;
                8'd7: mag = 16'sd16324;
                8'd8: mag = 16'sd16305;
                8'd9: mag = 16'sd16284;
                8'd10: mag = 16'sd16261;
                8'd11: mag = 16'sd16235;
                8'd12: mag = 16'sd16207;
                8'd13: mag = 16'sd16176;
                8'd14: mag = 16'sd16143;
                8'd15: mag = 16'sd16107;
                8'd16: mag = 16'sd16069;
                8'd17: mag = 16'sd16029;
                8'd18: mag = 16'sd15986;
                8'd19: mag = 16'sd15941;
                8'd20: mag = 16'sd15893;
                8'd21: mag = 16'sd15843;
                8'd22: mag = 16'sd15791;
                8'd23: mag = 16'sd15736;
                8'd24: mag = 16'sd15679;
                8'd25: mag = 16'sd15619;
                8'd26: mag = 16'sd15557;
                8'd27: mag = 16'sd15493;
                8'd28: mag = 16'sd15426;
                8'd29: mag = 16'sd15357;
                8'd30: mag = 16'sd15286;
                8'd31: mag = 16'sd15213;
                8'd32: mag = 16'sd15137;
                8'd33: mag = 16'sd15059;
                8'd34: mag = 16'sd14978;
                8'd35: mag = 16'sd14896;
                8'd36: mag = 16'sd14811;
                8'd37: mag = 16'sd14724;
                8'd38: mag = 16'sd14635;
                8'd39: mag = 16'sd14543;
                8'd40: mag = 16'sd14449;
                8'd41: mag = 16'sd14354;
                8'd42: mag = 16'sd14256;
                8'd43: mag = 16'sd14155;
                8'd44: mag = 16'sd14053;
                8'd45: mag = 16'sd13949;
                8'd46: mag = 16'sd13842;
                8'd47: mag = 16'sd13733;
                8'd48: mag = 16'sd13623;
                8'd49: mag = 16'sd13510;
                8'd50: mag = 16'sd13395;
                8'd51: mag = 16'sd13279;
                8'd52: mag = 16'sd13160;
                8'd53: mag = 16'sd13039;
                8'd54: mag = 16'sd12916;
                8'd55: mag = 16'sd12792;
                8'd56: mag = 16'sd12665;
                8'd57: mag = 16'sd12537;
                8'd58: mag = 16'sd12406;
                8'd59: mag = 16'sd12274;
                8'd60: mag = 16'sd12140;
                8'd61: mag = 16'sd12004;
                8'd62: mag = 16'sd11866;
                8'd63: mag = 16'sd11727;
                8'd64: mag = 16'sd11585;
                8'd65: mag = 16'sd11442;
                8'd66: mag = 16'sd11297;
                8'd67: mag = 16'sd11151;
                8'd68: mag = 16'sd11003;
                8'd69: mag = 16'sd10853;
                8'd70: mag = 16'sd10702;
                8'd71: mag = 16'sd10549;
                8'd72: mag = 16'sd10394;
                8'd73: mag = 16'sd10238;
                8'd74: mag = 16'sd10080;
                8'd75: mag = 16'sd9921;
                8'd76: mag = 16'sd9760;
                8'd77: mag = 16'sd9598;
                8'd78: mag = 16'sd9434;
                8'd79: mag = 16'sd9269;
                8'd80: mag = 16'sd9102;
                8'd81: mag = 16'sd8935;
                8'd82: mag = 16'sd8765;
                8'd83: mag = 16'sd8595;
                8'd84: mag = 16'sd8423;
                8'd85: mag = 16'sd8250;
                8'd86: mag = 16'sd8076;
                8'd87: mag = 16'sd7900;
                8'd88: mag = 16'sd7723;
                8'd89: mag = 16'sd7545;
                8'd90: mag = 16'sd7366;
                8'd91: mag = 16'sd7186;
                8'd92: mag = 16'sd7005;
                8'd93: mag = 16'sd6823;
                8'd94: mag = 16'sd6639;
                8'd95: mag = 16'sd6455;
                8'd96: mag = 16'sd6270;
                8'd97: mag = 16'sd6084;
                8'd98: mag = 16'sd5897;
                8'd99: mag = 16'sd5708;
                8'd100: mag = 16'sd5520;
                8'd101: mag = 16'sd5330;
                8'd102: mag = 16'sd5139;
                8'd103: mag = 16'sd4948;
                8'd104: mag = 16'sd4756;
                8'd105: mag = 16'sd4563;
                8'd106: mag = 16'sd4370;
                8'd107: mag = 16'sd4176;
                8'd108: mag = 16'sd3981;
                8'd109: mag = 16'sd3786;
                8'd110: mag = 16'sd3590;
                8'd111: mag = 16'sd3393;
                8'd112: mag = 16'sd3196;
                8'd113: mag = 16'sd2999;
                8'd114: mag = 16'sd2801;
                8'd115: mag = 16'sd2603;
                8'd116: mag = 16'sd2404;
                8'd117: mag = 16'sd2205;
                8'd118: mag = 16'sd2006;
                8'd119: mag = 16'sd1806;
                8'd120: mag = 16'sd1606;
                8'd121: mag = 16'sd1406;
                8'd122: mag = 16'sd1205;
                8'd123: mag = 16'sd1005;
                8'd124: mag = 16'sd804;
                8'd125: mag = 16'sd603;
                8'd126: mag = 16'sd402;
                8'd127: mag = 16'sd201;
                8'd128: mag = 16'sd0;
                default: mag = 16'sd0;
            endcase
            if (phase[8] ^ phase[7]) cos_q14 = -mag;
            else cos_q14 = mag;
        end
    endfunction

    function signed [15:0] sat16;
        input signed [31:0] product;
        reg signed [31:0] scaled;
        begin
            scaled = product >>> INPUT_FRAC;
            if (scaled > 32'sd32767) sat16 = 16'sd32767;
            else if (scaled < -32'sd32768) sat16 = -16'sd32768;
            else sat16 = scaled[15:0];
        end
    endfunction
    assign dout_v = valid_pipe[2];

    always @(posedge clk) begin
        if (!rst_n) begin
            phase_base <= 12'd0;
            valid_pipe <= 3'b000;
            adc_clk_cnt <= 24'd0;
        end else begin
            valid_pipe <= {valid_pipe[1:0], din_v};
            if (din_v) begin
                phase_base <= phase_base + 12'd3520;
                adc_clk_cnt <= adc_clk_cnt + 24'd1;
            end
        end
    end

    generate
        for (lane = 0; lane < 24; lane = lane + 1) begin : g_lane
            localparam [11:0] LANE_PHASE = lane * 1000;
            wire [11:0] this_phase;
            reg signed [15:0] sample_d1;
            reg [8:0] phase_d1;
            reg signed [31:0] product_i_d2;
            reg signed [31:0] product_q_d2;
            reg signed [15:0] result_i_d3;
            reg signed [15:0] result_q_d3;
            assign this_phase = phase_base + LANE_PHASE;
            always @(posedge clk) begin
                if (!rst_n) begin
                    sample_d1 <= 16'sd0;
                    phase_d1 <= 9'd0;
                    product_i_d2 <= 32'sd0;
                    product_q_d2 <= 32'sd0;
                    result_i_d3 <= 16'sd0;
                    result_q_d3 <= 16'sd0;
                end else begin
                    sample_d1 <= $signed(din[lane*16+:16]);
                    phase_d1 <= this_phase[11:3];
                    product_i_d2 <= sample_d1 * cos_q14(phase_d1);
                    product_q_d2 <= sample_d1 * cos_q14(phase_d1 + 9'd128);
                    result_i_d3 <= sat16(product_i_d2);
                    result_q_d3 <= sat16(product_q_d2);
                end
            end
            assign dout_i[lane*16+:16] = result_i_d3;
            assign dout_q[lane*16+:16] = result_q_d3;
        end
    endgenerate


endmodule
`default_nettype wire
