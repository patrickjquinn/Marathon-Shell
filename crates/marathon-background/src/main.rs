//! Declared background work for Marathon (`docs/BACKGROUND_WORK.md`).
//!
//! - As `marathon-background-generator` (a systemd user generator): units
//!   for the tasks apps declare in their manifests.
//! - `check`: a task's constraints, as its `ExecCondition=`.
//! - `arm-wake`: before suspend, a system wake-up for the next
//!   `marathon-wake-*` user timer.

mod check;
mod generator;
mod task;
mod wake;

use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::time::{SystemTime, UNIX_EPOCH};

const APPS: &str = "/usr/share/marathon-apps";
const KEEL_ACTIONS: &str = "/usr/share/keel/actions";
const POWER_SUPPLY: &str = "/sys/class/power_supply";
const WAKE_MARKER: &str = "/run/marathon-background/wake";

#[allow(clippy::print_stderr, reason = "journald collects stderr")]
fn log(message: &str) {
    eprintln!("marathon-background: {message}");
}

fn generate(normal_dir: Option<String>) -> ExitCode {
    let Some(out) = normal_dir else {
        log("a generator is called with its output directories");
        return ExitCode::FAILURE;
    };
    let helper = std::env::current_exe()
        .and_then(std::fs::canonicalize)
        .unwrap_or_else(|_| PathBuf::from("/usr/libexec/marathon-background"));
    let sources = generator::Sources {
        apps: Path::new(APPS),
        keel_actions: Path::new(KEEL_ACTIONS),
        helper: &helper,
    };
    match generator::generate(&sources, Path::new(&out)) {
        Ok(_) => ExitCode::SUCCESS,
        Err(e) => {
            log(&format!("writing units to {out}: {e}"));
            ExitCode::FAILURE
        }
    }
}

fn check(args: impl Iterator<Item = String>) -> ExitCode {
    let constraints = match check::parse_args(args) {
        Ok(c) => c,
        Err(e) => {
            log(&e);
            return ExitCode::from(255);
        }
    };
    match check::unmet(&constraints, Path::new(POWER_SUPPLY)) {
        None => ExitCode::SUCCESS,
        Some(reason) => {
            log(&format!("skipped: {reason}"));
            ExitCode::from(1)
        }
    }
}

fn arm_wake() -> ExitCode {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or_default();
    if wake::arm(now, Path::new(POWER_SUPPLY), Path::new(WAKE_MARKER)) {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}

fn main() -> ExitCode {
    let mut args = std::env::args();
    let argv0 = args.next().unwrap_or_default();
    if Path::new(&argv0).file_name() == Some("marathon-background-generator".as_ref()) {
        return generate(args.next());
    }
    match args.next().as_deref() {
        Some("check") => check(args),
        Some("arm-wake") => arm_wake(),
        _ => {
            log("usage: marathon-background check [--network=any|unmetered] [--battery-not-low] | arm-wake");
            ExitCode::from(2)
        }
    }
}
