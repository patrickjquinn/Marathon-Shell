//! `AndroidApps`: Android apps as Settings shows them, from deckardd's
//! org.marathonos.Deckard1 and org.marathonos.Deckard1.Packages
//! (Marathon-Deckard protocol/bridge.md).

use std::collections::{HashMap, HashSet};
use std::pin::Pin;

use cxx_qt::{CxxQtThread, CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QVariant};
use futures_lite::StreamExt;
use zbus::zvariant::OwnedValue;

use crate::variant;
use marathon_rt::{io, log};

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qvariant.h");
        type QVariant = cxx_qt_lib::QVariant;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, available, READ, NOTIFY)]
        #[qproperty(QMap_QString_QVariant, runtime, READ, NOTIFY)]
        #[qproperty(QList_QVariant, apps, READ, NOTIFY)]
        /// microG: {installed, enabled, push, accounts}; empty until loaded.
        #[qproperty(QMap_QString_QVariant, google_services, cxx_name = "googleServices", READ, NOTIFY)]
        type AndroidApps = super::AndroidAppsRust;

        #[qsignal]
        #[cxx_name = "appLoaded"]
        fn app_loaded(self: Pin<&mut Self>, pkg: &QString, app: &QMap_QString_QVariant);
        #[qsignal]
        #[cxx_name = "appChanged"]
        fn app_changed(self: Pin<&mut Self>, pkg: &QString);
        #[qsignal]
        #[cxx_name = "appRemoved"]
        fn app_removed(self: Pin<&mut Self>, pkg: &QString);
        #[qsignal]
        #[cxx_name = "specialAccessLoaded"]
        fn special_access_loaded(self: Pin<&mut Self>, kind: &QString, apps: &QList_QVariant);
        #[qsignal]
        #[cxx_name = "permissionAppsLoaded"]
        fn permission_apps_loaded(self: Pin<&mut Self>, permission: &QString, apps: &QList_QVariant);
        /// `action`: the invokable's name ("clearData", "uninstall", ...).
        #[qsignal]
        fn done(self: Pin<&mut Self>, pkg: &QString, action: &QString);
        #[qsignal]
        fn failed(self: Pin<&mut Self>, pkg: &QString, action: &QString, error: &QString);

        #[qinvokable]
        fn refresh(self: &AndroidApps);
        #[qinvokable]
        #[cxx_name = "refreshRuntime"]
        fn refresh_runtime(self: &AndroidApps);
        #[qinvokable]
        fn start(self: &AndroidApps);
        #[qinvokable]
        fn stop(self: &AndroidApps);
        #[qinvokable]
        fn restart(self: &AndroidApps);
        #[qinvokable]
        #[cxx_name = "setStartAtLogin"]
        fn set_start_at_login(self: &AndroidApps, enabled: bool);
        #[qinvokable]
        #[cxx_name = "resetAndroid"]
        fn reset_android(self: &AndroidApps);
        #[qinvokable]
        #[cxx_name = "loadApp"]
        fn load_app(self: Pin<&mut AndroidApps>, pkg: &QString);
        /// `permission`: a Marathon permission name ("camera", "storage", ...).
        #[qinvokable]
        #[cxx_name = "setPermission"]
        fn set_permission(self: &AndroidApps, pkg: &QString, permission: &QString, granted: bool);
        #[qinvokable]
        #[cxx_name = "loadPermissionApps"]
        fn load_permission_apps(self: &AndroidApps, permission: &QString);
        #[qinvokable]
        #[cxx_name = "setNotifications"]
        fn set_notifications(self: &AndroidApps, pkg: &QString, enabled: bool);
        #[qinvokable]
        #[cxx_name = "setOpenLinks"]
        fn set_open_links(self: &AndroidApps, pkg: &QString, enabled: bool);
        #[qinvokable]
        #[cxx_name = "setBattery"]
        fn set_battery(self: &AndroidApps, pkg: &QString, mode: &QString);
        #[qinvokable]
        #[cxx_name = "forceStop"]
        fn force_stop(self: &AndroidApps, pkg: &QString);
        #[qinvokable]
        #[cxx_name = "clearCache"]
        fn clear_cache(self: &AndroidApps, pkg: &QString);
        #[qinvokable]
        #[cxx_name = "clearData"]
        fn clear_data(self: &AndroidApps, pkg: &QString);
        #[qinvokable]
        fn uninstall(self: Pin<&mut AndroidApps>, pkg: &QString);
        #[qinvokable]
        #[cxx_name = "loadSpecialAccess"]
        fn load_special_access(self: &AndroidApps, kind: &QString);
        #[qinvokable]
        #[cxx_name = "setSpecialAccess"]
        fn set_special_access(self: &AndroidApps, kind: &QString, pkg: &QString, granted: bool);
        #[qinvokable]
        #[cxx_name = "loadGoogleServices"]
        fn load_google_services(self: &AndroidApps);
        /// `key`: "enabled" or "push".
        #[qinvokable]
        #[cxx_name = "setGoogleServices"]
        fn set_google_services(self: &AndroidApps, key: &QString, enabled: bool);
        /// `page`: "account" (sign in) or "selfcheck".
        #[qinvokable]
        #[cxx_name = "openGoogleServices"]
        fn open_google_services(self: &AndroidApps, page: &QString);
    }

    impl cxx_qt::Threading for AndroidApps {}
    impl cxx_qt::Initialize for AndroidApps {}
}

