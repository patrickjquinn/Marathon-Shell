//! The receiver's reference clock is an uncompensated crystal: its frequency
//! follows its temperature, which the DSP reports as a thermistor code each
//! epoch (msg 0x42). The host tells the DSP the frequency offset expected at
//! three codes around the current one (msg 0x10); the DSP interpolates.
//!
//! The model is the line through the values the stock engine sent on this
//! phone (offset units per code unit). Outside the codes it covered (a
//! warmer phone) the line is extrapolated; whether the Doppler offset the
//! DSP reports answers to the aid, and so could correct it, is what
//! `--clock-sweep` measures.

/// The stock engine's line: offset 1248 at code 29186, rising 0.3775 per code.
const BASE_CODE: f64 = 29_186.0;
const BASE_OFFSET: f64 = 1_248.0;
const SLOPE: f64 = 0.3775;
/// Spacing of the three points sent.
const SPREAD: i32 = 800;

/// The crystal's expected frequency offset (aid units) per thermistor code.
#[derive(Debug, Default, Clone, Copy)]
pub struct Model;

impl Model {
    /// The expected offset at a thermistor code.
    #[allow(clippy::cast_possible_truncation, reason = "offset units fit i32")]
    pub fn offset(self, code: i32) -> i32 {
        (BASE_OFFSET + SLOPE * (f64::from(code) - BASE_CODE)).round() as i32
    }

    /// The (code, offset) points for msg 0x10 around the current code.
    pub fn aid(self, code: u16) -> [(u16, i32); 3] {
        let c = i32::from(code);
        [c - SPREAD, c, c + SPREAD].map(|x| {
            (
                u16::try_from(x.clamp(0, i32::from(u16::MAX))).unwrap_or(u16::MAX),
                self.offset(x),
            )
        })
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
        assert_eq!(
            Model.aid(29_986),
            [(29_186, 1248), (29_986, 1550), (30_786, 1852)]
        );
        assert_eq!(Model.aid(29_666)[0], (28_866, 1127));
    }
}
