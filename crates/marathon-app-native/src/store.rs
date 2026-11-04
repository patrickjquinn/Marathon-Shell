//! `AppInstaller`: uninstalls through the shell's `AppStore1`, and lists the
//! installed Flatpaks.

use std::collections::{BTreeSet, HashMap};
use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QVariant};

use crate::shell::{relay, Service};
use marathon_rt::io;

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
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
        /// [{id, name}]
        #[qinvokable]
        #[cxx_name = "flatpakApps"]
        fn flatpak_apps(self: &AppInstaller) -> QList_QVariant;
    }

    impl cxx_qt::Threading for AppInstaller {}
    impl cxx_qt::Initialize for AppInstaller {}
}

use qobject::AppInstaller;

const STORE: Service = Service::shell("AppStore");

#[derive(Default)]
pub struct AppInstallerRust {
    /// Uninstalls this app asked for, which it hears the end of.
    pending: BTreeSet<String>,
    removable: HashMap<String, bool>,
}

impl cxx_qt::Initialize for AppInstaller {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        relay(
            qt.clone(),
            STORE,
            "UninstallComplete",
            |mut obj, (id,): (String,)| {
                obj.as_mut().rust_mut().removable.remove(&id);
                let app = QString::from(&id);
                obj.as_mut().app_removed(&app);
                if obj.as_mut().rust_mut().pending.remove(&id) {
                    obj.uninstall_complete(&app);
                }
            },
        );
        relay(
            qt,
            STORE,
            "UninstallFailed",
            |mut obj, (id, error): (String, String)| {
                if obj.as_mut().rust_mut().pending.remove(&id) {
                    obj.uninstall_failed(&QString::from(&id), &QString::from(&error));
                }
            },
        );
    }
}

impl AppInstaller {
    fn can_uninstall(mut self: Pin<&mut Self>, app_id: &QString) -> bool {
        let id = app_id.to_string();
        if let Some(known) = self.removable.get(&id) {
            return *known;
        }
        let Some(removable) = STORE.ask_now::<_, bool>("CanUninstall", &(id.clone(),)) else {
            return false;
        };
        self.as_mut().rust_mut().removable.insert(id, removable);
        removable
    }

    #[allow(clippy::unused_self, reason = "a QML invokable")]
    fn flatpak_apps(&self) -> QList<QVariant> {
        let apps: Vec<(String, String)> = STORE.ask_now("FlatpakApps", &()).unwrap_or_default();
        let mut list = QList::<QVariant>::default();
        for (id, name) in apps {
            let mut map = QMap::<QMapPair_QString_QVariant>::default();
            map.insert(QString::from("id"), QVariant::from(&QString::from(&id)));
            map.insert(QString::from("name"), QVariant::from(&QString::from(&name)));
            list.append(QVariant::from(&map));
        }
        list
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
