//! E Ink `.wbf` waveform files.
//!
//! Ported from yobert/swtcon `src/wbf.rs` and `src/waveform.rs`
//! (<https://github.com/yobert/swtcon>), used under the MIT License:
//!
//! > Copyright (c) 2026 Joel Jensen
//! >
//! > Permission is hereby granted, free of charge, to any person obtaining a copy of this
//! > software and associated documentation files (the "Software"), to deal in the Software
//! > without restriction, including without limitation the rights to use, copy, modify, merge,
//! > publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons
//! > to whom the Software is furnished to do so, subject to the following conditions:
//! >
//! > The above copyright notice and this permission notice shall be included in all copies or
//! > substantial portions of the Software.
//! >
//! > THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
//! > INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
//! > PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
//! > FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
//! > OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//! > DEALINGS IN THE SOFTWARE.
//!
//! Header fields used: file size (u32 @0x04), FPL lot (u16 @0x0e), mode-table offset
//! (u24 @0x20), element-size flag (@0x24), last mode and last temperature index (@0x25, @0x26),
//! END and TOGGLE marker bytes (@0x28, @0x29), temperature bounds (@0x30). Which WBF mode is
//! which (DU, GC16, GL16, A2 ...) depends on the file's mode version; callers pick by index.

use std::fmt;

use crate::waveform::{Mode, Table, Waveform, MAX_FRAMES};

const SIZE: usize = 0x04;
const FPL_LOT: usize = 0x0e;
const MODE_OFF: usize = 0x20;
const FLAGS: usize = 0x24;
const LAST_MODE: usize = 0x25;
const LAST_TEMP: usize = 0x26;
const END_BYTE: usize = 0x28;
const TOGGLE_BYTE: usize = 0x29;
const TEMP_TABLE: usize = 0x30;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WbfError {
    TooSmall,
    SizeMismatch { header: u32, actual: usize },
    ModeOutOfRange { mode: u8, max: u8 },
    TempOutOfRange { temp: u8, max: u8 },
    OutOfBounds { offset: usize, size: usize },
    TooLong { frames: usize },
}

impl fmt::Display for WbfError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            WbfError::TooSmall => write!(f, "wbf: file smaller than header"),
            WbfError::SizeMismatch { header, actual } => {
                write!(f, "wbf: size header {header} != actual {actual}")
            }
            WbfError::ModeOutOfRange { mode, max } => write!(f, "wbf: mode {mode} > max {max}"),
            WbfError::TempOutOfRange { temp, max } => write!(f, "wbf: temp {temp} > max {max}"),
            WbfError::OutOfBounds { offset, size } => {
                write!(f, "wbf: offset 0x{offset:x} past size 0x{size:x}")
            }
            WbfError::TooLong { frames } => write!(f, "wbf: {frames} frames exceeds {MAX_FRAMES}"),
        }
    }
}

impl std::error::Error for WbfError {}

#[derive(Debug, Clone, Copy)]
pub struct Wbf<'a> {
    raw: &'a [u8],
}

impl<'a> Wbf<'a> {
    pub fn parse(raw: &'a [u8]) -> Result<Self, WbfError> {
        if raw.len() <= TEMP_TABLE {
            return Err(WbfError::TooSmall);
        }
        let header = u32::from_le_bytes([raw[SIZE], raw[SIZE + 1], raw[SIZE + 2], raw[SIZE + 3]]);
        if header as usize != raw.len() {
            return Err(WbfError::SizeMismatch {
                header,
                actual: raw.len(),
            });
        }
        Ok(Self { raw })
    }

    pub fn fpl_lot(&self) -> u16 {
        u16::from_le_bytes([self.raw[FPL_LOT], self.raw[FPL_LOT + 1]])
    }

    pub fn last_mode(&self) -> u8 {
        self.raw[LAST_MODE]
    }

    pub fn last_temp(&self) -> u8 {
        self.raw[LAST_TEMP]
    }

    fn element_size(&self) -> usize {
        if self.raw[FLAGS] & 0xc == 4 {
            0x400
        } else {
            0x100
        }
    }

    /// Lower bound in °C of temperature range `i`.
    pub fn temp_bound(&self, i: u8) -> Result<u8, WbfError> {
        self.byte(TEMP_TABLE + usize::from(i))
    }

    fn byte(&self, off: usize) -> Result<u8, WbfError> {
        self.raw.get(off).copied().ok_or(WbfError::OutOfBounds {
            offset: off,
            size: self.raw.len(),
        })
    }

    fn u24(&self, off: usize) -> Result<usize, WbfError> {
        Ok(usize::from(self.byte(off)?)
            | usize::from(self.byte(off + 1)?) << 8
            | usize::from(self.byte(off + 2)?) << 16)
    }

    fn table_offset(&self, mode: u8, temp: u8) -> Result<usize, WbfError> {
        if mode > self.last_mode() {
            return Err(WbfError::ModeOutOfRange {
                mode,
                max: self.last_mode(),
            });
        }
        if temp > self.last_temp() {
            return Err(WbfError::TempOutOfRange {
                temp,
                max: self.last_temp(),
            });
        }
        let temps = self.u24(self.u24(MODE_OFF)? + usize::from(mode) * 4)?;
        let table = self.u24(temps + usize::from(temp) * 4)?;
        if table >= self.raw.len() {
            return Err(WbfError::OutOfBounds {
                offset: table,
                size: self.raw.len(),
            });
        }
        Ok(table)
    }

