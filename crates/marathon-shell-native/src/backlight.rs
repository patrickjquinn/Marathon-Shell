//! The panel's backlight in sysfs, written from the I/O thread: brightness
//! (the latest level wins), ramps, the wake-up power cycle and the call
//! proximity blank. A DCS or I2C backlight can take milliseconds a write;
//! none of them lands on the GUI thread. The curves and the policy stay in
//! `DisplayManagerCpp`, which owns this object.

use std::collections::VecDeque;
use std::path::PathBuf;
use std::pin::Pin;
use std::time::Duration;

use async_channel::{Receiver, Sender};
use async_io::Timer;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QString};
use futures_lite::future;

use crate::{io, log};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qlist.h");
        type QList_i32 = cxx_qt_lib::QList<i32>;
    }

    extern "RustQt" {
        #[qobject]
        type Backlight = super::BacklightRust;

        /// Someone else set the backlight: what it reads now.
        #[qsignal]
        #[cxx_name = "levelReadBack"]
        fn level_read_back(self: Pin<&mut Self>, actual: i32, requested: i32);
        /// Whether the panel lit after `checkLit`.
        #[qsignal]
        #[cxx_name = "litChecked"]
        fn lit_checked(self: Pin<&mut Self>, lit: bool);

        /// The sysfs directory of the backlight, `/sys/class/backlight/<name>`.
        #[qinvokable]
        #[cxx_name = "setDevice"]
        fn set_device(self: Pin<&mut Backlight>, directory: &QString);
        #[qinvokable]
        #[cxx_name = "setLevel"]
        fn set_level(self: &Backlight, level: i32);
        /// Writes each level in turn, `interval_ms` apart, skipping repeats;
        /// a later level or ramp replaces it.
        #[qinvokable]
        fn ramp(self: &Backlight, levels: &QList_i32, interval_ms: i32);
        /// Power-cycles the LED and writes `level`: a panel woken from deep
        /// idle can keep a duty latched at 0 otherwise.
        #[qinvokable]
        #[cxx_name = "forceOn"]
        fn force_on(self: &Backlight, level: i32);
        /// Powers the LED down, or up again at `level`.
        #[qinvokable]
        fn blank(self: &Backlight, blank: bool, level: i32);
        /// Reads the levels back, answering with `levelReadBack` if they
        /// differ from what was last written.
        #[qinvokable]
        fn refresh(self: &Backlight);
        /// Reads `bl_power`, answering with `litChecked`.
        #[qinvokable]
        #[cxx_name = "checkLit"]
        fn check_lit(self: &Backlight);
    }

    impl cxx_qt::Threading for Backlight {}
}

use qobject::Backlight;

#[derive(Default)]
pub struct BacklightRust {
    actor: Option<Sender<Command>>,
}

enum Command {
    Level(i32),
    Ramp(Vec<i32>, Duration),
    ForceOn(i32),
    Blank(bool, i32),
    Refresh,
    CheckLit,
}

type Qt = cxx_qt::CxxQtThread<Backlight>;

impl Backlight {
    fn set_device(mut self: Pin<&mut Self>, directory: &QString) {
        let (tx, rx) = async_channel::bounded(64);
        io::spawn(run(self.qt_thread(), PathBuf::from(directory.to_string()), rx));
        self.as_mut().rust_mut().actor = Some(tx);
    }

    fn send(&self, command: Command) {
        if let Some(actor) = &self.actor {
            if actor.try_send(command).is_err() {
                log::warn("backlight", "busy; dropped a write");
            }
        }
    }

    fn set_level(&self, level: i32) {
        self.send(Command::Level(level));
    }

    fn ramp(&self, levels: &QList<i32>, interval_ms: i32) {
        let interval = Duration::from_millis(u64::try_from(interval_ms).unwrap_or(20));
        self.send(Command::Ramp(levels.iter().copied().collect(), interval));
    }

    fn force_on(&self, level: i32) {
        self.send(Command::ForceOn(level));
    }

    fn blank(&self, blank: bool, level: i32) {
        self.send(Command::Blank(blank, level));
    }

    fn refresh(&self) {
        self.send(Command::Refresh);
    }

    fn check_lit(&self) {
        self.send(Command::CheckLit);
    }
}

struct Device {
    dir: PathBuf,
    written: Option<i32>,
}

