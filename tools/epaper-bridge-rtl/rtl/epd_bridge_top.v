// SPDX-License-Identifier: Apache-2.0
// MP01 e-paper direct-drive bridge: DSI receiver, bridge core, I2C/APB
// configuration bridge. One clock of our own (internal oscillator, 20.46 MHz)
// runs the panel, I2C, APB, watchdog and rails; rx_clk comes from the receiver.
// Every output is inactive from configuration until the first accepted frame.
// OUT_EN is for staged bring-up: bit 0 lets the panel outputs through, bit 1 the
// PMIC enables; a cleared bit holds those pins low whatever the datapath does.
`default_nettype none
module epd_bridge_top #(
    parameter [7:0]  FW_VERSION = 8'h82,
    parameter integer DEADMAN_CLKS = 2046000000,  // 100 s; 0 disables
    parameter [1:0]  OUT_EN = 2'b11
) (
    input  wire        dsi_ck_p,
    input  wire        dsi_ck_n,
    input  wire [3:0]  dsi_d_p,
    input  wire [3:0]  dsi_d_n,
    inout  wire        i2c_scl,
    inout  wire        i2c_sda,
    output wire        epd_sdclk,
    output wire        epd_sdle,
    output wire        epd_sdoe,
    output wire        epd_sph,
    output wire [7:0]  epd_sd,
    output wire        epd_gdclk,
    output wire        epd_gdsp,
    output wire        epd_gdoe,
    output wire        pmic_wakeup,
    output wire        pmic_pwrup,
    input  wire        pmic_pg
);
    wire clk, rst, rx_clk;
    pgc_osc osc (.clk(clk));
    por_sync por (.clk(clk), .rst(rst));

    wire        rx_valid, line_start, line_end, frame_start, line_crc_ok;
    wire [31:0] rx_data;
    dphy_rx_stub rx (
        .ck_p(dsi_ck_p), .ck_n(dsi_ck_n), .d_p(dsi_d_p), .d_n(dsi_d_n),
        .clk_ref(clk), .rst(rst), .rx_clk(rx_clk), .rx_valid(rx_valid), .rx_data(rx_data),
        .line_start(line_start), .line_end(line_end), .frame_start(frame_start),
        .line_crc_ok(line_crc_ok)
    );
    reg [1:0] rx_rs;
    always @(posedge rx_clk or posedge rst)
        if (rst) rx_rs <= 2'b11; else rx_rs <= {rx_rs[0], 1'b0};

    wire        sdclk, sdle, sdoe, sph, gdclk, gdsp, gdoe, wake, pwrup;
    wire [7:0]  sd;
    assign {epd_sdclk, epd_sdle, epd_sdoe, epd_sph, epd_sd, epd_gdclk, epd_gdsp, epd_gdoe} =
        OUT_EN[0] ? {sdclk, sdle, sdoe, sph, sd, gdclk, gdsp, gdoe} : 15'd0;
    assign {pmic_wakeup, pmic_pwrup} = OUT_EN[1] ? {wake, pwrup} : 2'd0;

    wire        synced, rails_ok, pg_fault, wd_tripped, dc_trip;
    wire [7:0]  last_seq, err_cnt, flt_cnt;
    wire signed [27:0] dc_acc;
    epd_bridge_core core (
        .rx_clk(rx_clk), .rx_rst(rx_rs[1]), .rx_valid(rx_valid), .rx_data(rx_data),
        .line_start(line_start), .line_end(line_end), .frame_start(frame_start),
        .line_crc_ok(line_crc_ok), .clk(clk), .rst(rst),
        .sdclk(sdclk), .sdle(sdle), .sdoe(sdoe), .sph(sph), .sd(sd),
        .gdclk(gdclk), .gdsp(gdsp), .gdoe(gdoe),
        .pmic_pg(pmic_pg & OUT_EN[1]), .pmic_wakeup(wake), .pmic_pwrup(pwrup),
        .vcom_mv(), .vcom_upd(), .synced(synced), .last_seq(last_seq),
        .err_cnt(err_cnt), .flt_cnt(flt_cnt), .rails_ok(rails_ok), .pg_fault(pg_fault),
        .wd_tripped(wd_tripped), .dc_trip(dc_trip), .dc_acc(dc_acc)
    );

    wire scl_oe, sda_oe, psel, penable, pwrite, pready;
    wire [4:0] paddr;
    wire [7:0] pwdata, prdata;
    cfg_bridge #(.FW_VERSION(FW_VERSION), .LINK_ID(8'hD2), .DEADMAN_CLKS(DEADMAN_CLKS)) cfg (
        .clk(clk), .rst(rst), .scl_i(i2c_scl), .sda_i(i2c_sda), .scl_oe(scl_oe), .sda_oe(sda_oe),
        .synced(synced), .rails_ok(rails_ok), .pg_fault(pg_fault), .dc_trip(dc_trip),
        .wd_tripped(wd_tripped), .err_cnt(err_cnt), .flt_cnt(flt_cnt), .last_seq(last_seq),
        .dc_hi(dc_acc[27:12]), .psel(psel), .penable(penable), .pwrite(pwrite), .paddr(paddr),
        .pwdata(pwdata), .prdata(prdata), .pready(pready)
    );
    pgc_ccs_apb ccs (
        .clk(clk), .rst_n(!rst), .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata), .prdata(prdata), .pready(pready)
    );
    assign i2c_scl = scl_oe ? 1'b0 : 1'bz;
    assign i2c_sda = sda_oe ? 1'b0 : 1'bz;
endmodule
