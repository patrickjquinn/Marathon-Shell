//! Launching: an app comes forward if it runs, else it starts, from a warm
//! spare where it can; its process and its windows are matched to it as
//! they come.

use std::fs;
use std::path::Path;
use std::pin::Pin;
use std::time::{Duration, Instant};

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QString, QVariant};

use super::{dbus, later, pool, q, Launch, Map, Tasks};
use crate::apps::{self, App};
use crate::{desktop, io, log, sandbox};

/// A launcher process (`waydroid app launch`) is not the app: its window
/// may come this long after it exits.
const EXITED_LAUNCH_GRACE: Duration = Duration::from_secs(30);
/// An app with no process of its own keeps its card this long after its
/// last window, for a replacement.
const WINDOW_GRACE: Duration = Duration::from_secs(1);
const EXPECT_WINDOW: Duration = Duration::from_secs(10);
/// A second tap within this of the first starts no second copy.
const LAUNCH_HOLD: Duration = Duration::from_secs(10);

/// Its process tree reaches `ancestor`.
pub(super) fn descends_from(pid: i64, ancestor: i64) -> bool {
    let mut cursor = pid;
    for _ in 0..64 {
        if cursor == ancestor {
            return true;
        }
        let Ok(stat) = fs::read_to_string(format!("/proc/{cursor}/stat")) else { return false };
        let Some(parent) = stat.rsplit_once(')').and_then(|(_, rest)| rest.split_whitespace().nth(1)).and_then(|p| p.parse::<i64>().ok()) else { return false };
        if parent <= 1 {
            return false;
        }
        cursor = parent;
    }
    false
}

/// An entry kept off the grid (Waydroid's stock Android apps) still
/// launches by its id.
fn desktop_entry(app_id: &str) -> Option<App> {
    let dirs = std::env::var("XDG_DATA_DIRS").unwrap_or_else(|_| "/usr/local/share:/usr/share".to_owned());
    let found = std::iter::once(marathon_rt::dirs::data()).chain(dirs.split(':').map(std::path::PathBuf::from)).map(|d| d.join("applications").join(format!("{app_id}.desktop"))).find(|p| p.is_file())?;
    let map = desktop::parse(&QString::from(&*found.to_string_lossy()));
    let text = |k: &str| map.get(&q(k)).and_then(|v| v.value::<QString>()).map(|s| s.to_string()).unwrap_or_default();
    Some(App { id: text("id"), name: text("name"), icon: text("icon"), kind: text("type"), exec: text("exec"), ..App::default() })
}

/// The app's Keel Actions manifest, so its runner owns
/// `org.marathonos.<appId>`.
pub(super) fn serves_keel_actions(app_id: &str) -> bool {
    if app_id.is_empty() {
        return false;
    }
    let dirs = std::env::var("XDG_DATA_DIRS").unwrap_or_else(|_| "/usr/local/share:/usr/share".to_owned());
    let file = format!("keel/actions/org.marathonos.{app_id}.json");
    std::iter::once(marathon_rt::dirs::data()).chain(dirs.split(':').map(std::path::PathBuf::from)).any(|d| d.join(&file).is_file())
}

impl Tasks {
    /// What it knows of the app: the grid's entry, its card, its desktop entry.
    fn resolve(&self, app_id: &str) -> Option<App> {
        if app_id.is_empty() {
            return None;
        }
        if let Some(app) = apps::get(app_id) {
            return Some(app);
        }
        if let Some(task) = self.task(app_id) {
            let name = if task.title.is_empty() { app_id.to_owned() } else { task.title.clone() };
            let kind = if task.kind.is_empty() { "native".to_owned() } else { task.kind.clone() };
            return Some(App { id: app_id.to_owned(), name, icon: task.icon.clone(), kind, ..App::default() });
        }
        desktop_entry(app_id)
    }

    pub(crate) fn can_launch(&self, app_id: &QString) -> bool {
        self.resolve(&app_id.to_string()).is_some()
    }

