//! `Tasks`: the apps that run, from their launch to their exit. One object
//! is the switcher's list model (QML `TaskModel`), the launcher (QML
//! `AppLaunchService`) and the lifecycle (QML `AppLifecycleManager`), and it
//! serves `Navigation1`, `AppLifecycle1` and `AppStore1`, so a launch, its
//! window, its card and its lifecycle state change together.
//!
//! The compositor stays C++: it hands this object its processes' and
//! windows' events as plain values (main.cpp connects them), and does what
//! this object's signals ask. QML shows the windows and runs the app
//! instances it holds when asked to.

#![allow(
    clippy::too_many_arguments,
    reason = "windowMapped: the window's facts, from the compositor"
)]

mod dbus;
mod keel;
pub(crate) use dbus::{playback_changed, uninstalled};
mod launch;
mod lifecycle;
mod pool;

use std::collections::{HashMap, HashSet};
use std::pin::Pin;
use std::sync::OnceLock;
use std::time::Instant;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{
    QByteArray, QHash, QHashPair_i32_QByteArray, QList, QMap, QMapPair_QString_QVariant,
    QModelIndex, QString, QStringList, QVariant,
};

// In the global namespace: cxx-qt 0.10 would put the base class in a
// bridge's namespace too.
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!(<QtCore/QAbstractListModel>);
        type QAbstractListModel;
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
        include!("cxx-qt-lib/qvariant.h");
        type QVariant = cxx_qt_lib::QVariant;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
        include!("cxx-qt-lib/qmodelindex.h");
        type QModelIndex = cxx_qt_lib::QModelIndex;
        include!("cxx-qt-lib/qhash.h");
        type QHash_i32_QByteArray = cxx_qt_lib::QHash<cxx_qt_lib::QHashPair_i32_QByteArray>;
    }

    unsafe extern "RustQt" {
        #[qobject]
        #[base = QAbstractListModel]
        #[qproperty(i32, task_count, cxx_name = "taskCount", READ, NOTIFY)]
        /// Apps whose windows stay off cards and screenshots.
        #[qproperty(QStringList, secure_apps, cxx_name = "secureApps", READ, NOTIFY)]
        /// An Android launch is waiting for Android to boot.
        #[qproperty(bool, android_starting, cxx_name = "androidStarting", READ, NOTIFY)]
        #[qproperty(QString, foreground_app_id, cxx_name = "foregroundAppId", READ, NOTIFY)]
        type Tasks = super::TasksRust;

        #[inherit]
        #[cxx_name = "beginResetModel"]
        fn begin_reset_model(self: Pin<&mut Tasks>);
        #[inherit]
        #[cxx_name = "endResetModel"]
        fn end_reset_model(self: Pin<&mut Tasks>);
        #[cxx_override]
        #[cxx_name = "rowCount"]
        fn row_count(self: &Tasks, parent: &QModelIndex) -> i32;
        #[cxx_override]
        fn data(self: &Tasks, index: &QModelIndex, role: i32) -> QVariant;
        #[cxx_override]
        #[cxx_name = "roleNames"]
        fn role_names(self: &Tasks) -> QHash_i32_QByteArray;

        // The task list.
        #[qsignal]
        #[cxx_name = "taskLaunched"]
        fn task_launched(self: Pin<&mut Tasks>, task_id: &QString);
        #[qsignal]
        #[cxx_name = "taskClosed"]
        fn task_closed(self: Pin<&mut Tasks>, task_id: &QString);
        #[qinvokable]
        #[cxx_name = "launchTask"]
        fn launch_task(
            self: Pin<&mut Tasks>,
            app_id: &QString,
            name: &QString,
            icon: &QString,
            kind: &QString,
            surface_id: i32,
        );
        #[qinvokable]
        #[cxx_name = "closeTask"]
        fn close_task(self: Pin<&mut Tasks>, task_id: &QString);
        /// The app's task: id, appId, title, icon, appType, surfaceId and
        /// timestamp; empty for none.
        #[qinvokable]
        #[cxx_name = "getTaskByAppId"]
        fn get_task_by_app_id(self: &Tasks, app_id: &QString) -> QMap_QString_QVariant;
        #[qinvokable]
        #[cxx_name = "getTaskBySurfaceId"]
        fn get_task_by_surface_id(self: &Tasks, surface_id: i32) -> QMap_QString_QVariant;

        // The launcher.
        #[qinvokable]
        #[cxx_name = "launchApp"]
        fn launch_app(self: Pin<&mut Tasks>, app_id: &QString) -> bool;
        /// A route and its JSON parameters for the runner (MARATHON_APP_ROUTE).
        #[qinvokable]
        #[cxx_name = "launchAppWithRoute"]
        fn launch_app_with_route(
            self: Pin<&mut Tasks>,
            app_id: &QString,
            route: &QString,
            params_json: &QString,
        ) -> bool;
        /// Starts the app without bringing it on screen; a running one is
        /// left where it is, thawed if it was frozen.
        #[qinvokable]
        #[cxx_name = "startAppInBackground"]
        fn start_app_in_background(self: Pin<&mut Tasks>, app_id: &QString) -> bool;
        #[cxx_name = "canLaunch"]
        fn can_launch(self: &Tasks, app_id: &QString) -> bool;
        /// How many windows of the app it asked to close.
        #[qinvokable]
        #[cxx_name = "closeAppWindows"]
        fn close_app_windows(self: Pin<&mut Tasks>, app_id: &QString) -> i32;
        #[qinvokable]
        #[cxx_name = "isAppLaunching"]
        fn is_app_launching(self: &Tasks, app_id: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "pidForAppId"]
        fn pid_for_app_id(self: &Tasks, app_id: &QString) -> i64;
        #[qinvokable]
        #[cxx_name = "appIdForPid"]
        fn app_id_for_pid(self: &Tasks, pid: i64) -> QString;
        /// A Keel app run under marathon-keel-host.
        #[qinvokable]
        #[cxx_name = "isKeelHostApp"]
        fn is_keel_host_app(self: &Tasks, app_id: &QString) -> bool;
        /// Tells a Keel app whether its cover is on screen.
        #[qinvokable]
        #[cxx_name = "setCoverVisible"]
        fn set_cover_visible(self: &Tasks, app_id: &QString, visible: bool);
        /// The app's window in front now, or the next one it maps within a
        /// few seconds; true when it had one to bring forward.
        #[cxx_name = "expectWindow"]
        fn expect_window(self: Pin<&mut Tasks>, app_id: &QString) -> bool;
        #[cxx_name = "setAppSecure"]
        fn set_app_secure(self: Pin<&mut Tasks>, app_id: &QString, secure: bool);

        #[qsignal]
        #[cxx_name = "appLaunchStarted"]
        fn app_launch_started(self: Pin<&mut Tasks>, app_id: &QString, name: &QString);
        #[qsignal]
        #[cxx_name = "appLaunchCompleted"]
        fn app_launch_completed(self: Pin<&mut Tasks>, app_id: &QString, name: &QString);
        #[qsignal]
        #[cxx_name = "appLaunchFailed"]
        fn app_launch_failed(
            self: Pin<&mut Tasks>,
            app_id: &QString,
            name: &QString,
            error: &QString,
        );
        /// A route for a running app, which must handle it live.
        #[qsignal]
        #[cxx_name = "routeForRunningApp"]
        fn route_for_running_app(
            self: Pin<&mut Tasks>,
            app_id: &QString,
            route: &QString,
            params_json: &QString,
        );
        #[qsignal]
        #[cxx_name = "appExited"]
        fn app_exited(self: Pin<&mut Tasks>, app_id: &QString);
        /// 0 hide, 1 show, 2 toggle.
        #[qsignal]
        #[cxx_name = "quickSettingsRequested"]
        fn quick_settings_requested(self: Pin<&mut Tasks>, mode: i32);
        #[qsignal]
        #[cxx_name = "homeRequested"]
        fn home_requested(self: Pin<&mut Tasks>, switcher: bool);
        /// A window the app shows over itself (a KeelDialog).
        #[qsignal]
        #[cxx_name = "dialogSurfaceCreated"]
        fn dialog_surface_created(self: Pin<&mut Tasks>, app_id: &QString, surface_id: i32);
        #[qsignal]
        #[cxx_name = "pidRegistered"]
        fn pid_registered(self: Pin<&mut Tasks>, pid: i64, app_id: &QString);
        #[qsignal]
        #[cxx_name = "pidUnregistered"]
        fn pid_unregistered(self: Pin<&mut Tasks>, pid: i64, app_id: &QString);

        // What QML does for it: UIStore's app, and the app window.
        #[qsignal]
        #[cxx_name = "openAppRequested"]
        fn open_app_requested(
            self: Pin<&mut Tasks>,
            app_id: &QString,
            name: &QString,
            icon: &QString,
            restore: bool,
        );
        /// `surface_id` -1 shows the splash until the app's window maps.
        #[qsignal]
        #[cxx_name = "showRequested"]
        fn show_requested(
            self: Pin<&mut Tasks>,
            app_id: &QString,
            name: &QString,
            icon: &QString,
            kind: &QString,
            surface_id: i32,
        );

        // What the compositor does for it (main.cpp connects these).
        #[qsignal]
        #[cxx_name = "spawnRequested"]
        fn spawn_requested(self: Pin<&mut Tasks>, command: &QString, env: &QMap_QString_QVariant);
        #[qsignal]
        #[cxx_name = "closeWindowRequested"]
        fn close_window_requested(self: Pin<&mut Tasks>, surface_id: i32);
        #[qsignal]
        #[cxx_name = "sandboxSocketRequested"]
        fn sandbox_socket_requested(self: Pin<&mut Tasks>, app_id: &QString, instance: &QString);
        #[qsignal]
        #[cxx_name = "sandboxSocketClosed"]
        fn sandbox_socket_closed(self: Pin<&mut Tasks>, instance: &QString);
        #[qsignal]
        #[cxx_name = "sandboxAppAssigned"]
        fn sandbox_app_assigned(self: Pin<&mut Tasks>, instance: &QString, app_id: &QString);
        #[qsignal]
        #[cxx_name = "nativeBackRequested"]
        fn native_back_requested(self: Pin<&mut Tasks>, surface_id: i32, keel_hosted: bool);
        #[qsignal]
        #[cxx_name = "nativeForwardRequested"]
        fn native_forward_requested(self: Pin<&mut Tasks>, surface_id: i32, keel_hosted: bool);

        // The compositor's events.
        #[cxx_name = "appLaunched"]
        fn app_launched(self: Pin<&mut Tasks>, command: &QString, pid: i64);
        #[cxx_name = "appClosed"]
        fn app_closed(self: Pin<&mut Tasks>, pid: i64);
        /// A new toplevel; true if it is shown. `recent_input`: the user
        /// touched the screen just now.
        #[cxx_name = "windowMapped"]
        fn window_mapped(
            self: Pin<&mut Tasks>,
            pid: i64,
            client_pid: i64,
            xdg_app_id: &QString,
            title: &QString,
            sandbox_app_id: &QString,
            surface_id: i32,
            recent_input: bool,
        ) -> bool;
        /// The window's app has no process of its own (Android's).
        #[cxx_name = "isForeignWindow"]
        fn is_foreign_window(self: &Tasks, surface_id: i32) -> bool;
        #[cxx_name = "windowDestroyed"]
        fn window_destroyed(self: Pin<&mut Tasks>, surface_id: i32);
        #[cxx_name = "windowActivated"]
        fn window_activated(self: Pin<&mut Tasks>, surface_id: i32, launch_pid: i64);
        #[cxx_name = "dialogMapped"]
        fn dialog_mapped(
            self: Pin<&mut Tasks>,
            pid: i64,
            sandbox_app_id: &QString,
            surface_id: i32,
        );
        #[cxx_name = "nativeBackUnhandled"]
        fn native_back_unhandled(self: Pin<&mut Tasks>, surface_id: i32);

        // The shell's state it follows, set by main.cpp.
        #[cxx_name = "setDevice"]
        fn set_device(self: Pin<&mut Tasks>, device: &QMap_QString_QVariant);
        #[cxx_name = "setUserScale"]
        fn set_user_scale(self: Pin<&mut Tasks>, scale: f64);
        #[cxx_name = "setAppViewport"]
        fn set_app_viewport(self: Pin<&mut Tasks>, width: i32, height: i32);
        #[cxx_name = "setShellState"]
        fn set_shell_state(
            self: Pin<&mut Tasks>,
            app_window_open: bool,
            current_app_id: &QString,
            locked: bool,
            quick_settings_open: bool,
        );

        // The lifecycle.
        /// An app the shell draws itself (an in-shell QML app or a native
        /// window): its name, icon, type, isNative and surfaceId.
        #[qinvokable]
        #[cxx_name = "registerApp"]
        fn register_app(self: Pin<&mut Tasks>, app_id: &QString, info: &QMap_QString_QVariant);
        #[qinvokable]
        #[cxx_name = "unregisterApp"]
        fn unregister_app(self: Pin<&mut Tasks>, app_id: &QString);
        #[qinvokable]
        #[cxx_name = "bringToForeground"]
        fn bring_to_foreground(self: Pin<&mut Tasks>, app_id: &QString);
        #[qinvokable]
        #[cxx_name = "restoreApp"]
        fn restore_app(self: Pin<&mut Tasks>, app_id: &QString);
        /// Thaws a frozen background app without bringing it forward.
        #[qinvokable]
        #[cxx_name = "wakeApp"]
        fn wake_app(self: Pin<&mut Tasks>, app_id: &QString);
        /// False when QML's own app instance must decide.
        #[qinvokable]
        #[cxx_name = "handleSystemBack"]
        fn handle_system_back(self: Pin<&mut Tasks>) -> bool;
        #[qinvokable]
        #[cxx_name = "handleSystemForward"]
        fn handle_system_forward(self: Pin<&mut Tasks>) -> bool;
        #[qinvokable]
        #[cxx_name = "minimizeForegroundApp"]
        fn minimize_foreground_app(self: Pin<&mut Tasks>) -> bool;
        #[qinvokable]
        #[cxx_name = "closeApp"]
        fn close_app(self: Pin<&mut Tasks>, app_id: &QString, skip_native_close: bool);
        #[qinvokable]
        #[cxx_name = "prepareClose"]
        fn prepare_close(self: Pin<&mut Tasks>, app_id: &QString);
        #[qinvokable]
        #[cxx_name = "broadcastLowMemory"]
        fn broadcast_low_memory(self: Pin<&mut Tasks>);
        /// The longest-frozen app, SIGTERMed then SIGKILLed after 5 s; its
        /// pid, -1 for none.
        #[qinvokable]
        #[cxx_name = "killOldestFrozenApp"]
        fn kill_oldest_frozen_app(self: Pin<&mut Tasks>) -> i32;
        /// Thaws and SIGTERMs every app, SIGKILLs what is left after
        /// `grace_ms`, then `allAppsStopped`.
        #[cxx_name = "stopAllApps"]
        fn stop_all_apps(self: Pin<&mut Tasks>, grace_ms: i32);
        #[qinvokable]
        #[cxx_name = "lifecycleState"]
        fn lifecycle_state(self: &Tasks, app_id: &QString) -> i32;
        #[qinvokable]
        #[cxx_name = "activeCapabilities"]
        fn active_capabilities(self: &Tasks, app_id: &QString) -> QStringList;
        #[qinvokable]
        #[cxx_name = "addCapability"]
        fn add_capability(self: Pin<&mut Tasks>, app_id: &QString, capability: &QString);
        #[qinvokable]
        #[cxx_name = "removeCapability"]
        fn remove_capability(self: Pin<&mut Tasks>, app_id: &QString, capability: &QString);
        /// Between leaving the front and freezing; 0 while dozing.
        #[cxx_name = "setIdleFreezeDebounceMs"]
        fn set_idle_freeze_debounce_ms(self: Pin<&mut Tasks>, ms: i32);
        #[cxx_name = "idleFreezeDebounceMs"]
        fn idle_freeze_debounce_ms(self: &Tasks) -> i32;

        #[qsignal]
        #[cxx_name = "appRegistered"]
        fn app_registered(self: Pin<&mut Tasks>, app_id: &QString);
        #[qsignal]
        #[cxx_name = "appUnregistered"]
        fn app_unregistered(self: Pin<&mut Tasks>, app_id: &QString);
        #[qsignal]
        #[cxx_name = "stateChanged"]
        fn state_changed(self: Pin<&mut Tasks>, app_id: &QString, old_state: i32, new_state: i32);
        #[qsignal]
        #[cxx_name = "capabilitiesChanged"]
        fn capabilities_changed(self: Pin<&mut Tasks>, app_id: &QString);
        /// Back went to an app out of process, and it declined.
        #[qsignal]
        #[cxx_name = "systemBackUnhandled"]
        fn system_back_unhandled(self: Pin<&mut Tasks>);
        #[qsignal]
        #[cxx_name = "allAppsStopped"]
        fn all_apps_stopped(self: Pin<&mut Tasks>);
        /// What QML's instance of the app does: pause, stop, start, resume,
        /// restore, minimize, close or handleLowMemory.
        #[qsignal]
        #[cxx_name = "appCommand"]
        fn app_command(self: Pin<&mut Tasks>, app_id: &QString, command: &QString);
        /// The app the compositor has in front; Android's apps have no
        /// lifecycle state, so only their CPU boost follows it.
        #[cxx_name = "setFrontApp"]
        fn set_front_app(self: Pin<&mut Tasks>, app_id: &QString);
    }

    impl cxx_qt::Threading for Tasks {}
    impl cxx_qt::Initialize for Tasks {}
}

