// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The CXX-Qt bridge: the `Reef` QML singleton (`Shipwright.Reef 1.0`) and
//! the list model type behind `catalogueModel`, `installedModel` and
//! `licenceModel`. The API is the one in apps/reef/UI.md ("Backend object
//! API").
//!
//! Threading: every invokable returns at once. Downloads run on a worker
//! thread (`crate::jobs`) and post their results back with
//! `CxxQtThread::queue`, so the GUI thread never blocks on the network.
//! Only one job runs at a time (`busy`); a `refresh()` asked for while busy
//! runs when the current job ends.

#![allow(
    clippy::unnecessary_box_returns,
    reason = "cxx_qt::bridge generates the boxed default constructor of ListModelRust"
)]

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qguiapplication.h");
        type QGuiApplication = cxx_qt_lib::QGuiApplication;
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
        include!("cxx-qt-lib/qlist.h");
        type QList_i32 = cxx_qt_lib::QList<i32>;
    }

    unsafe extern "C++" {
        include!("shipwright-reef/cpp/launcher.h");
        /// Loads `qml_path` into Keel's `SailfishApp::createView()` and shows
        /// it (full screen under keel-shell). False, with the QML errors
        /// printed, if it does not load. See cpp/launcher.cpp.
        fn keel_show_main_view(qml_path: &QString) -> bool;
        /// Deletes the view (and its engine and the QML objects in it)
        /// after the event loop ends, so that their threads stop before the
        /// process exits. See cpp/launcher.cpp.
        fn keel_destroy_main_view();
        /// Keel's application object (Keel::application()): booster-keel's
        /// when boosted, otherwise created on the first call.
        fn keel_application() -> *mut QGuiApplication;
        /// The app's command line (Keel::launchArguments()); see
        /// tools/keel-launcher/launcher.rs.
        fn keel_launch_arguments() -> QStringList;
    }

    unsafe extern "C++" {
        include!(<QtCore/QAbstractListModel>);
        type QAbstractListModel;
    }

    // `QObject` itself is declared by CXX-Qt's generated code for every
    // bridge with a #[qobject].
    unsafe extern "C++" {
        include!("shipwright-reef/cpp/factory.h");
        /// A new, empty list model owned by `parent`.
        ///
        /// # Safety
        /// `parent` must be a live QObject; it takes ownership of the model.
        unsafe fn reef_new_list_model(parent: *mut QObject) -> *mut ReefListModel;
    }

    extern "RustQt" {
        /// A read-only list model whose rows are set wholesale from Rust.
        /// Roles are fixed when the model is created.
        #[qobject]
        #[base = QAbstractListModel]
        #[qproperty(i32, count, READ, NOTIFY)]
        type ReefListModel = super::ListModelRust;

        #[qinvokable]
        #[cxx_override]
        fn data(self: &ReefListModel, index: &QModelIndex, role: i32) -> QVariant;

        #[qinvokable]
        #[cxx_override]
        #[cxx_name = "roleNames"]
        fn role_names(self: &ReefListModel) -> QHash_i32_QByteArray;

        #[qinvokable]
        #[cxx_override]
        #[cxx_name = "rowCount"]
        fn row_count(self: &ReefListModel, parent: &QModelIndex) -> i32;

        /// Row `row` as a role name to value map (`{}` when out of range).
        #[qinvokable]
        fn get(self: &ReefListModel, row: i32) -> QMap_QString_QVariant;
    }

    unsafe extern "RustQt" {
        #[inherit]
        #[cxx_name = "beginResetModel"]
        fn begin_reset_model(self: Pin<&mut ReefListModel>);

        #[inherit]
        #[cxx_name = "endResetModel"]
        fn end_reset_model(self: Pin<&mut ReefListModel>);

        #[inherit]
        #[cxx_name = "beginInsertRows"]
        fn begin_insert_rows(
            self: Pin<&mut ReefListModel>,
            parent: &QModelIndex,
            first: i32,
            last: i32,
        );

        #[inherit]
        #[cxx_name = "endInsertRows"]
        fn end_insert_rows(self: Pin<&mut ReefListModel>);

        #[inherit]
        #[cxx_name = "beginRemoveRows"]
        fn begin_remove_rows(
            self: Pin<&mut ReefListModel>,
            parent: &QModelIndex,
            first: i32,
            last: i32,
        );

        #[inherit]
        #[cxx_name = "endRemoveRows"]
        fn end_remove_rows(self: Pin<&mut ReefListModel>);

        #[inherit]
        #[cxx_name = "dataChanged"]
        fn data_changed(
            self: Pin<&mut ReefListModel>,
            top_left: &QModelIndex,
            bottom_right: &QModelIndex,
            roles: &QList_i32,
        );

        #[inherit]
        fn index(self: &ReefListModel, row: i32, column: i32, parent: &QModelIndex) -> QModelIndex;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qml_singleton]
        #[qproperty(QString, arch, READ, CONSTANT)]
        #[qproperty(QString, store_url, cxx_name = "storeUrl", READ, CONSTANT)]
        #[qproperty(bool, busy, READ, NOTIFY)]
        #[qproperty(QString, busy_text, cxx_name = "busyText", READ, NOTIFY)]
        #[qproperty(QString, last_error, cxx_name = "lastError", READ, NOTIFY)]
        #[qproperty(i32, revision, READ, NOTIFY)]
        #[qproperty(*mut ReefListModel, catalogue_model, cxx_name = "catalogueModel", READ, CONSTANT)]
        #[qproperty(*mut ReefListModel, installed_model, cxx_name = "installedModel", READ, CONSTANT)]
        #[qproperty(*mut ReefListModel, licence_model, cxx_name = "licenceModel", READ, CONSTANT)]
        #[qproperty(bool, refresh_on_start, cxx_name = "refreshOnStart")]
        #[qproperty(QString, licence_server, cxx_name = "licenceServer")]
        #[qproperty(QString, search_text, cxx_name = "searchText")]
        #[qproperty(*mut ReefListModel, featured_model, cxx_name = "featuredModel", READ, CONSTANT)]
        #[qproperty(*mut ReefListModel, recent_model, cxx_name = "recentModel", READ, CONSTANT)]
        #[qproperty(*mut ReefListModel, categories_model, cxx_name = "categoriesModel", READ, CONSTANT)]
        #[qproperty(*mut ReefListModel, collections_model, cxx_name = "collectionsModel", READ, CONSTANT)]
        #[qproperty(*mut ReefListModel, browse_model, cxx_name = "browseModel", READ, CONSTANT)]
        #[qproperty(QString, details_loading, cxx_name = "detailsLoading", READ, NOTIFY)]
        type Reef = super::ReefRust;

        #[qinvokable]
        fn refresh(self: Pin<&mut Reef>);

        /// Fills `browseModel` with one category's apps (`kind`
        /// "category"), one collection's ("collection") or every app
        /// ("all"); it follows later refreshes until the next call.
        #[qinvokable]
        fn browse(self: Pin<&mut Reef>, kind: &QString, id: &QString);

        /// The `catalogueModel` row of one app, as a role-name map (`{}`
        /// when it is not shown): the Discover page's collection rows.
        #[qinvokable]
        #[cxx_name = "appRow"]
        fn app_row(self: &Reef, name: &QString) -> QMap_QString_QVariant;

        /// Fetches an app's details (description, screenshots, what it
        /// brings) when the store index has not given them yet;
        /// `detailsLoading` names it meanwhile, and `revision` changes when
        /// they arrive. Does nothing when they are there.
        #[qinvokable]
        #[cxx_name = "loadDetails"]
        fn load_details(self: Pin<&mut Reef>, name: &QString);

        #[qinvokable]
        #[cxx_name = "packageDetails"]
        fn package_details(self: &Reef, name: &QString) -> QMap_QString_QVariant;

        #[qinvokable]
        #[cxx_name = "checkLicenceToken"]
        fn check_licence_token(self: &Reef, token: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "licenceTokenApp"]
        fn licence_token_app(self: &Reef, token: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "addLicenceToken"]
        fn add_licence_token(self: Pin<&mut Reef>, token: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "refreshLicences"]
        fn refresh_licences(self: Pin<&mut Reef>);

        #[qinvokable]
        #[cxx_name = "removeLicence"]
        fn remove_licence(self: Pin<&mut Reef>, app_id: &QString);

        /// The purchase URL of package `name` with a new claim code in it,
        /// or empty (with `lastError` set) when there is none to give.
        #[qinvokable]
        #[cxx_name = "buyUrl"]
        fn buy_url(self: Pin<&mut Reef>, name: &QString) -> QString;

        /// `refreshLicences()` when a purchase's claim code is pending: the
        /// window calls it on becoming active, so a licence bought in the
        /// browser arrives when the user comes back.
        #[qinvokable]
        #[cxx_name = "checkPurchases"]
        fn check_purchases(self: Pin<&mut Reef>);

    }

    impl cxx_qt::Threading for Reef {}
    impl cxx_qt::Initialize for Reef {}
}

