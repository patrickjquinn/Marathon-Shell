//! The flatpak work behind each verb. The app id has already been checked
//! against `REF_RE`, and every command runs with a fixed argv.

use std::fs::File;
use std::io::{self, Read};
use std::path::Path;
use std::process::{Command, Stdio};

use serde_json::{json, Value};

use crate::progress;
use crate::request::{Verb, REF_RE};
use crate::state::{now, Progress, StateDir};

const REMOTE: &str = "flathub";

pub fn job_unit(app_id: &str) -> String {
    format!("marathon-store-job-{app_id}.service")
}

/// Locale, Sources and Debug extensions update with their app.
fn is_app_ref(app_id: &str) -> bool {
    !(app_id.ends_with(".Locale") || app_id.ends_with(".Sources") || app_id.ends_with(".Debug"))
}

fn stdout_of(cmd: &mut Command) -> String {
    cmd.stderr(Stdio::null())
        .output()
        .map(|out| String::from_utf8_lossy(&out.stdout).into_owned())
        .unwrap_or_default()
}

/// User installs need a user remote; the image only registers Flathub for
/// the system installation.
fn ensure_remote(flatpak: &str) -> Vec<u8> {
    let local = "/etc/flatpak/remotes.d/flathub.flatpakrepo";
    let repo = if Path::new(local).is_file() {
        local
    } else {
        "https://dl.flathub.org/repo/flathub.flatpakrepo"
    };
    Command::new(flatpak)
        .args(["--user", "remote-add", "--if-not-exists", REMOTE, repo])
        .output()
        .map(|out| [out.stdout, out.stderr].concat())
        .unwrap_or_default()
}

/// Runs flatpak on a pty, since it only draws progress ("Installing 2/3…
/// 45%") on a terminal. Each redraw ends in a carriage return; `on_redraw`
/// sees each one. Returns whether flatpak succeeded and everything it wrote.
fn run_on_pty(
    flatpak: &str,
    args: &[&str],
    mut on_redraw: impl FnMut(&str),
) -> io::Result<(bool, Vec<u8>)> {
    let pty = nix::pty::openpty(None, None)?;
    let mut child = Command::new(flatpak)
        .args(args)
        .stdin(Stdio::null())
        .stdout(pty.slave.try_clone()?)
        .stderr(pty.slave)
        .spawn()?;
    let mut master = File::from(pty.master);
    let mut log = Vec::new();
    let mut pending = Vec::new();
    let mut buf = [0u8; 4096];
    loop {
        // EIO once the child has closed the pty's last slave descriptor.
        let n = match master.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => n,
            Err(e) if e.raw_os_error() == Some(nix::libc::EIO) => break,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(e),
        };
        log.extend_from_slice(&buf[..n]);
        pending.extend_from_slice(&buf[..n]);
        while let Some(at) = pending.iter().position(|&b| b == b'\r') {
            on_redraw(&String::from_utf8_lossy(&pending[..at]));
            pending.drain(..=at);
        }
    }
    if !pending.is_empty() {
        on_redraw(&String::from_utf8_lossy(&pending));
    }
    Ok((child.wait()?.success(), log))
}

/// install / update / uninstall one app, reporting progress through its
/// state file. Every outcome, including flatpak failing to start, ends in a
/// final record, so the Store never waits on "pending".
pub fn run_op(state: &StateDir, flatpak: &str, verb: Verb, app_id: &str) -> io::Result<()> {
    let op = verb.as_str();
    let (args, busy, done): (Vec<&str>, _, _) = match verb {
        Verb::Install => (
            vec!["--user", "install", "-y", REMOTE, app_id],
            "installing",
            "done",
        ),
        Verb::Update => (vec!["--user", "update", "-y", app_id], "installing", "done"),
        _ => (
            vec!["--user", "uninstall", "-y", app_id],
            "removing",
            "removed",
        ),
    };
    let record = |state_name: &'static str, percent: i32| Progress {
        app_id,
        verb: op,
        state: state_name,
        percent,
        error: "",
    };

    state.write_progress(&record("pending", -1))?;
    let mut log = if verb == Verb::Install {
        ensure_remote(flatpak)
    } else {
        Vec::new()
    };
    let result = run_on_pty(flatpak, &args, |redraw| {
        if let Some(pct) = progress::percent(redraw) {
            let pct = i32::try_from(pct).unwrap_or(100);
            // A lost redraw only delays the bar; the final record below
            // still reports the outcome, or fails loudly.
            let _redraw = state.write_progress(&record(busy, pct));
        }
    });
    match result {
        Ok((true, _)) => state.write_progress(&record(done, 100))?,
        Ok((false, out)) => {
            log.extend(out);
            let reason = progress::last_error(&log).unwrap_or_default();
            state.write_progress(&Progress {
                error: &reason,
                ..record("failed", -1)
            })?;
        }
        Err(e) => state.write_progress(&Progress {
            error: &e.to_string(),
            ..record("failed", -1)
        })?,
    }
    refresh(state, flatpak)
}

