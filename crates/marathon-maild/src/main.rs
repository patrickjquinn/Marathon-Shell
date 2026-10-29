//! Marathon's mail: `org.marathonos.Mail` on the session bus, serving
//! `Mail1` to the Mail app. Each account's Inbox is watched with IMAP IDLE,
//! so new mail is notified with the app closed; folders sync on request,
//! and mail is sent through the account's SMTP server, queued while that
//! fails. The shell admits each caller (`Permissions1.Admit`).

mod imap;
mod oauth;
mod secrets;
mod smtp;
mod store;

use std::collections::HashMap;
use std::io::Read as _;
use std::process::ExitCode;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use marathon_rt::daemon::{admit, Shared};
use marathon_rt::{io, log};
use zbus::message::Header;
use zbus::object_server::SignalEmitter;
use zbus::{fdo, interface, Connection};
use zbus::{ObjectPath, OwnedFd, Variant as Value};

use imap::Failure;
use store::{Account, Server, Store};

const BUS_NAME: &str = "org.marathonos.Mail";
const PATH: &str = "/org/marathonos/Shell/Mail";
const MAIL: &[&str] = &["secret-service"];
/// IDLE is re-issued within the servers' 29-minute limit.
const IDLE: Duration = Duration::from_mins(25);

fn failed(e: impl std::fmt::Display) -> fdo::Error {
    fdo::Error::Failed(e.to_string())
}

fn id(s: &str) -> fdo::Result<i64> {
    s.parse()
        .map_err(|e| fdo::Error::InvalidArgs(format!("no such id {s}: {e}")))
}

#[derive(Clone)]
struct Core {
    bus: Connection,
    store: Shared<Store>,
    /// Each account's sync state and last error.
    states: Arc<Mutex<HashMap<i64, (&'static str, String)>>>,
    /// Accounts whose Inbox is watched.
    watched: Arc<Mutex<Vec<i64>>>,
    setup: Arc<AtomicBool>,
}

impl Core {
    fn emitter(&self) -> SignalEmitter<'static> {
        SignalEmitter::from_parts(
            self.bus.clone(),
            ObjectPath::from_static_str_unchecked(PATH),
        )
    }

    async fn account(&self, id: i64) -> fdo::Result<Account> {
        self.store
            .with(move |s| s.account(id))
            .await
            .map_err(failed)?
            .ok_or_else(|| fdo::Error::InvalidArgs(format!("no account {id}")))
    }

    async fn state(&self, account: i64, state: &'static str, error: String) {
        self.states
            .lock()
            .unwrap_or_else(|_| std::process::abort())
            .insert(account, (state, error.clone()));
        MailService::state_changed(&self.emitter(), &account.to_string(), state, &error)
            .await
            .ok();
    }

    async fn changed(&self, account: i64) {
        MailService::changed(&self.emitter(), &account.to_string())
            .await
            .ok();
    }

    /// A session for one operation, its failure shown as the account's state.
    async fn session(&self, account: &Account) -> Option<imap::Imap> {
        match imap::session(account).await {
            Ok(s) => Some(s),
            Err(e) => {
                self.state(account.id, "error", e.message().to_owned())
                    .await;
                None
            }
        }
    }

    async fn sync(&self, account: &Account, folder: &str) -> Result<(), Failure> {
        let mut s = imap::session(account).await?;
        imap::folders(&mut s, &self.store, account.id).await?;
        let fresh = imap::sync(&mut s, &self.store, account.id, folder).await?;
        s.logout().await.ok();
        self.notify(&fresh).await;
        Ok(())
    }

    /// Syncs `folder` (the Inbox when empty) and tells the app.
    async fn refresh(&self, account: i64, folder: String) {
        let a = match self.store.with(move |s| s.account(account)).await {
            Ok(Some(a)) => a,
            Ok(None) => return,
            Err(e) => {
                log::warn(
                    "Mail",
                    format_args!("cannot refresh account {account}: {e}"),
                );
                return self.state(account, "error", e.to_string()).await;
            }
        };
        let inbox = match self
            .store
            .with(move |s| s.folder_of_kind(account, "inbox"))
            .await
        {
            Ok(folder) => folder.unwrap_or_else(|| "INBOX".into()),
            Err(e) => {
                log::warn(
                    "Mail",
                    format_args!("cannot find account {account}'s inbox: {e}"),
                );
                return self.state(account, "error", e.to_string()).await;
            }
        };
        let folder = if folder.is_empty() || folder == "outbox" {
            inbox
        } else {
            folder
        };
        self.state(account, "syncing", String::new()).await;
        match self.sync(&a, &folder).await {
            Ok(()) => self.state(account, "idle", String::new()).await,
            Err(e) => {
                self.state(
                    account,
                    if matches!(e, Failure::Offline(_)) {
                        "offline"
                    } else {
                        "error"
                    },
                    e.message().to_owned(),
                )
                .await;
            }
        }
        self.changed(account).await;
        self.flush().await;
    }

