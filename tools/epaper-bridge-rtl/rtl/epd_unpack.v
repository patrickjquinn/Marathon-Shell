// SPDX-License-Identifier: Apache-2.0
// Link v2 unpacker (stock DSI mode, 800x600 RGB888): one panel row per DSI line.
// Input is the RGB888 long-packet payload as 32-bit words, first wire byte in
// [7:0], 600 words a line. Line 0 words 0-7 are the header; on every line words
// 8-57 (bytes 32-231) are that line's panel row. All in the rx_clk domain.
// Events to the panel domain are toggles. The f_* bundle is stable from one acc_t
// toggle to the next; last_seq and err_cnt from one acc_t/ref_t toggle to the next.
`default_nettype none
module epd_unpack #(parameter AW = 9) (
    input  wire        clk,
    input  wire        rst,
    input  wire        rx_valid,
    input  wire [31:0] rx_data,
    input  wire        line_start,
    input  wire        line_end,
    input  wire        frame_start,
    input  wire        line_crc_ok,  // qualifies line_end
    input  wire        drive_ok,     // panel domain: rails up, no DC trip (asynchronous)
    output reg         wr_en,
    output reg  [31:0] wr_data,
    input  wire        fifo_ovf,
    input  wire [AW:0] fifo_wptr,
    output reg         f_drive,
    output reg         f_pmic_on,
    output reg         f_vcom_set,
    output reg  [9:0]  f_first,
    output reg  [9:0]  f_last,
    output reg  [15:0] f_vcom_mv,
    output reg  [AW:0] f_base,
    output reg         acc_t,        // frame accepted (resync or sequence-advancing)
    output reg         ref_t,        // frame refused
    output reg         row_t,        // a driving frame's line arrived whole, checksum good
    output reg         flt_t,        // data-path fault in the driving frame
    output reg         synced,
    output reg  [31:0] last_seq,
    output reg  [15:0] err_cnt,
    output reg  [15:0] flt_cnt
);
    `include "crc16_mcrf4xx.vh"

    localparam WORDS = 600, D0 = 8, D1 = 58, ROWS = 600, VERSION = 8'd2;

    reg  [9:0]  ln, wc;
    reg         in_line, decided, wr_on, hdr_ok;
    reg  [15:0] crc, sf, sl, vc;
    reg  [3:0]  flags;
    reg  [31:0] seq;
    reg  [1:0]  dok;

    always @(posedge clk) dok <= {dok[0], drive_ok};

    wire [15:0] crc4 = crc16_byte(crc16_byte(crc16_byte(crc16_byte(crc,
                       rx_data[7:0]), rx_data[15:8]), rx_data[23:16]), rx_data[31:24]);
    wire w = rx_valid && in_line;
    wire drive = flags[0], pmic_on = flags[1], vcom_set = flags[2], resync = flags[3];
    // Word 7 carries the CRC, so the header is decided on it and word 8 can be written.
    wire hdr_valid = hdr_ok && crc == rx_data[15:0] && !(resync && drive) &&
                     !(drive && !dok[1]) && (!drive || (sf <= sl && sl < ROWS));
    wire decide = w && ln == 0 && wc == 7 && !decided;
    wire short0 = line_end && in_line && ln == 0 && !decided;
    wire line_bad = line_end && in_line && (wc != WORDS || !line_crc_ok);
    wire fault = wr_on && (fifo_ovf || line_bad || (w && wc >= WORDS));
    // A controller rescanning a RESYNC buffer repeats its seq: refuse it, keep sync,
    // and do not feed the watchdog.
    wire rescan = resync && synced && seq == last_seq;

    always @(posedge clk) begin
        wr_en <= 1'b0;
        if (line_start) begin
            wc <= 0;
            in_line <= 1'b1;
        end

        if (w) begin
            if (wc != 10'h3FF) wc <= wc + 1'b1;
            if (ln == 0) case (wc)
                0: begin hdr_ok <= hdr_ok && rx_data == 32'h31445045; crc <= crc4; end  // "EPD1"
                1: begin hdr_ok <= hdr_ok && rx_data[7:0] == VERSION && rx_data[15:12] == 0;
                         flags <= rx_data[11:8]; crc <= crc4; end
                2: begin seq <= rx_data; crc <= crc4; end
                3: begin sf <= rx_data[15:0]; sl <= rx_data[31:16]; crc <= crc4; end
                4: begin vc <= rx_data[15:0]; crc <= crc4; end
                5, 6: crc <= crc4;
                default: ;
            endcase
            if (wr_on && wc >= D0 && wc < D1) begin
                wr_en <= 1'b1;
                wr_data <= rx_data;
            end
        end

        if (decide || short0) begin
            decided <= 1'b1;
            if (decide && hdr_valid && resync && !rescan) begin
                last_seq <= seq;
                synced <= 1'b1;
                acc_t <= ~acc_t;
                f_drive <= 1'b0;
                f_pmic_on <= pmic_on;
                f_vcom_set <= vcom_set;
                f_vcom_mv <= vc;
            end else if (decide && hdr_valid && !resync && synced && seq == last_seq + 1) begin
                last_seq <= seq;
                acc_t <= ~acc_t;
                wr_on <= drive;
                f_drive <= drive;
                f_pmic_on <= pmic_on;
                f_vcom_set <= vcom_set;
                f_first <= sf[9:0];
                f_last <= sl[9:0];
                f_vcom_mv <= vc;
                f_base <= fifo_wptr;
            end else begin
                ref_t <= ~ref_t;
                err_cnt <= err_cnt + 1'b1;
                if (decide && hdr_valid && !rescan) synced <= 1'b0;
            end
        end

        if (line_end && in_line) begin
            in_line <= 1'b0;
            if (ln != 10'h3FF) ln <= ln + 1'b1;
            if (wr_on && !line_bad && ln < ROWS) row_t <= ~row_t;
        end

        if (fault) begin
            wr_on <= 1'b0;
            flt_t <= ~flt_t;
            flt_cnt <= flt_cnt + 1'b1;
        end

        if (frame_start) begin
            ln <= 0;
            in_line <= 1'b0;
            wr_on <= 1'b0;
            decided <= 1'b0;
            hdr_ok <= 1'b1;
            crc <= 16'hFFFF;
        end

        if (rst) begin
            ln <= 10'h3FF;  // ignore lines until the first frame start
            in_line <= 1'b0; hdr_ok <= 1'b0; wr_on <= 1'b0; decided <= 1'b1; wr_en <= 1'b0;
            acc_t <= 1'b0; ref_t <= 1'b0; row_t <= 1'b0; flt_t <= 1'b0;
            synced <= 1'b0; last_seq <= 0; err_cnt <= 0; flt_cnt <= 0;
            f_drive <= 1'b0; f_pmic_on <= 1'b0; f_vcom_set <= 1'b0;
        end
    end
endmodule
