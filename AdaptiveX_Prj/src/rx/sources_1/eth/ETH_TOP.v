`timescale 1ns / 1ps
`default_nettype none

// Port 0 restores Ethernet frames; port 1 sends constellation UDP with frame metadata.
module ETH_TOP(
    input  wire         clk_phy,
    input  wire         rst_n_phy,
    input  wire [3:0]   phy_ploy,
    input  wire [31:0]  phy_din,
    input  wire         phy_din_v,
    input  wire [5:0]   phy_din_width,
    input  wire         ber_enable,
    output wire [63:0]  ber_total_errors,
    output wire [63:0]  ber_total_bits,
    output wire         ber_window_full,
    input  wire [127:0] cone_i,
    input  wire [127:0] cone_q,
    input  wire         cone_v,
    input  wire [1:0]   cone_modulation,
    input  wire [31:0]  cone_frame_id,
    input  wire         mac_tx_0_clk,
    input  wire         mac_tx_0_tready,
    output wire [63:0]  mac_tx_0_tdata,
    output wire [7:0]   mac_tx_0_tkeep,
    output wire         mac_tx_0_tlast,
    output wire         mac_tx_0_tvalid,
    input  wire         mac_tx_1_clk,
    input  wire         mac_tx_1_tready,
    output wire [63:0]  mac_tx_1_tdata,
    output wire [7:0]   mac_tx_1_tkeep,
    output wire         mac_tx_1_tlast,
    output wire         mac_tx_1_tvalid
);
    wire [31:0] packet_errors, packet_bits;
    wire stat_request;
    wire phy_rst_n;
    wire cone_rst_n;
    wire mac_rst_n;
    wire [63:0] phy_dout;
    wire phy_dout_v;
    wire [31:0] constellation_dout_i;
    wire [31:0] constellation_dout_q;
    wire constellation_dout_v;
    wire [3:0] constellation_dout_p;
    wire [1:0] constellation_dout_m;
    wire [31:0] constellation_dout_frame;
    reg [31:0] constellation_i_d1, constellation_i_d2;
    reg [31:0] constellation_q_d1, constellation_q_d2;
    reg constellation_v_d1, constellation_v_d2;
    reg [3:0] constellation_p_d1, constellation_p_d2;
    reg [1:0] constellation_m_d1, constellation_m_d2;
    reg [31:0] constellation_frame_d1, constellation_frame_d2;

    Reset_Sync u_phy_reset(
        .clk(clk_phy), .arst_n(rst_n_phy), .rst_n(phy_rst_n)
    );
    Reset_Sync u_mac_reset(
        .clk(mac_tx_0_clk), .arst_n(rst_n_phy), .rst_n(mac_rst_n)
    );
    Reset_Sync u_cone_reset(
        .clk(mac_tx_1_clk), .arst_n(rst_n_phy), .rst_n(cone_rst_n)
    );

    Rx_BER_Monitor u_ber (
        .clk_phy(clk_phy), .rst_n_phy(phy_rst_n), .enable(ber_enable),
        .din(phy_din), .din_v(phy_din_v), .din_width(phy_din_width),
        .clk_eth(mac_tx_1_clk), .rst_n_eth(cone_rst_n), .packet_request(stat_request),
        .packet_errors(packet_errors), .packet_bits(packet_bits),
        .total_errors(ber_total_errors), .total_bits(ber_total_bits), .window_full(ber_window_full)
    );

    phy_Wto64 u_phy_Wto64(
        .clk        (clk_phy),
        .rst_n      (phy_rst_n),
        .din        (phy_din),
        .din_v      (phy_din_v),
        .din_width  (phy_din_width),
        .dout       (phy_dout),
        .dout_v     (phy_dout_v)
    );

    MAC_UNTT u_MAC_UNTT(
        .clk_phy         (clk_phy),
        .rst_n           (phy_rst_n),
        .rst_n_mac       (mac_rst_n),
        .phy_out_data    (phy_dout),
        .phy_out_v       (phy_dout_v),
        .tt_out_rdy      (),
        .mac_core_1_clk  (mac_tx_0_clk),
        .mac_tx_1_tdata  (mac_tx_0_tdata),
        .mac_tx_1_tkeep  (mac_tx_0_tkeep),
        .mac_tx_1_tlast  (mac_tx_0_tlast),
        .mac_tx_1_tvalid (mac_tx_0_tvalid),
        .mac_tx_1_tready (mac_tx_0_tready)
    );

    Constellation_Choose u_Constellation_Choose(
        .clk                 (clk_phy),
        .rst_n               (phy_rst_n),
        .phy_ploy            (phy_ploy),
        .cone_modulation     (cone_modulation),
        .cone_frame_id       (cone_frame_id),
        .Din_i               (cone_i),
        .Din_q               (cone_q),
        .Din_v               (cone_v),
        .Constellation_LEN_i (constellation_dout_i),
        .Constellation_LEN_q (constellation_dout_q),
        .Constellation_LEN_v (constellation_dout_v),
        .Constellation_LEN_ploy (constellation_dout_p),
        .Constellation_LEN_modulation (constellation_dout_m),
        .Constellation_LEN_frame_id (constellation_dout_frame)
    );

    always@(posedge clk_phy)begin
        if(!phy_rst_n)begin
            constellation_i_d1 <= 0;
            constellation_i_d2 <= 0;
            constellation_q_d1 <= 0;
            constellation_q_d2 <= 0;
            constellation_v_d1 <= 0;
            constellation_v_d2 <= 0;
            constellation_p_d1 <= 0;
            constellation_p_d2 <= 0;
            constellation_m_d1 <= 0;
            constellation_m_d2 <= 0;
            constellation_frame_d1 <= 0;
            constellation_frame_d2 <= 0;
        end else begin
            constellation_i_d1 <= constellation_dout_i;
            constellation_i_d2 <= constellation_i_d1;
            constellation_q_d1 <= constellation_dout_q;
            constellation_q_d2 <= constellation_q_d1;
            constellation_v_d1 <= constellation_dout_v;
            constellation_v_d2 <= constellation_v_d1;
            constellation_p_d1 <= constellation_dout_p;
            constellation_p_d2 <= constellation_p_d1;
            constellation_m_d1 <= constellation_dout_m;
            constellation_m_d2 <= constellation_m_d1;
            constellation_frame_d1 <= constellation_dout_frame;
            constellation_frame_d2 <= constellation_frame_d1;
        end
    end

    constellation_eth_jiemian u_constellation_eth_jiemian(
        .clk_phy    (clk_phy),
        .cone_i     (constellation_i_d2),
        .cone_q     (constellation_q_d2),
        .cone_v     (constellation_v_d2),
        .cone_ploy  (constellation_p_d2),
        .cone_modulation (constellation_m_d2),
        .cone_frame_id (constellation_frame_d2),
        .err_bit    (packet_errors),
        .all_bit    (packet_bits),
        .stat_request(stat_request),
        .clk_gen    (mac_tx_1_clk),
        .rst        (!cone_rst_n),
        .rst_phy    (!phy_rst_n),
        .gen_tready (mac_tx_1_tready),
        .gen_tdata  (mac_tx_1_tdata),
        .gen_tvalid (mac_tx_1_tvalid),
        .gen_tkeep  (mac_tx_1_tkeep),
        .gen_tlast  (mac_tx_1_tlast)
    );
endmodule
`default_nettype wire
