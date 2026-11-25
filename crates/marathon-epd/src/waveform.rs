//! Waveform tables: what drive code each pixel gets on each frame of a transition from one grey
//! level to another, per mode and temperature band.
//!
//! Codes follow Glider/epdiy: 0 no drive, 1 toward black, 2 toward white. Sources load into
//! [`Waveform`]; the engine uses a flattened, GPU-shaped copy ([`Lut`]).

use std::fmt;
use std::path::Path;

pub const NONE: u8 = 0;
pub const BLACK: u8 = 1;
pub const WHITE: u8 = 2;

/// The longest transition the per-pixel 8-bit frame counter can index.
pub const MAX_FRAMES: usize = 255;

#[derive(Debug)]
pub enum Error {
    Io(std::io::Error),
    Parse {
        what: String,
        line: usize,
        msg: String,
    },
    Unsupported(String),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Io(e) => write!(f, "waveform: {e}"),
            Error::Parse { what, line, msg } => write!(f, "waveform: {what}:{line}: {msg}"),
            Error::Unsupported(msg) => write!(f, "waveform: unsupported: {msg}"),
        }
    }
}

impl std::error::Error for Error {}

impl From<std::io::Error> for Error {
    fn from(e: std::io::Error) -> Self {
        Error::Io(e)
    }
}

fn parse_err(what: &str, line: usize, msg: impl Into<String>) -> Error {
    Error::Parse {
        what: what.to_owned(),
        line,
        msg: msg.into(),
    }
}

/// One mode at one temperature: a code sequence per (src, dst) pair.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Table {
    seq: Vec<Vec<u8>>,
}

impl Default for Table {
    fn default() -> Self {
        Self {
            seq: vec![Vec::new(); 256],
        }
    }
}

impl Table {
    pub fn get(&self, src: u8, dst: u8) -> &[u8] {
        &self.seq[usize::from(src & 15) * 16 + usize::from(dst & 15)]
    }

    /// Code 3 (reserved/keep) is stored as no drive.
    pub fn set(&mut self, src: u8, dst: u8, codes: &[u8]) {
        self.seq[usize::from(src & 15) * 16 + usize::from(dst & 15)] = codes
            .iter()
            .map(|&c| if c == 3 { NONE } else { c })
            .collect();
    }

    pub fn max_len(&self) -> usize {
        self.seq.iter().map(Vec::len).max().unwrap_or(0)
    }

