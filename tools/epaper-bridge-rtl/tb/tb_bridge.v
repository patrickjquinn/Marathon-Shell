// SPDX-License-Identifier: Apache-2.0
// Testbench for epd_bridge_core: replays link v2 DSI frames (stock 800x600 mode)
// from $readmemh files as 32-bit payload words at the stock 60 Hz line rate,
// models the source driver's shift register and latch and a PMIC with a
// power-good delay, and checks every latched row against the input.
//   +frames=<hex> +nframes=<n> [+meta=<hex>]
// Without +meta (observe mode) it only checks that frames the bridge chose to
// drive match their input.
`timescale 1ns / 1ps
`default_nettype none
module tb_bridge;
    localparam MAXF = 32, WK = 58, FW = 600 * WK;
    localparam BYTES = 200, HFP = 12, HSYNC = 2, HBP = 2;
    localparam VFP = 0, VSYNC = 1, VBP = 0, ROWS = 600, VTAIL = 1;
    localparam HTOTAL = HFP + HSYNC + HBP + BYTES, VTOTAL = VFP + VSYNC + VBP + ROWS + VTAIL;
    localparam real TSYS = 48.876, TRX = 38.46;      // 20.46 MHz OSC; 26 MHz byte clock
    localparam integer LINE_RX = 642, VBL = 20, LATE = 1000;   // 60 Hz stock line
    localparam integer ROW_TO = 2048;
    localparam integer WD_GATE = 818400, WD_RAILS = 1227600;   // 40 / 60 ms
    localparam integer T_WAKE = 20460, T_UP_MIN = 4092, T_UP_MAX = 409200, T_DOWN = 102300;
    localparam real T_PG = 3e6;                                // PMIC rails settle, ns
    localparam integer DC_LIMIT = 1500000;
    localparam TIMING = 15;

    `include "crc16_mcrf4xx.vh"

    reg clk = 0, rx_clk = 0;
    always #(TSYS / 2) clk = ~clk;
    always #(TRX / 2) rx_clk = ~rx_clk;

    reg rst = 1, rx_rst = 1;
    reg rx_valid = 0, line_start = 0, line_end = 0, frame_start = 0, line_crc_ok = 1;
    reg [31:0] rx_data = 0;
    reg pmic_pg = 0;
    wire sdclk, sdle, sdoe, sph, gdclk, gdsp, gdoe, wake, pwrup, vcom_upd, synced;
    wire rails_ok, pg_fault, wd_tripped, dc_trip;
    wire [7:0] sd, last_seq, err_cnt, flt_cnt;
    wire [15:0] vcom_mv;
    wire signed [27:0] dc_acc;

    epd_bridge_core #(
        .BYTES(BYTES), .HFP(HFP), .HSYNC(HSYNC), .HBP(HBP),
        .VFP(VFP), .VSYNC(VSYNC), .VBP(VBP), .ROWS(ROWS), .VTAIL(VTAIL), .ROW_TO(ROW_TO),
        .WD_GATE(WD_GATE), .WD_RAILS(WD_RAILS), .T_WAKE(T_WAKE), .T_UP_MIN(T_UP_MIN),
        .T_UP_MAX(T_UP_MAX), .T_DOWN(T_DOWN), .DC_LIMIT(DC_LIMIT)
    ) dut (
        .rx_clk(rx_clk), .rx_rst(rx_rst), .rx_valid(rx_valid), .rx_data(rx_data),
        .line_start(line_start), .line_end(line_end), .frame_start(frame_start),
        .line_crc_ok(line_crc_ok), .clk(clk), .rst(rst),
        .sdclk(sdclk), .sdle(sdle), .sdoe(sdoe), .sph(sph), .sd(sd),
        .gdclk(gdclk), .gdsp(gdsp), .gdoe(gdoe), .pmic_pg(pmic_pg),
        .pmic_wakeup(wake), .pmic_pwrup(pwrup), .vcom_mv(vcom_mv), .vcom_upd(vcom_upd),
        .synced(synced), .last_seq(last_seq), .err_cnt(err_cnt), .flt_cnt(flt_cnt),
        .rails_ok(rails_ok), .pg_fault(pg_fault), .wd_tripped(wd_tripped), .dc_trip(dc_trip),
        .dc_acc(dc_acc)
    );

    // PMIC: power good T_PG after PWRUP (only while WAKEUP), lost at once without it.
    always @(posedge pwrup) begin
        #(T_PG);
        if (pwrup && wake) pmic_pg = 1;
    end
    always @(negedge pwrup) pmic_pg = 0;

    reg [31:0] frames [0:MAXF*FW-1];
    reg [47:0] meta [0:MAXF-1];
    integer nframes, cur, observe, ndriven;
    integer nchk [0:TIMING], nfail [0:TIMING];

    task automatic chk(input integer s, input ok, input [8*48-1:0] msg);
        begin
            nchk[s] = nchk[s] + 1;
            if (!ok) begin
                nfail[s] = nfail[s] + 1;
                if (nfail[s] <= 5) $display("  fail [%0d] frame %0d t=%0t: %0s", s, cur, $time, msg);
            end
        end
    endtask

    function [7:0] fbyte(input integer f, input integer line, input integer b);
        reg [31:0] x;
        begin
            x = frames[f*FW + line*WK + b/4];
            fbyte = x[8*(b%4)+:8];
        end
    endfunction

    function [7:0] mask11(input [7:0] b);
        integer i;
        begin
            for (i = 0; i < 8; i = i + 2) mask11[i+:2] = &b[i+:2] ? 2'b00 : b[i+:2];
        end
    endfunction

    // Per-frame expectation and observation.
    reg [47:0] m;
    integer scn, crc_line, late_line, short_line, cut_line, fault_lo, fault_hi;
    reg m_drive, m_refuse, m_fault, m_accept;
    integer flags, sf, sl, vc;
    integer rows, first_blank, flt0, err0;
    reg blanked, pmic_ever = 0, win = 0;
    integer n_sdclk, n_gdclk, n_gdsp, n_le, n_sd, n_sdoe, n_gdoe;
    integer peak = 0;
    real t_hdr, t_cut;

    // Source driver model.
    reg [7:0] shreg [0:BYTES-1];
    reg [7:0] lat [0:BYTES-1];
    integer nsh = 0, lat_n = 0, j;
    real t_sdclk = -1e9, t_sdchg = -1e9, t_ler = -1e9, t_lef = -1e9, t_gr = -1e9, t_gf = -1e9;
    reg after_le = 0;

    always @(sd or sph) begin
        chk(TIMING, $realtime - t_sdclk >= 8.0, "SD/SPH hold < 8 ns");
        t_sdchg = $realtime;
    end

    always @(posedge sdclk) begin
        n_sdclk = n_sdclk + 1;
        chk(TIMING, $realtime - t_sdclk >= 40.0, "SDCLK cycle < 40 ns");
        chk(TIMING, $realtime - t_sdchg >= 8.0, "SD/SPH setup < 8 ns");
        if (after_le) chk(TIMING, $realtime - t_lef >= 40.0, "LE off delay < 40 ns");
        after_le = 0;
        t_sdclk = $realtime;
        if (!sph) begin
            if (nsh < BYTES) shreg[nsh] = sd;
            nsh = nsh + 1;
        end
    end

    always @(posedge sdle) begin
        n_le = n_le + 1;
        chk(TIMING, $realtime - t_sdclk >= 40.0, "LE on delay < 40 ns");
        t_ler = $realtime;
        for (j = 0; j < BYTES; j = j + 1) lat[j] = shreg[j];
        lat_n = nsh;
        nsh = 0;
    end

    always @(negedge sdle) begin
        chk(TIMING, $realtime - t_ler >= 40.0 && $realtime - t_ler >= HSYNC * TSYS - 0.5,
            "SDLE pulse too short");
        t_lef = $realtime;
        after_le = 1;
        check_row;
    end

    // The panel is only ever driven with the rails up and power good.
    always @(posedge sdoe) chk(TIMING, rails_ok && pmic_pg && pwrup, "SDOE high without rails");
    always @(posedge gdoe) chk(TIMING, rails_ok && pmic_pg && pwrup, "GDOE high without rails");
    always @(posedge pwrup) chk(TIMING, wake, "PWRUP before WAKEUP");
    always @(negedge wake) chk(TIMING, !pwrup, "WAKEUP dropped before PWRUP");

    task check_row;
        integer k, r, match, zero;
        reg ok;
        reg [8*48-1:0] msg;
        begin
            r = rows;
            rows = rows + 1;
            match = 1;
            zero = 1;
            for (k = 0; k < BYTES; k = k + 1) begin
                if (lat[k] != mask11(fbyte(cur, r, 32 + k))) match = 0;
                if (lat[k] != 0) zero = 0;
            end
            ok = 1;
            msg = "";
            if (!m_drive) begin
                ok = 0; msg = "source latch on a non-driving frame";
            end else if (lat_n != BYTES) begin
                ok = 0; msg = "latch without 200 shifted bytes";
            end else if (r < sf || r > sl) begin
                ok = !sdoe && zero; msg = "row outside scan window not blank";
            end else if (blanked) begin
                ok = !sdoe && zero; msg = "row after fault not blank";
            end else if (!(sdoe && match)) begin
                if (!sdoe && m_fault && r >= fault_lo) begin
                    blanked = 1;
                    first_blank = r;
                end else begin
                    ok = 0; msg = sdoe ? "driven row data mismatch" : "in-window row not driven";
                end
            end
            chk(scn, ok, msg);
        end
    endtask

    always @(posedge gdclk) begin
        n_gdclk = n_gdclk + 1;
        if ($realtime - t_gr < 4 * LINE_RX * TRX)
            chk(TIMING, $realtime - t_gr >= HTOTAL * TSYS - 0.5 && $realtime - t_gr >= 4999.5,
                "GDCLK period below minimum");
        chk(TIMING, $realtime - t_gf >= 499.5, "GDCLK low < 0.5 us");
        t_gr = $realtime;
    end
    always @(negedge gdclk) begin
        chk(TIMING, $realtime - t_gr >= 499.5, "GDCLK high < 0.5 us");
        t_gf = $realtime;
    end
    always @(negedge gdsp) n_gdsp = n_gdsp + 1;

    always @(posedge wake) begin
        pmic_ever = 1;
        if (!observe) chk(scn, m_accept && (flags & 2), "rails woken by a frame that may not");
    end

    always @(posedge clk) begin
        if (win) begin
            if (sd != 0) n_sd = n_sd + 1;
            if (sdoe) n_sdoe = n_sdoe + 1;
            if (gdoe) n_gdoe = n_gdoe + 1;
        end
        if (((dut.wptr - dut.rptr) & 10'h3FF) > peak) peak = (dut.wptr - dut.rptr) & 10'h3FF;
    end

    function integer faults(input integer d);
        faults = dut.unpack.flt_cnt + dut.timing.flt_cnt;
    endfunction

    task send_frame(input integer f);
        integer l, w, nw;
        begin
            cur = f;
            m = observe ? 48'h90 : meta[f];
            scn = m[3:0];
            {m_accept, m_fault, m_refuse, m_drive} = m[7:4];
            crc_line = m[17:8];
            late_line = m[27:18];
            short_line = m[37:28];
            cut_line = m[47:38];
            fault_lo = (crc_line | short_line | cut_line) - 1;
            fault_hi = fault_lo + 1;
            flags = fbyte(f, 0, 5);
            sf = fbyte(f, 0, 12) | fbyte(f, 0, 13) << 8;
            sl = fbyte(f, 0, 14) | fbyte(f, 0, 15) << 8;
            vc = fbyte(f, 0, 16) | fbyte(f, 0, 17) << 8;
            rows = 0; blanked = 0; first_blank = -1;
            n_sdclk = 0; n_gdclk = 0; n_gdsp = 0; n_le = 0; n_sd = 0; n_sdoe = 0; n_gdoe = 0;
            flt0 = faults(0);
            err0 = dut.unpack.err_cnt;
            if (!observe && scn == 11) chk(scn, pwrup, "rails off before the PMIC_ON=0 frame");
            if (!observe && scn == 14 && !m_refuse) chk(scn, !dc_trip, "DC guard tripped early");

            @(posedge rx_clk) frame_start <= 1;
            @(posedge rx_clk) frame_start <= 0;
            for (l = 0; l < 600 && !(cut_line && l >= cut_line); l = l + 1) begin
                if (l != 0 && l == late_line) repeat (LATE) @(posedge rx_clk);
                if (l == 1) win = 1;
                line_start <= 1;
                @(posedge rx_clk) line_start <= 0;
                nw = l != 0 && l == short_line ? 599 : 600;
                for (w = 0; w < nw; w = w + 1) begin
                    rx_valid <= 1;
                    rx_data <= w < WK ? frames[f*FW + l*WK + w] : {16'hA5C3, w[15:0]};
                    @(posedge rx_clk);
                    if (l == 0 && w == 7) t_hdr = $realtime;   // header decided on word 7
                end
                rx_valid <= 0;
                line_end <= 1;
                line_crc_ok <= !(l != 0 && l == crc_line);
                @(posedge rx_clk) begin
                    line_end <= 0;
                    line_crc_ok <= 1;
                end
                repeat (LINE_RX - nw - 2) @(posedge rx_clk);
            end
            t_cut = $realtime;
            if (cut_line) watchdog;
            else repeat (VBL * LINE_RX) @(posedge rx_clk);
            win = 0;
            end_frame;
        end
    endtask

    task end_frame;
        begin
            if (observe) begin
                if (rows != 0) begin
                    chk(0, rows == ROWS, "driven frame did not latch 600 rows");
                    ndriven = ndriven + 1;
                end
            end else if (m_drive) begin
                chk(scn, rows == ROWS, "driven frame did not latch 600 rows");
                chk(scn, n_gdsp == 1 && n_gdclk == VTOTAL, "gate start/clock count");
                if (m_fault) begin
                    chk(scn, blanked && first_blank <= fault_hi, "fault did not blank the remainder");
                    chk(scn, faults(0) == flt0 + 1, "fault not counted once");
                end else
                    chk(scn, faults(0) == flt0, "unexpected data-path fault");
            end else begin
                chk(scn, n_sdclk == 0 && n_le == 0 && n_sd == 0 && n_sdoe == 0,
                    "source activity on a non-driving frame");
                chk(scn, n_gdclk == 0 && n_gdsp == 0, "gate activity on a non-driving frame");
                if (m_refuse) begin
                    chk(scn, n_gdoe == 0, "GDOE high on a refused frame");
                    chk(scn, dut.unpack.err_cnt == err0 + 1, "refusal not counted");
                end else
                    chk(scn, dut.unpack.err_cnt == err0, "accepted frame counted as refused");
            end
            if (!observe) begin
                if (scn == 3) chk(scn, !pmic_ever, "rails woken by a header-less frame");
                if (scn == 0 && (flags & 4)) chk(scn, vcom_mv == vc, "VCOM_SET not latched");
                if (scn == 1 && m_refuse) chk(scn, !dut.unpack.synced, "stale frame kept sync");
                if (scn == 13 && m_refuse) chk(scn, dut.unpack.synced,
                                               "rescanned RESYNC dropped sync");
                if (scn == 12 && m_refuse) begin
                    chk(scn, !pwrup && dut.unpack.synced, "drive refused for rails lost sync");
                end
                if (scn == 11) chk(scn, !pwrup, "PMIC_ON=0 did not drop the rails");
                if (scn == 14 && m_refuse) chk(scn, dc_trip, "DC guard did not trip");
            end
        end
    endtask

    // DSI lost mid-frame: driving stops within ROW_TO, the gate driver is off
    // WD_GATE after the last accepted header, PWRUP falls at WD_RAILS, then WAKEUP.
    real t_g, t_p, t_w, t_o;
    task watchdog;
        begin
            t_o = -1;
            while (!(dut.timing.fault) && $realtime < t_cut + 1e6) @(posedge clk);
            t_o = $realtime - t_cut;
            chk(8, t_o < (ROW_TO + 2 * HTOTAL) * TSYS, "drive did not stop within ROW_TO");
            chk(8, gdoe && pwrup, "GDOE/rails not on before the timeout");
            while (gdoe && $realtime < t_hdr + WD_GATE * TSYS + 1e6) @(posedge clk);
            t_g = $realtime - t_hdr;
            while (pwrup && $realtime < t_hdr + WD_RAILS * TSYS + 1e6) @(posedge clk);
            t_p = $realtime - t_hdr;
            while (wake && $realtime < t_hdr + (WD_RAILS + T_DOWN) * TSYS + 1e6) @(posedge clk);
            t_w = $realtime - t_hdr;
            chk(8, t_g > WD_GATE * TSYS - 2000 && t_g < WD_GATE * TSYS + 2000,
                "GDOE not dropped at WD_GATE");
            chk(8, t_p > WD_RAILS * TSYS - 2000 && t_p < WD_RAILS * TSYS + 2000,
                "PWRUP not dropped at WD_RAILS");
            chk(8, t_w > (WD_RAILS + T_DOWN) * TSYS - 2000 && t_w < (WD_RAILS + T_DOWN) * TSYS + 2000,
                "WAKEUP not dropped T_DOWN after PWRUP");
            chk(8, wd_tripped && !rails_ok, "watchdog state not reported");
            $display("  DSI lost at row %0d: drive stopped %.1f us later; GDOE low %.2f ms,",
                     cut_line, t_o / 1e3, t_g / 1e6);
            $display("  PWRUP low %.2f ms, WAKEUP low %.2f ms after the last accepted header",
                     t_p / 1e6, t_w / 1e6);
        end
    endtask

    function [8*52-1:0] desc(input integer s);
        case (s)
            0: desc = "RESYNC then 3 sequential frames drive";
            1: desc = "repeated buffer (stale seq) drives nothing";
            2: desc = "bad header CRC drives nothing";
            3: desc = "header-less RGB frame: nothing, rails never on";
            4: desc = "RESYNC with DRIVE rejected";
            5: desc = "scan window: outside rows blank, gate clocks";
            6: desc = "bad line checksum blanks the remainder";
            7: desc = "late line is absorbed by pacing";
            8: desc = "DSI lost mid-frame: stop, GDOE low, rails down";
            9: desc = "code 11 masked to 00";
            10: desc = "short line blanks the remainder";
            11: desc = "PMIC_ON=0 drops the rails after the frame";
            12: desc = "DRIVE before the rails are up is refused";
            13: desc = "rescanned RESYNC refused, sync kept";
            14: desc = "DC guard trips on runaway one-sided drive";
            default: desc = "panel bus timing, rails and reset state";
        endcase
    endfunction

    reg [8*256-1:0] ffile, mfile;
    reg [8*15-1:0] names = "abcdefghijklmno";
    reg [8*9-1:0] cv;
    reg [15:0] c;
    integer f, s, tot_fail, tot_chk;
    initial begin
        if (!$value$plusargs("frames=%s", ffile) || !$value$plusargs("nframes=%d", nframes)) begin
            $display("usage: +frames=<hex> +nframes=<n> [+meta=<hex>]");
            $finish;
        end
        observe = !$value$plusargs("meta=%s", mfile);
        $readmemh(ffile, frames, 0, nframes * FW - 1);
        if (!observe) $readmemh(mfile, meta, 0, nframes - 1);
        for (s = 0; s <= TIMING; s = s + 1) begin nchk[s] = 0; nfail[s] = 0; end
        ndriven = 0;
        cur = -1;

        cv = "123456789";
        c = 16'hFFFF;
        for (s = 8; s >= 0; s = s - 1) c = crc16_byte(c, cv[s*8+:8]);
        chk(TIMING, c == 16'h6F91, "CRC-16/MCRF4XX check value");

        repeat (10) @(posedge clk);
        rst = 0;
        @(posedge rx_clk) rx_rst = 0;
        repeat (100) @(posedge clk);
        chk(TIMING, !sdoe && !gdoe && sd == 0 && !sdclk && !sdle && !gdclk && sph && gdsp &&
                    !pwrup && !wake, "outputs not inactive after reset");
        for (f = 0; f < nframes; f = f + 1) send_frame(f);

        $display("");
        tot_fail = 0;
        tot_chk = 0;
        for (s = 0; s <= TIMING; s = s + 1) begin
            tot_fail = tot_fail + nfail[s];
            tot_chk = tot_chk + nchk[s];
            if (nchk[s] != 0 && (!observe || s == 0 || s == TIMING))
                $display("%s %-52s %s (%0d checks)", s == TIMING ? "( )" :
                         {"(", names[(14 - s)*8+:8], ")"}, desc(s),
                         nfail[s] ? "FAIL" : "PASS", nchk[s]);
        end
        if (observe) $display("observe mode: %0d of %0d frames drove the panel", ndriven, nframes);
        $display("peak line-FIFO fill %0d of %0d words; refused %0d, faults %0d, DC acc %0d",
                 peak, 1 << 9, dut.unpack.err_cnt, faults(0), dc_acc);
        $display("RESULT: %s", tot_fail == 0 && tot_chk > 0 ? "PASS" : "FAIL");
        $finish;
    end
endmodule
