//! The shell's app services, `Navigation1`, `AppLifecycle1` and `AppStore1`,
//! and its calls to the apps: a runner's `Lifecycle1`, a desktop app's
//! `org.freedesktop.Application`, Deckard's Android runtime.

use std::collections::HashMap;
use std::pin::Pin;
use std::time::Duration;

use cxx_qt_lib::QString;
use futures_lite::{future, StreamExt as _};
use serde::Serialize;
use zbus::message::Header;
use zbus::proxy::{CacheProperties, MethodFlags};
use zbus::zvariant::{DynamicType, OwnedValue, Value};
use zbus::fdo;

use super::{q, Qt, Tasks};
use crate::{apps, gate, io, ipc, log, sandbox};

pub(super) fn export(qt: Qt) {
    ipc::export("Navigation", Navigation1 { qt: qt.clone() });
    ipc::export("AppLifecycle", AppLifecycle1 { qt: qt.clone() });
    ipc::export("AppStore", AppStore1 { qt });
}

pub(super) fn foreground_changed(app_id: &str) {
    ipc::signal("Navigation", "ForegroundAppChanged", (app_id.to_owned(),));
}

pub(super) fn deep_link(app_id: &str, route: &str, params: &str) {
    ipc::signal("Navigation", "DeepLinkRequested", (app_id.to_owned(), route.to_owned(), params.to_owned()));
}

fn launched(app_id: &str, target: &str, ok: bool) {
    if ok {
        ipc::signal("Navigation", "AppLaunched", (app_id.to_owned(),));
    } else {
        ipc::signal("Navigation", "NavigationFailed", (target.to_owned(), "Failed to launch app".to_owned()));
    }
}

fn not_empty(app_id: &str) -> fdo::Result<()> {
    if app_id.is_empty() {
        return Err(fdo::Error::InvalidArgs("appId cannot be empty".into()));
    }
    Ok(())
}

async fn known_caller(h: &Header<'_>) -> fdo::Result<String> {
    ipc::caller(h).await.ok_or_else(|| fdo::Error::AccessDenied("Unknown caller".into()))
}

async fn service(h: &Header<'_>) -> fdo::Result<()> {
    if ipc::caller(h).await.is_some_and(|c| c.starts_with("service:")) {
        return Ok(());
    }
    Err(fdo::Error::AccessDenied("Only a session service may ask".into()))
}

struct Navigation1 {
    qt: Qt,
}

// Launching needs no permission: it shows nothing a tap on the home grid
// would not.
#[zbus::interface(name = "org.marathonos.Shell.Navigation1")]
impl Navigation1 {
    async fn launch_app(&self, app_id: String) -> fdo::Result<bool> {
        not_empty(&app_id)?;
        let id = app_id.clone();
        let ok = ipc::on_gui(&self.qt, move |obj| obj.launch(&id)).await?;
        launched(&app_id, &app_id, ok);
        Ok(ok)
    }

    /// Starts the app without bringing it to the front (Pilot's overlay).
    async fn start_app_in_background(&self, app_id: String) -> fdo::Result<bool> {
        not_empty(&app_id)?;
        let id = q(&app_id);
        let ok = ipc::on_gui(&self.qt, move |obj| obj.start_app_in_background(&id)).await?;
        launched(&app_id, &app_id, ok);
        Ok(ok)
    }

    async fn navigate(&self, uri: String, #[zbus(header)] h: Header<'_>) -> fdo::Result<bool> {
        known_caller(&h).await?;
        let Some(path) = uri.strip_prefix("marathon://") else { return Err(fdo::Error::InvalidArgs("URI must start with marathon://".into())) };
        let app_id = path.split('/').next().unwrap_or_default().to_owned();
        if app_id.is_empty() {
            return Err(fdo::Error::InvalidArgs("Could not parse appId from URI".into()));
        }
        let id = app_id.clone();
        let ok = ipc::on_gui(&self.qt, move |obj| obj.launch(&id)).await?;
        launched(&app_id, &uri, ok);
        Ok(ok)
    }

