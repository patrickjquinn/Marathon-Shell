// SPDX-License-Identifier: Apache-2.0
// Bridge datapath behind the DSI receiver: unpacker (px_clk), line FIFO,
// panel timing, watchdog and PMIC/VCOM control (epd_clk).
// Status domains: synced, last_seq, err_cnt, wflt_cnt are px_clk; rflt_cnt is
// epd_clk. An I2C slave reading them needs its own synchronisers.
`default_nettype none
module epd_bridge_core #(
    parameter AW = 11,
    parameter BYTES = 200, HFP = 12, HSYNC = 2, HBP = 2,
    parameter VFP = 0, VSYNC = 1, VBP = 0, ROWS = 600, VTAIL = 1,
    parameter WD_CLKS = 470588,         // 2 frame periods at 85 Hz, epd_clk 20 MHz
    parameter PMIC_OFF_CLKS = 2000000   // 100 ms at 20 MHz
) (
    input  wire        px_clk,
    input  wire        px_rst,
    input  wire        px_valid,
    input  wire [23:0] px_data,
    input  wire        line_start,
    input  wire        line_end,
    input  wire        frame_start,
    input  wire        line_crc_ok,
    input  wire        epd_clk,
    input  wire        epd_rst,
    output wire        sdclk,
    output wire        sdle,
    output wire        sdoe,
    output wire        sph,
    output wire [7:0]  sd,
    output wire        gdclk,
    output wire        gdsp,
    output wire        gdoe,
    output reg         pmic_en,
    output reg  [15:0] vcom_mv,
    output reg         vcom_upd,
    output wire        synced,
    output wire [31:0] last_seq,
    output wire [15:0] err_cnt,
    output wire [15:0] wflt_cnt,
    output wire [15:0] rflt_cnt
);
    wire        wr_en, fifo_ovf, fifo_re, fifo_empty, busy, done;
    wire [7:0]  wr_data, fifo_q;
    wire [AW:0] wptr, rptr, f_base;
    wire        f_drive, f_pmic_on, f_vcom_set, acc_t, ref_t, go_t, flt_t;
    wire [9:0]  f_first, f_last;
    wire [15:0] f_vcom_mv;

    epd_unpack #(.AW(AW)) unpack (
        .clk(px_clk), .rst(px_rst),
        .px_valid(px_valid), .px_data(px_data), .line_start(line_start),
        .line_end(line_end), .frame_start(frame_start), .line_crc_ok(line_crc_ok),
        .wr_en(wr_en), .wr_data(wr_data), .fifo_ovf(fifo_ovf), .fifo_wptr(wptr),
        .f_drive(f_drive), .f_pmic_on(f_pmic_on), .f_vcom_set(f_vcom_set),
        .f_first(f_first), .f_last(f_last), .f_vcom_mv(f_vcom_mv), .f_base(f_base),
        .acc_t(acc_t), .ref_t(ref_t), .go_t(go_t), .flt_t(flt_t),
        .synced(synced), .last_seq(last_seq), .err_cnt(err_cnt), .flt_cnt(wflt_cnt)
    );

    epd_line_fifo #(.AW(AW)) fifo (
        .wclk(px_clk), .wrst(px_rst), .we(wr_en), .wd(wr_data),
        .full(), .ovf(fifo_ovf), .wptr(wptr),
        .rclk(epd_clk), .rrst(epd_rst), .re(fifo_re), .rd(fifo_q),
        .empty(fifo_empty), .udf(), .rptr(rptr)
    );

    reg  [3:0] t1, t2, t3;
    wire [3:0] ev = t2 ^ t3;
    wire acc = ev[3], refused = ev[2], go = ev[1], wflt = ev[0];
    always @(posedge epd_clk) begin
        {t3, t2, t1} <= {t2, t1, acc_t, ref_t, go_t, flt_t};
        if (epd_rst) {t3, t2, t1} <= 0;
    end

    epd_timing #(
        .AW(AW), .BYTES(BYTES), .HFP(HFP), .HSYNC(HSYNC), .HBP(HBP),
        .VFP(VFP), .VSYNC(VSYNC), .VBP(VBP), .ROWS(ROWS), .VTAIL(VTAIL)
    ) timing (
        .clk(epd_clk), .rst(epd_rst), .go(go), .first(f_first), .last(f_last),
        .base(f_base), .fault_in(wflt), .fifo_re(fifo_re), .fifo_q(fifo_q),
        .fifo_empty(fifo_empty), .fifo_rptr(rptr), .busy(busy), .done(done),
        .flt_cnt(rflt_cnt), .sdclk(sdclk), .sdle(sdle), .sdoe(sdoe), .sph(sph),
        .sd(sd), .gdclk(gdclk), .gdsp(gdsp)
    );

    // Only sequence-advancing frames feed the watchdog: a stuck RESYNC buffer
    // must not keep the rails up.
    localparam WD_MAX = WD_CLKS + PMIC_OFF_CLKS;
    reg [$clog2(WD_MAX+1)-1:0] wd;
    reg gd_arm, off_after;
    assign gdoe = gd_arm;
    always @(posedge epd_clk) begin
        vcom_upd <= 1'b0;
        if (wd != WD_MAX) wd <= wd + 1'b1;
        if (wd == WD_CLKS || refused) gd_arm <= 1'b0;
        if (wd == WD_MAX) pmic_en <= 1'b0;
        if (done && off_after) begin
            pmic_en <= 1'b0;
            off_after <= 1'b0;
        end
        if (go) gd_arm <= 1'b1;
        if (acc) begin
            wd <= 0;
            if (f_vcom_set) begin
                vcom_mv <= f_vcom_mv;
                vcom_upd <= 1'b1;
            end
            if (f_pmic_on) begin
                pmic_en <= 1'b1;
                off_after <= 1'b0;
            end else if (f_drive)
                off_after <= 1'b1;
            else
                pmic_en <= 1'b0;
        end
        if (epd_rst) begin
            wd <= WD_MAX; gd_arm <= 1'b0; off_after <= 1'b0;
            pmic_en <= 1'b0; vcom_mv <= 0; vcom_upd <= 1'b0;
        end
    end
endmodule
