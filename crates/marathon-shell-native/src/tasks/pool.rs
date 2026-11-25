//! The warm runner pool: spare marathon-app-runners started ahead,
//! libraries loaded and Wayland connected, inside a neutral sandbox,
//! waiting on stdin for the app they become. A spare either sees the media
//! folders or not, and becomes only an app that needs the same.

use std::collections::HashMap;
use std::io::Write as _;
use std::os::unix::process::CommandExt as _;
use std::pin::Pin;
use std::process::{ChildStdin, Command, Stdio};
use std::time::{Duration, Instant};

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

use super::{Launch, Map, Tasks};
use crate::{io, log, sandbox};

/// A spare alive this long had finished starting and was warm.
const HEALTHY: Duration = Duration::from_secs(30);
/// A replacement waits for the adopted app to finish starting: a spare
/// spends seconds of CPU loading Qt and Mesa. Its window mapping is that
/// finish, and the refill starts then ([`REFILL_SETTLE`] after); this is
/// for a window that never maps.
const REFILL_DELAY: Duration = Duration::from_secs(8);
/// After an app's window maps: its first frames are drawn. On the Q25 a
/// spare then warms in 0.7 s, where the fixed 8 s left an app of the same
/// kind launched in that time to start cold.
const REFILL_SETTLE: Duration = Duration::from_millis(500);
const RECENT: usize = 5;
/// Spares that die before getting warm this many times turn the pool off.
const MAX_FAILURES: u32 = 3;

struct Spare {
    stdin: Option<ChildStdin>,
    pid: i64,
    instance: String,
    started: Instant,
}

#[derive(Default)]
pub(super) struct Pool {
    /// Plain, then storage.
    spares: [Option<Spare>; 2],
    /// Whether each of the last few launches the pool could serve needed
    /// storage, oldest first.
    recent: Vec<bool>,
    failures: u32,
    healthy_deaths: u32,
    retry_after: Option<Instant>,
    /// The one refill timer pending.
    refill_at: Option<Instant>,
    /// Spares told to leave (EOF on stdin), by pid: their sandbox's socket.
    retired: HashMap<i64, String>,
}

/// The build's runner beside the shell, else the installed one.
pub(super) fn runner_path() -> String {
    let built = std::env::current_exe().ok().and_then(|exe| {
        exe.parent()
            .map(|d| d.join("../tools/marathon-app-runner/marathon-app-runner"))
    });
    built.filter(|p| p.exists()).map_or_else(
        || "marathon-app-runner".to_owned(),
        |p| p.to_string_lossy().into_owned(),
    )
}

fn slot(storage: bool) -> usize {
    usize::from(storage)
}

impl Tasks {
    /// With two spares, one of each shape; with one, the shape most of the
    /// last few launches needed, ties to the latest, storage before any.
    fn wanted_spares(&self) -> Vec<bool> {
        let count = self.device.runner_pool;
        if count <= 0 {
            return Vec::new();
        }
        if count >= 2 {
            return vec![true, false];
        }
        let recent = &self.pool.recent;
        let Some(&last) = recent.last() else {
            return vec![true];
        };
        let storage = recent.iter().filter(|s| **s).count();
        let plain = recent.len() - storage;
        vec![if storage == plain {
            last
        } else {
            storage > plain
        }]
    }

    /// One refill timer at a time: a later request waits for the pending
    /// one (which re-arms as needed), an earlier one replaces it.
    pub(super) fn refill_later(mut self: Pin<&mut Self>, after: Duration) {
        let at = Instant::now() + after;
        if self.pool.refill_at.is_some_and(|due| due <= at) {
            return;
        }
        self.as_mut().rust_mut().pool.refill_at = Some(at);
        let qt = self.qt_thread();
        io::spawn(async move {
            async_io::Timer::after(after).await;
            qt.queue(move |obj| obj.refill_due(at)).ok();
        });
    }

    fn refill_due(mut self: Pin<&mut Self>, at: Instant) {
        if self.pool.refill_at != Some(at) {
            return;
        }
        self.as_mut().rust_mut().pool.refill_at = None;
        self.refill_spares();
    }