use core::pin::Pin;
use std::path::PathBuf;

use cxx_qt::casting::Upcast;
use cxx_qt::{CxxQtThread, CxxQtType, Threading};
use cxx_qt_lib::{
    QByteArray, QHash, QHashPair_i32_QByteArray, QList, QMap, QMapPair_QString_QVariant,
    QModelIndex, QString, QStringList, QVariant,
};
use reef_backend::catalogue::{Catalogue, LicenceModel};
use reef_backend::claim_codes::{self, PendingClaims};
use reef_backend::licences::LicenceStore;
use reef_backend::store::InstallState;
use reef_licence::{Licence, Policy};

use crate::jobs::{self, RefreshInput, RefreshOutput};
use crate::rows::{self, Value, LICENCE_ROLES, PACKAGE_ROLES};
use crate::settings::Settings;

/// `Qt::UserRole`: the first role number free for models.
const USER_ROLE: i32 = 0x0100;

/// `checkPurchases()` asks the licence service at most this often.
const PURCHASE_CHECK_INTERVAL: std::time::Duration = std::time::Duration::from_secs(10);

/// A row, role or item count as Qt's `int`, saturating (they stay tiny).
fn qt_count(n: usize) -> i32 {
    i32::try_from(n).unwrap_or(i32::MAX)
}