use qobject::AndroidApps;

type Qt = CxxQtThread<AndroidApps>;
type Map = HashMap<String, OwnedValue>;

#[zbus::proxy(interface = "org.marathonos.Deckard1", default_service = "org.marathonos.Deckard", default_path = "/org/marathonos/Deckard")]
trait Deckard {
    fn get_runtime(&self) -> zbus::Result<Map>;
    fn app_icon(&self, pkg: &str) -> zbus::Result<String>;
    fn get_app(&self, pkg: &str) -> zbus::Result<Map>;
    fn get_permission_apps(&self, permission: &str) -> zbus::Result<Vec<Map>>;
    fn get_special_access(&self, kind: &str) -> zbus::Result<Vec<Map>>;
    fn get_google_services(&self) -> zbus::Result<Map>;
    fn reset_android(&self) -> zbus::Result<()>;
    #[zbus(signal)]
    fn runtime_changed(&self, runtime: Map) -> zbus::Result<()>;
    #[zbus(signal)]
    fn app_changed(&self, pkg: String) -> zbus::Result<()>;
}

#[zbus::proxy(interface = "org.marathonos.Deckard1.Packages", default_service = "org.marathonos.Deckard", default_path = "/org/marathonos/Deckard")]
trait Packages {
    fn list_packages(&self) -> zbus::Result<Vec<Map>>;
    fn uninstall_package(&self, pkg: &str) -> zbus::Result<String>;
    #[zbus(signal)]
    fn package_changed(&self, pkg: String, change: String) -> zbus::Result<()>;
    #[zbus(signal)]
    fn finished(&self, job: String, ok: bool, pkg: String, message: String) -> zbus::Result<()>;
}

async fn deckard() -> zbus::Result<DeckardProxy<'static>> {
    DeckardProxy::new(&io::session_bus().await?).await
}

async fn packages() -> zbus::Result<PackagesProxy<'static>> {
    PackagesProxy::new(&io::session_bus().await?).await
}

#[derive(Default)]
pub struct AndroidAppsRust {
    available: bool,
    runtime: QMap<QMapPair_QString_QVariant>,
    apps: QList<QVariant>,
    google_services: QMap<QMapPair_QString_QVariant>,
    icons: HashMap<String, String>,
    // An uninstall's job, to its package.
    jobs: HashMap<String, String>,
    // Asked, not yet answered.
    uninstalling: HashSet<String>,
}

fn q(s: &str) -> QString {
    QString::from(s)
}

fn text(m: &Map, key: &str) -> String {
    m.get(key).and_then(|v| <&str>::try_from(&**v).ok()).unwrap_or_default().to_owned()
}

impl cxx_qt::Initialize for AndroidApps {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        io::spawn(follow(qt));
        self.refresh();
    }
}

/// deckardd's signals and its comings and goings.
async fn follow(qt: Qt) {
    let follow = async {
        let (d, p) = (deckard().await?, packages().await?);
        let runtime = d.receive_runtime_changed().await?.filter_map(|s| s.args().ok().map(|a| Event::Runtime(a.runtime)));
        let app = d.receive_app_changed().await?.filter_map(|s| s.args().ok().map(|a| Event::App(a.pkg)));
        let package = p.receive_package_changed().await?.filter_map(|s| s.args().ok().map(|a| Event::Package(a.pkg, a.change)));
        let finished = p.receive_finished().await?.filter_map(|s| s.args().ok().map(|a| Event::Finished(a.job, a.ok, a.pkg, a.message)));
        let owner = d.inner().receive_owner_changed().await?.map(|o| Event::Owner(o.is_some()));
        let mut events = runtime.boxed().or(app.boxed()).or(package.boxed()).or(finished.boxed()).or(owner.boxed());
        while let Some(event) = events.next().await {
            qt.queue(move |obj| obj.on_event(event)).ok();
        }
        zbus::Result::Ok(())
    };
    if let Err(e) = follow.await {
        log::warn("android", format_args!("not following deckardd: {e}"));
    }
}