    pub(super) fn is_app_launching(&self, app_id: &QString) -> bool {
        self.launching.contains(&app_id.to_string())
    }

    pub(super) fn pid_for(&self, app_id: &str) -> i64 {
        self.app_to_pid.get(app_id).copied().unwrap_or(-1)
    }

    pub(super) fn pid_for_app_id(&self, app_id: &QString) -> i64 {
        self.pid_for(&app_id.to_string())
    }

    pub(super) fn app_for_pid(&self, pid: i64) -> String {
        self.pid_to_app.get(&pid).cloned().unwrap_or_default()
    }

    pub(super) fn app_id_for_pid(&self, pid: i64) -> QString {
        q(&self.app_for_pid(pid))
    }

    fn host_pid(&self, app_id: &str) -> i64 {
        self.active_by_pid.iter().find(|(_, l)| l.app_id == app_id && desktop::is_keel_hosted(&q(&l.command))).map_or(-1, |(pid, _)| *pid)
    }

    pub(super) fn is_keel_host(&self, app_id: &str) -> bool {
        self.host_pid(app_id) > 0
    }

    pub(super) fn is_keel_host_app(&self, app_id: &QString) -> bool {
        self.is_keel_host(&app_id.to_string())
    }

    /// The process to SIGTERM to stop the app: a hosted app's host, which
    /// turns SIGTERM into `CloseRequested`.
    pub(super) fn termination_pid(&self, app_id: &str) -> i64 {
        let host = self.host_pid(app_id);
        if host > 0 {
            host
        } else {
            self.pid_for(app_id)
        }
    }

    pub(super) fn is_marathon_app(app_id: &str) -> bool {
        apps::get(app_id).is_some_and(|a| a.kind == "marathon")
    }

    #[allow(clippy::unused_self, reason = "a QML invokable")]
    pub(super) fn set_cover_visible(&self, app_id: &QString, visible: bool) {
        if !app_id.is_empty() {
            dbus::runner(&app_id.to_string(), "SetCoverStatus", (i32::from(visible),));
        }
    }

    /// A hosted Keel app learns from this whether it is in front; a
    /// runner takes it from its window.
    pub(super) fn set_app_active(&self, app_id: &str, active: bool) {
        if self.is_keel_host(app_id) {
            dbus::runner(app_id, "SetActive", (active,));
        }
    }

    pub(super) fn register_pid(mut self: Pin<&mut Self>, pid: i64, app_id: &str) {
        if pid <= 0 || app_id.is_empty() {
            return;
        }
        let mut rust = self.as_mut().rust_mut();
        rust.pid_to_app.insert(pid, app_id.to_owned());
        rust.app_to_pid.insert(app_id.to_owned(), pid);
        crate::gate::remember_pid(pid, app_id);
        self.as_mut().pid_registered(pid, &q(app_id));
        self.pid_seen(pid, app_id);
    }

    pub(crate) fn launch_app(self: Pin<&mut Self>, app_id: &QString) -> bool {
        self.launch(&app_id.to_string())
    }

    pub(crate) fn launch_app_with_route(mut self: Pin<&mut Self>, app_id: &QString, route: &QString, params_json: &QString) -> bool {
        self.as_mut().rust_mut().pending_route = Some((route.to_string(), params_json.to_string()));
        let ok = self.as_mut().launch(&app_id.to_string());
        if !ok {
            self.as_mut().rust_mut().pending_route = None;
        }
        ok
    }

    fn take_route(mut self: Pin<&mut Self>) -> Option<(String, String)> {
        self.as_mut().rust_mut().pending_route.take().filter(|(r, _)| !r.is_empty())
    }