#[derive(Default)]
pub struct ListModelRust {
    roles: &'static [&'static str],
    rows: Vec<Vec<Value>>,
    count: i32,
}

/// A `Value` as a `QVariant`.
pub fn to_variant(value: &Value) -> QVariant {
    match value {
        Value::Str(s) => QVariant::from(&QString::from(s.as_str())),
        Value::Bool(b) => QVariant::from(b),
        Value::Int(i) => match i32::try_from(*i) {
            Ok(small) => QVariant::from(&small),
            Err(_) => QVariant::from(i),
        },
        Value::List(items) => QVariant::from(&string_list(items)),
    }
}

fn string_list(items: &[String]) -> QStringList {
    let mut list = QList::<QString>::default();
    for item in items {
        list.append(QString::from(item.as_str()));
    }
    QStringList::from(&list)
}

fn to_map(pairs: &[(&str, Value)]) -> QMap<QMapPair_QString_QVariant> {
    let mut map = QMap::<QMapPair_QString_QVariant>::default();
    for (key, value) in pairs {
        map.insert(QString::from(*key), to_variant(value));
    }
    map
}

impl qobject::ReefListModel {
    fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
        usize::try_from(index.row())
            .ok()
            .zip(usize::try_from(role - USER_ROLE).ok())
            .and_then(|(row, col)| self.rows.get(row)?.get(col))
            .map(to_variant)
            .unwrap_or_default()
    }

    fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut roles = QHash::<QHashPair_i32_QByteArray>::default();
        for (i, name) in self.roles.iter().enumerate() {
            roles.insert(USER_ROLE + qt_count(i), QByteArray::from(*name));
        }
        roles
    }

    fn row_count(&self, parent: &QModelIndex) -> i32 {
        if parent.is_valid() {
            0
        } else {
            qt_count(self.rows.len())
        }
    }

    fn get(&self, row: i32) -> QMap<QMapPair_QString_QVariant> {
        let cells = usize::try_from(row).ok().and_then(|r| self.rows.get(r));
        let pairs: Vec<(&str, Value)> = cells
            .map(|cells| {
                self.roles
                    .iter()
                    .copied()
                    .zip(cells.iter().cloned())
                    .collect()
            })
            .unwrap_or_default();
        to_map(&pairs)
    }

    /// Makes the rows `rows`, keeping the ones that stay (`rows::RowEdit`):
    /// a row whose values change is updated in place (`dataChanged`), rows
    /// that come or go are inserted or removed, never the whole model
    /// reset. A reset makes every view rebuild its items and lose its
    /// place: the store's first page jumped back to its top whenever an
    /// install state changed (opening an app's page checks it).
    pub fn set_rows(mut self: Pin<&mut Self>, rows: Vec<Vec<Value>>) {
        if self.rows == rows {
            return;
        }
        let root = QModelIndex::default();
        match rows::edits(&self.rows, &rows) {
            None => {
                self.as_mut().begin_reset_model();
                self.as_mut().rust_mut().rows = rows;
                self.as_mut().end_reset_model();
            }
            Some(edits) => {
                for edit in edits {
                    match edit {
                        rows::RowEdit::Remove(i) => {
                            let row = qt_count(i);
                            self.as_mut().begin_remove_rows(&root, row, row);
                            self.as_mut().rust_mut().rows.remove(i);
                            self.as_mut().end_remove_rows();
                        }
                        rows::RowEdit::Insert(i) => {
                            let row = qt_count(i);
                            self.as_mut().begin_insert_rows(&root, row, row);
                            self.as_mut().rust_mut().rows.insert(i, rows[i].clone());
                            self.as_mut().end_insert_rows();
                        }
                        rows::RowEdit::Change(i) => {
                            self.as_mut().rust_mut().rows[i].clone_from(&rows[i]);
                            let at = self.index(qt_count(i), 0, &root);
                            self.as_mut()
                                .data_changed(&at, &at, &QList::<i32>::default());
                        }
                    }
                }
            }
        }
        let count = qt_count(self.rows.len());
        if self.count != count {
            self.as_mut().rust_mut().count = count;
            self.as_mut().count_changed();
        }
    }
}

/// # Safety
/// `ptr` must be a live model created by `reef_new_list_model` and owned by
/// the Reef object whose method is calling this.
unsafe fn model_mut<'a>(ptr: *mut qobject::ReefListModel) -> Pin<&'a mut qobject::ReefListModel> {
    // SAFETY: the caller guarantees `ptr` is a live model (non-null, aligned,
    // not aliased mutably elsewhere: the models are touched only on the GUI
    // thread, by their owning Reef object). A QObject never moves in
    // memory, so pinning it is sound.
    unsafe { Pin::new_unchecked(&mut *ptr) }
}