    /// The Inbox, followed with IDLE until the account goes.
    async fn watch(&self, account: i64) {
        {
            let mut watched = self
                .watched
                .lock()
                .unwrap_or_else(|_| std::process::abort());
            if watched.contains(&account) {
                return;
            }
            watched.push(account);
        }
        let mut backoff = Duration::from_secs(30);
        loop {
            let a = match self.store.with(move |s| s.account(account)).await {
                Ok(Some(a)) => a,
                Ok(None) => break,
                Err(e) => {
                    log::warn("Mail", format_args!("cannot read account {account}: {e}"));
                    self.state(account, "error", e.to_string()).await;
                    async_io::Timer::after(backoff).await;
                    backoff = (backoff * 2).min(Duration::from_mins(15));
                    continue;
                }
            };
            self.state(account, "connecting", String::new()).await;
            match self.follow(&a).await {
                Ok(()) => backoff = Duration::from_secs(30),
                Err(e) => {
                    log::warn("Mail", format_args!("account {account}: {}", e.message()));
                    self.state(
                        account,
                        if matches!(e, Failure::Offline(_)) {
                            "offline"
                        } else {
                            "error"
                        },
                        e.message().to_owned(),
                    )
                    .await;
                    async_io::Timer::after(backoff).await;
                    backoff = (backoff * 2).min(Duration::from_mins(15));
                }
            }
        }
        self.watched
            .lock()
            .unwrap_or_else(|_| std::process::abort())
            .retain(|a| *a != account);
    }

    async fn follow(&self, a: &Account) -> Result<(), Failure> {
        let mut s = imap::session(a).await?;
        imap::folders(&mut s, &self.store, a.id).await?;
        let id = a.id;
        let inbox = self
            .store
            .with(move |st| st.folder_of_kind(id, "inbox"))
            .await
            .map_err(|e| Failure::Server(format!("cannot find account {id}'s inbox: {e}")))?
            .unwrap_or_else(|| "INBOX".into());
        loop {
            let fresh = imap::sync(&mut s, &self.store, a.id, &inbox).await?;
            self.state(a.id, "idle", String::new()).await;
            self.changed(a.id).await;
            self.notify(&fresh).await;
            self.flush().await;
            let mut idle = s.idle();
            idle.init().await?;
            let (wait, _stop) = idle.wait_with_timeout(IDLE);
            wait.await?;
            s = idle.done().await?;
            if self
                .store
                .with(move |st| st.account(id))
                .await
                .map_err(|e| Failure::Server(format!("cannot read account {id}: {e}")))?
                .is_none()
            {
                return Ok(());
            }
        }
    }

    async fn notify(&self, ids: &[i64]) {
        for id in ids.iter().take(5) {
            let id = *id;
            let raw = match self.store.with(move |s| s.raw(id)).await {
                Ok(Some(raw)) => raw,
                Ok(None) => continue,
                Err(e) => {
                    log::warn(
                        "Mail",
                        format_args!("cannot read message {id} for notification: {e}"),
                    );
                    continue;
                }
            };
            let m = store::summarise(&raw);
            let summary = if m.sender.is_empty() {
                "Mail".to_owned()
            } else {
                m.sender
            };
            let body = if m.subject.is_empty() {
                "(No subject)".to_owned()
            } else {
                m.subject
            };
            let hints = HashMap::from([
                ("category", Value::from("email.arrived")),
                ("desktop-entry", Value::from("email")),
            ]);
            let sent = self
                .bus
                .call_method(
                    Some("org.freedesktop.Notifications"),
                    "/org/freedesktop/Notifications",
                    Some("org.freedesktop.Notifications"),
                    "Notify",
                    &(
                        "Mail",
                        0u32,
                        "mail-unread",
                        summary,
                        body,
                        vec!["default", "Open"],
                        hints,
                        -1i32,
                    ),
                )
                .await;
            if let Err(e) = sent {
                log::warn("Mail", format_args!("Notify: {e}"));
            }
        }
    }

