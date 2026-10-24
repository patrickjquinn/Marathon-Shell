//! `Notifications`: the shell's org.freedesktop.Notifications server, its
//! history (SQLite, kept across restarts) and the Hub's list model (QML
//! `NotificationService`). A tap opens the app; an action button tells the
//! sender, and runs the D-Bus call a Nemo.Notifications sender attached.

use std::collections::HashMap;
use std::path::PathBuf;
use std::pin::Pin;
use std::sync::OnceLock;
use std::time::Duration;

use base64::Engine as _;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{
    QByteArray, QHash, QHashPair_i32_QByteArray, QList, QMap, QMapPair_QString_QVariant,
    QModelIndex, QString, QVariant,
};
use futures_lite::StreamExt as _;
use serde_json::{json, Value as Json};
use zbus::fdo;
use zbus::message::Header;
use zbus::zvariant::{OwnedValue, StructureBuilder, Value};

use crate::{
    apps, audio, clock, gate, haptics, io, ipc, log, modem, power, settings, tasks, variant,
};

pub use proxy::NotificationsProxy;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!(<QtCore/QAbstractListModel>);
        type QAbstractListModel;
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
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
        #[qproperty(i32, unread_count, cxx_name = "unreadCount", READ, NOTIFY)]
        #[qproperty(bool, is_dnd_enabled, cxx_name = "isDndEnabled", READ, NOTIFY)]
        /// Every notification as a map, newest first.
        #[qproperty(QList_QVariant, notifications, READ, NOTIFY)]
        type Notifications = super::NotificationsRust;

        #[inherit]
        #[cxx_name = "beginResetModel"]
        fn begin_reset_model(self: Pin<&mut Notifications>);
        #[inherit]
        #[cxx_name = "endResetModel"]
        fn end_reset_model(self: Pin<&mut Notifications>);
        #[cxx_override]
        #[cxx_name = "rowCount"]
        fn row_count(self: &Notifications, parent: &QModelIndex) -> i32;
        #[cxx_override]
        fn data(self: &Notifications, index: &QModelIndex, role: i32) -> QVariant;
        #[cxx_override]
        #[cxx_name = "roleNames"]
        fn role_names(self: &Notifications) -> QHash_i32_QByteArray;

        /// The shell's own: options carry icon, category, actions and a
        /// message's replyTarget. Nothing for an app the person silenced.
        #[qinvokable]
        #[cxx_name = "sendNotification"]
        fn send_notification(
            self: &Notifications,
            app_id: &QString,
            title: &QString,
            body: &QString,
            options: &QMap_QString_QVariant,
        );
        /// At once, with no settings check (the validation harness's seed).
        #[qinvokable]
        #[cxx_name = "addNotification"]
        fn add_notification(
            self: Pin<&mut Notifications>,
            app_id: &QString,
            title: &QString,
            body: &QString,
            icon: &QString,
        );
        #[qinvokable]
        #[cxx_name = "dismissNotification"]
        fn dismiss_notification(self: Pin<&mut Notifications>, id: i32);
        /// Every one but the ongoing.
        #[qinvokable]
        #[cxx_name = "dismissAllNotifications"]
        fn dismiss_all_notifications(self: Pin<&mut Notifications>);
        #[qinvokable]
        #[cxx_name = "markAsRead"]
        fn mark_as_read(self: Pin<&mut Notifications>, id: i32);
        /// A tap: the app opens, at what it was about.
        #[qinvokable]
        #[cxx_name = "clickNotification"]
        fn click_notification(self: Pin<&mut Notifications>, id: i32);
        #[qinvokable]
        #[cxx_name = "triggerAction"]
        fn trigger_action(self: Pin<&mut Notifications>, id: i32, action: &QString);
        /// The text typed into a notification's Reply.
        #[qinvokable]
        fn reply(self: Pin<&mut Notifications>, id: i32, text: &QString);
        /// Empty for none.
        #[qinvokable]
        #[cxx_name = "getNotification"]
        fn get_notification(self: &Notifications, id: i32) -> QMap_QString_QVariant;
        /// Unread, from that app.
        #[qinvokable]
        #[cxx_name = "getNotificationCountForApp"]
        fn get_notification_count_for_app(self: &Notifications, app_id: &QString) -> i32;
        /// Each app once, newest first: { appId, unread }.
        #[qinvokable]
        fn sources(self: &Notifications) -> QList_QVariant;
        #[qinvokable]
        #[cxx_name = "roleId"]
        fn role_id(self: &Notifications, name: &QString) -> i32;
        #[cxx_name = "setDndEnabled"]
        fn set_dnd_enabled(self: Pin<&mut Notifications>, enabled: bool);

        /// A banner: a new notification, or a transient one shown only so.
        #[qsignal]
        #[cxx_name = "notificationReceived"]
        fn notification_received(
            self: Pin<&mut Notifications>,
            notification: &QMap_QString_QVariant,
        );
        #[qsignal]
        #[cxx_name = "notificationDismissed"]
        fn notification_dismissed(self: Pin<&mut Notifications>, id: i32);
        /// An app's toast (x-marathon-toast), shown at the bottom.
        #[qsignal]
        #[cxx_name = "toastRequested"]
        fn toast_requested(self: Pin<&mut Notifications>, notification: &QMap_QString_QVariant);
        /// A message's reply, for the phone to send.
        #[qsignal]
        fn replied(self: Pin<&mut Notifications>, id: i32, text: &QString);
    }

    impl cxx_qt::Threading for Notifications {}
    impl cxx_qt::Initialize for Notifications {}
}

use qobject::Notifications;