/// State that has no Qt property of its own.
#[derive(Default)]
pub struct Core {
    store_url: String,
    arch: String,
    catalogue: Option<Catalogue>,
    settings_path: Option<PathBuf>,
    licence_dir: Option<PathBuf>,
    cache_path: Option<PathBuf>,
    /// A `refresh()` arrived while another job was running.
    pending_refresh: bool,
    /// A `checkPurchases()` arrived while another job was running.
    pending_purchase_check: bool,
    /// When `checkPurchases()` last asked the licence service.
    last_purchase_check: Option<std::time::Instant>,
    /// Every listed package as the models show it, from the last rebuild:
    /// a search filters these instead of rebuilding everything (and
    /// re-verifying every licence) on each keystroke.
    package_rows: Vec<rows::PackageRow>,
    /// What `browseModel` shows: kind and id (`browse`).
    browse: (String, String),
}

pub struct ReefRust {
    arch: QString,
    /// Where the catalogue comes from (`jobs::store_url`).
    store_url: QString,
    busy: bool,
    busy_text: QString,
    last_error: QString,
    /// Bumped on every model rebuild, so QML bindings that call
    /// `packageDetails()` re-evaluate (`PackagePage` reads it in its `pkg` binding).
    revision: i32,
    catalogue_model: *mut qobject::ReefListModel,
    installed_model: *mut qobject::ReefListModel,
    licence_model: *mut qobject::ReefListModel,
    featured_model: *mut qobject::ReefListModel,
    /// The most recently updated apps (rows.rs, `recent_rows`).
    recent_model: *mut qobject::ReefListModel,
    /// The store's categories with apps shown here (rows.rs, `category_rows`).
    categories_model: *mut qobject::ReefListModel,
    /// The front page's collections (rows.rs, `collection_rows`).
    collections_model: *mut qobject::ReefListModel,
    /// One category's or collection's apps (`browse`).
    browse_model: *mut qobject::ReefListModel,
    /// The app whose details `loadDetails` is fetching; empty when none.
    details_loading: QString,
    refresh_on_start: bool,
    licence_server: QString,
    /// The catalogue page's search box; `catalogueModel` holds only the
    /// rows that match it (rows.rs, `filter_rows`).
    search_text: QString,
    core: Core,
}

impl Default for ReefRust {
    fn default() -> Self {
        let settings = Settings::default();
        Self {
            arch: QString::default(),
            store_url: QString::default(),
            busy: false,
            busy_text: QString::default(),
            last_error: QString::default(),
            revision: 0,
            catalogue_model: std::ptr::null_mut(),
            installed_model: std::ptr::null_mut(),
            licence_model: std::ptr::null_mut(),
            featured_model: std::ptr::null_mut(),
            recent_model: std::ptr::null_mut(),
            categories_model: std::ptr::null_mut(),
            collections_model: std::ptr::null_mut(),
            browse_model: std::ptr::null_mut(),
            details_loading: QString::default(),
            refresh_on_start: settings.refresh_on_start,
            licence_server: QString::from(settings.licence_server.as_str()),
            search_text: QString::default(),
            core: Core::default(),
        }
    }
}

/// Sets a read-only property's backing field and emits its NOTIFY signal
/// when the value changed.
macro_rules! set_notify {
    ($obj:expr, $field:ident, $notify:ident, $value:expr) => {{
        let value = $value;
        if $obj.$field != value {
            $obj.as_mut().rust_mut().$field = value;
            $obj.as_mut().$notify();
        }
    }};
}

