//! `AppRegistry`: the app's own entry, and with "system" every Marathon app,
//! as `Marathon.Platform`'s `Apps` (Settings' app manager and default-app
//! pickers), read from their manifests and install receipts.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{
    QByteArray, QHash, QHashPair_i32_QByteArray, QList, QMap, QMapPair_QString_QVariant,
    QModelIndex, QString, QStringList, QVariant,
};
use marathon_apps::apps::{self, App};
use marathon_rt::io;

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
        /// Roles id, name, icon, type, absolutePath, entryPoint, version,
        /// isProtected, permissions, searchKeywords, deepLinks, categories,
        /// handlesUriSchemes, defaultFor and backgroundCapabilities.
        #[qobject]
        #[base = QAbstractListModel]
        #[qproperty(i32, count, READ, NOTIFY)]
        type AppRegistry = super::AppRegistryRust;

        #[inherit]
        #[cxx_name = "beginResetModel"]
        fn begin_reset_model(self: Pin<&mut AppRegistry>);
        #[inherit]
        #[cxx_name = "endResetModel"]
        fn end_reset_model(self: Pin<&mut AppRegistry>);
        #[cxx_override]
        #[cxx_name = "rowCount"]
        fn row_count(self: &AppRegistry, parent: &QModelIndex) -> i32;
        #[cxx_override]
        fn data(self: &AppRegistry, index: &QModelIndex, role: i32) -> QVariant;
        #[cxx_override]
        #[cxx_name = "roleNames"]
        fn role_names(self: &AppRegistry) -> QHash_i32_QByteArray;

        /// Loads only `app_id`; false when there is no such app.
        fn load(self: Pin<&mut AppRegistry>, app_id: &QString) -> bool;
        /// Starts the one-shot background catalogue load for a system app.
        #[cxx_name = "loadAll"]
        fn load_all(self: Pin<&mut AppRegistry>);
        /// The entry's fields, as `roleNames` and `toolkit`, `isSystem` and
        /// `requiresQtModules`; empty for none.
        #[qinvokable]
        #[cxx_name = "getApp"]
        fn get_app(self: &AppRegistry, app_id: &QString) -> QMap_QString_QVariant;
        #[qinvokable]
        #[cxx_name = "getAllAppIds"]
        fn get_all_app_ids(self: &AppRegistry) -> QStringList;
        #[qinvokable]
        #[cxx_name = "hasApp"]
        fn has_app(self: &AppRegistry, app_id: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "isProtected"]
        fn is_protected(self: &AppRegistry, app_id: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "getBackgroundCapabilities"]
        fn get_background_capabilities(self: &AppRegistry, app_id: &QString) -> QStringList;
        /// The installer removed it.
        #[qinvokable]
        #[cxx_name = "unregisterApp"]
        fn unregister_app(self: Pin<&mut AppRegistry>, app_id: &QString);
    }

    impl cxx_qt::Threading for AppRegistry {}

    #[namespace = "marathon::apps"]
    extern "Rust" {
        /// Before the app's engine exists: whether its manifest asks for
        /// this Qt module (`webengine`).
        #[cxx_name = "requiresQtModule"]
        fn requires_qt_module(app_id: &QString, module: &QString) -> bool;
    }
}

use qobject::AppRegistry;

const ROLES: [&str; 15] = [
    "id",
    "name",
    "icon",
    "type",
    "absolutePath",
    "entryPoint",
    "version",
    "isProtected",
    "permissions",
    "searchKeywords",
    "deepLinks",
    "categories",
    "handlesUriSchemes",
    "defaultFor",
    "backgroundCapabilities",
];
const USER_ROLE: i32 = 0x0100;

#[derive(Default)]
pub struct AppRegistryRust {
    count: i32,
    apps: Vec<App>,
    may_load_all: bool,
    full_load_started: bool,
}

impl AppRegistryRust {
    fn begin_full_load(&mut self) -> bool {
        if !self.may_load_all || self.full_load_started {
            return false;
        }
        self.full_load_started = true;
        true
    }
}

fn strings(items: &[String]) -> QVariant {
    let mut l = QList::<QString>::default();
    for s in items {
        l.append(QString::from(s));
    }
    QVariant::from(&QStringList::from(&l))
}

fn field(app: &App, name: &str) -> QVariant {
    let text = |s: &str| QVariant::from(&QString::from(s));
    match name {
        "id" => text(&app.id),
        "name" => text(&app.name),
        "icon" => text(&app.icon),
        // MarathonAppRegistry::AppType's Marathon.
        "type" => QVariant::from(&1_i32),
        "absolutePath" => text(&app.path.to_string_lossy()),
        "entryPoint" => text(&app.entry_point),
        "version" => text(&app.version),
        "toolkit" => text(&app.toolkit),
        "isProtected" => QVariant::from(&app.is_protected),
        "isSystem" => QVariant::from(&app.is_system),
        "permissions" => strings(&app.permissions),
        "searchKeywords" => strings(&app.search_keywords),
        "deepLinks" => text(&app.deep_links_json()),
        "categories" => strings(&app.categories),
        "handlesUriSchemes" => strings(&app.handles_uri_schemes),
        "defaultFor" => strings(&app.default_for),
        "backgroundCapabilities" => strings(&app.background_capabilities),
        "requiresQtModules" => strings(&app.requires_qt_modules),
        _ => QVariant::default(),
    }
}

