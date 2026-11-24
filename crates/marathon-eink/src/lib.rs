//! The e-paper waveform policy. A bistable panel holds its picture at no
//! cost, so the ladder is waveforms, not refresh rates: `fast` the moment a
//! finger lands or content moves, `text` while typing, the resting waveform
//! once the screen is still, and a flashing clear only when asked for or
//! when the screen has stayed still after enough drawing in `fast`.
//! `clean` is never chosen: entering it flashes.
//!
//! Pure: the shell feeds it input and frames with their times, applies the
//! actions `poll` returns and calls `poll` again by `deadline`.
//! `docs/design/EINK_MODE.md` has the reasoning.

use std::collections::VecDeque;
use std::time::{Duration, Instant};

/// The panel's waveforms, named by behaviour (the interim sysfs ABI's names).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Waveform {
    /// Full grey, slowest, cleanest.
    Quality,
    /// Grey with less ghosting; entering it flashes twice.
    Clean,
    /// Nearly two-level: crisp text.
    Text,
    /// Two-level, fastest, ghosts.
    Fast,
}

impl Waveform {
    pub const fn name(self) -> &'static str {
        match self {
            Self::Quality => "quality",
            Self::Clean => "clean",
            Self::Text => "text",
            Self::Fast => "fast",
        }
    }

    pub fn parse(name: &str) -> Option<Self> {
        match name.trim() {
            "quality" => Some(Self::Quality),
            "clean" => Some(Self::Clean),
            "text" => Some(Self::Text),
            "fast" => Some(Self::Fast),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Input {
    /// A finger or button went down, in device pixels.
    Press {
        x: f32,
        y: f32,
    },
    Move {
        x: f32,
        y: f32,
    },
    Release,
    /// A wheel or trackpad scroll.
    Scroll,
    /// A key was typed, on the hardware keyboard or the on-screen one.
    Key,
    /// The compositor presented a frame.
    Frame,
    /// The user asked for a clear: the refresh key, tile or button.
    Clear,
    /// Most of the screen changed at once: an app switch, unlock or Home.
    Replaced,
    Screen {
        on: bool,
    },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Action {
    Waveform(Waveform),
    /// The panel's full flashing refresh.
    Clear,
}

#[derive(Clone, Copy, Debug)]
pub struct Tuning {
    /// How far a press travels before it is a drag, in device pixels.
    pub slop: f32,
    /// The least time between two waveform writes (stock's rule).
    pub min_switch: Duration,
    /// How long `fast` outlasts the last movement.
    pub settle: Duration,
    /// How long `text` outlasts the last key.
    pub typing: Duration,
    /// This many frames inside `motion_window` without input is motion
    /// (video, an app animating, keyboard scrolling).
    pub motion_frames: usize,
    pub motion_window: Duration,
    /// Frames drawn in `fast` before the still screen is cleared.
    pub clear_budget: u32,
    /// What a whole-screen change adds to that count.
    pub replaced_cost: u32,
    /// How long the screen stays still before an automatic clear.
    pub clear_still: Duration,
    /// The least time between automatic clears.
    pub clear_spacing: Duration,
    /// Clears asked for closer together than this are one clear.
    pub clear_coalesce: Duration,
}

impl Default for Tuning {
    fn default() -> Self {
        Self {
            slop: 12.0,
            min_switch: Duration::from_millis(200),
            settle: Duration::from_millis(350),
            typing: Duration::from_millis(1500),
            motion_frames: 4,
            motion_window: Duration::from_millis(300),
            clear_budget: 60,
            replaced_cost: 30,
            clear_still: Duration::from_millis(1500),
            clear_spacing: Duration::from_secs(20),
            clear_coalesce: Duration::from_millis(500),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum Touch {
    Up,
    /// Down at this point, not yet past the slop.
    Down(f32, f32),
    Dragging,
}

#[derive(Debug)]
pub struct Policy {
    tuning: Tuning,
    resting: Waveform,
    auto_clear: bool,
    /// What the panel was last told; nothing before the first poll.
    applied: Option<Waveform>,
    switched_at: Option<Instant>,
    touch: Touch,
    moved_at: Option<Instant>,
    typed_at: Option<Instant>,
    frames: VecDeque<Instant>,
    /// The last of a run of frames that is motion.
    animated_at: Option<Instant>,
    /// A waveform switch not yet drawn: the frame that follows it redraws
    /// the switch (the shell's output shader follows the waveform), not
    /// content.
    redraw: Option<Instant>,
    /// The last input or frame.
    active_at: Option<Instant>,
    /// Ghosting since the last clear, in `fast` frames.
    debt: u32,
    cleared_at: Option<Instant>,
    clear_asked: bool,
    screen_on: bool,
}

/// How soon after a switch its redraw is presented.
const REDRAW: Duration = Duration::from_millis(100);

fn within(since: Option<Instant>, span: Duration, now: Instant) -> bool {
    since.is_some_and(|t| now.saturating_duration_since(t) < span)
}

impl Policy {
    pub fn new(tuning: Tuning, resting: Waveform) -> Self {
        Self {
            tuning,
            resting: Self::restable(resting).unwrap_or(Waveform::Quality),
            auto_clear: true,
            applied: None,
            switched_at: None,
            touch: Touch::Up,
            moved_at: None,
            typed_at: None,
            frames: VecDeque::new(),
            animated_at: None,
            redraw: None,
            active_at: None,
            debt: 0,
            cleared_at: None,
            clear_asked: false,
            screen_on: true,
        }
    }

    /// Only `quality` and `text` can rest: `clean` flashes on every
    /// return to it and `fast` ghosts.
    fn restable(w: Waveform) -> Option<Waveform> {
        matches!(w, Waveform::Quality | Waveform::Text).then_some(w)
    }

    /// False, and unchanged, for a waveform that cannot rest.
    pub fn set_resting(&mut self, w: Waveform) -> bool {
        let Some(w) = Self::restable(w) else {
            return false;
        };
        self.resting = w;
        true
    }

    pub fn resting(&self) -> Waveform {
        self.resting
    }

    pub fn set_auto_clear(&mut self, on: bool) {
        self.auto_clear = on;
    }

    pub fn applied(&self) -> Option<Waveform> {
        self.applied
    }

    fn typing(&self, now: Instant) -> bool {
        within(self.typed_at, self.tuning.typing, now)
    }

    pub fn handle(&mut self, input: Input, now: Instant) {
        if !matches!(input, Input::Screen { .. }) {
            self.active_at = Some(now);
        }
        match input {
            Input::Press { x, y } => self.touch = Touch::Down(x, y),
            Input::Move { x, y } => {
                if let Touch::Down(x0, y0) = self.touch {
                    if (x - x0).hypot(y - y0) > self.tuning.slop {
                        self.touch = Touch::Dragging;
                    }
                }
                if self.touch == Touch::Dragging {
                    self.moved_at = Some(now);
                }
            }
            Input::Release => {
                // A tap on the keyboard while typing stays in text.
                let tap = matches!(self.touch, Touch::Down(..));
                if self.touch == Touch::Dragging || (tap && !self.typing(now)) {
                    self.moved_at = Some(now);
                }
                self.touch = Touch::Up;
            }
            Input::Scroll => self.moved_at = Some(now),
            Input::Key => self.typed_at = Some(now),
            Input::Frame => {
                if self.applied == Some(Waveform::Fast) {
                    self.debt = self.debt.saturating_add(1);
                }
                if self
                    .redraw
                    .take()
                    .is_some_and(|t| within(Some(t), REDRAW, now))
                {
                    return;
                }
                // Frames while a finger is down or a gesture settles draw
                // what it did, which its own settle covers; only frames
                // after it are content changing by itself.
                if self.touch != Touch::Up || within(self.moved_at, self.tuning.settle, now) {
                    self.frames.clear();
                    return;
                }
                let window = self.tuning.motion_window;
                while self
                    .frames
                    .front()
                    .is_some_and(|t| now.saturating_duration_since(*t) >= window)
                {
                    self.frames.pop_front();
                }
                self.frames.push_back(now);
                if self.frames.len() >= self.tuning.motion_frames {
                    self.animated_at = Some(now);
                }
            }
            Input::Clear => self.clear_asked = self.screen_on,
            Input::Replaced => {
                self.debt = self.debt.saturating_add(self.tuning.replaced_cost);
            }
            Input::Screen { on } => {
                self.screen_on = on;
                if !on {
                    self.touch = Touch::Up;
                    self.moved_at = None;
                    self.typed_at = None;
                    self.frames.clear();
                    self.animated_at = None;
                    self.clear_asked = false;
                }
            }
        }
    }

    /// The waveform this moment calls for. While typing, content that
    /// changes by itself (a list filtering as the user types) stays in
    /// `text`: only a finger or a scroll goes fast.
    pub fn want(&self, now: Instant) -> Waveform {
        let typing = self.typing(now);
        let moving = self.touch == Touch::Dragging
            || within(self.moved_at, self.tuning.settle, now)
            || (!typing && within(self.animated_at, self.tuning.settle, now))
            || (self.touch != Touch::Up && !typing);
        if moving {
            Waveform::Fast
        } else if typing {
            Waveform::Text
        } else {
            self.resting
        }
    }

    fn switch_ready(&self, now: Instant) -> bool {
        !within(self.switched_at, self.tuning.min_switch, now)
    }

    fn still_for(&self, now: Instant) -> Duration {
        self.active_at
            .map_or(Duration::MAX, |t| now.saturating_duration_since(t))
    }

    fn auto_clear_due(&self, now: Instant) -> bool {
        self.auto_clear
            && self.debt >= self.tuning.clear_budget
            && self.still_for(now) >= self.tuning.clear_still
            && !within(self.cleared_at, self.tuning.clear_spacing, now)
    }

    /// What to do now. Clears happen only at rest, so the panel's restore
    /// after the clear lands on the resting waveform.
    pub fn poll(&mut self, now: Instant) -> Vec<Action> {
        let mut actions = Vec::new();
        if !self.screen_on {
            return actions;
        }
        let want = self.want(now);
        if self.applied != Some(want) && self.switch_ready(now) {
            self.applied = Some(want);
            self.switched_at = Some(now);
            self.redraw = Some(now);
            actions.push(Action::Waveform(want));
        }
        let at_rest = want == self.resting && self.applied == Some(want) && self.touch == Touch::Up;
        let asked = self.clear_asked && !within(self.cleared_at, self.tuning.clear_coalesce, now);
        if at_rest && (asked || self.auto_clear_due(now)) {
            self.clear_asked = false;
            self.debt = 0;
            self.cleared_at = Some(now);
            self.switched_at = Some(now);
            actions.push(Action::Clear);
        }
        actions
    }

    /// When `poll` may next have something to do, if no input comes first.
    pub fn deadline(&self, now: Instant) -> Option<Instant> {
        let t = &self.tuning;
        let after = |since: Option<Instant>, span: Duration| since.map(|s| s + span);
        let mut candidates = vec![
            after(self.moved_at, t.settle),
            after(self.animated_at, t.settle),
            after(self.typed_at, t.typing),
        ];
        if self.applied != Some(self.want(now)) {
            candidates.push(after(self.switched_at, t.min_switch));
        }
        if self.clear_asked {
            candidates.push(after(self.cleared_at, t.clear_coalesce));
            candidates.push(after(self.switched_at, t.min_switch));
        }
        if self.auto_clear && self.debt >= t.clear_budget {
            candidates.push(after(self.active_at, t.clear_still));
            candidates.push(after(self.cleared_at, t.clear_spacing));
        }
        candidates.into_iter().flatten().filter(|d| *d > now).min()
    }
}

/// How long the next frame waits so content changes no faster than the
/// panel can finish them: `period` after the previous frame began. The
/// first frame after a pause goes at once.
pub fn pace(since_last_frame: Duration, period: Duration) -> Duration {
    period.saturating_sub(since_last_frame)
}

#[cfg(test)]
mod tests {
    use super::*;

    const MS: Duration = Duration::from_millis(1);

    struct Clock {
        start: Instant,
        now: u64,
        policy: Policy,
    }

    impl Clock {
        fn new() -> Self {
            let mut c = Self {
                start: Instant::now(),
                now: 0,
                policy: Policy::new(Tuning::default(), Waveform::Quality),
            };
            // The first poll tells the panel the resting waveform.
            assert_eq!(c.poll(0), vec![Action::Waveform(Waveform::Quality)]);
            c
        }

        fn at(&self, ms: u64) -> Instant {
            self.start + Duration::from_millis(ms)
        }

        fn input(&mut self, ms: u64, input: Input) -> Vec<Action> {
            self.now = ms;
            let now = self.at(ms);
            self.policy.handle(input, now);
            self.policy.poll(now)
        }

        fn poll(&mut self, ms: u64) -> Vec<Action> {
            self.now = ms;
            let now = self.at(ms);
            self.policy.poll(now)
        }

        /// Polls at every deadline up to `ms`, as the shell's thread does.
        fn run_until(&mut self, ms: u64) -> Vec<(u64, Action)> {
            let mut seen = Vec::new();
            let end = self.at(ms);
            while let Some(d) = self.policy.deadline(self.at(self.now)) {
                if d > end {
                    break;
                }
                self.now = u64::try_from((d - self.start).as_millis()).unwrap_or(u64::MAX);
                let t = self.now;
                seen.extend(self.policy.poll(d).into_iter().map(|a| (t, a)));
            }
            self.now = ms;
            seen
        }
    }

    const FAST: Action = Action::Waveform(Waveform::Fast);
    const TEXT: Action = Action::Waveform(Waveform::Text);
    const QUALITY: Action = Action::Waveform(Waveform::Quality);

    #[test]
    fn touch_down_goes_fast_at_once() {
        let mut c = Clock::new();
        assert_eq!(c.input(1000, Input::Press { x: 10.0, y: 10.0 }), vec![FAST]);
    }

    #[test]
    fn a_drag_goes_fast_and_rests_on_quality_after_settling() {
        let mut c = Clock::new();
        assert_eq!(c.input(1000, Input::Press { x: 0.0, y: 0.0 }), vec![FAST]);
        for step in 1..=10u8 {
            let ms = 1000 + 16 * u64::from(step);
            let y = f32::from(step) * 10.0;
            assert!(c.input(ms, Input::Move { x: 0.0, y }).is_empty());
        }
        assert!(c.input(1200, Input::Release).is_empty());
        assert_eq!(c.policy.want(c.at(1200 + 349)), Waveform::Fast);
        assert_eq!(c.run_until(3000), vec![(1550, QUALITY)]);
        // Nothing more happens: the screen holds its picture.
        assert_eq!(c.policy.deadline(c.at(3000)), None);
    }

    #[test]
    fn a_scroll_goes_fast() {
        let mut c = Clock::new();
        assert_eq!(c.input(500, Input::Scroll), vec![FAST]);
        assert_eq!(c.run_until(2000), vec![(850, QUALITY)]);
    }

    #[test]
    fn typing_holds_text_and_keyboard_taps_stay_in_it() {
        let mut c = Clock::new();
        assert_eq!(c.input(1000, Input::Key), vec![TEXT]);
        // A tap on the on-screen keyboard: the press does not go fast.
        assert!(c.input(1300, Input::Press { x: 50.0, y: 700.0 }).is_empty());
        assert!(c.input(1310, Input::Key).is_empty());
        assert!(c.input(1380, Input::Release).is_empty());
        assert_eq!(c.run_until(5000), vec![(2810, QUALITY)]);
    }

    #[test]
    fn the_first_keyboard_tap_switches_from_fast_to_text_when_allowed() {
        let mut c = Clock::new();
        assert_eq!(
            c.input(1000, Input::Press { x: 50.0, y: 700.0 }),
            vec![FAST]
        );
        // The key lands inside the rate limit: text waits for it.
        assert!(c.input(1005, Input::Key).is_empty());
        assert!(c.input(1060, Input::Release).is_empty());
        assert_eq!(c.run_until(1300), vec![(1200, TEXT)]);
    }

    #[test]
    fn a_drag_while_typing_still_goes_fast() {
        let mut c = Clock::new();
        assert_eq!(c.input(1000, Input::Key), vec![TEXT]);
        assert!(c.input(1300, Input::Press { x: 0.0, y: 300.0 }).is_empty());
        assert_eq!(c.input(1320, Input::Move { x: 0.0, y: 260.0 }), vec![FAST]);
    }

    #[test]
    fn switches_are_rate_limited_not_dropped() {
        let mut c = Clock::new();
        assert_eq!(c.input(1000, Input::Scroll), vec![FAST]);
        // Settles at 1350; the switch back is allowed then.
        assert_eq!(c.run_until(1400), vec![(1350, QUALITY)]);
        // A touch 50 ms later waits out the 200 ms limit.
        assert!(c.input(1400, Input::Press { x: 0.0, y: 0.0 }).is_empty());
        assert_eq!(c.run_until(1600), vec![(1550, FAST)]);
    }

    #[test]
    fn frames_without_input_are_motion() {
        let mut c = Clock::new();
        assert!(c.input(1000, Input::Frame).is_empty());
        assert!(c.input(1016, Input::Frame).is_empty());
        assert!(c.input(1033, Input::Frame).is_empty());
        assert_eq!(c.input(1050, Input::Frame), vec![FAST]);
        assert_eq!(c.run_until(2000), vec![(1400, QUALITY)]);
    }

    #[test]
    fn content_changing_while_typing_stays_in_text() {
        let mut c = Clock::new();
        assert_eq!(c.input(1000, Input::Key), vec![TEXT]);
        // The search results redraw for 200 ms after each key.
        for key in 0..3u64 {
            let at = 1000 + 400 * key;
            c.policy.handle(Input::Key, c.at(at));
            for f in 1..=12 {
                assert!(c.input(at + 16 * f, Input::Frame).is_empty(), "{at} {f}");
            }
        }
        assert_eq!(c.policy.want(c.at(2300)), Waveform::Text);
        assert_eq!(c.run_until(5000), vec![(3300, QUALITY)]);
    }

    #[test]
    fn frames_go_fast_again_once_typing_ends() {
        let mut c = Clock::new();
        assert_eq!(c.input(1000, Input::Key), vec![TEXT]);
        assert_eq!(c.run_until(2600), vec![(2500, QUALITY)]);
        for ms in [2700, 2716, 2733] {
            assert!(c.input(ms, Input::Frame).is_empty());
        }
        assert_eq!(c.input(2750, Input::Frame), vec![FAST]);
    }

    // The settle runs from the last frame of content: the frame that only
    // redraws the switch to the resting waveform starts no new motion.
    #[test]
    fn the_redraw_of_a_switch_is_not_motion() {
        let mut c = Clock::new();
        for ms in [1000, 1016, 1033] {
            assert!(c.input(ms, Input::Frame).is_empty());
        }
        assert_eq!(c.input(1050, Input::Frame), vec![FAST]);
        // The switch to fast redraws: not content.
        assert!(c.input(1066, Input::Frame).is_empty());
        for ms in [1360, 1380, 1390] {
            assert!(c.input(ms, Input::Frame).is_empty());
        }
        assert_eq!(c.run_until(1400), vec![(1400, QUALITY)]);
        // The switch back's redraw would be a fourth frame in the window.
        assert!(c.input(1410, Input::Frame).is_empty());
        assert_eq!(c.policy.applied(), Some(Waveform::Quality));
    }

    // A swipe's own frames (the page cut, the press going away) settle
    // with it: quality 350 ms after the release, not after its last frame.
    #[test]
    fn frames_a_gesture_draws_settle_with_it() {
        let mut c = Clock::new();
        assert_eq!(c.input(1000, Input::Press { x: 0.0, y: 0.0 }), vec![FAST]);
        for (ms, x) in [(1050, 40.0), (1100, 100.0)] {
            c.policy.handle(Input::Move { x, y: 0.0 }, c.at(ms));
            c.policy.handle(Input::Frame, c.at(ms));
        }
        assert!(c.input(1200, Input::Release).is_empty());
        for ms in [1210, 1240, 1270, 1300, 1330] {
            assert!(c.input(ms, Input::Frame).is_empty());
        }
        assert_eq!(c.run_until(3000), vec![(1550, QUALITY)]);
    }

    #[test]
    fn sparse_frames_are_not_motion() {
        let mut c = Clock::new();
        for ms in [1000, 1200, 1400, 1600, 60_000] {
            assert!(c.input(ms, Input::Frame).is_empty());
        }
    }

    #[test]
    fn idle_clear_after_enough_fast_frames_and_a_still_screen() {
        let mut c = Clock::new();
        assert_eq!(c.input(1000, Input::Scroll), vec![FAST]);
        // Three seconds of paced scrolling: 60 frames at 20 Hz.
        let mut ms = 1000;
        for _ in 0..60 {
            ms += 50;
            c.policy.handle(Input::Scroll, c.at(ms));
            c.policy.handle(Input::Frame, c.at(ms));
            assert!(c.policy.poll(c.at(ms)).is_empty());
        }
        // Rests at +350, clears once the screen has been still 1.5 s.
        assert_eq!(
            c.run_until(10_000),
            vec![(4350, QUALITY), (5500, Action::Clear)]
        );
        assert_eq!(c.policy.deadline(c.at(10_000)), None);
    }

    #[test]
    fn a_short_scroll_does_not_clear() {
        let mut c = Clock::new();
        assert_eq!(c.input(1000, Input::Scroll), vec![FAST]);
        for i in 1..=10u64 {
            c.policy.handle(Input::Frame, c.at(1000 + 50 * i));
        }
        assert_eq!(c.run_until(60_000), vec![(1850, QUALITY)]);
    }

    #[test]
    fn idle_clears_are_spaced() {
        let mut c = Clock::new();
        c.policy.debt = 1000;
        assert!(c.input(10, Input::Frame).is_empty());
        assert_eq!(c.run_until(1600), vec![(1510, Action::Clear)]);
        c.policy.debt = 1000;
        assert!(c.input(2000, Input::Frame).is_empty());
        // Still since 2 s, but the last clear was at 1.51 s.
        assert_eq!(c.run_until(30_000), vec![(21_510, Action::Clear)]);
    }

    #[test]
    fn whole_screen_changes_spend_the_budget() {
        let mut c = Clock::new();
        assert!(c.input(1000, Input::Replaced).is_empty());
        assert_eq!(c.run_until(5000), vec![]);
        assert!(c.input(6000, Input::Replaced).is_empty());
        assert_eq!(c.run_until(9000), vec![(7500, Action::Clear)]);
    }

    #[test]
    fn auto_clear_off_never_clears_by_itself() {
        let mut c = Clock::new();
        c.policy.set_auto_clear(false);
        c.policy.debt = 1000;
        assert_eq!(c.run_until(60_000), vec![]);
        assert_eq!(c.input(61_000, Input::Clear), vec![Action::Clear]);
    }

    #[test]
    fn an_asked_clear_waits_for_rest() {
        let mut c = Clock::new();
        // The refresh tile is a tap: fast first, the clear once rested.
        assert_eq!(c.input(1000, Input::Press { x: 0.0, y: 0.0 }), vec![FAST]);
        assert!(c.input(1080, Input::Release).is_empty());
        assert!(c.input(1081, Input::Clear).is_empty());
        assert_eq!(
            c.run_until(3000),
            vec![(1430, QUALITY), (1430, Action::Clear)]
        );
    }

    #[test]
    fn asked_clears_coalesce() {
        let mut c = Clock::new();
        assert_eq!(c.input(1000, Input::Clear), vec![Action::Clear]);
        assert!(c.input(1100, Input::Clear).is_empty());
        assert_eq!(c.run_until(3000), vec![(1500, Action::Clear)]);
    }

    #[test]
    fn never_clean() {
        let mut c = Clock::new();
        assert!(!c.policy.set_resting(Waveform::Clean));
        assert!(!c.policy.set_resting(Waveform::Fast));
        assert_eq!(c.policy.resting(), Waveform::Quality);
        assert!(c.policy.set_resting(Waveform::Text));
        assert_eq!(c.poll(1000), vec![TEXT]);
        assert_eq!(
            Policy::new(Tuning::default(), Waveform::Clean).resting(),
            Waveform::Quality
        );
    }

    #[test]
    fn nothing_is_written_while_the_screen_is_off() {
        let mut c = Clock::new();
        assert!(c.input(1000, Input::Screen { on: false }).is_empty());
        assert!(c.input(1100, Input::Scroll).is_empty());
        assert!(c.input(1200, Input::Clear).is_empty());
        assert_eq!(c.input(5000, Input::Screen { on: true }), vec![]);
        assert_eq!(c.run_until(6000), vec![]);
    }

    #[test]
    fn names_round_trip() {
        for w in [
            Waveform::Quality,
            Waveform::Clean,
            Waveform::Text,
            Waveform::Fast,
        ] {
            assert_eq!(Waveform::parse(w.name()), Some(w));
        }
        assert_eq!(Waveform::parse("fast\n"), Some(Waveform::Fast));
        assert_eq!(Waveform::parse("A2"), None);
    }

    #[test]
    fn pacing_holds_frames_to_the_period() {
        let period = 50 * MS;
        assert_eq!(pace(16 * MS, period), 34 * MS);
        assert_eq!(pace(50 * MS, period), Duration::ZERO);
        assert_eq!(pace(Duration::from_secs(3), period), Duration::ZERO);
    }
}