    pub(super) fn start_app_in_background(mut self: Pin<&mut Self>, app_id: &QString) -> bool {
        let id = app_id.to_string();
        if id.is_empty() {
            return false;
        }
        if self.pid_for(&id) > 0 || self.launching.contains(&id) || self.task(&id).is_some() {
            self.wake(&id);
            return true;
        }
        let mut rust = self.as_mut().rust_mut();
        rust.background_launches.insert(id.clone());
        rust.starting_in_background = true;
        let ok = self.as_mut().launch(&id);
        let mut rust = self.as_mut().rust_mut();
        rust.starting_in_background = false;
        if !ok {
            rust.background_launches.remove(&id);
        }
        ok
    }

    fn show(self: Pin<&mut Self>, app: &App, kind: &str, surface_id: i32) {
        self.show_requested(&q(&app.id), &q(&app.name), &q(&app.icon), &q(kind), surface_id);
    }

    fn open(self: Pin<&mut Self>, app: &App, restore: bool) {
        self.open_app_requested(&q(&app.id), &q(&app.name), &q(&app.icon), restore);
    }

    fn launched(mut self: Pin<&mut Self>, app: &App) {
        let id = q(&app.id);
        crate::permissions::with(move |p| p.request_declared_permissions(&id));
        if let Some((route, params)) = self.as_mut().take_route() {
            self.as_mut().route_for_running_app(&q(&app.id), &q(&route), &q(&params));
            dbus::deep_link(&app.id, &route, &params);
        }
        self.app_launch_completed(&q(&app.id), &q(&app.name));
    }

    pub(crate) fn launch(mut self: Pin<&mut Self>, app_id: &str) -> bool {
        let Some(mut app) = self.resolve(app_id) else {
            log::warn("tasks", format_args!("no app {app_id} to launch"));
            self.as_mut().app_launch_failed(&q(app_id), &q(app_id), &q("Invalid app object"));
            return false;
        };
        if app.kind.is_empty() {
            "marathon".clone_into(&mut app.kind);
        }
        let held = self.task(&app.id).filter(|t| t.surface_id >= 0).cloned();
        // Still starting in the background: show it as it maps.
        if !self.starting_in_background && held.is_none() && self.as_mut().rust_mut().background_launches.remove(&app.id) {
            self.as_mut().open(&app, false);
            let kind = app.kind.clone();
            self.as_mut().show(&app, &kind, -1);
            self.launched(&app);
            return true;
        }
        if self.launching.contains(&app.id) && held.is_none() {
            log::warn("tasks", format_args!("{} is already launching", app.id));
            return false;
        }
        // Running with a window: forward, not a second copy.
        if let Some(task) = held {
            self.as_mut().open(&app, true);
            self.as_mut().show(&app, &task.kind, task.surface_id);
            self.as_mut().rust_mut().launching.remove(&app.id);
            self.launched(&app);
            return true;
        }
        self.as_mut().rust_mut().launching.insert(app.id.clone());
        self.as_mut().app_launch_started(&q(&app.id), &q(&app.name));
        let native = app.kind == "native" || app.kind == "flatpak";
        // Running without a window: a second instance would only hand off
        // to it, so the running one is asked for a window.
        if native && self.pid_for(&app.id) > 0 && app.id.contains('.') {
            self.activate_running(app);
            return true;
        }
        if native {
            return self.launch_native(&app);
        }
        // A runner that never showed its window keeps the app's bus name,
        // which the next one could not take.
        if let Ok(stuck) = i32::try_from(self.pid_for(&app.id)) {
            if stuck > 0 {
                log::warn("tasks", format_args!("{} runner {stuck} never showed a window: replaced", app.id));
                // SAFETY: kill(2) takes plain integers.
                unsafe { libc::kill(stuck, libc::SIGKILL) };
            }
        }
        self.launch_marathon(&app)
    }