    /// Sends what waits in the outbox; a failure keeps it there.
    async fn flush(&self) {
        let Ok(queued) = self.store.with(|s| s.queued()).await else {
            return;
        };
        for (id, account, raw, recipients) in queued {
            let a = match self.store.with(move |s| s.account(account)).await {
                Ok(Some(a)) => a,
                Ok(None) => continue,
                Err(e) => {
                    log::warn(
                        "Mail",
                        format_args!("cannot read queued message {id}'s account {account}: {e}"),
                    );
                    continue;
                }
            };
            let sent = match secrets::credential(&a).await {
                Ok(credential) => {
                    let (acct, wire, to) = (a.clone(), raw.clone(), recipients.clone());
                    blocking::unblock(move || smtp::send(&acct, &credential, &wire, &to)).await
                }
                Err(_) => Err("login"),
            };
            match sent {
                Ok(()) => {
                    self.store.with(move |s| s.sent(id)).await.ok();
                    let a2 = a.clone();
                    let sent_folder = match self
                        .store
                        .with(move |s| s.folder_of_kind(a2.id, "sent"))
                        .await
                    {
                        Ok(folder) => folder,
                        Err(e) => {
                            log::warn(
                                "Mail",
                                format_args!("cannot find account {}'s sent folder: {e}", a.id),
                            );
                            None
                        }
                    };
                    if let Some(sent_folder) = sent_folder {
                        // Gmail and Outlook file what they send themselves.
                        if a.provider.is_empty() {
                            if let Some(mut s) = self.session(&a).await {
                                imap::append(&mut s, &sent_folder, &raw).await.ok();
                                s.logout().await.ok();
                            }
                        }
                    }
                    MailService::send_succeeded(&self.emitter()).await.ok();
                }
                Err(reason) => {
                    MailService::send_failed(&self.emitter(), reason).await.ok();
                    return;
                }
            }
            self.changed(account).await;
        }
    }

    /// A message by its id: its account, folder and UID.
    async fn locate(&self, message: &str) -> fdo::Result<(Account, String, u32, i64)> {
        let mid = id(message)?;
        let (account, folder, uid) = self
            .store
            .with(move |s| s.locate(mid))
            .await
            .map_err(failed)?
            .ok_or_else(|| fdo::Error::InvalidArgs("no such message".into()))?;
        Ok((self.account(account).await?, folder, uid, mid))
    }

    /// Verifies a new account by signing in; it is kept only if that works.
    async fn verify(&self, account: i64) {
        let failure = match self.store.with(move |s| s.account(account)).await {
            Ok(Some(a)) => match imap::session(&a).await {
                Ok(mut s) => {
                    imap::folders(&mut s, &self.store, account).await.ok();
                    s.logout().await.ok();
                    None
                }
                Err(e) => Some(e.reason()),
            },
            Ok(None) => Some("server"),
            Err(e) => {
                log::warn("Mail", format_args!("cannot verify account {account}: {e}"));
                self.setup.store(false, Ordering::Relaxed);
                MailService::account_setup_failed(&self.emitter(), "server")
                    .await
                    .ok();
                return;
            }
        };
        if self.setup.swap(false, Ordering::Relaxed) && failure.is_none() {
            MailService::account_setup_succeeded(&self.emitter(), &account.to_string())
                .await
                .ok();
            self.added(account).await;
            return;
        }
        self.store
            .with(move |s| s.remove_account(account))
            .await
            .ok();
        secrets::remove(account).await;
        MailService::account_setup_failed(&self.emitter(), failure.unwrap_or("cancelled"))
            .await
            .ok();
    }

    async fn added(&self, account: i64) {
        self.store
            .with(move |s| s.set_setting("account", &account.to_string()))
            .await
            .ok();
        self.changed(account).await;
        let core = self.clone();
        io::spawn(async move { core.watch(account).await });
    }
}

struct MailService(Core);

