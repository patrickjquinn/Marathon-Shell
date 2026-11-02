//! Host commands that keep the DSP searching and tracking.
//!
//! The values are those the receiver needs on a cold start (protocol notes in
//! docs/hardware/mt6789-gnss.md): engine settings once after boot, then every
//! epoch the next epoch's DSP time, the reference-clock aiding, a time aid,
//! the list of satellites to search and the end-of-commands marker.

use crate::mtk::encode;

const CONTROL: u16 = 0xfe05;
const EPOCH: u16 = 0xfe00;
const TIME_AID: u16 = 0xfe01;
const LISTS: u16 = 0xfe03;
const MASKS: u16 = 0xfe04;
const MODE: u16 = 0xfe08;
const CLOCK_A: u16 = 0xfe10;
const CLOCK_B: u16 = 0xfe11;
const END: u16 = 0xfe1c;

pub const GPS: u8 = 0x01;
pub const QZSS: u8 = 0x08;
pub const GLONASS: u8 = 0x10;
pub const BEIDOU: u8 = 0x20;

const SETTINGS: [&[u8]; 9] = [
    &[0x32, 0, 0, 1, 0],
    &[0x0a, 0, 0, 0, 0, 0, 0, 0, 0],
    &[0x46, 2, 0, 1, 0x0b, 0xee, 0xff, 0x98, 0x6e],
    &[0x46, 1, 0, 1, 0x0a, 0xe1, 0xff, 0xa4, 0x70],
    &[0x36, 0, 0, 0, 0],
    &[0x2a, 0, 0, 0, 0],
    &[0x34, 0, 0, 1, 0],
    &[0x0f, 0, 0, 0xe8, 0x03],
    &[0x15, 0, 0, 2, 0],
];

/// Signals enabled per system, all on.
const ENABLE: [u8; 56] = [
    0xff, 0xff, 0xff, 0xff, 0, 0, 0x0f, 0, 0xff, 0xff, 0xff, 0xff, 0, 0, 0x7f, 0, 0, 0, 0, 0, 0, 0,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f, 0, 0, 0xff, 0xff, 0xff, 0xff, 0, 0, 0, 0, 0xff,
    0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0, 0, 0x7f, 0, 0, 0, 0, 0,
];

/// Commands sent once, right after the DSP has booted.
pub fn start() -> Vec<u8> {
    let mut out: Vec<u8> = SETTINGS.iter().flat_map(|p| encode(CONTROL, p)).collect();
    out.extend(encode(MASKS, &ENABLE));
    out.extend(encode(MODE, &[0x10, 0, 0x10, 0]));
    out
}

/// A 32-bit value as the DSP sends it: high 16-bit word first, each word little-endian.
fn words_u32(value: u32) -> [u8; 4] {
    let hi = (value >> 16) as u16;
    #[allow(clippy::cast_possible_truncation, reason = "low word")]
    let lo = value as u16;
    [hi.to_le_bytes(), lo.to_le_bytes()]
        .concat()
        .try_into()
        .unwrap_or_default()
}

/// The reference-clock aid: the crystal's expected frequency offset at three
/// thermistor codes around the current one (see `clock`).
fn clock_aid(points: &[(u16, i32); 3]) -> Vec<u8> {
    let mut v = vec![1];
    for &(code, offset) in points {
        v.extend(words_u32(u32::from(code) << 16));
        v.extend(words_u32(offset.cast_unsigned()));
    }
    v
}