use qobject::Tasks;

type Qt = cxx_qt::CxxQtThread<Tasks>;
type Map = QMap<QMapPair_QString_QVariant>;

static QT: OnceLock<Qt> = OnceLock::new();

/// Runs `f` on the tasks, on the GUI thread.
pub(crate) fn with(f: impl FnOnce(Pin<&mut Tasks>) + Send + 'static) {
    if let Some(qt) = QT.get() {
        qt.queue(f).ok();
    }
}

/// A card in the switcher.
#[derive(Clone, Debug)]
struct Task {
    id: String,
    app_id: String,
    title: String,
    icon: String,
    kind: String,
    surface_id: i32,
    timestamp: i64,
}

const ROLES: [&str; 7] = [
    "id",
    "appId",
    "title",
    "icon",
    "type",
    "surfaceId",
    "timestamp",
];
const USER_ROLE: i32 = 0x0100;

/// A started process, until it exits.
#[derive(Clone, Debug, Default)]
struct Launch {
    app_id: String,
    name: String,
    icon: String,
    kind: String,
    command: String,
    sandbox_instance: String,
    pid: i64,
    foreground_generation: u64,
}

/// What a runner is started with on this device.
#[derive(Clone, Debug, Default)]
struct Device {
    render_node: String,
    gpu_webgl: bool,
    runner_pool: i32,
    runner_width: i32,
    runner_height: i32,
    thumbnails: String,
    dpi: f64,
    screen_width: i32,
    screen_height: i32,
    user_scale: f64,
    viewport_width: i32,
    viewport_height: i32,
}

