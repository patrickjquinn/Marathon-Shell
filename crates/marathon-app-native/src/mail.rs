//! `MailService`: the Mail app's view of marathon-maild's Mail1, the
//! accounts and their folders, the open folder's messages as a list model,
//! sending and signing in.

#![allow(
    clippy::too_many_arguments,
    reason = "addImapAccount: an account's fields, as QML passes them"
)]

use std::fs::File;
use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{
    QByteArray, QDateTime, QHash, QHashPair_i32_QByteArray, QList, QMap, QMapPair_QString_QVariant,
    QModelIndex, QString, QStringList, QTimeZone, QVariant,
};
use zbus::zvariant::{Fd, OwnedValue};

use crate::shell::{calls, relay, Service};
use crate::variant;
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
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
        include!("cxx-qt-lib/qvariant.h");
        type QVariant = cxx_qt_lib::QVariant;
        include!("cxx-qt-lib/qmodelindex.h");
        type QModelIndex = cxx_qt_lib::QModelIndex;
        include!("cxx-qt-lib/qhash.h");
        type QHash_i32_QByteArray = cxx_qt_lib::QHash<cxx_qt_lib::QHashPair_i32_QByteArray>;
    }

    extern "RustQt" {
        #[qobject]
        /// The accounts, a `MailList` the runner hands it.
        #[qproperty(*mut MailList, accounts, READ, CONSTANT)]
        #[qproperty(QString, current_account_id, cxx_name = "currentAccountId", READ, WRITE = set_current_account_id, NOTIFY = current_account_changed)]
        #[qproperty(QString, current_account_name, cxx_name = "currentAccountName", READ, NOTIFY = current_account_changed)]
        #[qproperty(QList_QVariant, account_list, cxx_name = "accountList", READ, NOTIFY = account_list_changed)]
        #[qproperty(QString, current_folder_id, cxx_name = "currentFolderId", READ, WRITE = set_current_folder_id, NOTIFY = current_folder_changed)]
        #[qproperty(QString, current_folder_name, cxx_name = "currentFolderName", READ, NOTIFY = current_folder_changed)]
        /// The open folder's messages.
        #[qproperty(*mut MailList, messages, READ, NOTIFY = current_folder_changed)]
        #[qproperty(i32, unread_count, cxx_name = "unreadCount", READ, NOTIFY = unread_count_changed)]
        #[qproperty(i32, outbox_count, cxx_name = "outboxCount", READ, NOTIFY = outbox_count_changed)]
        #[qproperty(bool, online, READ, NOTIFY = online_changed)]
        #[qproperty(QStringList, oauth_providers, cxx_name = "oauthProviders", READ, NOTIFY = oauth_providers_changed)]
        /// offline, connecting, idle, syncing or error.
        #[qproperty(QString, sync_state, cxx_name = "syncState", READ, NOTIFY = sync_state_changed)]
        #[qproperty(QString, last_error, cxx_name = "lastError", READ, NOTIFY = sync_state_changed)]
        type MailService = super::MailServiceRust;

        /// Before QML reads `accounts` or `messages`.
        #[cxx_name = "setModels"]
        unsafe fn set_models(
            self: Pin<&mut MailService>,
            accounts: *mut MailList,
            messages: *mut MailList,
        );
        #[cxx_name = "setCurrentAccountId"]
        fn set_current_account_id(self: Pin<&mut MailService>, id: QString);
        #[cxx_name = "setCurrentFolderId"]
        fn set_current_folder_id(self: Pin<&mut MailService>, id: QString);

        #[qsignal]
        #[cxx_name = "currentAccountChanged"]
        fn current_account_changed(self: Pin<&mut MailService>);
        #[qsignal]
        #[cxx_name = "currentFolderChanged"]
        fn current_folder_changed(self: Pin<&mut MailService>);
        #[qsignal]
        #[cxx_name = "accountListChanged"]
        fn account_list_changed(self: Pin<&mut MailService>);
        #[qsignal]
        #[cxx_name = "unreadCountChanged"]
        fn unread_count_changed(self: Pin<&mut MailService>);
        #[qsignal]
        #[cxx_name = "outboxCountChanged"]
        fn outbox_count_changed(self: Pin<&mut MailService>);
        #[qsignal]
        #[cxx_name = "onlineChanged"]
        fn online_changed(self: Pin<&mut MailService>);
        #[qsignal]
        #[cxx_name = "oauthProvidersChanged"]
        fn oauth_providers_changed(self: Pin<&mut MailService>);
        #[qsignal]
        #[cxx_name = "syncStateChanged"]
        fn sync_state_changed(self: Pin<&mut MailService>);
        #[qsignal]
        #[cxx_name = "sendSucceeded"]
        fn send_succeeded(self: Pin<&mut MailService>);
        /// offline, login, certificate, address or server.
        #[qsignal]
        #[cxx_name = "sendFailed"]
        fn send_failed(self: Pin<&mut MailService>, reason: &QString);
        #[qsignal]
        #[cxx_name = "accountSetupSucceeded"]
        fn account_setup_succeeded(self: Pin<&mut MailService>, account_id: &QString);
        /// offline, login, certificate, keyring, server or cancelled.
        #[qsignal]
        #[cxx_name = "accountSetupFailed"]
        fn account_setup_failed(self: Pin<&mut MailService>, reason: &QString);
        #[qsignal]
        #[cxx_name = "attachmentSaved"]
        fn attachment_saved(
            self: Pin<&mut MailService>,
            message_id: &QString,
            location: &QString,
            path: &QString,
        );
        #[qsignal]
        #[cxx_name = "attachmentFailed"]
        fn attachment_failed(self: Pin<&mut MailService>, message_id: &QString, location: &QString);
        #[qsignal]
        #[cxx_name = "oauthAuthUrlReady"]
        fn oauth_auth_url_ready(self: Pin<&mut MailService>, url: &QString);
        #[qsignal]
        #[cxx_name = "oauthLoginSucceeded"]
        fn oauth_login_succeeded(self: Pin<&mut MailService>, account_id: &QString);
        #[qsignal]
        #[cxx_name = "oauthLoginFailed"]
        fn oauth_login_failed(self: Pin<&mut MailService>, code: &QString, message: &QString);

        /// Syncs the open folder and sends what waits; false with no account.
        #[qinvokable]
        fn refresh(self: &MailService) -> bool;
        #[qinvokable]
        #[cxx_name = "cancelSync"]
        fn cancel_sync(self: &MailService);
        #[qinvokable]
        #[cxx_name = "refreshFolders"]
        fn refresh_folders(self: &MailService, account_id: &QString);
        #[qinvokable]
        #[cxx_name = "markAsRead"]
        fn mark_as_read(self: &MailService, message_id: &QString, read: bool) -> bool;
        #[qinvokable]
        #[cxx_name = "moveToTrash"]
        fn move_to_trash(self: &MailService, message_id: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "moveToArchive"]
        fn move_to_archive(self: &MailService, message_id: &QString) -> bool;
        /// Queued once it returns true; sendSucceeded or sendFailed follows.
        #[qinvokable]
        fn send(
            self: &MailService,
            to: &QString,
            cc: &QString,
            bcc: &QString,
            subject: &QString,
            body: &QString,
            attachment_paths: &QStringList,
        ) -> bool;
        /// subject, from, to, cc, date, bodyHtml, bodyPlain and
        /// attachments: [{ name, size, mime, location }].
        #[qinvokable]
        #[cxx_name = "openMessage"]
        fn open_message(self: &MailService, message_id: &QString) -> QMap_QString_QVariant;
        #[qinvokable]
        #[cxx_name = "saveAttachment"]
        fn save_attachment(self: &MailService, message_id: &QString, location: &QString) -> bool;
        /// Encryption: 0 none, 1 TLS, 2 STARTTLS. accountSetupSucceeded or
        /// accountSetupFailed follows.
        #[qinvokable]
        #[cxx_name = "addImapAccount"]
        fn add_imap_account(
            self: &MailService,
            name: &QString,
            email: &QString,
            imap_host: &QString,
            imap_port: i32,
            imap_encryption: i32,
            smtp_host: &QString,
            smtp_port: i32,
            smtp_encryption: i32,
            username: &QString,
            password: &QString,
        ) -> bool;
        /// gmail or outlook; the oauth signals follow.
        #[qinvokable]
        #[cxx_name = "startOAuthLogin"]
        fn start_oauth_login(self: &MailService, provider: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "cancelAccountSetup"]
        fn cancel_account_setup(self: &MailService);
        #[qinvokable]
        #[cxx_name = "cancelOAuthLogin"]
        fn cancel_oauth_login(self: &MailService);
        #[qinvokable]
        #[cxx_name = "checkOAuthProviders"]
        fn check_oauth_providers(self: &MailService);
    }

    unsafe extern "RustQt" {
        /// Rows of maps: the messages' messageId, subject, from, snippet,
        /// timestamp, unread, hasAttachment and tint, or the accounts' id,
        /// name and address.
        #[qobject]
        #[base = QAbstractListModel]
        type MailList = super::MailListRust;

        #[inherit]
        #[cxx_name = "beginResetModel"]
        fn begin_reset_model(self: Pin<&mut MailList>);
        #[inherit]
        #[cxx_name = "endResetModel"]
        fn end_reset_model(self: Pin<&mut MailList>);
        #[cxx_override]
        #[cxx_name = "rowCount"]
        fn row_count(self: &MailList, parent: &QModelIndex) -> i32;
        #[cxx_override]
        fn data(self: &MailList, index: &QModelIndex, role: i32) -> QVariant;
        #[cxx_override]
        #[cxx_name = "roleNames"]
        fn role_names(self: &MailList) -> QHash_i32_QByteArray;
    }

    impl cxx_qt::Threading for MailService {}
    impl cxx_qt::Initialize for MailService {}
}

