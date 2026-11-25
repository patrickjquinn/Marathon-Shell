// SPDX-License-Identifier: Apache-2.0
// Power-on reset: held for 16 clocks after configuration (registers start at 0).
`default_nettype none
module por_sync (input wire clk, output wire rst);
    reg [4:0] n = 5'd0;
    always @(posedge clk) if (!n[4]) n <= n + 1'b1;
    assign rst = !n[4];
endmodule