#[derive(Default)]
#[allow(
    clippy::struct_excessive_bools,
    reason = "the QML properties and the shell's state"
)]
pub struct TasksRust {
    task_count: i32,
    secure_apps: QStringList,
    android_starting: bool,
    foreground_app_id: QString,
    tasks: Vec<Task>,
    next_task: u64,
    device: Device,
    // The shell's own state.
    app_window_open: bool,
    current_app_id: String,
    locked: bool,
    quick_settings_open: bool,
    // The launcher.
    launching: HashSet<String>,
    background_launches: HashSet<String>,
    starting_in_background: bool,
    foreground_launches: launch::ForegroundLaunches,
    pending_route: Option<(String, String)>,
    pending_by_command: HashMap<String, Launch>,
    active_by_pid: HashMap<i64, Launch>,
    exited_launches: HashMap<String, Launch>,
    pid_to_app: HashMap<i64, String>,
    app_to_pid: HashMap<String, i64>,
    windows: HashMap<String, Vec<i32>>,
    window_clients: HashMap<i32, i64>,
    expected_windows: HashMap<String, Instant>,
    android_handoffs: HashMap<String, launch::AndroidHandoff>,
    secure: HashMap<String, bool>,
    after_android_boot: Vec<String>,
    pool: pool::Pool,
    // The lifecycle.
    lifecycle: lifecycle::Lifecycle,
}