use qobject::{MailList, MailService};

const MAIL: Service = Service::on("org.marathonos.Mail", "Mail");

type Qt = cxx_qt::CxxQtThread<MailService>;
type Map = QMap<QMapPair_QString_QVariant>;

pub struct MailServiceRust {
    accounts: *mut MailList,
    messages: *mut MailList,
    current_account_id: QString,
    current_account_name: QString,
    account_list: QList<QVariant>,
    current_folder_id: QString,
    current_folder_name: QString,
    unread_count: i32,
    outbox_count: i32,
    online: bool,
    oauth_providers: QStringList,
    sync_state: QString,
    last_error: QString,
}

impl Default for MailServiceRust {
    fn default() -> Self {
        Self {
            accounts: std::ptr::null_mut(),
            messages: std::ptr::null_mut(),
            current_account_id: QString::default(),
            current_account_name: QString::default(),
            account_list: QList::default(),
            current_folder_id: QString::default(),
            current_folder_name: QString::default(),
            unread_count: 0,
            outbox_count: 0,
            online: true,
            oauth_providers: QStringList::default(),
            sync_state: QString::from("offline"),
            last_error: QString::default(),
        }
    }
}

fn text(map: &Map, key: &str) -> QString {
    map.get(&QString::from(key))
        .and_then(|v| v.value::<QString>())
        .unwrap_or_default()
}

