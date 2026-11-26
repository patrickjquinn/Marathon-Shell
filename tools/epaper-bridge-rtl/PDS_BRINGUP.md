# MP01 direct-drive bridge: what to do once PDS exists

2026-11-24. Companion to `DESIGN.md`. Everything up to §4 happens in a VM with no device attached.
§4 is the device plan; each stage needs the user's go.

Inputs referred to below live in `~/q25-build/mp01-inventory/cpld/`: `cpld_v36.bin` (application
image, eflash pages 572–1142), `uflash-out/analyse-A/heap0-bitstream-0305.bin` (golden v0305, pages
0–570), `cpld_v25.bin`, `re/pgparse.py`, `re/iomap.py`, `re/ring.py`, `re/lut/fab.py`, the BSDL
`artefacts/pango-bsdl-PGC4KLS_SBG81-extracted/`, and `uflash-out/uflash-pgtest.py` (the proven
PROGRAM/READ framing).

---

## 1. PDS and the VM

| Item | Choice |
|---|---|
| Version | **≥ 2020.4** (PGC4KLS-SBG81 support was added then; 2022.2 release notes). Prefer **2023.2-SP4 or later**: v36 and v0305 were built with Fabric Compiler 2023.2-SP4, so the I/O encoding learnt by fuzzing matches theirs most closely. 2022.2-SP1 Lite (Windows, licence-free for Compa) is the fallback. Not the archive.org 2020.2 Lite (no PGC4KLS). |
| Licence | Lite: none. Full PDS (Linux): free node-locked licence from pangomicro.com, tied to a MAC, so fix the VM's MAC before applying. |
| VM | x86-64 on another machine: this host is aarch64, has little disk and runs kernel builds. Windows 10/11 for Lite, or RHEL/Rocky 8 for Linux PDS; 4 vCPU, 8 GB RAM, 60 GB disk. Never run the installer on this host. Keep scripts and probe designs outside the PDS tree. |
| Same login | Download DS03002 (PGC4KLS data sheet), PK03028 (SBG81 package: ball functions, bank-1 bonding, VCCIO per bank) and UG030006 (eflash), data-ids 2446/2473/2479. |

First checks, all offline:

