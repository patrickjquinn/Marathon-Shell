//! The lifecycle (`docs/PERF_LIFECYCLE.md)`: the app in front runs, one in
//! the background holding a capability (music, a call, navigation) runs
//! too, the rest freeze in their cgroup once a debounce passes. The kernel's
//! OOM killer and memory pressure take frozen apps first.

use std::collections::{HashMap, HashSet};
use std::pin::Pin;
use std::time::{Duration, Instant};

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QString, QStringList};

use super::{dbus, later, launch::serves_keel_actions, q, Map, Tasks};
use crate::{app_ids, cgroup, io, log};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i32)]
pub(super) enum State {
    Unregistered = 0,
    Foreground = 1,
    BackgroundActive = 2,
    BackgroundIdle = 3,
    Frozen = 4,
    Killed = 5,
}

impl State {
    /// Android's ladder: cached apps (frozen) go first, and an app holding
    /// a capability outranks even the one on screen, as iOS's jetsam does.
    fn oom_score(self) -> i32 {
        match self {
            Self::BackgroundActive => -100,
            Self::BackgroundIdle => 300,
            Self::Frozen => 950,
            Self::Foreground | Self::Killed | Self::Unregistered => 0,
        }
    }
}

struct AppState {
    state: State,
    entered: Instant,
    capabilities: HashSet<String>,
    /// Bumped by every freeze it cancels, so a timer or a `PrepareFreeze`
    /// reply from before does nothing.
    freeze_turn: u64,
}

/// What QML told it of an app the shell draws itself.
#[derive(Clone, Default)]
struct Instance {
    name: String,
    icon: String,
    kind: String,
    native: bool,
    surface_id: i32,
}

pub(super) struct Lifecycle {
    apps: HashMap<String, AppState>,
    instances: HashMap<String, Instance>,
    foreground: String,
    pending_foreground: Vec<String>,
    front_android: String,
    idle_freeze: Duration,
    stopping: bool,
    cgroups: cgroup::AppCgroups,
    claims: HashMap<u32, (String, String)>,
    next_claim: u32,
    audio_playback: String,
    active_call: String,
}

impl Default for Lifecycle {
    fn default() -> Self {
        Self::new()
    }
}

impl Lifecycle {
    pub(super) fn new() -> Self {
        Self {
            apps: HashMap::new(),
            instances: HashMap::new(),
            foreground: String::new(),
            pending_foreground: Vec::new(),
            front_android: String::new(),
            idle_freeze: Duration::from_secs(10),
            stopping: false,
            cgroups: cgroup::app_cgroups(),
            claims: HashMap::new(),
            next_claim: 1,
            audio_playback: String::new(),
            active_call: String::new(),
        }
    }
}

impl Tasks {
    fn command(self: Pin<&mut Self>, app_id: &str, command: &str) {
        self.app_command(&q(app_id), &q(command));
    }

    fn state_of(&self, app_id: &str) -> State {
        self.lifecycle
            .apps
            .get(app_id)
            .map_or(State::Unregistered, |a| a.state)
    }

    fn insert_state(mut self: Pin<&mut Self>, app_id: &str, state: State) {
        let entry = AppState {
            state,
            entered: Instant::now(),
            capabilities: HashSet::new(),
            freeze_turn: 0,
        };
        self.as_mut()
            .rust_mut()
            .lifecycle
            .apps
            .entry(app_id.to_owned())
            .or_insert(entry);
    }

    /// A runner's process is known: its first state, its cgroup, its OOM
    /// score. A background launch leaves the app in front where it is.
    pub(super) fn pid_seen(mut self: Pin<&mut Self>, pid: i64, app_id: &str) {
        let background = self.background_launches.contains(app_id);
        if !self.lifecycle.apps.contains_key(app_id) {
            self.as_mut().insert_state(
                app_id,
                if background {
                    State::BackgroundIdle
                } else {
                    State::Foreground
                },
            );
            if !background {
                self.set_app_active(app_id, true);
            }
        }
        if !background {
            let previous = self.lifecycle.foreground.clone();
            if !previous.is_empty() && previous != app_id {
                self.as_mut().foreground_exit(&previous);
            }
            app_id.clone_into(&mut self.as_mut().rust_mut().lifecycle.foreground);
        }
        let state = self.state_of(app_id);
        cgroup::set_oom_score_adj(pid, state.oom_score());
        let cgroup = cgroup::cgroup_of_pid(pid);
        self.as_mut().rust_mut().lifecycle.cgroups.adopt(
            app_id,
            pid,
            &cgroup,
            cgroup::Placement {
                frozen: state == State::Frozen,
                foreground: state == State::Foreground,
            },
        );
    }

