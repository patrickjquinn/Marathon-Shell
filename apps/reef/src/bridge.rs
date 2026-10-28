// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

//! The CXX-Qt bridge: the `Reef` QML singleton (`Shipwright.Reef 1.0`) and
//! the list model type behind `catalogueModel`, `installedModel` and
//! `licenceModel`. The API is exactly the one in reef/client/ui/README.md
//! ("Backend object API").
//!
//! Threading: every invokable returns at once. Downloads, `ssu` and
//! `PackageKit` transactions run on a worker thread (`crate::jobs`) and post
//! their results back with `CxxQtThread::queue`, so the GUI thread never
//! blocks on the network or D-Bus. Only one job runs at a time (`busy`); a
//! `refresh()` asked for while busy runs when the current job ends.

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
        #[qproperty(
            QString,
            installed_release,
            cxx_name = "installedRelease",
            READ,
            CONSTANT
        )]
        #[qproperty(QString, arch, READ, CONSTANT)]
        #[qproperty(QString, repo_alias, cxx_name = "repoAlias", READ, CONSTANT)]
        #[qproperty(QString, repo_state, cxx_name = "repoState", READ, NOTIFY)]
        #[qproperty(
            QString,
            registered_repo_url,
            cxx_name = "registeredRepoUrl",
            READ,
            NOTIFY
        )]
        #[qproperty(bool, busy, READ, NOTIFY)]
        #[qproperty(QString, busy_package, cxx_name = "busyPackage", READ, NOTIFY)]
        #[qproperty(QString, busy_text, cxx_name = "busyText", READ, NOTIFY)]
        #[qproperty(i32, progress, READ, NOTIFY)]
        #[qproperty(QString, last_error, cxx_name = "lastError", READ, NOTIFY)]
        #[qproperty(i32, update_count, cxx_name = "updateCount", READ, NOTIFY)]
        #[qproperty(i32, app_update_count, cxx_name = "appUpdateCount", READ, NOTIFY)]
        #[qproperty(QString, pending_plan, cxx_name = "pendingPlan", READ, NOTIFY)]
        #[qproperty(
            bool,
            background_check_asked,
            cxx_name = "backgroundCheckAsked",
            READ,
            NOTIFY
        )]
        #[qproperty(bool, background_wifi_only, cxx_name = "backgroundWifiOnly")]
        #[qproperty(i32, revision, READ, NOTIFY)]
        #[qproperty(*mut ReefListModel, catalogue_model, cxx_name = "catalogueModel", READ, CONSTANT)]
        #[qproperty(*mut ReefListModel, installed_model, cxx_name = "installedModel", READ, CONSTANT)]
        #[qproperty(*mut ReefListModel, licence_model, cxx_name = "licenceModel", READ, CONSTANT)]
        #[qproperty(bool, refresh_on_start, cxx_name = "refreshOnStart")]
        #[qproperty(i32, background_check_days, cxx_name = "backgroundCheckDays")]
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

        /// Whether the installed package has a launcher entry to open
        /// (launch.rs).
        #[qinvokable]
        #[cxx_name = "canOpen"]
        fn can_open(self: &Reef, name: &QString) -> bool;

        /// Opens the installed app, as the launcher would; false when it
        /// has no launcher entry or could not be started.
        #[qinvokable]
        fn open(self: &Reef, name: &QString) -> bool;

        /// Install, update, Update all and remove do nothing to the phone:
        /// each works out what it would do (`PackageKit`'s simulation) and
        /// offers it as `pendingPlan` with `planReady`. Only
        /// `confirmPlan()`, from the confirmation sheet's button, starts
        /// the transaction.
        #[qinvokable]
        fn install(self: Pin<&mut Reef>, name: &QString);

        #[qinvokable]
        fn update(self: Pin<&mut Reef>, name: &QString);

        #[qinvokable]
        #[cxx_name = "updateAll"]
        fn update_all(self: Pin<&mut Reef>);

        #[qinvokable]
        fn remove(self: Pin<&mut Reef>, name: &QString);

        /// The person tapped the confirmation sheet's button: runs the
        /// pending plan, and nothing it does not show.
        #[qinvokable]
        #[cxx_name = "confirmPlan"]
        fn confirm_plan(self: Pin<&mut Reef>);

        /// The person left the confirmation sheet: nothing happens.
        #[qinvokable]
        #[cxx_name = "declinePlan"]
        fn decline_plan(self: Pin<&mut Reef>);

        /// The answer to "Check for updates in the background?": turns the
        /// check's timer on (every few hours) or off.
        #[qinvokable]
        #[cxx_name = "answerBackgroundChecks"]
        fn answer_background_checks(self: Pin<&mut Reef>, check: bool);

        #[qinvokable]
        #[cxx_name = "repairRepository"]
        fn repair_repository(self: Pin<&mut Reef>);

        #[qinvokable]
        #[cxx_name = "repairCommands"]
        fn repair_commands(self: &Reef) -> QStringList;

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

        /// After install, update, remove or repair. `name` is the RPM name,
        /// or empty for update-all and repair.
        #[qsignal]
        #[cxx_name = "operationFinished"]
        fn operation_finished(self: Pin<&mut Reef>, name: QString, ok: bool, message: QString);

        /// A plan is waiting for the person (`pendingPlan`, the same JSON):
        /// the window shows the confirmation sheet. `name` as for
        /// `operationFinished`.
        #[qsignal]
        #[cxx_name = "planReady"]
        fn plan_ready(self: Pin<&mut Reef>, name: QString, plan: QString);

        /// The person declined the pending plan for `name`.
        #[qsignal]
        #[cxx_name = "planDeclined"]
        fn plan_declined(self: Pin<&mut Reef>, name: QString);
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
use reef_backend::packagekit::{Progress, SteadyProgress};
use reef_backend::release::{self, SailfishRelease};
use reef_backend::repo::{PinState, RepoConfig, SsuRepo};
use reef_licence::{Licence, Policy};