/// Every queued app reports "pending" up front, so the Store doesn't give up
/// on the ones still waiting their turn. Each update runs in its own job
/// unit, so one can be cancelled without stopping the rest; a cancelled
/// record skips an app that hasn't started yet.
pub fn update_all(state: &StateDir, flatpak: &str, handler: &Path) -> io::Result<()> {
    let listing = stdout_of(Command::new(flatpak).args([
        "--user",
        "remote-ls",
        "--updates",
        "--columns=application",
    ]));
    let apps: Vec<&str> = listing
        .split_whitespace()
        .filter(|app| is_app_ref(app) && REF_RE.is_match(app))
        .collect();
    for app in &apps {
        state.write_progress(&Progress {
            app_id: app,
            verb: "update",
            state: "pending",
            percent: -1,
            error: "",
        })?;
    }
    for app in apps {
        if state.progress_state(app).as_deref() == Some("cancelled") {
            continue;
        }
        // A failed update has already recorded why; carry on with the rest.
        let _status = Command::new("systemd-run")
            .args(["--user", "--quiet", "--collect", "--wait"])
            .arg(format!("--unit={}", job_unit(app)))
            .arg("--setenv=MARATHON_STORE_UNIT=1")
            .arg(handler)
            .arg(format!("marathon-store://update/{app}"))
            .status();
    }
    Ok(())
}

/// Stopping the unit kills flatpak mid-transaction; ostree leaves the
/// installed version untouched until a deploy completes. A job that
/// finished before the stop keeps its result.
pub fn cancel(state: &StateDir, flatpak: &str, app_id: &str) -> io::Result<()> {
    // Nothing to stop is fine: the job may not have started or has ended.
    let _status = Command::new("systemctl")
        .args(["--user", "stop", &job_unit(app_id)])
        .stderr(Stdio::null())
        .status();
    let record = state.read_progress(app_id);
    let field = |key: &str| {
        record
            .as_ref()
            .and_then(|r| r.get(key))
            .and_then(Value::as_str)
            .map(str::to_owned)
    };
    if matches!(
        field("state").as_deref(),
        Some("done" | "removed" | "failed")
    ) {
        return Ok(());
    }
    let verb = field("verb").unwrap_or_else(|| "install".to_owned());
    state.write_progress(&Progress {
        app_id,
        verb: &verb,
        state: "cancelled",
        percent: -1,
        error: "",
    })?;
    refresh(state, flatpak)
}

fn icon_for(icons: &Path, app_id: &str) -> String {
    [
        format!("128x128/apps/{app_id}.png"),
        format!("256x256/apps/{app_id}.png"),
        format!("512x512/apps/{app_id}.png"),
        format!("scalable/apps/{app_id}.svg"),
        format!("64x64/apps/{app_id}.png"),
    ]
    .iter()
    .map(|candidate| icons.join(candidate))
    .find(|path| path.is_file())
    .map(|path| format!("file://{}", path.display()))
    .unwrap_or_default()
}

/// `flatpak list --columns=application,version,name` rows.
pub fn installed(listing: &str, icons: &Path) -> Value {
    let apps: Vec<Value> = listing
        .lines()
        .filter_map(|line| {
            let mut cols = line.splitn(3, '\t');
            let app_id = cols.next().filter(|id| REF_RE.is_match(id))?;
            let version = cols.next().unwrap_or_default();
            let name = cols.next().unwrap_or_default();
            Some(json!({
                "app_id": app_id,
                "name": name,
                "version": version,
                "icon": icon_for(icons, app_id),
            }))
        })
        .collect();
    json!({ "installed": apps, "ts": now() })
}

pub fn updates(listing: &str) -> Value {
    let apps: Vec<Value> = listing
        .split_whitespace()
        .filter(|app| is_app_ref(app) && REF_RE.is_match(app))
        .map(|app| json!({ "app_id": app }))
        .collect();
    json!({ "updates": apps, "ts": now() })
}

