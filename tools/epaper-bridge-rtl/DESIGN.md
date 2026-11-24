# MP01 direct-drive bridge: design

2026-11-24. Everything here was built and checked offline (iverilog, yosys, rustc). Nothing
touched a device.

Tags: **[P]** proved from bytes, logs or tests we hold · **[D]** Pango document · **[I]** inference
· **[H]** needs the board.

Sources: `~/q25-build/mp01-inventory/cpld/re/` (`WAVEFORM_AND_DIRECT_MODE.md`,
`DIRECT_MODE_NO_PDS.md`, `HARD_I2C_PORT.md`, `REGISTER_MAP.md`, `vendor-src/`), `../panel-and-pinout.md`,
the 2026-11-24 device logs in `../uflash-out/`, UG030003/UG030004 v1.7/UG030005, DS03001 v1.6.

---

## 0. Summary

| | |
|---|---|
| What it is | A stateless bridge in the PGC4KLS. The GPU engine (`crates/marathon-epd`) computes a 2-bit drive code per pixel per panel frame and sends it over the **stock** DSI link; the CPLD checks it, shifts it to the source drivers and clocks the gate driver. It owns no waveform and no frame memory. |
| Link | Stock MP01 DSI mode (800×600 RGB888, 4 lanes, video sync-pulse). One panel row per DSI line, header in line 0. Panel frame rate = DSI frame rate: 60 Hz stock, 85 Hz by raising only the pixel clock. **Link v2**; supersedes Option B (800×51) and the 68×601 plan, which both needed a display-mode change. |
| Reflash path | Reproduces v36's I2C slave at 0x4b: user registers 0x80–0x8F and the eflash opcodes forwarded to the internal slave APB (`GTP_APB`). Erase, lock and CFG opcodes are refused in hardware. |
| Safety | Outputs inactive from configuration; no drive without a valid header with seq = last + 1; no drive without PMIC power-good; a row is shifted only after its DSI line passed its checksum; DSI loss stops drive within 100 µs, gate driver off at 50 ms, rails down at 150 ms; a panel-wide DC guard; bounded APB waits. |
| Recovery | Optional dead-man: an image the host cannot talk to blanks the first page of its own application slot, so the next power-up falls back to golden v0305 [H: fallback on the 4KL is undocumented]. |
| Size | 1,448 LUT4 + 829 FF + 2 DRMs for everything except the D-PHY RX (yosys generic). With a 4-lane soft D-PHY RX, ~2.0–2.4 k of 4,032 LUT4 (§8). |
| Tests | `make test`: 15 datapath scenarios + bus timing (5.3 M checks), I2C/APB suite against a CCS model (103 + 14 checks), engine-vector run, yosys estimate. All pass (§9). |
| Missing | The D-PHY RX + DSI parser (needs Pango I/O primitives) and the board pinout. Both need PDS; see `PDS_BRINGUP.md`. Ranked unknowns in §10. |

---

## 1. Architecture

```
            DSI 4 lanes (bank 2)                       I2C i2c-7 (0x4b, <= 400 kHz)
                 │                                                │
        ┌────────▼─────────┐  rx_clk                     ┌────────▼─────────┐   GTP_APB
        │ dphy_rx_stub      │ (free-running)             │ i2c_slave         │   (SEL_CCS)
        │ D-PHY RX + parser │                            │ cfg_bridge        ├──────────► CCS / eflash
        │ [needs PDS]       │                            │  user regs, APB   │
        └────────┬─────────┘                             │  master, dead-man │
   32-bit words, │ line/frame strobes, line CRC ok        └────────▲─────────┘
        ┌────────▼─────────┐                                      │ status
        │ epd_unpack        │ header, seq, faults ──toggles──┐     │
        └────────┬─────────┘                                 │     │
                 │ row words                                 │     │
        ┌────────▼─────────┐                       clk (OSC 20.46 MHz)
        │ epd_line_fifo     │ 512 × 32, 2 DRMs  ┌────────────▼─────┴──────────┐
        └────────┬─────────┘                    │ epd_timing   (line-paced)    │──► SDCLK SDLE SDOE SPH SD[7:0]
                 └─────────────────────────────►│ epd_dc_guard                 │──► GDCLK(CPV) GDSP(STV) GDOE
                                                │ epd_rails    (watchdog, PMIC)│──► PMIC WAKEUP, PWRUP ◄── PG
                                                └──────────────────────────────┘
```

