//! `Search` (QML `UnifiedSearchService`): the search sheet's results, the
//! apps on the grid and the deep links their manifests declare, and the
//! recent searches (Settings' `search/recent`).

use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::OnceLock;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QStringList, QVariant};
use fuzzy_matcher::skim::SkimMatcherV2;
use fuzzy_matcher::FuzzyMatcher as _;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    unsafe extern "RustQt" {
        #[qobject]
        #[qproperty(QStringList, recent_searches, cxx_name = "recentSearches", READ, NOTIFY)]
        type Search = super::SearchRust;

        /// Results, best first: type ("app", "deeplink"), id, appId, title,
        /// subtitle, icon, data and score.
        #[qinvokable]
        fn search(self: &Search, query: &QString) -> QList_QVariant;
        #[qinvokable]
        #[cxx_name = "addToRecentSearches"]
        fn add_to_recent_searches(self: Pin<&mut Search>, query: &QString);
        #[qinvokable]
        #[cxx_name = "clearRecentSearches"]
        fn clear_recent_searches(self: Pin<&mut Search>);
        #[qinvokable]
        #[cxx_name = "executeSearchResult"]
        fn execute_search_result(self: &Search, result: &QMap_QString_QVariant);
    }

    impl cxx_qt::Threading for Search {}
    impl cxx_qt::Initialize for Search {}
}

use qobject::Search;

type Map = QMap<QMapPair_QString_QVariant>;

const MAX_RECENT: usize = 10;
const RECENT_KEY: &str = "search/recent";

static NATIVE: AtomicBool = AtomicBool::new(true);
static QT: OnceLock<cxx_qt::CxxQtThread<Search>> = OnceLock::new();

#[derive(Default)]
pub struct SearchRust {
    recent_searches: QStringList,
}