#[interface(name = "org.marathonos.Shell.Mail1")]
impl MailService {
    /// `[{ id, name, address, unread, outbox, folders: [{ id, name, kind,
    /// unread, count }] }]`.
    async fn get_accounts(
        &self,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<Vec<Value<'static>>> {
        admit(&self.0.bus, &h, "Mail", MAIL).await?;
        let rows = self
            .0
            .store
            .with(|s| s.account_list())
            .await
            .map_err(failed)?;
        Ok(rows.into_iter().map(Value::from).collect())
    }

    /// `[{ messageId, subject, from, address, snippet, date, unread,
    /// hasAttachment }]`, newest first; `folder` "outbox" is what waits.
    async fn get_messages(
        &self,
        #[zbus(header)] h: Header<'_>,
        account: String,
        folder: String,
    ) -> fdo::Result<Vec<Value<'static>>> {
        admit(&self.0.bus, &h, "Mail", MAIL).await?;
        let account = id(&account)?;
        let rows = self
            .0
            .store
            .with(move |s| s.messages(account, &folder))
            .await
            .map_err(failed)?;
        Ok(rows.into_iter().map(Value::from).collect())
    }

    /// As `MailService.openMessage` gives it; a large message is fetched
    /// whole first.
    async fn get_message(
        &self,
        #[zbus(header)] h: Header<'_>,
        message: String,
    ) -> fdo::Result<HashMap<&'static str, Value<'static>>> {
        admit(&self.0.bus, &h, "Mail", MAIL).await?;
        let (a, folder, uid, mid) = self.0.locate(&message).await?;
        let mut raw = self
            .0
            .store
            .with(move |s| s.raw(mid))
            .await
            .map_err(failed)?
            .unwrap_or_default();
        if mail_parser::MessageParser::default()
            .parse(&raw)
            .is_some_and(|m| m.text_body().len() + m.html_body().len() == 0)
        {
            if let Some(mut s) = self.0.session(&a).await {
                if let Ok(whole) = imap::whole(&mut s, &folder, uid).await {
                    raw = whole;
                }
                s.logout().await.ok();
            }
        }
        Ok(store::open(&raw))
    }

    /// `(syncState, lastError)`: offline, connecting, idle, syncing or error.
    async fn get_state(
        &self,
        #[zbus(header)] h: Header<'_>,
        account: String,
    ) -> fdo::Result<(String, String)> {
        admit(&self.0.bus, &h, "Mail", MAIL).await?;
        let account = id(&account)?;
        let states = self
            .0
            .states
            .lock()
            .unwrap_or_else(|_| std::process::abort());
        Ok(states.get(&account).map_or_else(
            || ("offline".into(), String::new()),
            |(s, e)| ((*s).to_owned(), e.clone()),
        ))
    }

    /// The account and folder last open.
    async fn get_selection(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<(String, String)> {
        admit(&self.0.bus, &h, "Mail", MAIL).await?;
        self.0
            .store
            .with(|s| {
                Ok::<_, rusqlite::Error>((
                    s.setting("account")?.unwrap_or_default(),
                    s.setting("folder")?.unwrap_or_default(),
                ))
            })
            .await
            .map_err(failed)
    }

    async fn select(
        &self,
        #[zbus(header)] h: Header<'_>,
        account: String,
        folder: String,
    ) -> fdo::Result<()> {
        admit(&self.0.bus, &h, "Mail", MAIL).await?;
        self.0
            .store
            .with(move |s| {
                s.set_setting("account", &account)
                    .and_then(|()| s.set_setting("folder", &folder))
            })
            .await
            .map_err(failed)
    }

    #[allow(clippy::unused_self, reason = "a D-Bus method")]
    fn o_auth_providers(&self) -> Vec<String> {
        oauth::configured()
    }

    /// Syncs a folder and sends what waits; the account's state follows.
    async fn refresh(
        &self,
        #[zbus(header)] h: Header<'_>,
        account: String,
        folder: String,
    ) -> fdo::Result<()> {
        admit(&self.0.bus, &h, "Mail", MAIL).await?;
        let (core, account) = (self.0.clone(), id(&account)?);
        io::spawn(async move { core.refresh(account, folder).await });
        Ok(())
    }

    async fn refresh_folders(
        &self,
        #[zbus(header)] h: Header<'_>,
        account: String,
    ) -> fdo::Result<()> {
        admit(&self.0.bus, &h, "Mail", MAIL).await?;
        let core = self.0.clone();
        let a = core.account(id(&account)?).await?;
        io::spawn(async move {
            if let Some(mut s) = core.session(&a).await {
                imap::folders(&mut s, &core.store, a.id).await.ok();
                s.logout().await.ok();
                core.changed(a.id).await;
            }
        });
        Ok(())
    }

    async fn mark_as_read(
        &self,
        #[zbus(header)] h: Header<'_>,
        message: String,
        read: bool,
    ) -> fdo::Result<()> {
        admit(&self.0.bus, &h, "Mail", MAIL).await?;
        let (a, folder, uid, mid) = self.0.locate(&message).await?;
        self.0
            .store
            .with(move |s| s.set_seen(mid, read))
            .await
            .map_err(failed)?;
        self.0.changed(a.id).await;
        let core = self.0.clone();
        io::spawn(async move {
            if let Some(mut s) = core.session(&a).await {
                imap::set_seen(&mut s, &folder, uid, read).await.ok();
                let fresh = imap::sync(&mut s, &core.store, a.id, &folder)
                    .await
                    .unwrap_or_default();
                core.notify(&fresh).await;
                s.logout().await.ok();
                core.changed(a.id).await;
            }
        });
        Ok(())
    }

    /// To the account's trash or archive folder.
    async fn move_to(
        &self,
        #[zbus(header)] h: Header<'_>,
        message: String,
        kind: String,
    ) -> fdo::Result<bool> {
        admit(&self.0.bus, &h, "Mail", MAIL).await?;
        let (a, folder, uid, mid) = self.0.locate(&message).await?;
        let account = a.id;
        let Some(to) = self
            .0
            .store
            .with(move |s| s.folder_of_kind(account, &kind))
            .await
            .map_err(failed)?
        else {
            return Ok(false);
        };
        if to == folder {
            return Ok(false);
        }
        self.0
            .store
            .with(move |s| s.delete(mid))
            .await
            .map_err(failed)?;
        self.0.changed(a.id).await;
        let core = self.0.clone();
        io::spawn(async move {
            if let Some(mut s) = core.session(&a).await {
                if let Err(e) = imap::move_to(&mut s, &folder, uid, &to).await {
                    log::warn("Mail", format_args!("move: {}", e.message()));
                }
                let fresh = imap::sync(&mut s, &core.store, a.id, &folder)
                    .await
                    .unwrap_or_default();
                core.notify(&fresh).await;
                s.logout().await.ok();
                core.changed(a.id).await;
            }
        });
        Ok(true)
    }

    /// Queues the message and sends it; the outcome comes as `SendSucceeded`
    /// or `SendFailed`. Attachments are open files with their names.
    #[allow(
        clippy::too_many_arguments,
        reason = "the message's fields, as MailService.send takes them"
    )]
    async fn send(
        &self,
        #[zbus(header)] h: Header<'_>,
        account: String,
        to: String,
        cc: String,
        bcc: String,
        subject: String,
        body: String,
        attachments: Vec<(String, OwnedFd)>,
    ) -> fdo::Result<bool> {
        admit(&self.0.bus, &h, "Mail", MAIL).await?;
        let a = self.0.account(id(&account)?).await?;
        let mut files = Vec::new();
        for (name, fd) in attachments {
            let mut bytes = Vec::new();
            std::fs::File::from(std::os::fd::OwnedFd::from(fd))
                .read_to_end(&mut bytes)
                .map_err(failed)?;
            let mime = mime_of(&name);
            files.push((name, mime.to_owned(), bytes));
        }
        let draft = smtp::Draft {
            to: &to,
            cc: &cc,
            bcc: &bcc,
            subject: &subject,
            body: &body,
            attachments: files,
        };
        let Ok((raw, recipients)) = smtp::compose(&a, draft) else {
            Self::send_failed(&self.0.emitter(), "address").await.ok();
            return Ok(false);
        };
        let account = a.id;
        self.0
            .store
            .with(move |s| s.queue(account, &raw, &recipients))
            .await
            .map_err(failed)?;
        self.0.changed(account).await;
        let core = self.0.clone();
        io::spawn(async move { core.flush().await });
        Ok(true)
    }

    /// Writes an attachment to Downloads; `AttachmentSaved` or `AttachmentFailed`.
    async fn save_attachment(
        &self,
        #[zbus(header)] h: Header<'_>,
        message: String,
        location: String,
    ) -> fdo::Result<bool> {
        admit(&self.0.bus, &h, "Mail", MAIL).await?;
        let (_, _, _, mid) = self.0.locate(&message).await?;
        let index: usize = location
            .parse()
            .map_err(|e| fdo::Error::InvalidArgs(format!("bad location: {e}")))?;
        let saved = self
            .0
            .store
            .with(move |s| {
                let Some(raw) = s.raw(mid)? else {
                    return Ok(None);
                };
                let Some((name, bytes)) = store::attachment(&raw, index) else {
                    return Ok(None);
                };
                let dir = marathon_rt::dirs::home().join("Downloads");
                if std::fs::create_dir_all(&dir).is_err() {
                    return Ok(None);
                }
                let path = dir.join(name);
                if std::fs::write(&path, bytes).is_err() {
                    return Ok(None);
                }
                Ok::<_, rusqlite::Error>(Some(path.to_string_lossy().into_owned()))
            })
            .await
            .map_err(failed)?;
        let e = self.0.emitter();
        let ok = saved.is_some();
        match saved {
            Some(path) => Self::attachment_saved(&e, &message, &location, &path)
                .await
                .ok(),
            None => Self::attachment_failed(&e, &message, &location).await.ok(),
        };
        Ok(ok)
    }

    /// A password account, kept once it signs in: `AccountSetupSucceeded`
    /// or `AccountSetupFailed`. Security: 0 none, 1 TLS, 2 STARTTLS.
    #[allow(
        clippy::too_many_arguments,
        reason = "the account's fields, as MailService.addImapAccount takes them"
    )]
    async fn add_imap_account(
        &self,
        #[zbus(header)] h: Header<'_>,
        name: String,
        email: String,
        imap_host: String,
        imap_port: u16,
        imap_security: u8,
        smtp_host: String,
        smtp_port: u16,
        smtp_security: u8,
        username: String,
        password: String,
    ) -> fdo::Result<bool> {
        admit(&self.0.bus, &h, "Mail", MAIL).await?;
        let username = if username.is_empty() {
            email.clone()
        } else {
            username
        };
        let a = Account {
            id: 0,
            name: if name.is_empty() { email.clone() } else { name },
            address: email,
            username,
            imap: Server {
                host: imap_host,
                port: imap_port,
                security: imap_security,
            },
            smtp: Server {
                host: smtp_host,
                port: smtp_port,
                security: smtp_security,
            },
            provider: String::new(),
        };
        let account = self
            .0
            .store
            .with(move |s| s.add_account(&a))
            .await
            .map_err(failed)?;
        if let Err(e) = secrets::store(account, &password).await {
            log::warn("Mail", format_args!("keyring: {e}"));
            self.0
                .store
                .with(move |s| s.remove_account(account))
                .await
                .ok();
            Self::account_setup_failed(&self.0.emitter(), "keyring")
                .await
                .ok();
            return Ok(false);
        }
        self.0.setup.store(true, Ordering::Relaxed);
        let core = self.0.clone();
        io::spawn(async move { core.verify(account).await });
        Ok(true)
    }

    fn cancel_account_setup(&self) {
        self.0.setup.store(false, Ordering::Relaxed);
    }

    /// The browser sign-in: `OAuthAuthUrlReady` with the page to open, then
    /// `OAuthLoginSucceeded` or `OAuthLoginFailed`.
    async fn start_oauth_login(
        &self,
        #[zbus(header)] h: Header<'_>,
        provider: String,
    ) -> fdo::Result<bool> {
        admit(&self.0.bus, &h, "Mail", MAIL).await?;
        let Some(p) = oauth::provider(&provider) else {
            return Ok(false);
        };
        self.0.setup.store(false, Ordering::Relaxed);
        let cancelled = Arc::new(AtomicBool::new(false));
        CANCEL
            .lock()
            .unwrap_or_else(|_| std::process::abort())
            .clone_from(&Some(Arc::clone(&cancelled)));
        let core = self.0.clone();
        io::spawn(async move {
            let e = core.emitter();
            let (urls, ready) = async_channel::bounded::<String>(1);
            let relay = e.clone();
            io::spawn(async move {
                if let Ok(url) = ready.recv().await {
                    Self::o_auth_auth_url_ready(&relay, &url).await.ok();
                }
            });
            let outcome = blocking::unblock(move || {
                oauth::sign_in(p, |url| drop(urls.try_send(url)), &cancelled)
            })
            .await;
            match outcome {
                Ok(sign_in) => {
                    let a = sign_in.account;
                    match core.store.with(move |s| s.add_account(&a)).await {
                        Ok(account) if secrets::store(account, &sign_in.refresh).await.is_ok() => {
                            Self::o_auth_login_succeeded(&e, &account.to_string())
                                .await
                                .ok();
                            core.added(account).await;
                        }
                        _ => drop(
                            Self::o_auth_login_failed(
                                &e,
                                "keyring",
                                "The keyring did not keep the sign-in",
                            )
                            .await,
                        ),
                    }
                }
                Err((kind, why)) => drop(Self::o_auth_login_failed(&e, kind, &why).await),
            }
        });
        Ok(true)
    }

    #[allow(clippy::unused_self, reason = "a D-Bus method")]
    fn cancel_o_auth_login(&self) {
        if let Some(c) = CANCEL
            .lock()
            .unwrap_or_else(|_| std::process::abort())
            .take()
        {
            c.store(true, Ordering::Relaxed);
        }
    }

    async fn remove_account(
        &self,
        #[zbus(header)] h: Header<'_>,
        account: String,
    ) -> fdo::Result<()> {
        admit(&self.0.bus, &h, "Mail", MAIL).await?;
        let account = id(&account)?;
        self.0
            .store
            .with(move |s| s.remove_account(account))
            .await
            .map_err(failed)?;
        secrets::remove(account).await;
        self.0.changed(account).await;
        Ok(())
    }

    #[zbus(signal)]
    async fn changed(e: &SignalEmitter<'_>, account: &str) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn state_changed(
        e: &SignalEmitter<'_>,
        account: &str,
        state: &str,
        error: &str,
    ) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn send_succeeded(e: &SignalEmitter<'_>) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn send_failed(e: &SignalEmitter<'_>, reason: &str) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn account_setup_succeeded(e: &SignalEmitter<'_>, account: &str) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn account_setup_failed(e: &SignalEmitter<'_>, reason: &str) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn attachment_saved(
        e: &SignalEmitter<'_>,
        message: &str,
        location: &str,
        path: &str,
    ) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn attachment_failed(
        e: &SignalEmitter<'_>,
        message: &str,
        location: &str,
    ) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn o_auth_auth_url_ready(e: &SignalEmitter<'_>, url: &str) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn o_auth_login_succeeded(e: &SignalEmitter<'_>, account: &str) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn o_auth_login_failed(
        e: &SignalEmitter<'_>,
        code: &str,
        message: &str,
    ) -> zbus::Result<()>;
}

