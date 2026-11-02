# MT6789 CONNSYS GNSS

How the GNSS receiver of the MediaTek MT6789 (Helio G99, Zinwa Q25) works,
as far as it matters for an open driver and positioning engine. Everything
here comes from interoperability analysis of the Q25's stock vendor image
(`libmnl.so`, `mnld`, `MNL_Config.xml`), of the GPL stock kernel drivers
(LineageOS `android_kernel_xelex_mt6789` `2a873a35`,
`drivers/misc/mediatek/connectivity/gps`) and of the donor `wmt_drv`, plus
read-only reads of the phone. No MediaTek code or firmware is reproduced.

Status, 2026-11-02: the boot protocol is complete and the driver's boot
traffic is byte-identical to the stock engine's for the Q25 configuration
(checked by running the stock boot routine against a simulated DSP). Nothing
has run on the phone yet; see [Bring-up](#bring-up-on-the-q25).

## Summary

- The receiver is **host-based**. A DSP inside CONNSYS correlates and tracks
  satellites; it is loaded from the host at every power-on, takes its
  acquisition assistance from the host and returns per-channel tracking data
  and navigation-message bits in MediaTek's binary framing. The positioning
  engine (and NMEA) lives entirely in `libmnl.so` on the AP. The DSP never
  speaks NMEA, PMTK or PAIR; it is not an AG3335/MT3333-style receiver, and
  mainline `drivers/gnss/mtk.c` does not apply.
- MT6789 is **L1 only** in the stock engine: `libmnl` has an L1 DSP image for
  it and no L5 one, although the stock DT carries L5 LNA pin states.
- An open stack therefore needs three parts: (1) a kernel driver that powers
  the function, loads the DSP and passes the binary stream through a GNSS
  device (done: `devices/zinwa/q25/modules/gnss`); (2) the DSP image, copied
  from the phone's own stock partition (done:
  `packaging/packages/q25-gnss-firmware`); (3) an open host engine that
  drives acquisition, decodes the measurements and the navigation message and
  computes positions (not done; it needs captures from a running DSP, see
  [Open engine](#what-an-open-engine-needs)).

## Prior art

- github.com/gabin8/mt6572-connsys-modules (2026) brings up the older
  MT6572 CONSYS on mainline as out-of-tree modules, GPS included, but
  positions with the stock MNL engine run from a chroot of the stock
  `/system`. Its findings match this one: `/dev/stpgps` stays silent until an
  engine boots the DSP, and nothing is tracked without the external LNA
  enabled.
- MediaTek's own material calls this split "host-based" (MT3332, MT6620 and
  later combo chips). No open implementation or published analysis of the
  DSP boot or measurement protocol was found; Halium-based systems (Ubuntu
  Touch, Droidian, Sailfish) run the vendor `mnld` and HAL in the Android
  container.
- Mainline `drivers/gnss/mtk.c` covers MT333x serial receivers that speak
  NMEA/PMTK themselves.

## Hardware and power

- GNSS is a function of CONNSYS (with Wi-Fi and Bluetooth). The host reaches
  it through the CONNSYS MCU over STP on BTIF; there are no AP-visible GNSS
  registers in this path. `mediatek,gps` at `0x18c00000` in the stock DT is a
  software node only.
- Power: WMT's GPS function (`mtk_wcn_wmt_func_on(WMTDRV_TYPE_GPS)`). For the
  Q25's `WMT_SOC.cfg` (`co_clock_flag=1`, `wmt_gps_lna_enable=0`,
  `wmt_gps_lna_pin=0`) WMT sets GPS sync, takes the host LNA path and sends
  the GPS function-on command to the CONNSYS firmware.
- Data: STP channel `GPS_TASK_INDX` (2). Each send carries at most 1996 bytes;
  a send returns 0 when no STP window is free and must be retried.
- LNA: stock `gps_l1_lna` states on GPIO25 (`pinmux 0x1900` output low or
  high, `0x1902` = function 2). In function 2 the GNSS DSP drives the LNA
  enable itself; stock selects it on open and returns the pin to output-low on
  close. GPIO87 has the L5 equivalents, unused on MT6789.
