//! `Apps`: the apps the shell can start, Marathon's own (from the app
//! registry) and the desktop's, as the home grid's list model (QML
//! `AppModel`) and as a catalogue the shell's other Rust objects read.

use std::collections::HashMap;
use std::pin::Pin;
use std::sync::{LazyLock, RwLock};

use cxx_qt::CxxQtType;
use cxx_qt_lib::{QByteArray, QHash, QHashPair_i32_QByteArray, QList, QMap, QMapPair_QString_QVariant, QModelIndex, QString, QStringList, QVariant};

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
        /// Marathon's own apps, the registry's entries (its `getApp` maps);
        /// each replaces any entry of its id.
        #[cxx_name = "setRegistryApps"]
        fn set_registry_apps(self: Pin<&mut Apps>, apps: &QList_QVariant);
    }
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

/// The app of `id`, as the home grid lists it.
pub fn get(id: &str) -> Option<App> {
    CATALOGUE.read().unwrap_or_else(std::sync::PoisonError::into_inner).get(id).cloned()
}

/// Every app, in the grid's order.
pub fn all() -> Vec<App> {
    APPS_ORDER.read().unwrap_or_else(std::sync::PoisonError::into_inner).clone()
}

static APPS_ORDER: LazyLock<RwLock<Vec<App>>> = LazyLock::new(RwLock::default);

fn text(map: &QMap<QMapPair_QString_QVariant>, key: &str) -> String {
    map.get(&QString::from(key)).and_then(|v| v.value::<QString>()).map(|s| s.to_string()).unwrap_or_default()
}

fn list(map: &QMap<QMapPair_QString_QVariant>, key: &str) -> Vec<String> {
    let Some(value) = map.get(&QString::from(key)) else { return Vec::new() };
    if let Some(strings) = value.value::<QStringList>() {
        return QList::<QString>::from(&strings).iter().map(ToString::to_string).collect();
    }
    value.value::<QList<QVariant>>().map(|l| l.iter().filter_map(QVariant::value::<QString>).map(|s| s.to_string()).collect()).unwrap_or_default()
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
        search_terms: [list(map, "keywords"), list(map, "categories")].concat().iter().map(|t| t.to_lowercase()).collect(),
        background_capabilities: Vec::new(),
    };
    let valid = !app.id.is_empty() && !app.name.is_empty() && !app.icon.is_empty();
    (valid && ["native", "marathon", "system", "flatpak"].contains(&app.kind.as_str())).then_some(app)
}

/// A registry entry: its type is `MarathonAppRegistry::AppType` (0 system,
/// 1 Marathon, 2 native), and a relative icon lies in the app's directory.
fn from_registry(map: &QMap<QMapPair_QString_QVariant>) -> Option<App> {
    let kind = match map.get(&QString::from("type")).and_then(|v| v.value::<i32>()) {
        Some(0) => "system",
        Some(2) => "native",
        _ => "marathon",
    };
    let mut icon = text(map, "icon");
    if !icon.is_empty() && !icon.starts_with("qrc:") && !icon.starts_with("file://") {
        if !icon.starts_with('/') {
            icon = format!("{}/{icon}", text(map, "absolutePath"));
        }
        icon = format!("file://{icon}");
    }
    let app = App { id: text(map, "id"), name: text(map, "name"), icon, kind: kind.to_owned(), permissions: list(map, "permissions"), background_capabilities: list(map, "backgroundCapabilities"), ..App::default() };
    (!app.id.is_empty() && !app.name.is_empty() && !app.icon.is_empty()).then_some(app)
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
    for (key, value) in [("id", &app.id), ("name", &app.name), ("icon", &app.icon), ("type", &app.kind), ("exec", &app.exec), ("flatpakRef", &app.flatpak_ref)] {
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
        let Some(app) = usize::try_from(index.row()).ok().and_then(|row| self.apps.get(row)) else { return QVariant::default() };
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
        self.apps.iter().find(|a| a.id == id).map(to_map).unwrap_or_default()
    }

    fn get_app_at_index(&self, index: i32) -> QMap<QMapPair_QString_QVariant> {
        usize::try_from(index).ok().and_then(|i| self.apps.get(i)).map(to_map).unwrap_or_default()
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
        for app in apps.iter().filter_map(map_of).filter_map(|m| from_desktop(&m)) {
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

    fn set_registry_apps(self: Pin<&mut Self>, apps: &QList<QVariant>) {
        let mut registry: Vec<App> = apps.iter().filter_map(map_of).filter_map(|m| from_registry(&m)).collect();
        registry.sort_by(|a, b| a.id.cmp(&b.id));
        let mut next: Vec<App> = self.apps.iter().filter(|a| !registry.iter().any(|r| r.id == a.id)).cloned().collect();
        next.extend(registry);
        self.replace(next);
    }

    /// A reset rather than row edits: the lists are a few dozen apps, and
    /// the grid rebuilds from `count` either way.
    fn replace(mut self: Pin<&mut Self>, apps: Vec<App>) {
        if apps == self.apps {
            return;
        }
        *CATALOGUE.write().unwrap_or_else(std::sync::PoisonError::into_inner) = apps.iter().map(|a| (a.id.clone(), a.clone())).collect();
        APPS_ORDER.write().unwrap_or_else(std::sync::PoisonError::into_inner).clone_from(&apps);
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

    use super::{from_desktop, from_registry};

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
    fn registry_types_are_the_registrys_enum() {
        let app = |kind: i32| {
            from_registry(&entry(&[("id", s("clock")), ("name", s("Clock")), ("icon", s("icon.svg")), ("absolutePath", s("/apps/clock")), ("type", QVariant::from(&kind))])).unwrap()
        };
        assert_eq!((app(0).kind.as_str(), app(1).kind.as_str(), app(2).kind.as_str()), ("system", "marathon", "native"));
        assert_eq!(app(1).icon, "file:///apps/clock/icon.svg");
    }

    #[test]
    fn desktop_entries_need_a_name_an_icon_and_a_known_type() {
        let base = [("id", s("org.example.App")), ("name", s("App")), ("icon", s("app")), ("type", s("native"))];
        assert!(from_desktop(&entry(&base)).is_some());
        assert!(from_desktop(&entry(&[base[0].clone(), base[1].clone(), base[3].clone()])).is_none());
        assert!(from_desktop(&entry(&[base[0].clone(), base[1].clone(), base[2].clone(), ("type", s("applet"))])).is_none());
    }
}