enum Event {
    Runtime(Map),
    App(String),
    Package(String, String),
    Finished(String, bool, String, String),
    Owner(bool),
}

impl AndroidApps {
    fn on_event(mut self: Pin<&mut Self>, event: Event) {
        match event {
            Event::Runtime(r) => self.set_runtime_map(&r),
            Event::App(pkg) => self.app_changed(&q(&pkg)),
            // A removed app has no details left to load: its page closes instead.
            Event::Package(pkg, change) => {
                self.refresh();
                if change == "removed" {
                    self.as_mut().app_removed(&q(&pkg));
                } else {
                    self.as_mut().app_changed(&q(&pkg));
                }
            }
            // Finished can come before the reply that names the job, so the
            // package matches too.
            Event::Finished(job, ok, finished_pkg, message) => {
                let mut rust = self.as_mut().rust_mut();
                let pkg = rust.jobs.remove(&job).or_else(|| rust.uninstalling.contains(&finished_pkg).then_some(finished_pkg));
                let Some(pkg) = pkg.filter(|p| rust.uninstalling.remove(p)) else { return };
                if ok {
                    self.as_mut().done(&q(&pkg), &q("uninstall"));
                } else {
                    let message = if message.is_empty() { "Android refused".to_owned() } else { message };
                    self.as_mut().failed(&q(&pkg), &q("uninstall"), &q(&message));
                }
                self.refresh();
            }
            Event::Owner(true) => self.refresh(),
            Event::Owner(false) => {
                self.as_mut().set_available_flag(false);
                self.as_mut().rust_mut().apps = QList::default();
                self.apps_changed();
            }
        }
    }

    fn set_available_flag(mut self: Pin<&mut Self>, available: bool) {
        if self.available != available {
            self.as_mut().rust_mut().available = available;
            self.available_changed();
        }
    }

    fn set_runtime_map(mut self: Pin<&mut Self>, runtime: &Map) {
        self.as_mut().rust_mut().runtime = variant::qmap(runtime);
        self.runtime_changed();
    }

    /// Each package with its icon, as far as it is known.
    fn with_icons(&self, apps: Vec<Map>) -> QList<QVariant> {
        let mut list = QList::<QVariant>::default();
        for app in apps {
            let mut map = variant::qmap(&app);
            map.insert(q("icon"), QVariant::from(&q(self.icons.get(&text(&app, "pkg")).map_or("", String::as_str))));
            list.append(QVariant::from(&map));
        }
        list
    }

    fn refresh(&self) {
        self.refresh_runtime();
        let qt = self.qt_thread();
        io::spawn(async move {
            let Ok(packages) = async { packages().await?.list_packages().await }.await else { return };
            qt.queue(move |obj| obj.set_packages(packages)).ok();
        });
    }

    fn set_packages(mut self: Pin<&mut Self>, packages: Vec<Map>) {
        let mut apps: Vec<(String, Map)> = packages
            .into_iter()
            .filter(|p| !text(p, "pkg").is_empty() && !p.get("system").is_some_and(|s| bool::try_from(&**s).unwrap_or(false)))
            .map(|p| {
                let (pkg, label) = (text(&p, "pkg"), text(&p, "label"));
                let mut app = Map::new();
                app.insert("pkg".into(), OwnedValue::from(zbus::zvariant::Str::from(pkg.clone())));
                app.insert("id".into(), OwnedValue::from(zbus::zvariant::Str::from(format!("waydroid.{pkg}"))));
                app.insert("name".into(), OwnedValue::from(zbus::zvariant::Str::from(if label.is_empty() { pkg.clone() } else { label })));
                if let Some(v) = p.get("versionName").and_then(|v| v.try_clone().ok()) {
                    app.insert("version".into(), v);
                }
                (pkg, app)
            })
            .collect();
        apps.sort_by_key(|(_, a)| text(a, "name").to_lowercase());
        let missing: Vec<String> = apps.iter().map(|(pkg, _)| pkg.clone()).filter(|p| !self.icons.contains_key(p)).collect();
        let list = self.with_icons(apps.into_iter().map(|(_, a)| a).collect());
        self.as_mut().rust_mut().apps = list;
        self.as_mut().apps_changed();
        for pkg in missing {
            self.as_mut().load_icon(pkg);
        }
    }

