// SPDX-License-Identifier: Apache-2.0
// Internal oscillator: 266 MHz / CLK_DIV (UG030003 Table 50). 13 gives 20.46 MHz,
// the CCS system clock UG030004 ch. 5 quotes. Simulation uses tb/osc_model.v.
`default_nettype none
module pgc_osc #(parameter integer CLK_DIV = 13) (output wire clk);
    GTP_OSC_E2 #(.USER_DIV_EN("TRUE"), .CLK_DIV(CLK_DIV)) osc (
        .CLKOUT(clk), .CLKCRC(), .EN_N(1'b0)
    );
endmodule
