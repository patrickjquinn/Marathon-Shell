//! `Apps`: the apps the shell can start, Marathon's own (their manifests and
//! install receipts, `marathon_apps`) and the desktop's, as the home grid's
//! list model (QML `AppModel`) and as a catalogue the shell's other Rust
//! objects read. It also removes the user's installs.

use std::collections::HashMap;
use std::pin::Pin;
use std::sync::{LazyLock, OnceLock, RwLock};

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
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
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
        #[qproperty(i32, count, READ, NOTIFY)]
        type Apps = super::AppsRust;

        /// A Marathon app's manifest, as the registry gave it: id, name,
        /// icon, absolutePath, toolkit, entryPoint, version, isProtected,
        /// isSystem, permissions, searchKeywords, deepLinks, categories,
        /// handlesUriSchemes, defaultFor, backgroundCapabilities and
        /// requiresQtModules; empty for none.
        #[qinvokable]
        #[cxx_name = "getApp"]
        fn get_app(self: &Apps, app_id: &QString) -> QMap_QString_QVariant;
        /// Marathon's own apps' ids.
        #[qinvokable]
        #[cxx_name = "getAllAppIds"]
        fn get_all_app_ids(self: &Apps) -> QStringList;
        #[qinvokable]
        #[cxx_name = "hasApp"]
        fn has_app(self: &Apps, app_id: &QString) -> bool;
        /// A user install, not protected.
        #[qinvokable]
        #[cxx_name = "canUninstall"]
        fn can_uninstall(self: Pin<&mut Apps>, app_id: &QString) -> bool;
        #[qinvokable]
        fn uninstall(self: Pin<&mut Apps>, app_id: &QString) -> bool;
        /// Marathon's own apps were read again.
        #[qsignal]
        #[cxx_name = "registryChanged"]
        fn registry_changed(self: Pin<&mut Apps>);

        #[inherit]
        #[cxx_name = "beginResetModel"]
        fn begin_reset_model(self: Pin<&mut Apps>);
        #[inherit]
        #[cxx_name = "endResetModel"]
        fn end_reset_model(self: Pin<&mut Apps>);

        #[cxx_override]
        #[cxx_name = "rowCount"]
        fn row_count(self: &Apps, parent: &QModelIndex) -> i32;
        #[cxx_override]
        fn data(self: &Apps, index: &QModelIndex, role: i32) -> QVariant;
        #[cxx_override]
        #[cxx_name = "roleNames"]
        fn role_names(self: &Apps) -> QHash_i32_QByteArray;

        /// An app's id, name, icon, type, exec, permissions, flatpakRef and
        /// searchTerms; empty for no such app.
        #[qinvokable]
        #[cxx_name = "findById"]
        fn find_by_id(self: &Apps, app_id: &QString) -> QMap_QString_QVariant;
        #[qinvokable]
        #[cxx_name = "getAppAtIndex"]
        fn get_app_at_index(self: &Apps, index: i32) -> QMap_QString_QVariant;
        #[qinvokable]
        #[cxx_name = "appIdsByType"]
        fn app_ids_by_type(self: &Apps, kind: &QString) -> QStringList;
        /// The desktop's entries, as `desktop::scan` gives them; ids already
        /// listed are kept as they are.
        #[qinvokable]
        #[cxx_name = "addApps"]
        fn add_apps(self: Pin<&mut Apps>, apps: &QList_QVariant);
        #[qinvokable]
        #[cxx_name = "removeApp"]
        fn remove_app(self: Pin<&mut Apps>, app_id: &QString);
    }

    impl cxx_qt::Threading for Apps {}
    impl cxx_qt::Initialize for Apps {}
}

use qobject::Apps;

/// What the launcher and the shell's services need of an app.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct App {
    pub id: String,
    pub name: String,
    pub icon: String,
    pub kind: String,
    pub exec: String,
    pub permissions: Vec<String>,
    pub flatpak_ref: String,
    pub search_terms: Vec<String>,
    /// What the manifest lets it claim to keep running in the background.
    pub background_capabilities: Vec<String>,
}

const ROLES: [&str; 6] = ["id", "name", "icon", "type", "exec", "flatpakRef"];
const USER_ROLE: i32 = 0x0100;

#[derive(Default)]
pub struct AppsRust {
    count: i32,
    apps: Vec<App>,
}

static CATALOGUE: LazyLock<RwLock<HashMap<String, App>>> = LazyLock::new(RwLock::default);

/// Marathon's own apps, as their manifests and receipts describe them.
static REGISTRY: LazyLock<RwLock<Vec<marathon_apps::apps::App>>> = LazyLock::new(RwLock::default);

static QT: OnceLock<cxx_qt::CxxQtThread<Apps>> = OnceLock::new();

