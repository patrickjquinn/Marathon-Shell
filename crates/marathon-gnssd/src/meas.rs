//! Channel records (msg 0x29) and pseudoranges from them.
//!
//! A record carries the channel, satellite and system, C/N0 in dB-Hz, a
//! tracking state, the DSP's time estimate, the code phase (16-bit chips plus
//! a 16-bit fraction, high word first), the Doppler in Hz (including the
//! reference-clock offset) and the accumulated carrier phase.

use crate::orbit::C;
use crate::sat::Sat;
use nalgebra::Vector3;

pub const GPS: u8 = 0x01;
pub const GLONASS: u8 = 0x10;
pub const BEIDOU: u8 = 0x20;
/// Tracking-state bytes of a channel in steady code and carrier lock.
const LOCKED: [u8; 4] = [0x00, 0x14, 0x40, 0x2c];
/// Largest Doppler disagreement with the geometry, Hz.
const DOPPLER_TOLERANCE: f64 = 50.0;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Channel {
    pub channel: u8,
    /// GPS/BeiDou PRN, or GLONASS frequency slot (channel number + 8).
    pub sv: u8,
    pub system: u8,
    pub cn0: u8,
    pub locked: bool,
    /// Code phase in chips.
    pub chips: f64,
    pub doppler: i16,
}

pub fn channel(p: &[u8]) -> Option<Channel> {
    let w = |at: usize| p.get(at..at + 2).map(|b| u16::from_le_bytes([b[0], b[1]]));
    Some(Channel {
        channel: *p.first()?,
        sv: *p.get(1)?,
        system: *p.get(2)?,
        cn0: *p.get(3)?,
        locked: p.get(4..8)? == LOCKED,
        chips: f64::from(w(27)?) + f64::from(w(29)?) / 65536.0,
        doppler: w(31)?.cast_signed(),
    })
}

/// A GPS subframe (msg 0x2B record): a parity-failure mask with one bit per
/// word, the PRN, the subframe id, then ten 32-bit words in the DSP's word
/// order whose low 24 bits are the corrected data bits. Only clean ones.
pub fn gps_subframe(p: &[u8]) -> Option<(u8, [u8; 30])> {
    let w16 = |at: usize| p.get(at..at + 2).map(|b| u16::from_le_bytes([b[0], b[1]]));
    if w16(0)? & 0x3ff != 0 {
        return None;
    }
    let prn = u8::try_from(w16(2)?).ok()?;
    let mut words = [0u32; 10];
    for (i, w) in words.iter_mut().enumerate() {
        let at = 6 + 4 * i;
        *w = (u32::from(w16(at)?) << 16 | u32::from(w16(at + 2)?)) & 0x00ff_ffff;
    }
    Some((prn, crate::lnav::subframe_from_data(&words)?))
}

/// A BeiDou D1 subframe (msg 0x4B record): three bytes of word-failure
/// flags, the PRN, the subframe id, the page (subframes 4 and 5), then ten
/// 30-bit words in the DSP's word order with parity bits kept. Only clean ones.
pub fn beidou_subframe(p: &[u8]) -> Option<(u8, crate::d1::Subframe)> {
    let w16 = |at: usize| p.get(at..at + 2).map(|b| u16::from_le_bytes([b[0], b[1]]));
    if p.get(..3)? != [0, 0, 0] {
        return None;
    }
    let mut words = [0u32; 10];
    for (i, w) in words.iter_mut().enumerate() {
        let at = 7 + 4 * i;
        *w = (u32::from(w16(at)?) << 16 | u32::from(w16(at + 2)?)) & 0x3fff_ffff;
    }
    crate::d1::frame_id(&words)?;
    Some((p[3], words))
}

/// Range rate (m/s) from `approx` to the satellite around time `t`.
fn range_rate(sat: &Sat, t: f64, approx: Vector3<f64>) -> f64 {
    (sat.position(t + 0.5).0 - approx).norm() - (sat.position(t - 0.5).0 - approx).norm()
}