static CANCEL: Mutex<Option<Arc<AtomicBool>>> = Mutex::new(None);

fn mime_of(name: &str) -> &'static str {
    match name
        .rsplit('.')
        .next()
        .unwrap_or_default()
        .to_ascii_lowercase()
        .as_str()
    {
        "jpg" | "jpeg" => "image/jpeg",
        "png" => "image/png",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "pdf" => "application/pdf",
        "txt" => "text/plain",
        "html" | "htm" => "text/html",
        "zip" => "application/zip",
        _ => "application/octet-stream",
    }
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let store = Shared::new(Store::open(
        &marathon_rt::dirs::data().join("marathon/mail/mail.db"),
    )?);
    let bus = io::session_bus().await?;
    let core = Core {
        bus: bus.clone(),
        store,
        states: Arc::default(),
        watched: Arc::default(),
        setup: Arc::default(),
    };
    bus.object_server()
        .at(PATH, MailService(core.clone()))
        .await?;
    bus.request_name(BUS_NAME).await?;
    for a in core.store.with(|s| s.accounts()).await? {
        let core = core.clone();
        io::spawn(async move { core.watch(a.id).await });
    }
    std::future::pending::<()>().await;
    Ok(())
}

fn main() -> ExitCode {
    match async_io::block_on(run()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            log::warn("marathon-maild", e);
            ExitCode::FAILURE
        }
    }
}