use reef_backend::plan::Plan;

use crate::jobs::{self, Ask, Op, PkState, RefreshInput, RefreshOutput};
use crate::rows::{self, Value, LICENCE_ROLES, PACKAGE_ROLES};
use crate::settings::{normalise_days, Settings};

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
    config: RepoConfig,
    release: Option<SailfishRelease>,
    arch: String,
    catalogue: Option<Catalogue>,
    pk: PkState,
    repos: Option<Vec<SsuRepo>>,
    settings_path: Option<PathBuf>,
    licence_dir: Option<PathBuf>,
    cache_path: Option<PathBuf>,
    /// A `refresh()` arrived while another job was running.
    pending_refresh: bool,
    /// A `checkPurchases()` arrived while another job was running.
    pending_purchase_check: bool,
    /// When `checkPurchases()` last asked the licence service.
    last_purchase_check: Option<std::time::Instant>,
    /// What the person asked for and the plan the confirmation sheet shows,
    /// until they confirm or decline it. Nothing else starts meanwhile.
    pending: Option<(Ask, Plan)>,
    /// Every listed package as the models show it, from the last rebuild:
    /// a search filters these instead of rebuilding everything (and
    /// re-verifying every licence) on each keystroke.
    package_rows: Vec<rows::PackageRow>,
    /// What `browseModel` shows: kind and id (`browse`).
    browse: (String, String),
}

