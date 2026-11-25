// SPDX-License-Identifier: Apache-2.0
// Behavioural model of the CCS behind the internal slave APB, standing in for
// rtl/pango/pgc_ccs_apb.v. Registers per UG030004 Table 9-8, commands per
// Table 16-22, flows per Appendix 7. Device behaviour taken from the MP01 logs
// of 2026-11-24: IDCODE 0xA0422899; STATUSR 0x1489EFD0 (persist_si2c set);
// CTL 0x40B28341; PROGRAM and PROGRAM_CTL overwrite without an erase.
// Modelled assumptions (not documented): a page programs once 256 bytes are in
// DATATR; NOP leaves the write enable latched; DATATR/DATARR insert wait states.
// Every CMDR write is logged for the testbench.
`timescale 1ns / 1ps
`default_nettype none
module pgc_ccs_apb (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       psel,
    input  wire       penable,
    input  wire       pwrite,
    input  wire [4:0] paddr,
    input  wire [7:0] pwdata,
    output reg  [7:0] prdata,
    output wire       pready
);
    localparam PAGES = 1280, T_BUSY = 4000;   // ~200 us at 20.46 MHz (real: ~9 ms)
    localparam M_IDLE = 0, M_PROG = 1, M_PCTL = 2, M_READ = 3, M_RCTL = 4;

    reg [7:0]  flash [0:PAGES*256-1];
    reg [7:0]  pbuf [0:255];
    reg [31:0] ctl;
    reg [7:0]  adr0, adr1, adr2, cmdr;
    reg        wel;
    integer    mode, idx, busy_t, page, k, wcnt;
    integer    n_cmd, n_bad, n_prog_nowel, n_data_badmode;
    reg [7:0]  cmd_log [0:8191];
    reg        stuck;           // set by the testbench: next access never gets PREADY

    wire busy = busy_t != 0;
    wire [31:0] status = 32'h1489EFD0 | (busy << 21);
    wire slow = paddr == 5'h19 || paddr == 5'h1A;
    assign pready = psel && penable && !stuck && wcnt >= (slow ? 2 : 0);

    function integer pg(input [7:0] a1, input [7:0] a2);
        pg = a2[2:1] * 320 + {a2[0], a1};
    endfunction

    initial begin
        for (k = 0; k < PAGES * 256; k = k + 1) flash[k] = 8'h00;
        ctl = 32'h40B28341; wel = 0; mode = M_IDLE; idx = 0; busy_t = 0; wcnt = 0;
        n_cmd = 0; n_bad = 0; n_prog_nowel = 0; n_data_badmode = 0; stuck = 0;
        adr0 = 0; adr1 = 0; adr2 = 0; cmdr = 8'hFF;
    end

    always @(posedge clk) begin
        if (busy_t != 0) begin
            busy_t = busy_t - 1;
            if (busy_t == 0 && mode == M_PROG)
                for (k = 0; k < 256; k = k + 1) flash[page * 256 + k] = pbuf[k];
        end
        wcnt = psel && penable ? wcnt + 1 : 0;
        // Read data is sampled in the APB setup phase (the CCS has no wait for these).
        if (psel && !penable) case (paddr)
            5'h00, 5'h01, 5'h02, 5'h03: prdata <= 32'hA0422899 >> (8 * paddr[1:0]);
            5'h10, 5'h11, 5'h12, 5'h13: prdata <= status >> (8 * paddr[1:0]);
            5'h15: prdata <= cmdr;
            5'h1A: prdata <= mode == M_READ ? flash[page * 256 + adr0 * 4 + idx] :
                             mode == M_RCTL ? ctl >> (8 * (idx % 4)) : 8'h00;
            5'h1B: prdata <= {5'd0, busy, 2'd0};
            default: prdata <= 8'h00;
        endcase
        if (psel && penable && pready) begin
            if (pwrite) case (paddr)
                5'h15: begin
                    cmdr = pwdata;
                    cmd_log[n_cmd % 8192] = pwdata;
                    n_cmd = n_cmd + 1;
                    case (pwdata)
                        8'hFF: ;
                        8'h51: wel = 1;
                        8'h52: begin wel = 0; mode = M_IDLE; end
                        8'h20, 8'h21: if (!wel || busy) n_prog_nowel = n_prog_nowel + 1;
                                      else begin
                                          mode = pwdata == 8'h20 ? M_PROG : M_PCTL;
                                          idx = 0; page = pg(adr1, adr2);
                                      end
                        8'h30: begin mode = M_READ; idx = 0; page = pg(adr1, adr2); end
                        8'h31: begin mode = M_RCTL; idx = 0; end
                        8'h60, 8'h70, 8'h71: ;
                        default: n_bad = n_bad + 1;   // erase, lock, CFG or unknown
                    endcase
                end
                5'h16: adr0 = pwdata;
                5'h17: adr1 = pwdata;
                5'h18: adr2 = pwdata;
                5'h19: begin
                    if (mode == M_PROG && idx < 256) begin
                        pbuf[idx] = pwdata;
                        idx = idx + 1;
                        if (idx == 256) busy_t = T_BUSY;
                    end else if (mode == M_PCTL && idx < 4) begin
                        ctl = (ctl & ~(32'hFF << (8 * idx))) | (pwdata << (8 * idx));
                        idx = idx + 1;
                        if (idx == 4) busy_t = T_BUSY;
                    end else
                        n_data_badmode = n_data_badmode + 1;
                end
                default: ;
            endcase
            else if (paddr == 5'h1A) begin
                if (mode == M_READ || mode == M_RCTL) idx = idx + 1;
                else n_data_badmode = n_data_badmode + 1;
            end
            stuck = 0;
        end
    end
endmodule