type Qt = cxx_qt::CxxQtThread<Notifications>;
type Map = QMap<QMapPair_QString_QVariant>;

const PATH: &str = "/org/freedesktop/Notifications";
const NAME: &str = "org.freedesktop.Notifications";
/// NAME's own connection, so a sender's image-data never stalls the shell's.
static SERVER_BUS: OnceLock<zbus::Connection> = OnceLock::new();
/// The Hub's history, bounded.
const KEEP: i64 = 500;
const ROLES: [&str; 12] = [
    "id",
    "appId",
    "title",
    "body",
    "icon",
    "timestamp",
    "isRead",
    "actions",
    "actionIcons",
    "ongoing",
    "progress",
    "day",
];
const USER_ROLE: i32 = 0x0100;
/// Transient notifications have ids no stored row reaches.
const TRANSIENT: u32 = 1 << 31;

static QT: OnceLock<Qt> = OnceLock::new();

/// Runs `f` on the notifications, on the GUI thread.
pub(crate) fn with(f: impl FnOnce(Pin<&mut Notifications>) + Send + 'static) {
    if let Some(qt) = QT.get() {
        qt.queue(f).ok();
    }
}

#[derive(Clone, Debug, Default)]
struct Row {
    id: i64,
    app_id: String,
    title: String,
    body: String,
    icon: String,
    timestamp_ms: i64,
    read: bool,
    /// `{key, label}` each.
    actions: Json,
    /// The freedesktop hints, and the shell's own (replyTarget, priority).
    hints: serde_json::Map<String, Json>,
}

impl Row {
    fn hint(&self, key: &str) -> &Json {
        self.hints.get(key).unwrap_or(&Json::Null)
    }

    /// Progress: the de facto "value" hint.
    fn ongoing(&self) -> bool {
        self.hints.contains_key("value")
    }

    /// 0..1, or -1 while unknown.
    fn progress(&self) -> f64 {
        self.hint("value")
            .as_f64()
            .filter(|v| *v >= 0.0)
            .map_or(-1.0, |v| v.min(100.0) / 100.0)
    }

    fn to_json(&self) -> Json {
        json!({
            "id": self.id, "appId": self.app_id, "title": self.title, "body": self.body,
            "icon": self.icon, "timestamp": self.timestamp_ms, "read": self.read,
            "actions": self.actions,
            "replyPlaceholder": self.hint("x-kde-reply-placeholder-text").as_str().unwrap_or_default(),
            "category": self.hint("category").as_str().unwrap_or("message"),
            "actionIcons": self.hint("action-icons").as_bool().unwrap_or(false),
            "urgency": self.hint("urgency").as_i64().unwrap_or(1),
            "ongoing": self.ongoing(), "progress": self.progress(),
            "priority": self.hint("priority").as_str().unwrap_or("normal"),
            "persistent": self.hint("persistent").as_bool().unwrap_or(false),
            "replyTarget": self.hint("replyTarget").as_str().unwrap_or_default(),
        })
    }
}

#[derive(Default)]
pub struct NotificationsRust {
    count: i32,
    unread_count: i32,
    is_dnd_enabled: bool,
    notifications: QList<QVariant>,
    rows: Vec<Row>,
    store: Option<rusqlite::Connection>,
    next_transient: u32,
    /// The bus name that posted each ongoing notification.
    senders: HashMap<i64, String>,
}

impl cxx_qt::Initialize for Notifications {
    fn initialize(mut self: Pin<&mut Self>) {
        QT.set(self.qt_thread()).ok();
        let store = open_store()
            .map_err(|e| log::warn("notifications", format_args!("no history: {e}")))
            .ok();
        let rows = store.as_ref().map(load).unwrap_or_default();
        let mut rust = self.as_mut().rust_mut();
        rust.store = store;
        rust.next_transient = TRANSIENT;
        self.as_mut().set_rows(rows);
        serve(self.qt_thread());
    }
}

fn store_path() -> PathBuf {
    marathon_rt::dirs::data().join("Marathon OS/Marathon Shell/notifications.db")
}

fn open_store() -> rusqlite::Result<rusqlite::Connection> {
    let path = store_path();
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).ok();
    }
    let db = rusqlite::Connection::open(path)?;
    // Written on the GUI thread: WAL commits without an fsync.
    db.execute_batch(
        "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;
         CREATE TABLE IF NOT EXISTS notifications (id INTEGER PRIMARY KEY AUTOINCREMENT, app_id TEXT NOT NULL,
             title TEXT, body TEXT, icon TEXT, timestamp INTEGER, read INTEGER DEFAULT 0, dismissed INTEGER DEFAULT 0,
             category TEXT, priority INTEGER, actions TEXT, metadata TEXT);
         CREATE INDEX IF NOT EXISTS idx_timestamp ON notifications(timestamp DESC);",
    )?;
    Ok(db)
}

/// Moves Android apps' notifications from the `from` prefix to `to`.
///
/// # Errors
/// The history cannot be opened or written.
pub fn rename_app_ids(from: &str, to: &str) -> rusqlite::Result<()> {
    if !store_path().exists() {
        return Ok(());
    }
    let length = i64::try_from(from.len()).unwrap_or(i64::MAX);
    open_store()?.execute(
        "UPDATE notifications SET app_id = ?2 || substr(app_id, ?3 + 1) WHERE substr(app_id, 1, ?3) = ?1",
        rusqlite::params![from, to, length],
    )?;
    Ok(())
}

