//! The e-paper panel's waveform ladder: `marathon_eink`'s policy on a thread
//! of its own, fed by the shell's input filter, the on-screen keyboard and
//! the scene graph's frames, writing the panel driver's interim sysfs ABI
//! (`refresh_mode`, `full_refresh`). udev/70-marathon-shell.rules lets the
//! video group write them. A mode write is a two-byte I2C transfer, so it
//! goes out within the frame that asked for it.

use std::fs::{self, File, OpenOptions};
use std::os::unix::fs::FileExt as _;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::sync::{Mutex, OnceLock, PoisonError};
use std::time::{Duration, Instant};

use marathon_eink::{Action, Input, Policy, Tuning, Waveform};

use crate::log;

#[cxx_qt::bridge]
mod ffi {
    #[namespace = "marathon::eink"]
    extern "Rust" {
        /// A finger or button went down at `x`, `y` (device pixels).
        fn press(x: f32, y: f32);
        fn motion(x: f32, y: f32);
        fn release();
        fn scroll();
        /// A key was typed, on a keyboard or the on-screen one.
        fn key();
        /// The refresh key: clear the panel's ghosts.
        fn refresh();
        /// Render thread, before a frame: in `fast`, waits until the last
        /// frame is a pacing period old, so content changes no faster than
        /// the waveform finishes them.
        fn pace();
        /// Render thread, after a frame was presented.
        fn frame();
    }
}

enum Msg {
    Input(Input),
    Resting(Waveform),
    AutoClear(bool),
}

struct Engine {
    tx: Sender<Msg>,
    pace: Duration,
}

static ENGINE: OnceLock<Engine> = OnceLock::new();
/// The panel is in `fast`, from any thread.
static FAST: AtomicBool = AtomicBool::new(false);
/// When the last frame began, while pacing.
static LAST_FRAME: Mutex<Option<Instant>> = Mutex::new(None);

fn env_ms(name: &str, default: u64) -> Duration {
    Duration::from_millis(
        std::env::var(name)
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(default),
    )
}

/// The driver's attributes, on whichever device has both.
struct Panel {
    mode: File,
    clear: File,
}

impl Panel {
    fn find(root: &Path) -> Option<Self> {
        let dir = fs::read_dir(root)
            .ok()?
            .flatten()
            .map(|e| e.path())
            .find(|d| d.join("refresh_mode").exists() && d.join("full_refresh").exists())?;
        let open = |name: &str| {
            OpenOptions::new()
                .write(true)
                .open(dir.join(name))
                .map_err(|e| log::warn("eink", format_args!("{}/{name}: {e}", dir.display())))
                .ok()
        };
        let panel = Self {
            mode: open("refresh_mode")?,
            clear: open("full_refresh")?,
        };
        log::info(
            "eink",
            format_args!("refresh controls at {}", dir.display()),
        );
        Some(panel)
    }

    fn apply(&self, action: Action) {
        let (file, text, what) = match action {
            Action::Waveform(w) => (&self.mode, format!("{}\n", w.name()), "refresh_mode"),
            Action::Clear => (&self.clear, "1\n".to_owned(), "full_refresh"),
        };
        if let Err(e) = file.write_at(text.as_bytes(), 0) {
            log::warn("eink", format_args!("{what}: {e}"));
        }
    }
}

fn run(panel: &Panel, rx: &Receiver<Msg>, mut policy: Policy) {
    loop {
        let now = Instant::now();
        for action in policy.poll(now) {
            panel.apply(action);
            if let Action::Waveform(w) = action {
                FAST.store(w == Waveform::Fast, Ordering::Relaxed);
                crate::display::panel_waveform(w);
            }
        }
        let msg = match policy.deadline(now) {
            Some(d) => match rx.recv_timeout(d.saturating_duration_since(Instant::now())) {
                Ok(msg) => Some(msg),
                Err(RecvTimeoutError::Timeout) => None,
                Err(RecvTimeoutError::Disconnected) => return,
            },
            None => match rx.recv() {
                Ok(msg) => Some(msg),
                Err(_) => return,
            },
        };
        for msg in msg.into_iter().chain(rx.try_iter()) {
            match msg {
                Msg::Input(input) => policy.handle(input, Instant::now()),
                Msg::Resting(w) => {
                    policy.set_resting(w);
                }
                Msg::AutoClear(on) => policy.set_auto_clear(on),
            }
        }
    }
}

/// Starts the policy on the panel under `root` (/sys/bus/i2c/devices);
/// false when no panel has the refresh controls.
pub(crate) fn start(root: &Path) -> bool {
    let Some(panel) = Panel::find(root) else {
        log::info("eink", "no refresh controls: rendering policy only");
        return false;
    };
    // The two numbers a camera on the panel has to settle.
    let tuning = Tuning {
        settle: env_ms("MARATHON_EINK_SETTLE_MS", 350),
        ..Tuning::default()
    };
    let (tx, rx) = mpsc::channel();
    let policy = Policy::new(tuning, Waveform::Quality);
    let spawned = std::thread::Builder::new()
        .name("Eink".into())
        .spawn(move || run(&panel, &rx, policy));
    if let Err(e) = spawned {
        log::warn("eink", format_args!("no policy thread: {e}"));
        return false;
    }
    ENGINE
        .set(Engine {
            tx,
            pace: env_ms("MARATHON_EINK_PACE_MS", 50),
        })
        .is_ok()
}

fn send(msg: Msg) {
    if let Some(engine) = ENGINE.get() {
        engine.tx.send(msg).ok();
    }
}

fn input(input: Input) {
    send(Msg::Input(input));
}

pub(crate) fn set_resting(w: Waveform) {
    send(Msg::Resting(w));
}

pub(crate) fn set_auto_clear(on: bool) {
    send(Msg::AutoClear(on));
}

pub(crate) fn screen(on: bool) {
    input(Input::Screen { on });
}

/// Most of the screen changed at once: it counts toward the next clear.
pub(crate) fn replaced() {
    input(Input::Replaced);
}

pub(crate) fn refresh() {
    input(Input::Clear);
}

fn press(x: f32, y: f32) {
    input(Input::Press { x, y });
}

fn motion(x: f32, y: f32) {
    input(Input::Move { x, y });
}

fn release() {
    input(Input::Release);
}

fn scroll() {
    input(Input::Scroll);
}

fn key() {
    input(Input::Key);
}

fn frame() {
    input(Input::Frame);
}

fn pace() {
    let Some(engine) = ENGINE.get() else { return };
    if engine.pace.is_zero() {
        return;
    }
    let mut last = LAST_FRAME.lock().unwrap_or_else(PoisonError::into_inner);
    if FAST.load(Ordering::Relaxed) {
        if let Some(prev) = *last {
            std::thread::sleep(marathon_eink::pace(prev.elapsed(), engine.pace));
        }
    }
    *last = Some(Instant::now());
}