- Reference clock: 26 MHz co-clock (the phone's GPS NVRAM record
  `nvdata:/APCFG/APRDEB/GPS` holds 26 000 000 Hz; WMT reports co-clock, so the
  engine uses clock type 0xFE).
- `/dev/gps_emi` (a 1 MiB window at CONSYS EMI + 4 MiB) serves only raw ADC
  capture for factory calibration. Normal operation does not use it.
- `/dev/gps_pwr` relays battery-throttling events from connadp. Not needed.
- The `connsys_gnss_a/b` partitions are empty on the Q25 (all zero).

## The DSP image

`libmnl.so` (Q25 build sha256 `c0eba0a2…a8deca`, 7 092 152 bytes) holds DSP
images for some fifty MediaTek chips in `.rodata`. The boot routine picks one
by chip id (`0xffff6789`) and chip family (`0x2f0`). MT6789 has two:

| Image | File offset | Length | Use |
|---|---|---|---|
| L1 | `0x3dfcba` | `0x118a0` (71 840) | normal operation |
| L1 "CW" | `0x3ceeb8` | `0x10e02` (69 122) | continuous-wave factory test mode only |

Image layout, little-endian 16-bit words (the DSP is word-addressed):

| Word | Meaning | Q25 L1 image |
|---|---|---|
| 0 | code length in words | `0x8c4c` (= (71 840 − 8) / 2) |
| 1 | load address | `0x6400` |
| 2 | entry address | `0x6404` |
| 3 | cipher key | `0x01c8` |
| 4… | code | obfuscated with the key |

The DSP decodes the code itself with the key from the boot parameters; the
host sends the image as stored and never needs to decode it. The extractor
(`q25-gnss-firmware`) writes these 71 840 bytes, verbatim, to
`/var/lib/q25-gnss/gnss-l1-dsp.bin` (sha256 `2b01f748…cc3400c`), which the
kernel loads as `mediatek/mt6789/gnss-l1-dsp.bin`. It finds `vendor_a` in
super's LP metadata, reads `libmnl.so` with `debugfs` at that offset (nothing
mapped or mounted, read-only) and cuts the image at the offset recorded for
that library build; other builds need their own entry.

## Framing

Both directions use the same frame:

    AA F0 | len (le16) | id (le16) | payload | sum (le16) | AA 0F

- `len` is the payload length + 4 (its low 12 bits; the DSP may set the top
  four).
- `sum` is the 16-bit sum of the four `len`/`id` bytes and the payload bytes.
- Between the markers, `0xAA` is sent as `DE DF` and `0xDE` as `DE E0`. An
  unescaped `AA` is always a marker.
- Host-based messages have ids `0xFExx`. Below, "msg 0x08" means id `0xFE08`.

## Boot

After WMT has powered the function the DSP sits in a boot ROM. The host:

1. Sends msg 0x08, 106 bytes of boot parameters (below), and waits for msg
   0x31 whose first word is 0 (the sequence number). If none arrives in
   200·2^n ms it sends msg 0x05 with the word `0x0004` three times, waits
   500·(n+1) ms and resends; five attempts.
2. Sends the code in fragments, msg 0x0C each: a le16 sequence number
   (1, 2, …) followed by the fragment bytes. After each it waits for msg 0x32
   carrying the same sequence number, resending up to five times with the
   same 200·2^n ms timeouts.
3. When the last fragment is acknowledged the DSP runs the image and the
   stream carries its traffic from then on.

Fragmenting: the code (without the 8-byte header) is cut into 1400-byte
chunks; their number is ceil((code + 8) / 1400). A chunk with at least 14
bytes that need escaping is sent as two fragments, 700 bytes and the rest;
the last chunk is split only if those bytes plus its length reach 1414. The
fragment count goes into the boot parameters. The Q25 image makes 52 chunks
and 66 fragments; the whole boot is 67 frames, 73 214 bytes on the wire.

### Boot parameters (msg 0x08)