fn number(map: &Map, key: &str) -> i64 {
    map.get(&QString::from(key))
        .and_then(|v| v.value::<i64>())
        .unwrap_or_default()
}

fn maps(list: &QList<QVariant>) -> Vec<Map> {
    list.iter().filter_map(QVariant::value).collect()
}

impl cxx_qt::Initialize for MailService {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        relay(qt.clone(), MAIL, "Changed", |obj, (account,): (String,)| {
            reload(&obj.qt_thread(), Some(account));
        });
        relay(
            qt.clone(),
            MAIL,
            "StateChanged",
            |mut obj, (account, state, error): (String, String, String)| {
                if obj.current_account_id.to_string() == account {
                    obj.as_mut().apply_state(&state, &error);
                }
            },
        );
        relay(qt.clone(), MAIL, "SendSucceeded", |obj, (): ()| {
            obj.send_succeeded();
        });
        relay(
            qt.clone(),
            MAIL,
            "SendFailed",
            |obj, (reason,): (String,)| obj.send_failed(&QString::from(&reason)),
        );
        relay(
            qt.clone(),
            MAIL,
            "AccountSetupSucceeded",
            |mut obj, (id,): (String,)| {
                obj.as_mut().set_current_account_id(QString::from(&id));
                obj.account_setup_succeeded(&QString::from(&id));
            },
        );
        relay(
            qt.clone(),
            MAIL,
            "AccountSetupFailed",
            |obj, (reason,): (String,)| obj.account_setup_failed(&QString::from(&reason)),
        );
        relay(
            qt.clone(),
            MAIL,
            "AttachmentSaved",
            |obj, (id, at, path): (String, String, String)| {
                obj.attachment_saved(
                    &QString::from(&id),
                    &QString::from(&at),
                    &QString::from(&path),
                );
            },
        );
        relay(
            qt.clone(),
            MAIL,
            "AttachmentFailed",
            |obj, (id, at): (String, String)| {
                obj.attachment_failed(&QString::from(&id), &QString::from(&at));
            },
        );
        relay(
            qt.clone(),
            MAIL,
            "OAuthAuthUrlReady",
            |obj, (url,): (String,)| obj.oauth_auth_url_ready(&QString::from(&url)),
        );
        relay(
            qt.clone(),
            MAIL,
            "OAuthLoginSucceeded",
            |mut obj, (id,): (String,)| {
                obj.as_mut().set_current_account_id(QString::from(&id));
                obj.oauth_login_succeeded(&QString::from(&id));
            },
        );
        relay(
            qt.clone(),
            MAIL,
            "OAuthLoginFailed",
            |obj, (code, text): (String, String)| {
                obj.oauth_login_failed(&QString::from(&code), &QString::from(&text));
            },
        );
        io::spawn(async move {
            let (account, folder) = MAIL
                .ask::<_, (String, String)>("GetSelection", &())
                .await
                .unwrap_or_default();
            qt.queue(move |mut obj| {
                let mut s = obj.as_mut().rust_mut();
                s.current_account_id = QString::from(&account);
                s.current_folder_id = QString::from(&folder);
                reload(&obj.qt_thread(), None);
            })
            .ok();
        });
    }
}

