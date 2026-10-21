//! Interaction boost: every cpufreq policy's `scaling_min_freq` goes to its
//! maximum on input and back once input has been quiet for a while.
//! ondemand ramps only on a sample over 95% load, and a frame is a short
//! burst between idles, so gestures ran at the lowest clocks and missed
//! vblank. Writes run on a thread of their own: a cpufreq write waits for
//! the clock change. Needs write access to `scaling_min_freq` (the input
//! group, by marathon-base-config's 60-marathon-cpufreq.rules).

use std::fs::{self, File};
use std::os::unix::fs::FileExt as _;
use std::path::Path;
use std::sync::mpsc::{self, RecvTimeoutError, Sender};
use std::sync::LazyLock;
use std::time::Duration;

#[cxx_qt::bridge]
mod ffi {
    #[namespace = "marathon::boost"]
    extern "Rust" {
        /// The user touched, clicked or typed.
        fn input();
    }
}

/// The settle or fling after a release, and a launch's first frames.
const HOLD: Duration = Duration::from_millis(1500);

struct Policy {
    file: File,
    boosted: String,
    resting: String,
}

fn read(dir: &Path, name: &str) -> String {
    fs::read_to_string(dir.join(name)).map(|s| s.trim().to_owned()).unwrap_or_default()
}

fn policies() -> Vec<Policy> {
    let mut found = Vec::new();
    for dir in fs::read_dir("/sys/devices/system/cpu/cpufreq").into_iter().flatten().flatten().map(|e| e.path()) {
        if !dir.file_name().is_some_and(|n| n.to_string_lossy().starts_with("policy")) {
            continue;
        }
        let boosted = read(&dir, "cpuinfo_max_freq");
        let current = read(&dir, "scaling_min_freq");
        // A shell killed while boosting left the boosted floor in place.
        let resting = if current == boosted { read(&dir, "cpuinfo_min_freq") } else { current };
        if boosted.is_empty() || resting.is_empty() {
            continue;
        }
        match fs::OpenOptions::new().write(true).open(dir.join("scaling_min_freq")) {
            Ok(file) => found.push(Policy { file, boosted, resting }),
            Err(e) => crate::log::warn("boost", format_args!("{}: {e}; no interaction boost", dir.display())),
        }
    }
    found
}

fn write(policies: &[Policy], boosted: bool) {
    for p in policies {
        let value = if boosted { &p.boosted } else { &p.resting };
        if let Err(e) = p.file.write_at(value.as_bytes(), 0) {
            crate::log::warn("boost", format_args!("scaling_min_freq: {e}"));
        }
    }
}

static INPUT: LazyLock<Option<Sender<()>>> = LazyLock::new(|| {
    let policies = policies();
    if policies.is_empty() {
        return None;
    }
    let (tx, rx) = mpsc::channel::<()>();
    std::thread::Builder::new()
        .name("InputBoost".into())
        .spawn(move || {
            while rx.recv().is_ok() {
                write(&policies, true);
                loop {
                    match rx.recv_timeout(HOLD) {
                        Ok(()) => {}
                        Err(RecvTimeoutError::Timeout) => break,
                        Err(RecvTimeoutError::Disconnected) => return,
                    }
                }
                write(&policies, false);
            }
        })
        .ok()?;
    Some(tx)
});

fn input() {
    if let Some(tx) = INPUT.as_ref() {
        tx.send(()).ok();
    }
}
