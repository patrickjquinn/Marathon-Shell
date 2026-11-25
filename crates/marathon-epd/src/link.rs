//! The drive-frame format between the `SoC` and a dumb DSI-to-EPD bridge (link v2, see
//! `tools/epaper-bridge-rtl/DESIGN.md`): the stock MP01 DSI mode, RGB888 800×600, one panel row
//! per DSI line, so the panel frame rate is the DSI frame rate and no display-mode change is
//! needed.
//!
//! Each DSI pixel is three wire bytes B0, B1, B2 (B0 first), so a DSI line is 2,400 bytes. Bytes
//! 0..32 of line 0 are the header (zero on the other lines); bytes 32..232 of line `r` are panel
//! row `r`, the rest of the line is padding. Byte `j` of a row holds columns `4j..4j+3`, the first
//! in bits 7:6, which is [`crate::engine`]'s drive layout row for row. Codes: 00 none, 01 black,
//! 10 white; 11 is reserved and the bridge masks it to 00.
//!
//! Header (bytes 0..32 of line 0, little-endian): magic `EPD1`, version 2, flags, 2 reserved,
//! seq u32, `scan_first` u16, `scan_last` u16 (inclusive), `vcom_mv` u16, 10 reserved, CRC-16 over
//! bytes 0..28. The CRC is CRC-16/MCRF4XX, the DSI long-packet checksum, so the bridge reuses
//! one circuit.
//!
//! The bridge drives a frame only if its header is valid and its seq is exactly the last
//! accepted seq + 1, after a RESYNC frame (which never drives) set the base. A display
//! controller left rescanning a stale buffer, a bootloader's plain RGB logo, or garbage all fail
//! that check and never reach the panel. A rescan of the RESYNC buffer itself (same seq) is
//! refused without losing sync, so it cannot keep the bridge's watchdog fed either. The bridge
//! also refuses DRIVE until its PMIC rails are up, again without losing sync. [`Bridge`] is the
//! reference model of the sequence rules.

use std::fmt;

pub const PANEL_W: usize = 800;
pub const PANEL_H: usize = 600;
pub const ROW_BYTES: usize = PANEL_W / 4;
pub const DSI_W: usize = 800;
pub const DSI_H: usize = PANEL_H;
pub const LINE_BYTES: usize = DSI_W * 3;
pub const FRAME_BYTES: usize = LINE_BYTES * DSI_H;
pub const DRIVE_BYTES: usize = ROW_BYTES * PANEL_H;
pub const HEADER_LEN: usize = 32;
/// Offset of the panel row in every DSI line.
pub const ROW_OFFSET: usize = HEADER_LEN;

pub const MAGIC: [u8; 4] = *b"EPD1";
pub const VERSION: u8 = 2;
pub const DRIVE: u8 = 1 << 0;
pub const PMIC_ON: u8 = 1 << 1;
pub const VCOM_SET: u8 = 1 << 2;
pub const RESYNC: u8 = 1 << 3;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LinkError {
    Magic,
    Version(u8),
    Crc { got: u16, want: u16 },
    Flags(u8),
    ResyncDrives,
    ScanWindow { first: u16, last: u16 },
    Length(usize),
}

impl fmt::Display for LinkError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            LinkError::Magic => write!(f, "link: bad magic"),
            LinkError::Version(v) => write!(f, "link: version {v}"),
            LinkError::Crc { got, want } => write!(f, "link: crc {got:04x} != {want:04x}"),
            LinkError::Flags(fl) => write!(f, "link: reserved flags {fl:02x}"),
            LinkError::ResyncDrives => write!(f, "link: RESYNC frame with DRIVE"),
            LinkError::ScanWindow { first, last } => {
                write!(f, "link: scan window {first}..={last}")
            }
            LinkError::Length(n) => write!(f, "link: frame of {n} bytes"),
        }
    }
}

impl std::error::Error for LinkError {}