    pub(super) fn pid_gone(mut self: Pin<&mut Self>, app_id: &str) {
        self.as_mut().rust_mut().lifecycle.cgroups.forget(app_id);
    }

    pub(super) fn register_app(mut self: Pin<&mut Self>, app_id: &QString, info: &Map) {
        let id = app_id.to_string();
        if id.is_empty() {
            return;
        }
        let text = |k: &str| {
            info.get(&q(k))
                .and_then(|v| v.value::<QString>())
                .map(|s| s.to_string())
                .unwrap_or_default()
        };
        let instance = Instance {
            name: text("appName"),
            icon: text("appIcon"),
            kind: text("appType"),
            native: info
                .get(&q("isNative"))
                .and_then(|v| v.value::<bool>())
                .unwrap_or(false),
            surface_id: info
                .get(&q("surfaceId"))
                .and_then(|v| v.value::<i32>())
                .unwrap_or(-1),
        };
        self.as_mut()
            .rust_mut()
            .lifecycle
            .instances
            .insert(id.clone(), instance);
        self.as_mut().app_registered(app_id);
        self.as_mut().insert_state(&id, State::BackgroundIdle);
        if let Some(at) = self
            .lifecycle
            .pending_foreground
            .iter()
            .position(|a| *a == id)
        {
            self.as_mut()
                .rust_mut()
                .lifecycle
                .pending_foreground
                .remove(at);
            self.as_mut().bring_forward(&id);
        }
        self.ensure_task(&id);
    }

    pub(super) fn unregister_app(self: Pin<&mut Self>, app_id: &QString) {
        self.unregister(&app_id.to_string());
    }

    pub(super) fn unregister(mut self: Pin<&mut Self>, app_id: &str) {
        if app_id.is_empty() {
            return;
        }
        self.as_mut().close_task_of(app_id);
        self.as_mut().cancel_freeze(app_id);
        self.as_mut().rust_mut().lifecycle.cgroups.forget(app_id);
        let old = self.state_of(app_id);
        if self.lifecycle.apps.contains_key(app_id) && old != State::Killed {
            self.as_mut()
                .state_changed(&q(app_id), old as i32, State::Killed as i32);
        }
        let mut rust = self.as_mut().rust_mut();
        rust.lifecycle.instances.remove(app_id);
        rust.lifecycle.apps.remove(app_id);
        rust.lifecycle.pending_foreground.retain(|a| a != app_id);
        if rust.lifecycle.foreground == app_id {
            rust.lifecycle.foreground.clear();
        }
        self.app_unregistered(&q(app_id));
    }

    /// A card for an app the shell draws itself.
    fn ensure_task(mut self: Pin<&mut Self>, app_id: &str) {
        if self.task(app_id).is_some() {
            return;
        }
        let Some(i) = self.lifecycle.instances.get(app_id).cloned() else {
            return;
        };
        let name = if i.name.is_empty() {
            app_id.to_owned()
        } else {
            i.name
        };
        let kind = if i.kind.is_empty() {
            "marathon".to_owned()
        } else {
            i.kind
        };
        self.as_mut()
            .add_task(app_id, &name, &i.icon, &kind, i.surface_id);
    }

    pub(super) fn bring_to_foreground(self: Pin<&mut Self>, app_id: &QString) {
        self.bring_forward(&app_id.to_string());
    }

