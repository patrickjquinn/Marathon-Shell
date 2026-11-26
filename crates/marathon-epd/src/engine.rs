//! The per-pixel waveform engine (CPU reference). `gpu.rs` runs the same machine in a GLES
//! compute shader and must stay bit-exact with [`step`].
//!
//! Every pixel runs its own transition, Caster style:
//!
//! - **MONO**: a changed pixel starts at once, driving to a rail with the binary table.
//! - **HOLD**: a rail is shown while the pixel's grey is owed (an idle pixel whose level differs
//!   from its grey target). It waits until its target has been still for `quiet_frames` and the
//!   compositor allows greys (no finger down, no fling). Disallowing greys never reverts a grey
//!   that is already shown.
//! - **GREY**: the grey table drives from the rail to the grey.
//!
//! A pixel whose target changes in flight is turned around by *rewinding*: the frames already
//! applied are replayed inverted, newest first, until the pixel is back at its start. Rewinding
//! nets exactly zero drive, so cancels never unbalance DC, whatever the table. Turning around
//! again resumes forward from where the rewind stands. A grey transition rewinds only within
//! `grey_rewind_max` frames of its start; past that it finishes and the new target follows.
//!
//! Binary transitions from a grey level are not DC-balanced in any real waveform set (A2/DU
//! from grey), so each pixel also keeps its net drive. Its *excess* over the balanced value for
//! its rail (0 at black, the binary table's black-to-white net at white) is repaid while the
//! pixel rests at a rail where repaying is invisible: extra white frames at white for a black
//! excess, extra black frames at black for a white excess. The other sign waits for the next
//! rail.
//!
//! Target byte per pixel: bits 3:0 grey level, bit 4 binary stand-in (the target pass's
//! dithered/thresholded bit), bits 6:5 region class.

use crate::waveform::{EngineWaveform, Lut};

/// Hybrid: binary while the target moves, grey once quiet.
pub const CLASS_AUTO: u32 = 0;
/// Binary only (text input, video).
pub const CLASS_MONO: u32 = 1;
/// Grey without waiting for quiet (page change), via the nearest rail.
pub const CLASS_GREY: u32 = 2;
/// Frozen: no new transitions start; ones in flight finish.
pub const CLASS_FREEZE: u32 = 3;

pub const STAGE_DONE: u32 = 0;
pub const STAGE_MONO: u32 = 1;
pub const STAGE_GREY: u32 = 2;

pub const QUIET_MAX: u32 = 15;

/// Packed pixel state: lvl 3:0 (level shown, or a transition's start), tgt 7:4 (its end),
/// frame 15:8 (frames applied), stage 17:16, rev 18 (rewinding), last 22:19 (last grey target
/// seen), quiet 26:23 (frames since that target changed, saturating).
pub fn pack(lvl: u32, tgt: u32, frame: u32, stage: u32, rev: u32, last: u32, quiet: u32) -> u32 {
    lvl | tgt << 4 | frame << 8 | stage << 16 | rev << 18 | last << 19 | quiet << 23
}

/// A settled pixel showing `level`, with that level as its last target.
pub fn idle_state(level: u32) -> u32 {
    pack(level, level, 0, STAGE_DONE, 0, level, QUIET_MAX)
}

pub fn level(st: u32) -> u32 {
    st & 15
}

pub fn stage(st: u32) -> u32 {
    (st >> 16) & 3
}