    /// The runner reads the route as `MARATHON_APP_ROUTE` and its parameters
    /// as `MARATHON_APP_ROUTE_PARAMS` (the lock screen's Emergency call).
    async fn launch_app_with_route(&self, app_id: String, route: String, params_json: String, #[zbus(header)] h: Header<'_>) -> fdo::Result<bool> {
        known_caller(&h).await?;
        not_empty(&app_id)?;
        let id = q(&app_id);
        let ok = ipc::on_gui(&self.qt, move |obj| obj.launch_app_with_route(&id, &q(&route), &q(&params_json))).await?;
        launched(&app_id, &app_id, ok);
        Ok(ok)
    }

    /// Services only: an app could otherwise list what else runs.
    async fn app_id_for_pid(&self, pid: u32, #[zbus(header)] h: Header<'_>) -> fdo::Result<String> {
        service(&h).await?;
        ipc::on_gui(&self.qt, move |obj| obj.app_for_pid(i64::from(pid))).await
    }

    /// "" on the home screen, the switcher or the lock screen.
    async fn get_foreground_app(&self) -> fdo::Result<String> {
        ipc::on_gui(&self.qt, |obj| obj.foreground_app_id().to_string()).await
    }

    /// Services only (Deckard): the app's window comes in front now, or
    /// the next one it maps within 10 s; false while locked.
    async fn expect_app_window(&self, app_id: String, #[zbus(header)] h: Header<'_>) -> fdo::Result<bool> {
        service(&h).await?;
        ipc::on_gui(&self.qt, move |obj| {
            if app_id.is_empty() || obj.locked {
                return false;
            }
            obj.expect_window(&q(&app_id));
            true
        })
        .await
    }

    /// Services only: off cards and screenshots until its card goes.
    async fn set_app_window_secure(&self, app_id: String, secure: bool, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        service(&h).await?;
        if !app_id.is_empty() {
            ipc::on_gui(&self.qt, move |obj| obj.set_app_secure(&q(&app_id), secure)).await?;
        }
        Ok(())
    }

    // The shade has only toggles the lock screen gates already, and QML
    // keeps it shut while locked.
    async fn show_quick_settings(&self) -> fdo::Result<bool> {
        self.quick_settings(1).await
    }

    async fn hide_quick_settings(&self) -> fdo::Result<bool> {
        self.quick_settings(0).await
    }

    async fn toggle_quick_settings(&self) -> fdo::Result<bool> {
        self.quick_settings(2).await
    }
}

impl Navigation1 {
    async fn quick_settings(&self, mode: i32) -> fdo::Result<bool> {
        ipc::on_gui(&self.qt, move |obj| obj.quick_settings_requested(mode)).await?;
        Ok(true)
    }
}

struct AppLifecycle1 {
    qt: Qt,
}

/// Background work an app claims, so it does not freeze: navigation,
/// recording, a download. Playback and calls the shell sees for itself.
#[zbus::interface(name = "org.marathonos.Shell.AppLifecycle1")]
impl AppLifecycle1 {
    /// A handle, refcounted per category; only a category the app's
    /// manifest declares.
    async fn begin_background_task(&self, category: String, reason: String, #[zbus(header)] h: Header<'_>) -> fdo::Result<u32> {
        // The app's own words, for no one yet.
        drop(reason);
        if h.sender().is_some_and(|s| !gate::in_window(s.as_str(), "BeginBackgroundTask")) {
            return Err(fdo::Error::LimitsExceeded("Rate limit exceeded".into()));
        }
        let app_id = known_caller(&h).await?;
        if !apps::get(&app_id).is_some_and(|a| a.background_capabilities.contains(&category)) {
            gate::denied(&app_id, &format!("background:{category}"));
            return Err(fdo::Error::AccessDenied(format!("Category '{category}' not declared in manifest")));
        }
        ipc::on_gui(&self.qt, move |obj| obj.begin_claim(&app_id, &category)).await
    }

