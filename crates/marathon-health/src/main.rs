//! Boot health check for systemd boot assessment.
//!
//! Runs before `boot-complete.target` on a boot that systemd-boot is
//! counting. It succeeds once Marathon Shell has presented its first frame,
//! which the shell records as `$XDG_RUNTIME_DIR/marathon-shell-ready`, and
//! fails after the timeout so `systemd-bless-boot` never marks the entry
//! good. It then reboots if that can lead anywhere: into the same entry
//! while it has tries left, or into the previous good one.
//!
//! On a Raspberry Pi A/B image (`--mode tryboot`) the same frame commits a
//! trial boot in the firmware's `autoboot.txt`; `--mode boot` and `--mode
//! arm` set up those trials (see `tryboot`).

mod bootcount;
mod tryboot;

use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};
use std::time::{Duration, Instant};

const MARKER: &str = "marathon-shell-ready";
const POLL: Duration = Duration::from_secs(1);

#[allow(clippy::print_stderr, reason = "journald collects stderr")]
fn log(message: &str) {
    eprintln!("marathon-health: {message}");
}

fn shell_ready(runtime_root: &Path) -> bool {
    std::fs::read_dir(runtime_root).is_ok_and(|entries| {
        entries
            .flatten()
            .any(|entry| entry.path().join(MARKER).is_file())
    })
}