    fn launch_native(mut self: Pin<&mut Self>, app: &App) -> bool {
        if !self.background_launches.contains(&app.id) {
            self.as_mut().open(app, false);
            self.as_mut().show(app, "native", -1);
        }
        if !app.exec.is_empty() {
            let launch = Launch { app_id: app.id.clone(), name: app.name.clone(), icon: app.icon.clone(), kind: "native".to_owned(), command: app.exec.clone(), ..Launch::default() };
            self.as_mut().rust_mut().pending_by_command.insert(app.exec.clone(), launch);
            if app.exec.starts_with("waydroid app ") {
                self.as_mut().wake(&app.id);
                self.as_mut().after_android_boots(app.exec.clone());
            } else {
                self.as_mut().spawn_requested(&q(&app.exec), &Map::default());
            }
        }
        self.as_mut().rust_mut().launching.remove(&app.id);
        self.launched(app);
        true
    }

    /// `waydroid app launch` before Android has booted is dropped; with no
    /// session running it becomes the session, and Android stops with it.
    fn after_android_boots(mut self: Pin<&mut Self>, exec: String) {
        self.as_mut().rust_mut().after_android_boot.push(exec);
        if self.after_android_boot.len() > 1 {
            return;
        }
        self.as_mut().rust_mut().android_starting = true;
        self.as_mut().android_starting_changed();
        let qt = self.qt_thread();
        io::spawn(async move {
            dbus::wait_for_android().await;
            qt.queue(super::qobject::Tasks::android_booted).ok();
        });
    }

    fn android_booted(mut self: Pin<&mut Self>) {
        let waiting = std::mem::take(&mut self.as_mut().rust_mut().after_android_boot);
        self.as_mut().rust_mut().android_starting = false;
        self.as_mut().android_starting_changed();
        for exec in waiting {
            self.as_mut().spawn_requested(&q(&exec), &Map::default());
        }
    }

    /// `org.freedesktop.Application.Activate` on the desktop id; anything
    /// that does not answer it starts as before.
    fn activate_running(mut self: Pin<&mut Self>, app: App) {
        self.as_mut().wake(&app.id);
        let qt = self.qt_thread();
        io::spawn(async move {
            let activated = dbus::activate(&app.id).await;
            qt.queue(move |mut obj| {
                if !activated {
                    obj.launch_native(&app);
                    return;
                }
                obj.as_mut().open(&app, false);
                obj.as_mut().show(&app, "native", -1);
                obj.as_mut().rust_mut().launching.remove(&app.id);
                obj.launched(&app);
            })
            .ok();
        });
    }

    pub(super) fn runner(&self, app_id: &str, permissions: &[String], storage_spare: bool) -> sandbox::Runner {
        let d = &self.device;
        let (app_width, app_height) = if d.viewport_width > 0 && d.viewport_height > 0 { (d.viewport_width, d.viewport_height) } else { (d.runner_width, d.runner_height) };
        sandbox::Runner {
            app_id: app_id.to_owned(),
            permissions: permissions.to_vec(),
            requires_qt: Vec::new(),
            storage_spare,
            wayland_socket: String::new(),
            render_node: d.render_node.clone(),
            gpu_webgl: d.gpu_webgl,
            thumbnails: d.thumbnails.clone(),
            dpi: if d.dpi > 0.0 { d.dpi } else { 160.0 },
            user_scale: d.user_scale,
            screen_width: d.screen_width,
            screen_height: d.screen_height,
            app_width,
            app_height,
        }
    }

    /// The sandbox's own Wayland socket, from the compositor.
    pub(super) fn open_sandbox_socket(mut self: Pin<&mut Self>, app_id: &str, instance: &str) -> Option<String> {
        self.as_mut().sandbox_socket_requested(&q(app_id), &q(instance));
        let path = Path::new(&std::env::var("XDG_RUNTIME_DIR").unwrap_or_default()).join("marathon-sandbox").join(instance);
        path.exists().then(|| path.to_string_lossy().into_owned())
    }

