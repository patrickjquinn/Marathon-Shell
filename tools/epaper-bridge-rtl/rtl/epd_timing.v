// SPDX-License-Identifier: CERN-OHL-P-2.0
// Copyright Wenting Zhang 2024
// Copyright 2026 Patrick Quinn
//
// This source describes Open Hardware and is licensed under the CERN-OHL-P v2
//
// You may redistribute and modify this documentation and make products using
// it under the terms of the CERN-OHL-P v2 (https:/cern.ch/cern-ohl). This
// documentation is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY,
// INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY AND FITNESS FOR A
// PARTICULAR PURPOSE. Please see the CERN-OHL-P v2 for applicable conditions
//
// EPD source/gate timing for an 8-bit GDE043A2-class bus, one panel frame per
// go. Scan windows follow Caster (rtl/caster.v): line = hfp|hsync|hbp|hact,
// frame = vfp|vsync|vbp|active; SDLE = hsync, GDCLK = hsync|hbp|hact delayed a
// clock, GDSP low in vsync, SPH low in active. SPH and GDSP are active low.
// Rows are latched by the SDLE of the following line; VTAIL lines follow the
// last row (latch + gate flush). Row-to-gate alignment (VBP, dummy gate rows)
// is panel-specific and unverified on hardware.
`default_nettype none
module epd_timing #(
    parameter AW = 11,
    parameter BYTES = 200, HFP = 12, HSYNC = 2, HBP = 2,
    parameter VFP = 0, VSYNC = 1, VBP = 0, ROWS = 600, VTAIL = 1
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        go,
    input  wire [9:0]  first,
    input  wire [9:0]  last,
    input  wire [AW:0] base,      // FIFO write pointer when the frame was accepted
    input  wire        fault_in,  // write-side fault event
    output wire        fifo_re,
    input  wire [7:0]  fifo_q,
    input  wire        fifo_empty,
    input  wire [AW:0] fifo_rptr,
    output reg         busy,
    output reg         done,
    output reg  [15:0] flt_cnt,   // underruns + go while busy
    output wire        sdclk,
    output reg         sdle,
    output reg         sdoe,
    output reg         sph,
    output reg  [7:0]  sd,
    output reg         gdclk,
    output reg         gdsp
);
    localparam HACT0 = HFP + HSYNC + HBP, HTOTAL = HACT0 + BYTES;
    localparam VS0 = VFP + VSYNC + VBP, VTOTAL = VS0 + ROWS + VTAIL;

    reg [$clog2(HTOTAL)-1:0] h;
    reg [$clog2(VTOTAL)-1:0] v;
    reg        fault, disc, row_on, lat_on;
    reg [9:0]  r_first, r_last;
    reg [AW:0] r_base;

    wire       data_line = v >= VS0 && v < VS0 + ROWS;
    wire [9:0] row = v - VS0;
    wire       shift = busy && data_line && h >= HACT0;
    wire       udf = shift && !fault && (disc || fifo_empty);
    wire       le = busy && h >= HFP && h < HFP + HSYNC && v > VS0 && v <= VS0 + ROWS;
    wire       gck = busy && h >= HFP;
    wire       vsy = busy && v >= VFP && v < VFP + VSYNC;

    // disc: drop bytes a faulted or overrun frame left behind, up to base.
    assign fifo_re = disc ? fifo_rptr != r_base : busy && (shift || fault);

    function [7:0] mask11(input [7:0] b);
        integer i;
        begin
            for (i = 0; i < 8; i = i + 2)
                mask11[i+:2] = &b[i+:2] ? 2'b00 : b[i+:2];
        end
    endfunction

    always @(posedge clk) begin
        done <= 1'b0;
        if (busy) begin
            if (h == HTOTAL - 1) begin
                h <= 0;
                if (v == VTOTAL - 1) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end else
                    v <= v + 1'b1;
            end else
                h <= h + 1'b1;
            if (h == 0) begin
                lat_on <= row_on;
                row_on <= data_line && row >= r_first && row <= r_last;
            end
            if (fault_in) fault <= 1'b1;
            if (udf) begin
                fault <= 1'b1;
                flt_cnt <= flt_cnt + 1'b1;
            end
        end
        if (disc && fifo_rptr == r_base) disc <= 1'b0;
        if (go) begin
            if (busy)
                flt_cnt <= flt_cnt + 1'b1;
            else begin
                busy <= 1'b1;
                h <= 0; v <= 0;
                fault <= 1'b0; disc <= 1'b1; row_on <= 1'b0;
                r_first <= first; r_last <= last; r_base <= base;
            end
        end
        if (rst) begin
            busy <= 1'b0; done <= 1'b0; fault <= 1'b0; disc <= 1'b0;
            row_on <= 1'b0; lat_on <= 1'b0; flt_cnt <= 0;
        end
    end

    // Two-stage output pipeline: counters -> FIFO read -> pins.
    reg s1_shift, s1_drv, s1_le, s1_gck, s1_vsy, s2_gck, sdclk_en;
    always @(posedge clk) begin
        s1_shift <= shift;
        s1_drv   <= row_on && !fault && !udf;
        s1_le    <= le;
        s1_gck   <= gck;
        s1_vsy   <= vsy;
        s2_gck   <= s1_gck;

        sdclk_en <= s1_shift;
        sph      <= !s1_shift;
        sd       <= s1_shift && s1_drv && !fault ? mask11(fifo_q) : 8'h00;
        sdle     <= s1_le;
        gdclk    <= s2_gck;
        gdsp     <= !s1_vsy;
        if (s1_le && !sdle)
            sdoe <= lat_on && !fault;
        else if (fault || !busy)
            sdoe <= 1'b0;

        if (rst) begin
            s1_shift <= 1'b0; s1_le <= 1'b0; s1_gck <= 1'b0; s1_vsy <= 1'b0; s2_gck <= 1'b0;
            sdclk_en <= 1'b0; sph <= 1'b1; sd <= 0; sdle <= 1'b0; gdclk <= 1'b0; gdsp <= 1'b1;
            sdoe <= 1'b0;
        end
    end

    // Gated so SDCLK idles low outside shifting; a PDS build uses an output DDR
    // (D0 = 0, D1 = sdclk_en) instead of logic on the clock net.
    assign sdclk = sdclk_en & ~clk;
endmodule