/// Marathon's app of `id`, as its manifest describes it.
pub fn manifest(id: &str) -> Option<marathon_apps::apps::App> {
    REGISTRY
        .read()
        .unwrap_or_else(|_| std::process::abort())
        .iter()
        .find(|a| a.id == id)
        .cloned()
}

/// Runs `f` on the apps, on the GUI thread.
pub(crate) fn with(f: impl FnOnce(Pin<&mut Apps>) + Send + 'static) {
    if let Some(qt) = QT.get() {
        qt.queue(f).ok();
    }
}

impl cxx_qt::Initialize for Apps {
    fn initialize(self: Pin<&mut Self>) {
        QT.set(self.qt_thread()).ok();
        let qt = self.qt_thread();
        crate::io::spawn(async move {
            let found = blocking::unblock(|| {
                // Grants a legacy install's manifest claimed as "protected"
                // came from that claim, which a user install never has.
                for id in marathon_apps::install::migrate_legacy_installs() {
                    crate::permissions::with(move |p| p.forget_app(&QString::from(&id)));
                }
                marathon_apps::apps::scan()
            })
            .await;
            qt.queue(move |obj| obj.set_registry(found)).ok();
        });
    }
}

/// The app of `id`, as the home grid lists it.
pub fn get(id: &str) -> Option<App> {
    CATALOGUE
        .read()
        .unwrap_or_else(|_| std::process::abort())
        .get(id)
        .cloned()
}

/// Every app, in the grid's order.
pub fn all() -> Vec<App> {
    APPS_ORDER
        .read()
        .unwrap_or_else(|_| std::process::abort())
        .clone()
}

static APPS_ORDER: LazyLock<RwLock<Vec<App>>> = LazyLock::new(RwLock::default);

fn text(map: &QMap<QMapPair_QString_QVariant>, key: &str) -> String {
    map.get(&QString::from(key))
        .and_then(|v| v.value::<QString>())
        .map(|s| s.to_string())
        .unwrap_or_default()
}

fn list(map: &QMap<QMapPair_QString_QVariant>, key: &str) -> Vec<String> {
    let Some(value) = map.get(&QString::from(key)) else {
        return Vec::new();
    };
    if let Some(strings) = value.value::<QStringList>() {
        return QList::<QString>::from(&strings)
            .iter()
            .map(ToString::to_string)
            .collect();
    }
    value
        .value::<QList<QVariant>>()
        .map(|l| {
            l.iter()
                .filter_map(QVariant::value::<QString>)
                .map(|s| s.to_string())
                .collect()
        })
        .unwrap_or_default()
}

fn map_of(value: &QVariant) -> Option<QMap<QMapPair_QString_QVariant>> {
    value.value::<QMap<QMapPair_QString_QVariant>>()
}

/// A desktop entry, if it is one the grid can show.
fn from_desktop(map: &QMap<QMapPair_QString_QVariant>) -> Option<App> {
    let app = App {
        id: text(map, "id"),
        name: text(map, "name"),
        icon: text(map, "icon"),
        kind: text(map, "type"),
        exec: text(map, "exec"),
        permissions: list(map, "permissions"),
        flatpak_ref: text(map, "flatpakRef"),
        search_terms: [list(map, "keywords"), list(map, "categories")]
            .concat()
            .iter()
            .map(|t| t.to_lowercase())
            .collect(),
        background_capabilities: Vec::new(),
    };
    let valid = !app.id.is_empty() && !app.name.is_empty() && !app.icon.is_empty();
    (valid && ["native", "marathon", "system", "flatpak"].contains(&app.kind.as_str()))
        .then_some(app)
}

fn from_manifest(m: &marathon_apps::apps::App) -> Option<App> {
    let app = App {
        id: m.id.clone(),
        name: m.name.clone(),
        icon: m.icon.clone(),
        kind: "marathon".to_owned(),
        permissions: m.permissions.clone(),
        background_capabilities: m.background_capabilities.clone(),
        ..App::default()
    };
    (!app.icon.is_empty()).then_some(app)
}

fn strings(items: &[String]) -> QStringList {
    let mut l = QList::<QString>::default();
    for s in items {
        l.append(QString::from(s));
    }
    QStringList::from(&l)
}