    fn bring_forward(mut self: Pin<&mut Self>, app_id: &str) {
        if app_id.is_empty() {
            return;
        }
        self.as_mut().move_to_front(app_id);
        let previous = self.lifecycle.foreground.clone();
        if !previous.is_empty() && previous != app_id {
            if self.lifecycle.instances.contains_key(&previous) {
                self.as_mut().command(&previous, "pause");
                self.as_mut().command(&previous, "stop");
            }
            self.as_mut().foreground_exit(&previous);
        }
        if !self.lifecycle.instances.contains_key(app_id) {
            if !self
                .lifecycle
                .pending_foreground
                .iter()
                .any(|a| a == app_id)
            {
                self.as_mut()
                    .rust_mut()
                    .lifecycle
                    .pending_foreground
                    .push(app_id.to_owned());
            }
            return;
        }
        self.as_mut().command(app_id, "start");
        self.as_mut().command(app_id, "resume");
        app_id.clone_into(&mut self.as_mut().rust_mut().lifecycle.foreground);
        self.as_mut().cancel_freeze(app_id);
        self.as_mut().transition(app_id, State::Foreground);
        self.ensure_task(app_id);
    }

    pub(super) fn restore_app(mut self: Pin<&mut Self>, app_id: &QString) {
        let id = app_id.to_string();
        if self.lifecycle.instances.contains_key(&id) {
            self.as_mut().command(&id, "restore");
            self.bring_forward(&id);
        }
    }

    pub(super) fn wake_app(self: Pin<&mut Self>, app_id: &QString) {
        self.wake(&app_id.to_string());
    }

    pub(super) fn wake(mut self: Pin<&mut Self>, app_id: &str) {
        if !matches!(self.state_of(app_id), State::Frozen | State::BackgroundIdle) {
            return;
        }
        self.as_mut().cancel_freeze(app_id);
        self.as_mut().transition(app_id, State::BackgroundIdle);
        self.start_freeze_debounce(app_id, true);
    }

    /// A Marathon app's back goes to its runner, a native window's to the
    /// compositor; both answer later (systemBackUnhandled).
    pub(super) fn handle_system_back(mut self: Pin<&mut Self>) -> bool {
        let front = self.lifecycle.foreground.clone();
        if front.is_empty() {
            return false;
        }
        if Self::is_marathon_app(&front) {
            dbus::runner_back(self.qt_thread(), front);
            return true;
        }
        let Some(surface) = self.native_surface(&front) else {
            return false;
        };
        let hosted = self.is_keel_host(&front);
        self.as_mut().native_back_requested(surface, hosted);
        true
    }

    pub(super) fn handle_system_forward(mut self: Pin<&mut Self>) -> bool {
        let front = self.lifecycle.foreground.clone();
        if front.is_empty() {
            return false;
        }
        if Self::is_marathon_app(&front) {
            dbus::runner(&front, "Forward", ());
            return true;
        }
        let Some(surface) = self.native_surface(&front) else {
            return false;
        };
        let hosted = self.is_keel_host(&front);
        self.as_mut().native_forward_requested(surface, hosted);
        true
    }

    pub(super) fn native_back_unhandled(mut self: Pin<&mut Self>, surface_id: i32) {
        let front = self.lifecycle.foreground.clone();
        if self.native_surface(&front) == Some(surface_id) {
            self.as_mut().system_back_unhandled();
        }
    }

    pub(super) fn runner_back_unhandled(mut self: Pin<&mut Self>, app_id: &str) {
        if self.lifecycle.foreground == app_id {
            self.as_mut().system_back_unhandled();
        }
    }

    /// A native window's current surface: its card follows its newest window.
    fn native_surface(&self, app_id: &str) -> Option<i32> {
        let i = self.lifecycle.instances.get(app_id).filter(|i| i.native)?;
        Some(self.task(app_id).map_or(i.surface_id, |t| t.surface_id)).filter(|s| *s > 0)
    }

    pub(super) fn minimize_foreground_app(mut self: Pin<&mut Self>) -> bool {
        let front = self.lifecycle.foreground.clone();
        if front.is_empty() {
            return false;
        }
        self.as_mut().ensure_task(&front);
        if self.lifecycle.instances.contains_key(&front) {
            self.as_mut().command(&front, "minimize");
            self.as_mut().command(&front, "stop");
        }
        self.as_mut().rust_mut().lifecycle.foreground.clear();
        self.foreground_exit(&front);
        true
    }