    fn launch_marathon(mut self: Pin<&mut Self>, app: &App) -> bool {
        if !self.background_launches.contains(&app.id) {
            self.as_mut().open(app, false);
            self.as_mut().show(app, &app.kind, -1);
        }
        let mut runner = self.runner(&app.id, &app.permissions, false);
        let webengine = sandbox::uses_webengine(&runner);
        let mut env = sandbox::environment(&runner);
        // A spare can write every app's data: it takes only Marathon's own,
        // and not WebEngine's, whose environment is per app.
        if !sandbox::is_user_installed(&app.id) && !webengine {
            let storage = app.permissions.iter().any(|p| p == "storage");
            let launch = Launch { app_id: app.id.clone(), name: app.name.clone(), icon: app.icon.clone(), kind: app.kind.clone(), command: format!("pool-adopt {}", app.id), ..Launch::default() };
            if self.as_mut().adopt_spare(storage, launch, &env) {
                let qt = self.qt_thread();
                let id = app.id.clone();
                later(qt, LAUNCH_HOLD, move |mut obj| {
                    obj.as_mut().rust_mut().launching.remove(&id);
                });
                self.launched(app);
                return true;
            }
        }
        let mut instance = String::new();
        if sandbox::bwrap().is_some() {
            instance = super::launch_uuid();
            if let Some(socket) = self.as_mut().open_sandbox_socket(&app.id, &instance) { runner.wayland_socket = socket } else {
                log::warn("tasks", format_args!("no sandbox Wayland socket for {}", app.id));
                self.as_mut().rust_mut().launching.remove(&app.id);
                self.app_launch_failed(&q(&app.id), &q(&app.name), &q("No sandbox Wayland socket"));
                return false;
            }
        }
        let mut command = sandbox::command_line(&sandbox::argv(&runner, &pool::runner_path()));
        if let Some((route, params)) = self.as_mut().take_route() {
            command = format!("{command} --route \"{route}\"");
            env.insert(q("MARATHON_APP_ROUTE"), QVariant::from(&q(&route)));
            if !params.is_empty() {
                env.insert(q("MARATHON_APP_ROUTE_PARAMS"), QVariant::from(&q(&params)));
            }
        }
        let launch = Launch { app_id: app.id.clone(), name: app.name.clone(), icon: app.icon.clone(), kind: app.kind.clone(), command: command.clone(), sandbox_instance: instance, pid: -1 };
        self.as_mut().rust_mut().pending_by_command.insert(command.clone(), launch);
        self.as_mut().spawn_requested(&q(&command), &env);
        let id = app.id.clone();
        later(self.qt_thread(), LAUNCH_HOLD, move |mut obj| {
            obj.as_mut().rust_mut().launching.remove(&id);
        });
        let id = q(&app.id);
        crate::permissions::with(move |p| p.request_declared_permissions(&id));
        self.as_mut().app_launch_completed(&q(&app.id), &q(&app.name));
        true
    }

    pub(super) fn app_launched(mut self: Pin<&mut Self>, command: &QString, pid: i64) {
        let Some(mut launch) = self.as_mut().rust_mut().pending_by_command.remove(&command.to_string()) else { return };
        launch.pid = pid;
        let mut rust = self.as_mut().rust_mut();
        rust.pid_to_app.insert(pid, launch.app_id.clone());
        rust.app_to_pid.insert(launch.app_id.clone(), pid);
        rust.active_by_pid.insert(pid, launch);
    }

