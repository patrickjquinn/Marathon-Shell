//! Marathon's address book and DAV sync: `org.marathonos.Dav` on the
//! session bus, serving `Contacts1` and `Dav1` where the shell served them.
//! The shell admits each caller (`Permissions1.Admit`).

mod accounts;
mod contacts;
mod secrets;
mod sync;
mod webdav;

use std::collections::HashMap;
use std::process::ExitCode;
use std::time::Duration;

use async_channel::{Receiver, Sender};
use async_io::Timer;
use marathon_rt::daemon::{admit, shell_data, Shared};
use marathon_rt::{io, log};
use zbus::message::Header;
use zbus::object_server::SignalEmitter;
use zbus::zvariant::{ObjectPath, OwnedValue, Value};
use zbus::{fdo, interface, Connection};

use accounts::{Account, Accounts, SecretOp};
use contacts::{Book, Contact, Row};
use sync::Events;

const BUS_NAME: &str = "org.marathonos.Dav";
const CONTACTS_PATH: &str = "/org/marathonos/Shell/Contacts";
const DAV_PATH: &str = "/org/marathonos/Shell/Dav";
const SYNC_EVERY: Duration = Duration::from_mins(15);

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .ok()
        .and_then(|d| i64::try_from(d.as_millis()).ok())
        .unwrap_or_default()
}

#[derive(Default)]
struct SyncState {
    syncing: bool,
    last_error: String,
    last_sync_ms: i64,
    /// Each collection's sync-token, by URL.
    tokens: HashMap<String, String>,
}

#[derive(Clone)]
struct Core {
    bus: Connection,
    book: Shared<Book>,
    accounts: Shared<Accounts>,
    events: Shared<Events>,
    state: Shared<SyncState>,
    agent: ureq::Agent,
    /// Wakes the keyring task.
    keyring: Sender<()>,
}

fn emitter(bus: &Connection, path: &'static str) -> SignalEmitter<'static> {
    SignalEmitter::from_parts(bus.clone(), ObjectPath::from_static_str_unchecked(path))
}

impl Core {
    fn contacts(&self) -> SignalEmitter<'static> {
        emitter(&self.bus, CONTACTS_PATH)
    }

    fn dav(&self) -> SignalEmitter<'static> {
        emitter(&self.bus, DAV_PATH)
    }

    async fn discover(&self, id: String) {
        let ready = {
            let id = id.clone();
            self.accounts.with(move |a| a.ready(&id)).await
        };
        let Some((mut account, secret)) = ready else {
            return;
        };
        let agent = self.agent.clone();
        let found = blocking::unblock(move || {
            sync::discover(&agent, &mut account, &secret).map(|()| account)
        })
        .await;
        match found {
            Ok(account) => {
                self.accounts
                    .with(move |a| {
                        if let Some(known) = a.get_mut(&account.id) {
                            *known = Account {
                                enabled: known.enabled,
                                display_name: known.display_name.clone(),
                                ..account
                            };
                            a.save();
                        }
                    })
                    .await;
                DavService::account_discovered(&self.dav(), &id).await.ok();
            }
            Err(reason) => {
                log::warn("Dav", format_args!("discovery of {id} failed: {reason}"));
                DavService::account_discovery_failed(&self.dav(), &id, &reason)
                    .await
                    .ok();
            }
        }
    }

    /// Pulls every enabled account's collections into the address book and
    /// the event store.
    #[allow(
        clippy::too_many_lines,
        reason = "the account and collection sync transaction is clearer as one ordered workflow"
    )]
    async fn sync(&self) {
        let started = self
            .state
            .with(|s| !std::mem::replace(&mut s.syncing, true))
            .await;
        if !started {
            return;
        }
        let ready: Vec<(Account, String)> = self
            .accounts
            .with(|a| {
                a.saved
                    .accounts
                    .iter()
                    .filter_map(|x| a.ready(&x.id))
                    .collect()
            })
            .await;
        let mut changed = Vec::new();
        let mut error = String::new();
        for (account, secret) in ready {
            let collections = account
                .collections_contacts
                .iter()
                .chain(&account.collections_calendar)
                .cloned()
                .collect::<Vec<_>>();
            for collection in collections {
                let token = {
                    let collection = collection.clone();
                    self.state
                        .with(move |s| s.tokens.get(&collection).cloned().unwrap_or_default())
                        .await
                };
                let (agent, from, secret, url) = (
                    self.agent.clone(),
                    account.clone(),
                    secret.clone(),
                    collection.clone(),
                );
                let pulled =
                    blocking::unblock(move || sync::pull(&agent, &from, &secret, &url, &token))
                        .await;
                let pulled = match pulled {
                    Ok(pulled) => pulled,
                    Err(e) => {
                        log::warn("Dav", format_args!("{collection}: {e}"));
                        error = e;
                        continue;
                    }
                };
                let token = pulled.token;
                let contacts = pulled.contacts;
                let (stored, failures) = self
                    .book
                    .with(move |book| {
                        let mut stored = Vec::new();
                        let mut failures = Vec::new();
                        for contact in contacts {
                            match book.merge(contact) {
                                Ok(Some(id)) => stored.push(id),
                                Ok(None) => {}
                                Err(error) => failures.push(error.to_string()),
                            }
                        }
                        (stored, failures)
                    })
                    .await;
                changed.extend(stored);
                if failures.is_empty() {
                    self.state
                        .with(move |s| s.tokens.insert(collection, token))
                        .await;
                } else {
                    for failure in failures {
                        log::warn("Dav", format_args!("cannot store contact: {failure}"));
                        error = failure;
                    }
                }
                let (events, id) = (pulled.events, account.id.clone());
                let stored = self
                    .events
                    .with(move |store| {
                        events
                            .iter()
                            .try_for_each(|e| store.upsert(&id, e, now_ms()).map(drop))
                    })
                    .await;
                if let Err(e) = stored {
                    log::warn("Dav", format_args!("cannot store events: {e}"));
                }
            }
            DavService::sync_finished(&self.dav(), &account.id)
                .await
                .ok();
        }
        if !changed.is_empty() {
            ContactsService::contacts_changed(&self.contacts())
                .await
                .ok();
            for id in changed {
                ContactsService::contact_updated(&self.contacts(), id)
                    .await
                    .ok();
            }
        }
        self.state
            .with(move |s| {
                s.syncing = false;
                s.last_error = error;
                s.last_sync_ms = now_ms();
            })
            .await;
    }
}