    pub(super) fn broadcast_low_memory(mut self: Pin<&mut Self>) {
        let ids: Vec<String> = self.lifecycle.instances.keys().cloned().collect();
        for id in ids {
            self.as_mut().command(&id, "handleLowMemory");
        }
    }

    pub(super) fn prepare_close(self: Pin<&mut Self>, app_id: &QString) {
        self.prepare(&app_id.to_string());
    }

    fn prepare(mut self: Pin<&mut Self>, app_id: &str) {
        self.as_mut().cancel_freeze(app_id);
        if self.state_of(app_id) == State::Frozen {
            self.transition(app_id, State::BackgroundIdle);
        }
    }

    pub(super) fn close_app(mut self: Pin<&mut Self>, app_id: &QString, skip_native_close: bool) {
        let id = app_id.to_string();
        if id.is_empty() {
            return;
        }
        self.as_mut().prepare(&id);
        self.as_mut().close_task_of(&id);
        if let Some(surface) = self.native_surface(&id).filter(|_| !skip_native_close) {
            self.as_mut().close_window_requested(surface);
        }
        if self.lifecycle.instances.contains_key(&id) {
            self.as_mut().command(&id, "close");
        }
        if self.lifecycle.foreground == id {
            self.as_mut().rust_mut().lifecycle.foreground.clear();
        }
        self.unregister(&id);
    }

    pub(super) fn lifecycle_state(&self, app_id: &QString) -> i32 {
        self.state_of(&app_id.to_string()) as i32
    }

    pub(super) fn capabilities_of(&self, app_id: &str) -> Vec<String> {
        let mut caps: Vec<String> = self
            .lifecycle
            .apps
            .get(app_id)
            .map(|a| a.capabilities.iter().cloned().collect())
            .unwrap_or_default();
        caps.sort();
        caps
    }

    pub(super) fn active_capabilities(&self, app_id: &QString) -> QStringList {
        let mut list = QList::<QString>::default();
        for c in self.capabilities_of(&app_id.to_string()) {
            list.append(q(&c));
        }
        QStringList::from(&list)
    }

    pub(super) fn add_capability(self: Pin<&mut Self>, app_id: &QString, capability: &QString) {
        self.add_cap(&app_id.to_string(), &capability.to_string());
    }

    pub(super) fn remove_capability(self: Pin<&mut Self>, app_id: &QString, capability: &QString) {
        self.remove_cap(&app_id.to_string(), &capability.to_string());
    }

    /// A background app that gains a capability does not freeze.
    pub(super) fn add_cap(mut self: Pin<&mut Self>, app_id: &str, capability: &str) {
        if app_id.is_empty() || capability.is_empty() {
            return;
        }
        let mut rust = self.as_mut().rust_mut();
        let Some(app) = rust.lifecycle.apps.get_mut(app_id) else {
            return;
        };
        if !app.capabilities.insert(capability.to_owned()) {
            return;
        }
        let state = app.state;
        self.as_mut().capabilities_changed(&q(app_id));
        if state == State::BackgroundIdle {
            self.as_mut().cancel_freeze(app_id);
            self.transition(app_id, State::BackgroundActive);
        }
    }

    pub(super) fn remove_cap(mut self: Pin<&mut Self>, app_id: &str, capability: &str) {
        let mut rust = self.as_mut().rust_mut();
        let Some(app) = rust.lifecycle.apps.get_mut(app_id) else {
            return;
        };
        if !app.capabilities.remove(capability) {
            return;
        }
        let (state, empty) = (app.state, app.capabilities.is_empty());
        self.as_mut().capabilities_changed(&q(app_id));
        if state == State::BackgroundActive && empty {
            self.as_mut().transition(app_id, State::BackgroundIdle);
            self.start_freeze_debounce(app_id, false);
        }
    }

    pub(super) fn set_idle_freeze_debounce_ms(mut self: Pin<&mut Self>, ms: i32) {
        self.as_mut().rust_mut().lifecycle.idle_freeze =
            Duration::from_millis(u64::try_from(ms.max(0)).unwrap_or(0));
    }