Values as the stock engine sends them for the Q25 (26 MHz co-clock, GPS +
GLONASS + Galileo + BeiDou, no host-known LNA pin, empty learned-clock store).
They were recovered by running the stock boot routine on a simulated DSP
and varying one input at a time.

| Bytes | Content | Q25 |
|---|---|---|
| 0 | constant | `1a` |
| 5 | host link speed code (1 = 921 600 bit/s; meaningless over STP, sent anyway) | `01` |
| 6–9 | two words derived from the reference clock | `c3 01 a5 02` |
| 14–21 | image words 0–3 (length, load, entry, key) | from the image |
| 22–23 | fragment count | `42 00` (66) |
| 28–29 | constant | `05 00` |
| 30–57 | RF/PLL words derived from the reference clock | see driver |
| 38 | RF options: bit 1 from the constellation set, bit 2 high-gain LNA | `02` |
| 58 | constellation mask (low nibble of the HW mode, 0x17 here) | `07` |
| 60 | 1 for a co-clock, 0 for a TCXO | `01` |
| 62–95 | per-reference-clock table | see driver |
| 96–97 | chip id | `89 67` |
| 98 | LNA GPIO the DSP should drive, 0xFF for none (WMT's DT lookup finds none on the Q25, as on stock) | `ff` |
| 99 | chip-class value | `0a` |
| 102 | 1 = L1 only | `01` |
| 104–105 | constant | `4e 4f` |
| others | zero | |

The engine learns the reference clock's real frequency over time and stores
it in `/data/vendor/gps/mtkgps.dat`; with a stored value the clock-derived
words change slightly. The driver always sends the nominal 26 MHz set, which
is what stock sends on a phone with no stored data.

## After boot

DSP-to-host payloads are scrambled: each byte is sent rotated left by three
and XORed with 0x59 (libmnl's `dsp_auth_decrypt` undoes it after the
checksum check; the checksum covers the scrambled bytes). Boot
acknowledgements are not scrambled. Host-to-DSP payloads are plain.
Multi-byte DSP values are 16-bit little-endian words; 32-bit values are two
words, high word first.

Observed on the Q25 (2026-11-02, indoors, LNA not enabled, no host
commands after boot): the DSP runs by itself and sends one epoch per second
in the order 0x42, 0x2C, 0x62, 0x28, 0x29, 0x30, 0x4E. The DSP version
reply (msg 0x14 to `0018`) is `0007 0115`.

- msg 0x28 (9 bytes): byte 0 = 1, bytes 1–4 a 32-bit DSP time in ms
  (1013, 2013, … one second apart), bytes 5–8 constant (`78 69 00 50`).
- msg 0x2C, 0x4E, 0x62 carry the same millisecond time at bytes 2–3.
- msg 0x29 (67 bytes): one record per epoch for channel 66, byte 1 = 0x25,
  byte 2 = 1; bytes 23 and 25–30 change every epoch (a search in progress).
  libmnl reads the record as: byte 1 satellite, byte 2 signal/system, bytes
  3–6 state, then 16-bit and 32-bit fields from byte 7 on.


The DSP returns frames with these ids (sizes are the payload capacity the
stock decoder accepts). Meanings come from how `libmnl` stores and uses them;
none has been observed on the wire yet.

| id | Bytes | Stock use |
|---|---|---|
| 0x14 | 4 | reply to a msg 0x08 query: the DSP version for `0018`, `addr value` for a register read `000c addr` |
| 0x1D | 2 | event code, 28 kinds |
| 0x28 | 10 | epoch time tag; the host stamps it with `CLOCK_BOOTTIME` and starts the measurement update |
| 0x29 | 68 per channel | per-channel record, first byte the channel (< 99) |
| 0x2A / 0x2B | 11 / 46 per channel, ≤ 12 | header + per-channel block |
| 0x3A / 0x3B | 5 / 14 per channel, ≤ 13 | header + per-channel block |
| 0x40 / 0x41 | 13 / 32 per channel, ≤ 12 | header + per-channel block |
| 0x4A or 0x4C / 0x4B | 10 / 47 per channel, ≤ 16 | header + per-channel block |
| 0x4D | 47 per channel, ≤ 21 | per-channel block |
| 0x5B / 0x5C | 10 / 113 per channel, ≤ 16 | header + per-channel block |
| 0x5A | 42 per entry | list |
| 0x2C | 70 | end of epoch ("DBTT"); the first one after boot is logged as `FIRST_DBTT` |
| 0x2E, 0x30, 0x37, 0x42, 0x43, 0x4E, 0x59, 0x61, 0x62 | 40, 69, 70, 46, 20, 16, 9, 24, 8 | status and auxiliary blocks |
| 0x2F | 1 + 2 to 488 | sub-typed status; first byte the sub-type (4–0x13) |
| 0x63 | 1 | flag |
| 0x60 | 1024 | bulk block |
| 0x31, 0x32 | 10, 2 | boot acknowledgements: boot parameters, code fragment |
| 0x33 | 10 | another acknowledgement, not used by the L1 boot |

Which header/channel group belongs to which constellation or signal is not
established. The host decodes navigation-message subframes (GPS/QZSS
preamble and parity, GLONASS strings, Galileo words, BeiDou D1/D2) itself,
so the DSP delivers raw navigation bits.

The host sends these commands (`0xFE00 | id`, word payloads):

| id | Stock senders | Purpose |
|---|---|---|
| 0x01–0x03 | `vMCU_vrd_DB_Acq_Aid` | acquisition assistance per channel |
| 0x04 | `vMCU_vrd_DB_Chan_Reset` | channel reset |
| 0x05 | `vMCU_vrd_Command*`, boot | general control (word 4 kicks the boot ROM; sleep/stop sub-commands) |
| 0x07 | `vMCU_vrd_Sbas_*` | SBAS channel control |
| 0x08 | search mode, fast search, register get/set, version query (`0018`), boot parameters | multi-purpose; queries are answered with msg 0x14 |
| 0x09 | `vSend_DSP_Data_Bit` | navigation-bit aiding |
| 0x0A | `hal_sys_time_set` | time |
| 0x0F | `vATA_Send_60bit_Aiding` | 60-bit aiding |
| 0x10, 0x11, 0x15 | `vMCU_vrd_DB_CFOA/CFOB/C2OA` | clock-frequency-offset aiding |
| 0x1C | `Medium_Task_Ctl` | periodic task control |

While booting, only ids 0x05, 0x08, 0x0C and 0x1D are sent.

## Measurements and search commands

Established from two reference runs of the stock engine on the Q25
(analysis only, nothing of it in this repository) against public broadcast
ephemeris and a surveyed reference position.

Channel record (msg 0x29), offsets into the unscrambled payload:

| Bytes | Meaning |
|---|---|
| 0 | channel |
| 1 | satellite: GPS/QZSS PRN, GLONASS frequency slot, BeiDou PRN |
| 2 | system: 0x01 GPS, 0x02 Galileo, 0x08 QZSS, 0x10 GLONASS, 0x20 BeiDou |
| 3 | C/N0, dB-Hz (0 = not tracking) |
| 23–26 | the DSP's time estimate for the epoch, common to all channels of a system |
| 27–30 | GPS: code phase within the 20 ms data bit, 16-bit chips (0–20459) then a 16-bit fraction |
| 31–32 | Doppler in Hz, signed, including the reference-clock offset |
| 35–36 | accumulated carrier phase, L1 cycles, wrapping |

Checks: across satellites the code phase modulo 1 ms matches the geometry
to about 0.1 chip; the Doppler field equals the geometric Doppler plus one
common offset (1626 Hz on this phone, slope 1.000, 0.5 Hz rms); bytes 35–36
change by 5.26 per metre of range change (1/λ at L1). The BeiDou code phase
scale is not settled yet.

Host commands seen during a cold start (all payloads plain):

| id | When | Content |
|---|---|---|
| 0x05 | once | engine settings (sub-command byte first) |
| 0x04 | once | per-system signal enable masks |
| 0x08 | once | search mode `10 00 10 00` |
| 0x00 | every epoch | the next epoch's DSP time (32-bit, high word first) |
| 0x10, 0x11 | every epoch | reference-clock aiding per system |
| 0x01 | every epoch | time and frequency aid: clock offset in Hz, its uncertainty, the DSP time it refers to (0 before the first fix), GPS time in 1.5 s units |
| 0x03 | every epoch | type 0: satellites being aided; type 1: search list, `01 n` then (satellite, system) pairs |
| 0x1C | every epoch | end of the epoch's commands |
| 0x05 `29 00` | every epoch | |
| 0x02 | per tracked channel, after the first fix | aid echoing the channel's time, code phase and Doppler |
| 0x0A | every ~43 s once time is known | UTC date and time for a DSP time |
| 0x07 | cycling | SBAS satellite selection |

Without host commands the DSP only runs its idle channel; with the cold-start
set it acquires satellites on its own, before any per-channel aid.

## What an open engine needs

1. Captures of a running DSP: the stream from `/dev/gnssN` after boot, first
   with no host commands (does the DSP free-run, sending 0x2C each second?),
   then outdoors.
2. The layouts of the per-channel records (code phase, carrier frequency or
   Doppler, C/N0, lock and sync state, measurement time) and of the 0x28 time
   tag, from `XGps_DSP_decode` / `XG4K_Get_SV_DSP_Data` in `libmnl` checked
   against captures.
3. The acquisition commands 0x01–0x03 and search modes (msg 0x08): which
   satellite, code and Doppler window each channel searches. A cold start can
   assign every satellite with a full Doppler sweep; warm starts use
   ephemeris.
4. Navigation-bit extraction from the stream, then subframe decoding: RTKLIB
   (BSD-2-Clause) has GPS/Galileo/BeiDou/GLONASS navigation-message decoders
   and single-point positioning from pseudoranges and broadcast ephemeris.
5. The engine as a Marathon Rust daemon: owns `/dev/gnssN`, runs the
   acquisition loop, forms pseudoranges, solves with RTKLIB's algorithms (or a
   port), and writes NMEA to GeoClue's `nmea-socket`. Optional SUPL-free
   aiding: ephemeris from a public broadcast-ephemeris source.