#[allow(clippy::cast_possible_truncation, reason = "masked to 7 bits")]
pub fn target(grey: u32, stand: bool, class: u32) -> u8 {
    ((grey & 15) | u32::from(stand) << 4 | (class & 3) << 5) as u8
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Params {
    pub allow_grey: bool,
    pub quiet_frames: u32,
    /// Added to every pixel's quiet count this tick: the frames the loop slept through.
    pub quiet_bonus: u32,
    pub grey_rewind_max: u32,
    pub bin_table: u32,
    pub grey_table: u32,
    /// Net drive of the binary black-to-white transition: the balanced DC value at white.
    pub white_dc: i32,
    pub repay: bool,
}

impl Params {
    pub fn new(wf: &EngineWaveform, band: usize) -> Self {
        Self {
            allow_grey: true,
            quiet_frames: 13,
            quiet_bonus: 0,
            grey_rewind_max: 12,
            bin_table: wf.bin[band],
            grey_table: wf.grey[band],
            white_dc: (0..wf.lut.len(wf.bin[band], 0, 15))
                .map(|f| [0, -1, 1, 0][wf.lut.code(wf.bin[band], 0, 15, f) as usize])
                .sum(),
            repay: true,
        }
    }

    /// The balanced DC value of a settled pixel at `level`.
    pub fn rest_dc(&self, level: u32) -> Dc {
        if level == 15 {
            Dc::try_from(self.white_dc).unwrap_or(Dc::MAX)
        } else {
            0
        }
    }
}

#[inline]
fn is_rail(l: u32) -> bool {
    l == 0 || l == 15
}

#[inline]
fn rail(l: u32) -> u32 {
    if l >= 8 {
        15
    } else {
        0
    }
}

#[inline]
fn invert(code: u32) -> u32 {
    match code {
        1 => 2,
        2 => 1,
        _ => 0,
    }
}

/// One frame of one pixel: returns the new state and the drive code (0 none, 1 black, 2 white).
/// The caller adds the code to the pixel's net drive `dc`.
#[inline]
pub fn step(st: u32, dc: i32, tg: u32, p: &Params, lut: &Lut) -> (u32, u32) {
    let mut lvl = st & 15;
    let mut tgt = (st >> 4) & 15;
    let mut frame = (st >> 8) & 255;
    let mut stage = (st >> 16) & 3;
    let mut rev = (st >> 18) & 1;
    let mut last = (st >> 19) & 15;
    let mut quiet = (st >> 23) & 15;

    let grey = tg & 15;
    let stand = if tg & 16 != 0 { 15 } else { 0 };
    let class = (tg >> 5) & 3;

    if grey == last {
        quiet = (quiet + 1 + p.quiet_bonus).min(QUIET_MAX);
    } else {
        last = grey;
        quiet = 0;
    }
    let frozen = class == CLASS_FREEZE;
    // Disallowing greys stops new grey transitions; it does not undo greys already shown.
    let showing =
        (stage == STAGE_DONE && lvl == grey) || (stage == STAGE_GREY && rev == 0 && tgt == grey);
    let grey_ok = p.allow_grey || showing;
    let want = match class {
        CLASS_AUTO if quiet >= p.quiet_frames && grey_ok => grey,
        CLASS_GREY if grey_ok => grey,
        _ => stand,
    };

    if !frozen {
        let heading = if rev == 1 { lvl } else { tgt };
        if stage == STAGE_MONO {
            let goal = if is_rail(want) { want } else { rail(want) };
            if goal != heading {
                if rev == 0 {
                    rev = 1;
                } else if goal == tgt {
                    rev = 0;
                }
            }
        } else if stage == STAGE_GREY && want != heading {
            if rev == 0 {
                if frame <= p.grey_rewind_max {
                    rev = 1;
                }
            } else if want == tgt {
                rev = 0;
            }
        } else if stage == STAGE_DONE && want != lvl {
            stage = if is_rail(want) || !is_rail(lvl) {
                STAGE_MONO
            } else {
                STAGE_GREY
            };
            tgt = if is_rail(want) || is_rail(lvl) {
                want
            } else {
                rail(want)
            };
            frame = 0;
            rev = 0;
        }
    }

    let mut code = 0;
    if stage != STAGE_DONE {
        let table = if stage == STAGE_MONO {
            p.bin_table
        } else {
            p.grey_table
        };
        if rev == 0 {
            let len = lut.len(table, lvl, tgt);
            if frame < len {
                code = lut.code(table, lvl, tgt, frame);
                frame += 1;
            }
            if frame >= len {
                stage = STAGE_DONE;
                lvl = tgt;
                frame = 0;
            }
        } else {
            if frame > 0 {
                frame -= 1;
                code = invert(lut.code(table, lvl, tgt, frame));
            }
            if frame == 0 {
                stage = STAGE_DONE;
                tgt = lvl;
                rev = 0;
            }
        }
    } else if p.repay && !frozen && want == lvl {
        if lvl == 15 && dc < p.white_dc {
            code = 2;
        } else if lvl == 0 && dc > 0 {
            code = 1;
        }
    }
    (pack(lvl, tgt, frame, stage, rev, last, quiet), code)
}

/// Per-tick totals, merged across rows.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Stats {
    /// Pixels in a MONO or GREY transition after this tick, or repaying DC this tick.
    pub active: u32,
    /// Idle pixels whose level is not their grey target (HOLD).
    pub pending: u32,
    /// Pixels driven (code != 0) this tick.
    pub driven: u32,
    /// First and last row driven this tick; `row_min > row_max` when nothing was.
    pub row_min: u32,
    pub row_max: u32,
}

