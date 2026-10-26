//! The warm runner pool: spare marathon-app-runners started ahead,
//! libraries loaded and Wayland connected, inside a neutral sandbox,
//! waiting on stdin for the app they become. A spare either sees the media
//! folders or not, and becomes only an app that needs the same.

use std::collections::HashMap;
use std::io::Write as _;
use std::pin::Pin;
use std::process::{ChildStdin, Command, Stdio};
use std::time::{Duration, Instant};

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

use super::{Launch, Map, Qt, Tasks};
use crate::{io, log, sandbox};

/// A spare alive this long had finished starting and was warm.
const HEALTHY: Duration = Duration::from_secs(30);
/// A replacement waits for the adopted app to finish starting: a spare
/// spends seconds of CPU loading Qt and Mesa.
const REFILL_DELAY: Duration = Duration::from_secs(8);
const RECENT: usize = 5;

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
    /// Spares told to leave (EOF on stdin), by pid: their sandbox's socket.
    retired: HashMap<i64, String>,
}

pub(super) fn refill_later(qt: Qt, after: Duration) {
    io::spawn(async move {
        async_io::Timer::after(after).await;
        qt.queue(super::qobject::Tasks::refill_spares).ok();
    });
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

    pub(super) fn refill_spares(mut self: Pin<&mut Self>) {
        if let Some(at) = self.pool.retry_after {
            let wait = at.saturating_duration_since(Instant::now());
            if !wait.is_zero() {
                return refill_later(self.qt_thread(), wait);
            }
        }
        let wanted = self.wanted_spares();
        for (i, storage) in wanted.iter().enumerate() {
            if self.pool.spares[slot(*storage)].is_some() {
                continue;
            }
            // One at a time: a spare spends seconds of CPU warming up.
            if self.as_mut().spawn_spare(*storage) && i + 1 < wanted.len() {
                refill_later(self.qt_thread(), REFILL_DELAY);
            }
            return;
        }
    }

    fn spawn_spare(mut self: Pin<&mut Self>, storage: bool) -> bool {
        if self.pool.spares[slot(storage)].is_some() || sandbox::bwrap().is_none() {
            return false;
        }
        if self.pool.failures >= 3 {
            log::warn("tasks", "runner pool off after repeated spare failures");
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
        let child = Command::new(program)
            .args(args)
            .env_remove("QT_NO_BUILTIN_SELECTORS")
            .env_remove("GST_REGISTRY_UPDATE")
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::inherit())
            .spawn();
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
            }
            refill_later(self.qt_thread(), delay);
        } else if let Some(instance) = self.as_mut().rust_mut().pool.retired.remove(&pid) {
            self.as_mut()
                .sandbox_socket_closed(&QString::from(&instance));
            refill_later(self.qt_thread(), REFILL_DELAY);
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
        // The language may have changed since the spare started.
        for key in ["LANG", "LANGUAGE"] {
            if let Ok(value) = std::env::var(key) {
                grants.insert(key.into(), value.into());
            }
        }
        for (key, value) in env {
            let key = key.to_string();
            if key.starts_with("MARATHON_PERM_") {
                grants.insert(
                    key,
                    value
                        .value::<QString>()
                        .map(|v| v.to_string())
                        .unwrap_or_default()
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
        refill_later(self.qt_thread(), REFILL_DELAY);
        true
    }
}
