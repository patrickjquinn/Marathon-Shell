// SPDX-License-Identifier: Apache-2.0
// Testbench for epd_bridge_core: replays Option-B DSI frames from $readmemh
// files as bursts on the pixel interface, models the source driver's shift
// register and latch, and checks every latched row against the input.
//   +frames=<hex> +nframes=<n> [+meta=<hex>]
// Without +meta (observe mode) it only checks that frames the bridge chose to
// drive match their input.
`timescale 1ns / 1ps
`default_nettype none
module tb_bridge;
    localparam MAXF = 32, FW = 40800;
    localparam BYTES = 200, HFP = 12, HSYNC = 2, HBP = 2;
    localparam VFP = 0, VSYNC = 1, VBP = 0, ROWS = 600, VTAIL = 1;
    localparam WD_CLKS = 470588, PMIC_OFF_CLKS = 2000000;
    localparam HTOTAL = HFP + HSYNC + HBP + BYTES, VTOTAL = VFP + VSYNC + VBP + ROWS + VTAIL;
    localparam real TPX = 20.0, TEPD = 50.0;
    // DSI line = 12 panel lines exactly: 12 * 216 * 50 ns = 6480 * 20 ns.
    localparam B1 = 20, LINE_PX = 6480, VBL = 4000, STARVE = 1500;
    localparam TIMING = 12;

    `include "crc16_mcrf4xx.vh"

    reg px_clk = 0, epd_clk = 0;
    always #(TPX / 2) px_clk = ~px_clk;
    always #(TEPD / 2) epd_clk = ~epd_clk;

    reg px_rst = 1, epd_rst = 1;
    reg px_valid = 0, line_start = 0, line_end = 0, frame_start = 0, line_crc_ok = 1;
    reg [23:0] px_data = 0;
    wire sdclk, sdle, sdoe, sph, gdclk, gdsp, gdoe, pmic_en, vcom_upd, synced;
    wire [7:0] sd;
    wire [15:0] vcom_mv, err_cnt, wflt_cnt, rflt_cnt;
    wire [31:0] last_seq;

    epd_bridge_core #(
        .BYTES(BYTES), .HFP(HFP), .HSYNC(HSYNC), .HBP(HBP),
        .VFP(VFP), .VSYNC(VSYNC), .VBP(VBP), .ROWS(ROWS), .VTAIL(VTAIL),
        .WD_CLKS(WD_CLKS), .PMIC_OFF_CLKS(PMIC_OFF_CLKS)
    ) dut (
        .px_clk(px_clk), .px_rst(px_rst), .px_valid(px_valid), .px_data(px_data),
        .line_start(line_start), .line_end(line_end), .frame_start(frame_start),
        .line_crc_ok(line_crc_ok), .epd_clk(epd_clk), .epd_rst(epd_rst),
        .sdclk(sdclk), .sdle(sdle), .sdoe(sdoe), .sph(sph), .sd(sd),
        .gdclk(gdclk), .gdsp(gdsp), .gdoe(gdoe), .pmic_en(pmic_en),
        .vcom_mv(vcom_mv), .vcom_upd(vcom_upd), .synced(synced), .last_seq(last_seq),
        .err_cnt(err_cnt), .wflt_cnt(wflt_cnt), .rflt_cnt(rflt_cnt)
    );

    reg [23:0] frames [0:MAXF*FW-1];
    reg [31:0] meta [0:MAXF-1];
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

    function [7:0] fbyte(input integer f, input integer line, input integer L);
        reg [23:0] x;
        begin
            x = frames[f*FW + line*800 + L/3];
            fbyte = L % 3 == 0 ? x[23:16] : L % 3 == 1 ? x[15:8] : x[7:0];
        end
    endfunction

    function [7:0] mask11(input [7:0] b);
        integer i;
        begin
            for (i = 0; i < 8; i = i + 2) mask11[i+:2] = &b[i+:2] ? 2'b00 : b[i+:2];
        end
    endfunction

    // Per-frame expectation and observation.
    reg [31:0] m;
    integer scn, crc_line, starve_line, short_line, fault_lo, fault_hi;
    reg m_drive, m_refuse, m_fault, m_accept;
    integer flags, sf, sl, vc;
    integer rows, first_blank, flt0, err0;
    reg blanked, pmic_ever = 0, win = 0;
    integer n_sdclk, n_gdclk, n_gdsp, n_le, n_sd, n_sdoe, n_gdoe;
    integer peak = 0;
    real t_hdr;

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
        chk(TIMING, $realtime - t_ler >= 40.0 && $realtime - t_ler >= HSYNC * TEPD - 0.5,
            "SDLE pulse too short");
        t_lef = $realtime;
        after_le = 1;
        check_row;
    end

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
                if (lat[k] != mask11(fbyte(cur, 1 + r / 12, 200 * (r % 12) + k))) match = 0;
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
        if ($realtime - t_gr < 2 * HTOTAL * TEPD)
            chk(TIMING, $realtime - t_gr >= HTOTAL * TEPD - 0.5 && $realtime - t_gr >= 4999.5,
                "GDCLK period below minimum");
        chk(TIMING, $realtime - t_gf >= 499.5, "GDCLK low < 0.5 us");
        t_gr = $realtime;
    end
    always @(negedge gdclk) begin
        chk(TIMING, $realtime - t_gr >= 499.5, "GDCLK high < 0.5 us");
        t_gf = $realtime;
    end
    always @(negedge gdsp) n_gdsp = n_gdsp + 1;

    always @(posedge pmic_en) begin
        pmic_ever = 1;
        if (!observe) chk(scn, m_accept && (flags & 2), "PMIC enabled by a frame that may not");
    end

    always @(posedge epd_clk) begin
        if (win) begin
            if (sd != 0) n_sd = n_sd + 1;
            if (sdoe) n_sdoe = n_sdoe + 1;
            if (gdoe) n_gdoe = n_gdoe + 1;
        end
        if (((dut.wptr - dut.rptr) & 12'hFFF) > peak) peak = (dut.wptr - dut.rptr) & 12'hFFF;
    end

    task send_frame(input integer f);
        integer l, p, np;
        begin
            cur = f;
            m = observe ? 32'h90 : meta[f];
            scn = m[3:0];
            {m_accept, m_fault, m_refuse, m_drive} = m[7:4];
            crc_line = m[15:8];
            starve_line = m[23:16];
            short_line = m[31:24];
            fault_lo = 12 * ((crc_line | starve_line | short_line) - 1);
            fault_hi = starve_line ? fault_lo + 1 : fault_lo + 12;
            flags = fbyte(f, 0, 5);
            sf = fbyte(f, 0, 12) | fbyte(f, 0, 13) << 8;
            sl = fbyte(f, 0, 14) | fbyte(f, 0, 15) << 8;
            vc = fbyte(f, 0, 16) | fbyte(f, 0, 17) << 8;
            rows = 0; blanked = 0; first_blank = -1;
            n_sdclk = 0; n_gdclk = 0; n_gdsp = 0; n_le = 0; n_sd = 0; n_sdoe = 0; n_gdoe = 0;
            flt0 = wflt_cnt + rflt_cnt;
            err0 = err_cnt;
            if (!observe && scn == 11) chk(scn, pmic_en, "PMIC off before the PMIC_ON=0 frame");

            @(posedge px_clk) frame_start <= 1;
            @(posedge px_clk) frame_start <= 0;
            for (l = 0; l < 51; l = l + 1) begin
                if (l != 0 && l == starve_line) repeat (STARVE) @(posedge px_clk);
                repeat (B1) @(posedge px_clk);
                if (l == 1) win = 1;
                line_start <= 1;
                @(posedge px_clk) line_start <= 0;
                np = l != 0 && l == short_line ? 799 : 800;
                for (p = 0; p < np; p = p + 1) begin
                    px_valid <= 1;
                    px_data <= frames[f*FW + l*800 + p];
                    @(posedge px_clk) px_valid <= 0;
                    repeat (2) @(posedge px_clk);
                end
                line_end <= 1;
                line_crc_ok <= !(l != 0 && l == crc_line);
                @(posedge px_clk) begin
                    line_end <= 0;
                    line_crc_ok <= 1;
                end
                if (l == 0) t_hdr = $realtime;
                repeat (LINE_PX - B1 - 2 - 3 * 800) @(posedge px_clk);
            end
            repeat (VBL) @(posedge px_clk);
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
                    chk(scn, wflt_cnt + rflt_cnt == flt0 + 1, "fault not counted once");
                end else
                    chk(scn, wflt_cnt + rflt_cnt == flt0, "unexpected data-path fault");
            end else begin
                chk(scn, n_sdclk == 0 && n_le == 0 && n_sd == 0 && n_sdoe == 0,
                    "source activity on a non-driving frame");
                chk(scn, n_gdclk == 0 && n_gdsp == 0, "gate activity on a non-driving frame");
                if (m_refuse) begin
                    chk(scn, n_gdoe == 0, "GDOE high on a refused frame");
                    chk(scn, err_cnt == err0 + 1, "refusal not counted");
                end else
                    chk(scn, err_cnt == err0, "accepted frame counted as refused");
            end
            if (!observe) begin
                if (scn == 3) chk(scn, !pmic_ever, "PMIC enabled by a header-less frame");
                if (scn == 0 && (flags & 4)) chk(scn, vcom_mv == vc, "VCOM_SET not latched");
                if (scn == 1 && m_refuse) chk(scn, !synced, "stale frame did not drop sync");
                if (scn == 11) chk(scn, !pmic_en, "PMIC_ON=0 did not turn PMIC off");
                if (scn == 8) watchdog;
            end
        end
    endtask

    real t_g, t_p;
    task watchdog;
        begin
            chk(8, gdoe && pmic_en, "GDOE/PMIC not on before the stop");
            while (gdoe && $realtime < t_hdr + WD_CLKS * TEPD + 1e6) @(posedge epd_clk);
            t_g = $realtime - t_hdr;
            while (pmic_en && $realtime < t_hdr + (WD_CLKS + PMIC_OFF_CLKS) * TEPD + 1e6)
                @(posedge epd_clk);
            t_p = $realtime - t_hdr;
            chk(8, t_g > WD_CLKS * TEPD - 2000 && t_g < WD_CLKS * TEPD + 2000,
                "GDOE not dropped at 2 frame periods");
            chk(8, t_p > (WD_CLKS + PMIC_OFF_CLKS) * TEPD - 2000 &&
                   t_p < (WD_CLKS + PMIC_OFF_CLKS) * TEPD + 2000, "PMIC not off after timeout");
            $display("  watchdog: GDOE low %.2f ms, PMIC off %.2f ms after the last accepted header",
                     t_g / 1e6, t_p / 1e6);
        end
    endtask

    function [8*52-1:0] desc(input integer s);
        case (s)
            0: desc = "RESYNC then 3 sequential frames drive";
            1: desc = "repeated buffer (stale seq) drives nothing";
            2: desc = "bad header CRC drives nothing";
            3: desc = "header-less RGB frame: nothing, PMIC never on";
            4: desc = "RESYNC with DRIVE rejected";
            5: desc = "scan window: outside rows blank, gate clocks";
            6: desc = "bad line checksum blanks the remainder";
            7: desc = "FIFO underrun blanks the remainder";
            8: desc = "watchdog: GDOE low, then PMIC off";
            9: desc = "code 11 masked to 00";
            10: desc = "short line blanks the remainder";
            11: desc = "PMIC_ON=0 turns PMIC off after the frame";
            default: desc = "panel bus timing (GDE043A2 AC limits)";
        endcase
    endfunction

    reg [8*256-1:0] ffile, mfile;
    reg [8*12-1:0] names = "abcdefghijkl";
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

        repeat (10) @(posedge epd_clk);
        epd_rst = 0;
        @(posedge px_clk) px_rst = 0;
        repeat (100) @(posedge px_clk);
        for (f = 0; f < nframes; f = f + 1) send_frame(f);

        $display("");
        tot_fail = 0;
        tot_chk = 0;
        for (s = 0; s <= TIMING; s = s + 1) begin
            tot_fail = tot_fail + nfail[s];
            tot_chk = tot_chk + nchk[s];
            if (nchk[s] != 0 && (!observe || s == 0 || s == TIMING))
                $display("%s %-52s %s (%0d checks)", s == TIMING ? "( )" :
                         {"(", names[(11 - s)*8+:8], ")"}, desc(s),
                         nfail[s] ? "FAIL" : "PASS", nchk[s]);
        end
        if (observe) $display("observe mode: %0d of %0d frames drove the panel", ndriven, nframes);
        $display("peak line-FIFO fill %0d of %0d bytes; err_cnt %0d wflt_cnt %0d rflt_cnt %0d",
                 peak, 1 << 11, err_cnt, wflt_cnt, rflt_cnt);
        $display("RESULT: %s", tot_fail == 0 && tot_chk > 0 ? "PASS" : "FAIL");
        $finish;
    end
endmodule