/// CRC-16/MCRF4XX: poly 0x1021 reflected, init 0xFFFF, no final xor.
pub fn crc16(data: &[u8]) -> u16 {
    let mut crc = 0xFFFFu16;
    for &b in data {
        crc ^= u16::from(b);
        for _ in 0..8 {
            crc = if crc & 1 != 0 {
                (crc >> 1) ^ 0x8408
            } else {
                crc >> 1
            };
        }
    }
    crc
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Header {
    pub flags: u8,
    pub seq: u32,
    pub scan_first: u16,
    pub scan_last: u16,
    pub vcom_mv: u16,
}

impl Header {
    pub fn encode(&self) -> [u8; HEADER_LEN] {
        let mut h = [0u8; HEADER_LEN];
        h[..4].copy_from_slice(&MAGIC);
        h[4] = VERSION;
        h[5] = self.flags;
        h[8..12].copy_from_slice(&self.seq.to_le_bytes());
        h[12..14].copy_from_slice(&self.scan_first.to_le_bytes());
        h[14..16].copy_from_slice(&self.scan_last.to_le_bytes());
        h[16..18].copy_from_slice(&self.vcom_mv.to_le_bytes());
        let crc = crc16(&h[..28]);
        h[28..30].copy_from_slice(&crc.to_le_bytes());
        h
    }

    /// The bridge's validity rule.
    pub fn decode(b: &[u8]) -> Result<Self, LinkError> {
        if b.len() < HEADER_LEN {
            return Err(LinkError::Length(b.len()));
        }
        if b[..4] != MAGIC {
            return Err(LinkError::Magic);
        }
        if b[4] != VERSION {
            return Err(LinkError::Version(b[4]));
        }
        let (got, want) = (u16::from_le_bytes([b[28], b[29]]), crc16(&b[..28]));
        if got != want {
            return Err(LinkError::Crc { got, want });
        }
        let u16_at = |i: usize| u16::from_le_bytes([b[i], b[i + 1]]);
        let h = Self {
            flags: b[5],
            seq: u32::from_le_bytes([b[8], b[9], b[10], b[11]]),
            scan_first: u16_at(12),
            scan_last: u16_at(14),
            vcom_mv: u16_at(16),
        };
        if h.flags & 0xF0 != 0 {
            return Err(LinkError::Flags(h.flags));
        }
        if h.flags & RESYNC != 0 && h.flags & DRIVE != 0 {
            return Err(LinkError::ResyncDrives);
        }
        if h.flags & DRIVE != 0
            && (h.scan_first > h.scan_last || usize::from(h.scan_last) >= PANEL_H)
        {
            return Err(LinkError::ScanWindow {
                first: h.scan_first,
                last: h.scan_last,
            });
        }
        Ok(h)
    }
}

/// Lays out one DSI frame (wire bytes) from a header and the engine's drive buffer.
///
/// # Panics
/// If `drive` or `out` has the wrong size.
pub fn pack_frame(h: &Header, drive: &[u8], out: &mut [u8]) {
    assert_eq!(drive.len(), DRIVE_BYTES);
    assert_eq!(out.len(), FRAME_BYTES);
    out.fill(0);
    out[..HEADER_LEN].copy_from_slice(&h.encode());
    let (lines, _) = out.as_chunks_mut::<LINE_BYTES>();
    let (rows, _) = drive.as_chunks::<ROW_BYTES>();
    for (line, row) in lines.iter_mut().zip(rows) {
        line[ROW_OFFSET..ROW_OFFSET + ROW_BYTES].copy_from_slice(row);
    }
}

pub fn unpack_frame(wire: &[u8]) -> Result<Header, LinkError> {
    if wire.len() != FRAME_BYTES {
        return Err(LinkError::Length(wire.len()));
    }
    Header::decode(&wire[..LINE_BYTES])
}

/// Panel row `r` of a packed frame.
pub fn frame_row(wire: &[u8], r: usize) -> &[u8] {
    let at = r * LINE_BYTES + ROW_OFFSET;
    &wire[at..at + ROW_BYTES]
}

/// Wire bytes to XRGB8888 scanout words, assuming the display controller sends R, G, B per
/// pixel (B0 = R). Pin this against a DSI capture at bring-up; with an RGB888 plane whose
/// memory order matches the wire, the frame is scanned out with no copy at all.
pub fn to_xrgb8888(wire: &[u8], out: &mut [u32]) {
    for (px, w) in wire.as_chunks::<3>().0.iter().zip(out.iter_mut()) {
        *w = u32::from(px[0]) << 16 | u32::from(px[1]) << 8 | u32::from(px[2]);
    }
}

/// `SoC` side of the sequence contract.
#[derive(Debug, Default)]
pub struct Sequencer {
    seq: u32,
    pub vcom_mv: u16,
    vcom_pending: bool,
}

impl Sequencer {
    pub fn set_vcom(&mut self, mv: u16) {
        self.vcom_mv = mv;
        self.vcom_pending = true;
    }

    /// The first frame after the bridge powers up, and after it reports a refusal. It takes a
    /// fresh seq: the bridge refuses a RESYNC that repeats the last accepted one.
    pub fn resync(&mut self) -> Header {
        self.seq = self.seq.wrapping_add(1);
        Header {
            flags: RESYNC | PMIC_ON | self.vcom_flag(),
            seq: self.seq,
            vcom_mv: self.vcom_mv,
            ..Header::default()
        }
    }

    /// A drive frame; `rows` is the engine's driven row range (`None`: nothing driven).
    pub fn drive(&mut self, rows: Option<(u32, u32)>) -> Header {
        self.seq = self.seq.wrapping_add(1);
        let mut h = Header {
            flags: PMIC_ON | self.vcom_flag(),
            seq: self.seq,
            vcom_mv: self.vcom_mv,
            ..Header::default()
        };
        if let Some((first, last)) = rows {
            h.flags |= DRIVE;
            h.scan_first = u16::try_from(first).unwrap_or(u16::MAX);
            h.scan_last = u16::try_from(last).unwrap_or(u16::MAX);
        }
        h
    }

    /// The last frame before the loop stops: drives nothing and lets the bridge drop the rails.
    pub fn drain(&mut self) -> Header {
        self.seq = self.seq.wrapping_add(1);
        Header {
            seq: self.seq,
            ..Header::default()
        }
    }

    /// The display controller rejected the commit: the next frame reuses this seq.
    pub fn commit_failed(&mut self) {
        self.seq = self.seq.wrapping_sub(1);
    }

    fn vcom_flag(&mut self) -> u8 {
        if std::mem::take(&mut self.vcom_pending) {
            VCOM_SET
        } else {
            0
        }
    }
}

/// What the bridge does with one received frame.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Verdict {
    /// Drive these rows; every other row is clocked through with no drive.
    Drive { first: u16, last: u16 },
    /// Accepted (resync or drain); nothing driven.
    Accept,
    /// Not driven: invalid header, no header, or a stale or out-of-order seq.
    Refuse,
}