    /// A window mapped: an empty spare slot is refilled shortly.
    pub(super) fn refill_after_map(mut self: Pin<&mut Self>) {
        if self.pool.failures >= MAX_FAILURES {
            return;
        }
        let empty = self
            .wanted_spares()
            .iter()
            .any(|s| self.pool.spares[slot(*s)].is_none());
        if empty {
            self.as_mut().refill_later(REFILL_SETTLE);
        }
    }

    pub(super) fn refill_spares(mut self: Pin<&mut Self>) {
        if let Some(at) = self.pool.retry_after {
            let wait = at.saturating_duration_since(Instant::now());
            if !wait.is_zero() {
                return self.refill_later(wait);
            }
        }
        let wanted = self.wanted_spares();
        for (i, storage) in wanted.iter().enumerate() {
            if self.pool.spares[slot(*storage)].is_some() {
                continue;
            }
            // One at a time: a spare spends seconds of CPU warming up.
            if self.as_mut().spawn_spare(*storage) && i + 1 < wanted.len() {
                self.as_mut().refill_later(REFILL_DELAY);
            }
            return;
        }
    }

    fn spawn_spare(mut self: Pin<&mut Self>, storage: bool) -> bool {
        if self.pool.spares[slot(storage)].is_some() || sandbox::bwrap().is_none() {
            return false;
        }
        if self.pool.failures >= MAX_FAILURES {
            return false;
        }
        let instance = super::launch_uuid();
        let mut runner = self.runner("", &[], storage);
        let Some(socket) = self.as_mut().open_sandbox_socket("", &instance) else {
            return false;
        };
        runner.wayland_socket = socket;
        let command = sandbox::argv(&runner, &runner_path());
        let Some((program, args)) = command.split_first() else {
            return false;
        };
        // Shell-only start-up shortcuts (see WaylandCompositor::launchApp).
        let mut command = Command::new(program);
        command
            .args(args)
            .env_remove("QT_NO_BUILTIN_SELECTORS")
            .env_remove("GST_REGISTRY_UPDATE")
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::inherit());
        // The sandbox must not inherit the shell's descriptors: a GPU
        // driver dup()s the compositor's DRM render client without
        // O_CLOEXEC, and its buffer handles are guessable.
        // SAFETY: only an async-signal-safe syscall runs between fork and exec.
        unsafe {
            command.pre_exec(|| {
                // Marked rather than closed: std's own exec-error pipe stays open until exec.
                if libc::syscall(
                    libc::SYS_close_range,
                    3,
                    u32::MAX,
                    libc::CLOSE_RANGE_CLOEXEC,
                ) == 0
                {
                    Ok(())
                } else {
                    Err(std::io::Error::last_os_error())
                }
            });
        }
        let child = command.spawn();
        let mut child = match child {
            Ok(child) => child,
            Err(e) => {
                log::warn("tasks", format_args!("spare runner: {e}"));
                self.as_mut()
                    .sandbox_socket_closed(&QString::from(&instance));
                return false;
            }
        };
        let pid = i64::from(child.id());
        let stdin = child.stdin.take();
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            let code = child.wait().map_or(-1, |s| s.code().unwrap_or(-1));
            qt.queue(move |obj| obj.spare_exited(storage, pid, code))
                .ok();
        });
        self.as_mut().rust_mut().pool.spares[slot(storage)] = Some(Spare {
            stdin,
            pid,
            instance,
            started: Instant::now(),
        });
        true
    }

    /// Only a spare that never got warm counts against the pool; one taken
    /// later (oomd reaping the idlest process) backs the refill off.
    fn spare_exited(mut self: Pin<&mut Self>, storage: bool, pid: i64, code: i32) {
        let current = self.pool.spares[slot(storage)]
            .as_ref()
            .is_some_and(|s| s.pid == pid);
        if current {
            let Some(spare) = self.as_mut().rust_mut().pool.spares[slot(storage)].take() else {
                return;
            };
            let lived = spare.started.elapsed();
            let healthy = lived >= HEALTHY;
            log::warn(
                "tasks",
                format_args!(
                    "spare runner died unadopted, exit {code} after {} ms ({})",
                    lived.as_millis(),
                    if healthy { "healthy" } else { "early" }
                ),
            );
            self.as_mut()
                .sandbox_socket_closed(&QString::from(&spare.instance));
            let mut delay = Duration::from_secs(5);
            let mut rust = self.as_mut().rust_mut();
            if healthy {
                rust.pool.healthy_deaths += 1;
                delay =
                    Duration::from_secs((5u64 << (rust.pool.healthy_deaths - 1).min(5)).min(300));
                rust.pool.retry_after = Some(Instant::now() + delay);
            } else {
                rust.pool.failures += 1;
                if rust.pool.failures == MAX_FAILURES {
                    log::warn("tasks", "runner pool off after repeated spare failures");
                }
            }
            self.as_mut().refill_later(delay);
        } else if let Some(instance) = self.as_mut().rust_mut().pool.retired.remove(&pid) {
            self.as_mut()
                .sandbox_socket_closed(&QString::from(&instance));
            self.as_mut().refill_later(REFILL_DELAY);
        } else {
            self.app_closed(pid);
        }
    }

    /// A spare of a shape no longer wanted leaves: EOF on its stdin is its
    /// drain request.
    fn note_launch_shape(mut self: Pin<&mut Self>, storage: bool) {
        let mut rust = self.as_mut().rust_mut();
        rust.pool.recent.push(storage);
        if rust.pool.recent.len() > RECENT {
            rust.pool.recent.remove(0);
        }
        let wanted = self.wanted_spares();
        for shape in [false, true] {
            if wanted.contains(&shape) {
                continue;
            }
            let mut rust = self.as_mut().rust_mut();
            if let Some(spare) = rust.pool.spares[slot(shape)].take() {
                rust.pool.retired.insert(spare.pid, spare.instance);
            }
        }
    }

    /// Hands a warm spare the app: its id, route and grants, as one JSON
    /// line on its stdin. Registered first, so the cgroup and the CPU boost
    /// apply while it adopts.
    pub(super) fn adopt_spare(
        mut self: Pin<&mut Self>,
        storage: bool,
        mut launch: Launch,
        env: &Map,
    ) -> bool {
        self.as_mut().note_launch_shape(storage);
        let Some(spare) = self.pool.spares[slot(storage)].as_ref() else {
            return false;
        };
        let (pid, instance) = (spare.pid, spare.instance.clone());
        let mut grants = serde_json::Map::new();
        grants.insert(
            "MARATHON_USER_SCALE".into(),
            format!("{:.3}", self.device.user_scale).into(),
        );
        // The language may have changed since the spare started; empty unsets.
        for key in ["LANG", "LANGUAGE"] {
            grants.insert(key.into(), std::env::var(key).unwrap_or_default().into());
        }
        for (key, value) in env {
            let key = key.to_string();
            if key.starts_with("MARATHON_PERM_") {
                grants.insert(
                    key,
                    value
                        .value::<QString>()
                        .map_or_default(|v| v.to_string())
                        .into(),
                );
            }
        }
        let (route, params) = self.pending_route.clone().unwrap_or_default();
        let message = serde_json::json!({ "appId": launch.app_id, "route": route, "routeParams": params, "env": grants });
        launch.pid = pid;
        launch.sandbox_instance.clone_from(&instance);
        let app_id = launch.app_id.clone();
        self.as_mut()
            .sandbox_app_assigned(&QString::from(&instance), &QString::from(&app_id));
        self.as_mut().rust_mut().active_by_pid.insert(pid, launch);
        self.as_mut().register_pid(pid, &app_id);
        let line = format!("{message}\n");
        let mut rust = self.as_mut().rust_mut();
        let written = rust.pool.spares[slot(storage)]
            .as_mut()
            .and_then(|s| s.stdin.as_mut())
            .is_some_and(|stdin| {
                stdin
                    .write_all(line.as_bytes())
                    .and_then(|()| stdin.flush())
                    .is_ok()
            });
        if !written {
            log::warn(
                "tasks",
                format_args!("pool adopt write failed for {app_id}"),
            );
            rust.active_by_pid.remove(&pid);
            return false;
        }
        if let Some(spare) = rust.pool.spares[slot(storage)].take() {
            // Its stdin stays open: closing it is a spare's drain request.
            std::mem::forget(spare.stdin);
        }
        rust.pending_route = None;
        self.as_mut().refill_later(REFILL_DELAY);
        true
    }
}
