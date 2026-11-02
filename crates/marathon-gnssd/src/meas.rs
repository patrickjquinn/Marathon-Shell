//! Channel records (msg 0x29) and pseudoranges from them.
//!
//! A record carries the channel, satellite and system, C/N0 in dB-Hz, the
//! DSP's time-of-week estimate, the code phase within the 20 ms data bit
//! (16-bit chips plus a 16-bit fraction, high word first), the Doppler in Hz
//! (including the reference-clock offset) and the accumulated carrier phase.

use crate::lnav::Ephemeris;
use crate::orbit::{position, C};
use nalgebra::Vector3;

pub const GPS: u8 = 0x01;
const CHIP_RATE: f64 = 1.023e6;
const CODE_PERIOD: f64 = 1e-3;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Channel {
    pub channel: u8,
    pub sv: u8,
    pub system: u8,
    pub cn0: u8,
    /// Code phase in chips within the 20 ms bit.
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
        chips: f64::from(w(27)?) + f64::from(w(29)?) / 65536.0,
        doppler: w(31)?.cast_signed(),
    })
}

/// Satellite-clock transmit times (seconds of week) for GPS channels.
///
/// The code phase gives the transmit time modulo 1 ms; the whole
/// milliseconds come from the geometry predicted from an approximate
/// position and time, relative to one reference satellite so that an error
/// in the approximate time cancels.
pub fn transmit_times<'a>(
    chans: &[Channel],
    eph: impl Fn(u8) -> Option<&'a Ephemeris>,
    t: f64,
    approx: Vector3<f64>,
) -> Vec<(&'a Ephemeris, f64)> {
    let mut pred = Vec::new();
    for c in chans.iter().filter(|c| c.system == GPS) {
        let Some(e) = eph(c.sv) else { continue };
        let mut tau = 0.075;
        for _ in 0..3 {
            tau = (position(e, t - tau).0 - approx).norm() / C;
        }
        let frac = (c.chips % (CODE_PERIOD * CHIP_RATE)) / CHIP_RATE;
        pred.push((e, t - tau + position(e, t - tau).1, frac));
    }
    let Some(&(_, p0, f0)) = pred.first() else {
        return Vec::new();
    };
    let base = ((p0 - f0) / CODE_PERIOD).round() * CODE_PERIOD + f0;
    pred.into_iter()
        .map(|(e, p, f)| {
            let n = ((p - p0 - (f - f0)) / CODE_PERIOD).round();
            (e, base + (f - f0) + n * CODE_PERIOD)
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

    fn hex(s: &str) -> Vec<u8> {
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
            .collect()
    }
}
