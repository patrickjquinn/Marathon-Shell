//! `AppStore` and `AppInstaller`: the shell's `AppStore1`, the catalogue,
//! downloads and uninstalling.

use std::collections::{BTreeSet, HashMap};
use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QVariant};

use crate::shell::{get, mirror, relay, Service, Update};
use marathon_rt::io;

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, catalog_loaded, cxx_name = "catalogLoaded", READ, NOTIFY = state_changed)]
        #[qproperty(bool, loading, READ, NOTIFY = state_changed)]
        #[qproperty(QString, repository_url, cxx_name = "repositoryUrl", READ, NOTIFY = state_changed)]
        type AppStore = super::AppStoreRust;

        #[qsignal]
        #[cxx_name = "stateChanged"]
        fn state_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "catalogRefreshed"]
        fn catalog_refreshed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "downloadProgress"]
        fn download_progress(self: Pin<&mut Self>, app_id: &QString, bytes_received: i64, bytes_total: i64);
        #[qsignal]
        #[cxx_name = "downloadComplete"]
        fn download_complete(self: Pin<&mut Self>, app_id: &QString, package_path: &QString);
        #[qsignal]
        #[cxx_name = "downloadFailed"]
        fn download_failed(self: Pin<&mut Self>, app_id: &QString, error: &QString);

        #[qinvokable]
        #[cxx_name = "refreshCatalog"]
        fn refresh_catalog(self: &AppStore);
        #[qinvokable]
        #[cxx_name = "searchApps"]
        fn search_apps(self: &AppStore, query: &QString) -> QList_QVariant;
        #[qinvokable]
        #[cxx_name = "getApp"]
        fn get_app(self: &AppStore, app_id: &QString) -> QMap_QString_QVariant;
        #[qinvokable]
        #[cxx_name = "getFeaturedApps"]
        fn get_featured_apps(self: &AppStore) -> QList_QVariant;
        #[qinvokable]
        #[cxx_name = "getAppsByCategory"]
        fn get_apps_by_category(self: &AppStore, category: &QString) -> QList_QVariant;
        #[qinvokable]
        #[cxx_name = "getAvailableUpdates"]
        fn get_available_updates(self: &AppStore) -> QList_QVariant;
        #[qinvokable]
        #[cxx_name = "checkForUpdates"]
        fn check_for_updates(self: &AppStore);
        #[qinvokable]
        #[cxx_name = "downloadApp"]
        fn download_app(self: &AppStore, app_id: &QString);
        #[qinvokable]
        #[cxx_name = "cancelDownload"]
        fn cancel_download(self: &AppStore, app_id: &QString);
    }

    extern "RustQt" {
        #[qobject]
        type AppInstaller = super::AppInstallerRust;

        #[qsignal]
        #[cxx_name = "uninstallComplete"]
        fn uninstall_complete(self: Pin<&mut Self>, app_id: &QString);
        #[qsignal]
        #[cxx_name = "uninstallFailed"]
        fn uninstall_failed(self: Pin<&mut Self>, app_id: &QString, error: &QString);
        /// Any uninstall, this app's or not.
        #[qsignal]
        #[cxx_name = "appRemoved"]
        fn app_removed(self: Pin<&mut Self>, app_id: &QString);

        #[qinvokable]
        #[cxx_name = "canUninstall"]
        fn can_uninstall(self: Pin<&mut AppInstaller>, app_id: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "uninstallApp"]
        fn uninstall_app(self: Pin<&mut AppInstaller>, app_id: &QString);
    }

    impl cxx_qt::Threading for AppStore {}
    impl cxx_qt::Initialize for AppStore {}
    impl cxx_qt::Threading for AppInstaller {}
    impl cxx_qt::Initialize for AppInstaller {}
}

use qobject::{AppInstaller, AppStore};

const STORE: Service = Service("AppStore");