/// The kept history; progress belongs to a sender of the last session.
fn load(db: &rusqlite::Connection) -> Vec<Row> {
    db.execute("UPDATE notifications SET dismissed = 1 WHERE dismissed = 0 AND metadata LIKE '%\"value\":%'", []).ok();
    // Older Store helpers surfaced Flatpak runtime maintenance as unread app
    // updates. Remove those legacy rows without touching actual app notices.
    db.execute(
        "UPDATE notifications SET dismissed = 1
         WHERE dismissed = 0 AND app_id = 'store' AND body = ''
         AND title GLOB 'org.*.Platform* updated'",
        [],
    )
    .ok();
    let query = || -> rusqlite::Result<Vec<Row>> {
        let mut select = db.prepare("SELECT id, app_id, title, body, icon, timestamp, read, actions, metadata FROM notifications WHERE dismissed = 0 ORDER BY timestamp DESC, id DESC LIMIT ?1")?;
        let rows = select.query_map([KEEP], |r| {
            let text = |i: usize| r.get::<_, Option<String>>(i).map(Option::unwrap_or_default);
            let json = |s: String| serde_json::from_str::<Json>(&s).unwrap_or(Json::Null);
            Ok(Row {
                id: r.get(0)?,
                app_id: text(1)?,
                title: text(2)?,
                body: text(3)?,
                icon: text(4)?,
                timestamp_ms: r.get::<_, Option<i64>>(5)?.unwrap_or_default() * 1000,
                read: r.get::<_, Option<i64>>(6)?.unwrap_or_default() == 1,
                actions: json(text(7)?),
                hints: json(text(8)?).as_object().cloned().unwrap_or_default(),
            })
        })?;
        rows.collect()
    };
    query().unwrap_or_else(|e| {
        log::warn("notifications", format_args!("history: {e}"));
        Vec::new()
    })
}

fn q(s: &str) -> QString {
    QString::from(s)
}

/// A D-Bus value as JSON, for the store and QML.
fn to_json(value: &Value<'_>) -> Json {
    match value {
        Value::Bool(b) => Json::Bool(*b),
        Value::Str(s) => Json::String(s.to_string()),
        Value::ObjectPath(p) => Json::String(p.to_string()),
        Value::F64(f) => json!(f),
        Value::Value(inner) => to_json(inner),
        Value::Array(a) => Json::Array(a.iter().map(to_json).collect()),
        Value::Dict(d) => Json::Object(
            d.iter()
                .filter_map(|(k, v)| {
                    if let Value::Str(k) = k {
                        Some((k.to_string(), to_json(v)))
                    } else {
                        None
                    }
                })
                .collect(),
        ),
        other => variant::number(other).map_or(Json::Null, |n| json!(n)),
    }
}

/// image-data's (iiibiiay) as a PNG data URL, at most 128 px, so the Hub
/// keeps its pixels across restarts.
fn image_url(hint: &Value<'_>) -> Option<String> {
    let Value::Structure(s) = hint else {
        return None;
    };
    let f = s.fields();
    let int = |i: usize| {
        f.get(i)
            .and_then(variant::number)
            .and_then(|n| u32::try_from(n).ok())
    };
    let (width, height, stride, channels) = (int(0)?, int(1)?, int(2)?, int(5)?);
    let alpha = matches!(f.get(3), Some(Value::Bool(true)));
    let Some(Value::Array(a)) = f.get(6) else {
        return None;
    };
    let bytes: Vec<u8> = a
        .iter()
        .filter_map(|b| if let Value::U8(b) = b { Some(*b) } else { None })
        .collect();
    if int(4)? != 8 || channels != if alpha { 4 } else { 3 } || stride < width * channels {
        return None;
    }
    let line = usize::try_from(width * channels).ok()?;
    let mut packed = Vec::with_capacity(line * usize::try_from(height).ok()?);
    for row in 0..usize::try_from(height).ok()? {
        let start = row * usize::try_from(stride).ok()?;
        packed.extend_from_slice(bytes.get(start..start + line)?);
    }
    let image = if alpha {
        image::DynamicImage::ImageRgba8(image::RgbaImage::from_raw(width, height, packed)?)
    } else {
        image::DynamicImage::ImageRgb8(image::RgbImage::from_raw(width, height, packed)?)
    };
    let image = if width > 128 || height > 128 {
        image.thumbnail(128, 128)
    } else {
        image
    };
    let mut png = std::io::Cursor::new(Vec::new());
    image.write_to(&mut png, image::ImageFormat::Png).ok()?;
    Some(format!(
        "data:image/png;base64,{}",
        base64::engine::general_purpose::STANDARD.encode(png.into_inner())
    ))
}

/// The app a process runs as, from its cgroup: Marathon's marathon-app-<id>,
/// Flatpak's app-flatpak-<id>-<n>.scope, or systemd's app-[<launcher>-]<id>
/// units (systemd.unit(5), "Desktop Environment Integration").
fn app_from_cgroup(cgroup: &str) -> Option<String> {
    let unit = cgroup.rsplit('/').next()?;
    let scope = std::path::Path::new(unit)
        .extension()
        .is_some_and(|e| e == "scope");
    let name = unit
        .trim_end_matches(".scope")
        .trim_end_matches(".service")
        .replace("\\x2d", "-");
    if let Some(id) = name.strip_prefix("marathon-app-") {
        return Some(id.to_owned());
    }
    if let Some(rest) = name.strip_prefix("app-flatpak-") {
        return Some(
            rest.rsplit_once('-')
                .filter(|(_, n)| n.chars().all(|c| c.is_ascii_digit()))
                .map_or(rest, |(id, _)| id)
                .to_owned(),
        );
    }
    let rest = name.strip_prefix("app-")?;
    let rest = if scope {
        rest.rsplit_once('-')?.0
    } else {
        rest.split('@').next()?
    };
    // A launcher's name has no dot; an application id does.
    Some(match rest.split_once('-') {
        Some((launcher, id)) if !launcher.contains('.') && id.contains('.') => id.to_owned(),
        _ => rest.to_owned(),
    })
}