impl Default for Stats {
    fn default() -> Self {
        Self {
            active: 0,
            pending: 0,
            driven: 0,
            row_min: u32::MAX,
            row_max: 0,
        }
    }
}

impl Stats {
    fn merge(&mut self, o: &Stats) {
        self.active += o.active;
        self.pending += o.pending;
        self.driven += o.driven;
        self.row_min = self.row_min.min(o.row_min);
        self.row_max = self.row_max.max(o.row_max);
    }

    /// Nothing can change without new input.
    pub fn idle(&self, allow_grey: bool) -> bool {
        self.active == 0 && (self.pending == 0 || !allow_grey)
    }
}

/// Signed net drive per pixel (white minus black frames), saturating. Telemetry for DC balance.
pub type Dc = i8;

/// Drive output: 2 bits per pixel, four pixels per byte, the leftmost in bits 7:6, rows of
/// `width / 4` bytes. `link.rs` sends each row as is, one per DSI line.
pub fn drive_len(width: usize, height: usize) -> usize {
    width / 4 * height
}

/// A settled pixel that this tick cannot change: [`step`] would return it unchanged with no drive.
/// Most of a panel is in this state, so the CPU skips the full step for it.
#[inline]
fn steady(st: u32, dc: i32, tg: u32, p: &Params) -> bool {
    let g = tg & 15;
    let class = (tg >> 5) & 3;
    st == pack(g, g, 0, STAGE_DONE, 0, g, QUIET_MAX)
        && p.quiet_frames <= QUIET_MAX
        && (class != CLASS_MONO || g == if tg & 16 != 0 { 15 } else { 0 })
        && (!p.repay || !((g == 15 && dc < p.white_dc) || (g == 0 && dc > 0)))
}

#[allow(
    clippy::too_many_arguments,
    reason = "one band of each of the panel's planes"
)]
fn tick_rows(
    rows: std::ops::Range<usize>,
    width: usize,
    state: &mut [u32],
    dc: &mut [Dc],
    target: &[u8],
    drive: &mut [u8],
    p: &Params,
    lut: &Lut,
) -> Stats {
    let mut s = Stats::default();
    for (r, y) in rows.enumerate() {
        let base = r * width;
        let mut row_driven = 0;
        for (bx, out) in drive[r * width / 4..(r + 1) * width / 4]
            .iter_mut()
            .enumerate()
        {
            let mut byte = 0u32;
            for i in 0..4 {
                let x = base + bx * 4 + i;
                let tg = u32::from(target[x]);
                if steady(state[x], i32::from(dc[x]), tg, p) {
                    continue;
                }
                let (st, code) = step(state[x], i32::from(dc[x]), tg, p, lut);
                state[x] = st;
                byte |= code << (6 - 2 * i);
                if code != 0 {
                    dc[x] = dc[x].saturating_add(if code == 2 { 1 } else { -1 });
                }
                let stg = stage(st);
                s.active += u32::from(stg != STAGE_DONE || code != 0);
                let class = (tg >> 5) & 3;
                s.pending += u32::from(
                    stg == STAGE_DONE
                        && (class == CLASS_AUTO || class == CLASS_GREY)
                        && level(st) != (tg & 15),
                );
            }
            row_driven += (byte & 0x55 | (byte >> 1) & 0x55).count_ones();
            *out = u8::try_from(byte).unwrap_or(0);
        }
        if row_driven != 0 {
            s.driven += row_driven;
            let y = u32::try_from(y).unwrap_or(u32::MAX);
            s.row_min = s.row_min.min(y);
            s.row_max = s.row_max.max(y);
        }
    }
    s
}

/// The CPU engine: row bands in parallel on scoped threads.
pub struct CpuEngine {
    pub width: usize,
    pub height: usize,
    pub state: Vec<u32>,
    pub dc: Vec<Dc>,
    pub threads: usize,
}

