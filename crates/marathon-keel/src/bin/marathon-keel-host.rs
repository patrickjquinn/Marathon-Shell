//! Runs a native Keel app (a Sailfish app rebuilt on Keel's sailfishapp)
//! under a Keel host, as marathon-app-runner does for QML apps.

use std::path::PathBuf;
use std::process::{Command, ExitCode};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use clap::Parser;
use marathon_keel::{caller_is_shell, launch, runner_name, sailjail, Host, RUNNER_PATH};
use marathon_rt::{io, log};
use zbus::message::Header;

#[derive(Parser)]
#[command(about = "Runs a native Keel app under a Keel host")]
struct Args {
    #[arg(long)]
    app_id: Option<String>,
    #[arg(long, default_value_t = 160)]
    dpi: i32,
    /// The app's Sailjail permissions, comma-separated: run it in a sandbox
    /// built from them.
    #[arg(long, value_delimiter = ',')]
    sailjail: Option<Vec<String>>,
    #[arg(long, default_value = "")]
    org: String,
    #[arg(long, default_value = "")]
    app: String,
    #[arg(last = true, required = true)]
    command: Vec<String>,
}

/// keel-shell's close grace (PROTOCOL.md section 4).
const GRACE: Duration = Duration::from_secs(3);

/// The shell's per-app calls, as the runner serves them: what the shell
/// shows of the app becomes the Keel host's Active and `CoverStatus`.
struct Lifecycle1(Host);

#[zbus::interface(name = "org.marathonos.AppRunner.Lifecycle1")]
impl Lifecycle1 {
    async fn set_active(
        &self,
        active: bool,
        #[zbus(header)] h: Header<'_>,
    ) -> zbus::fdo::Result<()> {
        caller_is_shell(&h).await?;
        self.0.set_active(active);
        Ok(())
    }

    async fn set_cover_status(
        &self,
        status: i32,
        #[zbus(header)] h: Header<'_>,
    ) -> zbus::fdo::Result<()> {
        caller_is_shell(&h).await?;
        self.0.set_cover_status(status);
        Ok(())
    }
}

/// The shell freezes a backgrounded app's cgroup (marathon-app-<id>); a
/// frozen app never reads `CloseRequested`. A sandboxed app sits below bwrap.
fn thaw(pid: u32, depth: u8) {
    let cgroup = std::fs::read_to_string(format!("/proc/{pid}/cgroup")).unwrap_or_default();
    if let Some(path) = cgroup.lines().next().and_then(|l| l.strip_prefix("0::")) {
        if path
            .rsplit('/')
            .next()
            .is_some_and(|d| d.starts_with("marathon-app-"))
        {
            std::fs::write(format!("/sys/fs/cgroup{path}/cgroup.freeze"), "0").ok();
            return;
        }
    }
    if depth < 3 {
        let children =
            std::fs::read_to_string(format!("/proc/{pid}/task/{pid}/children")).unwrap_or_default();
        for child in children.split_whitespace().filter_map(|c| c.parse().ok()) {
            thaw(child, depth + 1);
        }
    }
}

fn signal(pid: u32, signal: i32) {
    if let Ok(pid) = i32::try_from(pid) {
        // SAFETY: kill(2) takes plain integers.
        unsafe { libc::kill(pid, signal) };
    }
}

fn main() -> ExitCode {
    let args = Args::parse();
    let runtime = PathBuf::from(std::env::var("XDG_RUNTIME_DIR").unwrap_or_default());
    let app_id = args.app_id.clone().unwrap_or_default();
    let activate = app_id.clone();
    let host = match Host::start(
        &runtime,
        args.dpi,
        Arc::new(move || launch(activate.clone())),
        Arc::new(|| {}),
    ) {
        Ok(host) => host,
        Err(e) => {
            log::warn(
                "marathon-keel-host",
                format_args!("cannot start the Keel host: {e}"),
            );
            return ExitCode::FAILURE;
        }
    };

    let Some((program, rest)) = args.command.split_first() else {
        return ExitCode::from(2);
    };
    let mut command = Command::new(program);
    command.args(rest);
    let bwrap = std::env::var_os("PATH").and_then(|p| {
        std::env::split_paths(&p)
            .map(|d| d.join("bwrap"))
            .find(|p| p.is_file())
    });
    if let (Some(permissions), Some(bwrap)) = (&args.sailjail, bwrap) {
        let home = std::env::var("HOME").unwrap_or_default();
        for base in ["/.local/share/", "/.cache/", "/.config/"] {
            std::fs::create_dir_all(format!("{home}{base}{}/{}", args.org, args.app)).ok();
        }
        command = Command::new(bwrap);
        command
            .args(sailjail::bwrap_args(
                permissions,
                &args.org,
                &args.app,
                &home,
                &runtime.to_string_lossy(),
            ))
            .arg("--")
            .arg(program)
            .args(rest);
    }
    command.envs(host.environment());

    if !app_id.is_empty() {
        let lifecycle = Lifecycle1(host.clone());
        let name = runner_name(&app_id);
        io::spawn(async move {
            let served = async {
                let bus = io::session_bus().await?;
                bus.object_server().at(RUNNER_PATH, lifecycle).await?;
                bus.request_name(name.as_str()).await
            };
            if let Err(e) = served.await {
                log::warn(
                    "marathon-keel-host",
                    format_args!("cannot register {name}: {e}"),
                );
            }
        });
    }

    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(e) => {
            log::warn(
                "marathon-keel-host",
                format_args!("cannot start {program}: {e}"),
            );
            return ExitCode::FAILURE;
        }
    };

    // SIGTERM: CloseRequested, then the grace, then SIGTERM and SIGKILL.
    let exited = Arc::new(AtomicBool::new(false));
    if let Ok(mut signals) = signal_hook::iterator::Signals::new([signal_hook::consts::SIGTERM]) {
        let (pid, exited, host) = (child.id(), Arc::clone(&exited), host.clone());
        std::thread::spawn(move || {
            if signals.forever().next().is_none() {
                return;
            }
            thaw(pid, 0);
            host.request_close();
            for sig in [libc::SIGTERM, libc::SIGKILL] {
                std::thread::sleep(GRACE);
                if exited.load(Ordering::Relaxed) {
                    return;
                }
                signal(pid, sig);
            }
        });
    }

    let code = child.wait().ok().and_then(|s| s.code()).unwrap_or(1);
    exited.store(true, Ordering::Relaxed);
    host.close();
    ExitCode::from(u8::try_from(code).unwrap_or(1))
}