/// Reference model of the bridge's acceptance rules, matched by the RTL testbench.
#[derive(Debug, Default)]
pub struct Bridge {
    last_seq: u32,
    synced: bool,
    pub pmic_on: bool,
    pub vcom_mv: u16,
    pub refused: u32,
}

impl Bridge {
    pub fn receive(&mut self, wire: &[u8]) -> Verdict {
        let Ok(h) = unpack_frame(wire) else {
            self.refused += 1;
            return Verdict::Refuse;
        };
        if h.flags & RESYNC != 0 && self.synced && h.seq == self.last_seq {
            self.refused += 1;
            return Verdict::Refuse;
        } else if h.flags & RESYNC != 0 {
            self.last_seq = h.seq;
            self.synced = true;
        } else if self.synced && h.seq == self.last_seq.wrapping_add(1) {
            self.last_seq = h.seq;
        } else {
            self.synced = false;
            self.refused += 1;
            return Verdict::Refuse;
        }
        self.pmic_on = h.flags & PMIC_ON != 0;
        if h.flags & VCOM_SET != 0 {
            self.vcom_mv = h.vcom_mv;
        }
        if h.flags & DRIVE != 0 {
            Verdict::Drive {
                first: h.scan_first,
                last: h.scan_last,
            }
        } else {
            Verdict::Accept
        }
    }
}

#[cfg(test)]
#[allow(
    clippy::panic,
    clippy::cast_possible_truncation,
    clippy::many_single_char_names,
    clippy::print_stderr,
    clippy::similar_names,
    reason = "tests"
)]
mod tests {
    use super::*;

    #[test]
    fn crc_check_value() {
        assert_eq!(crc16(b"123456789"), 0x6F91);
    }