struct Item {
    kind: &'static str,
    id: String,
    app_id: String,
    title: String,
    subtitle: String,
    icon: String,
    keywords: Vec<String>,
    text: String,
    data: Vec<(&'static str, String)>,
}

fn items() -> Vec<Item> {
    let native = NATIVE.load(Ordering::Relaxed);
    let mut out = Vec::new();
    for app in crate::apps::all() {
        if app.id.is_empty() || app.name.is_empty() || (app.kind == "native" && !native) {
            continue;
        }
        let name = app.name.to_lowercase();
        let mut keywords = vec![name.clone(), app.id.to_lowercase()];
        keywords.extend(name.split_whitespace().map(str::to_owned));
        keywords.extend(app.search_terms.iter().cloned());
        out.push(Item {
            kind: "app",
            text: format!("{name} {} {}", app.id.to_lowercase(), app.search_terms.join(" ")),
            subtitle: if app.kind == "native" { "Native App" } else { "Marathon App" }.into(),
            data: vec![("id", app.id.clone()), ("name", app.name.clone()), ("icon", app.icon.clone()), ("type", app.kind.clone())],
            id: app.id.clone(),
            app_id: String::new(),
            title: app.name.clone(),
            icon: app.icon.clone(),
            keywords,
        });
        let Some(manifest) = crate::apps::manifest(&app.id) else { continue };
        for (route, link) in &manifest.deep_links {
            let field = |k: &str| link.get(k).and_then(serde_json::Value::as_str).map(str::to_owned);
            let mut keywords: Vec<String> = link.get("keywords").and_then(serde_json::Value::as_array).into_iter().flatten().filter_map(|k| k.as_str().map(str::to_lowercase)).collect();
            keywords.extend([name.clone(), route.to_lowercase()]);
            let title = field("title").unwrap_or_else(|| route.clone());
            out.push(Item {
                kind: "deeplink",
                text: format!("{} {}", title.to_lowercase(), keywords.join(" ")),
                subtitle: field("description").unwrap_or_else(|| app.name.clone()),
                icon: if app.icon.is_empty() { "qrc:/images/app-icon-placeholder.svg".into() } else { app.icon.clone() },
                data: vec![("appId", app.id.clone()), ("route", route.clone()), ("appName", app.name.clone())],
                id: route.clone(),
                app_id: app.id.clone(),
                title,
                keywords,
            });
        }
    }
    out
}

/// The title's exact, prefix or substring match, a keyword's, then a fuzzy
/// match of everything; apps above deep links.
fn score(item: &Item, query: &str, fuzzy: &SkimMatcherV2) -> i64 {
    let title = item.title.to_lowercase();
    let tiers = [
        (title == query, 10_000),
        (title.starts_with(query), 5_000),
        (item.keywords.iter().any(|k| k == query), 3_000),
        (item.keywords.iter().any(|k| k.starts_with(query)), 2_000),
        (title.contains(query), 1_000),
        (item.keywords.iter().any(|k| k.contains(query)), 500),
    ];
    let base = tiers.iter().find(|(hit, _)| *hit).map_or_else(|| fuzzy.fuzzy_match(&item.text, query).unwrap_or(0).min(400), |(_, s)| *s);
    if base > 0 && item.kind == "app" { base + 100 } else { base }
}

fn text(s: &str) -> QVariant {
    QVariant::from(&QString::from(s))
}

fn strings(items: &[String]) -> QStringList {
    let mut list = QList::<QString>::default();
    for s in items {
        list.append(QString::from(s));
    }
    QStringList::from(&list)
}

impl cxx_qt::Initialize for Search {
    fn initialize(self: Pin<&mut Self>) {
        QT.set(self.qt_thread()).ok();
        crate::settings::with(|mut s| {
            NATIVE.store(*s.search_native_apps(), Ordering::Relaxed);
            s.as_mut().on_search_native_apps_changed(|s| NATIVE.store(*s.search_native_apps(), Ordering::Relaxed)).release();
            let saved = s.get(&QString::from(RECENT_KEY), &QVariant::default());
            let recent = saved.value::<QStringList>().unwrap_or_default();
            if let Some(qt) = QT.get() {
                qt.queue(move |mut obj| {
                    obj.as_mut().rust_mut().recent_searches = recent;
                    obj.recent_searches_changed();
                })
                .ok();
            }
        });
    }
}

impl Search {
    #[allow(clippy::unused_self, reason = "a QML invokable")]
    fn search(&self, query: &QString) -> QList<QVariant> {
        let query = query.to_string().trim().to_lowercase();
        let mut out = QList::<QVariant>::default();
        if query.is_empty() {
            return out;
        }
        let fuzzy = SkimMatcherV2::default();
        let mut ranked: Vec<(i64, Item)> = items().into_iter().map(|i| (score(&i, &query, &fuzzy), i)).filter(|(s, _)| *s > 0).collect();
        ranked.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.title.cmp(&b.1.title)));
        for (score, item) in ranked {
            let mut data = Map::default();
            for (k, v) in &item.data {
                data.insert(QString::from(*k), text(v));
            }
            let mut m = Map::default();
            for (k, v) in [("type", item.kind), ("id", &item.id), ("appId", &item.app_id), ("title", &item.title), ("subtitle", &item.subtitle), ("icon", &item.icon)] {
                m.insert(QString::from(k), text(v));
            }
            m.insert(QString::from("keywords"), QVariant::from(&strings(&item.keywords)));
            m.insert(QString::from("data"), QVariant::from(&data));
            m.insert(QString::from("score"), QVariant::from(&i32::try_from(score).unwrap_or(i32::MAX)));
            out.append(QVariant::from(&m));
        }
        out
    }

    fn set_recent(mut self: Pin<&mut Self>, recent: &[String]) {
        let list = strings(recent);
        self.as_mut().rust_mut().recent_searches = list.clone();
        self.recent_searches_changed();
        crate::settings::with(move |s| s.set(&QString::from(RECENT_KEY), &QVariant::from(&list)));
    }

    fn add_to_recent_searches(self: Pin<&mut Self>, query: &QString) {
        let query = query.to_string().trim().to_owned();
        if query.is_empty() {
            return;
        }
        let mut recent: Vec<String> = QList::<QString>::from(&self.recent_searches).iter().map(ToString::to_string).filter(|r| *r != query).collect();
        recent.insert(0, query);
        recent.truncate(MAX_RECENT);
        self.set_recent(&recent);
    }

    fn clear_recent_searches(self: Pin<&mut Self>) {
        if !QList::<QString>::from(&self.recent_searches).is_empty() {
            self.set_recent(&[]);
        }
    }

    #[allow(clippy::unused_self, reason = "a QML invokable")]
    fn execute_search_result(&self, result: &Map) {
        let get = |m: &Map, k: &str| m.get(&QString::from(k)).and_then(|v| v.value::<QString>()).map(|s| s.to_string()).unwrap_or_default();
        let data = result.get(&QString::from("data")).and_then(|v| v.value::<Map>()).unwrap_or_default();
        match get(result, "type").as_str() {
            "app" => {
                let id = get(&data, "id");
                crate::tasks::with(move |t| {
                    t.launch_app(&QString::from(&id));
                });
            }
            "deeplink" => crate::links::deep_link(get(&data, "appId"), get(&data, "route"), Map::default()),
            "setting" => crate::links::deep_link("settings".into(), get(result, "id"), Map::default()),
            _ => {}
        }
    }
}
