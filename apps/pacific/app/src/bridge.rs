// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The `Pacific` QML singleton (`import Shipwright.Pacific 1.0`): the
//! browser's services for the QML UI.
//!
//! Cheap, in-memory decisions (what typed text means, HTTPS-first steps,
//! the tab discard policy, Pilot's snapshot checks) answer at once. Every
//! database, file or network operation runs on the core thread
//! ([`crate::worker`]) or the network runtime ([`crate::net`]) and reports
//! back through a signal queued onto the GUI thread. `revision` goes up
//! when history or bookmarks change, and the list models re-read then.

#![allow(
    clippy::unnecessary_box_returns,
    reason = "cxx_qt::bridge generates the boxed default constructor of the Rust struct"
)]

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
        include!("cxx-qt-lib/qguiapplication.h");
        type QGuiApplication = cxx_qt_lib::QGuiApplication;
    }

    unsafe extern "C++" {
        include!("shipwright-pacific/cpp/launcher.h");
        /// Loads `qml_path` into Keel's `SailfishApp::createView()` and
        /// shows it. See cpp/launcher.cpp.
        fn keel_show_main_view(qml_path: &QString) -> bool;
        /// Deletes the view after the event loop ends.
        fn keel_destroy_main_view();
        fn keel_application() -> *mut QGuiApplication;
        fn keel_launch_arguments() -> QStringList;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qml_singleton]
        #[qproperty(bool, ready, READ, NOTIFY)]
        /// Goes up when history, bookmarks or downloads change.
        #[qproperty(i32, revision, READ, NOTIFY)]
        /// The global settings as JSON (pacific_core::settings::Settings).
        #[qproperty(QString, settings, READ, NOTIFY)]
        /// Search engines as JSON, in the person's order.
        #[qproperty(QString, engines, READ, NOTIFY)]
        #[qproperty(QString, default_engine, cxx_name = "defaultEngine", READ, NOTIFY)]
        /// The last run ended without a clean exit.
        #[qproperty(bool, crashed, READ, NOTIFY)]
        /// The saved session to restore, as JSON (empty when none).
        #[qproperty(QString, saved_session, cxx_name = "savedSession", READ, NOTIFY)]
        /// URLs from the command line, as JSON.
        #[qproperty(QString, startup_urls, cxx_name = "startupUrls", READ, CONSTANT)]
        #[qproperty(bool, blocker_ready, cxx_name = "blockerReady", READ, NOTIFY)]
        #[qproperty(bool, lists_updating, cxx_name = "listsUpdating", READ, NOTIFY)]
        /// Sites with their shields down (blocking and cookie-banner
        /// answers off), as a JSON array of hosts.
        #[qproperty(
            QString,
            shields_down_sites,
            cxx_name = "shieldsDownSites",
            READ,
            NOTIFY
        )]
        /// The autoconsent script to inject (empty when not installed).
        #[qproperty(
            QString,
            autoconsent_script,
            cxx_name = "autoconsentScript",
            READ,
            NOTIFY
        )]
        #[qproperty(QString, download_dir, cxx_name = "downloadDir", READ, NOTIFY)]
        #[qproperty(QString, thumbnail_dir, cxx_name = "thumbnailDir", READ, CONSTANT)]
        /// Pilot's background browsing, as JSON (AgentSession).
        #[qproperty(QString, agent, READ, NOTIFY)]
        /// Live web processes to keep without memory pressure.
        #[qproperty(i32, tab_budget, cxx_name = "tabBudget", READ, CONSTANT)]
        #[qproperty(QString, version, READ, CONSTANT)]
        /// Why the profile could not be opened (then nothing is kept).
        #[qproperty(QString, profile_error, cxx_name = "profileError", READ, NOTIFY)]
        type Pacific = super::PacificRust;

        // ---- Address bar --------------------------------------------------

        /// What typed text means: `{"kind": "url", "url"}` or
        /// `{"kind": "search", "engine", "query", "url"}`; `{}` for none.
        #[qinvokable]
        fn classify(self: &Pacific, text: &QString) -> QString;

        /// The results page of the default engine for `query`.
        #[qinvokable]
        fn search_url(self: &Pacific, query: &QString) -> QString;

        /// The person chose `url` after typing `input`.
        #[qinvokable]
        fn record_selection(self: &Pacific, input: &QString, url: &QString);

        // ---- History and bookmarks ----------------------------------------

        /// `transition`: link, typed, bookmark, reload, redirect, restore.
        #[qinvokable]
        fn record_visit(
            self: &Pacific,
            url: &QString,
            title: &QString,
            transition: &QString,
            private_tab: bool,
        );

        #[qinvokable]
        fn set_page_title(self: &Pacific, url: &QString, title: &QString, private_tab: bool);

        #[qinvokable]
        /// Records the page's icon and fetches it once into the cache;
        /// answers with `iconCached(url, fileUrl)` when it is there.
        fn set_page_icon(self: &Pacific, url: &QString, icon: &QString, private_tab: bool);

        /// The registrable domain of a page (`en.wikipedia.org` ->
        /// `wikipedia.org`), what the address bar shows; "" for non-web pages.
        #[qinvokable]
        fn site_of(self: &Pacific, url: &QString) -> QString;

        /// Whether this process's program was replaced on disk (an update):
        /// a prestarted Pacific waiting unseen then quits, and its service
        /// starts the new one (Browser.waiting).
        #[qinvokable]
        fn binary_replaced(self: &Pacific) -> bool;

        /// Started ahead of use by its user service (PACIFIC_PRESTART=1):
        /// loaded with no window until opened (Browser.waiting).
        #[qinvokable]
        fn prestarted(self: &Pacific) -> bool;

        /// A short name for the site of `url` (`wikipedia` for
        /// `https://en.wikipedia.org/…`), for labels under site icons.
        #[qinvokable]
        fn site_name(self: &Pacific, url: &QString) -> QString;

        /// A search made from the address bar (recent searches; never for
        /// private tabs).
        #[qinvokable]
        fn record_search(self: &Pacific, query: &QString, engine: &QString, private_tab: bool);

        #[qinvokable]
        fn delete_search(self: &Pacific, query: &QString);

        #[qinvokable]
        fn delete_history(self: &Pacific, url: &QString);

        #[qinvokable]
        fn hide_top_site(self: &Pacific, url: &QString);

        /// Answers with `bookmarkState(url, bookmarked)`.
        #[qinvokable]
        fn check_bookmark(self: &Pacific, url: &QString);

        /// Adds a bookmark (folder 1 is the root) or, if `url` is
        /// bookmarked already, removes it. Answers with `bookmarkState`.
        #[qinvokable]
        fn toggle_bookmark(self: &Pacific, url: &QString, title: &QString);

        #[qinvokable]
        fn add_bookmark(self: &Pacific, url: &QString, title: &QString, folder: i64);

        #[qinvokable]
        fn add_folder(self: &Pacific, title: &QString, parent: i64);

        #[qinvokable]
        fn edit_bookmark(self: &Pacific, id: i64, title: &QString, url: &QString, folder: i64);

        #[qinvokable]
        fn delete_bookmark(self: &Pacific, id: i64);

        #[qinvokable]
        fn import_bookmarks(self: &Pacific, path: &QString);

        #[qinvokable]
        fn export_bookmarks(self: &Pacific, path: &QString);

        // ---- Settings -----------------------------------------------------

        /// Sets global settings from a JSON object of changed keys.
        #[qinvokable]
        fn set_settings(self: &Pacific, patch_json: &QString);

        #[qinvokable]
        fn set_default_engine(self: &Pacific, id: &QString);

        /// Answers with `engineAdded(ok, message)`.
        #[qinvokable]
        fn add_engine(
            self: &Pacific,
            name: &QString,
            keyword: &QString,
            url_template: &QString,
            suggest: &QString,
        );

        #[qinvokable]
        fn remove_engine(self: &Pacific, id: &QString);

        /// Answers with `siteSettingsLoaded(url, json)`.
        #[qinvokable]
        fn load_site_settings(self: &Pacific, url: &QString, private_tab: bool);

        /// `value` empty clears the setting.
        #[qinvokable]
        fn set_site_setting(
            self: &Pacific,
            url: &QString,
            key: &QString,
            value: &QString,
            private_tab: bool,
        );

        #[qinvokable]
        fn clear_site_settings(self: &Pacific, site: &QString);

        /// Loads `host` over HTTPS first again.
        #[qinvokable]
        fn remove_https_exception(self: Pin<&mut Pacific>, host: &QString);

        /// `range`: last_hour, today, last_week, last_four_weeks, all;
        /// `what_json`: `{history, cookies, cache, downloads, site_settings,
        /// session}`. Answers with `dataCleared(json)` (the engine's part).
        #[qinvokable]
        fn clear_data(self: &Pacific, range: &QString, what_json: &QString);

        // ---- Session and tabs ---------------------------------------------

        /// Saves the session (TabModel.sessionJson()); debounced by the UI.
        #[qinvokable]
        fn save_session(self: &Pacific, json: &QString);

        /// Marks a clean exit (the UI calls it when it quits).
        #[qinvokable]
        fn shutdown(self: Pin<&mut Pacific>);

        /// The tab lifecycle decisions for `tabs_json`
        /// (`[{id, lastActive, foreground, pinned, audible, formDirty,
        /// live}]`), as JSON `[{action, tab}]`.
        #[qinvokable]
        fn lifecycle(self: &Pacific, tabs_json: &QString) -> QString;

        // ---- Protection ---------------------------------------------------

        /// HTTPS-first for a navigation starting in `tab`:
        /// `{"action": "load", "url"}`, `{"action": "proceed"}` or
        /// `{"action": "interstitial", "http_url", "host"}`.
        #[qinvokable]
        fn https_navigate(self: Pin<&mut Pacific>, tab: i64, url: &QString) -> QString;

        /// The load finished; true when that completed an upgrade.
        #[qinvokable]
        fn https_finished(self: Pin<&mut Pacific>, tab: i64, url: &QString) -> bool;

        #[qinvokable]
        fn https_failed(self: Pin<&mut Pacific>, tab: i64) -> QString;

        /// From the UI's timer while an upgrade is pending.
        #[qinvokable]
        fn https_timeout(self: Pin<&mut Pacific>, tab: i64) -> QString;

        #[qinvokable]
        fn https_pending(self: &Pacific, tab: i64) -> bool;

        /// "Continue to the site" on the interstitial.
        #[qinvokable]
        fn https_allow(self: Pin<&mut Pacific>, host: &QString, private_tab: bool);

        /// Answers with `cosmeticReady(tab, url, css, script, extra)`.
        #[qinvokable]
        fn cosmetic(self: &Pacific, tab: i64, url: &QString);

        #[qinvokable]
        fn page_started(self: Pin<&mut Pacific>, tab: i64, url: &QString);

        /// A request from `tab`'s page was blocked (if the engine reports it).
        #[qinvokable]
        fn request_blocked(self: Pin<&mut Pacific>, tab: i64, url: &QString);

        /// A report autoconsent posted from `tab`'s page (as JSON, to the
        /// `shipConsent` handler); true when it answered a cookie banner.
        #[qinvokable]
        fn consent_report(
            self: Pin<&mut Pacific>,
            tab: i64,
            report: &QString,
            private_tab: bool,
        ) -> bool;

        /// `{page_url, blocked, by_site, cookie_banner_handled, https_upgraded}`.
        #[qinvokable]
        fn page_stats(self: &Pacific, tab: i64) -> QString;

        #[qinvokable]
        fn tab_closed(self: Pin<&mut Pacific>, tab: i64);

        /// Answers with `totalsReady(json)`.
        #[qinvokable]
        fn load_totals(self: &Pacific);

        #[qinvokable]
        fn set_list_enabled(self: &Pacific, id: &QString, on: bool);

        /// Refreshes the filter lists that are due (or all with `force`).
        #[qinvokable]
        fn update_lists(self: Pin<&mut Pacific>, force: bool);

        // ---- Reader mode --------------------------------------------------

        /// Extracts the article of `html` (the page at `url`) and writes the
        /// reader page; answers with `readerReady(tab, ok, fileUrl, json)`.
        #[qinvokable]
        fn reader(self: &Pacific, tab: i64, url: &QString, html: &QString, minutes_label: &QString);

        // ---- Downloads ----------------------------------------------------

        /// A free path in the downloads directory for `suggested`, to set as
        /// the engine download's destination; also records the download.
        #[qinvokable]
        fn download_destination(
            self: &Pacific,
            url: &QString,
            suggested: &QString,
            mime: &QString,
            private_tab: bool,
        ) -> QString;

        /// `state`: running, finished, failed, cancelled.
        #[qinvokable]
        fn download_update(
            self: &Pacific,
            path: &QString,
            received: f64,
            total: f64,
            state: &QString,
            error: &QString,
            private_tab: bool,
        );

        #[qinvokable]
        fn remove_download(self: &Pacific, id: i64, delete_file: bool);

        #[qinvokable]
        fn clear_downloads(self: &Pacific);

        // ---- Shoal Keys ---------------------------------------------------

        /// Answers with `keysLoginsReady(tab, json, error)`.
        #[qinvokable]
        fn keys_logins(self: &Pacific, tab: i64, url: &QString);

        /// Answers with `keysFillReady(tab, script, error)`: the script fills the
        /// login form (run it in the "pacific" world).
        #[qinvokable]
        fn keys_fill(self: &Pacific, tab: i64, url: &QString, id: &QString);

        /// Answers with `keysSaved(status)`.
        #[qinvokable]
        fn keys_save(self: &Pacific, url: &QString, username: &QString, password: &QString);

        /// The script that detects a login form (run in "pacific").
        #[qinvokable]
        fn login_detector(self: &Pacific) -> QString;

        /// The script that reports submitted logins to the `shipLogin`
        /// message handler (isolated world "pacific", document end).
        #[qinvokable]
        fn login_watcher(self: &Pacific) -> QString;

        // ---- Home screen --------------------------------------------------

        /// Adds a launcher icon that opens `url` in Pacific. Answers with
        /// `notice(text)`.
        #[qinvokable]
        fn add_to_home_screen(self: &Pacific, url: &QString, title: &QString);

        // ---- Pilot --------------------------------------------------------

        /// Parses and checks a web view snapshot (agentSnapshot's result as
        /// JSON): `{ok, snapshot, outline}` or `{ok: false, error}`.
        #[qinvokable]
        fn agent_snapshot(self: &Pacific, json: &QString, outline_chars: i32) -> QString;

        /// Whether Pilot may fill `id` in the snapshot: "" or the reason not.
        #[qinvokable]
        fn agent_check_fill(self: &Pacific, json: &QString, id: &QString) -> QString;

        /// search, login, payment or other.
        #[qinvokable]
        fn agent_form_risk(self: &Pacific, json: &QString, form: &QString) -> QString;

        /// Page text made safe to hand to a model, at most `max` characters.
        #[qinvokable]
        fn untrusted(self: &Pacific, text: &QString, max: i32) -> QString;

        /// The URL Pilot may open, or "" (not a web page).
        #[qinvokable]
        fn agent_url(self: &Pacific, url: &QString) -> QString;

        #[qinvokable]
        fn agent_start(self: Pin<&mut Pacific>, tab: i64);

        #[qinvokable]
        fn agent_visited(self: Pin<&mut Pacific>, url: &QString);

        #[qinvokable]
        fn agent_stop(self: Pin<&mut Pacific>);

        // ---- Signals ------------------------------------------------------

        #[qsignal]
        fn started(self: Pin<&mut Pacific>, ok: bool, message: QString);

        #[qsignal]
        fn content_filter_compile(self: Pin<&mut Pacific>, identifier: QString, json: QString);

        /// The engine's answer for a content filter: compiled or loaded and
        /// in its store (`ok`), or not, in which case it is compiled again
        /// from the JSON kept on disk (`contentFilterCompile`). A filter
        /// counts as compiled only once this says so.
        #[qinvokable]
        fn content_filter_result(self: Pin<&mut Pacific>, identifier: &QString, ok: bool);

        /// The filter ids that should be active now (load the others from
        /// the store, remove any not listed).
        #[qsignal]
        fn content_filters_active(self: Pin<&mut Pacific>, ids_json: QString);

        /// `extra`: `{exceptions, generichide, procedural}`.
        #[qsignal]
        fn cosmetic_ready(
            self: Pin<&mut Pacific>,
            tab: i64,
            url: QString,
            css: QString,
            script: QString,
            extra: QString,
        );

        #[qsignal]
        fn reader_ready(
            self: Pin<&mut Pacific>,
            tab: i64,
            ok: bool,
            file_url: QString,
            json: QString,
        );

        #[qsignal]
        fn site_settings_loaded(self: Pin<&mut Pacific>, url: QString, json: QString);

        #[qsignal]
        fn bookmark_state(self: Pin<&mut Pacific>, url: QString, bookmarked: bool);

        #[qsignal]
        fn data_cleared(self: Pin<&mut Pacific>, json: QString);

        #[qsignal]
        fn totals_ready(self: Pin<&mut Pacific>, json: QString);

        #[qsignal]
        fn engine_added(self: Pin<&mut Pacific>, ok: bool, message: QString);

        #[qsignal]
        fn keys_logins_ready(self: Pin<&mut Pacific>, tab: i64, json: QString, error: QString);

        #[qsignal]
        fn keys_fill_ready(self: Pin<&mut Pacific>, tab: i64, script: QString, error: QString);

        #[qsignal]
        fn keys_saved(self: Pin<&mut Pacific>, status: QString);

        /// A short message for the person (an import's result, an error).
        #[qsignal]
        fn notice(self: Pin<&mut Pacific>, text: QString);

        /// Another app (or Lipstick) asked to open `url`.
        #[qsignal]
        fn open_url_requested(self: Pin<&mut Pacific>, url: QString);

        /// Pacific was opened while it runs (Reef's Open, the app grid):
        /// come to the front.
        #[qsignal]
        fn raise_requested(self: Pin<&mut Pacific>);

        #[qsignal]
        fn page_stats_changed(self: Pin<&mut Pacific>, tab: i64);

        #[qsignal]
        fn icon_cached(self: Pin<&mut Pacific>, url: QString, file_url: QString);
    }

    impl cxx_qt::Threading for Pacific {}
    impl cxx_qt::Initialize for Pacific {}
}

