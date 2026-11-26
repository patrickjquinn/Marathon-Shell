//! When the TCON loop runs: the LTPO-like idle and ramp.
//!
//! The loop ticks at the panel rate only while some pixel is in transition (or owes a grey it
//! may now start). Once the engine reports idle and nothing new arrived, one drain frame goes
//! out and the loop stops: no ticks, no frames. After `hold_off` frames without input the link
//! goes off too (CRTC inactive, bridge kept powered). Input wakes everything at once, before the
//! first changed frame exists; damage restarts the loop on the next vblank. Time is counted in
//! panel frames so the policy is testable without a clock.

use crate::engine::Stats;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    /// Run the engine and commit its frame. `quiet_bonus` is the number of frames slept since
    /// the loop last ran, for the engine's quiet counters.
    Tick { quiet_bonus: u32 },
    /// Commit one frame that drives nothing and lets the bridge drop the panel rails, then stop.
    Drain,
    /// Nothing to do this vblank (the caller should not even be waiting for vblanks).
    Sleep,
    /// Turn the link off now.
    LinkOff,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum State {
    Running,
    Draining,
    Stopped { at: u64 },
    LinkOff { at: u64 },
}

#[derive(Debug)]
pub struct Scheduler {
    state: State,
    dirty: bool,
    slept: u64,
    pub hold_off: u64,
}

impl Scheduler {
    pub fn new(hold_off: u64) -> Self {
        Self {
            state: State::LinkOff { at: 0 },
            dirty: false,
            slept: 0,
            hold_off,
        }
    }

    pub fn running(&self) -> bool {
        matches!(self.state, State::Running | State::Draining)
    }

    /// New target content (or a change of `allow_grey`). Returns true if the link must be turned
    /// on first.
    pub fn damage(&mut self, now: u64) -> bool {
        self.dirty = true;
        self.wake(now)
    }

    /// Touch-down or key-down: wake before any content changes. Returns true if the link must
    /// be turned on, which the input thread does at once.
    pub fn input(&mut self, now: u64) -> bool {
        self.wake(now)
    }

    fn wake(&mut self, now: u64) -> bool {
        let link_was_off = matches!(self.state, State::LinkOff { .. });
        self.state = match self.state {
            State::Stopped { at } | State::LinkOff { at } => {
                self.slept = now.saturating_sub(at);
                State::Running
            }
            _ => State::Running,
        };
        link_was_off
    }

    pub fn vblank(&mut self, now: u64) -> Action {
        match self.state {
            State::Running => {
                self.dirty = false;
                Action::Tick {
                    quiet_bonus: u32::try_from(std::mem::take(&mut self.slept)).unwrap_or(u32::MAX),
                }
            }
            State::Draining => {
                self.state = State::Stopped { at: now };
                Action::Drain
            }
            State::Stopped { at } if now.saturating_sub(at) >= self.hold_off => {
                self.state = State::LinkOff { at };
                Action::LinkOff
            }
            State::Stopped { .. } | State::LinkOff { .. } => Action::Sleep,
        }
    }

    /// After each tick: stop when the engine is idle and no damage arrived meanwhile.
    pub fn ticked(&mut self, stats: &Stats, allow_grey: bool) {
        if self.state == State::Running && !self.dirty && stats.idle(allow_grey) {
            self.state = State::Draining;
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
    use crate::engine::{drive_len, target, CpuEngine, Params, CLASS_AUTO};
    use crate::waveform::EngineWaveform;

    /// Runs `frames` vblanks; `events(frame)` may damage the target. Returns the frames on which
    /// something was committed (ticks and drains) and the link-off frames.
    fn timeline(
        frames: u64,
        mut events: impl FnMut(u64, &mut Vec<u8>, &mut Scheduler),
    ) -> (Vec<u64>, Vec<u64>) {
        let wf = EngineWaveform::reference();
        let p = Params::new(&wf, 0);
        let mut e = CpuEngine::new(32, 4, 15, &p);
        let mut tg = vec![target(15, true, CLASS_AUTO); 32 * 4];
        let mut drive = vec![0; drive_len(32, 4)];
        let mut s = Scheduler::new(170);
        let (mut commits, mut offs) = (Vec::new(), Vec::new());
        for now in 0..frames {
            events(now, &mut tg, &mut s);
            match s.vblank(now) {
                Action::Tick { quiet_bonus } => {
                    let st = e.tick(&tg, &Params { quiet_bonus, ..p }, &wf.lut, &mut drive);
                    s.ticked(&st, p.allow_grey);
                    commits.push(now);
                }
                Action::Drain => commits.push(now),
                Action::LinkOff => offs.push(now),
                Action::Sleep => {}
            }
        }
        (commits, offs)
    }

    #[test]
    fn idle_panel_sends_nothing() {
        let (commits, offs) = timeline(1000, |_, _, _| {});
        assert!(commits.is_empty() && offs.is_empty());
    }

    #[test]
    fn stops_after_the_transition_and_wakes_on_damage() {
        let (commits, offs) = timeline(1000, |now, tg, s| {
            if now == 10 || now == 600 {
                tg[5] = target(if now == 10 { 0 } else { 15 }, now != 10, CLASS_AUTO);
                assert_eq!(s.damage(now), now == 10 || now == 600);
            }
        });
        // Damage at 10: ticks start on that vblank, 12 binary frames, one idle tick, one drain.
        assert_eq!(commits.first(), Some(&10));
        assert_eq!(commits.iter().filter(|&&f| f < 600).count(), 14);
        assert_eq!(offs, vec![23 + 170, 613 + 170]);
        // Nothing between the drain and the next damage.
        assert!(commits.iter().all(|&f| f <= 23 || f >= 600));
        assert_eq!(commits.iter().filter(|&&f| f >= 600).count(), 14);
    }

    #[test]
    fn input_wakes_the_link_before_content() {
        let mut s = Scheduler::new(170);
        assert!(s.input(5), "link was off: the input thread turns it on now");
        assert!(s.running());
        assert!(matches!(s.vblank(6), Action::Tick { quiet_bonus: 5 }));
        assert!(!s.damage(7), "already up");
    }
}