    fn load_icon(mut self: Pin<&mut Self>, pkg: String) {
        self.as_mut().rust_mut().icons.insert(pkg.clone(), String::new());
        let qt = self.qt_thread();
        io::spawn(async move {
            let Ok(icon) = async { deckard().await?.app_icon(&pkg).await }.await else { return };
            if icon.is_empty() {
                return;
            }
            qt.queue(move |mut obj| {
                obj.as_mut().rust_mut().icons.insert(pkg.clone(), icon.clone());
                let mut apps = QList::<QVariant>::default();
                for app in &obj.apps {
                    let mut map = app.value::<QMap<QMapPair_QString_QVariant>>().unwrap_or_default();
                    if map.get(&q("pkg")).and_then(|p| p.value::<QString>()).is_some_and(|p| p.to_string() == pkg) {
                        map.insert(q("icon"), QVariant::from(&q(&icon)));
                    }
                    apps.append(QVariant::from(&map));
                }
                obj.as_mut().rust_mut().apps = apps;
                obj.apps_changed();
            })
            .ok();
        });
    }

    fn refresh_runtime(&self) {
        let qt = self.qt_thread();
        io::spawn(async move {
            let runtime = async { deckard().await?.get_runtime().await }.await;
            qt.queue(move |mut obj| {
                obj.as_mut().set_available_flag(runtime.is_ok());
                if let Ok(r) = runtime {
                    obj.set_runtime_map(&r);
                }
            })
            .ok();
        });
    }

    /// `method` on Deckard1 with `body`, then `done` or `failed` for `action`.
    fn act<B>(&self, action: &'static str, pkg: &QString, method: &'static str, body: B)
    where
        B: serde::Serialize + zbus::zvariant::DynamicType + Send + Sync + 'static,
    {
        let (qt, pkg) = (self.qt_thread(), pkg.to_string());
        io::spawn(async move {
            let reply = async { deckard().await?.inner().call_method(method, &body).await }.await;
            qt.queue(move |obj| match reply {
                Ok(_) => obj.done(&q(&pkg), &q(action)),
                Err(e) => obj.failed(&q(&pkg), &q(action), &q(&crate::shell::message(&e))),
            })
            .ok();
        });
    }

    fn start(&self) {
        self.act("start", &QString::default(), "Start", ());
    }

    fn stop(&self) {
        self.act("stop", &QString::default(), "Stop", ());
    }

    fn restart(&self) {
        self.act("restart", &QString::default(), "Restart", ());
    }

    fn set_start_at_login(&self, enabled: bool) {
        self.act("setStartAtLogin", &QString::default(), "SetStartAtLogin", (enabled,));
    }

    fn set_permission(&self, pkg: &QString, permission: &QString, granted: bool) {
        self.act("setPermission", pkg, "SetPermission", (pkg.to_string(), permission.to_string(), granted));
    }

    fn set_notifications(&self, pkg: &QString, enabled: bool) {
        self.act("setNotifications", pkg, "SetNotifications", (pkg.to_string(), enabled));
    }

    fn set_open_links(&self, pkg: &QString, enabled: bool) {
        self.act("setOpenLinks", pkg, "SetOpenLinks", (pkg.to_string(), enabled));
    }

    fn set_battery(&self, pkg: &QString, mode: &QString) {
        self.act("setBattery", pkg, "SetBattery", (pkg.to_string(), mode.to_string()));
    }

    fn force_stop(&self, pkg: &QString) {
        self.act("forceStop", pkg, "ForceStop", (pkg.to_string(),));
    }

    fn clear_cache(&self, pkg: &QString) {
        self.act("clearCache", pkg, "ClearCache", (pkg.to_string(),));
    }

    fn clear_data(&self, pkg: &QString) {
        self.act("clearData", pkg, "ClearData", (pkg.to_string(),));
    }

    fn set_special_access(&self, kind: &QString, pkg: &QString, granted: bool) {
        self.act("setSpecialAccess", pkg, "SetSpecialAccess", (kind.to_string(), pkg.to_string(), granted));
    }