    pub(super) fn app_closed(mut self: Pin<&mut Self>, pid: i64) {
        let Some(launch) = self.as_mut().rust_mut().active_by_pid.remove(&pid) else { return };
        if !launch.sandbox_instance.is_empty() {
            self.as_mut().sandbox_socket_closed(&q(&launch.sandbox_instance));
        }
        self.as_mut().rust_mut().pid_to_app.remove(&pid);
        // The app's pid may be the sandbox's inner runner (matched by its
        // window), which died with the sandbox.
        let own_pid = self.pid_for(&launch.app_id);
        if own_pid == pid || (own_pid > 0 && !Path::new(&format!("/proc/{own_pid}")).exists()) {
            let mut rust = self.as_mut().rust_mut();
            rust.app_to_pid.remove(&launch.app_id);
            rust.pid_to_app.remove(&own_pid);
            crate::gate::forget_pid(own_pid);
            self.as_mut().pid_unregistered(own_pid, &q(&launch.app_id));
            self.as_mut().pid_gone(&launch.app_id);
        }
        // Exited before any window: a launcher, unless no window comes.
        if !self.windows.contains_key(&launch.app_id) && self.task(&launch.app_id).is_none() {
            let app_id = launch.app_id.clone();
            self.as_mut().rust_mut().exited_launches.insert(app_id.clone(), launch);
            later(self.qt_thread(), EXITED_LAUNCH_GRACE, move |mut obj| {
                if obj.exited_launches.get(&app_id).is_some_and(|l| l.pid == pid) {
                    obj.as_mut().rust_mut().exited_launches.remove(&app_id);
                    obj.finish_exit(&app_id);
                }
            });
            return;
        }
        self.finish_exit(&launch.app_id);
    }

    fn finish_exit(mut self: Pin<&mut Self>, app_id: &str) {
        self.as_mut().rust_mut().background_launches.remove(app_id);
        self.as_mut().close_task_of(app_id);
        self.as_mut().unregister(app_id);
        let gone = q(app_id);
        crate::permissions::with(move |p| p.dismiss_for_app(&gone));
        self.app_exited(&q(app_id));
    }

    pub(crate) fn expect_window(mut self: Pin<&mut Self>, app_id: &QString) -> bool {
        let id = app_id.to_string();
        self.as_mut().rust_mut().expected_windows.insert(id.clone(), Instant::now() + EXPECT_WINDOW);
        if self.task(&id).is_none_or(|t| t.surface_id < 0) {
            return false;
        }
        self.launch(&id);
        true
    }

    pub(super) fn close_app_windows(mut self: Pin<&mut Self>, app_id: &QString) -> i32 {
        let windows = self.windows.get(&app_id.to_string()).cloned().unwrap_or_default();
        for surface in &windows {
            self.as_mut().close_window_requested(*surface);
        }
        i32::try_from(windows.len()).unwrap_or(i32::MAX)
    }

    fn file_window(mut self: Pin<&mut Self>, app_id: &str, surface_id: i32) {
        let mut rust = self.as_mut().rust_mut();
        for windows in rust.windows.values_mut() {
            windows.retain(|s| *s != surface_id);
        }
        rust.windows.entry(app_id.to_owned()).or_default().push(surface_id);
    }

    /// Files the window under its launch and shows it, unless the launch
    /// was in the background.
    fn show_launch(mut self: Pin<&mut Self>, launch: &Launch, surface_id: i32) -> bool {
        let kind = if launch.kind.is_empty() { "native".to_owned() } else { launch.kind.clone() };
        if self.task(&launch.app_id).is_some() {
            self.as_mut().update_task_window(&launch.app_id, surface_id);
        } else {
            self.as_mut().add_task(&launch.app_id, &launch.name, &launch.icon, &kind, surface_id);
        }
        self.as_mut().file_window(&launch.app_id, surface_id);
        if self.as_mut().rust_mut().background_launches.remove(&launch.app_id) {
            return false;
        }
        self.show_requested(&q(&launch.app_id), &q(&launch.name), &q(&launch.icon), &q(&kind), surface_id);
        true
    }

    /// Android's own rule for an activity in front: in answer to the
    /// user's input on the app in front.
    fn take_front(mut self: Pin<&mut Self>, app_id: &str, name: &str, icon: &str, surface_id: i32) -> bool {
        self.as_mut().open_app_requested(&q(app_id), &q(name), &q(icon), false);
        self.show_requested(&q(app_id), &q(name), &q(icon), &q("native"), surface_id);
        true
    }

