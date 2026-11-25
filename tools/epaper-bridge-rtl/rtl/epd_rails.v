// SPDX-License-Identifier: Apache-2.0
// DSI-loss watchdog and EPD PMIC rail sequencer (panel clock domain).
//
// Rails: OFF -> WAKE (wakeup=1, T_WAKE) -> UP (pwrup=1; needs pg and T_UP_MIN,
// gives up after T_UP_MAX) -> ON (rails_ok) -> DOWN (pwrup=0, T_DOWN) -> OFF.
// The PMIC's own sequencer orders the panel rails (VNEG, VGL, VPOS, VGH up;
// the reverse down); this block only owns its enables. A missing or lost
// power-good latches pg_fault: rails stay off until the bridge is reset.
//
// Watchdog: only accepted frames feed it. WD_GATE clocks after the last one the
// gate driver is disabled and the current frame stops driving; WD_RAILS clocks
// after it the rails go down. A frame accepted with PMIC_ON=0 drops the rails
// once the panel frame it started (if any) is done.
`default_nettype none
module epd_rails #(
    parameter integer WD_GATE = 1023000,   // 50 ms at 20.46 MHz
    parameter integer WD_RAILS = 3069000,  // 150 ms
    parameter integer T_WAKE = 81840,      // 4 ms
    parameter integer T_UP_MIN = 20460,    // 1 ms after pwrup before trusting pg
    parameter integer T_UP_MAX = 1023000,  // 50 ms
    parameter integer T_DOWN = 2046000     // 100 ms: PMIC power-down and discharge
) (
    input  wire clk,
    input  wire rst,
    input  wire acc,        // frame accepted
    input  wire acc_pmic,   // its PMIC_ON flag
    input  wire go,         // a panel frame started
    input  wire refused,    // frame refused
    input  wire done,       // panel frame finished
    input  wire pg,         // PMIC power good (tie 1 if the board has none)
    output reg  pmic_wakeup,
    output reg  pmic_pwrup,
    output wire rails_ok,
    output wire gdoe,
    output wire abort,      // stop driving the current frame
    output reg  pg_fault,
    output reg  wd_tripped  // the watchdog dropped the rails since the last acc
);
    localparam OFF = 3'd0, WAKE = 3'd1, UP = 3'd2, ON = 3'd3, DOWN = 3'd4;
    localparam integer TMAX = T_DOWN > T_UP_MAX ? (T_DOWN > T_WAKE ? T_DOWN : T_WAKE)
                                                : (T_UP_MAX > T_WAKE ? T_UP_MAX : T_WAKE);

    reg [2:0] s;
    reg [$clog2(TMAX+1)-1:0] t;
    reg [$clog2(WD_RAILS+1)-1:0] wd;
    reg want, off_after, gd_arm;
    reg [1:0] pg_s;

    assign rails_ok = s == ON;
    assign gdoe = gd_arm && rails_ok;
    assign abort = wd >= WD_GATE || !rails_ok;

    always @(posedge clk) begin
        pg_s <= {pg_s[0], pg};
        if (wd != WD_RAILS) wd <= wd + 1'b1;
        if (wd == WD_GATE || refused) gd_arm <= 1'b0;
        if (wd == WD_RAILS - 1) begin
            want <= 1'b0;
            wd_tripped <= 1'b1;
        end
        if (done && off_after) begin
            want <= 1'b0;
            off_after <= 1'b0;
        end
        if (go) gd_arm <= 1'b1;
        if (acc) begin
            wd <= 0;
            wd_tripped <= 1'b0;
            if (acc_pmic) begin
                want <= 1'b1;
                off_after <= 1'b0;
            end else if (go)
                off_after <= 1'b1;
            else
                want <= 1'b0;
        end

        if (t != 0) t <= t - 1'b1;
        case (s)
            OFF: if (want && !pg_fault) begin
                pmic_wakeup <= 1'b1; t <= T_WAKE; s <= WAKE;
            end
            WAKE: if (!want) begin
                pmic_wakeup <= 1'b0; s <= OFF;
            end else if (t == 0) begin
                pmic_pwrup <= 1'b1; t <= T_UP_MAX; s <= UP;
            end
            UP: if (!want) begin
                pmic_pwrup <= 1'b0; t <= T_DOWN; s <= DOWN;
            end else if (pg_s[1] && T_UP_MAX - t >= T_UP_MIN) begin
                s <= ON;
            end else if (t == 0) begin
                pg_fault <= 1'b1; pmic_pwrup <= 1'b0; t <= T_DOWN; s <= DOWN;
            end
            ON: if (!want || !pg_s[1]) begin
                if (!pg_s[1]) pg_fault <= 1'b1;
                pmic_pwrup <= 1'b0; t <= T_DOWN; s <= DOWN;
            end
            DOWN: if (t == 0) begin
                pmic_wakeup <= 1'b0; s <= OFF;
            end
            default: s <= OFF;
        endcase

        if (rst) begin
            s <= OFF; t <= 0; wd <= WD_RAILS; want <= 1'b0; off_after <= 1'b0;
            gd_arm <= 1'b0; pmic_wakeup <= 1'b0; pmic_pwrup <= 1'b0;
            pg_fault <= 1'b0; wd_tripped <= 1'b0;
        end
    end
endmodule