Files: `rtl/epd_bridge_top.v` (full image), `rtl/epd_stage1_top.v` (bring-up image, §7.6),
`rtl/epd_bridge_core.v` and below, `rtl/cfg_bridge.v`, `rtl/i2c_slave.v`, `rtl/pango/` (the two
primitive wrappers), `rtl/dphy_rx_stub.v`.

## 2. Interfaces and clocking

### 2.1 Clocks and reset

| Clock | Source | Frequency | Runs |
|---|---|---|---|
| `clk` | `GTP_OSC_E2`, `CLK_DIV = 13` (266 MHz / 13) [D UG030003 Table 50] | 20.46 MHz, ±5.5 % (C) / ±10 % (I) [D DS03001 Table 2-8] | panel timing, SDCLK, I2C slave (oversampled), APB, watchdog, rails, dead-man |
| `rx_clk` | from the receiver: a `GTP_PLL_E2` output off the oscillator, free-running | ≥ 40 MHz (the payload is ≤ 36.8 M words/s at 85 Hz) | `epd_unpack`, FIFO write side |

- The oscillator is independent of the DSI link, so the watchdog, the I2C bridge and the rails work
  with the link down. The CCS itself uses the same 20.46 MHz figure (UG030004 ch. 5).
- SDCLK = `clk` through an output DDR (D0 = 0, D1 = strobe): 48.9 ns nominal, 44.4 ns at +10 %,
  against the panel's ≥ 40 ns [D GDE043A2].
- Reset: `por_sync` holds every register in reset for 16 clocks after configuration. No external
  reset pin is used: GPIO85 (`reset-gpios` in `Z10.dts`) may be the CPLD's RSTN ball (C7, live in
  user mode), and its role in v36 is unknown (§10).
- Clock-domain crossings: the FIFO (gray pointers), single-bit toggles for frame and row events, and
  bundles (`f_*`, `last_seq`, `err_cnt`) that are stable from one toggle to the next.

### 2.2 Pins (logical; balls come from the PDS I/O decode, `PDS_BRINGUP.md` §2)

| Port | Dir | Bank / standard (expected) | Reset / idle | Notes |
|---|---|---|---|---|
| `dsi_ck_p/n`, `dsi_d_p/n[3:0]` | in | bank 2, `GTP_IOBUF_RX_MIPI`, 100 Ω | — | lanes 2/3 swapped by the SoC (`lane_swap`) |
| `i2c_scl`, `i2c_sda` | inout, open drain | the balls v36 uses for 0x4b, **not G4/G5** (§10) | released | 2.2 kΩ pull-ups on the board [I] |
| `epd_sdclk` | out | LVCMOS, ODDR | 0 | source CLK |
| `epd_sdle` | out | LVCMOS | 0 | source LE |
| `epd_sdoe` | out | LVCMOS | 0 | source OE |
| `epd_sph` | out | LVCMOS | 1 (inactive) | source start pulse, active low |
| `epd_sd[7:0]` | out | LVCMOS | 0 | D0–D7, four pixels per SDCLK |
| `epd_gdclk` | out | LVCMOS | 0 | gate CPV |
| `epd_gdsp` | out | LVCMOS | 1 (inactive) | gate STV, active low |
| `epd_gdoe` | out | LVCMOS | 0 | gate output enable / GMODE, if the board drives one |
| `pmic_wakeup`, `pmic_pwrup` | out | LVCMOS | 0 | PMIC enables (TPS65185-style names) |
| `pmic_pg` | in | LVCMOS | — | power good; tie 1 in the top if the board has none |

`OUT_EN` (top parameter) holds the panel outputs (bit 0) or the PMIC enables (bit 1) low, for
staged bring-up. With bit 1 clear, power-good is also masked, so nothing can drive.

## 3. DSI link (link v2)

### 3.1 The stock mode, kept as is [P `panel-z10-eink-vdo.c`]

