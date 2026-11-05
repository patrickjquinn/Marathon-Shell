//! BeiDou B1I D1 navigation message (BDS-SIS-ICD-B1I 3.0, section 5.2):
//! the ephemeris in subframes 1-3 of the MEO and IGSO satellites.
//!
//! A subframe is ten 30-bit words, the first bit of the subframe in bit 29
//! of word 0. Bit positions below count from that first bit with the
//! parity bits still in place: each word carries 22 data bits then 8 parity
//! bits (word 0: 26 then 4).

use crate::lnav::Ephemeris;
use std::f64::consts::PI;

const PREAMBLE: u32 = 0x712;

pub type Subframe = [u32; 10];

fn bits(s: &Subframe, pos: usize, len: usize) -> u64 {
    (pos..pos + len).fold(0, |v, i| v << 1 | u64::from(s[i / 30] >> (29 - i % 30) & 1))
}

/// A field split over two words.
fn bits2(s: &Subframe, (p1, l1): (usize, usize), (p2, l2): (usize, usize)) -> u64 {
    bits(s, p1, l1) << l2 | bits(s, p2, l2)
}

#[allow(clippy::cast_possible_wrap, reason = "two's complement field")]
fn signed(v: u64, len: usize) -> f64 {
    #[allow(clippy::cast_precision_loss, reason = "fields are at most 32 bits")]
    let x = ((v << (64 - len)) as i64 >> (64 - len)) as f64;
    x
}

#[allow(clippy::cast_precision_loss, reason = "fields are at most 32 bits")]
fn unsigned(v: u64) -> f64 {
    v as f64
}

/// Subframe id (1-5), or `None` without the preamble.
pub fn frame_id(s: &Subframe) -> Option<u8> {
    #[allow(clippy::cast_possible_truncation, reason = "3-bit field")]
    (bits(s, 0, 11) == u64::from(PREAMBLE)).then(|| bits(s, 15, 3) as u8)
}

/// Collects subframes 1-3 of one satellite into an ephemeris.
#[derive(Default)]
pub struct EphemerisBuilder {
    sf: [Option<Subframe>; 3],
}

impl EphemerisBuilder {
    /// Adds a checked subframe; returns the ephemeris once 1-3 describe the
    /// same reference time.
    pub fn add(&mut self, s: Subframe) -> Option<Ephemeris> {
        let id = frame_id(&s)?;
        if !(1..=3).contains(&id) {
            return None;
        }
        self.sf[usize::from(id) - 1] = Some(s);
        let [Some(s1), Some(s2), Some(s3)] = self.sf else {
            return None;
        };
        let e = decode(&s1, &s2, &s3);
        #[allow(clippy::float_cmp, reason = "both are integer multiples of 8 s")]
        (e.toc == e.toe).then_some(e)
    }
}

/// Times are BDT seconds of week, like the RINEX BeiDou records.
#[allow(clippy::cast_possible_truncation, reason = "field widths fit")]
fn decode(s1: &Subframe, s2: &Subframe, s3: &Subframe) -> Ephemeris {
    let s = |b, len| signed(b, len);
    let at = |v: f64, exp| v * 2f64.powi(exp);
    let sc = |v: f64, exp| v * 2f64.powi(exp) * PI;
    Ephemeris {
        health: bits(s1, 42, 1) as u8,
        iodc: bits(s1, 43, 5) as u16,
        week: bits(s1, 60, 13) as u16,
        toc: unsigned(bits2(s1, (73, 9), (90, 8))) * 8.0,
        tgd: s(bits(s1, 98, 10), 10) * 1e-10,
        af2: at(s(bits(s1, 214, 11), 11), -66),
        af0: at(s(bits2(s1, (225, 7), (240, 17)), 24), -33),
        af1: at(s(bits2(s1, (257, 5), (270, 17)), 22), -50),
        iode: bits(s1, 287, 5) as u8,
        dn: sc(s(bits2(s2, (42, 10), (60, 6)), 16), -43),
        cuc: at(s(bits2(s2, (66, 16), (90, 2)), 18), -31),
        m0: sc(s(bits2(s2, (92, 20), (120, 12)), 32), -31),
        e: at(unsigned(bits2(s2, (132, 10), (150, 22))), -33),
        cus: at(s(bits(s2, 180, 18), 18), -31),
        crc: at(s(bits2(s2, (198, 4), (210, 14)), 18), -6),
        crs: at(s(bits2(s2, (224, 8), (240, 10)), 18), -6),
        sqrt_a: at(unsigned(bits2(s2, (250, 12), (270, 20))), -19),
        toe: unsigned(bits(s2, 290, 2) << 15 | bits2(s3, (42, 10), (60, 5))) * 8.0,
        i0: sc(s(bits2(s3, (65, 17), (90, 15)), 32), -31),
        cic: at(s(bits2(s3, (105, 7), (120, 11)), 18), -31),
        omega_dot: sc(s(bits2(s3, (131, 11), (150, 13)), 24), -43),
        cis: at(s(bits2(s3, (163, 9), (180, 9)), 18), -31),
        idot: sc(s(bits2(s3, (189, 13), (210, 1)), 14), -43),
        omega0: sc(s(bits2(s3, (211, 21), (240, 11)), 32), -31),
        omega: sc(s(bits2(s3, (251, 11), (270, 21)), 32), -31),
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    /// C33's subframes 1-3 as the DSP reported them (0xFE4B) at BDT
    /// 129510-129522 on 2 November 2026.
    const C33: [&str; 3] = [
        "000000210001ff9038f8119827a5107e08df3da321a5d8203d37fec43d1492312e523f00247142d232b49fd03d7441",
        "000000210002ff9038fa21b0275f9dfd2d5a040910e887e41d4900152e9d57dd011861fc0b5efeaa0a2c515514e2ec",
        "000000210003ff9038f531c9277bec500cc9b9fc3d8dffbf3d39fdfd27d2ff603ffe7295019d44f03e6ddebd1684ee",
    ];

    fn record(hex: &str) -> Vec<u8> {
        (0..hex.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap())
            .collect()
    }

    #[test]
    fn decodes_c33() {
        let mut b = EphemerisBuilder::default();
        let mut e = None;
        for hex in C33 {
            let (prn, s) = crate::meas::beidou_subframe(&record(hex)).unwrap();
            assert_eq!(prn, 33);
            e = b.add(s);
        }
        let e = e.unwrap();
        assert_eq!((e.toc, e.toe, e.health), (126_000.0, 126_000.0, 0));
        assert!((e.sqrt_a - 5282.6355).abs() < 1e-3, "{}", e.sqrt_a);
        assert!((e.i0 - 0.990_662_5).abs() < 1e-6, "{}", e.i0);
        assert!((e.af0 + 9.339e-4).abs() < 1e-7, "{}", e.af0);
        assert!((e.e - 3.5159e-4).abs() < 1e-8, "{}", e.e);
    }

    #[test]
    fn rejects_flagged_records() {
        let mut r = record(C33[0]);
        r[0] = 0x80;
        assert!(crate::meas::beidou_subframe(&r).is_none());
    }
}
