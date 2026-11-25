// SPDX-License-Identifier: Apache-2.0
// Testbench for the stage-1 image (cfg_bridge + i2c_slave + CCS model): every
// frame uses the vendor driver's framing (panel-z10-eink-i2c.c) and the shapes
// the 2026-11-24 device tools sent through v36 at 0x4b, at 400 kHz, with both
// write-STOP-read and write-Sr-read.
//   +dm=0: host disarms the dead-man first, then the full opcode suite runs.
//   +dm=1: host never disarms; the dead-man must blank page 572 and only it.
//   +v: print each transaction.
`timescale 1ns / 1ps
`default_nettype none
module tb_i2c;
    localparam real TQ = 625.0;               // quarter SCL period: 400 kHz
    localparam integer DM_CLKS = 400000;      // ~19.6 ms
    localparam [6:0] A = 7'h4B;

    tri1 scl, sda;
    reg  m_scl = 1, m_sda = 1;
    assign scl = m_scl ? 1'bz : 1'b0;
    assign sda = m_sda ? 1'bz : 1'b0;

    wire sdclk, sdle, sdoe, sph, gdclk, gdsp, gdoe, wake, pwrup;
    wire [7:0] sd;
    epd_stage1_top #(.DEADMAN_CLKS(DM_CLKS)) dut (
        .i2c_scl(scl), .i2c_sda(sda), .epd_sdclk(sdclk), .epd_sdle(sdle), .epd_sdoe(sdoe),
        .epd_sph(sph), .epd_sd(sd), .epd_gdclk(gdclk), .epd_gdsp(gdsp), .epd_gdoe(gdoe),
        .pmic_wakeup(wake), .pmic_pwrup(pwrup)
    );
    wire [31:0] outs = {sdclk, sdle, sdoe, sph, sd, gdclk, gdsp, gdoe, wake, pwrup};

    integer nchk = 0, nfail = 0, verbose = 0;
    task chk(input ok, input [8*64-1:0] msg);
        begin
            nchk = nchk + 1;
            if (!ok) begin
                nfail = nfail + 1;
                $display("  FAIL t=%0t: %0s", $time, msg);
            end
        end
    endtask

    always @(outs) if ($time > 0) chk(outs == 0, "a panel or PMIC output left 0");

    // ---- Bit-level master, honours clock stretching.
    task q; #(TQ); endtask
    task scl_hi;
        begin m_scl = 1; wait (scl === 1'b1); end
    endtask
    task i2c_start;
        begin m_sda = 1; q; scl_hi; q; m_sda = 0; q; m_scl = 0; q; end
    endtask
    task i2c_stop;
        begin m_sda = 0; q; scl_hi; q; m_sda = 1; q; q; end
    endtask
    task wbyte(input [7:0] b, output nak);
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                m_sda = b[i]; q; scl_hi; q; q; m_scl = 0; q;
            end
            m_sda = 1; q; scl_hi; q; nak = sda; q; m_scl = 0; q;
        end
    endtask
    task rbyte(input last, output [7:0] b);
        integer i;
        begin
            m_sda = 1;
            for (i = 7; i >= 0; i = i - 1) begin
                q; scl_hi; q; b[i] = sda; q; m_scl = 0; q;
            end
            m_sda = last; q; scl_hi; q; q; m_scl = 0; q;
            m_sda = 1;
        end
    endtask

    // ---- Transactions. wbuf/rbuf hold the bytes.
    reg [7:0] wbuf [0:299];
    reg [7:0] rbuf [0:299];
    integer   wnak;   // index of the first NACKed byte (-1 address, -2 none)

    task xfer(input integer nw, input integer nr, input rs);
        integer i;
        reg nk;
        reg [7:0] b;
        begin
            wnak = -2;
            if (verbose) $display("  %0t xfer w%0d r%0d %02x", $time, nw, nr, wbuf[0]);
            if (nw > 0) begin
                i2c_start;
                wbyte({A, 1'b0}, nk);
                if (nk) wnak = -1;
                for (i = 0; i < nw && wnak == -2; i = i + 1) begin
                    wbyte(wbuf[i], nk);
                    if (nk) wnak = i;
                end
                if (!rs || nr == 0 || wnak != -2) i2c_stop;
            end
            if (nr > 0 && wnak == -2) begin
                i2c_start;
                wbyte({A, 1'b1}, nk);
                if (nk) wnak = -1;
                else for (i = 0; i < nr; i = i + 1) begin
                    rbyte(i == nr - 1, b);
                    rbuf[i] = b;
                end
                i2c_stop;
            end
        end
    endtask

    task w1(input [7:0] b0);
        begin wbuf[0] = b0; xfer(1, 0, 0); chk(wnak == -2, "single-byte command NACKed"); end
    endtask
    task w4r4(input [7:0] op, input rs);
        begin
            wbuf[0] = op; wbuf[1] = 0; wbuf[2] = 0; wbuf[3] = 0;
            xfer(4, 4, rs);
            chk(wnak == -2, "RDID/RDSR NACKed");
        end
    endtask
    function [31:0] rword(input integer dummy);
        rword = {rbuf[3], rbuf[2], rbuf[1], rbuf[0]};
    endfunction
    task user_rd(input [7:0] r, output [7:0] v);
        begin
            wbuf[0] = r; xfer(1, 1, 0);
            chk(wnak == -2, "user register read NACKed");
            v = rbuf[0];
        end
    endtask
    task rdsr(output [31:0] s);
        begin w4r4(8'hA3, 0); s = rword(0); end
    endtask
    task wait_idle;
        reg [31:0] s;
        integer n;
        begin
            n = 0;
            rdsr(s);
            while (s[21] && n < 200) begin rdsr(s); n = n + 1; end
            chk(!s[21], "eflash still busy");
        end
    endtask
    task read_ctl(input rs, output [31:0] c);
        begin
            w1(8'h51);
            wbuf[0] = 8'h31; wbuf[1] = 0; wbuf[2] = 0; wbuf[3] = 0; wbuf[4] = 0;
            xfer(5, 4, rs);
            chk(wnak == -2, "READ_CTL NACKed");
            c = rword(0);
        end
    endtask
    task program_ctl(input [31:0] c);
        begin
            w1(8'h51);
            wbuf[0] = 8'h21; wbuf[1] = 0; wbuf[2] = 0; wbuf[3] = 0;
            {wbuf[7], wbuf[6], wbuf[5], wbuf[4]} = c;
            xfer(8, 0, 0);
            chk(wnak == -2, "PROGRAM_CTL NACKed");
            wait_idle;
        end
    endtask
    function [23:0] paddr(input integer page);
        paddr = (page / 320) << 17 | (page % 320) << 8;
    endfunction
    task program_page(input integer page, input integer seed);
        integer i;
        begin
            w1(8'h51);
            wbuf[0] = 8'h20;
            {wbuf[1], wbuf[2], wbuf[3]} = paddr(page);
            for (i = 0; i < 256; i = i + 1) wbuf[4 + i] = pat(seed, i);
            xfer(260, 0, 0);
            chk(wnak == -2, "PROGRAM NACKed");
            wait_idle;
        end
    endtask
    task read_page(input integer page, input rs);
        begin
            w1(8'h51);
            wbuf[0] = 8'h30;
            {wbuf[1], wbuf[2], wbuf[3]} = paddr(page);
            wbuf[4] = 0;
            xfer(5, 256, rs);
            chk(wnak == -2, "READ NACKed");
        end
    endtask
    function [7:0] pat(input integer seed, input integer i);
        pat = seed == 0 ? 8'h00 : seed == 1 ? i[7:0] : seed == 2 ? ~i[7:0] : (i * 37 + seed) & 8'hFF;
    endfunction
    function page_is(input integer page, input integer seed);
        integer i;
        begin
            page_is = 1;
            for (i = 0; i < 256; i = i + 1) if (rbuf[i] != pat(seed, i)) page_is = 0;
        end
    endfunction
    function flash_is(input integer page, input integer seed);
        integer i;
        begin
            flash_is = 1;
            for (i = 0; i < 256; i = i + 1)
                if (dut.ccs.flash[page * 256 + i] != pat(seed, i)) flash_is = 0;
        end
    endfunction

    // ---- CMDR trace: no erase/lock/CFG ever, WREN always right after a NOP.
    task trace_ok;
        integer i;
        reg ok;
        begin
            ok = 1;
            for (i = 1; i < dut.ccs.n_cmd; i = i + 1)
                if (dut.ccs.cmd_log[i] == 8'h51 && dut.ccs.cmd_log[i - 1] != 8'hFF) ok = 0;
            chk(ok, "a WREN was not preceded by NOP");
            chk(dut.ccs.n_bad == 0, "a forbidden or unknown command reached CMDR");
            chk(dut.ccs.n_prog_nowel == 0, "PROGRAM without write enable");
            chk(dut.ccs.n_data_badmode == 0, "DATATR/DATARR access outside a data command");
        end
    endtask

    integer dm, i, n_before, page_seed;
    reg [7:0] v;
    reg [31:0] w;
    reg [8*40-1:0] r;
    initial begin
        if (!$value$plusargs("dm=%d", dm)) dm = 0;
        verbose = $test$plusargs("v");
        for (i = 0; i < 256; i = i + 1) begin
            dut.ccs.flash[572 * 256 + i] = pat(7, i);
            dut.ccs.flash[573 * 256 + i] = pat(8, i);
        end
        #(5000);

        if (dm == 0) begin
            wbuf[0] = 8'h89; wbuf[1] = 8'hA5; xfer(2, 0, 0);
            chk(wnak == -2, "dead-man disarm NACKed");
            user_rd(8'h81, v);
            chk(v[6] == 0, "dead-man still armed after 0x89 = A5");

            user_rd(8'h80, v); chk(v == 8'h81, "0x80 is not the stage-1 version 0x81");
            user_rd(8'h84, v); chk(v == 8'hD0, "0x84 is not 0xD0");
            user_rd(8'h8D, v); chk(v == 8'hDE, "undecoded register is not 0xDE");
            wbuf[0] = 8'h80; xfer(1, 2, 0);
            chk(rbuf[0] == 8'h81 && rbuf[1] == 8'h81, "burst read of 0x80");
            wbuf[0] = 8'h8C; wbuf[1] = 8'h03; xfer(2, 0, 0);
            chk(wnak == -2, "kernel's 0x8C write NACKed");
            wbuf[0] = 8'h8E; wbuf[1] = 8'h05; xfer(2, 0, 0);
            chk(wnak == -2, "kernel's 0x8E write NACKed");

            w4r4(8'hA1, 0); chk(rword(0) == 32'hA0422899, "RDID (STOP framing)");
            chk(rbuf[0] == 8'h99 && rbuf[3] == 8'hA0, "RDID bytes are not 99 28 42 a0");
            w4r4(8'hA1, 1); chk(rword(0) == 32'hA0422899, "RDID (Sr framing)");
            rdsr(w); chk(w == 32'h1489EFD0, "RDSR is not d0 ef 89 14");
            w4r4(8'hA3, 1); chk(rword(0) == 32'h1489EFD0, "RDSR (Sr framing)");

            read_ctl(0, w); chk(w == 32'h40B28341, "READ_CTL is not 41 83 b2 40");
            read_ctl(1, w); chk(w == 32'h40B28341, "READ_CTL (Sr framing)");

            n_before = dut.ccs.n_cmd;
            read_page(1279, 0); chk(page_is(1279, 0), "blank page 1279 does not read 00");
            // Pattern, its inverse over it (overwrite, no erase), then blank again.
            for (i = 0; i < 3; i = i + 1) begin
                page_seed = i == 0 ? 1 : i == 1 ? 2 : 0;
                program_page(1279, page_seed);
                chk(flash_is(1279, page_seed), "PROGRAM did not land in page 1279");
                read_page(1279, i == 1);
                chk(page_is(1279, page_seed), "READ of page 1279 does not match");
            end
            chk(flash_is(572, 7) && flash_is(573, 8), "PROGRAM of 1279 touched the app slot");

            program_ctl(32'h400383C1);
            read_ctl(0, w); chk(w == 32'h400383C1, "PROGRAM_CTL then READ_CTL");
            program_ctl(32'h40B28341);
            read_ctl(1, w); chk(w == 32'h40B28341, "PROGRAM_CTL restore");

            w1(8'h71); w1(8'h70); w1(8'h52);
            rdsr(w); chk(w == 32'h1489EFD0, "RDSR after WAKEUP/SLEEP/WRDIS");

            // Refused opcodes: ERASE, ERASE_PAGE, ERASE_CTL, PROGRAM_LOCK, CFG,
            // slave-I2C PROGRAM_CTL, ISC_ENABLE, RDUID, NOP, and 0x90 (bit-7 alias of ERASE).
            n_before = dut.ccs.n_cmd;
            for (i = 0; i < 10; i = i + 1) begin
                wbuf[0] = i == 0 ? 8'h10 : i == 1 ? 8'h11 : i == 2 ? 8'h12 : i == 3 ? 8'h40 :
                          i == 4 ? 8'h50 : i == 5 ? 8'h22 : i == 6 ? 8'h53 : i == 7 ? 8'hA4 :
                          i == 8 ? 8'hFF : 8'h90;
                wbuf[1] = 0; wbuf[2] = 0; wbuf[3] = 0;
                xfer(4, 0, 0);
                chk(wnak == 0, "a refused opcode was ACKed");
            end
            chk(dut.ccs.n_cmd == n_before, "a refused opcode reached CMDR");

            // A stuck APB (no PREADY) must not wedge the bus.
            dut.ccs.stuck = 1;
            w4r4(8'hA1, 0);
            dut.ccs.stuck = 0;
            chk(rbuf[0] == 8'hFF, "a timed-out APB read did not return FF");
            user_rd(8'h81, v); chk(v[5] == 1, "APB timeout not flagged in 0x81 bit 5");
            w4r4(8'hA1, 0); chk(rword(0) == 32'hA0422899, "RDID after an APB timeout");

            #(DM_CLKS * 48.88 + 2e6);
            user_rd(8'h81, v);
            chk(v[7] == 0, "dead-man fired although disarmed");
            chk(flash_is(572, 7), "page 572 changed although disarmed");
        end else begin
            user_rd(8'h80, v); chk(v == 8'h81, "0x80 is not the stage-1 version 0x81");
            user_rd(8'h81, v); chk(v[6] == 1, "dead-man not armed at power-up");
            i = 0;
            while ($time < (DM_CLKS * 48.88 + 3e6)) begin
                wbuf[0] = 8'h80; xfer(1, 1, 0);
                if (wnak == -1) i = i + 1;
            end
            chk(i > 0, "address not NACKed while the dead-man ran");
            user_rd(8'h81, v);
            chk(v[7] == 1 && v[6] == 0, "dead-man did not report fired");
            chk(flash_is(572, 0), "page 572 not zeroed by the dead-man");
            chk(flash_is(573, 8), "dead-man touched page 573");
            chk(dut.ccs.cmd_log[0] == 8'hFF && dut.ccs.cmd_log[1] == 8'h51 &&
                dut.ccs.cmd_log[2] == 8'h20 && dut.ccs.cmd_log[3] == 8'h52 &&
                dut.ccs.cmd_log[4] == 8'hFF && dut.ccs.n_cmd == 5,
                "dead-man CMDR sequence is not NOP WREN PROGRAM WRDIS NOP");
            $display("  dead-man: %0d address NACKs while it ran", i);
        end
        trace_ok;
        $display("tb_i2c dm=%0d: %0d checks, %0d failures, %0d CMDR writes", dm, nchk, nfail,
                 dut.ccs.n_cmd);
        $display("RESULT: %s", nfail == 0 && nchk > 0 ? "PASS" : "FAIL");
        $finish;
    end
endmodule