#[allow(
    clippy::struct_excessive_bools,
    reason = "the Qt properties behind the QML object, one field each"
)]
pub struct ReefRust {
    installed_release: QString,
    arch: QString,
    repo_alias: QString,
    repo_state: QString,
    registered_repo_url: QString,
    busy: bool,
    busy_package: QString,
    busy_text: QString,
    progress: i32,
    last_error: QString,
    /// Every Reef update Update all applies: apps, and the libraries and
    /// services they use.
    update_count: i32,
    /// The apps among them, as the store lists them.
    app_update_count: i32,
    /// The plan waiting for the person's tap, as JSON; empty when none.
    pending_plan: QString,
    background_check_asked: bool,
    background_wifi_only: bool,
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
    background_check_days: i32,
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
            installed_release: QString::default(),
            arch: QString::default(),
            repo_alias: QString::default(),
            // Assumed pinned until the `ssu lr` check that runs at start
            // says otherwise, so the repair banner does not flash up.
            repo_state: QString::from("pinned"),
            registered_repo_url: QString::default(),
            busy: false,
            busy_package: QString::default(),
            busy_text: QString::default(),
            progress: -1,
            last_error: QString::default(),
            update_count: 0,
            app_update_count: 0,
            pending_plan: QString::default(),
            background_check_asked: settings.background_check_asked,
            background_wifi_only: settings.background_wifi_only,
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
            background_check_days: settings.background_check_days,
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
        // The installed repo.conf, as the installer registered it; developer
        // and test overrides (never set on a phone): REEF_SYSROOT (root for
        // the release files) and REEF_URL_TEMPLATE.
        let root = jobs::sysroot();
        let config = jobs::repo_config(&root);
        let release = release::detect(&root);
        let arch = release::native_arch().to_string();
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
            r.installed_release = QString::from(
                release
                    .as_ref()
                    .map(reef_backend::release::SailfishRelease::full)
                    .unwrap_or_default()
                    .as_str(),
            );
            r.arch = QString::from(arch.as_str());
            r.repo_alias = QString::from(config.alias.as_str());
            r.catalogue_model = catalogue_model;
            r.installed_model = installed_model;
            r.licence_model = licence_model;
            r.featured_model = featured_model;
            r.recent_model = recent_model;
            r.categories_model = categories_model;
            r.collections_model = collections_model;
            r.browse_model = browse_model;
            r.refresh_on_start = settings.refresh_on_start;
            r.background_check_days = settings.background_check_days;
            r.background_check_asked = settings.background_check_asked;
            r.background_wifi_only = settings.background_wifi_only;
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
            r.core.config = config;
            r.core.release = release;
            r.core.arch = arch;
            r.core.settings_path = settings_path;
            r.core.licence_dir = LicenceStore::default_dir();
        }

        self.as_mut()
            .on_refresh_on_start_changed(qobject::Reef::save_settings)
            .release();
        // Picking a background check setting is an answer too: the timer
        // follows it.
        self.as_mut()
            .on_background_check_days_changed(|q| {
                let days = q.background_check_days;
                q.answer_background_checks_days(days);
            })
            .release();
        self.as_mut()
            .on_background_wifi_only_changed(qobject::Reef::save_settings)
            .release();
        // Reef 27 and earlier left the install record world-writable.
        jobs::secure_ledger();
        // The timer follows the person's answer at every start too: a
        // switch that failed (Reef 28 test builds ran systemctl in secure
        // mode) is put right without asking again.
        if self.settings().background_check_asked {
            let on = self.settings().background_checks_on();
            let started = std::thread::Builder::new()
                .name("reef-timer".into())
                .spawn(move || {
                    if let Err(e) = crate::check::set_timer(on) {
                        log::warn!("{e}");
                    }
                });
            if let Err(e) = started {
                log::warn!("switching the background check: {e}");
            }
        }
        self.as_mut()
            .on_licence_server_changed(qobject::Reef::save_settings)
            .release();
        self.as_mut()
            .on_search_text_changed(qobject::Reef::apply_search)
            .release();

        self.as_mut().rebuild_models();
        // Repository state and install state from the phone itself (ssu and
        // PackageKit; no network), in the background.
        self.as_mut().start_local_check();
    }
}

