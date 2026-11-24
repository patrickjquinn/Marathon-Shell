// SPDX-License-Identifier: Apache-2.0
// Option-B unpacker (800x51 RGB888): header check, sequence guard, data-line
// checks, 24->8 serialisation into the line FIFO. All in the px_clk domain.
// Events to the panel domain are toggles; the f_* bundle is stable from one
// acc_t toggle to the next.
`default_nettype none
module epd_unpack #(parameter AW = 11) (
    input  wire        clk,
    input  wire        rst,
    input  wire        px_valid,     // at most one pixel every 3 clocks
    input  wire [23:0] px_data,      // {B0, B1, B2}, B0 first on the wire
    input  wire        line_start,
    input  wire        line_end,
    input  wire        frame_start,
    input  wire        line_crc_ok,  // qualifies line_end
    output reg         wr_en,
    output reg  [7:0]  wr_data,
    input  wire        fifo_ovf,
    input  wire [AW:0] fifo_wptr,
    output reg         f_drive,
    output reg         f_pmic_on,
    output reg         f_vcom_set,
    output reg  [9:0]  f_first,
    output reg  [9:0]  f_last,
    output reg  [15:0] f_vcom_mv,
    output reg  [AW:0] f_base,
    output reg         acc_t,        // sequence-advancing frame accepted
    output reg         ref_t,        // frame refused
    output reg         go_t,         // first pixel of data line 1, driving frame
    output reg         flt_t,        // data-path fault in the driving frame
    output reg         synced,
    output reg  [31:0] last_seq,
    output reg  [15:0] err_cnt,
    output reg  [15:0] flt_cnt
);
    `include "crc16_mcrf4xx.vh"

    localparam HPX = 800, LINES = 51;

    reg  [5:0]  ln;
    reg  [9:0]  pc;
    reg         in_line;
    reg  [15:0] crc;
    reg         hdr_ok;
    reg  [3:0]  flags;
    reg  [31:0] seq;
    reg  [15:0] sf, sl, vc;
    reg         wr_on;
    reg  [15:0] sh;
    reg  [1:0]  sn;

    wire [7:0]  b0 = px_data[23:16], b1 = px_data[15:8], b2 = px_data[7:0];
    wire [15:0] crc3 = crc16_byte(crc16_byte(crc16_byte(crc, b0), b1), b2);
    wire px = px_valid && in_line;
    wire data_ln = ln != 0 && ln < LINES;
    wire dat_px = px && data_ln;

    wire drive = flags[0], pmic_on = flags[1], vcom_set = flags[2], resync = flags[3];
    wire hdr_valid = hdr_ok && pc == HPX && line_crc_ok && !(resync && drive) &&
                     (!drive || (sf <= sl && sl < 16'd600));
    wire fault = wr_on && ((dat_px && pc >= HPX) || (px_valid && sn != 0) || fifo_ovf ||
                           (line_end && in_line && data_ln && (pc != HPX || !line_crc_ok)));

    always @(posedge clk) begin
        wr_en <= 1'b0;
        if (sn != 0) begin
            wr_en <= 1'b1;
            wr_data <= sh[15:8];
            sh <= {sh[7:0], 8'h00};
            sn <= sn - 1'b1;
        end

        if (line_start) begin
            pc <= 0;
            in_line <= 1'b1;
        end

        if (px) begin
            if (pc != 10'h3FF) pc <= pc + 1'b1;
            if (ln == 0) case (pc)
                0: begin hdr_ok <= hdr_ok && px_data == 24'h455044; crc <= crc3; end
                1: begin hdr_ok <= hdr_ok && b0 == 8'h31 && b1 == 8'd1 && b2[7:4] == 0;
                         flags <= b2[3:0]; crc <= crc3; end
                2: begin seq[7:0] <= b2; crc <= crc3; end
                3: begin seq[31:8] <= {b2, b1, b0}; crc <= crc3; end
                4: begin sf <= {b1, b0}; sl[7:0] <= b2; crc <= crc3; end
                5: begin sl[15:8] <= b0; vc <= {b2, b1}; crc <= crc3; end
                6, 7, 8: crc <= crc3;
                9: hdr_ok <= hdr_ok && crc16_byte(crc, b0) == {b2, b1};
                default: ;
            endcase
            if (dat_px && wr_on && pc < HPX && sn == 0) begin
                wr_en <= 1'b1;
                wr_data <= b0;
                sh <= {b1, b2};
                sn <= 2'd2;
            end
            if (dat_px && ln == 1 && pc == 0 && wr_on) go_t <= ~go_t;
        end

        if (line_end && in_line) begin
            in_line <= 1'b0;
            if (ln != 6'h3F) ln <= ln + 1'b1;
            if (ln == 0) begin
                if (hdr_valid && resync) begin
                    last_seq <= seq;
                    synced <= 1'b1;
                end else if (hdr_valid && synced && seq == last_seq + 1) begin
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
                    if (hdr_valid) synced <= 1'b0;
                end
            end
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
            hdr_ok <= 1'b1;
            crc <= 16'hFFFF;
        end

        if (rst) begin
            ln <= 6'h3F;  // ignore lines until the first frame start
            in_line <= 1'b0; hdr_ok <= 1'b0; wr_on <= 1'b0; sn <= 0; wr_en <= 1'b0;
            acc_t <= 1'b0; ref_t <= 1'b0; go_t <= 1'b0; flt_t <= 1'b0;
            synced <= 1'b0; last_seq <= 0; err_cnt <= 0; flt_cnt <= 0;
            f_drive <= 1'b0; f_pmic_on <= 1'b0; f_vcom_set <= 1'b0;
        end
    end
endmodule
