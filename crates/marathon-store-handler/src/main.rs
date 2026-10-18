//! Marathon App Store URL-scheme handler, invoked as
//! `xdg-open marathon-store://<verb>/<arg>`.
//!
//! Only `flathub` is used, refs must look like Flathub app ids, flatpak runs
//! with a fixed argv, and per-app state files are written atomically.

mod notice;
mod ops;
mod progress;
mod request;
mod state;

use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Command, ExitCode};

use request::{Request, Verb};
use state::StateDir;

const FLATPAK: &str = "flatpak";

#[allow(
    clippy::print_stderr,
    reason = "the handler's only diagnostics channel"
)]
fn fail(message: &str, code: u8) -> ExitCode {
    eprintln!("marathon-store-handler: {message}");
    ExitCode::from(code)
}

fn call_shell(path: &str, interface: &str, method: &str, arg: &str) -> zbus::Result<()> {
    zbus::blocking::Connection::session()?.call_method(
        Some("org.marathonos.Shell"),
        path,
        Some(interface),
        method,
        &(arg,),
    )?;
    Ok(())
}

/// xdg-open runs the handler inside the calling app's sandbox, where the
/// home is a private tmpfs and systemd won't take requests from the
/// sandbox's PID namespace. There, PID 1 is bwrap: the URL goes to the
/// shell, which checks the caller holds the "system" permission and runs
/// the handler from outside. In the session, the handler re-runs itself as a
/// transient unit so the work outlives xdg-open and stays out of the shell's
/// process tree; jobs get one named unit per app, so cancel can stop it and
/// a second install of the same app is refused while the first runs.
fn relaunch(url: &str, request: &Request) -> ExitCode {
    let pid1 = std::fs::read_to_string("/proc/1/comm").unwrap_or_default();
    if pid1.trim() != "systemd" {
        return match call_shell(
            "/org/marathonos/Shell/AppStore",
            "org.marathonos.Shell.AppStore1",
            "RunStoreUrl",
            url,
        ) {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => fail(&format!("shell refused the request: {e}"), 1),
        };
    }
    let handler = match std::env::current_exe() {
        Ok(path) => path,
        Err(e) => return fail(&e.to_string(), 1),
    };
    let mut cmd = Command::new("systemd-run");
    cmd.args(["--user", "--quiet", "--collect"]);
    if request.verb.is_job() {
        cmd.arg(format!("--unit={}", ops::job_unit(&request.arg)));
    }
    let err = cmd
        .arg("--setenv=MARATHON_STORE_UNIT=1")
        .arg(handler)
        .arg(url)
        .exec();
    fail(&format!("systemd-run: {err}"), 1)
}

fn runtime_dir() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR").map_or_else(
        || PathBuf::from(format!("/run/user/{}", nix::unistd::getuid())),
        PathBuf::from,
    )
}

/// Runs a verb inside its transient unit, in the foreground: systemd kills a
/// unit's leftover processes once its main process exits.
fn run(request: &Request) -> std::io::Result<()> {
    let state = || StateDir::open(&runtime_dir());
    match request.verb {
        Verb::Install | Verb::Update | Verb::Uninstall => {
            let state = state()?;
            let name = Some(request.name.clone())
                .filter(|name| !name.is_empty())
                .or_else(|| state.installed_name(&request.arg))
                .unwrap_or_else(|| request.arg.clone());
            let notice = notice::Notice::for_job(request.verb, &name);
            ops::run_op(&state, FLATPAK, request.verb, &request.arg, notice)
        }
        Verb::UpdateAll => ops::update_all(&state()?, FLATPAK, &std::env::current_exe()?),
        Verb::Cancel => ops::cancel(&state()?, FLATPAK, &request.arg),
        Verb::RefreshState => ops::refresh(&state()?, FLATPAK),
        // Launch through the shell like a home-screen tap, so the app gets
        // the compositor's socket and a place in the task switcher.
        Verb::Open => call_shell(
            "/org/marathonos/Shell/Navigation",
            "org.marathonos.Shell.Navigation1",
            "LaunchApp",
            &request.arg,
        )
        .map_err(std::io::Error::other),
    }
}

fn main() -> ExitCode {
    let url = std::env::args().nth(1).unwrap_or_default();
    let request = match request::parse(&url) {
        Ok(request) => request,
        Err(rejection) => {
            return fail(&rejection.message(&url), rejection.exit_code());
        }
    };
    if std::env::var_os("MARATHON_STORE_UNIT").is_none() {
        return relaunch(&url, &request);
    }
    match run(&request) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => fail(&e.to_string(), 1),
    }
}