fn wait_for_shell(runtime_root: &Path, timeout: Duration, poll: Duration) -> bool {
    let deadline = Instant::now() + timeout;
    loop {
        if shell_ready(runtime_root) {
            return true;
        }
        let now = Instant::now();
        if now >= deadline {
            return false;
        }
        std::thread::sleep(poll.min(deadline - now));
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Mode {
    Bless,
    Tryboot,
    Boot,
    Arm,
}

struct Args {
    timeout: Duration,
    runtime_root: PathBuf,
    mode: Mode,
}

fn parse_args(mut args: impl Iterator<Item = String>) -> Result<Args, String> {
    let mut parsed = Args {
        timeout: Duration::from_secs(300),
        runtime_root: PathBuf::from("/run/user"),
        mode: Mode::Bless,
    };
    while let Some(arg) = args.next() {
        let value = args.next().ok_or_else(|| format!("{arg} needs a value"))?;
        match arg.as_str() {
            "--timeout" => {
                let secs = value
                    .parse()
                    .map_err(|e| format!("bad --timeout {value}: {e}"))?;
                parsed.timeout = Duration::from_secs(secs);
            }
            "--runtime-root" => parsed.runtime_root = PathBuf::from(value),
            "--mode" => {
                parsed.mode = match value.as_str() {
                    "bless" => Mode::Bless,
                    "tryboot" => Mode::Tryboot,
                    "boot" => Mode::Boot,
                    "arm" => Mode::Arm,
                    _ => return Err(format!("unknown --mode {value}")),
                }
            }
            _ => return Err(format!("unknown argument {arg}")),
        }
    }
    Ok(parsed)
}

fn main() -> ExitCode {
    let args = match parse_args(std::env::args().skip(1)) {
        Ok(args) => args,
        Err(e) => {
            log(&e);
            return ExitCode::from(2);
        }
    };
    match args.mode {
        Mode::Bless => bless(&args),
        Mode::Tryboot => commit_trial(&args),
        Mode::Boot => {
            tryboot::on_boot();
            ExitCode::SUCCESS
        }
        Mode::Arm => {
            tryboot::on_shutdown();
            ExitCode::SUCCESS
        }
    }
}

/// A Pi trial boot: commit it once the shell draws, else reboot, which the
/// firmware sends to the committed slot.
fn commit_trial(args: &Args) -> ExitCode {
    if !tryboot::is_trial_boot() {
        log("not a trial boot");
        return ExitCode::SUCCESS;
    }
    if !wait_for_shell(&args.runtime_root, args.timeout, POLL) {
        log(&format!(
            "no shell frame within {}s; going back to the committed slot",
            args.timeout.as_secs()
        ));
        tryboot::reboot();
        return ExitCode::FAILURE;
    }
    match tryboot::commit() {
        Ok(Some(a)) => {
            log(&format!(
                "shell presented its first frame; partition {} committed",
                a.all
            ));
            ExitCode::SUCCESS
        }
        Ok(None) => {
            log("shell presented its first frame; already committed");
            ExitCode::SUCCESS
        }
        Err(e) => {
            log(&format!("could not commit the trial boot: {e}"));
            ExitCode::FAILURE
        }
    }
}

fn bless(args: &Args) -> ExitCode {
    if wait_for_shell(&args.runtime_root, args.timeout, POLL) {
        log("shell presented its first frame; boot is good");
        ExitCode::SUCCESS
    } else {
        log(&format!(
            "no shell frame within {}s; leaving this boot unblessed",
            args.timeout.as_secs()
        ));
        match bootcount::counted_entry(Path::new(bootcount::COUNT_PATH_VAR)) {
            Some(entry) if bootcount::reboot_helps(&entry) => {
                log(&format!("rebooting away from {}", entry.display()));
                match Command::new("systemctl")
                    .args(["--no-block", "reboot"])
                    .status()
                {
                    Ok(status) if status.success() => {}
                    Ok(status) => log(&format!("systemctl reboot: {status}")),
                    Err(e) => log(&format!("systemctl reboot: {e}")),
                }
            }
            Some(entry) => log(&format!(
                "{} is the last entry left; staying up",
                entry.display()
            )),
            None => log("this boot is not counted"),
        }
        ExitCode::FAILURE
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    fn args(list: &[&str]) -> Result<Args, String> {
        parse_args(list.iter().map(ToString::to_string))
    }

    #[test]
    fn ready_once_any_user_runtime_dir_has_the_marker() {
        let root = tempfile::tempdir().unwrap();
        std::fs::create_dir(root.path().join("0")).unwrap();
        std::fs::create_dir(root.path().join("1000")).unwrap();
        assert!(!shell_ready(root.path()));
        std::fs::write(root.path().join("1000").join(MARKER), b"").unwrap();
        assert!(shell_ready(root.path()));
    }

    #[test]
    fn a_marker_directory_is_not_a_frame() {
        let root = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(root.path().join("1000").join(MARKER)).unwrap();
        assert!(!shell_ready(root.path()));
    }

    #[test]
    fn a_missing_runtime_root_is_not_ready() {
        let root = tempfile::tempdir().unwrap();
        assert!(!shell_ready(&root.path().join("user")));
    }

    #[test]
    fn times_out_without_a_frame() {
        let root = tempfile::tempdir().unwrap();
        let start = Instant::now();
        assert!(!wait_for_shell(
            root.path(),
            Duration::from_millis(50),
            Duration::from_millis(10)
        ));
        assert!(start.elapsed() >= Duration::from_millis(50));
    }

    #[test]
    fn sees_a_frame_that_arrives_while_waiting() {
        let root = tempfile::tempdir().unwrap();
        let dir = root.path().join("1000");
        std::fs::create_dir(&dir).unwrap();
        let writer = std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(30));
            std::fs::write(dir.join(MARKER), b"").unwrap();
        });
        assert!(wait_for_shell(
            root.path(),
            Duration::from_secs(5),
            Duration::from_millis(10)
        ));
        writer.join().unwrap();
    }

    #[test]
    fn parses_timeout_and_root() {
        let parsed = args(&["--timeout", "120", "--runtime-root", "/tmp/x"]).unwrap();
        assert_eq!(parsed.timeout, Duration::from_secs(120));
        assert_eq!(parsed.runtime_root, PathBuf::from("/tmp/x"));
        let defaults = args(&[]).unwrap();
        assert_eq!(defaults.timeout, Duration::from_secs(300));
        assert_eq!(defaults.runtime_root, PathBuf::from("/run/user"));
        assert_eq!(defaults.mode, Mode::Bless);
    }

    #[test]
    fn parses_modes() {
        assert_eq!(args(&["--mode", "tryboot"]).unwrap().mode, Mode::Tryboot);
        assert_eq!(args(&["--mode", "boot"]).unwrap().mode, Mode::Boot);
        assert_eq!(args(&["--mode", "arm"]).unwrap().mode, Mode::Arm);
        assert_eq!(args(&["--mode", "bless"]).unwrap().mode, Mode::Bless);
        assert!(args(&["--mode", "later"]).is_err());
    }

    #[test]
    fn rejects_bad_arguments() {
        assert!(args(&["--timeout"]).is_err());
        assert!(args(&["--timeout", "soon"]).is_err());
        assert!(args(&["--frobnicate", "1"]).is_err());
    }
}
