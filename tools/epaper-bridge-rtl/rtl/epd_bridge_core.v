// SPDX-License-Identifier: Apache-2.0
// Bridge datapath behind the DSI receiver: unpacker (rx_clk), line FIFO, and in
// the panel clock domain (clk) the panel timing, DC guard, watchdog and rails.
// Status outputs are all in the clk domain.
`default_nettype none
module epd_bridge_core #(
    parameter AW = 9,
    parameter BYTES = 200, HFP = 12, HSYNC = 2, HBP = 2,
    parameter VFP = 0, VSYNC = 1, VBP = 0, ROWS = 600, VTAIL = 1,
    parameter ROW_TO = 2048,
    parameter integer WD_GATE = 1023000, WD_RAILS = 3069000,
    parameter integer T_WAKE = 81840, T_UP_MIN = 20460, T_UP_MAX = 1023000, T_DOWN = 2046000,
    parameter integer DC_LIMIT = 1 << 25
) (
    input  wire        rx_clk,
    input  wire        rx_rst,
    input  wire        rx_valid,
    input  wire [31:0] rx_data,
    input  wire        line_start,
    input  wire        line_end,
    input  wire        frame_start,
    input  wire        line_crc_ok,
    input  wire        clk,
    input  wire        rst,
    output wire        sdclk,
    output wire        sdle,
    output wire        sdoe,
    output wire        sph,
    output wire [7:0]  sd,
    output wire        gdclk,
    output wire        gdsp,
    output wire        gdoe,
    input  wire        pmic_pg,
    output wire        pmic_wakeup,
    output wire        pmic_pwrup,
    output reg  [15:0] vcom_mv,
    output reg         vcom_upd,
    output reg         synced,
    output reg  [7:0]  last_seq,
    output reg  [7:0]  err_cnt,
    output reg  [7:0]  flt_cnt,
    output wire        rails_ok,
    output wire        pg_fault,
    output wire        wd_tripped,
    output wire        dc_trip,
    output wire signed [27:0] dc_acc
);
    wire        wr_en, fifo_ovf, fifo_re, fifo_empty, busy, done, abort, sd_strobe;
    wire [31:0] wr_data, fifo_q;
    wire [AW:0] wptr, rptr, f_base;
    wire        f_drive, f_pmic_on, f_vcom_set, acc_t, ref_t, row_t, flt_t, rx_synced;
    wire [9:0]  f_first, f_last;
    wire [15:0] f_vcom_mv, rx_err, rx_flt, tm_flt;
    wire [31:0] rx_seq;
    wire        drive_ok = rails_ok && !dc_trip;

    epd_unpack #(.AW(AW)) unpack (
        .clk(rx_clk), .rst(rx_rst),
        .rx_valid(rx_valid), .rx_data(rx_data), .line_start(line_start),
        .line_end(line_end), .frame_start(frame_start), .line_crc_ok(line_crc_ok),
        .drive_ok(drive_ok),
        .wr_en(wr_en), .wr_data(wr_data), .fifo_ovf(fifo_ovf), .fifo_wptr(wptr),
        .f_drive(f_drive), .f_pmic_on(f_pmic_on), .f_vcom_set(f_vcom_set),
        .f_first(f_first), .f_last(f_last), .f_vcom_mv(f_vcom_mv), .f_base(f_base),
        .acc_t(acc_t), .ref_t(ref_t), .row_t(row_t), .flt_t(flt_t),
        .synced(rx_synced), .last_seq(rx_seq), .err_cnt(rx_err), .flt_cnt(rx_flt)
    );

    epd_line_fifo #(.AW(AW), .DW(32)) fifo (
        .wclk(rx_clk), .wrst(rx_rst), .we(wr_en), .wd(wr_data),
        .full(), .ovf(fifo_ovf), .wptr(wptr),
        .rclk(clk), .rrst(rst), .re(fifo_re), .rd(fifo_q),
        .empty(fifo_empty), .rptr(rptr)
    );

    // Toggle events into clk. The bundles they qualify were stable before the toggle.
    reg  [3:0] t1, t2, t3;
    wire [3:0] ev = t2 ^ t3;
    wire acc = ev[3], refused = ev[2], row = ev[1], wflt = ev[0];
    wire go = acc && f_drive && drive_ok;
    always @(posedge clk) begin
        {t3, t2, t1} <= {t2, t1, acc_t, ref_t, row_t, flt_t};
        if (rst) {t3, t2, t1} <= 0;
    end

    epd_timing #(
        .AW(AW), .BYTES(BYTES), .HFP(HFP), .HSYNC(HSYNC), .HBP(HBP),
        .VFP(VFP), .VSYNC(VSYNC), .VBP(VBP), .ROWS(ROWS), .VTAIL(VTAIL), .ROW_TO(ROW_TO)
    ) timing (
        .clk(clk), .rst(rst), .go(go), .first(f_first), .last(f_last),
        .base(f_base), .row_ev(row), .fault_in(wflt), .abort(abort),
        .fifo_re(fifo_re), .fifo_q(fifo_q), .fifo_empty(fifo_empty), .fifo_rptr(rptr),
        .busy(busy), .done(done), .flt_cnt(tm_flt), .sdclk(sdclk), .sd_strobe(sd_strobe),
        .sdle(sdle), .sdoe(sdoe), .sph(sph), .sd(sd), .gdclk(gdclk), .gdsp(gdsp)
    );

    epd_dc_guard #(.LIMIT(DC_LIMIT)) dc (
        .clk(clk), .rst(rst), .strobe(sd_strobe), .sd(sd), .frame_done(done),
        .acc(dc_acc), .trip(dc_trip)
    );

    epd_rails #(
        .WD_GATE(WD_GATE), .WD_RAILS(WD_RAILS), .T_WAKE(T_WAKE),
        .T_UP_MIN(T_UP_MIN), .T_UP_MAX(T_UP_MAX), .T_DOWN(T_DOWN)
    ) rails (
        .clk(clk), .rst(rst), .acc(acc), .acc_pmic(f_pmic_on), .go(go),
        .refused(refused), .done(done), .pg(pmic_pg),
        .pmic_wakeup(pmic_wakeup), .pmic_pwrup(pmic_pwrup), .rails_ok(rails_ok),
        .gdoe(gdoe), .abort(abort), .pg_fault(pg_fault), .wd_tripped(wd_tripped)
    );

    // Status for the I2C register file, saturating 8-bit counters.
    reg [1:0] sy;
    reg [7:0] tm_last;
    always @(posedge clk) begin
        sy <= {sy[0], rx_synced};
        synced <= sy[1];
        vcom_upd <= 1'b0;
        if (acc) begin
            last_seq <= rx_seq[7:0];
            if (f_vcom_set) begin
                vcom_mv <= f_vcom_mv;
                vcom_upd <= 1'b1;
            end
        end
        if (refused) err_cnt <= rx_err[15:8] != 0 ? 8'hFF : rx_err[7:0];
        tm_last <= tm_flt[7:0];
        if ((wflt || (acc && f_drive && !drive_ok) || tm_flt[7:0] != tm_last) && flt_cnt != 8'hFF)
            flt_cnt <= flt_cnt + 1'b1;
        if (rst) begin
            sy <= 0; synced <= 1'b0; last_seq <= 0; err_cnt <= 0; flt_cnt <= 0;
            tm_last <= 0; vcom_mv <= 0; vcom_upd <= 1'b0;
        end
    end
endmodule