use core::pin::Pin;
use std::sync::OnceLock;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use pacific_core::agent::{self, AgentSession, Snapshot};
use pacific_core::autoconsent;
use pacific_core::blocker::lists::{self, FilterList, ListStore};
use pacific_core::blocker::record::FilterRecord;
use pacific_core::blocker::stats::{self, StatsBook};
use pacific_core::blocker::{self, Blocker};
use pacific_core::downloads::{self, State};
use pacific_core::frecency::Transition;
use pacific_core::https::{HttpsFirst, Step};
use pacific_core::lifecycle::{self, MemInfo, TabInfo};
use pacific_core::omnibox;
use pacific_core::passwords;
use pacific_core::privacy;
use pacific_core::reader;
use pacific_core::search::SearchEngine;
use pacific_core::settings::Settings;
use pacific_core::util::now_ms;
use serde_json::{json, Value};

use crate::worker::{self, Core};

/// URLs from the command line (set by `run` before the UI loads).
pub static STARTUP_URLS: OnceLock<Vec<String>> = OnceLock::new();

#[allow(
    clippy::struct_excessive_bools,
    reason = "backing fields of independent QML properties"
)]
pub struct PacificRust {
    ready: bool,
    revision: i32,
    settings: QString,
    engines: QString,
    default_engine: QString,
    crashed: bool,
    saved_session: QString,
    startup_urls: QString,
    blocker_ready: bool,
    lists_updating: bool,
    shields_down_sites: QString,
    autoconsent_script: QString,
    download_dir: QString,
    thumbnail_dir: QString,
    agent: QString,
    tab_budget: i32,
    version: QString,
    profile_error: QString,
    // GUI-side state.
    engine_cache: Vec<SearchEngine>,
    settings_cache: Settings,
    https: HttpsFirst,
    stats: StatsBook,
    agent_session: AgentSession,
    /// A stats flush is due ([`qobject::Pacific::flush_stats`]).
    stats_flush_scheduled: bool,
    downloads_dir: std::path::PathBuf,
}