/// Runs what the keyring still has to do, again with backoff while it
/// cannot answer.
async fn keep_secrets(core: Core, wake: Receiver<()>) {
    let mut backoff = Duration::from_secs(1);
    loop {
        let mut unavailable = false;
        for op in core.accounts.with(|a| a.secret_work()).await {
            match op {
                SecretOp::Store { id, label, secret } => {
                    match secrets::store(&core.bus, &id, &label, &secret).await {
                        Ok(()) => core.accounts.with(move |a| a.stored(&id, &secret)).await,
                        Err(_) => unavailable = true,
                    }
                }
                SecretOp::Load(id) => match secrets::load(&core.bus, &id).await {
                    Ok(secret) => core.accounts.with(move |a| a.loaded(&id, secret)).await,
                    Err(_) => unavailable = true,
                },
                SecretOp::Remove(id) => match secrets::remove(&core.bus, &id).await {
                    Ok(()) => core.accounts.with(move |a| a.removed(&id)).await,
                    Err(_) => unavailable = true,
                },
            }
        }
        if unavailable {
            futures_lite::future::or(async { wake.recv().await.unwrap_or(()) }, async {
                Timer::after(backoff).await;
            })
            .await;
            backoff = (backoff * 2).min(Duration::from_mins(5));
        } else {
            backoff = Duration::from_secs(1);
            if wake.recv().await.is_err() {
                return;
            }
        }
    }
}

struct ContactsService(Core);

impl ContactsService {
    async fn admit(&self, h: &Header<'_>) -> fdo::Result<()> {
        admit(&self.0.bus, h, "Contacts", &["contacts"]).await
    }
}

fn rows(contacts: impl IntoIterator<Item = Contact>) -> Vec<Value<'static>> {
    contacts.into_iter().map(|c| Value::from(c.row())).collect()
}

#[interface(name = "org.marathonos.Shell.Contacts1")]
impl ContactsService {
    async fn get_contacts(
        &self,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<Vec<Value<'static>>> {
        self.admit(&h).await?;
        Ok(rows(self.0.book.with(|b| b.all().to_vec()).await))
    }