/// The accounts again, and the open folder's messages if `account` (or
/// any, when none is named) is the open one.
fn reload(qt: &Qt, account: Option<String>) {
    let qt = qt.clone();
    io::spawn(async move {
        let Ok(list) = MAIL.ask::<_, Vec<OwnedValue>>("GetAccounts", &()).await else {
            return;
        };
        qt.queue(move |mut obj| {
            obj.as_mut().apply_accounts(variant::qlist(&list));
            if account.is_none_or(|a| a == obj.current_account_id.to_string()) {
                load_messages(&obj);
            }
        })
        .ok();
    });
}

fn load_messages(obj: &MailService) {
    let (account, folder) = (
        obj.current_account_id.to_string(),
        obj.current_folder_id.to_string(),
    );
    let qt = obj.qt_thread();
    io::spawn(async move {
        let rows = if account.is_empty() {
            Vec::new()
        } else {
            MAIL.ask::<_, Vec<OwnedValue>>("GetMessages", &(account.clone(), folder.clone()))
                .await
                .unwrap_or_default()
        };
        let state = if account.is_empty() {
            None
        } else {
            MAIL.ask::<_, (String, String)>("GetState", &(account.clone(),))
                .await
                .ok()
        };
        qt.queue(move |mut obj| {
            if obj.current_account_id.to_string() != account
                || obj.current_folder_id.to_string() != folder
            {
                return;
            }
            if let Some((state, error)) = state {
                obj.as_mut().apply_state(&state, &error);
            }
            let rows = maps(&variant::qlist(&rows))
                .into_iter()
                .map(message_row)
                .collect();
            // SAFETY: the runner parents the models to this object.
            if let Some(model) = unsafe { obj.messages.as_mut() } {
                // SAFETY: as above; the model is a pinned QObject.
                unsafe { Pin::new_unchecked(model) }.set_rows(rows);
            }
        })
        .ok();
    });
}