    fn open_google_services(&self, page: &QString) {
        self.act("openGoogleServices", &QString::default(), "OpenGoogleServices", (page.to_string(),));
    }

    fn reset_android(&self) {
        let qt = self.qt_thread();
        io::spawn(async move {
            let reply = async { deckard().await?.reset_android().await }.await;
            qt.queue(move |mut obj| {
                if let Err(e) = reply {
                    return obj.failed(&QString::default(), &q("reset"), &q(&crate::shell::message(&e)));
                }
                // Android is stopped, so ListPackages can't say the apps are gone.
                let mut rust = obj.as_mut().rust_mut();
                rust.apps = QList::default();
                rust.icons.clear();
                obj.as_mut().apps_changed();
                obj.done(&QString::default(), &q("reset"));
            })
            .ok();
        });
    }

    fn load_app(mut self: Pin<&mut Self>, pkg: &QString) {
        let (qt, id) = (self.qt_thread(), pkg.to_string());
        let name = id.clone();
        io::spawn(async move {
            let app = async { deckard().await?.get_app(&name).await }.await;
            qt.queue(move |obj| match app {
                Ok(app) => {
                    let mut map = variant::qmap(&app);
                    map.insert(q("icon"), QVariant::from(&q(obj.icons.get(&name).map_or("", String::as_str))));
                    obj.app_loaded(&q(&name), &map);
                }
                Err(e) => obj.failed(&q(&name), &q("loadApp"), &q(&crate::shell::message(&e))),
            })
            .ok();
        });
        if !self.icons.contains_key(&id) {
            self.as_mut().load_icon(id);
        }
    }

    fn load_permission_apps(&self, permission: &QString) {
        let (qt, permission) = (self.qt_thread(), permission.to_string());
        io::spawn(async move {
            let apps = async { deckard().await?.get_permission_apps(&permission).await }.await.unwrap_or_default();
            qt.queue(move |obj| {
                let list = obj.with_icons(apps);
                obj.permission_apps_loaded(&q(&permission), &list);
            })
            .ok();
        });
    }

    fn load_special_access(&self, kind: &QString) {
        let (qt, kind) = (self.qt_thread(), kind.to_string());
        io::spawn(async move {
            let apps = async { deckard().await?.get_special_access(&kind).await }.await;
            qt.queue(move |obj| match apps {
                Ok(apps) => {
                    let list = obj.with_icons(apps);
                    obj.special_access_loaded(&q(&kind), &list);
                }
                Err(e) => obj.failed(&QString::default(), &q("loadSpecialAccess"), &q(&crate::shell::message(&e))),
            })
            .ok();
        });
    }

    fn uninstall(mut self: Pin<&mut Self>, pkg: &QString) {
        let (qt, pkg) = (self.qt_thread(), pkg.to_string());
        self.as_mut().rust_mut().uninstalling.insert(pkg.clone());
        io::spawn(async move {
            let reply = async { packages().await?.uninstall_package(&pkg).await }.await;
            qt.queue(move |mut obj| {
                let job = reply.as_deref().unwrap_or_default().to_owned();
                let mut rust = obj.as_mut().rust_mut();
                if !job.is_empty() && rust.uninstalling.contains(&pkg) {
                    rust.jobs.insert(job, pkg);
                } else if job.is_empty() && rust.uninstalling.remove(&pkg) {
                    let error = reply.err().map(|e| crate::shell::message(&e)).filter(|e| !e.is_empty()).unwrap_or_else(|| "Android refused".into());
                    obj.failed(&q(&pkg), &q("uninstall"), &q(&error));
                }
            })
            .ok();
        });
    }

    fn load_google_services(&self) {
        let qt = self.qt_thread();
        io::spawn(async move {
            let google = async { deckard().await?.get_google_services().await }.await.unwrap_or_default();
            qt.queue(move |mut obj| {
                obj.as_mut().rust_mut().google_services = variant::qmap(&google);
                obj.google_services_changed();
            })
            .ok();
        });
    }

    fn set_google_services(&self, key: &QString, enabled: bool) {
        let (qt, key) = (self.qt_thread(), key.to_string());
        io::spawn(async move {
            let reply = async { deckard().await?.inner().call_method("SetGoogleServices", &(key, enabled)).await }.await;
            qt.queue(move |mut obj| {
                if let Err(e) = reply {
                    obj.as_mut().failed(&QString::default(), &q("setGoogleServices"), &q(&crate::shell::message(&e)));
                }
                obj.load_google_services();
            })
            .ok();
        });
    }
}