    async fn get_contact(&self, #[zbus(header)] h: Header<'_>, id: i32) -> fdo::Result<Row> {
        self.admit(&h).await?;
        Ok(self
            .0
            .book
            .with(move |b| b.get(id).map(Contact::row))
            .await
            .unwrap_or_default())
    }

    async fn get_contact_by_number(
        &self,
        #[zbus(header)] h: Header<'_>,
        phone_number: String,
    ) -> fdo::Result<Row> {
        self.admit(&h).await?;
        Ok(self
            .0
            .book
            .with(move |b| b.by_number(&phone_number).map(Contact::row))
            .await
            .unwrap_or_default())
    }

    async fn search_contacts(
        &self,
        #[zbus(header)] h: Header<'_>,
        query: String,
    ) -> fdo::Result<Vec<Value<'static>>> {
        self.admit(&h).await?;
        Ok(rows(
            self.0
                .book
                .with(move |b| b.search(&query).into_iter().cloned().collect::<Vec<_>>())
                .await,
        ))
    }

    async fn add_contact(
        &self,
        #[zbus(header)] h: Header<'_>,
        name: String,
        phone: String,
        email: String,
    ) -> fdo::Result<()> {
        self.admit(&h).await?;
        let added = self
            .0
            .book
            .with(move |b| {
                b.add(Contact {
                    name,
                    phone,
                    email,
                    ..Contact::default()
                })
            })
            .await
            .map_err(|e| fdo::Error::Failed(format!("Cannot save contact: {e}")))?;
        let Some(id) = added else {
            return Err(fdo::Error::InvalidArgs("A contact needs a name".into()));
        };
        Self::contacts_changed(&self.0.contacts()).await?;
        Ok(Self::contact_added(&self.0.contacts(), id).await?)
    }

    async fn update_contact(
        &self,
        #[zbus(header)] h: Header<'_>,
        id: i32,
        data: HashMap<String, OwnedValue>,
    ) -> fdo::Result<()> {
        self.admit(&h).await?;
        let updated = self
            .0
            .book
            .with(move |b| b.update(id, &data))
            .await
            .map_err(|e| fdo::Error::Failed(format!("Cannot save contact {id}: {e}")))?;
        if !updated {
            return Err(fdo::Error::InvalidArgs(format!("No contact {id}")));
        }
        Self::contacts_changed(&self.0.contacts()).await?;
        Ok(Self::contact_updated(&self.0.contacts(), id).await?)
    }

    async fn delete_contact(&self, #[zbus(header)] h: Header<'_>, id: i32) -> fdo::Result<()> {
        self.admit(&h).await?;
        let deleted = self
            .0
            .book
            .with(move |b| b.delete(id))
            .await
            .map_err(|e| fdo::Error::Failed(format!("Cannot delete contact {id}: {e}")))?;
        if !deleted {
            return Err(fdo::Error::InvalidArgs(format!("No contact {id}")));
        }
        Self::contacts_changed(&self.0.contacts()).await?;
        Ok(Self::contact_deleted(&self.0.contacts(), id).await?)
    }

    #[zbus(signal)]
    async fn contacts_changed(e: &SignalEmitter<'_>) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn contact_added(e: &SignalEmitter<'_>, id: i32) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn contact_updated(e: &SignalEmitter<'_>, id: i32) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn contact_deleted(e: &SignalEmitter<'_>, id: i32) -> zbus::Result<()>;
}

struct DavService(Core);

impl DavService {
    async fn admit(&self, h: &Header<'_>) -> fdo::Result<()> {
        admit(&self.0.bus, h, "Dav", &["system"]).await
    }
}

#[interface(name = "org.marathonos.Shell.Dav1")]
impl DavService {
    async fn list_accounts(
        &self,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<Vec<Value<'static>>> {
        self.admit(&h).await?;
        Ok(self
            .0
            .accounts
            .with(|a| {
                a.saved
                    .accounts
                    .iter()
                    .map(|x| Value::from(x.row()))
                    .collect()
            })
            .await)
    }