/// A daemon row with what the inbox shows: the time as the list writes it
/// and the sender's tile colour.
fn message_row(mut m: Map) -> Map {
    m.insert(
        QString::from("timestamp"),
        QVariant::from(&relative(number(&m, "date"))),
    );
    m.insert(
        QString::from("tint"),
        QVariant::from(&QString::from(tint(&text(&m, "address").to_string()))),
    );
    m
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| i64::try_from(d.as_millis()).unwrap_or(0))
}

/// Today "HH:mm", then "Yesterday", the day this week, else "d MMM".
fn relative(ms: i64) -> QString {
    if ms <= 0 {
        return QString::default();
    }
    let zone = QTimeZone::system_time_zone();
    let when = QDateTime::from_msecs_since_epoch(ms, &zone);
    let today = QDateTime::from_msecs_since_epoch(now_ms(), &zone).date();
    let days = when.date().days_to(today);
    let format = match days {
        0 => "HH:mm",
        1 => return QString::from("Yesterday"),
        2..=6 => "ddd",
        _ => "d MMM",
    };
    if days == 0 {
        when.time().format(&QString::from(format))
    } else {
        when.date().format(&QString::from(format))
    }
}

/// One of six muted hues per address, stable across launches.
fn tint(address: &str) -> &'static str {
    const PALETTE: [&str; 6] = [
        "#3a6b9c", "#4a8a5e", "#c89545", "#a85968", "#6b5d8f", "#1a4a3e",
    ];
    if address.is_empty() {
        return "#040404";
    }
    let hash = address
        .encode_utf16()
        .fold(0u32, |h, c| h.wrapping_mul(31).wrapping_add(u32::from(c)));
    PALETTE[usize::try_from(hash).unwrap_or(0) % PALETTE.len()]
}

impl MailService {
    /// # Safety
    ///
    /// The models outlive this object; the runner parents them to it.
    unsafe fn set_models(self: Pin<&mut Self>, accounts: *mut MailList, messages: *mut MailList) {
        let mut s = self.rust_mut();
        s.accounts = accounts;
        s.messages = messages;
    }

    fn apply_state(mut self: Pin<&mut Self>, state: &str, error: &str) {
        let (state, error) = (QString::from(state), QString::from(error));
        if self.sync_state != state || self.last_error != error {
            let mut s = self.as_mut().rust_mut();
            s.sync_state = state.clone();
            s.last_error = error;
            self.as_mut().sync_state_changed();
        }
        set!(self, online, online_changed, state.to_string() != "offline");
    }

    fn apply_accounts(mut self: Pin<&mut Self>, list: QList<QVariant>) {
        let accounts = maps(&list);
        // SAFETY: the runner parents the models to this object.
        if let Some(model) = unsafe { self.accounts.as_mut() } {
            // SAFETY: as above; the model is a pinned QObject.
            unsafe { Pin::new_unchecked(model) }.set_rows(accounts.clone());
        }
        let id = self.current_account_id.to_string();
        if !accounts.iter().any(|a| text(a, "id").to_string() == id) {
            let first = accounts.first().map(|a| text(a, "id")).unwrap_or_default();
            self.as_mut().rust_mut().current_account_id = first;
            self.as_mut().rust_mut().current_folder_id = QString::default();
        }
        let id = self.current_account_id.to_string();
        let account = accounts
            .iter()
            .find(|a| text(a, "id").to_string() == id)
            .cloned()
            .unwrap_or_default();
        let folders: Vec<Map> = account
            .get(&QString::from("folders"))
            .and_then(|v| v.value::<QList<QVariant>>())
            .map(|l| maps(&l))
            .unwrap_or_default();
        let folder = self.current_folder_id.to_string();
        let open = folders
            .iter()
            .find(|f| text(f, "id").to_string() == folder)
            .or_else(|| {
                folders
                    .iter()
                    .find(|f| text(f, "kind").to_string() == "inbox")
            });
        let (folder_id, folder_name) = open
            .map(|f| (text(f, "id"), text(f, "name")))
            .unwrap_or_default();
        let name = text(&account, "name");
        if self.current_account_name != name || self.current_account_id.to_string() != id {
            self.as_mut().rust_mut().current_account_name = name;
            self.as_mut().current_account_changed();
        }
        if self.current_folder_id != folder_id || self.current_folder_name != folder_name {
            let mut s = self.as_mut().rust_mut();
            s.current_folder_id = folder_id;
            s.current_folder_name = folder_name;
            self.as_mut().current_folder_changed();
        }
        let unread = i32::try_from(number(&account, "unread")).unwrap_or(0);
        set!(self, unread_count, unread_count_changed, unread);
        let outbox = i32::try_from(number(&account, "outbox")).unwrap_or(0);
        set!(self, outbox_count, outbox_count_changed, outbox);
        self.as_mut().rust_mut().account_list = list;
        self.account_list_changed();
    }