impl cxx_qt::Initialize for Tasks {
    fn initialize(self: Pin<&mut Self>) {
        QT.set(self.qt_thread()).ok();
        dbus::export(self.qt_thread());
        keel::export(self.qt_thread());
        pool::refill_later(self.qt_thread(), std::time::Duration::from_secs(8));
    }
}

impl Tasks {
    fn row_count(&self, parent: &QModelIndex) -> i32 {
        if parent.is_valid() {
            0
        } else {
            self.task_count
        }
    }

    fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
        let Some(task) = usize::try_from(index.row())
            .ok()
            .and_then(|row| self.tasks.get(row))
        else {
            return QVariant::default();
        };
        let text = |s: &str| QVariant::from(&QString::from(s));
        match role - USER_ROLE - 1 {
            0 => text(&task.id),
            1 => text(&task.app_id),
            2 => text(&task.title),
            3 => text(&task.icon),
            4 => text(&task.kind),
            5 => QVariant::from(&task.surface_id),
            6 => QVariant::from(&task.timestamp),
            _ => QVariant::default(),
        }
    }

    #[allow(clippy::unused_self, reason = "a QAbstractListModel override")]
    fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut roles = QHash::<QHashPair_i32_QByteArray>::default();
        for (role, name) in (USER_ROLE + 1..).zip(ROLES) {
            roles.insert(role, QByteArray::from(name));
        }
        roles
    }

    fn task(&self, app_id: &str) -> Option<&Task> {
        self.tasks.iter().find(|t| t.app_id == app_id)
    }

    fn task_map(task: Option<&Task>) -> Map {
        let mut map = Map::default();
        let Some(task) = task else { return map };
        let text = |s: &str| QVariant::from(&QString::from(s));
        map.insert(QString::from("id"), text(&task.id));
        map.insert(QString::from("appId"), text(&task.app_id));
        map.insert(QString::from("title"), text(&task.title));
        map.insert(QString::from("icon"), text(&task.icon));
        map.insert(QString::from("appType"), text(&task.kind));
        map.insert(QString::from("surfaceId"), QVariant::from(&task.surface_id));
        map.insert(QString::from("timestamp"), QVariant::from(&task.timestamp));
        map
    }

    fn get_task_by_app_id(&self, app_id: &QString) -> Map {
        Self::task_map(self.task(&app_id.to_string()))
    }

    fn get_task_by_surface_id(&self, surface_id: i32) -> Map {
        Self::task_map(self.tasks.iter().find(|t| t.surface_id == surface_id))
    }

    /// The list changes as a whole: a switcher has a handful of cards.
    fn set_tasks(mut self: Pin<&mut Self>, tasks: Vec<Task>) {
        let count = i32::try_from(tasks.len()).unwrap_or(i32::MAX);
        self.as_mut().begin_reset_model();
        let mut rust = self.as_mut().rust_mut();
        rust.tasks = tasks;
        rust.task_count = count;
        self.as_mut().end_reset_model();
        self.as_mut().task_count_changed();
        self.refresh_secure();
    }

    fn launch_task(
        self: Pin<&mut Self>,
        app_id: &QString,
        name: &QString,
        icon: &QString,
        kind: &QString,
        surface_id: i32,
    ) {
        self.add_task(
            &app_id.to_string(),
            &name.to_string(),
            &icon.to_string(),
            &kind.to_string(),
            surface_id,
        );
    }

    fn add_task(
        mut self: Pin<&mut Self>,
        app_id: &str,
        name: &str,
        icon: &str,
        kind: &str,
        surface_id: i32,
    ) {
        if self.task(app_id).is_some() {
            return;
        }
        let id = {
            let mut rust = self.as_mut().rust_mut();
            rust.next_task += 1;
            format!("task_{}", rust.next_task)
        };
        let task = Task {
            id: id.clone(),
            app_id: app_id.to_owned(),
            title: name.to_owned(),
            icon: icon.to_owned(),
            kind: kind.to_owned(),
            surface_id,
            timestamp: now_ms(),
        };
        let mut tasks = self.tasks.clone();
        tasks.insert(0, task);
        self.as_mut().set_tasks(tasks);
        self.task_launched(&QString::from(&id));
    }

    fn close_task(self: Pin<&mut Self>, task_id: &QString) {
        let id = task_id.to_string();
        self.remove_task(|t| t.id == id);
    }

    fn close_task_of(self: Pin<&mut Self>, app_id: &str) {
        self.remove_task(|t| t.app_id == app_id);
    }

    fn remove_task(mut self: Pin<&mut Self>, which: impl Fn(&Task) -> bool) {
        let Some(task) = self.tasks.iter().find(|t| which(t)).cloned() else {
            return;
        };
        let tasks = self
            .tasks
            .iter()
            .filter(|t| t.id != task.id)
            .cloned()
            .collect();
        self.as_mut().set_tasks(tasks);
        self.task_closed(&QString::from(&task.id));
    }

    fn move_to_front(mut self: Pin<&mut Self>, app_id: &str) {
        let Some(at) = self.tasks.iter().position(|t| t.app_id == app_id) else {
            return;
        };
        if at > 0 {
            let mut tasks = self.tasks.clone();
            let task = tasks.remove(at);
            tasks.insert(0, task);
            self.as_mut().set_tasks(tasks);
        }
    }

    /// The task shows the window; a native one, whatever it started as.
    fn update_task_window(mut self: Pin<&mut Self>, app_id: &str, surface_id: i32) {
        let mut tasks = self.tasks.clone();
        let Some(task) = tasks.iter_mut().find(|t| t.app_id == app_id) else {
            return;
        };
        "native".clone_into(&mut task.kind);
        task.surface_id = surface_id;
        self.as_mut().set_tasks(tasks);
    }

    /// A secure app stays secure until its card goes.
    fn refresh_secure(mut self: Pin<&mut Self>) {
        let ids: HashSet<String> = self.tasks.iter().map(|t| t.app_id.clone()).collect();
        let mut rust = self.as_mut().rust_mut();
        for (app, had_card) in &mut rust.secure {
            *had_card |= ids.contains(app);
        }
        let before = rust.secure.len();
        rust.secure
            .retain(|app, had_card| !*had_card || ids.contains(app));
        if rust.secure.len() != before {
            self.publish_secure();
        }
    }

    fn publish_secure(mut self: Pin<&mut Self>) {
        let mut list = QList::<QString>::default();
        for app in self.secure.keys() {
            list.append(QString::from(app));
        }
        self.as_mut().rust_mut().secure_apps = QStringList::from(&list);
        self.secure_apps_changed();
    }

    fn set_app_secure(mut self: Pin<&mut Self>, app_id: &QString, secure: bool) {
        let app = app_id.to_string();
        if secure == self.secure.contains_key(&app) {
            return;
        }
        let had_card = self.task(&app).is_some();
        let mut rust = self.as_mut().rust_mut();
        if secure {
            rust.secure.insert(app, had_card);
        } else {
            rust.secure.remove(&app);
        }
        self.publish_secure();
    }

    fn set_device(mut self: Pin<&mut Self>, device: &Map) {
        let text = |k: &str| {
            device
                .get(&QString::from(k))
                .and_then(|v| v.value::<QString>())
                .map(|s| s.to_string())
                .unwrap_or_default()
        };
        let int = |k: &str| {
            device
                .get(&QString::from(k))
                .and_then(|v| v.value::<i32>())
                .unwrap_or_default()
        };
        let real = |k: &str| {
            device
                .get(&QString::from(k))
                .and_then(|v| v.value::<f64>())
                .unwrap_or_default()
        };
        let profile = &*crate::device::VALUES;
        let (runner_width, runner_height) = profile.runner_size();
        let user_scale = self.device.user_scale;
        let viewport = (self.device.viewport_width, self.device.viewport_height);
        self.as_mut().rust_mut().device = Device {
            render_node: profile.render_node(),
            gpu_webgl: profile.gpu_stack() == "mesa-v3d",
            runner_pool: profile.runner_pool(),
            runner_width,
            runner_height,
            thumbnails: text("thumbnails"),
            dpi: real("dpi"),
            screen_width: int("screenWidth"),
            screen_height: int("screenHeight"),
            user_scale,
            viewport_width: viewport.0,
            viewport_height: viewport.1,
        };
    }

    fn set_user_scale(mut self: Pin<&mut Self>, scale: f64) {
        self.as_mut().rust_mut().device.user_scale = scale;
    }

    fn set_app_viewport(mut self: Pin<&mut Self>, width: i32, height: i32) {
        let mut rust = self.as_mut().rust_mut();
        rust.device.viewport_width = width;
        rust.device.viewport_height = height;
    }

    /// The app in front: "" on the home screen, the switcher or the lock
    /// screen.
    fn set_shell_state(
        mut self: Pin<&mut Self>,
        app_window_open: bool,
        current_app_id: &QString,
        locked: bool,
        quick_settings_open: bool,
    ) {
        let mut rust = self.as_mut().rust_mut();
        if rust.current_app_id != current_app_id.to_string() || locked || !app_window_open {
            let previous = rust.current_app_id.clone();
            rust.android_handoffs.remove(&previous);
        }
        rust.quick_settings_open = quick_settings_open;
        rust.app_window_open = app_window_open;
        rust.current_app_id = current_app_id.to_string();
        rust.locked = locked;
        let front = if app_window_open && !locked {
            current_app_id.clone()
        } else {
            QString::default()
        };
        if self.foreground_app_id != front {
            self.as_mut().rust_mut().foreground_app_id = front.clone();
            self.as_mut().foreground_app_id_changed();
            dbus::foreground_changed(&front.to_string());
            self.set_front_app(&front);
        }
    }
}

fn q(s: &str) -> QString {
    QString::from(s)
}

fn later(qt: Qt, after: std::time::Duration, f: impl FnOnce(Pin<&mut Tasks>) + Send + 'static) {
    crate::io::spawn(async move {
        async_io::Timer::after(after).await;
        qt.queue(f).ok();
    });
}

/// A sandbox instance's id.
fn launch_uuid() -> String {
    std::fs::read_to_string("/proc/sys/kernel/random/uuid")
        .unwrap_or_default()
        .trim()
        .to_owned()
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| i64::try_from(d.as_millis()).unwrap_or(0))
}