    /// The (mode, temp) table as one 2-bit code per byte, element after element.
    ///
    /// Literal bytes hold four codes (low bits first). TOGGLE flips between run-length mode
    /// (each literal followed by a count minus one) and single literals; END stops.
    pub fn decode(&self, mode: u8, temp: u8) -> Result<Vec<u8>, WbfError> {
        let mut idx = self.table_offset(mode, temp)?;
        let (end, toggle) = (self.raw[END_BYTE], self.raw[TOGGLE_BYTE]);
        let mut out = Vec::new();
        let mut runs = true;
        loop {
            let elem = self.byte(idx)?;
            if elem == end {
                break;
            }
            if elem == toggle {
                runs = !runs;
                idx += 1;
                continue;
            }
            let n = if runs {
                idx += 2;
                usize::from(self.byte(idx - 1)?) + 1
            } else {
                idx += 1;
                1
            };
            for _ in 0..n {
                out.extend([elem & 3, (elem >> 2) & 3, (elem >> 4) & 3, (elem >> 6) & 3]);
            }
        }
        Ok(out)
    }

    /// One mode at one temperature as a [`Table`], using swtcon's (src, dst) element layout.
    pub fn table(&self, mode: u8, temp: u8) -> Result<Table, WbfError> {
        let elem = self.element_size();
        let (src_stride, dst_stride) = if elem == 0x400 { (2, 0x40) } else { (1, 0x10) };
        let decoded = self.decode(mode, temp)?;
        let frames = decoded.len() / elem;
        if frames > MAX_FRAMES {
            return Err(WbfError::TooLong { frames });
        }
        let mut table = Table::default();
        for src in 0..16u8 {
            for dst in 0..16u8 {
                let off = usize::from(src) * src_stride + usize::from(dst) * dst_stride;
                let codes: Vec<u8> = (0..frames).map(|f| decoded[f * elem + off]).collect();
                table.set(src, dst, &codes);
            }
        }
        Ok(table)
    }

    /// The named WBF modes, every temperature range.
    pub fn to_waveform(&self, modes: &[(&str, u8)]) -> Result<Waveform, WbfError> {
        let temps = (0..=self.last_temp())
            .map(|t| self.temp_bound(t).map(i32::from))
            .collect::<Result<_, _>>()?;
        let mut tables = Vec::new();
        let mut out = Vec::new();
        for &(name, mode) in modes {
            let mut idx = Vec::new();
            for t in 0..=self.last_temp() {
                idx.push(tables.len());
                tables.push(self.table(mode, t)?);
            }
            out.push(Mode {
                name: name.to_owned(),
                tables: idx,
            });
        }
        Ok(Waveform {
            temps,
            modes: out,
            tables,
        })
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

    /// A minimal WBF: one mode, two temperature ranges, 256-byte elements.
    fn synth(phases: &[[u8; 256]]) -> Vec<u8> {
        let (end, toggle) = (0xFF, 0xFC);
        let mut f = vec![0u8; 0x40];
        f[LAST_MODE] = 0;
        f[LAST_TEMP] = 1;
        f[END_BYTE] = end;
        f[TOGGLE_BYTE] = toggle;
        f[TEMP_TABLE] = 0;
        f[TEMP_TABLE + 1] = 25;
        f[FPL_LOT] = 0x34;
        f[FPL_LOT + 1] = 0x12;
        let mode_table = f.len();
        f.extend([0u8; 4]);
        let temp_table = f.len();
        f.extend([0u8; 8]);
        let data = f.len();
        // Run-length mode: every literal byte packs four codes, followed by a count of 0.
        for phase in phases {
            for quad in phase.chunks(4) {
                let b = quad[0] | quad[1] << 2 | quad[2] << 4 | quad[3] << 6;
                assert!(b != end && b != toggle);
                f.extend([b, 0]);
            }
        }
        f.push(end);
        let put24 = |f: &mut Vec<u8>, at: usize, v: usize| {
            f[at..at + 3].copy_from_slice(&(v as u32).to_le_bytes()[..3]);
        };
        put24(&mut f, MODE_OFF, mode_table);
        put24(&mut f, mode_table, temp_table);
        put24(&mut f, temp_table, data);
        put24(&mut f, temp_table + 4, data);
        let len = f.len() as u32;
        f[SIZE..SIZE + 4].copy_from_slice(&len.to_le_bytes());
        f
    }

    #[test]
    fn decodes_a_synthetic_file() {
        let mut phases = [[0u8; 256]; 3];
        // Element offset is src + 16*dst for 256-byte elements.
        phases[0][3 + 16 * 15] = 2;
        phases[1][3 + 16 * 15] = 2;
        phases[2][3 + 16 * 15] = 1;
        phases[2][15] = 1;
        let raw = synth(&phases);
        let wbf = Wbf::parse(&raw).unwrap_or_else(|e| panic!("{e}"));
        assert_eq!(wbf.fpl_lot(), 0x1234);
        let wf = wbf
            .to_waveform(&[("GC16", 0)])
            .unwrap_or_else(|e| panic!("{e}"));
        assert_eq!(wf.temps, vec![0, 25]);
        assert_eq!(wf.tables.len(), 2);
        assert_eq!(wf.tables[1].get(3, 15), &[2, 2, 1]);
        assert_eq!(wf.tables[0].get(15, 0), &[0, 0, 1]);
        assert!(matches!(
            wbf.table(1, 0),
            Err(WbfError::ModeOutOfRange { .. })
        ));
    }

    #[test]
    fn rejects_bad_sizes() {
        assert_eq!(Wbf::parse(&[0; 8]).err(), Some(WbfError::TooSmall));
        let mut raw = synth(&[[0; 256]]);
        raw.push(0);
        assert!(matches!(
            Wbf::parse(&raw),
            Err(WbfError::SizeMismatch { .. })
        ));
    }
}
