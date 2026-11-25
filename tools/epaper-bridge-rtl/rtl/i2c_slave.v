// SPDX-License-Identifier: Apache-2.0
// Byte-level I2C slave, 7-bit address, oversampled by clk (>= 16x SCL; 20.46 MHz
// covers 1 MHz). SCL and SDA are open drain: *_oe = 1 pulls the line low.
//
// Upper-layer contract:
//   start/stop  pulse on S (or Sr) and P.
//   wr_byte     pulse with rx when a written data byte (not the address) has
//               been shifted in; ack must be valid by the next SCL fall.
//   rd_req      pulse when the master wants the next byte (after the address
//               with R, and after each master ACK); tx is taken once hold is 0.
//   hold        stretches SCL at byte boundaries while 1. Every wr_byte and
//               rd_req is issued with hold low, so the upper layer is idle then.
`default_nettype none
module i2c_slave #(parameter [6:0] ADDR = 7'h4B) (
    input  wire       clk,
    input  wire       rst,
    input  wire       scl_i,
    input  wire       sda_i,
    output reg        scl_oe,
    output reg        sda_oe,
    input  wire       addr_en,   // answer the address at all
    output reg        start,
    output reg        stop,
    output reg        wr_byte,
    output reg  [7:0] rx,
    input  wire       ack,
    output reg        rd_req,
    input  wire [7:0] tx,
    input  wire       hold,
    output wire       busy       // between our address ACK and the following P/Sr
);
    localparam IDLE = 3'd0, ADR = 3'd1, AACK = 3'd2, WR = 3'd3, WACK = 3'd4,
               RD = 3'd5, RACK = 3'd6;

    // 2-FF synchroniser, then accept a level only after two equal samples.
    reg [1:0] scl_s, sda_s;
    reg [1:0] scl_h, sda_h;
    reg scl, sda, scl_d, sda_d;
    always @(posedge clk) begin
        scl_s <= {scl_s[0], scl_i};
        sda_s <= {sda_s[0], sda_i};
        scl_h <= {scl_h[0], scl_s[1]};
        sda_h <= {sda_h[0], sda_s[1]};
        if (scl_h[1] == scl_h[0]) scl <= scl_h[1];
        if (sda_h[1] == sda_h[0]) sda <= sda_h[1];
        scl_d <= scl;
        sda_d <= sda;
        if (rst) begin
            scl_s <= 2'b11; sda_s <= 2'b11; scl_h <= 2'b11; sda_h <= 2'b11;
            scl <= 1'b1; sda <= 1'b1; scl_d <= 1'b1; sda_d <= 1'b1;
        end
    end
    wire rise = scl && !scl_d, fall = !scl && scl_d;
    wire s_det = scl && scl_d && sda_d && !sda;
    wire p_det = scl && scl_d && !sda_d && sda;

    reg [2:0] st;
    reg [3:0] n;
    reg [7:0] sr;
    reg       rw, stretch;
    reg [2:0] rel;
    reg [1:0] sp;
    assign busy = st != IDLE && st != ADR;

    always @(posedge clk) begin
        start <= 1'b0; stop <= 1'b0; wr_byte <= 1'b0; rd_req <= 1'b0;
        if (s_det) begin
            start <= 1'b1; st <= ADR; n <= 0; sda_oe <= 1'b0; scl_oe <= 1'b0; stretch <= 1'b0;
        end else if (p_det) begin
            stop <= 1'b1; st <= IDLE; sda_oe <= 1'b0; scl_oe <= 1'b0; stretch <= 1'b0;
        end else if (stretch) begin
            // SCL held low until the upper layer is idle; a read then asks for its
            // byte and waits for it, and SDA gets set-up time before SCL is let go.
            case (sp)
                2'd0: if (!hold) begin
                    if (st == RD) begin rd_req <= 1'b1; rel <= 3'd3; sp <= 2'd1; end
                    else begin rel <= 3'd4; sp <= 2'd3; end
                end
                2'd1: if (rel != 0) rel <= rel - 1'b1; else sp <= 2'd2;
                2'd2: if (!hold) begin
                    sr <= {tx[6:0], 1'b0};
                    sda_oe <= !tx[7];
                    n <= 1;
                    rel <= 3'd4;
                    sp <= 2'd3;
                end
                default: if (rel != 0) rel <= rel - 1'b1;
                         else begin scl_oe <= 1'b0; stretch <= 1'b0; end
            endcase
        end else case (st)
            ADR: if (rise) begin
                sr <= {sr[6:0], sda};
                n <= n + 1'b1;
            end else if (fall && n == 8) begin
                if (sr[7:1] == ADDR && addr_en) begin
                    sda_oe <= 1'b1;
                    rw <= sr[0];
                    st <= AACK;
                end else
                    st <= IDLE;
            end
            AACK: if (fall) begin
                sda_oe <= 1'b0;
                n <= 0;
                st <= rw ? RD : WR;
                if (rw || hold) begin
                    scl_oe <= 1'b1; stretch <= 1'b1; sp <= 0;
                end
            end
            WR: if (rise) begin
                sr <= {sr[6:0], sda};
                n <= n + 1'b1;
                if (n == 7) begin
                    rx <= {sr[6:0], sda};
                    wr_byte <= 1'b1;
                end
            end else if (fall && n == 8) begin
                sda_oe <= ack;
                st <= WACK;
            end
            WACK: if (fall) begin
                sda_oe <= 1'b0;
                n <= 0;
                st <= ack ? WR : IDLE;
                if (ack && hold) begin
                    scl_oe <= 1'b1; stretch <= 1'b1; sp <= 0;
                end
            end
            RD: if (fall) begin
                if (n == 8) begin
                    sda_oe <= 1'b0;
                    st <= RACK;
                end else begin
                    sda_oe <= !sr[7];
                    sr <= {sr[6:0], 1'b0};
                    n <= n + 1'b1;
                end
            end
            RACK: if (rise) begin
                if (sda) st <= IDLE;   // NACK: last byte
            end else if (fall) begin
                st <= RD;
                scl_oe <= 1'b1; stretch <= 1'b1; sp <= 0;
            end
            default: ;
        endcase
        if (rst) begin
            st <= IDLE; n <= 0; sda_oe <= 1'b0; scl_oe <= 1'b0; stretch <= 1'b0; rel <= 0;
            rw <= 1'b0;
        end
    end
endmodule