impl Default for PacificRust {
    fn default() -> Self {
        let dirs = worker::Dirs::from_env();
        let budget = MemInfo::read().map_or(3, |m| m.budget());
        Self {
            ready: false,
            revision: 0,
            settings: qs(&serde_json::to_string(&Settings::default()).unwrap_or_default()),
            engines: qs("[]"),
            default_engine: qs("duckduckgo"),
            crashed: false,
            saved_session: QString::default(),
            startup_urls: qs(&serde_json::to_string(
                STARTUP_URLS.get().map_or(&[][..], Vec::as_slice),
            )
            .unwrap_or_default()),
            blocker_ready: false,
            lists_updating: false,
            shields_down_sites: qs("[]"),
            autoconsent_script: QString::default(),
            download_dir: qs(&dirs.downloads.to_string_lossy()),
            thumbnail_dir: qs(&dirs.thumbnails().to_string_lossy()),
            agent: qs("{\"active\":false}"),
            tab_budget: i32::try_from(budget).unwrap_or(3),
            version: qs(env!("CARGO_PKG_VERSION")),
            profile_error: QString::default(),
            engine_cache: pacific_core::search::builtin_engines(),
            settings_cache: Settings::default(),
            https: HttpsFirst::new(true),
            stats: StatsBook::default(),
            agent_session: AgentSession::default(),
            stats_flush_scheduled: false,
            downloads_dir: dirs.downloads.clone(),
        }
    }
}

fn qs(s: &str) -> QString {
    QString::from(s)
}

fn to_json<T: serde::Serialize>(v: &T) -> String {
    serde_json::to_string(v).unwrap_or_else(|_| "null".into())
}

macro_rules! set_notify {
    ($obj:expr, $field:ident, $notify:ident, $value:expr) => {{
        let value = $value;
        if $obj.$field != value {
            $obj.as_mut().rust_mut().$field = value;
            $obj.as_mut().$notify();
        }
    }};
}

/// What the start-up job read.
struct Started {
    settings: Settings,
    engines: Vec<SearchEngine>,
    default_engine: String,
    https_exceptions: Vec<String>,
    session: Option<String>,
    crashed: bool,
    open_error: Option<String>,
    autoconsent: Option<String>,
    download_dir: String,
}

fn start_core(c: &mut Core) -> Started {
    let p = &c.profile;
    let settings = p.settings().unwrap_or_default();
    let engines = p.search_engines().unwrap_or_default();
    let default_engine = p
        .default_engine()
        .map_or_else(|_| "duckduckgo".into(), |e| e.id);
    let https_exceptions = p.https_exceptions().unwrap_or_default();
    let loaded = c.sessions.load();
    if let Err(e) = c.sessions.mark_running() {
        log::warn!("cannot write the crash marker: {e}");
    }
    let session = (!loaded.session.tabs.is_empty()).then(|| to_json(&loaded.session));
    if let Err(e) = p.pause_interrupted_downloads() {
        log::warn!("downloads: {e}");
    }
    // Daily housekeeping.
    let today = stats::day_of(now_ms()).to_string();
    if p.pref("housekeeping.day").ok().flatten().as_deref() != Some(today.as_str()) {
        let _ = p.decay_input_history();
        if settings.history_days > 0 {
            let _ = p.expire_visits(settings.history_days, now_ms());
        }
        let _ = p.set_pref("housekeeping.day", &today);
    }
    let script_path = std::env::var_os("PACIFIC_AUTOCONSENT_JS").map_or_else(
        || c.dirs.share.join("autoconsent/autoconsent.js"),
        std::path::PathBuf::from,
    );
    let autoconsent = match autoconsent::load(&script_path) {
        Ok(s) => Some(s),
        Err(e) => {
            log::info!("cookie-banner rejection is off: {e}");
            None
        }
    };
    let download_dir = if settings.download_dir.is_empty() {
        c.dirs.downloads.to_string_lossy().into_owned()
    } else {
        settings.download_dir.clone()
    };
    Started {
        settings,
        engines,
        default_engine,
        https_exceptions,
        session,
        crashed: loaded.crashed,
        open_error: c.open_error.clone(),
        autoconsent,
        download_dir,
    }
}

/// Loads or builds the filter engine and works out the content filters.
/// Returns (compile: [(id, json)], active ids).
/// What [`prepare_blocker`] made: filters to compile, the ones in force, and
/// the sites with their shields down.
struct Refilter {
    compile: Vec<(String, String)>,
    active: Vec<String>,
    allow: Vec<String>,
}