    #[allow(clippy::too_many_arguments, reason = "the compositor's view of the window")]
    pub(super) fn window_mapped(mut self: Pin<&mut Self>, pid: i64, client_pid: i64, xdg_app_id: &QString, title: &QString, sandbox_app_id: &QString, surface_id: i32, recent_input: bool) -> bool {
        let (sandboxed, title) = (sandbox_app_id.to_string(), title.to_string());
        let xdg = if sandboxed.is_empty() { xdg_app_id.to_string() } else { sandboxed.clone() };
        self.as_mut().rust_mut().window_clients.insert(surface_id, client_pid);
        // In answer to the user's touch on the app in front, from the same client.
        let front_surface = if self.app_window_open { self.task(&self.current_app_id).map_or(-1, |t| t.surface_id) } else { -1 };
        let mut front_input = recent_input && front_surface >= 0 && self.window_clients.get(&front_surface) == Some(&client_pid);
        if let Some(deadline) = self.expected_windows.get(&xdg).copied() {
            front_input |= Instant::now() < deadline;
            if Instant::now() >= deadline {
                self.as_mut().rust_mut().expected_windows.remove(&xdg);
            }
        }
        if pid > 0 {
            if let Some(launch) = self.active_by_pid.get(&pid).cloned() {
                if self.background_launches.contains(&launch.app_id) || launch.kind == "native" {
                    self.as_mut().register_pid(pid, &launch.app_id);
                }
                return self.show_launch(&launch, surface_id);
            }
            let parent = self.active_by_pid.iter().find(|(p, l)| **p > 0 && ((!sandboxed.is_empty() && l.app_id == sandboxed) || descends_from(pid, **p))).map(|(_, l)| l.clone());
            if let Some(launch) = parent {
                self.as_mut().register_pid(pid, &launch.app_id);
                return self.show_launch(&launch, surface_id);
            }
        }
        // Launched by another process (`waydroid app launch`), not the app.
        if !xdg.is_empty() {
            let mut launch = self.as_mut().rust_mut().exited_launches.remove(&xdg);
            let pending: Vec<String> = self.pending_by_command.iter().filter(|(_, l)| l.app_id == xdg).map(|(c, _)| c.clone()).collect();
            for command in pending {
                launch = self.as_mut().rust_mut().pending_by_command.remove(&command);
            }
            let active: Vec<i64> = self.active_by_pid.iter().filter(|(_, l)| l.app_id == xdg).map(|(p, _)| *p).collect();
            for p in active {
                let mut rust = self.as_mut().rust_mut();
                launch = rust.active_by_pid.remove(&p);
                rust.pid_to_app.remove(&p);
                if rust.app_to_pid.get(&xdg) == Some(&p) {
                    rust.app_to_pid.remove(&xdg);
                }
            }
            if let Some(launch) = launch {
                return self.show_launch(&launch, surface_id);
            }
            if let Some(task) = self.task(&xdg).cloned() {
                self.as_mut().update_task_window(&xdg, surface_id);
                self.as_mut().file_window(&xdg, surface_id);
                return front_input && self.take_front(&xdg, &task.title, &task.icon, surface_id);
            }
        }
        let app_id = if !xdg.is_empty() {
            xdg.clone()
        } else if !title.is_empty() {
            let slug: String = title.to_lowercase().chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '-' }).collect();
            format!("native-app-{}", slug.split('-').filter(|s| !s.is_empty()).collect::<Vec<_>>().join("-"))
        } else {
            format!("native-surface-{surface_id}")
        };
        let name = if !title.is_empty() { title } else if !xdg.is_empty() { xdg.clone() } else { app_id.clone() };
        let icon = apps::get(&xdg).map(|a| a.icon).filter(|i| !i.is_empty()).unwrap_or_else(|| if xdg.is_empty() { "application-x-executable".to_owned() } else { xdg.clone() });
        if self.task(&app_id).is_some() {
            self.as_mut().update_task_window(&app_id, surface_id);
        } else {
            self.as_mut().add_task(&app_id, &name, &icon, "native", surface_id);
        }
        self.as_mut().file_window(&app_id, surface_id);
        // Nobody launched it: a card. Waydroid re-creates a task's window
        // as Android redraws it, which must not take the front.
        front_input && self.take_front(&app_id, &name, &icon, surface_id)
    }

    pub(super) fn is_foreign_window(&self, surface_id: i32) -> bool {
        self.tasks.iter().find(|t| t.surface_id == surface_id).is_some_and(|t| self.termination_pid(&t.app_id) <= 0)
    }

    /// The card shows the newest window left; with none, an app with no
    /// process of its own is gone after a grace, as Waydroid re-creates a
    /// task's window as Android redraws it.
    pub(super) fn window_destroyed(mut self: Pin<&mut Self>, surface_id: i32) {
        self.as_mut().rust_mut().window_clients.remove(&surface_id);
        let Some(app_id) = self.windows.iter().find(|(_, w)| w.contains(&surface_id)).map(|(a, _)| a.clone()) else { return };
        let left: Vec<i32> = self.windows.get(&app_id).map(|w| w.iter().copied().filter(|s| *s != surface_id).collect()).unwrap_or_default();
        let task_surface = self.task(&app_id).map(|t| t.surface_id);
        if let Some(&newest) = left.last() {
            self.as_mut().rust_mut().windows.insert(app_id.clone(), left);
            if task_surface == Some(surface_id) {
                self.as_mut().update_task_window(&app_id, newest);
            }
            return;
        }
        self.as_mut().rust_mut().windows.remove(&app_id);
        if task_surface.is_none_or(|s| s == surface_id) && self.termination_pid(&app_id) <= 0 {
            later(self.qt_thread(), WINDOW_GRACE, move |mut obj| {
                if obj.windows.contains_key(&app_id) || obj.task(&app_id).is_some_and(|t| t.surface_id != surface_id) {
                    return;
                }
                obj.as_mut().close_task_of(&app_id);
                obj.unregister(&app_id);
            });
        }
    }

    /// Activated with its launch's token, a window is that launch's;
    /// any other honoured activation brings its task forward.
    pub(super) fn window_activated(mut self: Pin<&mut Self>, surface_id: i32, launch_pid: i64) {
        let task = self.tasks.iter().find(|t| t.surface_id == surface_id).cloned();
        if let Some(launch) = self.active_by_pid.get(&launch_pid).cloned() {
            if task.as_ref().is_some_and(|t| t.app_id == launch.app_id) {
                return;
            }
            if let Some(task) = task {
                self.as_mut().close_task_of(&task.app_id);
            }
            self.show_launch(&launch, surface_id);
            return;
        }
        let Some(task) = task else { return };
        self.as_mut().open_app_requested(&q(&task.app_id), &q(&task.title), &q(&task.icon), false);
        self.show_requested(&q(&task.app_id), &q(&task.title), &q(&task.icon), &q(&task.kind), surface_id);
    }

    /// Only an app the shell runs may put a window over others.
    pub(super) fn dialog_mapped(mut self: Pin<&mut Self>, pid: i64, sandbox_app_id: &QString, surface_id: i32) {
        let mut app_id = sandbox_app_id.to_string();
        if app_id.is_empty() {
            app_id = self.app_for_pid(pid);
        }
        if app_id.is_empty() {
            app_id = self.pid_to_app.iter().find(|(p, _)| descends_from(pid, **p)).map(|(_, a)| a.clone()).unwrap_or_default();
        }
        if app_id.is_empty() {
            log::warn("tasks", format_args!("dialog {surface_id} from pid {pid} of no app: not shown"));
            return;
        }
        self.as_mut().dialog_surface_created(&q(&app_id), surface_id);
    }
}