Items 2–3 are the bulk of the work and cannot be finished from static
analysis alone.

## Engine design (`crates/marathon-gnssd`)

One daemon owns `/dev/gnssN` (opening it boots the DSP) and does what
`libmnl` does on stock, with open code:

1. Protocol: deframe, unscramble, group messages into epochs (0x42 … 0x4E,
   one per second), send host commands. Done.
2. Measurements: turn the per-channel records into pseudoranges (code
   phase, measurement time, carrier/Doppler, C/N0, lock flags). Blocked on
   decoding the records from outdoor captures.
3. Acquisition: decide which satellite each channel searches and with what
   code/Doppler window (msgs 0x01–0x03, search mode in msg 0x08), using
   the best available aiding: system time (NTP-synced clock), an
   approximate position (GeoClue's Wi-Fi/cell fix, requested at city
   accuracy so that this daemon does not feed on itself) and, once decoded,
   broadcast ephemeris and almanac. Cold start without aiding: assign all 32
   GPS PRNs round-robin with full Doppler search. Blocked on the command
   layouts; whether the DSP searches on its own (the indoor capture shows
   one channel working unprompted) is the first thing an outdoor capture
   answers.
4. Navigation message: GPS L1 C/A word parity and subframes 1–3 →
   ephemeris (IS-GPS-200). Done; needs the DSP's navigation bits wired in.
   GLONASS, Galileo and BeiDou decoders follow the same pattern later.