    /// Net drive frames (white minus black) of one transition.
    pub fn net(&self, src: u8, dst: u8) -> i32 {
        self.get(src, dst)
            .iter()
            .map(|&c| match c {
                WHITE => 1,
                BLACK => -1,
                _ => 0,
            })
            .sum()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Mode {
    pub name: String,
    /// Index into [`Waveform::tables`] per temperature band.
    pub tables: Vec<usize>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Waveform {
    /// Lower bound in °C of each temperature band, ascending.
    pub temps: Vec<i32>,
    pub modes: Vec<Mode>,
    pub tables: Vec<Table>,
}

impl Waveform {
    pub fn mode(&self, name: &str) -> Option<usize> {
        self.modes
            .iter()
            .position(|m| m.name.eq_ignore_ascii_case(name))
    }

    /// A hand-made, illustrative set for tests and the simulator; not a real panel's waveform.
    ///
    /// `BIN` drives straight toward a rail, 12 frames rail to rail, so a black/white round trip
    /// nets zero. `GREY` is GC-like and DC-balanced per transition: overdrive into the source
    /// rail (saturated, so no optical change), cross to the other rail, then come back to the
    /// grey. Both modes have one temperature band.
    pub fn reference() -> Self {
        const RAIL: usize = 12;
        let mut bin = Table::default();
        let mut grey = Table::default();
        for src in 0..16u8 {
            for dst in 0..16u8 {
                if src == dst {
                    continue;
                }
                if dst == 0 || dst == 15 {
                    let n = (RAIL * usize::from(src.abs_diff(dst))).div_ceil(15);
                    bin.set(src, dst, &vec![if dst == 15 { WHITE } else { BLACK }; n]);
                }
                // White frames needed to lift black to `dst`.
                let m = (RAIL * usize::from(dst) + 7) / 15;
                let codes: Vec<u8> = if src >= 8 {
                    [vec![WHITE; RAIL - m], vec![BLACK; RAIL], vec![WHITE; m]].concat()
                } else {
                    [vec![BLACK; m], vec![WHITE; RAIL], vec![BLACK; RAIL - m]].concat()
                };
                grey.set(src, dst, &codes);
            }
        }
        Self {
            temps: vec![0],
            modes: vec![
                Mode {
                    name: "BIN".into(),
                    tables: vec![0],
                },
                Mode {
                    name: "GREY".into(),
                    tables: vec![1],
                },
            ],
            tables: vec![bin, grey],
        }
    }

    /// Glider's Interchangeable Waveform Format: an ini descriptor plus `PREFIX_TBn.csv` tables.
    pub fn load_iwf(path: &Path) -> Result<Self, Error> {
        let text = std::fs::read_to_string(path)?;
        let what = path.display().to_string();
        let dir = path.parent().unwrap_or_else(|| Path::new("."));
        let ini = Ini::parse(&text, &what)?;
        let get = |sec: &str, key: &str| ini.get(sec, key);
        let num = |sec: &str, key: &str| -> Result<usize, Error> {
            get(sec, key)
                .ok_or_else(|| parse_err(&what, 0, format!("missing {key}")))?
                .parse()
                .map_err(|e| parse_err(&what, 0, format!("{key}: {e}")))
        };
        if let Some(bpp) = get("", "BPP") {
            if bpp != "4" {
                return Err(Error::Unsupported(format!(
                    "BPP {bpp}: the engine has 16 levels"
                )));
            }
        }
        let prefix = get("", "PREFIX").ok_or_else(|| parse_err(&what, 0, "missing PREFIX"))?;
        let n_temps = num("", "TEMPS")?;
        let temps = (0..n_temps)
            .map(|t| {
                let key = format!("T{t}RANGE");
                get("", &key)
                    .ok_or_else(|| parse_err(&what, 0, format!("missing {key}")))?
                    .parse()
                    .map_err(|e| parse_err(&what, 0, format!("{key}: {e}")))
            })
            .collect::<Result<Vec<i32>, _>>()?;
        let tables = (0..num("", "TABLES")?)
            .map(|i| {
                let frames = num("", &format!("TB{i}FC"))?;
                let csv = dir.join(format!("{prefix}_TB{i}.csv"));
                load_csv_table(&csv, Some(frames))
            })
            .collect::<Result<Vec<_>, _>>()?;
        let modes = (0..num("", "MODES")?)
            .map(|m| {
                let sec = format!("MODE{m}");
                let name = get(&sec, "NAME").unwrap_or(&sec).to_owned();
                let tables = (0..n_temps)
                    .map(|t| {
                        let idx = num(&sec, &format!("T{t}TABLE"))?;
                        if idx >= tables.len() {
                            return Err(parse_err(
                                &what,
                                0,
                                format!("{sec} T{t}TABLE {idx} out of range"),
                            ));
                        }
                        Ok(idx)
                    })
                    .collect::<Result<Vec<_>, _>>()?;
                Ok(Mode { name, tables })
            })
            .collect::<Result<Vec<_>, Error>>()?;
        Ok(Self {
            temps,
            modes,
            tables,
        })
    }

    /// One mode, one band, from a single IWF-style CSV table.
    pub fn from_csv(path: &Path, name: &str) -> Result<Self, Error> {
        Ok(Self {
            temps: vec![0],
            modes: vec![Mode {
                name: name.to_owned(),
                tables: vec![0],
            }],
            tables: vec![load_csv_table(path, None)?],
        })
    }
}

/// Lines are `src,dst,code,code,...`; `src` and `dst` may be ranges `a:b`.
pub fn parse_csv_table(text: &str, what: &str, frames: Option<usize>) -> Result<Table, Error> {
    let range = |s: &str, line: usize| -> Result<(u8, u8), Error> {
        let bad = |_| parse_err(what, line, format!("bad level {s:?}"));
        let (a, b) = if let Some((a, b)) = s.split_once(':') {
            (
                a.trim().parse().map_err(bad)?,
                b.trim().parse().map_err(bad)?,
            )
        } else {
            let v = s.trim().parse().map_err(bad)?;
            (v, v)
        };
        if a > b || b > 15 {
            return Err(parse_err(what, line, format!("bad level range {s:?}")));
        }
        Ok((a, b))
    };
    let mut table = Table::default();
    for (i, raw) in text.lines().enumerate() {
        let line = i + 1;
        let raw = raw.trim();
        if raw.is_empty() || raw.starts_with('#') {
            continue;
        }
        let mut fields = raw.split(',');
        let (Some(s), Some(d)) = (fields.next(), fields.next()) else {
            return Err(parse_err(what, line, "need src,dst,codes"));
        };
        let (s0, s1) = range(s, line)?;
        let (d0, d1) = range(d, line)?;
        let codes = fields
            .map(|c| match c.trim() {
                "0" => Ok(0),
                "1" => Ok(1),
                "2" => Ok(2),
                "3" => Ok(3),
                other => Err(parse_err(what, line, format!("bad code {other:?}"))),
            })
            .collect::<Result<Vec<u8>, _>>()?;
        if codes.len() > MAX_FRAMES || frames.is_some_and(|f| codes.len() > f) {
            return Err(parse_err(
                what,
                line,
                format!("{} frames is too long", codes.len()),
            ));
        }
        for src in s0..=s1 {
            for dst in d0..=d1 {
                table.set(src, dst, &codes);
            }
        }
    }
    Ok(table)
}

fn load_csv_table(path: &Path, frames: Option<usize>) -> Result<Table, Error> {
    parse_csv_table(
        &std::fs::read_to_string(path)?,
        &path.display().to_string(),
        frames,
    )
}

/// How to read the tables decoded from the v0x25 CPLD bitstream
/// (`mp01-inventory/cpld/re/v25/mode{A,B}_H1.csv`). Which axis is the old level, which plane
/// drives toward white and the time direction are unresolved, so all three are choices.
#[derive(Debug, Clone, Copy)]
pub struct V25Axes {
    pub c_is_src: bool,
    pub p_is_white: bool,
    pub reverse_time: bool,
}

/// One table from a v25 CSV (`c,n,seq,framesP,framesQ`, `seq` of `.PQ` per frame). Trailing
/// no-drive frames are trimmed. A structural template only: it is not the shipped waveform.
pub fn parse_v25(text: &str, what: &str, axes: V25Axes) -> Result<Table, Error> {
    let mut table = Table::default();
    for (i, raw) in text.lines().enumerate().skip(1) {
        let line = i + 1;
        let fields: Vec<&str> = raw.trim().split(',').collect();
        if fields.len() < 3 {
            continue;
        }
        let lvl = |s: &str| -> Result<u8, Error> {
            s.parse()
                .ok()
                .filter(|v| *v < 16)
                .ok_or_else(|| parse_err(what, line, format!("bad level {s:?}")))
        };
        let (c, n) = (lvl(fields[0])?, lvl(fields[1])?);
        let (p, q) = if axes.p_is_white {
            (WHITE, BLACK)
        } else {
            (BLACK, WHITE)
        };
        let mut codes = fields[2]
            .chars()
            .map(|ch| match ch {
                '.' => Ok(NONE),
                'P' => Ok(p),
                'Q' => Ok(q),
                other => Err(parse_err(what, line, format!("bad phase {other:?}"))),
            })
            .collect::<Result<Vec<u8>, _>>()?;
        if axes.reverse_time {
            codes.reverse();
        }
        while codes.last() == Some(&NONE) {
            codes.pop();
        }
        let (src, dst) = if axes.c_is_src { (c, n) } else { (n, c) };
        table.set(src, dst, &codes);
    }
    Ok(table)
}

struct Ini<'a> {
    entries: Vec<(String, String, &'a str)>,
}

impl<'a> Ini<'a> {
    fn parse(text: &'a str, what: &str) -> Result<Self, Error> {
        let mut section = String::new();
        let mut entries = Vec::new();
        for (i, raw) in text.lines().enumerate() {
            let raw = raw.trim();
            if raw.is_empty() || raw.starts_with(';') || raw.starts_with('#') {
                continue;
            }
            if let Some(name) = raw.strip_prefix('[').and_then(|r| r.strip_suffix(']')) {
                section = name.trim().to_ascii_uppercase();
            } else if let Some((k, v)) = raw.split_once('=') {
                entries.push((section.clone(), k.trim().to_ascii_uppercase(), v.trim()));
            } else {
                return Err(parse_err(what, i + 1, "expected key = value"));
            }
        }
        Ok(Self { entries })
    }

    /// `sec == ""` finds the key in any section that is not a `[MODEn]`.
    fn get(&self, sec: &str, key: &str) -> Option<&'a str> {
        self.entries
            .iter()
            .find(|(s, k, _)| {
                k == key
                    && if sec.is_empty() {
                        !s.starts_with("MODE")
                    } else {
                        s.eq_ignore_ascii_case(sec)
                    }
            })
            .map(|e| e.2)
    }
}

/// The engine's flattened tables, shaped for a GPU storage buffer: 16 codes per `u32`
/// (frame `f` in bits `2*(f%16)`), `words` words per (src, dst) pair, 256 pairs per table.
#[derive(Debug, Clone)]
pub struct Lut {
    pub words: usize,
    pub codes: Vec<u32>,
    /// Transition length per table and pair.
    pub lens: Vec<u8>,
}

impl Lut {
    pub fn new(tables: &[&Table]) -> Self {
        let words = tables
            .iter()
            .map(|t| t.max_len())
            .max()
            .unwrap_or(0)
            .div_ceil(16)
            .max(1);
        let mut codes = vec![0u32; tables.len() * 256 * words];
        let mut lens = vec![0u8; tables.len() * 256];
        for (t, table) in tables.iter().enumerate() {
            for pair in 0..256 {
                let seq = &table.seq[pair];
                lens[t * 256 + pair] = u8::try_from(seq.len()).unwrap_or(u8::MAX);
                for (f, &c) in seq.iter().enumerate().take(MAX_FRAMES) {
                    codes[(t * 256 + pair) * words + f / 16] |= u32::from(c) << (2 * (f % 16));
                }
            }
        }
        Self { words, codes, lens }
    }

    #[inline]
    pub fn len(&self, table: u32, src: u32, dst: u32) -> u32 {
        u32::from(self.lens[(table * 256 + src * 16 + dst) as usize])
    }

    #[inline]
    pub fn code(&self, table: u32, src: u32, dst: u32, frame: u32) -> u32 {
        let pair = (table * 256 + src * 16 + dst) as usize;
        (self.codes[pair * self.words + (frame / 16) as usize] >> (2 * (frame % 16))) & 3
    }
}

/// What the engine drives with: the binary (MONO) and grey (refine) modes, per temperature band.
#[derive(Debug, Clone)]
pub struct EngineWaveform {
    pub lut: Lut,
    pub temps: Vec<i32>,
    pub bin: Vec<u32>,
    pub grey: Vec<u32>,
}

impl EngineWaveform {
    pub fn new(wf: &Waveform, bin_mode: usize, grey_mode: usize) -> Self {
        let used: Vec<usize> = wf.modes[bin_mode]
            .tables
            .iter()
            .chain(&wf.modes[grey_mode].tables)
            .copied()
            .collect();
        let tables: Vec<&Table> = used.iter().map(|&i| &wf.tables[i]).collect();
        let n = wf.temps.len();
        let idx = |i: usize| u32::try_from(i).unwrap_or(u32::MAX);
        Self {
            lut: Lut::new(&tables),
            temps: wf.temps.clone(),
            bin: (0..n).map(idx).collect(),
            grey: (n..2 * n).map(idx).collect(),
        }
    }

    pub fn reference() -> Self {
        Self::new(&Waveform::reference(), 0, 1)
    }

    pub fn band(&self, celsius: i32) -> usize {
        self.temps.iter().rposition(|&t| celsius >= t).unwrap_or(0)
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
    fn reference_grey_is_dc_balanced_and_bin_round_trips() {
        let wf = Waveform::reference();
        let (bin, grey) = (&wf.tables[0], &wf.tables[1]);
        for s in 0..16 {
            for d in 0..16 {
                assert_eq!(grey.net(s, d), 0, "grey {s}->{d}");
            }
        }
        assert_eq!(bin.net(0, 15) + bin.net(15, 0), 0);
        assert_eq!(bin.get(0, 15).len(), 12);
    }

    #[test]
    fn csv_ranges_and_codes() {
        let t = parse_csv_table("# c\n4,7,1,1,1,0,2\n0:14,15,2,2,3\n", "t", Some(5))
            .unwrap_or_default();
        assert_eq!(t.get(4, 7), &[1, 1, 1, 0, 2]);
        assert_eq!(t.get(9, 15), &[2, 2, 0]);
        assert!(t.get(15, 15).is_empty());
        assert!(parse_csv_table("1,2,1,1,1,1,1,1\n", "t", Some(5)).is_err());
        assert!(parse_csv_table("1,16,1\n", "t", None).is_err());
    }

    #[test]
    fn iwf_loads_modes_and_bands() {
        let dir = std::env::temp_dir().join(format!("epd-iwf-{}", std::process::id()));
        std::fs::create_dir_all(&dir).ok();
        let iwf = "[WAVEFORM]\nVERSION = 2.0\nPREFIX = W\nMODES = 2\nTEMPS = 2\nT0RANGE = 0\nT1RANGE = 25\n\
                   TABLES = 2\nTB0FC = 3\nTB1FC = 4\n[MODE0]\nNAME = DU\nT0TABLE = 0\nT1TABLE = 0\n\
                   [MODE1]\nNAME = GC16\nT0TABLE = 1\nT1TABLE = 1\n";
        std::fs::write(dir.join("w.iwf"), iwf).ok();
        std::fs::write(dir.join("W_TB0.csv"), "0:15,0,1,1,1\n0:15,15,2,2,2\n").ok();
        std::fs::write(dir.join("W_TB1.csv"), "0:15,0:15,1,2,2,1\n").ok();
        let wf = Waveform::load_iwf(&dir.join("w.iwf"));
        std::fs::remove_dir_all(&dir).ok();
        let wf = wf.unwrap_or_else(|e| panic!("{e}"));
        assert_eq!(wf.temps, vec![0, 25]);
        assert_eq!(wf.mode("gc16"), Some(1));
        assert_eq!(wf.tables[0].get(3, 15), &[2, 2, 2]);
        let ew = EngineWaveform::new(&wf, 0, 1);
        assert_eq!(ew.band(30), 1);
        assert_eq!(ew.band(-5), 0);
        assert_eq!(ew.lut.code(ew.grey[1], 2, 9, 1), 2);
        assert_eq!(ew.lut.len(ew.bin[0], 7, 0), 3);
    }

    #[test]
    fn v25_tables_parse_when_present() {
        let dir = std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default())
            .join("q25-build/mp01-inventory/cpld/re/v25");
        let axes = V25Axes {
            c_is_src: true,
            p_is_white: false,
            reverse_time: false,
        };
        for (file, max) in [("modeA_H1.csv", 32), ("modeB_H1.csv", 12)] {
            let Ok(text) = std::fs::read_to_string(dir.join(file)) else {
                return;
            };
            let t = parse_v25(&text, file, axes).unwrap_or_else(|e| panic!("{e}"));
            assert!(
                t.max_len() <= max && t.max_len() > 0,
                "{file}: {}",
                t.max_len()
            );
        }
    }

    #[test]
    fn lut_packs_sixteen_codes_per_word() {
        let mut t = Table::default();
        let codes: Vec<u8> = (0..40).map(|i| [0, 1, 2][i % 3]).collect();
        t.set(3, 12, &codes);
        let lut = Lut::new(&[&t]);
        assert_eq!(lut.words, 3);
        for (f, &c) in codes.iter().enumerate() {
            assert_eq!(lut.code(0, 3, 12, f as u32), u32::from(c));
        }
        assert_eq!(lut.len(0, 3, 12), 40);
    }
}