impl CpuEngine {
    /// A panel showing `level` everywhere, settled.
    ///
    /// # Panics
    /// If `width` is not a multiple of 16.
    pub fn new(width: usize, height: usize, level: u32, p: &Params) -> Self {
        assert!(
            width.is_multiple_of(16),
            "width {width} is not a multiple of 16"
        );
        Self {
            width,
            height,
            state: vec![idle_state(level); width * height],
            dc: vec![p.rest_dc(level); width * height],
            threads: std::thread::available_parallelism()
                .map_or(1, std::num::NonZero::get)
                .min(4),
        }
    }

    /// # Panics
    /// If `target` or `drive` does not match the panel size, or a worker thread panicked.
    pub fn tick(&mut self, target: &[u8], p: &Params, lut: &Lut, drive: &mut [u8]) -> Stats {
        let (w, h) = (self.width, self.height);
        assert_eq!(target.len(), w * h);
        assert_eq!(drive.len(), drive_len(w, h));
        let band = h.div_ceil(self.threads.max(1));
        if self.threads <= 1 {
            return tick_rows(
                0..h,
                w,
                &mut self.state,
                &mut self.dc,
                target,
                drive,
                p,
                lut,
            );
        }
        let mut total = Stats::default();
        std::thread::scope(|sc| {
            let jobs: Vec<_> = self
                .state
                .chunks_mut(band * w)
                .zip(self.dc.chunks_mut(band * w))
                .zip(target.chunks(band * w))
                .zip(drive.chunks_mut(band * w / 4))
                .enumerate()
                .map(|(i, (((st, dc), tg), dr))| {
                    let rows = i * band..(i * band + st.len() / w);
                    sc.spawn(move || tick_rows(rows, w, st, dc, tg, dr, p, lut))
                })
                .collect();
            for j in jobs {
                match j.join() {
                    Ok(s) => total.merge(&s),
                    Err(e) => std::panic::resume_unwind(e),
                }
            }
        });
        total
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
    use crate::waveform::{EngineWaveform, Table, Waveform};

    fn one(st: &mut u32, tg: u8, p: &Params, lut: &Lut) -> u32 {
        let dc = if level(*st) == 15 { p.white_dc } else { 0 };
        let (s, c) = step(*st, dc, u32::from(tg), p, lut);
        *st = s;
        c
    }

    fn net(codes: &[u32]) -> i32 {
        codes.iter().map(|&c| [0, -1, 1, 0][c as usize]).sum()
    }

    #[test]
    fn binary_change_starts_at_once_and_settles() {
        let wf = EngineWaveform::reference();
        let p = Params::new(&wf, 0);
        let mut st = idle_state(0);
        let w = target(15, true, CLASS_MONO);
        let codes: Vec<u32> = (0..12).map(|_| one(&mut st, w, &p, &wf.lut)).collect();
        assert_eq!(codes, vec![2; 12]);
        assert_eq!((level(st), stage(st)), (15, STAGE_DONE));
        assert_eq!(one(&mut st, w, &p, &wf.lut), 0);
    }

    #[test]
    fn early_cancel_rewinds_exactly() {
        let wf = EngineWaveform::reference();
        let p = Params::new(&wf, 0);
        let mut st = idle_state(0);
        let (white, black) = (target(15, true, CLASS_MONO), target(0, false, CLASS_MONO));
        let mut codes: Vec<u32> = (0..5).map(|_| one(&mut st, white, &p, &wf.lut)).collect();
        // The target flips back: reversal starts on the very next frame.
        let back: Vec<u32> = (0..5).map(|_| one(&mut st, black, &p, &wf.lut)).collect();
        assert_eq!(back, vec![1; 5]);
        codes.extend(&back);
        assert_eq!(net(&codes), 0);
        assert_eq!((level(st), stage(st)), (0, STAGE_DONE));
        // Turn around twice mid-rewind: resumes forward from where the rewind stands.
        let mut st = idle_state(0);
        let seq = [white, white, white, black, white, white];
        let c: Vec<u32> = seq.iter().map(|&t| one(&mut st, t, &p, &wf.lut)).collect();
        assert_eq!(c, vec![2, 2, 2, 1, 2, 2]);
        assert_eq!((st >> 8) & 255, 4);
    }

    #[test]
    fn hybrid_mono_hold_grey() {
        let wf = EngineWaveform::reference();
        let mut p = Params::new(&wf, 0);
        p.quiet_frames = 15;
        let mut st = idle_state(15);
        // Content goes to grey 5; its binary stand-in is black.
        let tg = target(5, false, CLASS_AUTO);
        let mut stages = Vec::new();
        let mut codes = Vec::new();
        for _ in 0..60 {
            codes.push(one(&mut st, tg, &p, &wf.lut));
            stages.push(stage(st));
        }
        // 12 frames of MONO to black, HOLD until the target has been still for 15 frames, then
        // 24 frames of GREY.
        assert_eq!(&codes[..12], &[1; 12]);
        assert!(stages[11..15].iter().all(|&s| s == STAGE_DONE));
        assert_eq!(&codes[12..15], &[0; 3]);
        let grey_start = stages.iter().position(|&s| s == STAGE_GREY).unwrap_or(99);
        assert_eq!(grey_start, 15);
        assert_eq!(level(st), 5);
        // With greys disallowed (finger down), the pixel holds at the rail.
        let mut st = idle_state(15);
        p.allow_grey = false;
        for _ in 0..60 {
            one(&mut st, tg, &p, &wf.lut);
        }
        assert_eq!((level(st), stage(st)), (0, STAGE_DONE));
    }

    #[test]
    fn grey_cancel_rewinds_only_early() {
        let wf = EngineWaveform::reference();
        let mut p = Params::new(&wf, 0);
        p.grey_rewind_max = 5;
        let to7 = target(7, false, CLASS_GREY);
        let to0 = target(0, false, CLASS_GREY);
        let mut st = idle_state(15);
        let mut c: Vec<u32> = (0..3).map(|_| one(&mut st, to7, &p, &wf.lut)).collect();
        c.extend((0..3).map(|_| one(&mut st, to0, &p, &wf.lut)));
        assert_eq!(net(&c), 0);
        assert_eq!((level(st), stage(st)), (15, STAGE_DONE));
        // Past the limit the grey finishes before the new target is taken.
        let mut st = idle_state(15);
        for _ in 0..10 {
            one(&mut st, to7, &p, &wf.lut);
        }
        for _ in 0..14 {
            one(&mut st, to0, &p, &wf.lut);
        }
        assert_eq!(level(st), 7);
    }

    #[test]
    fn dc_stays_balanced_over_long_random_sequences() {
        // Binary content with frequent mid-flight flips: the net drive of every pixel is a
        // function of its level alone (0 at black, +12 at white), however many cancels happened.
        let wf = EngineWaveform::reference();
        let p = Params::new(&wf, 0);
        let mut e = CpuEngine::new(64, 16, 0, &p);
        let mut rng = Rng(0x1234_5678);
        let mut tg: Vec<u8> = vec![target(0, false, CLASS_MONO); 64 * 16];
        let mut drive = vec![0; drive_len(64, 16)];
        let mut wide = vec![0i32; 64 * 16];
        for _ in 0..20_000 {
            for t in &mut tg {
                if rng.next().is_multiple_of(9) {
                    let w = *t & 16 == 0;
                    *t = target(if w { 15 } else { 0 }, w, CLASS_MONO);
                }
            }
            e.tick(&tg, &p, &wf.lut, &mut drive);
            for (i, d) in wide.iter_mut().enumerate() {
                *d += [0, -1, 1, 0][((drive[i / 4] >> (6 - 2 * (i % 4))) & 3) as usize];
            }
        }
        for _ in 0..30 {
            e.tick(&tg, &p, &wf.lut, &mut drive);
            for (i, d) in wide.iter_mut().enumerate() {
                *d += [0, -1, 1, 0][((drive[i / 4] >> (6 - 2 * (i % 4))) & 3) as usize];
            }
        }
        for (i, &st) in e.state.iter().enumerate() {
            assert_eq!(stage(st), STAGE_DONE);
            assert_eq!(wide[i], if level(st) == 15 { 12 } else { 0 }, "pixel {i}");
            assert_eq!(i32::from(e.dc[i]), wide[i]);
        }
    }

    /// Worst |net drive| over a run of random grey and binary content with frequent changes.
    fn grey_chaos_worst_dc(repay: bool) -> u8 {
        let wf = EngineWaveform::reference();
        let mut p = Params::new(&wf, 0);
        p.quiet_frames = 3;
        p.repay = repay;
        let mut e = CpuEngine::new(32, 8, 15, &p);
        e.threads = 1;
        let mut rng = Rng(42);
        let mut tg = vec![target(15, true, CLASS_AUTO); 32 * 8];
        let mut drive = vec![0; drive_len(32, 8)];
        let mut worst = 0;
        for i in 0..15_000 {
            if i % 40 < 8 {
                for t in &mut tg {
                    if rng.next().is_multiple_of(5) {
                        let g = rng.next() % 16;
                        *t = target(g, g >= 8, CLASS_AUTO);
                    }
                }
            }
            p.allow_grey = i % 300 > 100;
            e.tick(&tg, &p, &wf.lut, &mut drive);
            worst = worst.max(e.dc.iter().map(|d| d.unsigned_abs()).max().unwrap_or(0));
        }
        worst
    }

    #[test]
    fn grey_source_binary_leak_is_repaid() {
        // Binary transitions out of a grey are not balanced, so without repayment the net drive
        // of busy pixels runs to the counter's limit; with it, it stays bounded.
        assert_eq!(grey_chaos_worst_dc(false), 128);
        let worst = grey_chaos_worst_dc(true);
        assert!(worst <= 80, "worst {worst}");
    }

    #[test]
    fn stats_report_rows_pending_and_idle() {
        let wf = EngineWaveform::reference();
        let mut p = Params::new(&wf, 0);
        let mut e = CpuEngine::new(32, 8, 15, &p);
        e.threads = 3;
        let mut tg = vec![target(15, true, CLASS_AUTO); 32 * 8];
        tg[3 * 32 + 5] = target(6, false, CLASS_AUTO);
        tg[5 * 32 + 9] = target(0, false, CLASS_AUTO);
        let mut drive = vec![0; drive_len(32, 8)];
        let s = e.tick(&tg, &p, &wf.lut, &mut drive);
        assert_eq!((s.active, s.driven, s.row_min, s.row_max), (2, 2, 3, 5));
        assert_eq!(drive[3 * 8 + 1], 0b0001_0000);
        let mut ticks = 1;
        loop {
            let s = e.tick(&tg, &p, &wf.lut, &mut drive);
            ticks += 1;
            if s.idle(p.allow_grey) {
                break;
            }
            assert!(ticks < 100);
        }
        assert_eq!(level(e.state[3 * 32 + 5]), 6);
        p.allow_grey = false;
        tg[0] = target(9, true, CLASS_AUTO);
        let s = e.tick(&tg, &p, &wf.lut, &mut drive);
        assert_eq!((s.active, s.pending), (0, 1));
        assert!(s.idle(false));
    }

    #[test]
    fn freeze_starts_nothing() {
        let wf = EngineWaveform::reference();
        let p = Params::new(&wf, 0);
        let mut st = idle_state(0);
        assert_eq!(one(&mut st, target(15, true, CLASS_FREEZE), &p, &wf.lut), 0);
        assert_eq!(st, pack(0, 0, 0, STAGE_DONE, 0, 15, 0));
    }

    #[test]
    fn handles_unbalanced_tables() {
        // A table with gaps and no entry for some pairs still terminates.
        let mut t = Table::default();
        t.set(0, 15, &[0, 2, 0, 2]);
        let wf = Waveform {
            temps: vec![0],
            modes: vec![],
            tables: vec![t.clone(), t],
        };
        let ew = EngineWaveform::new(
            &Waveform {
                modes: vec![
                    crate::waveform::Mode {
                        name: "B".into(),
                        tables: vec![0],
                    },
                    crate::waveform::Mode {
                        name: "G".into(),
                        tables: vec![1],
                    },
                ],
                ..wf
            },
            0,
            1,
        );
        let p = Params::new(&ew, 0);
        let mut st = idle_state(15);
        let c = one(&mut st, target(0, false, CLASS_MONO), &p, &ew.lut);
        assert_eq!((c, level(st), stage(st)), (0, 0, STAGE_DONE));
    }

    pub(crate) struct Rng(pub u64);
    impl Rng {
        pub fn next(&mut self) -> u32 {
            self.0 ^= self.0 << 13;
            self.0 ^= self.0 >> 7;
            self.0 ^= self.0 << 17;
            (self.0 >> 32) as u32
        }
    }
}