fn app_of_pid(pid: u32) -> Option<String> {
    gate::resolve(pid)
        .filter(|a| !a.starts_with("service:"))
        .or_else(|| {
            let cgroups = std::fs::read_to_string(format!("/proc/{pid}/cgroup")).ok()?;
            app_from_cgroup(cgroups.lines().find_map(|l| l.strip_prefix("0::"))?)
        })
}

/// The installed app the first candidate names, by id or by name.
fn installed(candidates: &[&str]) -> Option<String> {
    let all = apps::all();
    candidates
        .iter()
        .map(|c| c.trim().trim_end_matches(".desktop"))
        .filter(|c| !c.is_empty())
        .find_map(|c| {
            apps::get(c).map(|a| a.id).or_else(|| {
                all.iter()
                    .find(|a| a.id.eq_ignore_ascii_case(c) || a.name.eq_ignore_ascii_case(c))
                    .map(|a| a.id.clone())
            })
        })
}

/// Which app a notification is from: its desktop entry or the sender's own
/// scope when either is installed, else the name the sender gave.
fn app_of(provided: &str, entry: &str, sender_app: Option<&str>) -> String {
    let entry = entry.trim_end_matches(".desktop");
    installed(&[entry, sender_app.unwrap_or_default(), provided])
        .or_else(|| (!provided.is_empty()).then(|| provided.to_owned()))
        .or_else(|| (!entry.is_empty()).then(|| entry.to_owned()))
        .unwrap_or_else(|| "unknown".to_owned())
}

/// What the D-Bus side hands the GUI thread.
struct Incoming {
    app_id: String,
    replaces_id: u32,
    icon: String,
    summary: String,
    body: String,
    actions: Vec<(String, String)>,
    hints: serde_json::Map<String, Json>,
    expire_timeout: i32,
    sender: String,
    /// In the history, across restarts.
    keep: bool,
}

impl Notifications {
    fn row_count(&self, parent: &QModelIndex) -> i32 {
        if parent.is_valid() {
            0
        } else {
            self.count
        }
    }

    fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
        let Some(row) = usize::try_from(index.row())
            .ok()
            .and_then(|i| self.rows.get(i))
        else {
            return QVariant::default();
        };
        let text = |s: &str| QVariant::from(&q(s));
        match role - USER_ROLE - 1 {
            0 => QVariant::from(&i32::try_from(row.id).unwrap_or_default()),
            1 => text(&row.app_id),
            2 => text(&row.title),
            3 => text(&row.body),
            4 => text(&row.icon),
            5 => QVariant::from(&row.timestamp_ms),
            6 => QVariant::from(&row.read),
            7 => variant::from_json(&row.actions),
            8 => QVariant::from(&row.hint("action-icons").as_bool().unwrap_or(false)),
            9 => QVariant::from(&row.ongoing()),
            10 => QVariant::from(&row.progress()),
            11 => text(
                &clock::local(row.timestamp_ms / 1000)
                    .map(|t| {
                        format!(
                            "{:04}-{:02}-{:02}",
                            t.tm_year + 1900,
                            t.tm_mon + 1,
                            t.tm_mday
                        )
                    })
                    .unwrap_or_default(),
            ),
            _ => QVariant::default(),
        }
    }

    #[allow(clippy::unused_self, reason = "a QAbstractListModel override")]
    fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut roles = QHash::<QHashPair_i32_QByteArray>::default();
        for (role, name) in (USER_ROLE + 1..).zip(ROLES) {
            roles.insert(role, QByteArray::from(name));
        }
        roles
    }

    #[allow(clippy::unused_self, reason = "a QML invokable")]
    fn role_id(&self, name: &QString) -> i32 {
        let name = name.to_string();
        (USER_ROLE + 1..)
            .zip(ROLES)
            .find(|(_, n)| *n == name)
            .map_or(-1, |(r, _)| r)
    }

    /// The list changes as a whole: the Hub holds a few hundred at most.
    fn set_rows(mut self: Pin<&mut Self>, mut rows: Vec<Row>) {
        rows.truncate(usize::try_from(KEEP).unwrap_or_default());
        let unread = i32::try_from(rows.iter().filter(|r| !r.read).count()).unwrap_or(i32::MAX);
        let count = i32::try_from(rows.len()).unwrap_or(i32::MAX);
        let mut list = QList::<QVariant>::default();
        for row in &rows {
            list.append(QVariant::from(&variant::map(&row.to_json())));
        }
        self.as_mut().begin_reset_model();
        let mut rust = self.as_mut().rust_mut();
        rust.rows = rows;
        rust.count = count;
        rust.notifications = list;
        self.as_mut().end_reset_model();
        self.as_mut().count_changed();
        self.as_mut().notifications_changed();
        if self.unread_count != unread {
            self.as_mut().rust_mut().unread_count = unread;
            self.unread_count_changed();
        }
    }

    fn row(&self, id: i32) -> Option<&Row> {
        self.rows.iter().find(|r| r.id == i64::from(id))
    }

    fn get_notification(&self, id: i32) -> Map {
        self.row(id)
            .map(|r| variant::map(&r.to_json()))
            .unwrap_or_default()
    }

    fn get_notification_count_for_app(&self, app_id: &QString) -> i32 {
        let app = app_id.to_string();
        i32::try_from(
            self.rows
                .iter()
                .filter(|r| r.app_id == app && !r.read)
                .count(),
        )
        .unwrap_or(i32::MAX)
    }

    fn sources(&self) -> QList<QVariant> {
        let mut order: Vec<(&str, i32)> = Vec::new();
        for row in &self.rows {
            match order.iter_mut().find(|(a, _)| *a == row.app_id) {
                Some((_, unread)) => *unread += i32::from(!row.read),
                None => order.push((&row.app_id, i32::from(!row.read))),
            }
        }
        let mut list = QList::<QVariant>::default();
        for (app, unread) in order {
            list.append(QVariant::from(&variant::map(
                &json!({"appId": app, "unread": unread}),
            )));
        }
        list
    }

    fn set_dnd_enabled(mut self: Pin<&mut Self>, enabled: bool) {
        if self.is_dnd_enabled != enabled {
            self.as_mut().rust_mut().is_dnd_enabled = enabled;
            self.is_dnd_enabled_changed();
        }
    }

    #[allow(clippy::unused_self, reason = "a QML invokable")]
    fn send_notification(&self, app_id: &QString, title: &QString, body: &QString, options: &Map) {
        let app = if app_id.is_empty() {
            "system".to_owned()
        } else {
            app_id.to_string()
        };
        let mut hints: serde_json::Map<String, Json> = marathon_qt::map(options)
            .iter()
            .map(|(k, v)| (k.clone(), to_json(v)))
            .collect();
        let (title, body) = (title.to_string(), body.to_string());
        settings::with(move |s| {
            if !s.is_notifications_enabled_for_app(&q(&app)) {
                return;
            }
            with(move |n| {
                let icon = hints
                    .remove("icon")
                    .and_then(|i| i.as_str().map(str::to_owned))
                    .unwrap_or_default();
                let actions = hints.remove("actions").unwrap_or_default();
                let actions = actions
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter_map(|a| {
                        Some((
                            a["key"].as_str()?.to_owned(),
                            a["label"].as_str().unwrap_or_default().to_owned(),
                        ))
                    })
                    .collect();
                n.receive(Incoming {
                    app_id: app,
                    replaces_id: 0,
                    icon,
                    summary: title,
                    body,
                    actions,
                    hints,
                    expire_timeout: -1,
                    sender: String::new(),
                    keep: true,
                });
            });
        });
    }

    fn add_notification(
        self: Pin<&mut Self>,
        app_id: &QString,
        title: &QString,
        body: &QString,
        icon: &QString,
    ) {
        let incoming = Incoming {
            app_id: app_id.to_string(),
            replaces_id: 0,
            icon: icon.to_string(),
            summary: title.to_string(),
            body: body.to_string(),
            actions: Vec::new(),
            hints: serde_json::Map::new(),
            expire_timeout: -1,
            sender: String::new(),
            keep: false,
        };
        self.receive(incoming);
    }

    fn next_transient(mut self: Pin<&mut Self>) -> u32 {
        let id = self.next_transient;
        self.as_mut().rust_mut().next_transient = id.wrapping_add(1).max(TRANSIENT);
        id
    }

    /// One notification, from the bus or the shell: a banner, a toast, a
    /// progress update in place, or a new stored row.
    #[allow(
        clippy::too_many_lines,
        reason = "notification normalization and replacement must remain one atomic state update"
    )]
    fn receive(mut self: Pin<&mut Self>, n: Incoming) -> u32 {
        let actions = Json::Array(
            n.actions
                .iter()
                .map(|(k, l)| json!({"key": k, "label": l}))
                .collect(),
        );
        let ongoing = n.hints.contains_key("value");
        // Progress moves the row it replaces, without a new banner or sound.
        if ongoing && n.replaces_id > 0 {
            if let Some(at) = self
                .rows
                .iter()
                .position(|r| r.id == i64::from(n.replaces_id) && r.ongoing())
            {
                let mut rows = self.rows.clone();
                let row = &mut rows[at];
                (row.title, row.body, row.icon, row.actions, row.hints) =
                    (n.summary, n.body, n.icon, actions, n.hints);
                self.as_mut().set_rows(rows);
                return n.replaces_id;
            }
        }
        let flag = |key: &str| n.hints.get(key).and_then(Json::as_bool).unwrap_or(false);
        let toast = flag("x-marathon-toast");
        // Transient: shown, then gone, with no record or sound.
        if toast || flag("transient") {
            let id = self.as_mut().next_transient();
            let shown = variant::map(
                &json!({"id": id, "appId": n.app_id, "title": n.summary, "body": n.body, "icon": n.icon,
                "actions": actions, "actionIcons": flag("action-icons")}),
            );
            if toast {
                self.as_mut().toast_requested(&shown);
            } else {
                self.as_mut().notification_received(&shown);
            }
            let after = Duration::from_millis(
                u64::try_from(n.expire_timeout)
                    .ok()
                    .filter(|t| *t > 0)
                    .unwrap_or(5000),
            );
            io::spawn(async move {
                async_io::Timer::after(after).await;
                emit("NotificationClosed", (id, 1u32));
            });
            return id;
        }
        if n.replaces_id > 0 {
            self.as_mut().dismiss(i64::from(n.replaces_id), None);
        }
        // An urgent one keeps the phone awake while it is seen.
        if n.hints.get("urgency").and_then(Json::as_i64).unwrap_or(1) >= 2 {
            power::hold_wakelock("notification", Duration::from_secs(5));
        }
        let now = clock::now();
        let mut hints = n.hints;
        hints.insert("expire_timeout".into(), json!(n.expire_timeout));
        let category = hints
            .get("category")
            .and_then(Json::as_str)
            .unwrap_or("general")
            .to_owned();
        let priority = match hints.get("urgency").and_then(Json::as_i64) {
            Some(0) => 0,
            Some(2) => 3,
            _ => 1,
        };
        let stored = self.store.as_ref().filter(|_| n.keep).and_then(|db| {
            db.execute(
                "INSERT INTO notifications (app_id, title, body, icon, timestamp, read, dismissed, category, priority, actions, metadata) VALUES (?1, ?2, ?3, ?4, ?5, 0, 0, ?6, ?7, ?8, ?9)",
                rusqlite::params![n.app_id, n.summary, n.body, n.icon, now, category, priority, actions.to_string(), Json::Object(hints.clone()).to_string()],
            )
            .map_err(|e| log::warn("notifications", format_args!("not kept: {e}")))
            .ok()?;
            let id = db.last_insert_rowid();
            db.execute("DELETE FROM notifications WHERE id NOT IN (SELECT id FROM notifications ORDER BY id DESC LIMIT ?1)", [KEEP]).ok();
            Some(id)
        });
        let id = match stored {
            Some(id) => id,
            None => i64::from(self.as_mut().next_transient()),
        };
        if ongoing && !n.sender.is_empty() {
            self.as_mut().rust_mut().senders.insert(id, n.sender);
        }
        let row = Row {
            id,
            app_id: n.app_id,
            title: n.summary,
            body: n.body,
            icon: n.icon,
            timestamp_ms: now * 1000,
            read: false,
            actions,
            hints,
        };
        let shown = variant::map(&row.to_json());
        let quiet = row.hint("suppress-sound").as_bool().unwrap_or(false);
        let mut rows = self.rows.clone();
        rows.insert(0, row);
        self.as_mut().set_rows(rows);
        // Progress is for the Hub; it doesn't call for attention.
        if !ongoing {
            self.as_mut().notification_received(&shown);
            if !self.is_dnd_enabled {
                if !quiet {
                    audio::notification_sound();
                }
                settings::with(|s| {
                    if *s.vibration_enabled() {
                        haptics::vibrate(&[50, 100, 50].map(OwnedValue::from));
                    }
                });
            }
        }
        u32::try_from(id).unwrap_or_default()
    }

    /// Gone from the Hub and the history; `reason` closes it on the bus too.
    fn dismiss(mut self: Pin<&mut Self>, id: i64, reason: Option<u32>) {
        let Some(at) = self.rows.iter().position(|r| r.id == id) else {
            return;
        };
        if let Some(db) = &self.store {
            db.execute("UPDATE notifications SET dismissed = 1 WHERE id = ?1", [id])
                .ok();
        }
        let mut rows = self.rows.clone();
        rows.remove(at);
        self.as_mut().rust_mut().senders.remove(&id);
        self.as_mut().set_rows(rows);
        self.as_mut()
            .notification_dismissed(i32::try_from(id).unwrap_or_default());
        if let (Some(reason), Ok(id)) = (reason, u32::try_from(id)) {
            emit("NotificationClosed", (id, reason));
        }
    }

    fn dismiss_notification(self: Pin<&mut Self>, id: i32) {
        self.dismiss(i64::from(id), Some(2));
    }

    fn dismiss_all_notifications(mut self: Pin<&mut Self>) {
        let ids: Vec<i64> = self
            .rows
            .iter()
            .filter(|r| !r.ongoing())
            .map(|r| r.id)
            .collect();
        for id in ids {
            self.as_mut().dismiss(id, Some(2));
        }
    }

    fn mark_as_read(self: Pin<&mut Self>, id: i32) {
        let Some(at) = self
            .rows
            .iter()
            .position(|r| r.id == i64::from(id) && !r.read)
        else {
            return;
        };
        if let Some(db) = &self.store {
            db.execute("UPDATE notifications SET read = 1 WHERE id = ?1", [id])
                .ok();
        }
        let mut rows = self.rows.clone();
        rows[at].read = true;
        self.set_rows(rows);
    }

    /// Tells the sender, and makes the call a Nemo.Notifications sender
    /// attached to the action; as the spec has it, a button closes the
    /// notification unless it is resident.
    fn activate(self: Pin<&mut Self>, row: &Row, action: &str) {
        if let Ok(id) = u32::try_from(row.id) {
            emit("ActionInvoked", (id, action.to_owned()));
        }
        if let Some(call) = row.hint(&format!("x-nemo-remote-action-{action}")).as_str() {
            nemo_call(call.to_owned());
        }
        if action != "default" && !row.hint("resident").as_bool().unwrap_or(false) {
            self.dismiss(row.id, Some(2));
        }
    }

    fn click_notification(mut self: Pin<&mut Self>, id: i32) {
        let Some(row) = self.row(id).cloned() else {
            return;
        };
        self.as_mut().mark_as_read(id);
        self.as_mut().activate(&row, "default");
        open(&row);
        if !row.ongoing() {
            self.dismiss(row.id, Some(2));
        }
    }

    fn trigger_action(mut self: Pin<&mut Self>, id: i32, action: &QString) {
        let Some(row) = self.row(id).cloned() else {
            return;
        };
        let action = action.to_string();
        self.as_mut().mark_as_read(id);
        self.as_mut().activate(&row, &action);
        let number = row.body.replace("From: ", "");
        match (row.app_id.as_str(), action.as_str()) {
            ("phone", "call_back") => {
                modem::dial(&number);
                deep_link("phone", "", &json!({}));
            }
            ("phone", "message") => {
                deep_link("messages", "conversation", &json!({"number": number}));
            }
            ("messages", "inline-reply") => deep_link("messages", "", &json!({})),
            ("messages", "mark_read") => self.dismiss(row.id, Some(2)),
            _ => {}
        }
    }

    fn reply(self: Pin<&mut Self>, id: i32, text: &QString) {
        if let Ok(id) = u32::try_from(id) {
            emit("NotificationReplied", (id, text.to_string()));
        }
        self.replied(id, text);
    }

    /// A sender that left the bus can no longer finish its progress.
    fn sender_gone(mut self: Pin<&mut Self>, sender: &str) {
        let ids: Vec<i64> = self
            .senders
            .iter()
            .filter(|(_, s)| *s == sender)
            .map(|(id, _)| *id)
            .collect();
        for id in ids {
            self.as_mut().dismiss(id, Some(3));
        }
    }
}