    pub(super) fn idle_freeze_debounce_ms(&self) -> i32 {
        i32::try_from(self.lifecycle.idle_freeze.as_millis()).unwrap_or(i32::MAX)
    }

    /// A capability decides where it goes: running, or idle until it freezes.
    fn foreground_exit(mut self: Pin<&mut Self>, app_id: &str) {
        let Some(app) = self.lifecycle.apps.get(app_id) else {
            return;
        };
        if app.capabilities.is_empty() {
            self.as_mut().transition(app_id, State::BackgroundIdle);
            self.start_freeze_debounce(app_id, false);
        } else {
            self.transition(app_id, State::BackgroundActive);
        }
    }

    /// A debounce of 0 (dozing) freezes at once, except where the app needs
    /// time: woken for work, or not yet showing its first window.
    fn start_freeze_debounce(mut self: Pin<&mut Self>, app_id: &str, grace: bool) {
        self.as_mut().cancel_freeze(app_id);
        let Some(turn) = self.lifecycle.apps.get(app_id).map(|a| a.freeze_turn) else {
            return;
        };
        let debounce = self.lifecycle.idle_freeze;
        let delay = if debounce.is_zero() && grace {
            Duration::from_secs(10)
        } else {
            debounce
        };
        if delay.is_zero() {
            if self.state_of(app_id) == State::BackgroundIdle {
                self.freeze(app_id);
            }
            return;
        }
        let id = app_id.to_owned();
        later(self.qt_thread(), delay, move |obj| {
            if obj
                .lifecycle
                .apps
                .get(&id)
                .is_some_and(|a| a.freeze_turn == turn && a.state == State::BackgroundIdle)
            {
                obj.freeze(&id);
            }
        });
    }

    fn cancel_freeze(mut self: Pin<&mut Self>, app_id: &str) {
        if let Some(app) = self.as_mut().rust_mut().lifecycle.apps.get_mut(app_id) {
            app.freeze_turn += 1;
        }
    }

    /// A frozen app cannot answer, so a Keel Actions app gives up its bus
    /// name first: a call for it then goes to bus activation.
    fn freeze(self: Pin<&mut Self>, app_id: &str) {
        if !serves_keel_actions(app_id) {
            return self.transition(app_id, State::Frozen);
        }
        let turn = self.lifecycle.apps.get(app_id).map_or(0, |a| a.freeze_turn);
        dbus::prepare_freeze(self.qt_thread(), app_id.to_owned(), move |mut obj, id| {
            if obj
                .lifecycle
                .apps
                .get(&id)
                .is_some_and(|a| a.freeze_turn == turn && a.state == State::BackgroundIdle)
            {
                obj.as_mut().transition(&id, State::Frozen);
            }
            if obj.state_of(&id) != State::Frozen {
                dbus::runner(&id, "Thawed", ());
            }
        });
    }

    /// The one place a state changes.
    pub(super) fn transition(mut self: Pin<&mut Self>, app_id: &str, new: State) {
        let old = self.state_of(app_id);
        if !self.lifecycle.apps.contains_key(app_id)
            || old == new
            || (self.lifecycle.stopping && new == State::Frozen)
        {
            return;
        }
        // Never freeze an app that has not mapped its first window: it
        // would stop before showing it, an app that "won't open".
        if new == State::Frozen {
            if self.task(app_id).is_none_or(|t| t.surface_id < 0) {
                return self.start_freeze_debounce(app_id, true);
            }
            if self.termination_pid(app_id) <= 0 {
                return;
            }
        }
        if let Some(app) = self.as_mut().rust_mut().lifecycle.apps.get_mut(app_id) {
            app.state = new;
            app.entered = Instant::now();
        }
        cgroup::set_oom_score_adj(self.pid_for(app_id), new.oom_score());
        if new == State::Frozen {
            self.lifecycle.cgroups.set_frozen(app_id, true);
        } else if old == State::Frozen {
            self.lifecycle.cgroups.set_frozen(app_id, false);
        }
        self.lifecycle
            .cgroups
            .set_front(app_id, new == State::Foreground);
        if old == State::Frozen && serves_keel_actions(app_id) {
            dbus::runner(app_id, "Thawed", ());
        }
        if (old == State::Foreground) != (new == State::Foreground) {
            self.set_app_active(app_id, new == State::Foreground);
        }
        self.state_changed(&q(app_id), old as i32, new as i32);
    }