fn requires_qt_module(app_id: &QString, module: &QString) -> bool {
    let module = module.to_string();
    apps::find(&app_id.to_string()).is_some_and(|a| a.requires_qt_modules.contains(&module))
}

fn initial_apps(app: App) -> (Vec<App>, bool) {
    let load_all = app
        .permissions
        .iter()
        .any(|permission| permission == "system");
    (vec![app], load_all)
}

impl AppRegistry {
    fn row_count(&self, parent: &QModelIndex) -> i32 {
        if parent.is_valid() {
            0
        } else {
            self.count
        }
    }

    fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
        let app = usize::try_from(index.row())
            .ok()
            .and_then(|row| self.apps.get(row));
        let name = usize::try_from(role - USER_ROLE - 1)
            .ok()
            .and_then(|i| ROLES.get(i));
        app.zip(name).map(|(a, n)| field(a, n)).unwrap_or_default()
    }

    fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut roles = QHash::<QHashPair_i32_QByteArray>::default();
        for (role, name) in (USER_ROLE + 1..).zip(ROLES) {
            roles.insert(role, QByteArray::from(name));
        }
        roles
    }

    fn find(&self, app_id: &QString) -> Option<&App> {
        let id = app_id.to_string();
        self.apps.iter().find(|a| a.id == id)
    }

    fn set(mut self: Pin<&mut Self>, found: Vec<App>) {
        let count = i32::try_from(found.len()).unwrap_or(i32::MAX);
        self.as_mut().begin_reset_model();
        let mut rust = self.as_mut().rust_mut();
        rust.apps = found;
        rust.count = count;
        self.as_mut().end_reset_model();
        self.count_changed();
    }

    fn load(mut self: Pin<&mut Self>, app_id: &QString) -> bool {
        let Some(app) = apps::find(&app_id.to_string()) else {
            return false;
        };
        let (initial, load_all) = initial_apps(app);
        let mut rust = self.as_mut().rust_mut();
        rust.may_load_all = load_all;
        rust.full_load_started = false;
        self.set(initial);

        true
    }

    fn load_all(mut self: Pin<&mut Self>) {
        if !self.as_mut().rust_mut().begin_full_load() {
            return;
        }
        let qt = self.qt_thread();

        // System apps configure other apps, but only their own manifest is
        // needed to start. The runner calls this after the first frame, and
        // directory and manifest I/O stays off the GUI thread.
        io::spawn(async move {
            let found = blocking::unblock(apps::scan).await;
            qt.queue(move |obj| obj.set(found)).ok();
        });
    }

    fn get_app(&self, app_id: &QString) -> QMap<QMapPair_QString_QVariant> {
        let mut map = QMap::<QMapPair_QString_QVariant>::default();
        if let Some(app) = self.find(app_id) {
            for name in ROLES
                .iter()
                .chain(&["toolkit", "isSystem", "requiresQtModules"])
            {
                map.insert(QString::from(*name), field(app, name));
            }
        }
        map
    }

    fn get_all_app_ids(&self) -> QStringList {
        let mut l = QList::<QString>::default();
        for app in &self.apps {
            l.append(QString::from(&app.id));
        }
        QStringList::from(&l)
    }

    fn has_app(&self, app_id: &QString) -> bool {
        self.find(app_id).is_some()
    }

    fn is_protected(&self, app_id: &QString) -> bool {
        self.find(app_id).is_some_and(|a| a.is_protected)
    }

    fn get_background_capabilities(&self, app_id: &QString) -> QStringList {
        self.find(app_id)
            .map(|a| {
                field(a, "backgroundCapabilities")
                    .value::<QStringList>()
                    .unwrap_or_default()
            })
            .unwrap_or_default()
    }

    fn unregister_app(self: Pin<&mut Self>, app_id: &QString) {
        let id = app_id.to_string();
        if self.apps.iter().any(|a| a.id == id) {
            let rest = self.apps.iter().filter(|a| a.id != id).cloned().collect();
            self.set(rest);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn system_app_starts_with_only_its_own_entry() {
        let app = App {
            id: "settings".to_owned(),
            permissions: vec!["system".to_owned()],
            ..App::default()
        };

        let (initial, load_all) = initial_apps(app);

        assert!(load_all);
        assert_eq!(initial.len(), 1);
        assert_eq!(initial[0].id, "settings");
    }

    #[test]
    fn regular_app_keeps_single_entry_model() {
        let app = App {
            id: "calculator".to_owned(),
            permissions: vec!["storage".to_owned()],
            ..App::default()
        };

        let (initial, load_all) = initial_apps(app);

        assert!(!load_all);
        assert_eq!(initial.len(), 1);
        assert_eq!(initial[0].id, "calculator");
    }

    #[test]
    fn full_catalog_load_is_system_only_and_one_shot() {
        let mut regular = AppRegistryRust::default();
        assert!(!regular.begin_full_load());

        let mut system = AppRegistryRust {
            may_load_all: true,
            ..AppRegistryRust::default()
        };
        assert!(system.begin_full_load());
        assert!(!system.begin_full_load());
    }
}