1. The device list shows `PGC4KLS-6SBG81` (the part named in v36's `.sbit` header).
2. A blinky builds; `python3 -I re/pgparse.py blinky.sbit out/` parses it; the packet sequence
   (preamble, `IDCODE`, `CTRLR`, `FAR`/`FDRI` 489 × 268 B, `CRCR`) matches v36's shape.
3. Read `arch/` before fuzzing anything: look for per-device fuse or bit tables (Apicula found
   Gowin's in `.fse`/`.dat`), and for the simulation models
   (`arch/vendor/pango/verilog/simulation/`). From the models confirm the port names and widths of
   `GTP_APB`, `GTP_OSC_E2`, `GTP_IOBUF_RX_MIPI`, `GTP_ISERDES_E1`, `GTP_PLL_E2`, `GTP_ODDR`
   against `rtl/pango/gtp_blackbox.v`, and run `tb_i2c` once with the vendor `GTP_APB` model in place
   of `tb/ccs_model.v` if the model is behavioural.
4. Synthesise `epd_stage1_top` and `epd_bridge_top` (with the stub) as they are, to get real LUT5,
   FF and DRM numbers against `DESIGN.md` §8.

## 2. Recover v36's ball-to-signal map (I/O-tile fuzzing)

Plan from `../panel-and-pinout.md` §3.3, made concrete. Nothing here needs the device.

### 2.1 What is already known

- Bitstream geometry [P]: 489 frames of 67 big-endian 32-bit words (268 B) at FAR 0. The I/O tiles
  are the left frames 0–25, the right frames 468–488, and words 0 (top tile) and 66 (bottom tile) of
  every frame (`re/lut/fab.py`, `HARD_I2C_PORT.md` §2).
- Pin placement is identical in v36 and v25 (`iomap.py`: right frame 488 has the same 51 bits in
  six clusters of four templates in both).
- 51 bonded user pads plus JTAG and MIPI_CTRL (BSDL): bank 0 22, bank 2 15 (H9 J8 F8 F7 G8 G7 J7
  J6 H6 H7 J5 H4 J4 J3 J2: the only 100 Ω bank, so the DSI), bank 3 7, bank 5 7. `ring.py` gives
  the pad-ring order.
- G4/G5 (pads B0_32/33) are the hard slave-I2C port, **persisted since 2026-11-24 with address 0x2C**,
  and they are not on i2c-7 (0x4b still answered; 0x2C did not). So the 0x4b slave is on two other
  balls, and G4/G5 must stay out of every new design (§3).

### 2.2 Probe builds

A probe top: a free-running 24-bit counter (placed with `PAP_LOC` on a fixed CLM site far from the
edges) whose bit 3 drives one port; every other ball unused. Fixed seed, fixed placement.

| Variant | Port configuration |
|---|---|
| A | output, LVCMOS33, 8 mA, no pull |
| B | input, LVCMOS33, pull-up, feeding the counter enable (so it is not optimised away) |
| C | output, LVCMOS18 (bank-voltage encoding) |
| D | open-drain bidirectional (`GTP_IOBUF`, T from the counter, O into the enable): the I2C shape |
| E | output through `GTP_ODDR` (the SDCLK shape) |
| F | bank-2 pairs only: `GTP_IOBUF_RX_MIPI` HS + LP, 100 Ω, into a `GTP_ISERDES_E1` |

Per ball × variant, build **twice** with the counter on two different CLM sites. About 51 × 5 × 2 ≈
500 builds of a near-empty design, a few minutes each with `pds_shell` Tcl batching: one to two
days of VM time.

### 2.3 Decode

1. For each build: `pgparse.py probe.sbit dir/` → `fdri_00000000.bin`. XOR against the baseline
   (the same design with the port unused), keep only bits in the I/O regions of §2.1.
2. A ball's **footprint** for a variant is the intersection of its two placements' diffs (routing
   bits differ between placements, I/O-tile bits do not).
3. Validate before trusting it:
   - a third placement of a few probes reproduces the footprint;
   - the JTAG balls (A4, B4, C4, C5) cannot be probed and own no footprint;
   - footprint positions run in the BSDL ring order (`ring.py`);
   - a held-out build with a random mix of attributes on random balls decodes exactly.
4. Apply to the three shipped images. Extend `iomap.py` (it loads v36 and v25 FDRI) with
   `re/v0305/` and the decoded footprint table, and print per ball: used, direction, standard, drive,
   pull, open drain, ODDR/IDDR/ISERDES, MIPI. v36, v0305 and v25 are independent place-and-route
   runs with a fixed pinout, so **all three must agree**; any ball where they differ is unresolved.

### 2.4 Expected inventory and naming

| Group | Expected | How to tell |
|---|---|---|
| DSI | 4 data pairs + clock pair, bank 2, MIPI | variant F footprint |
| Host I2C (0x4b) | one open-drain bidirectional pair, not G4/G5 | variant D footprint; the only OD pair on the SoC side |
| Source | D0–D7 (eight identical outputs, one bank), SDCLK (ODDR), LE, OE, SPH | attributes |
| Gate | CPV, STV, maybe GMODE/OE | attributes |
| Straps | SHR, L/R, GMODE1/2 | outputs driven by a constant LUT in v36 |
| PMIC | WAKEUP/PWRUP or EN pins, PG input, and/or an open-drain pair (unknown 2 in `DESIGN.md`) | attributes; a second OD pair means a PMIC I2C bus |
| Others | TE/BUSY to the SoC (GPIO83 is `DSI_TE`), reset in (GPIO85) | inputs vs outputs on the SoC side |

The counts must match the 26-pin GDE043A2 class (about 15 panel outputs plus PMIC control), or the
panel is a different class and the timing in `DESIGN.md` §4 is wrong.

Attributes alone do not name every panel signal. The panel-driving stages (§4.4) need each one
proved, because a wrong LE/OE/CPV/STV with the rails up DC-stresses the film:

- **Routing one hop back** from each output pad (fuzz only the I/O tile's output mux and the
  nearest switch box): the pad driven by a counter terminal bit is SDCLK's enable; LE and CPV come
  from line-rate strobes; STV from a frame-rate strobe; D0–D7 from the eight data bits, whose order
  (bit 0 to bit 7) follows from which LUT/DRM output feeds each.
- **D0–D7 order matters**: a permutation scrambles codes. Code 00 is safe under any permutation
  (no drive), so stage 3 starts with frames of 00 plus one 4-pixel column group driven at a time.
- If routing decode stalls: PK03028 plus one opened-phone probe session of the panel FPC, or JTAG
  SAMPLE (`../panel-and-pinout.md` §3.2). Both need the user's decision.

## 3. Constraints and build settings

### 3.1 Pins

One constraint file serves both tops (same port names). Generate it with PDS's I/O constraint
editor, then fill in from §2:

| Port | Ball | Standard | Notes |
|---|---|---|---|
| `i2c_scl`, `i2c_sda` | the decoded OD pair | as v36 (LVCMOS18 if the bank is 1.8 V: i2c-7 is a 1.8 V bus) | open drain, no internal pull (board has them) |
| `dsi_*` | bank-2 pairs, with v36's lane order | MIPI, 100 Ω | lanes 2/3 swapped on the board |
| `epd_sd[7:0]`, `epd_sdle`, `epd_sdoe`, `epd_sph`, `epd_gdclk`, `epd_gdsp`, `epd_gdoe` | decoded | as v36 | drive and slew as v36 |
| `epd_sdclk` | decoded | as v36 | `GTP_ODDR` (D0 = 0, D1 = `sd_strobe`): replace the `sdclk` gate in `epd_timing.v` |
| `pmic_wakeup`, `pmic_pwrup`, `pmic_pg` | decoded | as v36 | rename to the PMIC's pins once identified |
| any other ball v36 drives | — | as v36 | add as an output port held at 0 in both tops |
| **G4, G5** | — | — | **reserved: slave I2C "Dedicated IO"** (persisted). Never user I/O |

Stage-1 rule: every ball v36 uses as an output is an output held low; every open-drain pair other
than the host I2C is released. Low means PMIC enables off for every candidate part (TPS65185,
FP9931 and SY7636A enables are active high).

### 3.2 Timing

- `clk`: 48.88 ns (20.46 MHz) on the `GTP_OSC_E2` output; also check at −10 % period.
- `rx_clk`: the receiver's PLL output; the D-PHY byte clock: 38.5 ns at 60 Hz, 27.2 ns at 85 Hz.
- All three asynchronous to each other. The toggle synchronisers, the FIFO gray-pointer
  synchronisers and the `f_*` / `rx_seq` / `rx_err` bundles are the only crossings: false-path the
  bundles (they are stable for a frame before their toggle is seen).
- Panel outputs are registered and SDCLK is forwarded by ODDR, so source setup/hold (8 ns) is
  met by construction; constrain SD/SPH/LE relative to SDCLK anyway.

### 3.3 Bitstream settings

Compare the new `.sbit` with `cpld_v36.bin` packet by packet (`pgparse.py`); only the fabric frames,
USERCODE and the CRCs should differ.

| Setting | Value |
|---|---|
| Device | PGC4KLS-6SBG81 |
| Slave I2C | "Dedicated IO" / persisted (it is, in the CTL word); this keeps PDS off G4/G5 |
| JTAG | persisted, as v36 |
| Watchdog | as v36's application image; no user-mode watchdog |
| Dual boot | **no** `DBOOTADRR` and no `MSDBOOT` command: those belong to golden's preamble only |
| Wake-up clock | as v36 (`OPTION0R` = 0x0D) |
| CRC | on (PDS default) |
| USERCODE | `0x00000081` (stage 1) / `0x00000082` (bridge), readable over APB 0x04–0x07 |
| Feature control | irrelevant: the device's CTL word is not rewritten by this flow and no `PROGRAM_CTL` is sent |
| Size | the `.sbit` (with its 160-byte header, as the vendor programs it) must be ≤ 571 pages = 146,176 B; v36 is 146,104 B |

Build matrix:

| Image | Top | Parameters |
|---|---|---|
| stage 1 | `epd_stage1_top` | `DEADMAN_CLKS` = 2,046,000,000 (100 s) |
| stage 2 | `epd_bridge_top` + real receiver | `OUT_EN` = 2'b00, dead-man 100 s |
| stage 3 | `epd_bridge_top` | `OUT_EN` = 2'b11 (after unknown 2 is closed), dead-man 100 s |
| production | `epd_bridge_top` | `DEADMAN_CLKS` = 0 once the reflash loop has been proved |

## 4. Staged first load (device; each stage on the user's go)

### 4.1 Host tool (to write before stage 0)

A writer in the style of `uflash-pgtest.py`, 400 kHz, `I2C_RDWR`, the same preflight and quiesce
(blanking suppressed for the session):

- **Allowlist:** `80`–`8F` reads; `89 A5`; WREN `51`; WRDIS `52`; RDID `A1`; RDSR `A3`; READ `30`
  any page; READ_CTL `31`; PROGRAM `20` to pages **572–1142 and 1279** only. Nothing else, in
  particular no `10 11 12 21 22 40 50 60`.
- **Write:** per page WREN, `20 A2 A1 A0` + 256 B, RDSR until busy (bit 21) clears (≤ 0.5 s), WREN,
  READ, compare; one retry; stop on a second mismatch. The image is the `.sbit` with its header,
  last page padded with 00; pages after the image up to 1142 are written with 00 so the slot
  verifies exactly. About 10 s for 571 pages.
- **Gate:** refuse to start unless `80/84` read 36/10 (v36), 81/D0 (stage 1) or 82/D2 (bridge), RDSR
  shows lock = 0 and busy = 0, and a SHA-256 of the image matches the one given on the command line.
- Keep `cpld_v36.bin` and the full eflash dump (`uflash-full-A-*.img`) as the restore source.

### 4.2 Stage 0: rehearse with v36 itself

1. Write `cpld_v36.bin` over pages 572–1142 (identical bytes; overwrite semantics are proven) and
   verify. Power-cycle (blank, unblank). Expect `80 = 36`, the panel unchanged, RDSR fallback
   (bit 17) = 0.
2. **Optional, on the second MP01 only: prove golden fallback.** Overwrite page 572 with zeros,
   power-cycle. Expect RDSR fallback = 1, a working panel under v0305, and `80` = v0305's version.
   Rewrite page 572 from `cpld_v36.bin`, power-cycle, `80 = 36`. If the CPLD instead stays dead, the
   dead-man is no safety net on this part and stage 1 must not run on the only phone (recovery is
   JTAG, phone opened).

### 4.3 Stage 1: the I2C bridge alone, rails off

Proves that a design of ours loads, answers at 0x4b, and can put v36 back. All panel and PMIC
outputs are held low; the screen keeps its last image.

1. Write the stage-1 `.sbit` to 572–1142, verify, power-cycle.
2. Within 100 s (the tool does it at once):
   - `80 → 81`, `84 → D0`, RDID `99 28 42 a0`, RDSR with fallback 0, crc_err 0, id_err 0, busy 0;
   - READ page 1279, PROGRAM a pattern into 1279, READ it back, PROGRAM 00 back, READ;
   - READ_CTL `41 83 b2 40`;
   - **only if every step passed:** write `89 A5`, read `81`: bit 6 = 0.
3. Put v36 back through our bridge: write `cpld_v36.bin` to 572–1142, verify, power-cycle,
   `80 = 36`, panel works.
4. Repeat 1–3 once more. The reflash loop is then proven both ways.

If something fails:

| Symptom | Action |
|---|---|
| No ACK at 0x4b after the power-cycle | Leave it 2 minutes: the dead-man blanks page 572. Power-cycle: golden v0305 runs. Rewrite `cpld_v36.bin`. |
| ACK, but PROGRAM or READ misbehaves | Do **not** disarm; wait for the dead-man as above. |
| The dead-man fires but the CPLD stays dead after the power-cycle | Fallback does not work (see 4.2.2). Recovery needs JTAG. |

### 4.4 Stage 2: the link, nothing driven

`OUT_EN = 2'b00` with the real receiver. The host sends link v2 frames (RESYNC with PMIC_ON, then
non-driving PMIC_ON frames; DRIVE frames are refused because power-good is masked).

- `81` bit 0 synced; `85` increments at the frame rate; `82` stays put; `83` stays 0.
- Corrupt one header on purpose: `82` increments by one, then RESYNC recovers.
- Soak 10 minutes at 60 Hz, then at 85 Hz (pixel clock 49.04 MHz, porches unchanged).
- This settles the receiver, the RGB byte order and the word alignment (unknown 6) before any
  panel pin moves.

### 4.5 Stage 3: first ink

Preconditions: every panel signal named and proved (§2.4), the PMIC identified and its control
built (unknown 2), VCOM known (v36's 0x8A = 0x70).

`OUT_EN = 2'b11`. Single 64 × 64 patch, binary waveform, a handful of frames, camera on; then
D0–D7 order by single column groups; then full screen. This is milestone M6 of
`WAVEFORM_AND_DIRECT_MODE.md` §4.7 and follows its calibration plan.

## 5. What PDS has to deliver, in order

1. `PGC4KLS-6SBG81` in the device list; the primitive models for `GTP_APB`, `GTP_OSC_E2`, the MIPI
   I/O, ISERDES, IOCLK, PLL and ODDR (port names checked against `rtl/pango/`).
2. The I/O-tile decode and the three-image pinout table (§2), including the host I2C pair and the
   PMIC's interface.
3. The D-PHY RX and DSI parser behind `dphy_rx_stub.v`'s contract (`DESIGN.md` §3.4), simulated
   against a DSI line model before synthesis.
4. Constraint files (§3), timing closure at 85 Hz, and the two images: stage 1, then the bridge.
5. If the PMIC is on an I2C pair: the PMIC master (`DESIGN.md` §10, unknown 2).