impl cxx_qt::Initialize for qobject::Reef {
    fn initialize(mut self: Pin<&mut Self>) {
        let arch = std::env::consts::ARCH.to_string();
        let store_url = jobs::store_url(&arch);
        let settings_path = Settings::default_path();
        let settings = settings_path
            .as_deref()
            .map(Settings::load)
            .unwrap_or_default();

        // Models, owned by this object through the QObject tree.
        let parent: *mut cxx_qt::QObject = {
            // SAFETY: only a raw pointer to the QObject base is taken here;
            // nothing is moved out of the pinned object, and the pointer is
            // used only as the models' Qt parent.
            let this: &mut qobject::Reef = unsafe { self.as_mut().get_unchecked_mut() };
            std::ptr::from_mut::<cxx_qt::QObject>(this.upcast_mut())
        };
        // SAFETY: `parent` is this live Reef object; each model becomes its
        // QObject child, so Qt deletes the models with it and they live as
        // long as every method of `self` that uses the pointers.
        let [catalogue_model, installed_model, licence_model, featured_model, recent_model, categories_model, collections_model, browse_model] =
            std::array::from_fn(|_| unsafe { qobject::reef_new_list_model(parent) });
        for (model, roles) in [
            (catalogue_model, PACKAGE_ROLES),
            (installed_model, PACKAGE_ROLES),
            (licence_model, LICENCE_ROLES),
            (featured_model, PACKAGE_ROLES),
            (recent_model, PACKAGE_ROLES),
            (categories_model, rows::CATEGORY_ROLES),
            (collections_model, rows::COLLECTION_ROLES),
            (browse_model, PACKAGE_ROLES),
        ] {
            // SAFETY: just created above by reef_new_list_model, owned by
            // `self` (see model_mut's contract).
            unsafe { model_mut(model) }.rust_mut().roles = roles;
        }

        {
            let mut r = self.as_mut().rust_mut();
            r.arch = QString::from(arch.as_str());
            r.store_url = QString::from(store_url.as_str());
            r.catalogue_model = catalogue_model;
            r.installed_model = installed_model;
            r.licence_model = licence_model;
            r.featured_model = featured_model;
            r.recent_model = recent_model;
            r.categories_model = categories_model;
            r.collections_model = collections_model;
            r.browse_model = browse_model;
            r.refresh_on_start = settings.refresh_on_start;
            r.licence_server = QString::from(settings.licence_server.as_str());
            r.core.cache_path = jobs::cache_path();
            // The last catalogue downloaded, so the store opens with content
            // before (or without) a refresh.
            r.core.catalogue = r
                .core
                .cache_path
                .as_deref()
                .and_then(|p| std::fs::read(p).ok())
                .and_then(|b| Catalogue::parse(&b, &arch).ok());
            r.core.store_url = store_url;
            r.core.arch = arch;
            r.core.settings_path = settings_path;
            r.core.licence_dir = LicenceStore::default_dir();
        }

        self.as_mut()
            .on_refresh_on_start_changed(qobject::Reef::save_settings)
            .release();
        self.as_mut()
            .on_licence_server_changed(qobject::Reef::save_settings)
            .release();
        self.as_mut()
            .on_search_text_changed(qobject::Reef::apply_search)
            .release();

        self.as_mut().rebuild_models();
    }
}

impl qobject::Reef {
    fn save_settings(self: Pin<&mut Self>) {
        let settings = self.settings();
        if let Some(path) = &self.core.settings_path {
            if let Err(e) = settings.save(path) {
                log::warn!("saving settings to {}: {e}", path.display());
            }
        }
    }

    fn settings(&self) -> Settings {
        Settings {
            refresh_on_start: self.refresh_on_start,
            licence_server: self.licence_server.to_string(),
        }
    }

    fn licence_store(&self) -> Option<LicenceStore> {
        self.core.licence_dir.as_deref().map(jobs::licence_store)
    }

    /// The cached local path of a repository-relative asset, or empty.
    fn asset(&self, rel: &str) -> String {
        self.core
            .cache_path
            .as_deref()
            .map_or_else(String::new, |p| jobs::asset_path(&jobs::asset_dir(p), rel))
    }

    /// The catalogue model for the current search, from the rows the last
    /// rebuild made (nothing else depends on the search text).
    fn apply_search(self: Pin<&mut Self>) {
        let shown = rows::filter_rows(&self.core.package_rows, &self.search_text.to_string());
        // SAFETY: as in rebuild_models: a QObject child of `self`, used only
        // here on the GUI thread.
        unsafe {
            model_mut(self.catalogue_model)
                .set_rows(shown.iter().map(rows::PackageRow::values).collect());
        }
    }

    /// Rebuilds the models from the current state.
    fn rebuild_models(mut self: Pin<&mut Self>) {
        let now = jobs::unix_now();
        let stored = self
            .licence_store()
            .map(|s| s.list(now))
            .unwrap_or_default();
        let usable: Vec<String> = stored
            .iter()
            .filter(|s| rows::licence_usable(s))
            .map(|s| s.app_id.clone())
            .collect();
        let licensed = |app: &str| usable.iter().any(|a| a == app);
        let asset = |rel: &str| self.asset(rel);

        let package_rows = match &self.core.catalogue {
            Some(c) => rows::package_rows(c, &[], &[], &licensed, &asset, rows::today(now)),
            None => Vec::new(),
        };
        let installed_rows = rows::installed_rows(&package_rows);
        let catalogue = self.core.catalogue.as_ref();
        let featured_rows = catalogue
            .map(|c| rows::featured_rows(&package_rows, c))
            .unwrap_or_default();
        let recent_rows = rows::recent_rows(&package_rows);
        let shown_rows = rows::filter_rows(&package_rows, &self.search_text.to_string());
        let (category_rows, collection_rows, browse_rows) = catalogue
            .map(|c| {
                let (kind, id) = &self.core.browse;
                (
                    rows::category_rows(c, &package_rows),
                    rows::collection_rows(c, &package_rows),
                    rows::browse_rows(c, &package_rows, kind, id),
                )
            })
            .unwrap_or_default();
        let licence_rows: Vec<Vec<Value>> = stored
            .iter()
            .map(|s| rows::licence_row(s, &|app| rows::title_for_app(catalogue, app)).values())
            .collect();
        self.as_mut().rust_mut().core.package_rows = package_rows;
        // SAFETY: the models were created in `initialize` as QObject
        // children of `self` and live as long as it does; they are used only
        // here, on the GUI thread (model_mut's contract).
        unsafe {
            model_mut(self.catalogue_model)
                .set_rows(shown_rows.iter().map(rows::PackageRow::values).collect());
            model_mut(self.installed_model).set_rows(
                installed_rows
                    .iter()
                    .map(rows::PackageRow::values)
                    .collect(),
            );
            model_mut(self.licence_model).set_rows(licence_rows);
            model_mut(self.featured_model)
                .set_rows(featured_rows.iter().map(rows::PackageRow::values).collect());
            model_mut(self.recent_model)
                .set_rows(recent_rows.iter().map(rows::PackageRow::values).collect());
            model_mut(self.categories_model).set_rows(category_rows);
            model_mut(self.collections_model).set_rows(collection_rows);
            model_mut(self.browse_model)
                .set_rows(browse_rows.iter().map(rows::PackageRow::values).collect());
        }
        let revision = self.revision.wrapping_add(1);
        self.as_mut().rust_mut().revision = revision;
        self.as_mut().revision_changed();
    }

