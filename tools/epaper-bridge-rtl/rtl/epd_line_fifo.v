// SPDX-License-Identifier: Apache-2.0
// Dual-clock byte FIFO (gray-coded pointers), one block RAM of 2^AW bytes.
// Pointers are exported so the reader can discard up to a write-side snapshot.
`default_nettype none
module epd_line_fifo #(parameter AW = 11) (
    input  wire          wclk,
    input  wire          wrst,
    input  wire          we,
    input  wire [7:0]    wd,
    output wire          full,
    output wire          ovf,
    output reg  [AW:0]   wptr,
    input  wire          rclk,
    input  wire          rrst,
    input  wire          re,
    output reg  [7:0]    rd,
    output wire          empty,
    output wire          udf,
    output reg  [AW:0]   rptr
);
    reg [7:0] mem [0:(1 << AW) - 1];
    reg [AW:0] wg, rg, rg_w1, rg_w2, wg_r1, wg_r2;
    wire [AW:0] wnext = wptr + 1'b1;
    wire [AW:0] rnext = rptr + 1'b1;

    assign full  = wg == {~rg_w2[AW:AW-1], rg_w2[AW-2:0]};
    assign empty = rg == wg_r2;
    assign ovf   = we && full;
    assign udf   = re && empty;

    always @(posedge wclk) begin
        if (we && !full) begin
            mem[wptr[AW-1:0]] <= wd;
            wptr <= wnext;
            wg   <= wnext ^ (wnext >> 1);
        end
        {rg_w2, rg_w1} <= {rg_w1, rg};
        if (wrst) begin
            wptr <= 0; wg <= 0; rg_w1 <= 0; rg_w2 <= 0;
        end
    end

    always @(posedge rclk) begin
        if (re && !empty) begin
            rd   <= mem[rptr[AW-1:0]];
            rptr <= rnext;
            rg   <= rnext ^ (rnext >> 1);
        end
        {wg_r2, wg_r1} <= {wg_r1, wg};
        if (rrst) begin
            rptr <= 0; rg <= 0; wg_r1 <= 0; wg_r2 <= 0;
        end
    end
endmodule
