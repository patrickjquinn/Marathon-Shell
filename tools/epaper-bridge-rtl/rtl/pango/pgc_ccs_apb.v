// SPDX-License-Identifier: Apache-2.0
// The CPLD's internal slave APB, CCS port only (UG030004 sec. 9.5, Table 9-7;
// primitive GTP_APB, UG030003 Table 47). PDS builds use this file; simulation
// replaces the module with tb/ccs_model.v.
`default_nettype none
module pgc_ccs_apb (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       psel,
    input  wire       penable,
    input  wire       pwrite,
    input  wire [4:0] paddr,
    input  wire [7:0] pwdata,
    output wire [7:0] prdata,
    output wire       pready
);
    GTP_APB apb (
        .CLK(clk), .RST_N(rst_n), .ADDR(paddr),
        .SEL_CCS(psel), .SEL_SPI(1'b0), .SEL_I2C0(1'b0), .SEL_I2C1(1'b0),
        .SEL_TIMER(1'b0), .SEL_PLL0(1'b0), .SEL_PLL1(1'b0),
        .EN(penable), .WR(pwrite), .WDATA(pwdata), .RDATA(prdata), .RDY(pready),
        .IRQ(), .IRQ_CCS()
    );
endmodule
