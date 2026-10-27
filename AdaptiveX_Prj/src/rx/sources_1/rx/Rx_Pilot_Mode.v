`timescale 1ns / 1ps
`default_nettype none

// Identify M from the first data block's split pilot.
module Rx_Pilot_Mode (
    input wire clk,
    input wire rst_n,
    input wire [3:0] phy_ploy,
    input wire [127:0] din_i,
    input wire [127:0] din_q,
    input wire din_v,
    input wire din_pilot,
    input wire [2:0] din_blk,
    output reg [1:0] dout,
    output reg dout_v
);

    ////////////////////////// Declaration //////////////////////////
    localparam [2:0] IDLE         = 0;
    localparam [2:0] SUM          = 1;
    localparam [2:0] COMPLEX      = 2;
    localparam [2:0] WAIT_COMPLEX = 3;
    localparam [2:0] SCALE        = 4;
    localparam [2:0] WAIT_SCALE   = 5;
    localparam [2:0] DECIDE       = 6;

    reg [2:0] state;
    reg [1:0] product_idx;
    reg signed [16:0] a_i_pair0;
    reg signed [16:0] a_i_pair1;
    reg signed [16:0] a_q_pair0;
    reg signed [16:0] a_q_pair1;
    reg signed [16:0] b_i_pair0;
    reg signed [16:0] b_i_pair1;
    reg signed [16:0] b_q_pair0;
    reg signed [16:0] b_q_pair1;
    reg signed [17:0] a_i;
    reg signed [17:0] a_q;
    reg signed [17:0] b_i;
    reg signed [17:0] b_q;
    reg signed [35:0] product_ii;
    reg signed [35:0] product_qq;
    reg signed [35:0] product_iq;
    reg signed [36:0] z_i;
    reg signed [36:0] z_q;
    wire [36:0] z_q_abs;
    reg [51:0] boundary_lhs;
    reg [32:0] scale_low;
    reg [51:0] boundary_rhs;

    reg signed [26:0] mult_din_a;
    reg signed [17:0] mult_din_b;
    reg [2:0] mult_din_idx;
    reg mult_din_v;
    (* use_dsp = "yes" *) reg signed [44:0] mult_product;
    reg signed [44:0] mult_dout;
    reg [2:0] mult_idx_d0;
    reg [2:0] mult_idx_d1;
    reg mult_v_d0;
    reg mult_v_d1;

    assign z_q_abs = z_q[36] ? -z_q : z_q;

    ////////////////////////// Shared real multiply //////////////////////////
    always @(posedge clk) begin
        if (!rst_n) begin
            mult_product <= 0;
            mult_dout <= 0;
            mult_idx_d0 <= 0;
            mult_idx_d1 <= 0;
            mult_v_d0 <= 0;
            mult_v_d1 <= 0;
        end else begin
            mult_product <= mult_din_a * mult_din_b;
            mult_dout <= mult_product;
            mult_idx_d0 <= mult_din_idx;
            mult_idx_d1 <= mult_idx_d0;
            mult_v_d0 <= mult_din_v;
            mult_v_d1 <= mult_v_d0;
        end
    end

    ////////////////////////// Pilot calculation //////////////////////////
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            product_idx <= 0;
            a_i_pair0 <= 0;
            a_i_pair1 <= 0;
            a_q_pair0 <= 0;
            a_q_pair1 <= 0;
            b_i_pair0 <= 0;
            b_i_pair1 <= 0;
            b_q_pair0 <= 0;
            b_q_pair1 <= 0;
            a_i <= 0;
            a_q <= 0;
            b_i <= 0;
            b_q <= 0;
            product_ii <= 0;
            product_qq <= 0;
            product_iq <= 0;
            z_i <= 0;
            z_q <= 0;
            scale_low <= 0;
            boundary_lhs <= 0;
            boundary_rhs <= 0;
            mult_din_a <= 0;
            mult_din_b <= 0;
            mult_din_idx <= 0;
            mult_din_v <= 0;
            dout <= 2'd3;
            dout_v <= 0;
        end else begin
            mult_din_v <= 0;
            dout_v <= 0;

            case (state)
                IDLE:
                if (din_v && din_pilot && din_blk == 0) begin
                    a_i_pair1 <= 0;
                    a_q_pair1 <= 0;
                    b_i_pair1 <= 0;
                    b_q_pair1 <= 0;
                    case (phy_ploy)
                        2: begin
                            a_i_pair0 <= $signed(din_i[15:0]);
                            a_q_pair0 <= $signed(din_q[15:0]);
                            b_i_pair0 <= $signed(din_i[31:16]);
                            b_q_pair0 <= $signed(din_q[31:16]);
                        end
                        4: begin
                            a_i_pair0 <= $signed(din_i[15:0]) + $signed(din_i[31:16]);
                            a_q_pair0 <= $signed(din_q[15:0]) + $signed(din_q[31:16]);
                            b_i_pair0 <= $signed(din_i[47:32]) + $signed(din_i[63:48]);
                            b_q_pair0 <= $signed(din_q[47:32]) + $signed(din_q[63:48]);
                        end
                        8: begin
                            a_i_pair0 <= $signed(din_i[15:0]) + $signed(din_i[31:16]);
                            a_q_pair0 <= $signed(din_q[15:0]) + $signed(din_q[31:16]);
                            a_i_pair1 <= $signed(din_i[47:32]) + $signed(din_i[63:48]);
                            a_q_pair1 <= $signed(din_q[47:32]) + $signed(din_q[63:48]);
                            b_i_pair0 <= $signed(din_i[79:64]) + $signed(din_i[95:80]);
                            b_q_pair0 <= $signed(din_q[79:64]) + $signed(din_q[95:80]);
                            b_i_pair1 <= $signed(din_i[111:96]) + $signed(din_i[127:112]);
                            b_q_pair1 <= $signed(din_q[111:96]) + $signed(din_q[127:112]);
                        end
                        default: begin
                            a_i_pair0 <= 0;
                            a_q_pair0 <= 0;
                            b_i_pair0 <= 0;
                            b_q_pair0 <= 0;
                        end
                    endcase
                    if (phy_ploy == 2 || phy_ploy == 4 || phy_ploy == 8) state <= SUM;
                end

                SUM: begin
                    a_i <= $signed(a_i_pair0) + $signed(a_i_pair1);
                    a_q <= $signed(a_q_pair0) + $signed(a_q_pair1);
                    b_i <= $signed(b_i_pair0) + $signed(b_i_pair1);
                    b_q <= $signed(b_q_pair0) + $signed(b_q_pair1);
                    product_idx <= 0;
                    state <= COMPLEX;
                end

                COMPLEX: begin
                    mult_din_v   <= 1;
                    mult_din_idx <= {1'b0, product_idx};
                    case (product_idx)
                        0: begin
                            mult_din_a <= a_i;
                            mult_din_b <= b_i;
                        end
                        1: begin
                            mult_din_a <= a_q;
                            mult_din_b <= b_q;
                        end
                        2: begin
                            mult_din_a <= a_i;
                            mult_din_b <= b_q;
                        end
                        3: begin
                            mult_din_a <= a_q;
                            mult_din_b <= b_i;
                        end
                    endcase
                    if (product_idx == 3) state <= WAIT_COMPLEX;
                    else product_idx <= product_idx + 1'b1;
                end

                WAIT_COMPLEX: begin
                    if (mult_v_d1 && mult_idx_d1 == 3) begin
                        z_i <= $signed(product_ii) + $signed(product_qq);
                        z_q <= $signed(product_iq) - $signed(mult_dout[35:0]);
                        product_idx <= 0;
                        state <= SCALE;
                    end
                end

                SCALE: begin
                    // 24576*a = 3*a*8192; register before the comparison.
                    if (product_idx == 0) boundary_lhs <= ({15'd0, z_i} << 14) + ({15'd0, z_i} << 13);
                    mult_din_v <= 1;
                    mult_din_idx <= product_idx == 0 ? 3'd4 : 3'd5;
                    mult_din_a <= product_idx == 0 ? $signed({9'd0, z_q_abs[17:0]}) : $signed({8'd0, z_q_abs[36:18]});
                    mult_din_b <= 18'sd14189;
                    if (product_idx == 1) state <= WAIT_SCALE;
                    else product_idx <= 1;
                end

                WAIT_SCALE:
                if (mult_v_d1 && mult_idx_d1 == 5) begin
                    // Positive chunk products fit exactly in 33/34 bits.
                    boundary_rhs <= {mult_dout[33:0], 18'd0} + {19'd0, scale_low};
                    state <= DECIDE;
                end

                DECIDE: begin
                    if (!z_i[36] && boundary_lhs >= boundary_rhs) dout <= 2'd0;
                    else dout <= z_q[36] ? 2'd2 : 2'd1;
                    dout_v <= 1;
                    state  <= IDLE;
                end

                default: state <= IDLE;
            endcase

            if (mult_v_d1) begin
                case (mult_idx_d1)
                    0: product_ii <= mult_dout[35:0];
                    1: product_qq <= mult_dout[35:0];
                    2: product_iq <= mult_dout[35:0];
                    4: scale_low <= mult_dout[32:0];
                endcase
            end
        end
    end

endmodule
`default_nettype wire