    async fn add_account(
        &self,
        #[zbus(header)] h: Header<'_>,
        display_name: String,
        base_url: String,
        username: String,
        secret: String,
        auth_kind: String,
    ) -> fdo::Result<String> {
        self.admit(&h).await?;
        let id = std::fs::read_to_string("/proc/sys/kernel/random/uuid")
            .map_err(|e| fdo::Error::Failed(e.to_string()))?
            .trim()
            .to_owned();
        let auth_kind = if auth_kind.is_empty() {
            "basic".to_owned()
        } else {
            auth_kind
        };
        let account = Account {
            id: id.clone(),
            display_name,
            base_url,
            username,
            auth_kind,
            enabled: true,
            ..Account::default()
        };
        self.0.accounts.with(move |a| a.add(account, secret)).await;
        self.0.keyring.try_send(()).ok();
        Self::accounts_changed(&self.0.dav()).await?;
        let core = self.0.clone();
        let account = id.clone();
        io::spawn(async move { core.discover(account).await });
        Ok(id)
    }

    async fn remove_account(&self, #[zbus(header)] h: Header<'_>, id: String) -> fdo::Result<bool> {
        self.admit(&h).await?;
        let removed = self.0.accounts.with(move |a| a.remove(&id)).await;
        if removed {
            self.0.keyring.try_send(()).ok();
            Self::accounts_changed(&self.0.dav()).await?;
        }
        Ok(removed)
    }

    async fn enable_account(
        &self,
        #[zbus(header)] h: Header<'_>,
        id: String,
        enabled: bool,
    ) -> fdo::Result<()> {
        self.admit(&h).await?;
        let found = self
            .0
            .accounts
            .with(move |a| {
                let found = a.get_mut(&id).map(|x| x.enabled = enabled).is_some();
                a.save();
                found
            })
            .await;
        if found {
            Self::accounts_changed(&self.0.dav()).await?;
        }
        Ok(())
    }

    async fn sync_now(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        self.admit(&h).await?;
        let core = self.0.clone();
        io::spawn(async move { core.sync().await });
        Ok(())
    }

    async fn get_state(
        &self,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<HashMap<&'static str, Value<'static>>> {
        self.admit(&h).await?;
        let count = self
            .0
            .accounts
            .with(|a| i32::try_from(a.saved.accounts.len()).unwrap_or(i32::MAX))
            .await;
        let (syncing, last_error, last_sync_ms) = self
            .0
            .state
            .with(|s| (s.syncing, s.last_error.clone(), s.last_sync_ms))
            .await;
        Ok(HashMap::from([
            ("accountCount", Value::from(count)),
            ("syncing", Value::from(syncing)),
            ("lastError", Value::from(last_error)),
            ("lastSyncMs", Value::from(last_sync_ms)),
        ]))
    }

    #[zbus(signal)]
    async fn accounts_changed(e: &SignalEmitter<'_>) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn sync_finished(e: &SignalEmitter<'_>, account_id: &str) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn account_discovered(e: &SignalEmitter<'_>, account_id: &str) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn account_discovery_failed(
        e: &SignalEmitter<'_>,
        account_id: &str,
        reason: &str,
    ) -> zbus::Result<()>;
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let dir = shell_data().join("marathon");
    let book = Shared::new(Book::open(dir.join("contacts")));
    let accounts = Shared::new(Accounts::open(
        dir.join("dav-accounts.json"),
        &marathon_rt::dirs::config().join("Marathon OS/Marathon Shell.conf"),
    ));
    let events = Shared::new(Events::open(&dir.join("dav-events.db"))?);
    let bus = io::session_bus().await?;
    let (keyring, wake) = async_channel::bounded(1);
    let core = Core {
        bus: bus.clone(),
        book,
        accounts,
        events,
        state: Shared::new(SyncState::default()),
        agent: webdav::agent(),
        keyring,
    };
    bus.object_server()
        .at(CONTACTS_PATH, ContactsService(core.clone()))
        .await?;
    bus.object_server()
        .at(DAV_PATH, DavService(core.clone()))
        .await?;
    bus.request_name(BUS_NAME).await?;
    io::spawn(keep_secrets(core.clone(), wake));
    loop {
        Timer::after(SYNC_EVERY).await;
        core.sync().await;
    }
}

fn main() -> ExitCode {
    match async_io::block_on(run()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            log::warn("marathon-davd", e);
            ExitCode::FAILURE
        }
    }
}
