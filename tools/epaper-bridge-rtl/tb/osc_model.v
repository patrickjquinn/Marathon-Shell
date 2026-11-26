// SPDX-License-Identifier: Apache-2.0
// Simulation stand-in for rtl/pango/pgc_osc.v: 266 MHz / 13 = 20.46 MHz.
`timescale 1ns / 1ps
`default_nettype none
module pgc_osc #(parameter integer CLK_DIV = 13) (output reg clk);
    initial clk = 1'b0;
    always #(1000.0 * CLK_DIV / 266.0 / 2.0) clk = ~clk;
endmodule