| | Value |
|---|---|
| Active | 800 × 600, RGB888 (`MIPI_DSI_FMT_RGB888`) |
| Horizontal | HFP 20, HSA 16, HBP 20 → HTOTAL 856 |
| Vertical | VFP 54, VSA 10, VBP 10 → VTOTAL 674 |
| Lanes | 4, `lane_swap` 2↔3 |
| Flags | `VIDEO`, `VIDEO_SYNC_PULSE`, `LPM`, `EOT_PACKET`, `CLOCK_NON_CONTINUOUS` |

| Frame rate | Pixel clock | Lane rate | Byte clock | DSI line | Panel line busy |
|---|---|---|---|---|---|
| 60 Hz (stock) | 34.62 MHz | 208 Mbit/s | 26.0 MHz | 24.7 µs | 10.6 µs |
| 85 Hz | 49.04 MHz | 294 Mbit/s | 36.8 MHz | 17.5 µs | 10.6 µs |

85 Hz changes only `clock` in the DRM mode; the MT6789 PLL range (125 Mbit/s–1.6 Gbit/s per lane)
and the CPLD MIPI input (≤ 900 Mbit/s at -6) both cover it [V, `WAVEFORM_AND_DIRECT_MODE.md` §3.3].

### 3.2 Payload layout

A DSI line is one RGB888 long packet of 2,400 bytes. Wire byte order within a pixel is B0, B1, B2
(B0 first; which of R/G/B that is gets pinned at bring-up, `link.rs::to_xrgb8888`).

| Bytes of DSI line *r* (0–599) | Content |
|---|---|
| 0–31 | line 0: header; other lines: ignored (sent as 0) |
| 32–231 | panel row *r*: byte *j* = columns 4*j*…4*j*+3, the first in bits 7:6 |
| 232–2399 | padding, ignored |

Codes: 00 no drive, 01 toward black, 10 toward white, 11 reserved (masked to 00 by the bridge).
This is the engine's drive buffer row for row (`engine::drive_len` layout); `link::pack_frame` copies
each 200-byte row to offset 32 of its line, and a GPU path can write the scanout buffer directly
with a 2,400-byte stride.

Header (line 0, bytes 0–31, little-endian), unchanged from Option B except the version:

| Bytes | Field |
|---|---|
| 0–3 | magic `EPD1` |
| 4 | version = **2** |
| 5 | flags: bit 0 DRIVE, 1 PMIC_ON, 2 VCOM_SET, 3 RESYNC; bits 7:4 must be 0 |
| 6–7 | reserved |
| 8–11 | seq (u32) |
| 12–13, 14–15 | scan_first, scan_last (rows, inclusive) |
| 16–17 | vcom_mv |
| 18–27 | reserved |
| 28–29 | CRC-16/MCRF4XX over bytes 0–27 (the DSI long-packet checksum, so one circuit) |
| 30–31 | reserved |

The receiver hands `epd_unpack` the payload as 32-bit words (byte 0 in bits 7:0), so the header is
words 0–7 and the row is words 8–57, both word-aligned. The header is decided on word 7, before any
row word, so line 0 carries row 0 too.

### 3.3 Acceptance rules (`epd_unpack`; reference model `link::Bridge`)

1. A header is valid if magic, version, reserved flags and CRC match, RESYNC and DRIVE are not both
   set, and for DRIVE `scan_first ≤ scan_last < 600`.
2. RESYNC sets the sequence base and is accepted (rails request, watchdog feed) without drive. A
   RESYNC that repeats the last accepted seq while synced is a **rescan of the same buffer**: refused,
   sync kept, watchdog not fed. `Sequencer::resync` therefore takes a fresh seq.
3. Any other frame is accepted only if synced and seq = last + 1. A valid header with the wrong
   seq drops sync (the MediaTek controller rescanning a stale buffer drives at most once).
4. DRIVE is refused while the rails are not up or the DC guard has tripped (`drive_ok`), **without**
   dropping sync, so the host can retry the same seq.
5. Line faults in a driving frame (length ≠ 600 words, bad packet checksum, FIFO overflow) end the
   frame's drive: the rest of the frame scans with no drive. A row is shifted only after its own line
   arrived whole with a good checksum, so a corrupt line is never driven (this closes Option B's
   "three rows latched before the checksum" gap).

### 3.4 Receiver contract (`dphy_rx_stub.v`, to be built in PDS)

