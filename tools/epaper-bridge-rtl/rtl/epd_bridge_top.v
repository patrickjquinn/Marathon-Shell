// SPDX-License-Identifier: Apache-2.0
// MP01 e-paper dumb bridge: DSI receiver + bridge core.
// px_clk: free-running, >= 3x the in-burst DSI pixel rate. epd_clk: panel
// clock, <= 25 MHz (SDCLK = epd_clk, cycle >= 40 ns).
`default_nettype none
module epd_bridge_top (
    input  wire        rst_n,
    input  wire        px_clk,
    input  wire        epd_clk,
    input  wire        dsi_ck_p,
    input  wire        dsi_ck_n,
    input  wire [3:0]  dsi_d_p,
    input  wire [3:0]  dsi_d_n,
    input  wire [1:0]  dsi_lp_ck,
    input  wire [7:0]  dsi_lp_d,
    output wire        epd_sdclk,
    output wire        epd_sdle,
    output wire        epd_sdoe,
    output wire        epd_sph,
    output wire [7:0]  epd_sd,
    output wire        epd_gdclk,
    output wire        epd_gdsp,
    output wire        epd_gdoe,
    output wire        pmic_en,
    output wire [15:0] vcom_mv,
    output wire        vcom_upd,
    output wire        synced,
    output wire [31:0] last_seq,
    output wire [15:0] err_cnt,
    output wire [15:0] wflt_cnt,
    output wire [15:0] rflt_cnt
);
    reg [1:0] px_rs, epd_rs;
    always @(posedge px_clk or negedge rst_n)
        if (!rst_n) px_rs <= 2'b11; else px_rs <= {px_rs[0], 1'b0};
    always @(posedge epd_clk or negedge rst_n)
        if (!rst_n) epd_rs <= 2'b11; else epd_rs <= {epd_rs[0], 1'b0};

    wire        px_valid, line_start, line_end, frame_start, line_crc_ok;
    wire [23:0] px_data;

    dphy_rx_stub rx (
        .ck_p(dsi_ck_p), .ck_n(dsi_ck_n), .d_p(dsi_d_p), .d_n(dsi_d_n),
        .lp_ck(dsi_lp_ck), .lp_d(dsi_lp_d), .px_clk(px_clk), .rst(px_rs[1]),
        .px_valid(px_valid), .px_data(px_data), .line_start(line_start),
        .line_end(line_end), .frame_start(frame_start), .line_crc_ok(line_crc_ok)
    );

    epd_bridge_core core (
        .px_clk(px_clk), .px_rst(px_rs[1]), .px_valid(px_valid), .px_data(px_data),
        .line_start(line_start), .line_end(line_end), .frame_start(frame_start),
        .line_crc_ok(line_crc_ok), .epd_clk(epd_clk), .epd_rst(epd_rs[1]),
        .sdclk(epd_sdclk), .sdle(epd_sdle), .sdoe(epd_sdoe), .sph(epd_sph), .sd(epd_sd),
        .gdclk(epd_gdclk), .gdsp(epd_gdsp), .gdoe(epd_gdoe),
        .pmic_en(pmic_en), .vcom_mv(vcom_mv), .vcom_upd(vcom_upd),
        .synced(synced), .last_seq(last_seq), .err_cnt(err_cnt),
        .wflt_cnt(wflt_cnt), .rflt_cnt(rflt_cnt)
    );
endmodule