    #[test]
    fn frame_round_trip() {
        let drive: Vec<u8> = (0..DRIVE_BYTES).map(|i| (i * 31 % 251) as u8).collect();
        let h = Header {
            flags: DRIVE | PMIC_ON,
            seq: 0xDEAD_BEEF,
            scan_first: 3,
            scan_last: 590,
            vcom_mv: 1520,
        };
        let mut wire = vec![0u8; FRAME_BYTES];
        pack_frame(&h, &drive, &mut wire);
        let h2 = unpack_frame(&wire).unwrap_or_else(|e| panic!("{e}"));
        assert_eq!(h2, h);
        for r in 0..PANEL_H {
            assert_eq!(
                frame_row(&wire, r),
                &drive[r * ROW_BYTES..(r + 1) * ROW_BYTES]
            );
        }
        // Panel row 13 = DSI line 13, bytes 32..232.
        assert_eq!(
            &wire[13 * LINE_BYTES + 32..13 * LINE_BYTES + 232],
            &drive[13 * 200..14 * 200]
        );
        assert!(wire[13 * LINE_BYTES..13 * LINE_BYTES + 32]
            .iter()
            .all(|&b| b == 0));
        let mut fb = vec![0u32; DSI_W * DSI_H];
        to_xrgb8888(&wire, &mut fb);
        assert_eq!(fb[0], u32::from_be_bytes([0, b'E', b'P', b'D']));
    }

    #[test]
    fn header_rejections() {
        let good = Header {
            flags: DRIVE,
            seq: 7,
            scan_first: 0,
            scan_last: 599,
            vcom_mv: 0,
        }
        .encode();
        assert!(Header::decode(&good).is_ok());
        for i in 0..HEADER_LEN - 2 {
            let mut bad = good;
            bad[i] ^= 0x10;
            assert!(Header::decode(&bad).is_err(), "byte {i}");
        }
        let resync_drive = Header {
            flags: RESYNC | DRIVE,
            ..Header::default()
        }
        .encode();
        assert_eq!(Header::decode(&resync_drive), Err(LinkError::ResyncDrives));
        let window = Header {
            flags: DRIVE,
            scan_first: 10,
            scan_last: 600,
            ..Header::default()
        }
        .encode();
        assert!(matches!(
            Header::decode(&window),
            Err(LinkError::ScanWindow { .. })
        ));
    }

    #[test]
    fn bridge_refuses_stale_and_headerless_frames() {
        let drive = vec![0x55u8; DRIVE_BYTES];
        let mut wire = vec![0u8; FRAME_BYTES];
        let mut seq = Sequencer::default();
        let mut br = Bridge::default();
        // A plain RGB frame (boot logo) never drives.
        assert_eq!(br.receive(&vec![0x80; FRAME_BYTES]), Verdict::Refuse);
        // Nor does a valid drive frame before a resync.
        pack_frame(&seq.drive(Some((0, 599))), &drive, &mut wire);
        assert_eq!(br.receive(&wire), Verdict::Refuse);
        pack_frame(&seq.resync(), &drive, &mut wire);
        assert_eq!(br.receive(&wire), Verdict::Accept);
        pack_frame(&seq.drive(Some((5, 9))), &drive, &mut wire);
        assert_eq!(br.receive(&wire), Verdict::Drive { first: 5, last: 9 });
        // A rescanned RESYNC is refused but keeps sync.
        pack_frame(&seq.resync(), &drive, &mut wire);
        assert_eq!(br.receive(&wire), Verdict::Accept);
        assert_eq!(br.receive(&wire), Verdict::Refuse);
        pack_frame(&seq.drive(Some((5, 9))), &drive, &mut wire);
        assert_eq!(br.receive(&wire), Verdict::Drive { first: 5, last: 9 });
        // The display controller rescans the same buffer: inert after the first scan.
        assert_eq!(br.receive(&wire), Verdict::Refuse);
        pack_frame(&seq.drive(None), &drive, &mut wire);
        assert_eq!(
            br.receive(&wire),
            Verdict::Refuse,
            "desynced until the next resync"
        );
        assert_eq!(br.refused, 5);
    }

    #[test]
    fn sequencer_reuses_seq_after_failed_commit() {
        let mut s = Sequencer::default();
        let a = s.drive(None).seq;
        s.commit_failed();
        assert_eq!(s.drive(None).seq, a);
        s.set_vcom(1500);
        assert_eq!(s.drive(None).flags & VCOM_SET, VCOM_SET);
        assert_eq!(s.drive(None).flags & VCOM_SET, 0);
        assert_eq!(s.drain().flags, 0);
    }
}