    async fn end_background_task(&self, handle: u32, #[zbus(header)] h: Header<'_>) -> fdo::Result<bool> {
        let app_id = known_caller(&h).await?;
        ipc::on_gui(&self.qt, move |obj| obj.end_claim(handle, &app_id)).await
    }

    async fn get_my_capabilities(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<Vec<String>> {
        let Some(app_id) = ipc::caller(&h).await else { return Ok(Vec::new()) };
        ipc::on_gui(&self.qt, move |obj| obj.capabilities_of(&app_id)).await
    }
}

struct AppStore1 {
    qt: Qt,
}

async fn system(h: &Header<'_>) -> fdo::Result<()> {
    ipc::admit(h, "AppStore", &["system"]).await.map(drop)
}

/// What the Store's and Settings' sandboxes cannot do themselves.
#[zbus::interface(name = "org.marathonos.Shell.AppStore1")]
impl AppStore1 {
    /// flatpak --user must run outside the Store's private home. The
    /// handler checks each verb and ref; only the scheme is checked here.
    async fn run_store_url(&self, url: String, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        system(&h).await?;
        if !url.starts_with("marathon-store://") {
            return Err(fdo::Error::InvalidArgs("Not a marathon-store:// URL".into()));
        }
        let mut child = std::process::Command::new("/usr/bin/marathon-store-handler").arg(url).spawn().map_err(|e| fdo::Error::Failed(format!("Could not start marathon-store-handler: {e}")))?;
        io::spawn(async move {
            blocking::unblock(move || child.wait()).await.ok();
        });
        Ok(())
    }

    async fn can_uninstall(&self, app_id: String, #[zbus(header)] h: Header<'_>) -> fdo::Result<bool> {
        system(&h).await?;
        Ok(sandbox::is_user_installed(&app_id))
    }

