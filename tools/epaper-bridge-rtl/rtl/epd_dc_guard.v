// SPDX-License-Identifier: Apache-2.0
// Panel-wide DC guard. Sums (black - white) codes over every byte shifted to the
// source drivers, frame by frame, into a signed accumulator. Per-pixel balance is
// the GPU engine's job (it holds per-pixel state; this CPLD does not), but a
// balanced waveform keeps the panel-wide sum within +-(pixels x largest potential
// swing). Past LIMIT the guard trips: no further frame is driven until the bridge
// is reset by a power cycle. Codes: 01 black (+1), 10 white (-1).
`default_nettype none
module epd_dc_guard #(parameter integer LIMIT = 1 << 25) (
    input  wire               clk,
    input  wire               rst,
    input  wire               strobe,
    input  wire [7:0]         sd,
    input  wire               frame_done,
    output reg signed [27:0]  acc,
    output reg                trip
);
    function signed [3:0] net(input [7:0] b);
        integer i;
        begin
            net = 0;
            for (i = 0; i < 8; i = i + 2)
                net = net + (b[i+:2] == 2'b01) - (b[i+:2] == 2'b10);
        end
    endfunction

    reg signed [20:0] fr;
    wire signed [27:0] sum = acc + fr;
    always @(posedge clk) begin
        if (strobe) fr <= fr + net(sd);
        if (frame_done) begin
            acc <= sum;
            fr <= 0;
            if (sum > LIMIT || sum < -LIMIT) trip <= 1'b1;
        end
        if (rst) begin
            acc <= 0; fr <= 0; trip <= 1'b0;
        end
    end
endmodule
