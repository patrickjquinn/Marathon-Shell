// SPDX-License-Identifier: Apache-2.0
// Placeholder for the 4-lane D-PHY receiver and DSI video-mode parser.
//
// Not implemented: it needs the vendor toolchain (Pango PDS) and its primitives:
//  - GTP_IOBUF_RX_MIPI per lane and clock: HS differential + LP single-ended
//    receive on the same pads (UG030005 section 12), 100 ohm termination;
//  - GTP_ISERDES_E1 1:8 deserialisers, SoT (0xB8) byte alignment, lane deskew
//    and merge (lanes 2/3 are swapped on the MP01 board);
//  - a CDC from the non-continuous HS byte clock into px_clk;
//  - a DSI packet parser: header ECC, payload checksum (crc16_mcrf4xx.vh),
//    VSS/HSS/HSE, RGB888 long packets, producing the pixel interface below
//    (px_valid at most every third px_clk).
// Outputs are tied off so nothing downstream can drive the panel.
`default_nettype none
module dphy_rx_stub (
    input  wire        ck_p,
    input  wire        ck_n,
    input  wire [3:0]  d_p,
    input  wire [3:0]  d_n,
    input  wire [1:0]  lp_ck,     // separate LP pins, resistor-network option only
    input  wire [7:0]  lp_d,
    input  wire        px_clk,
    input  wire        rst,
    output wire        px_valid,
    output wire [23:0] px_data,
    output wire        line_start,
    output wire        line_end,
    output wire        frame_start,
    output wire        line_crc_ok
);
    assign {px_valid, px_data, line_start, line_end, frame_start, line_crc_ok} = 0;
endmodule