fn deep_link(app_id: &str, route: &str, params: &Json) {
    let (app, route, params) = (q(app_id), q(route), q(&params.to_string()));
    tasks::with(move |t| {
        t.launch_app_with_route(&app, &route, &params);
    });
}

/// The app it is from, at what it was about.
fn open(row: &Row) {
    match row.app_id.as_str() {
        "phone" => return deep_link("phone", "history", &json!({})),
        "messages" => {
            let target = row.hint("replyTarget").as_str().unwrap_or_default();
            return if target.is_empty() {
                deep_link("messages", "", &json!({}));
            } else {
                deep_link("messages", "conversation", &json!({"number": target}));
            };
        }
        _ => {}
    }
    if let Some(app) = installed(&[&row.app_id]) {
        return deep_link(&app, "", &json!({}));
    }
    // An Android or desktop app the catalogue does not list: its window, or
    // the one its default action opens.
    let opens_itself = row
        .actions
        .as_array()
        .into_iter()
        .flatten()
        .any(|a| a["key"] == "default");
    let app = q(&row.app_id);
    tasks::with(move |mut t| {
        if !t.can_launch(&app) {
            return log::warn("notifications", format_args!("no app to show for {app}"));
        }
        if !t.as_mut().expect_window(&app) && !opens_itself {
            t.launch(&app.to_string());
        }
    });
}