On `rx_clk`: `frame_start` once per VSS; for each RGB888 long packet `line_start`, up to one
`rx_valid` word per clock with the payload re-aligned so byte 0 is in bits 7:0, then `line_end` with
`line_crc_ok`. The non-continuous HS clock stops in LP between lines, so the receiver needs a small
CDC FIFO from the byte clock into `rx_clk`. Primitives: `GTP_IOBUF_RX_MIPI` (HS + LP on the same
pads), `GTP_ISERDES_E1` 1:8, `GTP_IOCLKBUF`/`GTP_IOCLKDIV_E1`, `GTP_PLL_E2` [D UG030005, UG030003].
Open skeletons to port: gatecat CSI2Rx (iCE40), Lattice RD1182/RD1185 for sizing.

## 4. Panel timing (`epd_timing`)

GDE043A2-class 8-bit bus, 800 × 600, scan windows after Caster.

| Item | Value (clk = 20.46 MHz) | Limit |
|---|---|---|
| Line | HFP 12 + HSYNC 2 + HBP 2 + 200 shift = 216 clocks = 10.56 µs busy | — |
| SDCLK | 48.9 ns (44.4 ns at +10 %) | ≥ 40 ns |
| SD/SPH setup, hold | ≥ 1 clock | ≥ 8 ns |
| SDLE width | 2 clocks = 98 ns | ≥ 40 ns |
| Line period | **= DSI line period**: 24.7 µs at 60 Hz, 17.5 µs at 85 Hz | CPV ≤ 200 kHz (≥ 5 µs) |
| CPV high / low | ≈ 10.0 µs / ≈ 14.7 µs at 60 Hz | ≥ 0.5 µs each |
| Frame | VFP 0, VSYNC 1, VBP 0, 600 rows, VTAIL 1 [H: row-to-gate alignment unverified] | — |
| Frame rate | = DSI frame rate (60 / 85 Hz) | — |

**Line pacing.** Each data line waits at h = 0 for a row credit (one per DSI line that arrived
whole), so the panel line period locks to the DSI line period and the FIFO never holds more than a
couple of rows (peak 85 of 512 words in simulation). Row *r* is shifted during DSI line *r* + 1 and
latched by the next line's SDLE. Credits that do not come within `ROW_TO` = 2,048 clocks (100 µs,
four DSI lines) mean the link died mid-frame: the frame finishes its scan with no drive.

## 5. PMIC rails (`epd_rails`)

The PMIC is not identified. Smart Season's PGC4KLS e-ink board uses a Fitipower FP9931 [V photo];
TPS65185 is the reference class. The bridge owns only enables; the PMIC's sequencer orders the panel
rails, which is the stock order:

- power-up: VDD (logic, already on with the CPLD) → VNEG (−15 V) → VGL/VEE (−20 V) → VPOS (+15 V)
  → VGH/VDDH (+22 V); TPS65185 default 6 ms steps [D GDE043A2 "VDD → VNEG → VPOS, VGL → VGH";
  TPS65185 SLVSAQ8G];
- power-down: the reverse, then discharge (TPS65185: 6/24/48 ms + ~100 ms).

| State | Outputs | Leaves when |
|---|---|---|
| OFF | WAKEUP 0, PWRUP 0 | an accepted frame has PMIC_ON (and no latched fault) |
| WAKE | WAKEUP 1 | `T_WAKE` = 4 ms (PMIC wake-up, TPS65185 2.5–4 ms); or request dropped → OFF |
| UP | WAKEUP 1, PWRUP 1 | PG high and ≥ `T_UP_MIN` = 1 ms → ON; `T_UP_MAX` = 50 ms without PG → fault; request dropped → DOWN |
| ON (`rails_ok`) | WAKEUP 1, PWRUP 1 | request dropped → DOWN; PG lost → fault, DOWN |
| DOWN | WAKEUP 1, PWRUP 0 | `T_DOWN` = 100 ms (sequenced power-down + discharge), then OFF |

- A PG timeout or PG loss latches `pg_fault`: rails stay off until the bridge is reset (power
  cycle). No retry storm.
- Requests: an accepted frame with PMIC_ON raises it; one without PMIC_ON drops it, after the panel
  frame it started (if it drives); the watchdog drops it.