/// The content filters for WebKit, from the lists' texts (`texts`, as
/// [`ListStore::enabled_texts`] gives them): the ones the engine's store
/// should have in force, and those to compile first. Quick when the record
/// on disk is current (the usual start): no list is converted, and the
/// Rust engine is not needed, so the pages are protected before it loads.
fn prepare_filters(c: &mut Core, texts: &[(&'static FilterList, String)]) -> Refilter {
    let started = std::time::Instant::now();
    let list_texts = ListStore::list_texts(texts);
    let hash = blocker::lists_hash(&list_texts);
    let dir = c.dirs.adblock();
    let allow = c.profile.blocking_allowlist().unwrap_or_default();
    let _ = blocker::BlockerDir::new(&dir).write_allowlist(&allow);
    // Content filters: converted again only when the lists or the allow
    // list change; compiled again (from the JSON kept on disk) whenever the
    // engine has not confirmed them, e.g. after a run killed mid-compile.
    let state_key = format!("{hash}:{}:{}", blocker::webkit::FORMAT, allow.join(","));
    let mut record = FilterRecord::open(&dir);
    if !record.is_current(&state_key) {
        let filters = blocker::webkit::convert_all(&list_texts, &allow);
        log::info!(
            "{} content filters ({} rules) converted from {} lists in {:?}",
            filters.len(),
            filters.iter().map(|f| f.rules).sum::<usize>(),
            list_texts.len(),
            started.elapsed()
        );
        if let Err(e) = record.replace(&state_key, &filters) {
            log::warn!("cannot record the content filters: {e}");
            let ids = filters.iter().map(|f| f.identifier.clone()).collect();
            return Refilter {
                compile: filters
                    .into_iter()
                    .map(|f| (f.identifier, f.json))
                    .collect(),
                active: ids,
                allow,
            };
        }
    }
    let compile = record
        .pending()
        .into_iter()
        .filter_map(|id| record.json(&id).map(|json| (id, json)))
        .collect();
    Refilter {
        compile,
        active: record.ids().to_vec(),
        allow,
    }
}

/// The Rust filter engine (cosmetic filtering, scriptlets, the request
/// counts), from its cache or built from the lists.
fn load_engine(c: &mut Core, texts: &[(&'static FilterList, String)]) {
    let started = std::time::Instant::now();
    let list_texts = ListStore::list_texts(texts);
    let hash = blocker::lists_hash(&list_texts);
    let dir = c.dirs.adblock();
    let engine = Blocker::load(&dir, Some(&hash)).unwrap_or_else(|_| {
        let b = Blocker::build(&list_texts);
        if let Err(e) = b.save(&dir) {
            log::warn!("cannot cache the filter engine: {e}");
        }
        b
    });
    let mut engine = engine;
    let resources = c.dirs.share.join("adblock/resources.json");
    if let Ok(bytes) = std::fs::read(&resources) {
        if let Err(e) = engine.use_resources_json(&bytes) {
            log::warn!("scriptlet resources: {e}");
        }
    }
    c.blocker = Some(engine);
    log::info!("filter engine ready in {:?}", started.elapsed());
}

/// [`prepare_filters`] and [`load_engine`] in one (a change of lists or
/// exceptions, when nothing waits on the engine).
fn prepare_blocker(c: &mut Core) -> Refilter {
    let texts = c.lists.enabled_texts();
    let refilter = prepare_filters(c, &texts);
    load_engine(c, &texts);
    refilter
}

/// On the Qt thread: hands a [`prepare_blocker`] result to QML.
fn apply_refilter(mut q: Pin<&mut qobject::Pacific>, r: Refilter) {
    for (id, json) in r.compile {
        q.as_mut().content_filter_compile(qs(&id), qs(&json));
    }
    q.as_mut().content_filters_active(qs(&to_json(&r.active)));
    set_notify!(
        q,
        shields_down_sites,
        shields_down_sites_changed,
        qs(&to_json(&r.allow))
    );
}

/// Adds blocked-request counts to the day's totals.
fn write_counts(c: &Core, writes: &[(&'static str, i64)]) {
    for (kind, n) in writes {
        if let Err(e) = c.profile.add_protection_count(kind, *n, now_ms()) {
            log::warn!("protection counts: {e}");
        }
    }
}

impl qobject::Pacific {
    /// A flush of the page stats in [`stats::EMIT_INTERVAL_MS`], unless
    /// one is due already (without the timer runtime: now).
    fn schedule_stats_flush(mut self: Pin<&mut Self>) {
        if self.stats_flush_scheduled {
            return;
        }
        let Some(rt) = crate::net::runtime() else {
            self.flush_stats(false);
            return;
        };
        self.as_mut().rust_mut().stats_flush_scheduled = true;
        let thread = self.qt_thread();
        rt.spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(stats::EMIT_INTERVAL_MS)).await;
            let _ = thread.queue(|q| q.flush_stats(false));
        });
    }

    /// Tells the UI which tabs' counts changed and writes what is due
    /// (everything with `force`); schedules another flush while counts
    /// wait, so the last of them is always told and written.
    fn flush_stats(mut self: Pin<&mut Self>, force: bool) {
        if !force {
            self.as_mut().rust_mut().stats_flush_scheduled = false;
        }
        let changed = self.as_mut().rust_mut().stats.take_changed();
        for tab in changed {
            self.as_mut().page_stats_changed(tab);
        }
        let writes = self.as_mut().rust_mut().stats.take_writes(now_ms(), force);
        if !writes.is_empty() {
            worker::run(move |c| write_counts(c, &writes));
        }
        if !self.stats.is_settled() {
            self.schedule_stats_flush();
        }
    }

    fn content_filter_result(self: Pin<&mut Self>, identifier: &QString, ok: bool) {
        let id = identifier.to_string();
        let thread = self.qt_thread();
        worker::run(move |c| {
            let mut record = FilterRecord::open(&c.dirs.adblock());
            if let Err(e) = record.confirm(&id, ok) {
                log::warn!("content filter {id}: {e}");
            }
            if ok {
                return;
            }
            log::info!("content filter {id} missing from the engine's store: compiling it again");
            if let Some(json) = record.json(&id) {
                let _ = thread.queue(move |q| q.content_filter_compile(qs(&id), qs(&json)));
            }
        });
    }
}

impl cxx_qt::Initialize for qobject::Pacific {
    fn initialize(self: Pin<&mut Self>) {
        worker::init(worker::Dirs::from_env());
        let thread = self.qt_thread();
        worker::run(move |c| {
            let started = start_core(c);
            let t = thread.clone();
            if thread.queue(move |q| q.apply_started(started)).is_err() {
                return;
            }
            // The pages' filters first (from the record on disk), then the
            // engine, which took seconds and kept the first page waiting
            // for its protection.
            let texts = c.lists.enabled_texts();
            let refilter = prepare_filters(c, &texts);
            if t.queue(move |q| apply_refilter(q, refilter)).is_err() {
                return;
            }
            load_engine(c, &texts);
            let _ = t.queue(move |mut q| {
                set_notify!(q, blocker_ready, blocker_ready_changed, true);
            });
        });
        crate::dbus::serve(self.qt_thread());
    }
}

#[allow(
    clippy::unused_self,
    reason = "QML invokables are methods of the singleton, stateless or not"
)]
impl qobject::Pacific {
    fn apply_started(mut self: Pin<&mut Self>, s: Started) {
        let mut https = HttpsFirst::new(s.settings.https_first);
        for h in &s.https_exceptions {
            let _ = https.add_exception(None, h, 0);
        }
        self.as_mut().rust_mut().https = https;
        s.engines
            .clone_into(&mut self.as_mut().rust_mut().engine_cache);
        self.as_mut().rust_mut().downloads_dir = std::path::PathBuf::from(&s.download_dir);
        self.as_mut().rust_mut().settings_cache = s.settings.clone();
        set_notify!(self, settings, settings_changed, qs(&to_json(&s.settings)));
        set_notify!(self, engines, engines_changed, qs(&to_json(&s.engines)));
        set_notify!(
            self,
            default_engine,
            default_engine_changed,
            qs(&s.default_engine)
        );
        set_notify!(self, crashed, crashed_changed, s.crashed);
        set_notify!(
            self,
            saved_session,
            saved_session_changed,
            qs(s.session.as_deref().unwrap_or(""))
        );
        set_notify!(
            self,
            autoconsent_script,
            autoconsent_script_changed,
            qs(s.autoconsent.as_deref().unwrap_or(""))
        );
        set_notify!(
            self,
            download_dir,
            download_dir_changed,
            qs(&s.download_dir)
        );
        set_notify!(
            self,
            profile_error,
            profile_error_changed,
            qs(s.open_error.as_deref().unwrap_or(""))
        );
        set_notify!(self, ready, ready_changed, true);
        let msg = s.open_error.unwrap_or_default();
        self.as_mut().started(msg.is_empty(), qs(&msg));
        // Filter lists due for a refresh: in the background, a minute
        // after start, so start-up has the network to itself.
        let thread = self.qt_thread();
        std::thread::Builder::new()
            .name("pacific-lists-timer".into())
            .spawn(move || {
                std::thread::sleep(std::time::Duration::from_secs(60));
                let _ = thread.queue(|q| q.update_lists(false));
            })
            .map_err(|e| log::warn!("{e}"))
            .ok();
    }

    fn bump(mut self: Pin<&mut Self>) {
        let r = self.revision.wrapping_add(1);
        self.as_mut().rust_mut().revision = r;
        self.as_mut().revision_changed();
    }

    /// Runs `job` on the core thread, then bumps `revision`.
    fn change(
        &self,
        job: impl FnOnce(&mut Core) -> Result<(), pacific_core::Error> + Send + 'static,
    ) {
        let thread = self.qt_thread();
        worker::run(move |c| {
            let r = job(c);
            let _ = thread.queue(move |mut q| {
                if let Err(e) = r {
                    q.as_mut().notice(qs(&e.to_string()));
                }
                q.bump();
            });
        });
    }

    fn engines_for_classify(&self) -> (SearchEngine, Vec<SearchEngine>) {
        let id = self.default_engine.to_string();
        let default = self
            .engine_cache
            .iter()
            .find(|e| e.id == id)
            .or_else(|| self.engine_cache.first())
            .cloned()
            .unwrap_or_else(|| pacific_core::search::builtin_engines().remove(0));
        (default, self.engine_cache.clone())
    }

    fn classify(&self, text: &QString) -> QString {
        let (default, all) = self.engines_for_classify();
        let nav = omnibox::classify(&text.to_string(), &default, &|k| {
            all.iter()
                .find(|e| !e.keyword.is_empty() && e.keyword.eq_ignore_ascii_case(k))
                .cloned()
        });
        qs(&nav.map_or_else(|| "{}".into(), |n| to_json(&n)))
    }

    fn search_url(&self, query: &QString) -> QString {
        let (default, _) = self.engines_for_classify();
        qs(&default.search_url_for(&query.to_string()))
    }

    fn record_selection(&self, input: &QString, url: &QString) {
        let (input, url) = (input.to_string(), url.to_string());
        worker::run(move |c| {
            let _ = c.profile.record_selection(&input, &url);
        });
    }

    fn record_visit(
        &self,
        url: &QString,
        title: &QString,
        transition: &QString,
        private_tab: bool,
    ) {
        let (url, title) = (url.to_string(), title.to_string());
        let t = match transition.to_string().as_str() {
            "typed" => Transition::Typed,
            "bookmark" => Transition::Bookmark,
            "reload" => Transition::Reload,
            "redirect" => Transition::Redirect,
            "restore" => Transition::Restore,
            _ => Transition::Link,
        };
        if private_tab {
            worker::run(move |c| {
                let _ = c.private.record_visit(&url, Some(&title), t, now_ms());
            });
        } else {
            self.change(move |c| {
                c.profile
                    .record_visit(&url, Some(&title), t, now_ms())
                    .map(|_| ())
            });
        }
    }

    fn set_page_title(&self, url: &QString, title: &QString, private_tab: bool) {
        let (url, title) = (url.to_string(), title.to_string());
        if title.trim().is_empty() {
            return;
        }
        worker::run(move |c| {
            let _ = c.profile_for(private_tab).set_title(&url, &title);
        });
    }

    fn set_page_icon(&self, url: &QString, icon: &QString, private_tab: bool) {
        let (url, icon) = (url.to_string(), icon.to_string());
        if private_tab || icon.is_empty() || icon.starts_with("data:") && icon.len() > 64 * 1024 {
            return;
        }
        let thread = self.qt_thread();
        worker::run(move |c| {
            let _ = c.profile.set_icon(&url, &icon);
            let cached = c.dirs.favicon_url(&icon);
            if !cached.is_empty() {
                let _ = thread.queue(move |q| q.icon_cached(qs(&url), qs(&cached)));
                return;
            }
            if !pacific_core::favicons::fetchable(&icon) {
                return;
            }
            let Some(rt) = crate::net::runtime() else {
                return;
            };
            let file = pacific_core::favicons::file_for(&c.dirs.favicons(), &icon);
            rt.spawn(async move {
                let Ok(resp) = crate::net::get(
                    &icon,
                    &[],
                    pacific_core::favicons::MAX_BYTES,
                    std::time::Duration::from_secs(15),
                )
                .await
                else {
                    return;
                };
                if resp.status != 200 || !pacific_core::favicons::looks_like_image(&resp.body) {
                    return;
                }
                if pacific_core::util::write_atomic(&file, &resp.body).is_ok() {
                    let file_url = worker::file_url(&file);
                    let _ = thread.queue(move |mut q| {
                        q.as_mut().icon_cached(qs(&url), qs(&file_url));
                        q.bump();
                    });
                }
            });
        });
    }

    fn site_name(&self, url: &QString) -> QString {
        let host = pacific_core::util::host_of(&url.to_string());
        if host.is_empty() {
            return QString::default();
        }
        qs(&pacific_core::util::site_name(&host))
    }

    fn binary_replaced(&self) -> bool {
        std::fs::read_link("/proc/self/exe")
            .is_ok_and(|p| p.to_string_lossy().ends_with(" (deleted)"))
    }

    fn prestarted(&self) -> bool {
        std::env::var_os("PACIFIC_PRESTART").is_some_and(|v| v == "1")
    }

    fn site_of(&self, url: &QString) -> QString {
        let host = pacific_core::util::host_of(&url.to_string());
        if host.is_empty() {
            return QString::default();
        }
        qs(&pacific_core::util::site_of(&host))
    }

    fn record_search(&self, query: &QString, engine: &QString, private_tab: bool) {
        if private_tab {
            return;
        }
        let (query, engine) = (query.to_string(), engine.to_string());
        worker::run(move |c| {
            let _ = c.profile.record_search(&query, &engine, now_ms());
        });
    }

    fn delete_search(&self, query: &QString) {
        let query = query.to_string();
        worker::run(move |c| {
            let _ = c.profile.delete_search(&query);
        });
    }

    fn delete_history(&self, url: &QString) {
        let url = url.to_string();
        self.change(move |c| c.profile.delete_place(&url));
    }

    fn hide_top_site(&self, url: &QString) {
        let url = url.to_string();
        self.change(move |c| c.profile.hide_top_site(&url));
    }

    fn check_bookmark(&self, url: &QString) {
        let url = url.to_string();
        let thread = self.qt_thread();
        worker::run(move |c| {
            let on = c.profile.is_bookmarked(&url).unwrap_or(false);
            let _ = thread.queue(move |q| q.bookmark_state(qs(&url), on));
        });
    }

    fn toggle_bookmark(&self, url: &QString, title: &QString) {
        let (url, title) = (url.to_string(), title.to_string());
        let thread = self.qt_thread();
        worker::run(move |c| {
            let r = if c.profile.is_bookmarked(&url).unwrap_or(false) {
                c.profile.unbookmark(&url).map(|()| false)
            } else {
                c.profile
                    .add_bookmark(&url, &title, pacific_core::bookmarks::ROOT)
                    .map(|_| true)
            };
            let _ = thread.queue(move |mut q| {
                match r {
                    Ok(on) => q.as_mut().bookmark_state(qs(&url), on),
                    Err(e) => q.as_mut().notice(qs(&e.to_string())),
                }
                q.bump();
            });
        });
    }

    fn add_bookmark(&self, url: &QString, title: &QString, folder: i64) {
        let (url, title) = (url.to_string(), title.to_string());
        self.change(move |c| c.profile.add_bookmark(&url, &title, folder).map(|_| ()));
    }

    fn add_folder(&self, title: &QString, parent: i64) {
        let title = title.to_string();
        self.change(move |c| c.profile.add_folder(&title, parent).map(|_| ()));
    }

    fn edit_bookmark(&self, id: i64, title: &QString, url: &QString, folder: i64) {
        let (title, url) = (title.to_string(), url.to_string());
        self.change(move |c| {
            let url = (!url.is_empty()).then_some(url.as_str());
            c.profile.update_bookmark(id, &title, url)?;
            match c.profile.bookmark(id)? {
                Some(b) if b.parent != folder && folder > 0 => {
                    c.profile.move_bookmark(id, folder, -1)
                }
                _ => Ok(()),
            }
        });
    }

    fn delete_bookmark(&self, id: i64) {
        self.change(move |c| c.profile.delete_bookmark(id));
    }

    fn import_bookmarks(&self, path: &QString) {
        let path = path.to_string();
        let thread = self.qt_thread();
        worker::run(move |c| {
            let msg = match std::fs::read_to_string(&path) {
                Ok(html) => match c.profile.import_bookmarks_html(&html, "Imported") {
                    Ok(n) => format!("{n} bookmarks imported"),
                    Err(e) => e.to_string(),
                },
                Err(e) => format!("{path}: {e}"),
            };
            let _ = thread.queue(move |mut q| {
                q.as_mut().notice(qs(&msg));
                q.bump();
            });
        });
    }

    fn export_bookmarks(&self, path: &QString) {
        let path = path.to_string();
        let thread = self.qt_thread();
        worker::run(move |c| {
            let msg = match c.profile.export_bookmarks_html().and_then(|h| {
                pacific_core::util::write_atomic(std::path::Path::new(&path), h.as_bytes())
            }) {
                Ok(()) => format!("Bookmarks saved to {path}"),
                Err(e) => e.to_string(),
            };
            let _ = thread.queue(move |q| q.notice(qs(&msg)));
        });
    }

    fn set_settings(&self, patch_json: &QString) {
        let Ok(patch) = serde_json::from_str::<Value>(&patch_json.to_string()) else {
            return;
        };
        let thread = self.qt_thread();
        worker::run(move |c| {
            let r = c
                .profile
                .settings()
                .and_then(|s| s.merged(&patch))
                .and_then(|s| c.profile.save_settings(&s).map(|()| s));
            let _ = thread.queue(move |mut q| match r {
                Ok(s) => {
                    let mut https = std::mem::take(&mut q.as_mut().rust_mut().https);
                    https.enabled = s.https_first;
                    q.as_mut().rust_mut().https = https;
                    if !s.download_dir.is_empty() {
                        q.as_mut().rust_mut().downloads_dir =
                            std::path::PathBuf::from(&s.download_dir);
                    }
                    q.as_mut().rust_mut().settings_cache = s.clone();
                    set_notify!(q, settings, settings_changed, qs(&to_json(&s)));
                }
                Err(e) => q.as_mut().notice(qs(&e.to_string())),
            });
        });
    }

    fn reload_engines(&self) {
        let thread = self.qt_thread();
        worker::run(move |c| {
            let all = c.profile.search_engines().unwrap_or_default();
            let def = c.profile.default_engine().map(|e| e.id).unwrap_or_default();
            let _ = thread.queue(move |mut q| {
                all.clone_into(&mut q.as_mut().rust_mut().engine_cache);
                set_notify!(q, engines, engines_changed, qs(&to_json(&all)));
                set_notify!(q, default_engine, default_engine_changed, qs(&def));
            });
        });
    }

    fn set_default_engine(&self, id: &QString) {
        let id = id.to_string();
        worker::run(move |c| {
            let _ = c.profile.set_default_engine(&id);
        });
        self.reload_engines();
    }

    fn add_engine(
        &self,
        name: &QString,
        keyword: &QString,
        url_template: &QString,
        suggest: &QString,
    ) {
        let (name, keyword, template, suggest) = (
            name.to_string(),
            keyword.to_string(),
            url_template.to_string(),
            suggest.to_string(),
        );
        let thread = self.qt_thread();
        worker::run(move |c| {
            let r = c
                .profile
                .add_search_engine(&name, &keyword, &template, &suggest);
            let _ = thread.queue(move |mut q| match r {
                Ok(_) => q.as_mut().engine_added(true, QString::default()),
                Err(e) => q.as_mut().engine_added(false, qs(&e.to_string())),
            });
        });
        self.reload_engines();
    }

    fn remove_engine(&self, id: &QString) {
        let id = id.to_string();
        worker::run(move |c| {
            let _ = c.profile.remove_search_engine(&id);
        });
        self.reload_engines();
    }

    fn load_site_settings(&self, url: &QString, private_tab: bool) {
        let url = url.to_string();
        let thread = self.qt_thread();
        worker::run(move |c| {
            // A private tab's own settings (kept in memory) win; without
            // any it follows the normal profile's (zoom, permissions denied),
            // which it never writes.
            let own = if private_tab {
                c.private.site_settings(&url).ok().filter(|s| !s.is_empty())
            } else {
                None
            };
            let s = own.unwrap_or_else(|| c.profile.site_settings(&url).unwrap_or_default());
            let _ = thread.queue(move |q| q.site_settings_loaded(qs(&url), qs(&to_json(&s))));
        });
    }

    fn set_site_setting(&self, url: &QString, key: &QString, value: &QString, private_tab: bool) {
        let (url, key, value) = (url.to_string(), key.to_string(), value.to_string());
        let thread = self.qt_thread();
        worker::run(move |c| {
            let p = c.profile_for(private_tab);
            let r = p.set_site_setting(&url, &key, &value);
            let s = p.site_settings(&url).unwrap_or_default();
            let blocking = key == "blocking" && !private_tab;
            let refilter = if blocking && r.is_ok() {
                Some(prepare_blocker(c))
            } else {
                None
            };
            let _ = thread.queue(move |mut q| {
                if let Err(e) = r {
                    q.as_mut().notice(qs(&e.to_string()));
                }
                q.as_mut().site_settings_loaded(qs(&url), qs(&to_json(&s)));
                if let Some(refilter) = refilter {
                    apply_refilter(q.as_mut(), refilter);
                }
                q.bump();
            });
        });
    }

    fn clear_site_settings(&self, site: &QString) {
        let site = site.to_string();
        let thread = self.qt_thread();
        worker::run(move |c| {
            // A site whose shields were down has them up again: the filters
            // must be made again without it (they were not, and blocking
            // stayed off there until something else rebuilt them).
            let had_blocking = c
                .profile
                .site_settings(&site)
                .is_ok_and(|s| s.blocking.is_some());
            let r = c.profile.clear_site_settings(&site);
            let refilter = (had_blocking && r.is_ok()).then(|| prepare_blocker(c));
            let _ = thread.queue(move |mut q| {
                if let Err(e) = r {
                    q.as_mut().notice(qs(&e.to_string()));
                }
                if let Some(refilter) = refilter {
                    apply_refilter(q.as_mut(), refilter);
                }
                q.bump();
            });
        });
    }

    fn remove_https_exception(self: Pin<&mut Self>, host: &QString) {
        let host = host.to_string();
        // The GUI side's copy: rebuilt without this host.
        let enabled = self.https.enabled;
        let mut fresh = HttpsFirst::new(enabled);
        let h2 = host.clone();
        let thread = self.qt_thread();
        worker::run(move |c| {
            let _ = c.profile.remove_https_exception(&h2);
            let rest = c.profile.https_exceptions().unwrap_or_default();
            let _ = thread.queue(move |mut q| {
                for h in &rest {
                    let _ = fresh.add_exception(None, h, 0);
                }
                q.as_mut().rust_mut().https = fresh;
                q.bump();
            });
        });
    }

    fn clear_data(&self, range: &QString, what_json: &QString) {
        let range = privacy::Range::parse(&range.to_string()).unwrap_or(privacy::Range::LastHour);
        let what: privacy::What = serde_json::from_str(&what_json.to_string()).unwrap_or_default();
        let thread = self.qt_thread();
        worker::run(move |c| {
            let offset = crate::time::local_utc_offset();
            let r = privacy::clear(&c.profile, Some(&c.sessions), range, what, now_ms(), offset);
            if what.history {
                // The private session's history goes too.
                let _ = privacy::clear(&c.private, None, range, what, now_ms(), offset);
            }
            // Cleared site settings may have put sites' shields back up.
            let refilter = (what.site_settings && r.is_ok()).then(|| prepare_blocker(c));
            let _ = thread.queue(move |mut q| {
                match r {
                    Ok(e) => q.as_mut().data_cleared(qs(&to_json(&e))),
                    Err(e) => q.as_mut().notice(qs(&e.to_string())),
                }
                if let Some(refilter) = refilter {
                    apply_refilter(q.as_mut(), refilter);
                }
                q.bump();
            });
        });
    }

    fn save_session(&self, json: &QString) {
        let json = json.to_string();
        worker::run(
            move |c| match serde_json::from_str::<pacific_core::session::Session>(&json) {
                Ok(s) => {
                    if let Err(e) = c.sessions.save(&s) {
                        log::warn!("session: {e}");
                    }
                }
                Err(e) => log::warn!("session JSON: {e}"),
            },
        );
    }

    fn shutdown(mut self: Pin<&mut Self>) {
        let clear = self.settings_cache.clear_on_exit;
        // Blocked requests not written yet.
        let writes = self.as_mut().rust_mut().stats.take_writes(now_ms(), true);
        let _ = worker::call(move |c| {
            write_counts(c, &writes);
            if clear {
                let all = privacy::What {
                    history: true,
                    cookies: true,
                    cache: true,
                    downloads: true,
                    site_settings: false,
                    session: true,
                };
                let _ = privacy::clear(
                    &c.profile,
                    Some(&c.sessions),
                    privacy::Range::All,
                    all,
                    now_ms(),
                    0,
                );
            }
            let _ = c.sessions.mark_clean_exit();
            let _ = c.profile.checkpoint();
        });
    }

    fn lifecycle(&self, tabs_json: &QString) -> QString {
        #[derive(serde::Deserialize)]
        #[serde(rename_all = "camelCase")]
        #[allow(
            clippy::struct_excessive_bools,
            reason = "the tab's facts as QML gives them"
        )]
        struct T {
            id: i64,
            #[serde(default)]
            last_active: f64,
            #[serde(default)]
            foreground: bool,
            #[serde(default)]
            pinned: bool,
            #[serde(default)]
            audible: bool,
            #[serde(default)]
            form_dirty: bool,
            #[serde(default)]
            live: bool,
        }
        let tabs: Vec<T> = serde_json::from_str(&tabs_json.to_string()).unwrap_or_default();
        let infos: Vec<TabInfo> = tabs
            .into_iter()
            .map(|t| TabInfo {
                id: t.id,
                #[allow(clippy::cast_possible_truncation, reason = "a ms timestamp from QML")]
                last_active: t.last_active as i64,
                foreground: t.foreground,
                pinned: t.pinned,
                audible: t.audible,
                form_dirty: t.form_dirty,
                live: t.live,
            })
            .collect();
        let mem = MemInfo::read().unwrap_or(MemInfo {
            total_kib: 8 << 20,
            available_kib: 4 << 20,
        });
        let budget = usize::try_from(self.tab_budget).unwrap_or(3);
        qs(&to_json(&lifecycle::decide(
            &infos,
            budget,
            mem.pressure(),
            now_ms(),
        )))
    }

    fn https_navigate(mut self: Pin<&mut Self>, tab: i64, url: &QString) -> QString {
        let url = url.to_string();
        let step = self
            .as_mut()
            .rust_mut()
            .https
            .navigate(tab, &url, None, now_ms())
            .unwrap_or(Step::Proceed);
        qs(&to_json(&step))
    }

    fn https_finished(mut self: Pin<&mut Self>, tab: i64, url: &QString) -> bool {
        let done = self
            .as_mut()
            .rust_mut()
            .https
            .load_finished(tab, &url.to_string());
        if done {
            self.as_mut().rust_mut().stats.https_upgraded(tab);
            worker::run(|c| {
                let _ = c
                    .profile
                    .add_protection_count(stats::KIND_HTTPS_UPGRADES, 1, now_ms());
            });
        }
        done
    }

    fn https_failed(mut self: Pin<&mut Self>, tab: i64) -> QString {
        qs(&to_json(&self.as_mut().rust_mut().https.load_failed(tab)))
    }

    fn https_timeout(mut self: Pin<&mut Self>, tab: i64) -> QString {
        qs(&to_json(
            &self.as_mut().rust_mut().https.check_timeout(tab, now_ms()),
        ))
    }

    fn https_pending(&self, tab: i64) -> bool {
        self.https.is_pending(tab)
    }

    fn https_allow(mut self: Pin<&mut Self>, host: &QString, private_tab: bool) {
        let host = host.to_string();
        let _ = self
            .as_mut()
            .rust_mut()
            .https
            .add_exception(None, &host, now_ms());
        if !private_tab {
            worker::run(move |c| {
                let _ = c.profile.add_https_exception(&host, now_ms());
            });
        }
    }

    fn cosmetic(&self, tab: i64, url: &QString) {
        let url = url.to_string();
        let blocking = self.settings_cache.blocking;
        let thread = self.qt_thread();
        worker::run(move |c| {
            let allow = !blocking
                || c.profile
                    .site_settings(&url)
                    .map(|s| s.blocking == Some(false))
                    .unwrap_or(false);
            let cos = c
                .blocker
                .as_ref()
                .map(|b| b.cosmetic(&url, allow))
                .unwrap_or_default();
            let payload = json!({ "exceptions": cos.exceptions, "generichide": cos.generichide, "procedural": cos.procedural });
            let _ = thread.queue(move |q| {
                q.cosmetic_ready(
                    tab,
                    qs(&url),
                    qs(&cos.css),
                    qs(&cos.script),
                    qs(&payload.to_string()),
                );
            });
        });
    }

    fn page_started(mut self: Pin<&mut Self>, tab: i64, url: &QString) {
        self.as_mut().flush_stats(true);
        self.as_mut()
            .rust_mut()
            .stats
            .navigated(tab, &url.to_string());
        self.as_mut().page_stats_changed(tab);
    }

    /// Counted at once; `pageStatsChanged` and the profile's count follow
    /// in batches ([`Self::flush_stats`]).
    fn request_blocked(mut self: Pin<&mut Self>, tab: i64, url: &QString) {
        self.as_mut()
            .rust_mut()
            .stats
            .blocked(tab, &url.to_string());
        self.as_mut().schedule_stats_flush();
    }

    fn consent_report(
        mut self: Pin<&mut Self>,
        tab: i64,
        report: &QString,
        private_tab: bool,
    ) -> bool {
        match autoconsent::parse_report(&report.to_string()) {
            Some(autoconsent::Event::Done { .. }) => {
                // Counted once per page, however many frames report.
                if !self.as_mut().rust_mut().stats.cookie_banner(tab) {
                    return true;
                }
                self.as_mut().page_stats_changed(tab);
                if !private_tab {
                    worker::run(|c| {
                        let _ =
                            c.profile
                                .add_protection_count(stats::KIND_COOKIE_BANNERS, 1, now_ms());
                    });
                }
                true
            }
            _ => false,
        }
    }

    fn page_stats(&self, tab: i64) -> QString {
        qs(&to_json(&self.stats.page(tab)))
    }

    fn tab_closed(mut self: Pin<&mut Self>, tab: i64) {
        self.as_mut().flush_stats(true);
        self.as_mut().rust_mut().stats.closed(tab);
        self.as_mut().rust_mut().https.tab_closed(tab);
    }

    fn load_totals(&self) {
        let thread = self.qt_thread();
        worker::run(move |c| {
            let t = c.profile.protection_totals(0).unwrap_or_default();
            let rules: usize = lists::CATALOGUE
                .iter()
                .filter(|l| c.lists.is_enabled(l.id))
                .map(|l| c.lists.state(l.id).rules)
                .sum();
            let v = json!({ "totals": t, "rules": rules });
            let _ = thread.queue(move |q| q.totals_ready(qs(&v.to_string())));
        });
    }

    fn set_list_enabled(&self, id: &QString, on: bool) {
        let id = id.to_string();
        let thread = self.qt_thread();
        worker::run(move |c| {
            if let Err(e) = c.lists.set_enabled(&id, on) {
                log::warn!("{e}");
            }
            let refilter = prepare_blocker(c);
            let _ = thread.queue(move |mut q| {
                apply_refilter(q.as_mut(), refilter);
                q.bump();
            });
        });
    }

    fn update_lists(mut self: Pin<&mut Self>, force: bool) {
        if self.lists_updating {
            return;
        }
        set_notify!(self, lists_updating, lists_updating_changed, true);
        let thread = self.qt_thread();
        worker::run(move |c| {
            let due = c.lists.due(now_ms(), force);
            let Some(rt) = crate::net::runtime() else {
                let _ = thread
                    .queue(|mut q| set_notify!(q, lists_updating, lists_updating_changed, false));
                return;
            };
            rt.spawn(async move {
                let mut results = Vec::new();
                for f in due {
                    let headers = [
                        ("If-None-Match", f.etag.as_str()),
                        ("If-Modified-Since", f.last_modified.as_str()),
                    ];
                    let r = crate::net::get(
                        f.url,
                        &headers,
                        lists::MAX_LIST_BYTES,
                        std::time::Duration::from_secs(90),
                    )
                    .await;
                    results.push((f.id, r));
                }
                worker::run(move |c| {
                    let mut changed = false;
                    for (id, r) in results {
                        let now = now_ms();
                        let outcome = match r {
                            Ok(resp) if resp.status == 304 => {
                                c.lists.record_unchanged(id, now).map(|()| false)
                            }
                            Ok(resp) if resp.status == 200 => {
                                c.lists
                                    .store(id, &resp.body, &resp.etag, &resp.last_modified, now)
                            }
                            Ok(resp) => c
                                .lists
                                .record_error(id, &format!("HTTP {}", resp.status), now)
                                .map(|()| false),
                            Err(e) => c.lists.record_error(id, &e, now).map(|()| false),
                        };
                        match outcome {
                            Ok(ch) => changed |= ch,
                            Err(e) => {
                                log::warn!("{id}: {e}");
                                let _ = c.lists.record_error(id, &e.to_string(), now);
                            }
                        }
                    }
                    let refilter = changed.then(|| prepare_blocker(c));
                    let _ = thread.queue(move |mut q| {
                        if let Some(refilter) = refilter {
                            apply_refilter(q.as_mut(), refilter);
                        }
                        set_notify!(q, lists_updating, lists_updating_changed, false);
                        q.bump();
                    });
                });
            });
        });
    }

    fn reader(&self, tab: i64, url: &QString, html: &QString, minutes_label: &QString) {
        let (url, html, label) = (url.to_string(), html.to_string(), minutes_label.to_string());
        let s = self.settings_cache.clone();
        let thread = self.qt_thread();
        worker::run(move |c| {
            let out = reader::extract(&html, &url).and_then(|a| {
                let page = reader::render(
                    &a,
                    &url,
                    reader::Theme::parse(&s.reader_theme),
                    s.reader_font_px,
                    s.reader_serif,
                    &label,
                );
                let path = c.dirs.reader().join(format!("tab-{tab}.html"));
                pacific_core::util::write_atomic(&path, page.as_bytes())?;
                Ok((worker::file_url(&path), a))
            });
            let _ = thread.queue(move |q| match out {
                Ok((file, a)) => {
                    let summary = json!({
                        "title": a.title, "byline": a.byline, "siteName": a.site_name,
                        "minutes": a.minutes, "words": a.words, "lang": a.lang, "excerpt": a.excerpt,
                    });
                    q.reader_ready(tab, true, qs(&file), qs(&summary.to_string()));
                }
                Err(e) => q.reader_ready(tab, false, QString::default(), qs(&json!({ "error": e.to_string() }).to_string())),
            });
        });
    }

    fn download_destination(
        &self,
        url: &QString,
        suggested: &QString,
        mime: &QString,
        private_tab: bool,
    ) -> QString {
        let (url, suggested, mime) = (url.to_string(), suggested.to_string(), mime.to_string());
        let dir = self.downloads_dir.clone();
        if let Err(e) = std::fs::create_dir_all(&dir) {
            log::warn!("{}: {e}", dir.display());
        }
        let path = downloads::unique_path(&dir, &downloads::file_name_for(&url, &suggested));
        // Claim the name so a second download at once picks another.
        let _ = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&path);
        let p2 = path.clone();
        self.change(move |c| {
            c.profile_for(private_tab)
                .record_download(&url, &p2, &mime, "")
                .map(|_| ())
        });
        qs(&path.to_string_lossy())
    }

    fn download_update(
        &self,
        path: &QString,
        received: f64,
        total: f64,
        state: &QString,
        error: &QString,
        private_tab: bool,
    ) {
        let (path, error) = (path.to_string(), error.to_string());
        let state = State::parse(&state.to_string()).unwrap_or(State::Running);
        #[allow(
            clippy::cast_possible_truncation,
            reason = "byte counts from QML numbers"
        )]
        let (received, total) = (received as i64, total as i64);
        let finished = state != State::Running;
        let job = move |c: &mut Core| {
            c.profile_for(private_tab)
                .update_download_by_path(&path, received, total, state, &error)
        };
        if finished {
            self.change(job);
        } else {
            worker::run(move |c| {
                let _ = job(c);
            });
        }
    }

    fn remove_download(&self, id: i64, delete_file: bool) {
        self.change(move |c| c.profile.remove_download(id, delete_file));
    }

    fn clear_downloads(&self) {
        self.change(|c| c.profile.clear_finished_downloads().map(|_| ()));
    }

    fn keys_logins(&self, tab: i64, url: &QString) {
        let url = url.to_string();
        let thread = self.qt_thread();
        std::thread::Builder::new()
            .name("pacific-keys".into())
            .spawn(move || {
                let r = passwords::KeysClient::session().and_then(|k| k.logins(&url));
                let _ = thread.queue(move |q| match r {
                    Ok(l) => q.keys_logins_ready(tab, qs(&to_json(&l)), QString::default()),
                    Err(e) => q.keys_logins_ready(tab, qs("[]"), qs(&e.to_string())),
                });
            })
            .map_err(|e| log::warn!("{e}"))
            .ok();
    }

    fn keys_fill(&self, tab: i64, url: &QString, id: &QString) {
        let (url, id) = (url.to_string(), id.to_string());
        let thread = self.qt_thread();
        std::thread::Builder::new()
            .name("pacific-keys".into())
            .spawn(move || {
                let r = passwords::KeysClient::session().and_then(|k| k.fill(&url, &id));
                let _ = thread.queue(move |q| match r {
                    Ok(creds) => {
                        q.keys_fill_ready(tab, qs(&passwords::fill_js(&creds)), QString::default());
                    }
                    Err(e) => q.keys_fill_ready(tab, QString::default(), qs(&e.to_string())),
                });
            })
            .map_err(|e| log::warn!("{e}"))
            .ok();
    }

    fn keys_save(&self, url: &QString, username: &QString, password: &QString) {
        let (url, user, pass) = (url.to_string(), username.to_string(), password.to_string());
        let thread = self.qt_thread();
        std::thread::Builder::new()
            .name("pacific-keys".into())
            .spawn(move || {
                let r = passwords::KeysClient::session().and_then(|k| k.save(&url, &user, &pass));
                let status = r.unwrap_or_else(|e| e.to_string());
                let _ = thread.queue(move |q| q.keys_saved(qs(&status)));
            })
            .map_err(|e| log::warn!("{e}"))
            .ok();
    }

    fn login_detector(&self) -> QString {
        qs(passwords::DETECT_LOGIN_JS)
    }

    fn login_watcher(&self) -> QString {
        qs(passwords::WATCH_SUBMIT_JS)
    }

    fn add_to_home_screen(&self, url: &QString, title: &QString) {
        let (url, title) = (url.to_string(), title.to_string());
        let thread = self.qt_thread();
        worker::run(move |_| {
            let msg = match crate::launcher_entry::write(&url, &title) {
                Ok(()) => format!(
                    "{} added to the home screen",
                    if title.is_empty() { &url } else { &title }
                ),
                Err(e) => e,
            };
            let _ = thread.queue(move |q| q.notice(qs(&msg)));
        });
    }

    fn agent_snapshot(&self, json: &QString, outline_chars: i32) -> QString {
        let max = usize::try_from(outline_chars)
            .unwrap_or(8000)
            .clamp(500, 40_000);
        qs(&match Snapshot::parse(&json.to_string()) {
            Ok(s) => json!({ "ok": true, "outline": s.outline(max), "snapshot": s }).to_string(),
            Err(e) => json!({ "ok": false, "error": e.to_string() }).to_string(),
        })
    }

    fn agent_check_fill(&self, json: &QString, id: &QString) -> QString {
        match Snapshot::parse(&json.to_string()) {
            Ok(s) => s
                .check_fill(&id.to_string())
                .map_or_else(|e| qs(&e.to_string()), |_| QString::default()),
            Err(e) => qs(&e.to_string()),
        }
    }

    fn agent_form_risk(&self, json: &QString, form: &QString) -> QString {
        let risk = Snapshot::parse(&json.to_string())
            .and_then(|s| s.form_risk(&form.to_string()))
            .unwrap_or(agent::Risk::Other);
        qs(to_json(&risk).trim_matches('"'))
    }

    fn untrusted(&self, text: &QString, max: i32) -> QString {
        qs(&agent::untrusted(
            &text.to_string(),
            usize::try_from(max).unwrap_or(0),
        ))
    }

    fn agent_url(&self, url: &QString) -> QString {
        agent::may_navigate(&url.to_string()).map_or_else(|_| QString::default(), |u| qs(&u))
    }

    fn agent_start(mut self: Pin<&mut Self>, tab: i64) {
        self.as_mut().rust_mut().agent_session.start(tab, now_ms());
        let v = qs(&to_json(&self.agent_session));
        set_notify!(self, agent, agent_changed, v);
    }

    fn agent_visited(mut self: Pin<&mut Self>, url: &QString) {
        self.as_mut()
            .rust_mut()
            .agent_session
            .visited(&url.to_string());
        let v = qs(&to_json(&self.agent_session));
        set_notify!(self, agent, agent_changed, v);
    }

    fn agent_stop(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().agent_session.stop();
        let v = qs(&to_json(&self.agent_session));
        set_notify!(self, agent, agent_changed, v);
    }
}

// Keel's launcher: launch_args() and keel_application().
include!("../../../../tools/keel-launcher/launcher.rs");