impl Device {
    fn write(&self, file: &str, value: &str) -> bool {
        match std::fs::write(self.dir.join(file), format!("{value}\n")) {
            Ok(()) => true,
            Err(e) => {
                log::warn("backlight", format_args!("{file}: {e}"));
                false
            }
        }
    }

    fn read(&self, file: &str) -> Option<i32> {
        std::fs::read_to_string(self.dir.join(file)).ok()?.trim().parse().ok()
    }

    fn level(&mut self, level: i32) {
        if self.written != Some(level) && self.write("brightness", &level.to_string()) {
            self.written = Some(level);
        }
    }
}

async fn run(qt: Qt, dir: PathBuf, commands: Receiver<Command>) {
    let mut device = Device { dir, written: None };
    let mut ramp: VecDeque<i32> = VecDeque::new();
    let mut interval = Duration::from_millis(20);
    loop {
        // While ramping, the next step and the next command race.
        let command = if ramp.is_empty() {
            match commands.recv().await {
                Ok(c) => Some(c),
                Err(_) => return,
            }
        } else {
            future::or(async { commands.recv().await.ok() }, async {
                Timer::after(interval).await;
                None
            })
            .await
        };
        let Some(command) = command else {
            if let Some(level) = ramp.pop_front() {
                device.level(level);
            }
            continue;
        };
        for command in collapse(command, &commands) {
            match command {
                Command::Level(level) => {
                    ramp.clear();
                    device.level(level);
                }
                Command::Ramp(levels, step) => {
                    interval = step;
                    let mut levels = levels;
                    levels.dedup();
                    ramp = levels.into();
                }
                Command::ForceOn(level) => {
                    ramp.clear();
                    device.write("bl_power", "4");
                    Timer::after(Duration::from_millis(30)).await;
                    device.write("bl_power", "0");
                    // Two stores, so pwm_backlight_update_status re-applies
                    // the duty: one idempotent write can be skipped.
                    device.write("brightness", "1");
                    device.written = None;
                    device.level(level);
                }
                Command::Blank(blank, level) => {
                    device.write("bl_power", if blank { "4" } else { "0" });
                    if !blank {
                        device.written = None;
                        device.level(level);
                    }
                }
                Command::Refresh => {
                    // actual_brightness can lag the hardware; only a requested
                    // level the shell didn't write is someone else's.
                    let requested = device.read("brightness");
                    if requested.is_some() && requested != device.written {
                        let actual = device.read("actual_brightness").unwrap_or(-1);
                        let requested = requested.unwrap_or(-1);
                        device.written = Some(requested);
                        qt.queue(move |obj| obj.level_read_back(actual, requested)).ok();
                    }
                }
                Command::CheckLit => {
                    // bl_power 0 (FB_BLANK_UNBLANK) means the panel lit.
                    let lit = device.read("bl_power") == Some(0);
                    qt.queue(move |obj| obj.lit_checked(lit)).ok();
                }
            }
        }
    }
}

/// `first` and everything queued behind it, each run of levels collapsed
/// to its last: a slider drag writes where the finger is, not every step
/// it passed.
fn collapse(first: Command, commands: &Receiver<Command>) -> Vec<Command> {
    let mut batch: Vec<Command> = Vec::new();
    for command in std::iter::once(first).chain(std::iter::from_fn(|| commands.try_recv().ok())) {
        if let (Command::Level(_), Some(Command::Level(_))) = (&command, batch.last()) {
            batch.pop();
        }
        batch.push(command);
    }
    batch
}

#[cfg(test)]
mod tests {
    use super::{collapse, Command};

    #[test]
    fn runs_of_levels_collapse_to_their_last() {
        let (tx, rx) = async_channel::unbounded();
        for c in [Command::Level(3), Command::Refresh, Command::Level(5), Command::Level(6), Command::CheckLit, Command::Level(7)] {
            tx.try_send(c).ok();
        }
        let batch = collapse(Command::Level(2), &rx);
        let shown: Vec<String> = batch
            .iter()
            .map(|c| match c {
                Command::Level(l) => l.to_string(),
                Command::Refresh => "refresh".into(),
                Command::CheckLit => "lit".into(),
                _ => "other".into(),
            })
            .collect();
        assert_eq!(shown, ["3", "refresh", "6", "lit", "7"]);
    }
}