    /// The outcome comes as `UninstallComplete` or `UninstallFailed`.
    async fn uninstall(&self, app_id: String, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        system(&h).await?;
        ipc::on_gui(&self.qt, move |obj| obj.uninstall_requested(&q(&app_id))).await
    }
}

impl Tasks {
    #[allow(clippy::unused_self, reason = "the installer's answer, connected in main.cpp")]
    pub(super) fn uninstall_finished(&self, app_id: &QString, error: &QString) {
        if error.is_empty() {
            ipc::signal("AppStore", "UninstallComplete", (app_id.to_string(),));
        } else {
            ipc::signal("AppStore", "UninstallFailed", (app_id.to_string(), error.to_string()));
        }
    }
}

/// The runner's bus name, as it sanitises it.
fn runner_name(app_id: &str) -> String {
    let id: String = app_id.chars().map(|c| if c.is_ascii_alphanumeric() || c == '_' { c } else { '_' }).collect();
    format!("org.marathonos.AppRunner.{id}")
}

async fn call_runner<B>(app_id: &str, method: &str, body: &B) -> zbus::Result<zbus::Message>
where
    B: Serialize + DynamicType,
{
    let bus = io::session_bus().await?;
    bus.call_method(Some(runner_name(app_id).as_str()), "/org/marathonos/AppRunner/Lifecycle", Some("org.marathonos.AppRunner.Lifecycle1"), method, body).await
}

/// Never waits: a runner may be waiting on a frame only the GUI thread sends.
pub(super) fn runner<B>(app_id: &str, method: &'static str, body: B)
where
    B: Serialize + DynamicType + Send + Sync + 'static,
{
    let id = app_id.to_owned();
    io::spawn(async move {
        call_runner(&id, method, &body).await.ok();
    });
}

/// The runner pops its own stack, or says it has nothing to pop.
pub(super) fn runner_back(qt: Qt, app_id: String) {
    io::spawn(async move {
        let handled = call_runner(&app_id, "Back", &()).await.ok().and_then(|m| m.body().deserialize::<bool>().ok()).unwrap_or(false);
        if !handled {
            qt.queue(move |obj| obj.runner_back_unhandled(&app_id)).ok();
        }
    });
}

/// `then` runs once the runner has let go of its name, or after a second.
pub(super) fn prepare_freeze(qt: Qt, app_id: String, then: impl FnOnce(Pin<&mut Tasks>, String) + Send + 'static) {
    io::spawn(async move {
        let call = async { Some(call_runner(&app_id, "PrepareFreeze", &()).await) };
        let timeout = async {
            async_io::Timer::after(Duration::from_secs(1)).await;
            None
        };
        match future::or(call, timeout).await {
            Some(Ok(_)) => {}
            Some(Err(e)) => log::warn("tasks", format_args!("PrepareFreeze for {app_id}: {e}")),
            None => log::warn("tasks", format_args!("PrepareFreeze for {app_id}: no answer")),
        }
        qt.queue(move |obj| then(obj, app_id)).ok();
    });
}

/// Whether the running app took `org.freedesktop.Application.Activate`
/// on its desktop id (a D-Bus-activatable app, `GApplication`, `KDBusService`).
pub(super) async fn activate(app_id: &str) -> bool {
    let path = format!("/{}", app_id.replace('.', "/").replace('-', "_"));
    let call = async {
        let bus = io::session_bus().await?;
        let proxy = zbus::proxy::Builder::<zbus::Proxy<'_>>::new(&bus).destination(app_id)?.path(path.as_str())?.interface("org.freedesktop.Application")?.cache_properties(CacheProperties::No).build().await?;
        proxy.call_with_flags::<_, _, ()>("Activate", MethodFlags::NoAutoStart.into(), &(HashMap::<String, Value<'_>>::new(),)).await
    };
    call.await.is_ok()
}

#[zbus::proxy(interface = "org.marathonos.Deckard1", default_service = "org.marathonos.Deckard", default_path = "/org/marathonos/Deckard")]
trait Deckard {
    fn get_runtime(&self) -> zbus::Result<HashMap<String, OwnedValue>>;
    #[zbus(signal)]
    fn runtime_changed(&self, runtime: HashMap<String, OwnedValue>) -> zbus::Result<()>;
}

fn running(runtime: &HashMap<String, OwnedValue>) -> bool {
    runtime.get("state").and_then(|v| <&str>::try_from(&**v).ok()) == Some("running")
}

/// Until deckardd says Android runs: Android boots some ten seconds after
/// its session, and drops a `waydroid app launch` before that. Without
/// deckardd, or after 90 s, it waits no more.
pub(super) async fn wait_for_android() {
    let wait = async {
        let bus = io::session_bus().await?;
        if !fdo::DBusProxy::new(&bus).await?.name_has_owner("org.marathonos.Deckard".try_into()?).await? {
            return Ok(());
        }
        let deckard = DeckardProxy::new(&bus).await?;
        let mut changes = deckard.receive_runtime_changed().await?;
        if running(&deckard.get_runtime().await?) {
            return Ok(());
        }
        while let Some(change) = changes.next().await {
            if change.args().is_ok_and(|a| running(&a.runtime)) {
                break;
            }
        }
        zbus::Result::Ok(())
    };
    let timeout = async {
        async_io::Timer::after(Duration::from_secs(90)).await;
        Ok(())
    };
    future::or(wait, timeout).await.ok();
}

/// MPRIS's playing player is an app's: by its bus name's process, else by
/// its desktop entry (a flatpak's player reaches the bus through
/// xdg-dbus-proxy, whose process is not the app's).
pub(crate) fn playback_changed(bus_name: String, desktop_entry: String, playing: bool) {
    io::spawn(async move {
        let pid = if playing { player_pid(&bus_name).await } else { None };
        super::with(move |obj| {
            let app = pid.map(|p| obj.app_for_pid(i64::from(p))).filter(|a| !a.is_empty());
            let app = app.or_else(|| (playing && obj.pid_for(&desktop_entry) > 0).then_some(desktop_entry)).unwrap_or_default();
            obj.playback(&app);
        });
    });
}

async fn player_pid(bus_name: &str) -> Option<u32> {
    let bus = io::session_bus().await.ok()?;
    fdo::DBusProxy::new(&bus).await.ok()?.get_connection_unix_process_id(bus_name.try_into().ok()?).await.ok()
}