    fn select(&self) {
        MAIL.call(
            "Select",
            (
                self.current_account_id.to_string(),
                self.current_folder_id.to_string(),
            ),
        );
    }

    fn set_current_account_id(mut self: Pin<&mut Self>, id: QString) {
        if self.current_account_id == id {
            return;
        }
        let mut s = self.as_mut().rust_mut();
        s.current_account_id = id;
        s.current_folder_id = QString::default();
        self.select();
        reload(&self.qt_thread(), None);
    }

    fn set_current_folder_id(mut self: Pin<&mut Self>, id: QString) {
        if self.current_folder_id == id {
            return;
        }
        self.as_mut().rust_mut().current_folder_id = id;
        self.select();
        reload(&self.qt_thread(), None);
    }

    fn refresh(&self) -> bool {
        if self.current_account_id.is_empty() {
            return false;
        }
        MAIL.call(
            "Refresh",
            (
                self.current_account_id.to_string(),
                self.current_folder_id.to_string(),
            ),
        );
        true
    }

    fn cancel_sync(&self) {}

    calls! { MAIL;
        refresh_folders(account_id: &QString) => "RefreshFolders";
        cancel_account_setup() => "CancelAccountSetup";
        cancel_oauth_login() => "CancelOAuthLogin";
    }

    fn mark_as_read(&self, message_id: &QString, read: bool) -> bool {
        MAIL.call("MarkAsRead", (message_id.to_string(), read));
        true
    }

    fn move_to(&self, message_id: &QString, kind: &str) -> bool {
        MAIL.ask_now::<_, bool>("MoveTo", &(message_id.to_string(), kind))
            .unwrap_or(false)
    }

    fn move_to_trash(&self, message_id: &QString) -> bool {
        self.move_to(message_id, "trash")
    }

    fn move_to_archive(&self, message_id: &QString) -> bool {
        self.move_to(message_id, "archive")
    }