    pub(super) fn set_front_app(mut self: Pin<&mut Self>, app_id: &QString) {
        let id = app_id.to_string();
        let android = if id.starts_with(app_ids::ANDROID) {
            id
        } else {
            String::new()
        };
        if android == self.lifecycle.front_android {
            return;
        }
        if !self.lifecycle.front_android.is_empty() {
            self.lifecycle
                .cgroups
                .set_front(&self.lifecycle.front_android, false);
        }
        if !android.is_empty() {
            self.lifecycle.cgroups.set_front(&android, true);
        }
        self.as_mut().rust_mut().lifecycle.front_android = android;
    }

    pub(super) fn kill_oldest_frozen_app(self: Pin<&mut Self>) -> i32 {
        let Some(oldest) = self
            .lifecycle
            .apps
            .iter()
            .filter(|(_, a)| a.state == State::Frozen)
            .min_by_key(|(_, a)| a.entered)
            .map(|(id, _)| id.clone())
        else {
            return -1;
        };
        let pid = self.termination_pid(&oldest);
        let Ok(raw) = i32::try_from(pid) else {
            return -1;
        };
        if raw <= 0 {
            log::warn("tasks", format_args!("no pid to kill for {oldest}"));
            return -1;
        }
        // Thawed first: a frozen process cannot run its SIGTERM handler.
        self.lifecycle.cgroups.set_frozen(&oldest, false);
        // SAFETY: `raw` is a validated positive process ID, so this targets
        // that process rather than a process group.
        if unsafe { libc::kill(raw, libc::SIGTERM) } != 0 {
            log::warn(
                "tasks",
                format_args!(
                    "cannot terminate {oldest} ({raw}): {}",
                    std::io::Error::last_os_error()
                ),
            );
        }
        let id = oldest.clone();
        later(self.qt_thread(), Duration::from_secs(5), move |obj| {
            if obj.termination_pid(&id) == pid {
                // SAFETY: `raw` remains the positive PID associated with this
                // lifecycle generation. Failure is harmless if it exited.
                if unsafe { libc::kill(raw, libc::SIGKILL) } != 0 {
                    log::warn(
                        "tasks",
                        format_args!(
                            "cannot kill {id} ({raw}): {}",
                            std::io::Error::last_os_error()
                        ),
                    );
                }
            }
        });
        self.transition(&oldest, State::Killed);
        raw
    }

    pub(super) fn stop_all_apps(mut self: Pin<&mut Self>, grace_ms: i32) {
        if self.lifecycle.stopping {
            return;
        }
        self.as_mut().rust_mut().lifecycle.stopping = true;
        self.lifecycle.cgroups.thaw_all();
        let ids: Vec<String> = self.lifecycle.apps.keys().cloned().collect();
        let pids: Vec<i32> = ids
            .iter()
            .filter_map(|id| i32::try_from(self.termination_pid(id)).ok())
            .filter(|p| *p > 0)
            .collect();
        let qt = self.qt_thread();
        let grace = Duration::from_millis(u64::try_from(grace_ms.max(0)).unwrap_or(0));
        io::spawn(async move {
            let killed = blocking::unblock(move || stop_processes(&pids, grace)).await;
            if killed > 0 {
                log::warn(
                    "tasks",
                    format_args!("stopAllApps: {killed} SIGKILLed after the grace"),
                );
            }
            qt.queue(super::qobject::Tasks::all_apps_stopped).ok();
        });
    }

    // The capabilities the shell sees: an MPRIS player playing, a call.
    pub(crate) fn playback(mut self: Pin<&mut Self>, app_id: &str) {
        let current = self.lifecycle.audio_playback.clone();
        if current == app_id {
            return;
        }
        if !current.is_empty() {
            self.as_mut().remove_cap(&current, "audio-playback");
        }
        app_id.clone_into(&mut self.as_mut().rust_mut().lifecycle.audio_playback);
        if !app_id.is_empty() {
            self.add_cap(app_id, "audio-playback");
        }
    }