    fn set_error(mut self: Pin<&mut Self>, error: &str) {
        set_notify!(self, last_error, last_error_changed, QString::from(error));
    }

    /// Marks a job as started. Returns false (and changes nothing) when
    /// another job is running.
    fn begin_job(mut self: Pin<&mut Self>, text: &str) -> bool {
        if self.busy {
            return false;
        }
        set_notify!(self, busy_text, busy_text_changed, QString::from(text));
        set_notify!(self, busy, busy_changed, true);
        true
    }

    fn end_job(mut self: Pin<&mut Self>) {
        set_notify!(self, busy, busy_changed, false);
        set_notify!(self, busy_text, busy_text_changed, QString::default());
        let purchases = std::mem::take(&mut self.as_mut().rust_mut().core.pending_purchase_check);
        if std::mem::take(&mut self.as_mut().rust_mut().core.pending_refresh) {
            // A refresh redeems pending claim codes too.
            self.refresh();
        } else if purchases {
            self.check_purchases();
        }
    }

    /// Runs `work` on a worker thread; it posts its result back through the
    /// `CxxQtThread` it is given. If the thread cannot be created (out of
    /// memory or threads), the job ends at once with the error in
    /// `lastError` instead of aborting the app; returns false then.
    fn spawn<F>(mut self: Pin<&mut Self>, work: F) -> bool
    where
        F: FnOnce(CxxQtThread<qobject::Reef>) + Send + 'static,
    {
        let thread = self.qt_thread();
        match std::thread::Builder::new()
            .name("reef-worker".into())
            .spawn(move || work(thread))
        {
            Ok(_) => true,
            Err(e) => {
                log::error!("starting a worker thread: {e}");
                self.as_mut()
                    .set_error(&rows::message("worker_failed", &[&e.to_string()]));
                self.end_job();
                false
            }
        }
    }

    fn refresh_input(&self) -> RefreshInput {
        RefreshInput {
            store_url: self.core.store_url.clone(),
            arch: self.core.arch.clone(),
            licence_dir: self.core.licence_dir.clone(),
            licence_server: self.licence_server.to_string(),
            cache_path: self.core.cache_path.clone(),
        }
    }

    fn apply_refresh(mut self: Pin<&mut Self>, out: RefreshOutput) {
        // The worker has already cached it (jobs::refresh, atomically).
        if let Some(catalogue) = out.catalogue {
            self.as_mut().rust_mut().core.catalogue = Some(catalogue);
        }
        self.as_mut().set_error(&out.errors.join("\n"));
        for e in &out.errors {
            log::warn!("{e}");
        }
        self.as_mut().rebuild_models();
        self.end_job();
    }

    pub fn refresh(mut self: Pin<&mut Self>) {
        if self.busy {
            self.as_mut().rust_mut().core.pending_refresh = true;
            return;
        }
        if !self.as_mut().begin_job("refreshing") {
            return;
        }
        let input = self.refresh_input();
        self.as_mut().spawn(move |thread| {
            let out = jobs::refresh(&input);
            queue_or_log(&thread, move |q| q.apply_refresh(out));
        });
    }

    pub fn browse(mut self: Pin<&mut Self>, kind: &QString, id: &QString) {
        self.as_mut().rust_mut().core.browse = (kind.to_string(), id.to_string());
        let shown = match &self.core.catalogue {
            Some(c) => rows::browse_rows(
                c,
                &self.core.package_rows,
                &kind.to_string(),
                &id.to_string(),
            ),
            None => Vec::new(),
        };
        // SAFETY: as in rebuild_models.
        unsafe {
            model_mut(self.browse_model)
                .set_rows(shown.iter().map(rows::PackageRow::values).collect());
        }
    }

    pub fn app_row(&self, name: &QString) -> QMap<QMapPair_QString_QVariant> {
        let name = name.to_string();
        self.core
            .package_rows
            .iter()
            .find(|r| r.name == name)
            .map(|r| {
                let pairs: Vec<(&str, Value)> =
                    PACKAGE_ROLES.iter().copied().zip(r.values()).collect();
                to_map(&pairs)
            })
            .unwrap_or_default()
    }