fn emit<B>(member: &'static str, body: B)
where
    B: serde::Serialize + zbus::zvariant::DynamicType + Send + Sync + 'static,
{
    io::spawn(async move {
        let Some(bus) = SERVER_BUS.get() else {
            return;
        };
        if let Err(e) = bus
            .emit_signal(None::<&str>, PATH, NAME, member, &body)
            .await
        {
            log::warn("notifications", format_args!("{member}: {e}"));
        }
    });
}

/// A `QDataStream`'d `QVariant` (Qt 6: type id, null flag, value) as the D-Bus
/// value it stands for: the types a Nemo action passes.
fn unstream(mut b: &[u8]) -> Option<Value<'static>> {
    let mut take = |n: usize| -> Option<Vec<u8>> {
        let (head, rest) = b.split_at_checked(n)?;
        b = rest;
        Some(head.to_vec())
    };
    let kind = u32::from_be_bytes(take(4)?.try_into().ok()?);
    take(1)?;
    Some(match kind {
        1 => Value::Bool(take(1)?[0] != 0),
        2 => Value::I32(i32::from_be_bytes(take(4)?.try_into().ok()?)),
        3 => Value::U32(u32::from_be_bytes(take(4)?.try_into().ok()?)),
        4 => Value::I64(i64::from_be_bytes(take(8)?.try_into().ok()?)),
        5 => Value::U64(u64::from_be_bytes(take(8)?.try_into().ok()?)),
        6 => Value::F64(f64::from_be_bytes(take(8)?.try_into().ok()?)),
        10 => {
            let len = u32::from_be_bytes(take(4)?.try_into().ok()?);
            if len == u32::MAX {
                return Some(Value::from(String::new()));
            }
            let units: Vec<u16> = take(usize::try_from(len).ok()?)?
                .as_chunks::<2>()
                .0
                .iter()
                .map(|c| u16::from_be_bytes(*c))
                .collect();
            Value::from(String::from_utf16_lossy(&units))
        }
        _ => return None,
    })
}

/// "<service> <path> <interface> <method> <base64 arg>...".
fn nemo_call(hint: String) {
    io::spawn(async move {
        let parts: Vec<&str> = hint.split_whitespace().collect();
        let [service, path, interface, method, args @ ..] = parts.as_slice() else {
            return;
        };
        let mut body = StructureBuilder::new();
        for arg in args {
            let Some(value) = base64::engine::general_purpose::STANDARD
                .decode(arg)
                .ok()
                .and_then(|b| unstream(&b))
            else {
                return log::warn(
                    "notifications",
                    format_args!("{method}: an argument it cannot read"),
                );
            };
            body = body.append_field(value);
        }
        let call = async {
            let bus = io::session_bus().await?;
            if args.is_empty() {
                bus.call_method(Some(*service), *path, Some(*interface), *method, &())
                    .await
            } else {
                bus.call_method(
                    Some(*service),
                    *path,
                    Some(*interface),
                    *method,
                    &body.build()?,
                )
                .await
            }
        };
        if let Err(e) = call.await {
            log::warn("notifications", format_args!("{interface}.{method}: {e}"));
        }
    });
}

struct Server {
    qt: Qt,
}