    /// Modem doesn't attribute calls yet: they are the Phone app's.
    pub(crate) fn call_active(mut self: Pin<&mut Self>, active: bool) {
        let holder = if active { "phone" } else { "" };
        let current = self.lifecycle.active_call.clone();
        if current == holder {
            return;
        }
        if !current.is_empty() {
            self.as_mut().remove_cap(&current, "active-call");
        }
        holder.clone_into(&mut self.as_mut().rust_mut().lifecycle.active_call);
        if !holder.is_empty() {
            self.add_cap(holder, "active-call");
        }
    }

    /// `AppLifecycle1`'s claims, refcounted per app and category.
    pub(super) fn begin_claim(mut self: Pin<&mut Self>, app_id: &str, category: &str) -> u32 {
        let mut rust = self.as_mut().rust_mut();
        let handle = rust.lifecycle.next_claim;
        rust.lifecycle.next_claim += 1;
        rust.lifecycle
            .claims
            .insert(handle, (app_id.to_owned(), category.to_owned()));
        self.add_cap(app_id, category);
        handle
    }

    /// Only the app that began it ends it.
    pub(super) fn end_claim(mut self: Pin<&mut Self>, handle: u32, caller: &str) -> bool {
        if self
            .lifecycle
            .claims
            .get(&handle)
            .is_none_or(|c| c.0 != caller)
        {
            return false;
        }
        let Some((app, category)) = self.as_mut().rust_mut().lifecycle.claims.remove(&handle)
        else {
            return false;
        };
        if !self
            .lifecycle
            .claims
            .values()
            .any(|c| c.0 == app && c.1 == category)
        {
            self.remove_cap(&app, &category);
        }
        true
    }
}

/// SIGTERMs them, waits up to `grace` for each through its pidfd, SIGKILLs
/// the rest; how many it killed.
fn stop_processes(pids: &[i32], grace: Duration) -> usize {
    let deadline = Instant::now() + grace;
    let mut fds: Vec<i32> = Vec::new();
    for &pid in pids {
        // SAFETY: pidfd_open(2) and pidfd_send_signal(2) take plain integers.
        let fd = unsafe { libc::syscall(libc::SYS_pidfd_open, pid, 0) };
        let Ok(fd) = i32::try_from(fd) else { continue };
        if fd < 0 {
            continue;
        }
        // SAFETY: as above, with a pidfd this function opened.
        if unsafe {
            libc::syscall(
                libc::SYS_pidfd_send_signal,
                fd,
                libc::SIGTERM,
                std::ptr::null::<libc::siginfo_t>(),
                0,
            )
        } == 0
        {
            fds.push(fd);
        } else {
            // SAFETY: closes the pidfd this function opened.
            unsafe { libc::close(fd) };
        }
    }
    let mut killed = 0;
    for fd in fds {
        let left = deadline.saturating_duration_since(Instant::now());
        let mut poll = libc::pollfd {
            fd,
            events: libc::POLLIN,
            revents: 0,
        };
        // SAFETY: one pollfd this function owns.
        let ready = unsafe {
            libc::poll(
                &raw mut poll,
                1,
                i32::try_from(left.as_millis()).unwrap_or(i32::MAX),
            )
        };
        // A pidfd polls readable once its process has exited, reaped or not.
        let signalled = if ready <= 0 {
            // SAFETY: `fd` is the pidfd opened above and the remaining syscall
            // arguments follow pidfd_send_signal's contract.
            (unsafe {
                libc::syscall(
                    libc::SYS_pidfd_send_signal,
                    fd,
                    libc::SIGKILL,
                    std::ptr::null::<libc::siginfo_t>(),
                    0,
                )
            }) == 0
        } else {
            false
        };
        if signalled {
            killed += 1;
        }
        // SAFETY: closes the pidfd this function opened.
        unsafe { libc::close(fd) };
    }
    killed
}