    fn send(
        &self,
        to: &QString,
        cc: &QString,
        bcc: &QString,
        subject: &QString,
        body: &QString,
        attachment_paths: &QStringList,
    ) -> bool {
        if self.current_account_id.is_empty() {
            return false;
        }
        let mut files = Vec::new();
        for path in QList::<QString>::from(attachment_paths)
            .iter()
            .map(|p| p.to_string().trim_start_matches("file://").to_owned())
        {
            let Ok(file) = File::open(&path) else {
                return false;
            };
            let name = path.rsplit('/').next().unwrap_or("attachment").to_owned();
            files.push((name, file));
        }
        let wire: Vec<(String, Fd<'_>)> = files
            .iter()
            .map(|(n, f)| (n.clone(), Fd::from(f)))
            .collect();
        let body = (
            self.current_account_id.to_string(),
            to.to_string(),
            cc.to_string(),
            bcc.to_string(),
            subject.to_string(),
            body.to_string(),
            wire,
        );
        MAIL.ask_now::<_, bool>("Send", &body).unwrap_or(false)
    }

    fn open_message(&self, message_id: &QString) -> Map {
        let Some(wire) = MAIL.ask_now::<_, std::collections::HashMap<String, OwnedValue>>(
            "GetMessage",
            &(message_id.to_string(),),
        ) else {
            return Map::default();
        };
        let mut m = variant::qmap(&wire);
        let date = number(&m, "date");
        if date > 0 {
            m.insert(
                QString::from("date"),
                QVariant::from(&QDateTime::from_msecs_since_epoch(
                    date,
                    &QTimeZone::system_time_zone(),
                )),
            );
        }
        m
    }

    fn save_attachment(&self, message_id: &QString, location: &QString) -> bool {
        MAIL.call(
            "SaveAttachment",
            (message_id.to_string(), location.to_string()),
        );
        !location.is_empty()
    }

    #[allow(
        clippy::too_many_arguments,
        reason = "MailService.addImapAccount's arguments"
    )]
    fn add_imap_account(
        &self,
        name: &QString,
        email: &QString,
        imap_host: &QString,
        imap_port: i32,
        imap_encryption: i32,
        smtp_host: &QString,
        smtp_port: i32,
        smtp_encryption: i32,
        username: &QString,
        password: &QString,
    ) -> bool {
        let (Ok(ip), Ok(ie), Ok(sp), Ok(se)) = (
            u16::try_from(imap_port),
            u8::try_from(imap_encryption),
            u16::try_from(smtp_port),
            u8::try_from(smtp_encryption),
        ) else {
            return false;
        };
        if email.is_empty() || imap_host.is_empty() || smtp_host.is_empty() {
            return false;
        }
        let args = (
            name.to_string(),
            email.to_string(),
            imap_host.to_string(),
            ip,
            ie,
            smtp_host.to_string(),
            sp,
            se,
            username.to_string(),
            password.to_string(),
        );
        MAIL.ask_now::<_, bool>("AddImapAccount", &args)
            .unwrap_or(false)
    }

    fn start_oauth_login(&self, provider: &QString) -> bool {
        MAIL.ask_now::<_, bool>("StartOAuthLogin", &(provider.to_string(),))
            .unwrap_or(false)
    }

    fn check_oauth_providers(&self) {
        let qt = self.qt_thread();
        io::spawn(async move {
            let providers = MAIL
                .ask::<_, Vec<String>>("OAuthProviders", &())
                .await
                .unwrap_or_default();
            qt.queue(move |mut obj| {
                let list =
                    QStringList::from(&providers.iter().map(QString::from).collect::<QList<_>>());
                obj.as_mut().rust_mut().oauth_providers = list;
                obj.oauth_providers_changed();
            })
            .ok();
        });
    }
}

#[derive(Default)]
pub struct MailListRust {
    rows: Vec<Map>,
}

const ROLES: [&str; 11] = [
    "messageId",
    "subject",
    "from",
    "snippet",
    "timestamp",
    "unread",
    "hasAttachment",
    "tint",
    "id",
    "name",
    "address",
];
const FIRST_ROLE: i32 = 0x0100 + 1; // Qt::UserRole + 1

impl MailList {
    fn set_rows(mut self: Pin<&mut Self>, rows: Vec<Map>) {
        self.as_mut().begin_reset_model();
        self.as_mut().rust_mut().rows = rows;
        self.end_reset_model();
    }

    fn row_count(&self, parent: &QModelIndex) -> i32 {
        if parent.is_valid() {
            0
        } else {
            i32::try_from(self.rows.len()).unwrap_or(i32::MAX)
        }
    }

    fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
        let row = usize::try_from(index.row())
            .ok()
            .and_then(|r| self.rows.get(r));
        let key = usize::try_from(role - FIRST_ROLE)
            .ok()
            .and_then(|i| ROLES.get(i));
        row.zip(key)
            .and_then(|(r, key)| r.get(&QString::from(*key)))
            .unwrap_or_default()
    }

    fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut roles = QHash::<QHashPair_i32_QByteArray>::default();
        for (role, name) in (FIRST_ROLE..).zip(ROLES) {
            roles.insert(role, QByteArray::from(name));
        }
        roles
    }
}