impl qobject::Reef {
    fn save_settings(mut self: Pin<&mut Self>) {
        let days = normalise_days(self.background_check_days);
        if days != self.background_check_days {
            // Re-enters through the changed signal and saves from there.
            self.as_mut().set_background_check_days(days);
            return;
        }
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
            background_check_days: normalise_days(self.background_check_days),
            background_check_asked: self.background_check_asked,
            background_wifi_only: self.background_wifi_only,
            licence_server: self.licence_server.to_string(),
        }
    }

    pub fn answer_background_checks(self: Pin<&mut Self>, check: bool) {
        self.answer_background_checks_days(i32::from(check));
    }

    /// The person chose background checks every `days` (0: never): saved,
    /// and the check's user timer enabled or disabled to match, off the GUI
    /// thread (`systemctl --user`).
    fn answer_background_checks_days(mut self: Pin<&mut Self>, days: i32) {
        let days = normalise_days(days);
        if days != self.background_check_days {
            // Re-enters through the changed signal.
            self.as_mut().set_background_check_days(days);
            return;
        }
        set_notify!(
            self,
            background_check_asked,
            background_check_asked_changed,
            true
        );
        self.as_mut().save_settings();
        let on = self.settings().background_checks_on();
        let started = std::thread::Builder::new()
            .name("reef-timer".into())
            .spawn(move || {
                if let Err(e) = crate::check::set_timer(on) {
                    log::warn!("{e}");
                }
            });
        if let Err(e) = started {
            log::warn!("switching the background check: {e}");
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

    /// Rebuilds all four models and `updateCount` from the current state.
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

        let package_rows = match (&self.core.catalogue, &self.core.release) {
            (Some(c), Some(r)) => rows::package_rows(
                c,
                r,
                &self.core.pk.installed,
                &self.core.pk.updates,
                &licensed,
                &asset,
                rows::today(now),
            ),
            _ => Vec::new(),
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
        let update_count = qt_count(self.core.pk.updates.len());
        let app_update_count = qt_count(
            package_rows
                .iter()
                .filter(|r| r.install_state == "update_available")
                .count(),
        );

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
        set_notify!(self, update_count, update_count_changed, update_count);
        set_notify!(
            self,
            app_update_count,
            app_update_count_changed,
            app_update_count
        );
        let revision = self.revision.wrapping_add(1);
        self.as_mut().rust_mut().revision = revision;
        self.as_mut().revision_changed();
    }

    fn set_repos(mut self: Pin<&mut Self>, repos: Vec<SsuRepo>) {
        let (state, url) = match &self.core.release {
            Some(release) => {
                let state = self.core.config.pin_state(&repos, release, &self.core.arch);
                (
                    rows::repo_state(&state),
                    rows::registered_url(&repos, &self.core.config.alias),
                )
            }
            None => ("missing", String::new()),
        };
        self.as_mut().rust_mut().core.repos = Some(repos);
        set_notify!(self, repo_state, repo_state_changed, QString::from(state));
        set_notify!(
            self,
            registered_repo_url,
            registered_repo_url_changed,
            QString::from(url.as_str())
        );
    }

    fn pin_state(&self) -> Option<PinState> {
        let release = self.core.release.as_ref()?;
        let repos = self.core.repos.as_deref().unwrap_or(&[]);
        Some(self.core.config.pin_state(repos, release, &self.core.arch))
    }

    fn set_error(mut self: Pin<&mut Self>, error: &str) {
        set_notify!(self, last_error, last_error_changed, QString::from(error));
    }

    /// Marks a job as started. Returns false (and changes nothing) when
    /// another job is running.
    fn begin_job(mut self: Pin<&mut Self>, package: &str, text: &str) -> bool {
        if self.busy {
            return false;
        }
        set_notify!(
            self,
            busy_package,
            busy_package_changed,
            QString::from(package)
        );
        set_notify!(self, busy_text, busy_text_changed, QString::from(text));
        set_notify!(self, progress, progress_changed, -1);
        set_notify!(self, busy, busy_changed, true);
        true
    }

    fn end_job(mut self: Pin<&mut Self>) {
        set_notify!(self, busy, busy_changed, false);
        set_notify!(self, busy_package, busy_package_changed, QString::default());
        set_notify!(self, busy_text, busy_text_changed, QString::default());
        set_notify!(self, progress, progress_changed, -1);
        if self.core.pending.is_some() {
            // A refresh waits until the person has answered the sheet, so
            // that their tap never meets a busy store.
            return;
        }
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
            config: self.core.config.clone(),
            release: self.core.release.clone(),
            arch: self.core.arch.clone(),
            previous: self.core.catalogue.clone(),
            licence_dir: self.core.licence_dir.clone(),
            licence_server: self.licence_server.to_string(),
            cache_path: self.core.cache_path.clone(),
            index_check: jobs::index_check(&self.core.config.alias),
        }
    }

    fn apply_refresh(mut self: Pin<&mut Self>, out: RefreshOutput, full: bool) {
        // The worker has already cached it (jobs::refresh, atomically).
        if let Some(catalogue) = out.catalogue {
            self.as_mut().rust_mut().core.catalogue = Some(catalogue);
        }
        if let Some(repos) = out.repos {
            self.as_mut().set_repos(repos);
        }
        if let Some(pk) = out.pk {
            self.as_mut().rust_mut().core.pk = pk;
        }
        if full || !out.errors.is_empty() {
            self.as_mut().set_error(&out.errors.join("\n"));
        }
        for e in &out.errors {
            log::warn!("{e}");
        }
        self.as_mut().rebuild_models();
        self.end_job();
    }

    /// Start-up check: `ssu lr` and `PackageKit` only, against the cached
    /// catalogue.
    fn start_local_check(mut self: Pin<&mut Self>) {
        if !self.as_mut().begin_job("", "checking") {
            return;
        }
        let input = self.refresh_input();
        self.as_mut().spawn(move |thread| {
            let mut out = RefreshOutput::default();
            match jobs::ssu_repos() {
                Ok(repos) => out.repos = Some(repos),
                Err(e) => out.errors.push(e),
            }
            let alias = input.config.alias.clone();
            match jobs::local_state(&alias, input.previous.as_ref()) {
                Ok(pk) => out.pk = Some(pk),
                Err(e) => out.errors.push(e),
            }
            queue_or_log(&thread, move |q| q.apply_refresh(out, false));
        });
    }

    fn apply_progress(mut self: Pin<&mut Self>, p: &Progress) {
        set_notify!(
            self,
            progress,
            progress_changed,
            rows::progress_value(p.percentage)
        );
        set_notify!(
            self,
            busy_text,
            busy_text_changed,
            QString::from(rows::status_text(p.status))
        );
    }

    /// Works out what `ask` would do and offers it to the person
    /// (`pendingPlan`, `planReady`); nothing is installed or removed.
    fn start_preview(mut self: Pin<&mut Self>, ask: Ask) {
        let name = ask.package().to_string();
        if self.core.pending.is_some() || !self.as_mut().begin_job(&name, "checking_plan") {
            self.operation_finished(
                QString::from(name.as_str()),
                false,
                QString::from(rows::message("busy", &[]).as_str()),
            );
            return;
        }
        let alias = self.core.config.alias.clone();
        let mut catalogue = self.core.catalogue.clone();
        let details = self.details_source();
        self.as_mut().spawn(move |thread| {
            // What the plan shows (services, changes, the build for this
            // processor) is in the app's details.
            if let (Some(c), Some((base, dir))) = (catalogue.as_mut(), &details) {
                for e in jobs::load_details(c, base, dir, &[ask.package().to_string()], false) {
                    log::warn!("details: {e}");
                }
            }
            let result = jobs::preview(&ask, &alias, catalogue.as_ref());
            queue_or_log(&thread, move |mut q| match result {
                Ok(plan) => {
                    let json = QString::from(plan.to_json().as_str());
                    q.as_mut().rust_mut().core.pending = Some((ask, plan));
                    set_notify!(q, pending_plan, pending_plan_changed, json.clone());
                    q.as_mut().end_job();
                    q.plan_ready(QString::from(name.as_str()), json);
                }
                Err(e) => {
                    log::warn!("{name}: {e}");
                    q.as_mut().set_error(&e);
                    q.as_mut().end_job();
                    q.operation_finished(
                        QString::from(name.as_str()),
                        false,
                        QString::from(e.as_str()),
                    );
                }
            });
        });
    }

    /// Takes the pending plan away from the sheet, and starts the refresh
    /// that waited for it.
    fn take_pending(mut self: Pin<&mut Self>) -> Option<(Ask, Plan)> {
        let pending = self.as_mut().rust_mut().core.pending.take();
        set_notify!(self, pending_plan, pending_plan_changed, QString::default());
        pending
    }

    pub fn confirm_plan(mut self: Pin<&mut Self>) {
        let Some((ask, plan)) = self.as_mut().take_pending() else {
            return;
        };
        self.start_op(Op { ask, plan });
    }

    pub fn decline_plan(mut self: Pin<&mut Self>) {
        let Some((ask, _)) = self.as_mut().take_pending() else {
            return;
        };
        self.as_mut().plan_declined(QString::from(ask.package()));
        // What waited for the answer.
        if !self.busy {
            self.as_mut().end_job();
        }
    }

    fn start_op(mut self: Pin<&mut Self>, op: Op) {
        let name = op.package().to_string();
        if !self.as_mut().begin_job(&name, "starting") {
            self.operation_finished(
                QString::from(name.as_str()),
                false,
                QString::from(rows::message("busy", &[]).as_str()),
            );
            return;
        }
        let alias = self.core.config.alias.clone();
        let catalogue = self.core.catalogue.clone();
        self.as_mut().spawn(move |thread| {
            let progress_thread = thread.clone();
            // The bar only moves forward, and only changes are posted.
            let mut steady = SteadyProgress::default();
            let mut on_progress = |p: Progress| {
                if let Some(p) = steady.next(p) {
                    queue_or_log(&progress_thread, move |q| q.apply_progress(&p));
                }
            };
            let (result, state) = jobs::run_op(&op, &alias, catalogue.as_ref(), &mut on_progress);
            queue_or_log(&thread, move |mut q| {
                if let Some(state) = state {
                    q.as_mut().rust_mut().core.pk = state;
                }
                q.as_mut().rebuild_models();
                q.as_mut().end_job();
                let (ok, message) = match result {
                    Ok(m) => (true, m),
                    Err(e) => {
                        log::warn!("{}: {e}", op.package());
                        // Shown on every page, not only to a PackagePage
                        // listening for operationFinished (U-04).
                        q.as_mut().set_error(&e);
                        (false, e)
                    }
                };
                q.operation_finished(
                    QString::from(op.package()),
                    ok,
                    QString::from(message.as_str()),
                );
            });
        });
    }

    pub fn refresh(mut self: Pin<&mut Self>) {
        if self.busy || self.core.pending.is_some() {
            self.as_mut().rust_mut().core.pending_refresh = true;
            return;
        }
        if !self.as_mut().begin_job("", "refreshing") {
            return;
        }
        let input = self.refresh_input();
        self.as_mut().spawn(move |thread| {
            let out = jobs::refresh(&input);
            queue_or_log(&thread, move |q| q.apply_refresh(out, true));
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
        let release = self.core.release.as_ref()?;
        let cache = self.core.cache_path.as_deref()?;
        Some((
            self.core.config.resolved_url(release, &self.core.arch),
            jobs::details_dir(cache),
        ))
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
        let (Some(catalogue), Some(release)) = (&self.core.catalogue, &self.core.release) else {
            return QMap::default();
        };
        let Some(package) = catalogue.visible_package(&name, release) else {
            return QMap::default();
        };
        let state = rows::state_of(
            catalogue,
            release,
            &self.core.pk.installed,
            &self.core.pk.updates,
            &name,
        )
        .unwrap_or(reef_backend::store::InstallState::NotInstalled);
        let now = jobs::unix_now();
        let licensed = package.licence.app_id().is_some_and(|app| {
            self.licence_store()
                .and_then(|s| s.check(app, now))
                .is_some_and(|s| rows::licence_usable(&s))
        });
        let mut details = rows::package_details(package, &state, licensed, &|rel| self.asset(rel));
        // Reef offers Remove only for what it installed (fix 8).
        details.push(("removable", self.core.pk.removable.contains(&name).into()));
        to_map(&details)
    }

    pub fn can_open(&self, name: &QString) -> bool {
        crate::launch::desktop_entry(&jobs::sysroot(), &name.to_string()).is_some()
    }

    pub fn open(&self, name: &QString) -> bool {
        let Some(entry) = crate::launch::desktop_entry(&jobs::sysroot(), &name.to_string()) else {
            return false;
        };
        match crate::launch::open(&entry) {
            Ok(()) => true,
            Err(e) => {
                log::warn!("opening {entry}: {e}");
                false
            }
        }
    }

    pub fn install(self: Pin<&mut Self>, name: &QString) {
        self.start_preview(Ask::Install(name.to_string()));
    }

    pub fn update(self: Pin<&mut Self>, name: &QString) {
        self.start_preview(Ask::Update(name.to_string()));
    }

    pub fn update_all(self: Pin<&mut Self>) {
        self.start_preview(Ask::UpdateAll);
    }

    pub fn remove(self: Pin<&mut Self>, name: &QString) {
        self.start_preview(Ask::Remove(name.to_string()));
    }

    pub fn repair_repository(mut self: Pin<&mut Self>) {
        let (Some(release), Some(state)) = (self.core.release.clone(), self.pin_state()) else {
            self.operation_finished(
                QString::default(),
                false,
                QString::from(rows::message("no_release", &[]).as_str()),
            );
            return;
        };
        if !self.as_mut().begin_job("", "repairing") {
            self.operation_finished(
                QString::default(),
                false,
                QString::from(rows::message("busy", &[]).as_str()),
            );
            return;
        }
        let commands = self.core.config.repair_commands(&state, &release);
        self.as_mut().spawn(move |thread| {
            let result = jobs::run_commands(&commands);
            let repos = jobs::ssu_repos();
            queue_or_log(&thread, move |mut q| {
                if let Ok(repos) = repos {
                    q.as_mut().set_repos(repos);
                }
                q.as_mut().end_job();
                let (ok, message) = match result {
                    Ok(()) => (true, String::new()),
                    Err(e) => (false, e),
                };
                q.as_mut().set_error(&message);
                q.operation_finished(QString::default(), ok, QString::from(message.as_str()));
            });
        });
    }

    pub fn repair_commands(&self) -> QStringList {
        let lines: Vec<String> = match (&self.core.release, self.pin_state()) {
            (Some(release), Some(state)) => self
                .core
                .config
                .repair_commands(&state, release)
                .iter()
                .map(reef_backend::repo::Command::to_shell)
                .collect(),
            _ => Vec::new(),
        };
        string_list(&lines)
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
        // Not while the confirmation sheet waits: its tap must find the
        // store free.
        if self.core.pending.is_some() || !self.as_mut().begin_job("", "refreshing_licences") {
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
        let paid = match (&self.core.catalogue, &self.core.release) {
            (Some(c), Some(r)) => match c.visible_package(&name, r).map(|p| &p.licence) {
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
            _ => None,
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
        if self.busy || self.core.pending.is_some() {
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
