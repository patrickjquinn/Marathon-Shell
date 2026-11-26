// SPDX-License-Identifier: Apache-2.0
// I2C (7-bit 0x4b) front end that reproduces v36's user-logic bridge: the user
// registers 0x80-0x8F, and the Pango flash opcodes forwarded to the CPLD's
// internal slave APB (UG030004 sec. 9.5, Table 9-8; command codes Table 16-22)
// with the framing the vendor driver uses. Only these opcodes are taken:
//   51 WREN, 52 WRDIS, 60 RESET, 70 EFLASH_SLEEP, 71 EFLASH_WAKEUP,
//   A1 RDID, A3 RDSR, 20 PROGRAM, 21 PROGRAM_CTL, 30 READ, 31 READ_CTL.
// Any other first byte is NACKed and nothing reaches the APB, so this design
// cannot erase, lock or reconfigure (no 10/11/12/40/50).
//
// Optional dead-man (DEADMAN_CLKS != 0): unless the host writes 0xA5 to 0x89
// within DEADMAN_CLKS of reset, the bridge overwrites the first page of the
// application slot with zeros, so the next power-up fails the application load
// and falls back to the golden image. That is the recovery path for an image
// whose I2C front end does not work on the board.
`default_nettype none
module cfg_bridge #(
    parameter [7:0]  FW_VERSION = 8'h82,
    parameter [7:0]  LINK_ID = 8'hD2,
    parameter [6:0]  I2C_ADDR = 7'h4B,
    parameter integer DEADMAN_CLKS = 0,
    parameter [23:0] DEADMAN_ADDR = 24'h02FC00,   // page 572: heap 1, page 252
    parameter integer APB_TO = 4095,
    parameter integer POLL_TO = 2046000           // 100 ms at 20.46 MHz
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        scl_i,
    input  wire        sda_i,
    output wire        scl_oe,
    output wire        sda_oe,
    // status, clk domain
    input  wire        synced,
    input  wire        rails_ok,
    input  wire        pg_fault,
    input  wire        dc_trip,
    input  wire        wd_tripped,
    input  wire [7:0]  err_cnt,
    input  wire [7:0]  flt_cnt,
    input  wire [7:0]  last_seq,
    input  wire [15:0] dc_hi,
    // APB master to the CCS (GTP_APB, SEL_CCS)
    output reg         psel,
    output reg         penable,
    output reg         pwrite,
    output reg  [4:0]  paddr,
    output reg  [7:0]  pwdata,
    input  wire [7:0]  prdata,
    input  wire        pready
);
    localparam [4:0] A_STAT2 = 5'h12, A_CMDR = 5'h15, A_ADR0 = 5'h16, A_ADR1 = 5'h17,
                     A_ADR2 = 5'h18, A_DATATR = 5'h19, A_DATARR = 5'h1A;
    localparam [7:0] NOP = 8'hFF, WREN = 8'h51, WRDIS = 8'h52, PROGRAM = 8'h20;
    localparam [1:0] R_NONE = 2'd0, R_REG = 2'd1, R_APB4 = 2'd2, R_DATA = 2'd3;

    wire start, stop, wr_byte, rd_req, sl_busy;
    wire [7:0] rx;
    reg  [7:0] tx;
    reg        ack, dm_run;
    wire       hold;

    i2c_slave #(.ADDR(I2C_ADDR)) sl (
        .clk(clk), .rst(rst), .scl_i(scl_i), .sda_i(sda_i), .scl_oe(scl_oe), .sda_oe(sda_oe),
        .addr_en(!dm_run), .start(start), .stop(stop), .wr_byte(wr_byte), .rx(rx), .ack(ack),
        .rd_req(rd_req), .tx(tx), .hold(hold), .busy(sl_busy)
    );

    // ---- APB master: one transfer at a time, bounded wait on PREADY.
    reg        a_req, a_wr, a_done, apb_err;
    reg [4:0]  a_addr;
    reg [7:0]  a_wdata, a_rdata;
    reg [$clog2(APB_TO+1)-1:0] a_t;
    always @(posedge clk) begin
        a_done <= 1'b0;
        if (!psel) begin
            if (a_req) begin
                psel <= 1'b1; pwrite <= a_wr; paddr <= a_addr; pwdata <= a_wdata; a_t <= 0;
            end
        end else if (!penable)
            penable <= 1'b1;
        else if (pready || a_t == APB_TO) begin
            psel <= 1'b0; penable <= 1'b0; a_done <= 1'b1;
            a_rdata <= pready ? prdata : 8'hFF;
            if (!pready) apb_err <= 1'b1;
        end else
            a_t <= a_t + 1'b1;
        if (rst) begin
            psel <= 1'b0; penable <= 1'b0; pwrite <= 1'b0; paddr <= 0; pwdata <= 0;
            apb_err <= 1'b0; a_t <= 0;
        end
    end
    wire a_idle = !psel && !a_req;

    // ---- Command queue fed by I2C events (<= 4 APB transfers per event; the slave
    // stretches SCL until it is empty, so every event finds it empty). Reads load
    // the next tx byte.
    reg [13:0] q0, q1, q2, q3;   // {wr, addr[4:0], data[7:0]}
    reg [2:0]  qn, qi;
    wire       q_busy = qi != qn;
    wire [13:0] qe = qi[1] ? (qi[0] ? q3 : q2) : (qi[0] ? q1 : q0);

    // ---- Transaction state.
    reg [7:0]  cmd, b1, b2;
    reg [2:0]  nb;          // bytes seen in this write, saturating at 4
    reg        ok;
    reg [1:0]  rsrc;
    reg [3:0]  ptr;
    reg [4:0]  rbase;
    reg [1:0]  ridx;
    reg        dr_used;

    // ---- Dead-man.
    reg        dm_armed, dm_fired;
    reg [$clog2((DEADMAN_CLKS > 0 ? DEADMAN_CLKS : 1)+1)-1:0] dm_t;
    reg [8:0]  dm_i;
    reg [2:0]  dm_ph;
    reg [$clog2(POLL_TO+1)-1:0] dm_p;

    assign hold = q_busy || a_req || psel;
    wire op_ok = rx[7:4] == 4'h8 || rx == WREN || rx == WRDIS || rx == 8'h60 || rx == 8'h70 ||
                 rx == 8'h71 || rx == 8'hA1 || rx == 8'hA3 || rx == 8'h20 || rx == 8'h21 ||
                 rx == 8'h30 || rx == 8'h31;

    function [7:0] reg_rd(input [3:0] r);
        case (r)
            4'h0: reg_rd = FW_VERSION;
            4'h1: reg_rd = {dm_fired, dm_armed, apb_err, wd_tripped, dc_trip, pg_fault,
                            rails_ok, synced};
            4'h2: reg_rd = err_cnt;
            4'h3: reg_rd = flt_cnt;
            4'h4: reg_rd = LINK_ID;
            4'h5: reg_rd = last_seq;
            4'h6: reg_rd = dc_hi[15:8];
            4'h7: reg_rd = dc_hi[7:0];
            4'h9: reg_rd = {7'd0, dm_armed};
            default: reg_rd = 8'hDE;   // what v36 returns for undecoded registers
        endcase
    endfunction

    function [13:0] E(input wr, input [4:0] a, input [7:0] d);
        E = {wr, a, d};
    endfunction

    always @(posedge clk) begin
        // Queue executor / dead-man drive the APB master.
        if (a_done) begin
            if (dm_run) begin
                if (dm_ph == 3'd2 && !a_rdata[5]) dm_ph <= 3'd3;      // busy (STATUSR bit 21) low
                else if (dm_ph != 3'd2) dm_i <= dm_i + 1'b1;
            end else begin
                if (!qe[13]) tx <= a_rdata;
                qi <= qi + 1'b1;
            end
        end
        a_req <= 1'b0;
        if (a_idle && !a_done) begin
            if (dm_run) begin
                a_req <= 1'b1;
                a_wr <= 1'b1;
                case (dm_ph)
                    3'd0: case (dm_i)       // NOP, WREN, ADR0..2, PROGRAM
                        0: begin a_addr <= A_CMDR; a_wdata <= NOP; end
                        1: begin a_addr <= A_CMDR; a_wdata <= WREN; end
                        2: begin a_addr <= A_ADR0; a_wdata <= DEADMAN_ADDR[7:0]; end
                        3: begin a_addr <= A_ADR1; a_wdata <= DEADMAN_ADDR[15:8]; end
                        4: begin a_addr <= A_ADR2; a_wdata <= DEADMAN_ADDR[23:16]; end
                        5: begin a_addr <= A_CMDR; a_wdata <= PROGRAM; end
                        default: begin a_req <= 1'b0; dm_ph <= 3'd1; dm_i <= 0; end
                    endcase
                    3'd1: if (dm_i != 256) begin a_addr <= A_DATATR; a_wdata <= 8'h00; end
                          else begin a_req <= 1'b0; dm_ph <= 3'd2; dm_p <= 0; end
                    3'd2: begin
                        a_wr <= 1'b0; a_addr <= A_STAT2;
                        if (dm_p == POLL_TO) begin a_req <= 1'b0; dm_ph <= 3'd3; end
                    end
                    3'd3: begin a_addr <= A_CMDR; a_wdata <= WRDIS; dm_ph <= 3'd4; end
                    3'd4: begin a_addr <= A_CMDR; a_wdata <= NOP; dm_ph <= 3'd5; end
                    default: begin
                        a_req <= 1'b0; dm_run <= 1'b0; dm_fired <= 1'b1; dm_armed <= 1'b0;
                    end
                endcase
            end else if (q_busy) begin
                a_req <= 1'b1;
                {a_wr, a_addr, a_wdata} <= qe;
            end
        end

        if (dm_run && dm_ph == 3'd2 && dm_p != POLL_TO) dm_p <= dm_p + 1'b1;
        if (dm_armed && !dm_run) begin
            if (dm_t != DEADMAN_CLKS) dm_t <= dm_t + 1'b1;
            else if (!sl_busy && !q_busy && a_idle) begin
                dm_run <= 1'b1; dm_ph <= 0; dm_i <= 0;
            end
        end

        // I2C events.
        if (start) nb <= 0;
        if (stop && dr_used) begin
            q0 <= E(1, A_CMDR, NOP); qi <= 0; qn <= 1;
            dr_used <= 1'b0;
        end
        if (wr_byte) begin
            if (nb != 3'd4) nb <= nb + 1'b1;
            if (nb == 1) b1 <= rx;
            if (nb == 2) b2 <= rx;
            if (nb == 0) begin
                cmd <= rx;
                ok <= op_ok;
                casez (rx)
                    8'h8?: begin ptr <= rx[3:0]; rsrc <= R_REG; end
                    WREN: begin
                        q0 <= E(1, A_CMDR, NOP); q1 <= E(1, A_CMDR, WREN); qi <= 0; qn <= 2;
                    end
                    WRDIS: begin
                        q0 <= E(1, A_CMDR, WRDIS); q1 <= E(1, A_CMDR, NOP); qi <= 0; qn <= 2;
                    end
                    8'h60, 8'h70, 8'h71: begin q0 <= E(1, A_CMDR, rx); qi <= 0; qn <= 1; end
                    8'hA1: begin rsrc <= R_APB4; rbase <= 5'h00; ridx <= 0; end
                    8'hA3: begin rsrc <= R_APB4; rbase <= 5'h10; ridx <= 0; end
                    8'h20, 8'h21, 8'h30: ;
                    8'h31: begin
                        q0 <= E(1, A_CMDR, rx); qi <= 0; qn <= 1; rsrc <= R_DATA;
                    end
                    default: rsrc <= R_NONE;
                endcase
            end else if (ok) casez (cmd)
                8'h8?: if (nb == 1 && ptr == 4'h9 && rx == 8'hA5) dm_armed <= 1'b0;
                8'h20, 8'h30: if (nb == 3) begin
                    // Address bytes arrive ADR2, ADR1, ADR0 (the vendor's page_addr, MSB first).
                    q0 <= E(1, A_ADR0, rx); q1 <= E(1, A_ADR1, b2);
                    q2 <= E(1, A_ADR2, b1); q3 <= E(1, A_CMDR, cmd); qi <= 0; qn <= 4;
                    if (cmd == 8'h30) rsrc <= R_DATA;
                end else if (nb == 4 && cmd == 8'h20) begin
                    q0 <= E(1, A_DATATR, rx); qi <= 0; qn <= 1;
                end
                8'h21: if (nb == 3) begin
                    q0 <= E(1, A_CMDR, cmd); qi <= 0; qn <= 1;
                end else if (nb == 4) begin
                    q0 <= E(1, A_DATATR, rx); qi <= 0; qn <= 1;
                end
                default: ;
            endcase
            ack <= nb == 0 ? op_ok : ok;
        end
        if (rd_req) case (rsrc)
            R_REG: tx <= reg_rd(ptr);
            R_APB4: begin
                q0 <= E(0, rbase + ridx, 8'h00); qi <= 0; qn <= 1;
                ridx <= ridx + 1'b1;
            end
            R_DATA: begin
                q0 <= E(0, A_DATARR, 8'h00); qi <= 0; qn <= 1; dr_used <= 1'b1;
            end
            default: tx <= 8'hFF;
        endcase

        if (rst) begin
            qi <= 0; qn <= 0; a_req <= 1'b0; tx <= 8'hFF; ack <= 1'b0;
            nb <= 0; ok <= 1'b0; rsrc <= R_NONE; ptr <= 0; dr_used <= 1'b0; cmd <= 0;
            dm_armed <= DEADMAN_CLKS != 0; dm_fired <= 1'b0; dm_run <= 1'b0; dm_t <= 0;
            dm_ph <= 0; dm_i <= 0; dm_p <= 0;
        end
    end
endmodule