/// Commands for the epoch after `dsp_ms`; `tow` is the GPS time of week of
/// that epoch from the system clock, `clock` the reference-clock aid and
/// `search` the (satellite, system) pairs in search order.
pub fn epoch(dsp_ms: u32, tow: f64, clock: &[(u16, i32); 3], search: &[(u8, u8)]) -> Vec<u8> {
    let mut out = encode(CONTROL, &[0x34, 0, 0, 1, 0]);
    out.extend(encode(EPOCH, &words_u32(dsp_ms.wrapping_add(1000))));
    out.extend(encode(CLOCK_A, &clock_aid(clock)));
    out.extend(encode(CLOCK_B, &[0; 11]));
    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        reason = "1.5 s count wraps at 16 bits"
    )]
    let units = ((tow / 1.5) as u32 & 0xffff) as u16;
    let mut aid = [0u8; 18];
    aid[0] = 5;
    aid[4..6].copy_from_slice(&0x1bb4u16.to_le_bytes());
    aid[11] = 1;
    aid[13..15].copy_from_slice(&units.to_le_bytes());
    out.extend(encode(TIME_AID, &aid));
    out.extend(encode(LISTS, &[0, 0]));
    let n = search.len().min(87);
    let mut list = vec![1, u8::try_from(n).unwrap_or(87)];
    list.extend(search[..n].iter().flat_map(|&(sv, sys)| [sv, sys]));
    out.extend(encode(LISTS, &list));
    out.extend(encode(END, &[]));
    out.extend(encode(CONTROL, &[0x29, 0]));
    out
}

/// The satellites to search, in order. `gps` leads (tracked, then expected
/// up); the other GPS PRNs follow unless `gps_only_these`, so that a known
/// sky gets the DSP's whole search effort. `glonass` (frequency slot + 8)
/// and `beidou` lead their systems.
pub fn search_order(
    gps: &[u8],
    gps_only_these: bool,
    glonass: &[u8],
    beidou: &[u8],
) -> Vec<(u8, u8)> {
    let mut v: Vec<(u8, u8)> = gps.iter().map(|&p| (p, GPS)).collect();
    if !gps_only_these {
        v.extend((1..=32).filter(|p| !gps.contains(p)).map(|p| (p, GPS)));
    }
    v.extend([193, 194, 195, 199].map(|p| (p, QZSS)));
    v.extend(glonass.iter().map(|&k| (k, GLONASS)));
    v.extend(
        (1..=14)
            .filter(|k| !glonass.contains(k))
            .map(|k| (k, GLONASS)),
    );
    v.extend(beidou.iter().map(|&p| (p, BEIDOU)));
    v.extend(
        (1..=37)
            .filter(|p| !beidou.contains(p))
            .map(|p| (p, BEIDOU)),
    );
    v
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn epoch_time_words() {
        // DSP ms 400615 -> next epoch 401615 = 0x000620cf, sent as 06 00 cf 20.
        let clock = [(29_186, 1248), (29_986, 1550), (30_786, 1848)];
        let out = epoch(
            400_615,
            123_528.0,
            &clock,
            &search_order(&[], false, &[], &[]),
        );
        let start = encode(CONTROL, &[0x34, 0, 0, 1, 0]).len();
        assert_eq!(
            &out[start..start + 10],
            &[0xaa, 0xf0, 0x08, 0x00, 0x00, 0xfe, 0x06, 0x00, 0xcf, 0x20]
        );
        // The stock engine's first aid on this phone, byte for byte.
        let aid = [
            0x01, 0x02, 0x72, 0, 0, 0, 0, 0xe0, 0x04, 0x22, 0x75, 0, 0, 0, 0, 0x0e, 0x06, 0x42,
            0x78, 0, 0, 0, 0, 0x38, 0x07,
        ];
        assert_eq!(clock_aid(&clock), aid);
    }

    #[test]
    fn search_list_shape() {
        let s = search_order(&[30, 18], false, &[9], &[36]);
        assert_eq!(s.len(), 87);
        assert_eq!((s[0], s[1], s[2]), ((30, GPS), (18, GPS), (1, GPS)));
        assert_eq!((s[36], s[37]), ((9, GLONASS), (1, GLONASS)));
        assert_eq!(s[50], (36, BEIDOU));
        let only = search_order(&[13, 32], true, &[], &[]);
        assert_eq!((only.len(), only[2]), (57, (193, QZSS)));
    }
}