fn manifest_map(m: &marathon_apps::apps::App) -> QMap<QMapPair_QString_QVariant> {
    let mut map = QMap::<QMapPair_QString_QVariant>::default();
    let text = |s: &str| QVariant::from(&QString::from(s));
    for (key, value) in [
        ("id", &m.id),
        ("name", &m.name),
        ("icon", &m.icon),
        ("toolkit", &m.toolkit),
        ("entryPoint", &m.entry_point),
        ("version", &m.version),
    ] {
        map.insert(QString::from(key), text(value));
    }
    map.insert(QString::from("type"), QVariant::from(&1_i32));
    map.insert(
        QString::from("absolutePath"),
        text(&m.path.to_string_lossy()),
    );
    map.insert(QString::from("deepLinks"), text(&m.deep_links_json()));
    map.insert(
        QString::from("isProtected"),
        QVariant::from(&m.is_protected),
    );
    map.insert(QString::from("isSystem"), QVariant::from(&m.is_system));
    for (key, value) in [
        ("permissions", &m.permissions),
        ("searchKeywords", &m.search_keywords),
        ("categories", &m.categories),
        ("handlesUriSchemes", &m.handles_uri_schemes),
        ("defaultFor", &m.default_for),
        ("backgroundCapabilities", &m.background_capabilities),
        ("requiresQtModules", &m.requires_qt_modules),
    ] {
        map.insert(QString::from(key), QVariant::from(&strings(value)));
    }
    map
}

fn to_map(app: &App) -> QMap<QMapPair_QString_QVariant> {
    let mut map = QMap::<QMapPair_QString_QVariant>::default();
    let strings = |items: &[String]| {
        let mut l = QList::<QString>::default();
        for s in items {
            l.append(QString::from(s));
        }
        QVariant::from(&QStringList::from(&l))
    };
    for (key, value) in [
        ("id", &app.id),
        ("name", &app.name),
        ("icon", &app.icon),
        ("type", &app.kind),
        ("exec", &app.exec),
        ("flatpakRef", &app.flatpak_ref),
    ] {
        map.insert(QString::from(key), QVariant::from(&QString::from(value)));
    }
    map.insert(QString::from("permissions"), strings(&app.permissions));
    map.insert(QString::from("searchTerms"), strings(&app.search_terms));
    map
}

impl Apps {
    fn row_count(&self, parent: &QModelIndex) -> i32 {
        if parent.is_valid() {
            0
        } else {
            self.count
        }
    }

    fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
        let Some(app) = usize::try_from(index.row())
            .ok()
            .and_then(|row| self.apps.get(row))
        else {
            return QVariant::default();
        };
        let value = match role - USER_ROLE - 1 {
            0 => &app.id,
            1 => &app.name,
            2 => &app.icon,
            3 => &app.kind,
            4 => &app.exec,
            5 => &app.flatpak_ref,
            _ => return QVariant::default(),
        };
        QVariant::from(&QString::from(value))
    }

    #[allow(clippy::unused_self, reason = "a QAbstractListModel override")]
    fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut roles = QHash::<QHashPair_i32_QByteArray>::default();
        for (role, name) in (USER_ROLE + 1..).zip(ROLES) {
            roles.insert(role, QByteArray::from(name));
        }
        roles
    }

    fn find_by_id(&self, app_id: &QString) -> QMap<QMapPair_QString_QVariant> {
        let id = app_id.to_string();
        self.apps
            .iter()
            .find(|a| a.id == id)
            .map(to_map)
            .unwrap_or_default()
    }

    fn get_app_at_index(&self, index: i32) -> QMap<QMapPair_QString_QVariant> {
        usize::try_from(index)
            .ok()
            .and_then(|i| self.apps.get(i))
            .map(to_map)
            .unwrap_or_default()
    }

    fn app_ids_by_type(&self, kind: &QString) -> QStringList {
        let kind = kind.to_string();
        let mut ids = QList::<QString>::default();
        for app in self.apps.iter().filter(|a| a.kind == kind) {
            ids.append(QString::from(&app.id));
        }
        QStringList::from(&ids)
    }

    fn add_apps(self: Pin<&mut Self>, apps: &QList<QVariant>) {
        let mut next = self.apps.clone();
        for app in apps
            .iter()
            .filter_map(map_of)
            .filter_map(|m| from_desktop(&m))
        {
            if !next.iter().any(|a| a.id == app.id) {
                next.push(app);
            }
        }
        self.replace(next);
    }

    fn remove_app(self: Pin<&mut Self>, app_id: &QString) {
        let id = app_id.to_string();
        let next: Vec<App> = self.apps.iter().filter(|a| a.id != id).cloned().collect();
        if next.len() != self.apps.len() {
            self.replace(next);
        }
    }

    #[allow(clippy::unused_self, reason = "a QML invokable")]
    fn get_app(&self, app_id: &QString) -> QMap<QMapPair_QString_QVariant> {
        manifest(&app_id.to_string())
            .as_ref()
            .map(manifest_map)
            .unwrap_or_default()
    }

    #[allow(clippy::unused_self, reason = "a QML invokable")]
    fn get_all_app_ids(&self) -> QStringList {
        let ids: Vec<String> = REGISTRY
            .read()
            .unwrap_or_else(|_| std::process::abort())
            .iter()
            .map(|a| a.id.clone())
            .collect();
        strings(&ids)
    }

    #[allow(clippy::unused_self, reason = "a QML invokable")]
    fn has_app(&self, app_id: &QString) -> bool {
        manifest(&app_id.to_string()).is_some()
    }

    /// Marathon's own apps, read again: the grid, the permissions' record of
    /// what each declared, and the shell's other readers.
    fn set_registry(mut self: Pin<&mut Self>, found: Vec<marathon_apps::apps::App>) {
        let gone: Vec<String> = {
            let old = REGISTRY.read().unwrap_or_else(|_| std::process::abort());
            old.iter()
                .filter(|o| !found.iter().any(|f| f.id == o.id))
                .map(|o| o.id.clone())
                .collect()
        };
        for app in &found {
            crate::permissions::declare(&app.id, app.permissions.clone(), app.is_protected);
        }
        for id in &gone {
            crate::permissions::undeclare(id);
        }
        let mut grid: Vec<App> = found.iter().filter_map(from_manifest).collect();
        grid.sort_by(|a, b| a.id.cmp(&b.id));
        *REGISTRY.write().unwrap_or_else(|_| std::process::abort()) = found;
        let mut next: Vec<App> = self
            .apps
            .iter()
            .filter(|a| a.kind != "marathon" && !grid.iter().any(|r| r.id == a.id))
            .cloned()
            .collect();
        next.extend(grid);
        self.as_mut().replace(next);
        self.registry_changed();
    }

    fn rescan(self: Pin<&mut Self>) {
        self.set_registry(marathon_apps::apps::scan());
    }

    /// marathon-dev installs from its own process: an install the shell has
    /// not read yet is read first.
    fn can_uninstall(mut self: Pin<&mut Self>, app_id: &QString) -> bool {
        let id = app_id.to_string();
        if manifest(&id).is_none() && marathon_apps::paths::receipt(&id).exists() {
            self.as_mut().rescan();
        }
        marathon_apps::install::can_uninstall(&id)
    }

    pub(crate) fn uninstall(mut self: Pin<&mut Self>, app_id: &QString) -> bool {
        let id = app_id.to_string();
        let done = if self.as_mut().can_uninstall(app_id) {
            marathon_apps::install::uninstall(&id)
        } else {
            Err("Cannot uninstall a protected or system app".to_owned())
        };
        let error = match done {
            Ok(data_removed) => {
                self.as_mut().rescan();
                crate::permissions::with({
                    let id = id.clone();
                    move |p| p.forget_app(&QString::from(&id))
                });
                if data_removed {
                    let key = id.clone();
                    crate::settings::with(move |s| s.remove_app_keys(&QString::from(&key)));
                    if let Ok(mut reset) = std::process::Command::new("dconf")
                        .args(["reset", "-f", &format!("/apps/{id}/")])
                        .spawn()
                    {
                        std::thread::spawn(move || reset.wait());
                    }
                }
                String::new()
            }
            Err(e) => e,
        };
        crate::tasks::uninstalled(&id, &error);
        error.is_empty()
    }

    /// A reset rather than row edits: the lists are a few dozen apps, and
    /// the grid rebuilds from `count` either way.
    fn replace(mut self: Pin<&mut Self>, apps: Vec<App>) {
        if apps == self.apps {
            return;
        }
        *CATALOGUE.write().unwrap_or_else(|_| std::process::abort()) =
            apps.iter().map(|a| (a.id.clone(), a.clone())).collect();
        APPS_ORDER
            .write()
            .unwrap_or_else(|_| std::process::abort())
            .clone_from(&apps);
        let count = i32::try_from(apps.len()).unwrap_or(i32::MAX);
        self.as_mut().begin_reset_model();
        let mut rust = self.as_mut().rust_mut();
        rust.apps = apps;
        rust.count = count;
        self.as_mut().end_reset_model();
        self.count_changed();
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use cxx_qt_lib::{QMap, QMapPair_QString_QVariant, QString, QVariant};

    use super::from_desktop;

    fn entry(pairs: &[(&str, QVariant)]) -> QMap<QMapPair_QString_QVariant> {
        let mut map = QMap::<QMapPair_QString_QVariant>::default();
        for (k, v) in pairs {
            map.insert(QString::from(*k), v.clone());
        }
        map
    }

    fn s(v: &str) -> QVariant {
        QVariant::from(&QString::from(v))
    }

    #[test]
    fn desktop_entries_need_a_name_an_icon_and_a_known_type() {
        let base = [
            ("id", s("org.example.App")),
            ("name", s("App")),
            ("icon", s("app")),
            ("type", s("native")),
        ];
        assert!(from_desktop(&entry(&base)).is_some());
        assert!(
            from_desktop(&entry(&[base[0].clone(), base[1].clone(), base[3].clone()])).is_none()
        );
        assert!(from_desktop(&entry(&[
            base[0].clone(),
            base[1].clone(),
            base[2].clone(),
            ("type", s("applet"))
        ]))
        .is_none());
    }
}