    /// The repository directory's URL and the details cache, when the
    /// catalogue came from somewhere details can be fetched.
    fn details_source(&self) -> Option<(String, PathBuf)> {
        let cache = self.core.cache_path.as_deref()?;
        Some((self.core.store_url.clone(), jobs::details_dir(cache)))
    }

    pub fn load_details(mut self: Pin<&mut Self>, name: &QString) {
        let name = name.to_string();
        let Some(d) = self
            .core
            .catalogue
            .as_ref()
            .and_then(|c| c.packages.iter().find(|p| p.name == name))
            .and_then(|p| p.details.clone())
        else {
            return;
        };
        let Some((base, dir)) = self.details_source() else {
            return;
        };
        if !self.details_loading.is_empty() {
            return;
        }
        set_notify!(
            self,
            details_loading,
            details_loading_changed,
            QString::from(name.as_str())
        );
        let thread = self.qt_thread();
        let spawned = std::thread::Builder::new()
            .name("reef-details".into())
            .spawn(move || {
                let result = jobs::details_bytes(&base, &dir, &d);
                queue_or_log(&thread, move |mut q| {
                    match result.and_then(|bytes| {
                        match q.as_mut().rust_mut().core.catalogue.as_mut() {
                            Some(c) => c.merge_details(&name, &bytes).map_err(|e| e.to_string()),
                            None => Ok(()),
                        }
                    }) {
                        Ok(()) => {
                            if let (Some(path), Some(c)) =
                                (q.core.cache_path.clone(), q.core.catalogue.clone())
                            {
                                if let Err(e) = jobs::write_cache(&path, &c) {
                                    log::warn!("caching the catalogue: {e}");
                                }
                            }
                        }
                        Err(e) => log::warn!("{name}: details: {e}"),
                    }
                    set_notify!(
                        q,
                        details_loading,
                        details_loading_changed,
                        QString::default()
                    );
                    q.as_mut().rebuild_models();
                });
            });
        if let Err(e) = spawned {
            log::error!("starting a worker thread: {e}");
            set_notify!(
                self,
                details_loading,
                details_loading_changed,
                QString::default()
            );
        }
    }

    pub fn package_details(&self, name: &QString) -> QMap<QMapPair_QString_QVariant> {
        let name = name.to_string();
        let Some(catalogue) = &self.core.catalogue else {
            return QMap::default();
        };
        let Some(package) = catalogue.visible_package(&name) else {
            return QMap::default();
        };
        let state =
            rows::state_of(catalogue, &[], &[], &name).unwrap_or(InstallState::NotInstalled);
        let now = jobs::unix_now();
        let licensed = package.licence.app_id().is_some_and(|app| {
            self.licence_store()
                .and_then(|s| s.check(app, now))
                .is_some_and(|s| rows::licence_usable(&s))
        });
        to_map(&rows::package_details(package, &state, licensed, &|rel| {
            self.asset(rel)
        }))
    }

    fn verify_token(token: &QString) -> Result<Licence, String> {
        let keys = reef_licence::KeySet::from_embedded(reef_backend::licences::EMBEDDED_KEYS)
            .map_err(|e| e.to_string())?;
        Licence::verify_any_app(
            token.to_string().trim(),
            &keys,
            &Policy::default(),
            jobs::unix_now(),
        )
        .map_err(|e| e.to_string())
    }

    pub fn check_licence_token(&self, token: &QString) -> QString {
        match Self::verify_token(token) {
            Ok(_) => QString::default(),
            Err(e) => QString::from(e.as_str()),
        }
    }

    pub fn licence_token_app(&self, token: &QString) -> QString {
        match Self::verify_token(token) {
            Ok(l) => QString::from(
                rows::title_for_app(self.core.catalogue.as_ref(), &l.claims.app)
                    .unwrap_or(l.claims.app)
                    .as_str(),
            ),
            Err(_) => QString::default(),
        }
    }

    pub fn add_licence_token(mut self: Pin<&mut Self>, token: &QString) -> QString {
        let Some(store) = self.licence_store() else {
            let error = rows::message("no_licence_store", &[]);
            self.as_mut().set_error(&error);
            return QString::from(error.as_str());
        };
        match store.save(&token.to_string(), jobs::unix_now()) {
            Ok(_) => {
                self.as_mut().rebuild_models();
                QString::default()
            }
            // Also in lastError: the dialog has closed by the time it fails,
            // and the licences page shows lastError (U-04).
            Err(e) => {
                let error = rows::message("licence_add_failed", &[&e.to_string()]);
                self.as_mut().set_error(&error);
                QString::from(error.as_str())
            }
        }
    }

    pub fn refresh_licences(mut self: Pin<&mut Self>) {
        let Some(dir) = self.core.licence_dir.clone() else {
            return;
        };
        if !self.as_mut().begin_job("refreshing_licences") {
            return;
        }
        let server = self.licence_server.to_string();
        self.as_mut().spawn(move |thread| {
            let result = jobs::refresh_licences(&dir, &server, jobs::unix_now());
            queue_or_log(&thread, move |mut q| {
                let error = result.err().unwrap_or_default();
                q.as_mut().set_error(&error);
                q.as_mut().rebuild_models();
                q.end_job();
            });
        });
    }