#[zbus::interface(name = "org.freedesktop.Notifications")]
impl Server {
    #[allow(clippy::too_many_arguments, reason = "the spec's signature")]
    async fn notify(
        &self,
        app_name: String,
        replaces_id: u32,
        app_icon: String,
        summary: String,
        body: String,
        actions: Vec<String>,
        mut hints: HashMap<String, OwnedValue>,
        expire_timeout: i32,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<u32> {
        let sender = h.sender().map(ToString::to_string).unwrap_or_default();
        let pid = match h.sender() {
            Some(s) => fdo::DBusProxy::new(&io::session_bus().await?)
                .await?
                .get_connection_unix_process_id(s.clone().into())
                .await
                .ok(),
            None => None,
        };
        let text = |hints: &HashMap<String, OwnedValue>, key: &str| {
            hints
                .get(key)
                .and_then(|v| v.downcast_ref::<String>().ok())
                .unwrap_or_default()
        };
        let app_id = app_of(
            &app_name,
            &text(&hints, "desktop-entry"),
            pid.and_then(app_of_pid).as_deref(),
        );
        let image = hints.remove("image-data").and_then(|v| image_url(&v));
        let path = text(&hints, "image-path");
        let icon = image
            .or_else(|| (!path.is_empty()).then_some(path))
            .unwrap_or(app_icon);
        let incoming = Incoming {
            app_id,
            replaces_id,
            icon,
            summary,
            body,
            actions: actions
                .as_chunks::<2>()
                .0
                .iter()
                .map(|[k, l]| (k.clone(), l.clone()))
                .collect(),
            hints: hints.iter().map(|(k, v)| (k.clone(), to_json(v))).collect(),
            expire_timeout,
            sender,
            keep: true,
        };
        ipc::on_gui(&self.qt, move |n| n.receive(incoming)).await
    }

    async fn close_notification(&self, id: u32) -> fdo::Result<()> {
        ipc::on_gui(&self.qt, move |n| n.dismiss(i64::from(id), Some(3))).await
    }

    #[allow(clippy::unused_self, reason = "a D-Bus method")]
    fn get_capabilities(&self) -> Vec<&'static str> {
        vec![
            "actions",
            "body",
            "body-markup",
            "icon-static",
            "persistence",
            "action-icons",
            "inline-reply",
        ]
    }

    #[allow(clippy::unused_self, reason = "a D-Bus method")]
    fn get_server_information(&self) -> (&'static str, &'static str, &'static str, &'static str) {
        (
            "Marathon Notification Service",
            "Marathon OS",
            env!("CARGO_PKG_VERSION"),
            "1.2",
        )
    }

    /// KDE's inline reply.
    async fn invoke_reply(&self, id: u32, text: String) -> fdo::Result<()> {
        ipc::on_gui(&self.qt, move |n| {
            n.reply(i32::try_from(id).unwrap_or_default(), &q(&text));
        })
        .await
    }
}

/// Takes org.freedesktop.Notifications, and closes the progress of senders
/// that leave the bus.
fn serve(qt: Qt) {
    io::spawn(async move {
        let served = async {
            let bus = zbus::Connection::session().await?;
            bus.object_server()
                .at(PATH, Server { qt: qt.clone() })
                .await?;
            bus.request_name(NAME).await?;
            SERVER_BUS.set(bus.clone()).ok();
            let mut changes = fdo::DBusProxy::new(&bus)
                .await?
                .receive_name_owner_changed()
                .await?;
            while let Some(change) = changes.next().await {
                if let Ok(args) = change.args() {
                    if args.new_owner().is_none() {
                        let name = args.name().to_string();
                        qt.queue(move |n| n.sender_gone(&name)).ok();
                    }
                }
            }
            zbus::Result::Ok(())
        };
        if let Err(e) = served.await {
            log::warn("notifications", format_args!("cannot serve {NAME}: {e}"));
        }
    });
}

mod proxy {
    use std::collections::HashMap;

    use zbus::zvariant::Value;

    /// The server, as the shell's other Rust posts to it.
    #[zbus::proxy(
        interface = "org.freedesktop.Notifications",
        default_service = "org.freedesktop.Notifications",
        default_path = "/org/freedesktop/Notifications"
    )]
    pub trait Notifications {
        #[allow(clippy::too_many_arguments, reason = "the spec's signature")]
        fn notify(
            &self,
            app_name: &str,
            replaces_id: u32,
            app_icon: &str,
            summary: &str,
            body: &str,
            actions: &[&str],
            hints: HashMap<&str, Value<'_>>,
            expire_timeout: i32,
        ) -> zbus::Result<u32>;
        fn close_notification(&self, id: u32) -> zbus::Result<()>;
        #[zbus(signal)]
        fn action_invoked(&self, id: u32, action_key: String) -> zbus::Result<()>;
    }
}

#[cfg(test)]
mod tests {
    use super::app_from_cgroup;

    #[test]
    fn a_process_is_the_app_its_cgroup_says() {
        assert_eq!(
            app_from_cgroup("/user.slice/marathon-apps/marathon-app-clock").as_deref(),
            Some("clock")
        );
        assert_eq!(
            app_from_cgroup("/app.slice/app-flatpak-org.gnome.Maps-12345.scope").as_deref(),
            Some("org.gnome.Maps")
        );
        assert_eq!(
            app_from_cgroup("/app.slice/app-gnome-org.gnome.Nautilus-3456.scope").as_deref(),
            Some("org.gnome.Nautilus")
        );
        assert_eq!(
            app_from_cgroup("/app.slice/app-org.kde.kate@1.service").as_deref(),
            Some("org.kde.kate")
        );
        assert_eq!(app_from_cgroup("/user.slice/session.scope"), None);
    }
}
