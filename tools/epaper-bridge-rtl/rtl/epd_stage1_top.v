// SPDX-License-Identifier: Apache-2.0
// Stage-1 image: the I2C/APB bridge and user registers only. It proves the
// reflash loop on the board. Every panel and PMIC output is driven low (PMIC
// enables inactive, no clocks); nothing is driven from the DSI link.
// Same port names as epd_bridge_top, so one pin constraint file serves both.
`default_nettype none
module epd_stage1_top #(
    parameter integer DEADMAN_CLKS = 2046000000   // 100 s; 0 disables
) (
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
    output wire        pmic_pwrup
);
    wire clk, rst;
    pgc_osc osc (.clk(clk));
    por_sync por (.clk(clk), .rst(rst));

    assign {epd_sdclk, epd_sdle, epd_sdoe, epd_sph, epd_sd, epd_gdclk, epd_gdsp, epd_gdoe,
            pmic_wakeup, pmic_pwrup} = 0;

    wire scl_oe, sda_oe, psel, penable, pwrite, pready;
    wire [4:0] paddr;
    wire [7:0] pwdata, prdata;
    cfg_bridge #(.FW_VERSION(8'h81), .LINK_ID(8'hD0), .DEADMAN_CLKS(DEADMAN_CLKS)) cfg (
        .clk(clk), .rst(rst), .scl_i(i2c_scl), .sda_i(i2c_sda), .scl_oe(scl_oe), .sda_oe(sda_oe),
        .synced(1'b0), .rails_ok(1'b0), .pg_fault(1'b0), .dc_trip(1'b0), .wd_tripped(1'b0),
        .err_cnt(8'd0), .flt_cnt(8'd0), .last_seq(8'd0), .dc_hi(16'd0),
        .psel(psel), .penable(penable), .pwrite(pwrite), .paddr(paddr),
        .pwdata(pwdata), .prdata(prdata), .pready(pready)
    );
    pgc_ccs_apb ccs (
        .clk(clk), .rst_n(!rst), .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata), .prdata(prdata), .pready(pready)
    );
    assign i2c_scl = scl_oe ? 1'b0 : 1'bz;
    assign i2c_sda = sda_oe ? 1'b0 : 1'bz;
endmodule