5. Position: satellite orbit and clock from the ephemeris, then single-point
   least squares (RTKLIB's `pntpos` method, with nalgebra). Done; the
   Klobuchar ionosphere and a troposphere model come next for 5–10 m.
6. Output: NMEA GGA/RMC (done) to GeoClue's `[network-nmea]` source.
   GeoClue connects to a Unix socket given as `nmea-socket=` and reads NMEA
   lines; the daemon will listen on `/run/marathon-gnssd/nmea.sock`.

Today the binary prints each epoch's messages unscrambled, which is the
tool for step 2.

## Kernel driver

`devices/zinwa/q25/modules/gnss/mtk-connsys-gnss.c`, compatible
`mediatek,mt6789-gnss` (binding: `devices/zinwa/q25/kernel/0012`, board node:
`0013`). On open of `/dev/gnssN` it selects the LNA's `active` state, turns
the WMT GPS function on, loads `mediatek/mt6789/gnss-l1-dsp.bin` and boots the
DSP as above, then hands every byte from the DSP to the GNSS device (type
`MTK`; a dedicated type for this binary protocol would be the upstream
choice) and sends every byte written to it. Close turns the function off and
returns the pin to output-low. Loading the module touches no hardware.

Dependency on CONNSYS: power and the byte channel come from MediaTek's
out-of-tree `wmt_drv` (`mtk_wcn_wmt_func_on/off`, `mtk_wcn_stp_send_data`,
`mtk_wcn_stp_receive_data`, `mtk_wcn_stp_register_event_cb`,
`mtk_wcn_wmt_msgcb_reg`), the same exports `q25-btmtk-stp` uses, and the
module creates its platform device itself because `wmt_drv` does not populate
the CONNSYS node's children. An upstream driver would sit under a mainline
CONNSYS (WMT/STP over BTIF) driver that powers functions and provides
per-function channels and populates the `gnss` child; only the transport
functions at the top of the driver would change. No such driver exists for
MT6789 (or any CONNAC1 SoC) today, so the driver cannot go upstream before
one does.

## Bring-up on the Q25

The phone runs a kernel without module unloading, so a loaded module stays
until reboot. The module does nothing at load; all hardware access happens on
open of `/dev/gnssN`, and closing powers the function off again. A failed
boot returns an error from `open()` and leaves the function off. Wi-Fi and
Bluetooth share CONNSYS: a CONNSYS fault during GNSS power-on can trigger
WMT's whole-chip reset, which drops Wi-Fi/BT briefly (they recover through
WMT's normal reset path).

1. Firmware, without loading anything:
   `/usr/libexec/q25-gnss/q25-gnss-firmware` (or the service), then
   `sha256sum /var/lib/q25-gnss/gnss-l1-dsp.bin` should print `2b01f748…`.
2. Without the new DT (boot, no LNA): `insmod mtk-connsys-gnss.ko`; dmesg
   shows only `no LNA pin state` (expected without the DT node);
   `/dev/gnss0` and `/sys/class/gnss/gnss0/type` = `MTK` appear.
3. `timeout 60 cat /dev/gnss0 > /tmp/gnss.bin` (open boots the DSP). Expected
   dmesg: `DSP running (66 fragments)` within a few seconds; then frames start
   with `AA F0`. If the boot ROM does not answer: `DSP boot ROM did not
   answer` after about 14 s and `open` fails. Decode with
   `devices/zinwa/q25/gnss/mtk-gnss-frames < /tmp/gnss.bin`; the first
   question is whether 0x2C arrives about once per second unprompted.
   A harmless probe of the running image is the version query the stock
   engine sends: with the capture running, write
   `aa f0 06 00 08 fe 18 00 24 01 aa 0f` to `/dev/gnss0` (a second open
   shares the running receiver); the capture should then hold a msg 0x14
   with four bytes, the DSP version.
4. LNA without a new DT: the pinctrl debugfs mux gives GPIO25 to the DSP
   for a test, the same setting as `0013`'s `active` state:
   `echo "GPIO25 func2" > /sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris/pinmux-select`
   (and `func0` to undo). Record outdoors with
   `devices/zinwa/q25/gnss/mtk-gnss-capture`.
5. With the DT from `0013` (needs a reboot into it): the module binds to the
   `gnss` node and switches GPIO25 to function 2 while open
   (with debugfs mounted, `/sys/kernel/debug/pinctrl/*/pinmux-pins` shows
   pin 25 in function 2 only while `/dev/gnss0` is open). Outdoors, per-channel records (0x29 and
   the grouped blocks) should start to carry non-zero data once satellites
   are tracked; that capture is the input for the open engine.

No time to first fix can be measured until the open engine exists.
