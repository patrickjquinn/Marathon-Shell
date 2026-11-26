// SPDX-License-Identifier: Apache-2.0
// Placeholder for the 4-lane D-PHY receiver and DSI video-mode parser.
//
// Not implemented: it needs Pango PDS and its I/O primitives (UG030005):
//  - GTP_IOBUF_RX_MIPI per data lane and the clock lane: HS differential and
//    LP single-ended receive on the same bank-2 pads, 100 ohm termination;
//  - GTP_ISERDES_E1 1:8 per lane on an IO clock from the DSI clock lane
//    (GTP_IOCLKBUF/GTP_IOCLKDIV_E1), SoT (0xB8) byte alignment, lane deskew and
//    merge (lanes 2/3 are swapped on the MP01 board);
//  - the stock link runs a non-continuous HS clock, so the byte clock stops in
//    LP: a small CDC FIFO into rx_clk, which must run free (a GTP_PLL_E2 output
//    from the internal oscillator, >= 40 MHz for 85 Hz at stock porches);
//  - a DSI packet parser: header ECC, long-packet checksum (crc16_mcrf4xx.vh),
//    VSS / HSS, RGB888 (0x3E) long packets of 2,400 bytes.
// Interface it must produce, all on rx_clk (see DESIGN.md sec. 3):
//  - frame_start: one pulse per VSS;
//  - line_start ... rx_valid words ... line_end for each RGB888 long packet;
//    rx_data[7:0] is the first payload byte, 600 words a line, at most one
//    word per clock, re-aligned so the payload starts on a word;
//  - line_crc_ok with line_end: the packet's checksum matched.
// Outputs are tied off so nothing downstream can drive the panel.
`default_nettype none
module dphy_rx_stub (
    input  wire        ck_p,
    input  wire        ck_n,
    input  wire [3:0]  d_p,
    input  wire [3:0]  d_n,
    input  wire        clk_ref,   // free-running reference (internal oscillator)
    input  wire        rst,
    output wire        rx_clk,
    output wire        rx_valid,
    output wire [31:0] rx_data,
    output wire        line_start,
    output wire        line_end,
    output wire        frame_start,
    output wire        line_crc_ok
);
    assign rx_clk = clk_ref;
    assign {rx_valid, rx_data, line_start, line_end, frame_start, line_crc_ok} = 0;
endmodule