/// The channels whose Doppler matches the geometry once one reference-clock
/// frequency offset, common to all of them, is removed.
pub fn doppler_consistent<'a>(
    chans: &[(Channel, Sat<'a>)],
    t: f64,
    approx: Vector3<f64>,
) -> Vec<(Channel, Sat<'a>)> {
    let ratio = |(c, s): &(Channel, Sat)| {
        (f64::from(c.doppler) + range_rate(s, t, approx) * s.carrier() / C) / s.carrier()
    };
    let mut drifts: Vec<f64> = chans.iter().map(ratio).collect();
    drifts.sort_by(f64::total_cmp);
    let Some(&drift) = drifts.get(drifts.len() / 2) else {
        return Vec::new();
    };
    chans
        .iter()
        .filter(|o| ((ratio(o) - drift) * o.1.carrier()).abs() < DOPPLER_TOLERANCE)
        .copied()
        .collect()
}

/// Satellite-clock transmit times (GPS seconds of week) for the channels.
///
/// The code phase gives the transmit time modulo the code period; the whole
/// periods come from the geometry predicted from an approximate
/// position and time, relative to one reference satellite so that an error
/// in the approximate time cancels.
pub fn transmit_times<'a>(
    chans: &[(Channel, Sat<'a>)],
    t: f64,
    approx: Vector3<f64>,
) -> Vec<(Sat<'a>, f64)> {
    let mut pred = Vec::new();
    for (c, sat) in chans {
        let mut tau = 0.075;
        for _ in 0..3 {
            tau = (sat.position(t - tau).0 - approx).norm() / C;
        }
        let frac = (c.chips / sat.chip_rate()) % sat.code_period();
        pred.push((*sat, t - tau + sat.position(t - tau).1, frac));
    }
    let Some(&(s0, p0, f0)) = pred.first() else {
        return Vec::new();
    };
    let base = ((p0 - f0) / s0.code_period()).round() * s0.code_period() + f0;
    pred.into_iter()
        .map(|(sat, p, f)| {
            let n = ((p - p0 - (f - f0)) / sat.code_period()).round();
            (sat, base + (f - f0) + n * sat.code_period())
        })
        .collect()
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn record_from_reference_run() {
        // A GPS PRN 30 record (unscrambled) as the Q25 DSP reported it.
        let p = hex("001e011d0014402c5788200165006500e4020509000100af4116006e4d793cabfd7acf0200eafaa4ed1d0000001a0008203b01770000000c0048e70080000000000000");
        let c = channel(&p).unwrap();
        assert_eq!(
            (c.channel, c.sv, c.system, c.cn0, c.doppler),
            (0, 30, GPS, 29, -597)
        );
        assert!((c.chips - (19822.0 + 15481.0 / 65536.0)).abs() < 1e-9);
    }

    #[test]
    fn subframe_record() {
        // Built like the DSP's: mask 0, PRN 30, subframe 2, then words with
        // parity bits above the data.
        let sf = crate::lnav::tests::subframe(2, |b| crate::lnav::tests::put(b, 48, 8, 83));
        let mut p = vec![0, 0, 30, 0, 2, 0];
        for c in sf.chunks(3) {
            let w = 0x2b00_0000 | u32::from(c[0]) << 16 | u32::from(c[1]) << 8 | u32::from(c[2]);
            p.extend_from_slice(&u16::try_from(w >> 16).unwrap().to_le_bytes());
            p.extend_from_slice(&u16::try_from(w & 0xffff).unwrap().to_le_bytes());
        }
        assert_eq!(gps_subframe(&p), Some((30, sf)));
        p[0] = 1;
        assert_eq!(gps_subframe(&p), None);
    }

    fn hex(s: &str) -> Vec<u8> {
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
            .collect()
    }
}