    pub fn buy_url(mut self: Pin<&mut Self>, name: &QString) -> QString {
        let name = name.to_string();
        let paid = match &self.core.catalogue {
            Some(c) => match c.visible_package(&name).map(|p| &p.licence) {
                Some(
                    LicenceModel::OneOff {
                        app_id,
                        purchase_url,
                    }
                    | LicenceModel::Subscription {
                        app_id,
                        purchase_url,
                    },
                ) => Some((app_id.clone(), purchase_url.clone())),
                _ => None,
            },
            None => None,
        };
        let Some((app_id, purchase_url)) = paid else {
            return QString::default();
        };
        let Some(dir) = self.core.licence_dir.clone() else {
            self.as_mut()
                .set_error(&rows::message("no_licence_store", &[]));
            return QString::default();
        };
        // Without a recorded code the licence could not be fetched after
        // paying, so there is no purchase without one.
        match PendingClaims::beside(&dir).create(&app_id, jobs::unix_now()) {
            Ok(code) => {
                // The next return to the foreground asks for it at once.
                self.as_mut().rust_mut().core.last_purchase_check = None;
                QString::from(claim_codes::purchase_url_with_claim(&purchase_url, &code).as_str())
            }
            Err(e) => {
                log::warn!("recording a claim code for {app_id}: {e}");
                self.as_mut()
                    .set_error(&rows::message("claim_failed", &[&e.to_string()]));
                QString::default()
            }
        }
    }

    pub fn check_purchases(mut self: Pin<&mut Self>) {
        let Some(dir) = self.core.licence_dir.clone() else {
            return;
        };
        if !PendingClaims::beside(&dir).any(jobs::unix_now()) {
            return;
        }
        if self.busy {
            self.as_mut().rust_mut().core.pending_purchase_check = true;
            return;
        }
        if self
            .core
            .last_purchase_check
            .is_some_and(|t| t.elapsed() < PURCHASE_CHECK_INTERVAL)
        {
            return;
        }
        self.as_mut().rust_mut().core.last_purchase_check = Some(std::time::Instant::now());
        self.refresh_licences();
    }

    pub fn remove_licence(mut self: Pin<&mut Self>, app_id: &QString) {
        if let Some(store) = self.licence_store() {
            if let Err(e) = store.remove(&app_id.to_string()) {
                self.as_mut()
                    .set_error(&rows::message("licence_remove_failed", &[&e.to_string()]));
            }
        }
        self.rebuild_models();
    }
}

/// Posts `f` to the GUI thread. `queue` fails only when the Reef object is
/// being destroyed (the app is quitting), so the result has nowhere to go:
/// it is logged, not dropped silently.
fn queue_or_log<F>(thread: &CxxQtThread<qobject::Reef>, f: F)
where
    F: FnOnce(Pin<&mut qobject::Reef>) + Send + 'static,
{
    if let Err(e) = thread.queue(f) {
        log::warn!("result of a background job dropped: {e:?}");
    }
}

// Keel's launcher: launch_args() and keel_application().
include!("../../../../tools/keel-launcher/launcher.rs");

#[cfg(test)]
mod tests {
    //! The Qt half of the model conversions: [`Value`]s as the `QVariant`s
    //! QML receives. (The row contents are tested in `crate::rows`.)
    use super::*;

    #[test]
    fn values_become_the_variants_qml_expects() {
        let s = to_variant(&Value::Str("installed".into()));
        assert_eq!(s.value::<QString>().unwrap().to_string(), "installed");

        let b = to_variant(&Value::Bool(true));
        assert_eq!(b.value::<bool>(), Some(true));

        // Small integers stay `int` for QML; large ones keep 64 bits.
        let small = to_variant(&Value::Int(42));
        assert_eq!(small.value::<i32>(), Some(42));
        let big = to_variant(&Value::Int(5_000_000_000));
        assert_eq!(big.value::<i64>(), Some(5_000_000_000));

        let list = to_variant(&Value::List(vec!["5.2.0.17".into(), "5.2.0.18".into()]));
        let list = list.value::<QStringList>().unwrap();
        let items: Vec<String> = QList::<QString>::from(&list)
            .iter()
            .map(ToString::to_string)
            .collect();
        assert_eq!(items, ["5.2.0.17", "5.2.0.18"]);
    }

    #[test]
    fn details_become_a_map_keyed_by_role_name() {
        let map = to_map(&[
            ("name", Value::Str("harbour-x".into())),
            ("sandboxed", Value::Bool(false)),
        ]);
        assert_eq!(map.len(), 2);
        let name = map.get(&QString::from("name")).unwrap();
        assert_eq!(name.value::<QString>().unwrap().to_string(), "harbour-x");
        let sandboxed = map.get(&QString::from("sandboxed")).unwrap();
        assert_eq!(sandboxed.value::<bool>(), Some(false));
        assert!(map.get(&QString::from("missing")).is_none());
        assert_eq!(to_map(&[]).len(), 0);
    }
}