/// installed.json, then updates.json: remote-ls can hang on a flaky
/// network, so it gets 20 seconds.
pub fn refresh(state: &StateDir, flatpak: &str) -> io::Result<()> {
    let home = std::env::var_os("HOME").unwrap_or_default();
    let icons = Path::new(&home).join(".local/share/flatpak/exports/share/icons/hicolor");
    let listing = stdout_of(Command::new(flatpak).args([
        "--user",
        "list",
        "--app",
        "--columns=application,version,name",
    ]));
    state.write_json("installed.json", &installed(&listing, &icons))?;

    let listing = stdout_of(Command::new("timeout").args([
        "20",
        flatpak,
        "--user",
        "remote-ls",
        "--updates",
        "--columns=application",
    ]));
    state.write_json("updates.json", &updates(&listing))
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;
    use std::fs;
    use std::os::unix::fs::PermissionsExt;

    /// A stand-in flatpak: prints `output` (with \r redraws) and exits `code`.
    fn fake_flatpak(dir: &Path, output: &str, code: i32) -> String {
        let path = dir.join("flatpak");
        fs::write(
            &path,
            format!("#!/bin/sh\nprintf '{output}'\n[ -t 1 ] || echo NOT-A-TTY\nexit {code}\n"),
        )
        .unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
        path.to_str().unwrap().to_owned()
    }

    #[test]
    fn reports_progress_and_success() {
        let tmp = tempfile::tempdir().unwrap();
        let state = StateDir::open(&tmp.path().join("run")).unwrap();
        let flatpak = fake_flatpak(tmp.path(), "Updating 1/2… 50%%\\rUpdating 2/2… 100%%\\r", 0);
        let mut seen = Vec::new();
        let (ok, log) =
            run_on_pty(&flatpak, &[], |redraw| seen.push(progress::percent(redraw))).unwrap();
        assert!(ok);
        assert!(!String::from_utf8_lossy(&log).contains("NOT-A-TTY"));
        assert_eq!(&seen[..2], [Some(25), Some(100)]);

        run_op(&state, &flatpak, Verb::Update, "org.x.Y").unwrap();
        let record = state.read_progress("org.x.Y").unwrap();
        assert_eq!(record["state"], "done");
        assert_eq!(record["percent"], 100);
        assert!(state.path().join("installed.json").is_file());
        assert!(state.path().join("updates.json").is_file());
    }

    #[test]
    fn records_why_flatpak_failed() {
        let tmp = tempfile::tempdir().unwrap();
        let state = StateDir::open(&tmp.path().join("run")).unwrap();
        let flatpak = fake_flatpak(tmp.path(), "error: No remote refs found\\n", 1);
        run_op(&state, &flatpak, Verb::Uninstall, "org.x.Y").unwrap();
        let record = state.read_progress("org.x.Y").unwrap();
        assert_eq!(record["state"], "failed");
        assert_eq!(record["verb"], "uninstall");
        assert_eq!(record["error"], "No remote refs found");
    }

    #[test]
    fn records_a_flatpak_that_cannot_start() {
        let tmp = tempfile::tempdir().unwrap();
        let state = StateDir::open(&tmp.path().join("run")).unwrap();
        let missing = tmp.path().join("no-flatpak");
        run_op(&state, missing.to_str().unwrap(), Verb::Install, "org.x.Y").unwrap();
        assert_eq!(state.progress_state("org.x.Y").as_deref(), Some("failed"));
    }

    #[test]
    fn cancel_keeps_a_finished_result() {
        let tmp = tempfile::tempdir().unwrap();
        let state = StateDir::open(&tmp.path().join("run")).unwrap();
        let flatpak = fake_flatpak(tmp.path(), "", 0);
        let write = |s: &str, verb: &str| {
            state
                .write_progress(&Progress {
                    app_id: "org.x.Y",
                    verb,
                    state: s,
                    percent: 100,
                    error: "",
                })
                .unwrap();
        };
        write("done", "install");
        cancel(&state, &flatpak, "org.x.Y").unwrap();
        assert_eq!(state.progress_state("org.x.Y").as_deref(), Some("done"));

        write("installing", "update");
        cancel(&state, &flatpak, "org.x.Y").unwrap();
        let record = state.read_progress("org.x.Y").unwrap();
        assert_eq!(record["state"], "cancelled");
        assert_eq!(record["verb"], "update");

        cancel(&state, &flatpak, "org.new.App").unwrap();
        assert_eq!(
            state.read_progress("org.new.App").unwrap()["verb"],
            "install"
        );
    }

    #[test]
    fn lists_installed_apps_with_icons() {
        let tmp = tempfile::tempdir().unwrap();
        let icon = tmp.path().join("256x256/apps/org.x.Y.png");
        fs::create_dir_all(icon.parent().unwrap()).unwrap();
        fs::write(&icon, "png").unwrap();
        let value = installed("org.x.Y\t1.0\tWhy \"Y\"\norg.a.B\t\tB\n\n", tmp.path());
        let apps = value["installed"].as_array().unwrap();
        assert_eq!(apps.len(), 2);
        assert_eq!(apps[0]["name"], "Why \"Y\"");
        assert_eq!(apps[0]["icon"], format!("file://{}", icon.display()));
        assert_eq!(apps[1]["version"], "");
        assert_eq!(apps[1]["icon"], "");
    }

    #[test]
    fn lists_updates_without_extensions() {
        let value = updates("org.x.Y\norg.x.Y.Locale\norg.a.B.Debug\norg.c.D\n");
        let ids: Vec<_> = value["updates"]
            .as_array()
            .unwrap()
            .iter()
            .map(|u| u["app_id"].as_str().unwrap())
            .collect();
        assert_eq!(ids, ["org.x.Y", "org.c.D"]);
    }

    /// Offline, flatpak prints only terminal escapes; they are not apps.
    #[test]
    fn ignores_terminal_escapes() {
        assert_eq!(updates("\u{1b}[?25h")["updates"], json!([]));
        let value = installed("\u{1b}[?25h\norg.x.Y\t1.0\tY\n", Path::new("/nonexistent"));
        assert_eq!(value["installed"].as_array().unwrap().len(), 1);
    }
}
