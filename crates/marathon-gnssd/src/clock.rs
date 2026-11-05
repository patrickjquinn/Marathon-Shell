//! The receiver's reference clock is an uncompensated crystal: its frequency
//! follows its temperature, which the DSP reports as a thermistor code each
//! epoch (msg 0x42). The host tells the DSP the frequency offset expected at
//! three codes around the current one (msg 0x10); the DSP interpolates.
//!
//! The model starts from the line through the values the stock engine sent on
//! this phone, which only covered codes 28866-30786 (a cool phone), and learns
//! a correction per code bin from the common Doppler offset the DSP reports
//! while tracking: with the aid right that offset is 1626 Hz, and it rises
//! about 0.87 Hz per aid unit the aid is too high (from aid sweeps on the
//! phone, `--clock-sweep`).

use std::collections::BTreeMap;

/// The stock engine's line: offset 1248 at code 29186, rising 0.3775 per code.
const BASE_CODE: f64 = 29_186.0;
const BASE_OFFSET: f64 = 1_248.0;
const SLOPE: f64 = 0.3775;
/// Spacing of the three points sent.
const SPREAD: i32 = 800;
/// The GPS Doppler offset (Hz) the DSP reports when the aid is right, and how
/// it moves per aid unit.
pub const NOMINAL_DOPPLER: f64 = 1_626.0;
const HZ_PER_UNIT: f64 = 0.87;
/// Fraction of each measured error applied, the largest step and the largest
/// correction (aid units), and the code bin width.
const GAIN: f64 = 0.2;
const MAX_STEP: f64 = 100.0;
const MAX_CORRECTION: f64 = 2_000.0;
const BIN: i32 = 250;

/// The crystal's expected frequency offset (aid units) per thermistor code.
#[derive(Debug, Default, Clone, PartialEq)]
pub struct Model {
    /// Learnt correction per code bin.
    bins: BTreeMap<i32, f64>,
}

impl Model {
    /// The correction at a code: interpolated between learnt bin centres, the
    /// nearest one's beyond them.
    #[allow(clippy::cast_possible_truncation, reason = "bin numbers are small")]
    fn correction(&self, code: i32) -> f64 {
        let at = f64::from(code) / f64::from(BIN) - 0.5;
        let below = self.bins.range(..=at.floor() as i32).next_back();
        let above = self.bins.range(at.ceil() as i32..).next();
        match (below, above) {
            (Some((&b0, &c0)), Some((&b1, &c1))) if b1 > b0 => {
                c0 + (c1 - c0) * (at - f64::from(b0)) / f64::from(b1 - b0)
            }
            (Some((_, &c)), _) | (None, Some((_, &c))) => c,
            (None, None) => 0.0,
        }
    }

    /// The expected offset at a thermistor code.
    #[allow(clippy::cast_possible_truncation, reason = "offset units fit i32")]
    pub fn offset(&self, code: i32) -> i32 {
        (BASE_OFFSET + SLOPE * (f64::from(code) - BASE_CODE) + self.correction(code)).round() as i32
    }

    /// The (code, offset) points for msg 0x10 around the current code.
    pub fn aid(&self, code: u16) -> [(u16, i32); 3] {
        let c = i32::from(code);
        [c - SPREAD, c, c + SPREAD].map(|x| {
            (
                u16::try_from(x.clamp(0, i32::from(u16::MAX))).unwrap_or(u16::MAX),
                self.offset(x),
            )
        })
    }

    /// Learns from the common GPS Doppler offset (Hz) the DSP reported at
    /// `code` while the aid was this model's.
    pub fn learn(&mut self, code: u16, doppler: f64) {
        let c = i32::from(code);
        let step = (GAIN * (NOMINAL_DOPPLER - doppler) / HZ_PER_UNIT).clamp(-MAX_STEP, MAX_STEP);
        let now = self.correction(c);
        self.bins.insert(
            c.div_euclid(BIN),
            (now + step).clamp(-MAX_CORRECTION, MAX_CORRECTION),
        );
    }

    pub fn to_lines(&self) -> String {
        let lines: Vec<String> = self
            .bins
            .iter()
            .map(|(b, c)| format!("{b} {c:e}"))
            .collect();
        lines.join("\n") + "\n"
    }

    pub fn from_lines(s: &str) -> Self {
        let bins = s
            .lines()
            .filter_map(|l| {
                let (b, c) = l.split_once(' ')?;
                Some((b.parse().ok()?, c.parse().ok()?))
            })
            .collect();
        Self { bins }
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn stock_points() {
        // The stock engine's first aid on this phone, at code 29986, and
        // one ten minutes later at 29666.
        let m = Model::default();
        assert_eq!(
            m.aid(29_986),
            [(29_186, 1248), (29_986, 1550), (30_786, 1852)]
        );
        assert_eq!(m.aid(29_666)[0], (28_866, 1127));
    }

    #[test]
    fn learns_a_hot_crystal() {
        // The crystal needs 280 units less than the line at code 27300; the
        // DSP reports the aid's error as Doppler offset.
        let mut m = Model::default();
        let truth = Model::default().offset(27_300) - 280;
        for _ in 0..100 {
            let doppler = NOMINAL_DOPPLER + HZ_PER_UNIT * f64::from(m.offset(27_300) - truth);
            m.learn(27_300, doppler);
        }
        assert!(
            (m.offset(27_300) - truth).abs() <= 2,
            "{} {truth}",
            m.offset(27_300)
        );
        // Codes beyond the learnt bin keep its correction.
        let far = Model::default().offset(26_000) - 280;
        assert!(
            (m.offset(26_000) - far).abs() <= 3,
            "{} {far}",
            m.offset(26_000)
        );
        assert_eq!(Model::from_lines(&m.to_lines()), m);
    }
}
