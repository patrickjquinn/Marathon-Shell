// SPDX-License-Identifier: Apache-2.0
// Port shapes of the Pango primitives used here, for yosys only. Widths follow
// UG030004 Table 9-7 (APB) and UG030003 Table 48 (OSC); PDS supplies the cells.
(* blackbox *)
module GTP_APB (
    input  CLK, RST_N, input [4:0] ADDR,
    input  SEL_CCS, SEL_SPI, SEL_I2C0, SEL_I2C1, SEL_TIMER, SEL_PLL0, SEL_PLL1,
    input  EN, WR, input [7:0] WDATA, output [7:0] RDATA, output RDY, IRQ, IRQ_CCS
);
endmodule
(* blackbox *)
module GTP_OSC_E2 #(parameter USER_DIV_EN = "FALSE", parameter CLK_DIV = 0) (
    output CLKOUT, CLKCRC, input EN_N
);
endmodule