#[derive(Default)]
pub struct AppStoreRust {
    catalog_loaded: bool,
    loading: bool,
    repository_url: QString,
}

impl cxx_qt::Initialize for AppStore {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        relay(qt.clone(), STORE, "CatalogRefreshed", |obj, ()| obj.catalog_refreshed());
        relay(qt.clone(), STORE, "DownloadProgress", |obj, (id, got, total): (String, i64, i64)| {
            obj.download_progress(&QString::from(&id), got, total);
        });
        relay(qt.clone(), STORE, "DownloadComplete", |obj, (id, path): (String, String)| {
            obj.download_complete(&QString::from(&id), &QString::from(&path));
        });
        relay(qt.clone(), STORE, "DownloadFailed", |obj, (id, error): (String, String)| {
            obj.download_failed(&QString::from(&id), &QString::from(&error));
        });
        mirror(qt, STORE, "system", |mut obj, update| {
            let Update::State(s) = update else { return };
            let mut a = obj.as_mut().rust_mut();
            a.catalog_loaded = get(&s, "catalogLoaded");
            a.loading = get(&s, "loading");
            a.repository_url = get(&s, "repositoryUrl");
            obj.state_changed();
        });
    }
}

impl AppStore {
    crate::shell::calls! { STORE;
        refresh_catalog() => "RefreshCatalog";
        check_for_updates() => "CheckForUpdates";
        download_app(app_id: &QString) => "DownloadApp";
        cancel_download(app_id: &QString) => "CancelDownload";
    }
    crate::shell::asks! { STORE;
        search_apps(query: &QString) -> QList<QVariant> => "SearchApps";
        get_app(app_id: &QString) -> QMap<QMapPair_QString_QVariant> => "GetApp";
        get_featured_apps() -> QList<QVariant> => "GetFeaturedApps";
        get_apps_by_category(category: &QString) -> QList<QVariant> => "GetAppsByCategory";
        get_available_updates() -> QList<QVariant> => "GetAvailableUpdates";
    }
}

#[derive(Default)]
pub struct AppInstallerRust {
    /// Uninstalls this app asked for, which it hears the end of.
    pending: BTreeSet<String>,
    removable: HashMap<String, bool>,
}

impl cxx_qt::Initialize for AppInstaller {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        relay(qt.clone(), STORE, "UninstallComplete", |mut obj, (id,): (String,)| {
            obj.as_mut().rust_mut().removable.remove(&id);
            let app = QString::from(&id);
            obj.as_mut().app_removed(&app);
            if obj.as_mut().rust_mut().pending.remove(&id) {
                obj.uninstall_complete(&app);
            }
        });
        relay(qt, STORE, "UninstallFailed", |mut obj, (id, error): (String, String)| {
            if obj.as_mut().rust_mut().pending.remove(&id) {
                obj.uninstall_failed(&QString::from(&id), &QString::from(&error));
            }
        });
    }
}

impl AppInstaller {
    fn can_uninstall(mut self: Pin<&mut Self>, app_id: &QString) -> bool {
        let id = app_id.to_string();
        if let Some(known) = self.removable.get(&id) {
            return *known;
        }
        let Some(removable) = STORE.ask_now::<_, bool>("CanUninstall", &(id.clone(),)) else { return false };
        self.as_mut().rust_mut().removable.insert(id, removable);
        removable
    }

    fn uninstall_app(mut self: Pin<&mut Self>, app_id: &QString) {
        let id = app_id.to_string();
        self.as_mut().rust_mut().pending.insert(id.clone());
        let qt = self.qt_thread();
        io::spawn(async move {
            if let Err(e) = STORE.reply("Uninstall", &(id.clone(),)).await {
                let error = QString::from(&crate::shell::message(&e));
                qt.queue(move |mut obj| {
                    if obj.as_mut().rust_mut().pending.remove(&id) {
                        obj.uninstall_failed(&QString::from(&id), &error);
                    }
                })
                .ok();
            }
        });
    }
}