- VCOM: `vcom_mv` from a VCOM_SET header is latched (`vcom_mv`, `vcom_upd`) for a PMIC I2C master
  that is **not built** until the board shows how v36 reaches the PMIC (§10, unknown 2).

## 6. I2C slave and APB bridge (`i2c_slave`, `cfg_bridge`)

### 6.1 Bus

7-bit address 0x4b, open drain, oversampled by `clk` with a two-sample glitch filter; works to
1 MHz, 400 kHz recommended (UG030004 Table 4-4; the vendor DT's 1 MHz is out of spec). The slave
stretches SCL at byte boundaries while an APB transfer is outstanding (a few hundred ns, inside
SCL low at 400 kHz, so normally invisible). The state that a write sets up (register pointer,
read source) survives STOP, so both shapes the device tools used work:
`S W … P S R … P` (vendor) and `S W … Sr R … P`.

### 6.2 Framing (vendor driver `panel-z10-eink-i2c.c`; v36 device logs 2026-11-24)

APB addresses: IDCODER0–3 0x00–0x03, STATUSR0–3 0x10–0x13, CMDR 0x15, ADR0–2 0x16–0x18,
DATATR 0x19, DATARR 0x1A (UG030004 Table 9-8). Eflash address bytes `A2 A1 A0` =
`(page / 320) << 17 | (page % 320) << 8`, MSB first; they are ADR2 (heap, page[8]), ADR1
(page[7:0]), ADR0 (word offset) (Tables 16-23–16-25). Page 572 = `02 FC 00`, page 1279 = `07 3F 00`.

| Op | Host writes (`S 4b+W … P`) | Host reads (`S 4b+R …`) | APB transfers the bridge makes |
|---|---|---|---|
| user read | `8r` | 1 byte (repeats on a burst) | — |
| user write | `8r vv` | — | — (only `89 A5` has an effect) |
| WREN | `51` | — | CMDR ← FF, CMDR ← 51 |
| WRDIS | `52` | — | CMDR ← 52, CMDR ← FF |
| RESET / EFLASH_SLEEP / EFLASH_WAKEUP | `60` / `70` / `71` | — | CMDR ← op |
| RDID | `A1 00 00 00` | 4 bytes, IDCODE LSB first: `99 28 42 a0` | read 0x00–0x03 |
| RDSR | `A3 00 00 00` | 4 bytes, STATUS LSB first (today `d0 ef 89 14`) | read 0x10–0x13 |
| READ | `30 A2 A1 A0 00` | 256 bytes | ADR0 ← A0, ADR1 ← A1, ADR2 ← A2, CMDR ← 30; one DATARR read per byte; CMDR ← FF at the STOP |
| READ_CTL | `31 00 00 00 00` | 4 bytes, CTL LSB first (today `41 83 b2 40`) | CMDR ← 31; DATARR × 4; CMDR ← FF at the STOP |
| PROGRAM | `20 A2 A1 A0 d0 … d255` | — | ADR0–2, CMDR ← 20, DATATR × 256 |
| PROGRAM_CTL | `21 00 00 00 c0 c1 c2 c3` | — | CMDR ← 21, DATATR × 4 |
| anything else | first byte **NACKed** | — | none |

Host sequences stay the vendor's: WREN before READ, READ_CTL, PROGRAM and PROGRAM_CTL, and RDSR
polls on bit 21 (busy) after a program. Refused: ERASE 10, ERASE_PAGE 11, ERASE_CTL 12
(it wedged v36's bridge on 2026-11-24), PROGRAM_LOCK 40, CFG 50, the slave-port codes 22/53–56,
RDUID A4, NOP FF, and anything ≥ 0x90 that would alias a flash opcode with bit 7 ignored.
PROGRAM overwrites a page without an erase (proved on the device), so no erase is ever needed.

The NOP pairing (NOP before WREN, NOP after WRDIS and after a data read) follows the APB flows of
UG030004 Appendix 7; what v36's own bridge sends to CMDR is not observable [H, §10].

### 6.3 User registers (0x80–0x8F)

| Reg | Access | Content |
|---|---|---|
| 0x80 | R | firmware version: **0x82** full bridge, **0x81** stage-1 image (v36: 0x36) |
| 0x81 | R | status: [0] synced [1] rails_ok [2] pg_fault [3] dc_trip [4] wd_tripped [5] apb_timeout (sticky) [6] dead-man armed [7] dead-man fired |
| 0x82 | R | refused-frame count (saturating) |
| 0x83 | R | data-path fault count (saturating) |
| 0x84 | R | link id: **0xD2** (link v2), **0xD0** stage-1 (v36: 0x10, waveform 16) |
| 0x85 | R | last accepted seq, low byte |
| 0x86, 0x87 | R | DC accumulator bits 27:20, 19:12 |
| 0x89 | R/W | write `A5` disarms the dead-man; reads {7'b0, armed} |
| others | R | `DE`, as v36 reads undecoded registers |

All writes to 0x80–0x8F are ACKed, so the vendor and Marathon kernel drivers' 0x8C/0x8E writes do
not fail; only `89 A5` does anything. Tools tell the designs apart by `80`/`84`: 36/10 (v36),
81/D0 (stage 1), 82/D2 (bridge).

### 6.4 The APB module boundary

`cfg_bridge` is an APB3 master (`psel`, `penable`, `pwrite`, `paddr[4:0]`, `pwdata`, `prdata`,
`pready`). `rtl/pango/pgc_ccs_apb.v` is the only place the primitive appears:

```verilog
GTP_APB apb (.CLK(clk), .RST_N(rst_n), .ADDR(paddr), .SEL_CCS(psel), .SEL_SPI(1'b0),
             .SEL_I2C0(1'b0), .SEL_I2C1(1'b0), .SEL_TIMER(1'b0), .SEL_PLL0(1'b0), .SEL_PLL1(1'b0),
             .EN(penable), .WR(pwrite), .WDATA(pwdata), .RDATA(prdata), .RDY(pready), .IRQ(), .IRQ_CCS());
```

(port list UG030003 Table 47; signals UG030004 Table 9-7). Simulation swaps in `tb/ccs_model.v`.
Every transfer waits for PREADY at most `APB_TO` = 4,095 clocks (200 µs); a timeout returns FF,
sets status bit 5 and releases SCL, so a wedged CCS cannot hold i2c-7 low.

### 6.5 Dead-man (bring-up recovery)

With `DEADMAN_CLKS` ≠ 0 (top default 100 s), if nothing writes `89 A5` within that time of power-up,
the bridge waits for an idle bus, NACKs its address, and runs NOP, WREN, ADR ← `02 FC 00`,
PROGRAM, 256 × DATATR 00, RDSR-polls busy (≤ 100 ms), WRDIS, NOP. Page 572 holds the image's
`.sbit` header and its sync word (offset 200), so the next application load finds no sync, the
configuration watchdog (on in golden's preamble, ≈ 102 ms) times out, and the CCS falls back to
golden v0305 at page 0 (UG030004 ch. 5). The host then rewrites pages 572–1142.

- It protects against the stage-1 failure that has no other way out: an image whose I2C pins or
  front end are wrong on the board.
- It assumes golden fallback works on this 4KLS [H]; Table 5-1 lists master-self-download dual
  boot for 4KD only, yet the shipped image uses it.
- The host (bring-up tool, and later the kernel driver at probe and resume) must disarm it on every
  CPLD power-up. Production images can be built with `DEADMAN_CLKS = 0` once the reflash loop is
  proved.

## 7. Safety

The rule from the research: no unbounded drive, and nothing driven on a guess.

| # | Invariant | Where | Test |
|---|---|---|---|
| 1 | All outputs inactive from configuration: SD 0, SDCLK/LE/OE/CPV 0, SPH/STV 1, GDOE 0, PMIC enables 0 | reset values; `por_sync` | tb_bridge reset check; tb_i2c (stage 1 never leaves 0) |
| 2 | No drive without a valid header, seq = last + 1 after a RESYNC; stale buffers, boot logos, rescans are inert | `epd_unpack` | (a)–(e), (n), (d) |
| 3 | No drive without PMIC power-good; SDOE/GDOE only with rails up; PWRUP only after WAKEUP, WAKEUP only after PWRUP falls | `epd_rails`, `drive_ok` | (m), timing checks on every edge |
| 4 | A row is driven only after its line's length and checksum are good; any line fault blanks the rest of the frame | `epd_unpack`, `epd_timing` | (g), (k), (h) |
| 5 | **DSI-loss watchdog:** no row credit for 100 µs → stop driving; 50 ms (`WD_GATE`) after the last accepted header → gate driver off; 150 ms (`WD_RAILS`) → PWRUP off, then WAKEUP after `T_DOWN` | `epd_timing`, `epd_rails` | (i): stopped 109 µs after the loss; GDOE, PWRUP, WAKEUP at 40.0, 60.0, 65.0 ms (tb values) |
| 6 | **DC guard:** Σ(black − white) codes actually shifted, over all frames since power-up; past ±`DC_LIMIT` (2²⁵ ≈ 2.3 × the full-panel swing of a balanced 16-level waveform) no frame drives until a power cycle | `epd_dc_guard` | (o) |
| 7 | Code 11 never reaches the panel | `epd_timing` mask | (j) |
| 8 | The flash can only be read and overwritten page by page; erase, lock, CFG never reach the CCS | `cfg_bridge` opcode table | tb_i2c refused-opcode set, CMDR trace |
| 9 | No unbounded wait: APB 200 µs, PMIC power-good 50 ms, dead-man poll 100 ms | `cfg_bridge`, `epd_rails` | tb_i2c stuck-APB case |
| 10 | G4/G5 belong to the hard slave-I2C port (now persisted at 0x2C): never user I/O | PDS constraint | `PDS_BRINGUP.md` §3 |

Per-pixel DC balance needs per-pixel state, which this design deliberately does not hold (the
in-package PSRAM is unused); the engine tracks per-pixel net drive (`engine::Dc`) and is the primary
control. The guard catches runaway one-sided drive (a stuck or buggy engine); with balanced
waveforms the panel-wide sum stays within ±(pixels × largest potential), about ±14.4 M for a
30-frame swing.

## 8. Resources

yosys 0.67, `synth -flatten -lut 4` then `abc -lut 4`, Pango primitives and the D-PHY stub as
blackboxes (`make lut`). Generic LUT4 counts: the Compa CLM has LUT5s, so these are upper bounds.

| Block | LUT4 | FF | Block RAM |
|---|---|---|---|
| `epd_unpack` | 322 | 277 | — |
| `epd_timing` | 211 | 107 | — |
| `epd_dc_guard` | 142 | 50 | — |
| `epd_rails` | 155 | 57 | — |
| `epd_bridge_core` (with FIFO control, CDC, status) | 882 | 609 | 512 × 32 = 2 DRMs (512 × 18 mode) |
| `i2c_slave` | 101 | 49 | — |
| `cfg_bridge` incl. slave, dead-man on | 566 | 264 | — |
| **`epd_stage1_top`** | **542** | **269** | — |
| **`epd_bridge_top`** (all of the above) | **1,448** | **829** | **2 of 11 DRMs** |
| D-PHY RX + DSI parser, 4 lanes (estimate: Lattice RD1182 4-lane RX 557 LUT4 / 617 FF; RD1185 full bridge 903 / 1,100) | 560–900 | 620–1,100 | 0–1 |
| **Total** | **~2.0–2.4 k of 4,032 (50–60 %)** | ~1.5–1.9 k | 2–3 of 11 |

v36 fills 3,998 of 4,032 LUT sites with a 4-lane receiver and a full TCON, so this fits with room.
If the receiver comes out large, a 1- or 2-lane link at ≥ 125 Mbit/s per lane is the fallback (a
MediaTek mode change, `WAVEFORM_AND_DIRECT_MODE.md` §4.4).

## 9. Verification (`make test`)

| Target | What | Result (2026-11-24) |
|---|---|---|
| `sim` | `tb_bridge.v` + `gen_vectors.py`: 30 link v2 frames at the stock 60 Hz line rate (26 MHz word clock, 20.46 MHz panel clock), source-driver latch model, PMIC model with a 3 ms power-good delay. 15 scenarios a–o, plus every AC limit on every edge, rails ordering, and the reset state | PASS, 5.3 M checks |
| `i2c` | `tb_i2c.v` on `epd_stage1_top` + `ccs_model.v` (IDCODE, STATUSR, CTL and overwrite semantics from the device logs), 400 kHz master with clock stretching, both STOP and Sr framings. `+dm=0`: user regs, kernel writes, RDID, RDSR, READ_CTL, READ / PROGRAM / overwrite / blank of page 1279, PROGRAM_CTL and restore, WAKEUP/SLEEP/WRDIS, 10 refused opcodes, stuck APB. `+dm=1`: dead-man blanks page 572 only, with the exact CMDR sequence | PASS, 103 + 14 checks; mutating the ADR order, the NOP/WREN pairing, the RDSR base or the opcode table each fails it |
| `lut` | yosys estimate | §8 |
| `test-engine EPD_TOOL=…` | `epd-tool vectors` (the real CPU engine, link v2 via `link::pack_frame`) → `engine_vectors.py` → `tb_bridge` | PASS: 6 frames (resync, 4 driving a moving bar, drain); every latched row matches the engine's drive buffer |

`epd-tool` was built with plain `rustc` (the crate has no dependencies without `gles`); the crate's
24 unit tests pass with the link v2 changes.

## 10. Open unknowns, ranked

1. **The board pinout** (every panel, PMIC and I2C ball). Blocks any load. Comes from the PDS I/O-tile
   decode of v36 cross-checked on v0305 and v25 (`PDS_BRINGUP.md` §2). The I2C pair is **not** G4/G5:
   persisting the hard port there on 2026-11-24 left 0x4b answering and nothing at 0x2C (case B).
2. **The PMIC and how v36 controls it.** 0x8F (temperature, 0x15 = 21 °C) and 0x8A (VCOM 0x70) are
   live in v36, which suggests v36 has an I2C master to the PMIC. If the decode shows an open-drain
   pair to the PMIC, a small I2C master (VCOM write, temperature read, maybe the enables by register:
   ~100–150 LUT4) has to be written against that PMIC's register map before rails come up. If the
   enables are pins, `epd_rails` is complete as is.
3. **What v36's bridge writes to CMDR** (the NOP pairing, whether NOP clears WREN, whether READ needs
   a NOP after it). Ours follows UG030004 Appendix 7 and is proved only against the model. The stage-1
   load is the test; the dead-man covers a failure.
4. **Golden fallback on the 4KLS** (Table 5-1 says 4KD only). Needed for the dead-man to recover a
   dead stage-1 image. Untested on hardware.
5. **Panel row/gate alignment** (VFP/VSYNC/VBP/VTAIL, which gate row the first SDLE lands on, SHR,
   L/R, GMODE straps). Visible only on the panel: stage 3 with a single patch.
6. **Byte order of the RGB888 wire** (which of R/G/B is B0) and the receiver's word alignment.
   Pinned by a DSI capture or by the stage-2 header CRC counters.
7. **GPIO85** (`reset-gpios`): RSTN ball C7 or a user reset input. The design ignores it.
8. **D-PHY RX timing closure** at 294 Mbit/s with a non-continuous clock (low risk: v36 does it at
   208 Mbit/s).

## 11. Files

| Path | What |
|---|---|
| `rtl/epd_bridge_top.v`, `rtl/epd_stage1_top.v` | full image; stage-1 image (I2C bridge only, outputs low) |
| `rtl/epd_bridge_core.v` | datapath, CDC, status |
| `rtl/epd_unpack.v`, `rtl/epd_line_fifo.v`, `rtl/epd_timing.v` | link v2 unpacker, FIFO, line-paced panel timing (CERN-OHL-P, after Caster) |
| `rtl/epd_rails.v`, `rtl/epd_dc_guard.v` | watchdog and rail sequencer; DC guard |
| `rtl/i2c_slave.v`, `rtl/cfg_bridge.v`, `rtl/por_sync.v` | I2C slave; opcode decode, user registers, APB master, dead-man; power-on reset |
| `rtl/dphy_rx_stub.v` | receiver contract, tied off |
| `rtl/pango/pgc_ccs_apb.v`, `rtl/pango/pgc_osc.v`, `rtl/pango/gtp_blackbox.v` | `GTP_APB`, `GTP_OSC_E2` wrappers; port shapes for yosys |
| `tb/tb_bridge.v`, `tb/gen_vectors.py`, `tb/engine_vectors.py` | datapath testbench and vectors |
| `tb/tb_i2c.v`, `tb/ccs_model.v`, `tb/osc_model.v` | I2C/APB testbench and models |
| `PDS_BRINGUP.md` | what to do once PDS exists |
