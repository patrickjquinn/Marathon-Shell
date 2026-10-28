// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

//! [`PackageManager`] over `PackageKit`'s D-Bus API (zbus 5).
//!
//! Each operation is one `PackageKit` transaction: `CreateTransaction` on the
//! daemon, subscribe to the transaction object's signals, call the method,
//! then read `Package`, `ItemProgress`, `ErrorCode`, `Details` and property
//! changes until `Finished`. Subscribing before the call matters: `PackageKit` may
//! emit results before the method call returns.
//!
//! Any client on the system bus can emit a signal with the transaction's
//! object path, so the subscription matches the daemon's unique bus name as
//! well, and every message is checked against it again: a forged `Finished`
//! or `Package` from another connection is ignored. A transaction that
//! stays silent for [`DEFAULT_IDLE_TIMEOUT`] fails instead of blocking the
//! worker (and the UI's busy state) forever.

use std::collections::HashMap;
use std::time::Duration;

use futures_lite::StreamExt;
use zbus::message::Type;
use zbus::proxy::CacheProperties;
use zbus::zvariant::{OwnedObjectPath, OwnedValue};
use zbus::{Connection, MatchRule, Message, MessageStream};

use super::types::percentage;
use super::{
    filter_bits, Error, Exit, Filter, Overall, PackageId, PackageInfo, PackageManager, Progress,
    Result, Status, TRANSACTION_FLAG_ONLY_TRUSTED, TRANSACTION_FLAG_SIMULATE,
};

pub const SERVICE: &str = "org.freedesktop.PackageKit";

/// How long a transaction may go without a signal before it is abandoned.
/// `PackageKit` reports progress continuously during downloads and installs,
/// so ten silent minutes means it is stuck.
pub const DEFAULT_IDLE_TIMEOUT: Duration = Duration::from_secs(600);
const TRANSACTION_IFACE: &str = "org.freedesktop.PackageKit.Transaction";

#[zbus::proxy(
    interface = "org.freedesktop.PackageKit",
    default_service = "org.freedesktop.PackageKit",
    default_path = "/org/freedesktop/PackageKit",
    gen_blocking = false
)]
trait PackageKit {
    fn create_transaction(&self) -> zbus::Result<OwnedObjectPath>;
    fn suggest_daemon_quit(&self) -> zbus::Result<()>;
}

#[zbus::proxy(
    interface = "org.freedesktop.PackageKit.Transaction",
    default_service = "org.freedesktop.PackageKit",
    gen_blocking = false
)]
trait Transaction {
    fn resolve(&self, filter: u64, packages: &[&str]) -> zbus::Result<()>;
    fn install_packages(&self, transaction_flags: u64, package_ids: &[&str]) -> zbus::Result<()>;
    fn update_packages(&self, transaction_flags: u64, package_ids: &[&str]) -> zbus::Result<()>;
    fn remove_packages(
        &self,
        transaction_flags: u64,
        package_ids: &[&str],
        allow_deps: bool,
        autoremove: bool,
    ) -> zbus::Result<()>;
    fn get_updates(&self, filter: u64) -> zbus::Result<()>;
    fn search_names(&self, filter: u64, values: &[&str]) -> zbus::Result<()>;
    fn depends_on(&self, filter: u64, package_ids: &[&str], recursive: bool) -> zbus::Result<()>;
    fn required_by(&self, filter: u64, package_ids: &[&str], recursive: bool) -> zbus::Result<()>;
    fn repo_set_data(&self, repo_id: &str, parameter: &str, value: &str) -> zbus::Result<()>;
    fn get_details(&self, package_ids: &[&str]) -> zbus::Result<()>;
}

/// The operations Reef runs, one per transaction.
enum Op<'a> {
    Resolve(u64, &'a [&'a str]),
    Install(&'a [&'a str]),
    Update(&'a [&'a str]),
    Remove(&'a [&'a str]),
    GetUpdates,
    SearchNames(u64, &'a [&'a str]),
    DependsOn(&'a [&'a str]),
    RequiredBy(&'a [&'a str]),
    RefreshRepo(&'a str),
    /// Install, update or remove with `SIMULATE`: what would happen.
    SimulateInstall(&'a [&'a str]),
    SimulateUpdate(&'a [&'a str]),
    SimulateRemove(&'a [&'a str]),
    Details(&'a [&'a str]),
}

/// What one transaction reported.
#[derive(Default)]
struct Outcome {
    packages: Vec<PackageInfo>,
    /// `Details`: package id and size in bytes.
    sizes: Vec<(String, u64)>,
}

/// A `PackageKit` client on a D-Bus connection (the system bus on a phone).
#[derive(Clone)]
pub struct PackageKitClient {
    conn: Connection,
    idle_timeout: Duration,
}

impl PackageKitClient {
    /// Connects to the system bus, where `PackageKit` lives.
    ///
    /// Whether a sandboxed or unprivileged app may start transactions is
    /// decided by the phone's D-Bus policy; see the backend README ("Needs
    /// device verification").
    pub async fn system() -> Result<Self> {
        Ok(Self::new(Connection::system().await?))
    }

    /// Uses an existing connection (tests use a private bus).
    pub fn new(conn: Connection) -> Self {
        Self {
            conn,
            idle_timeout: DEFAULT_IDLE_TIMEOUT,
        }
    }

    /// Replaces [`DEFAULT_IDLE_TIMEOUT`] (tests use a short one).
    #[must_use]
    pub fn with_idle_timeout(mut self, idle_timeout: Duration) -> Self {
        self.idle_timeout = idle_timeout;
        self
    }

    async fn run(&self, op: Op<'_>, progress: &mut dyn FnMut(Progress)) -> Result<Outcome> {
        let daemon = PackageKitProxy::builder(&self.conn)
            .cache_properties(CacheProperties::No)
            .build()
            .await?;
        let path = daemon.create_transaction().await?;
        // The daemon's unique name, so only it can speak for the transaction.
        let owner = zbus::fdo::DBusProxy::new(&self.conn)
            .await?
            .get_name_owner(
                zbus::names::BusName::from_static_str(SERVICE).map_err(zbus::Error::from)?,
            )
            .await?;

        let rule = MatchRule::builder()
            .msg_type(Type::Signal)
            .sender(owner.clone())?
            .path(path.clone())?
            .build();
        let mut signals = MessageStream::for_match_rule(rule, &self.conn, None).await?;

        let tx = TransactionProxy::builder(&self.conn)
            .path(path)?
            .cache_properties(CacheProperties::No)
            .build()
            .await?;
        let trusted = TRANSACTION_FLAG_ONLY_TRUSTED;
        match op {
            Op::Resolve(filter, names) => tx.resolve(filter, names).await?,
            Op::Install(ids) => tx.install_packages(trusted, ids).await?,
            Op::Update(ids) => tx.update_packages(trusted, ids).await?,
            Op::Remove(ids) => tx.remove_packages(0, ids, false, false).await?,
            Op::GetUpdates => tx.get_updates(filter_bits(&[Filter::None])).await?,
            Op::SearchNames(filter, values) => tx.search_names(filter, values).await?,
            Op::DependsOn(ids) => {
                tx.depends_on(filter_bits(&[Filter::Installed]), ids, false)
                    .await?;
            }
            Op::RequiredBy(ids) => {
                tx.required_by(filter_bits(&[Filter::Installed]), ids, false)
                    .await?;
            }
            Op::RefreshRepo(alias) => tx.repo_set_data(alias, "refresh-now", "true").await?,
            // The same flags as the real thing, plus SIMULATE.
            Op::SimulateInstall(ids) => {
                tx.install_packages(trusted | TRANSACTION_FLAG_SIMULATE, ids)
                    .await?;
            }
            Op::SimulateUpdate(ids) => {
                tx.update_packages(trusted | TRANSACTION_FLAG_SIMULATE, ids)
                    .await?;
            }
            Op::SimulateRemove(ids) => {
                tx.remove_packages(TRANSACTION_FLAG_SIMULATE, ids, false, false)
                    .await?;
            }
            Op::Details(ids) => tx.get_details(ids).await?,
        }

        let mut state = TransactionState {
            sender: Some(owner.to_string()),
            ..TransactionState::default()
        };
        loop {
            let next = futures_lite::future::or(async { Some(signals.next().await) }, async {
                async_io::Timer::after(self.idle_timeout).await;
                None
            });
            match next.await {
                Some(Some(msg)) => {
                    if let Some(done) = state.handle(&msg?, progress) {
                        return done;
                    }
                }
                Some(None) => break,
                None => {
                    return Err(Error::Transaction {
                        exit: Exit::Other(0),
                        error: Some((
                            0,
                            format!(
                                "PackageKit sent nothing for {} s; giving up",
                                self.idle_timeout.as_secs()
                            ),
                        )),
                    })
                }
            }
        }
        Err(Error::Transaction {
            exit: Exit::Other(0),
            error: Some((0, "PackageKit disconnected mid-transaction".into())),
        })
    }
}

/// Accumulates one transaction's signals.
#[derive(Default)]
struct TransactionState {
    /// The daemon's unique name; messages from anyone else are ignored.
    sender: Option<String>,
    packages: Vec<PackageInfo>,
    sizes: Vec<(String, u64)>,
    error: Option<(u32, String)>,
    status: Option<Status>,
    overall: Overall,
}

impl TransactionState {
    /// Handles one signal; returns the result once the transaction ends.
    fn handle(
        &mut self,
        msg: &Message,
        progress: &mut dyn FnMut(Progress),
    ) -> Option<Result<Outcome>> {
        let header = msg.header();
        if let Some(expected) = &self.sender {
            if header.sender().map(zbus::names::UniqueName::as_str) != Some(expected.as_str()) {
                return None;
            }
        }
        let member = header.member()?.as_str();
        let iface = header.interface().map(zbus::names::InterfaceName::as_str);
        let body = msg.body();
        match (iface, member) {
            (Some(TRANSACTION_IFACE), "Package") => {
                if let Ok((info, id, summary)) = body.deserialize::<(u32, String, String)>() {
                    self.overall.package(info.into(), &id);
                    if let Some(id) = PackageId::parse(&id) {
                        self.packages.push(PackageInfo {
                            info: info.into(),
                            id,
                            summary,
                        });
                    }
                }
            }
            (Some(TRANSACTION_IFACE), "ItemProgress") => {
                // One package's own 0 to 100, once to download it and once
                // to install it: folded into the transaction's (Overall).
                if let Ok((id, status, pct)) = body.deserialize::<(String, u32, u32)>() {
                    let status: Status = status.into();
                    let overall = self.overall.item(&id, status, percentage(pct));
                    progress(Progress {
                        percentage: overall,
                        status,
                        item: Some(id),
                    });
                }
            }
            (Some(TRANSACTION_IFACE), "Details") => {
                if let Some(size) = details_size(&body) {
                    self.sizes.push(size);
                }
            }
            (Some(TRANSACTION_IFACE), "ErrorCode") => {
                if let Ok(err) = body.deserialize::<(u32, String)>() {
                    self.error = Some(err);
                }
            }
            (Some(TRANSACTION_IFACE), "Finished") => {
                let (exit, _runtime) = body.deserialize::<(u32, u32)>().ok()?;
                let exit = Exit::from(exit);
                return Some(if exit == Exit::Success {
                    Ok(Outcome {
                        packages: std::mem::take(&mut self.packages),
                        sizes: std::mem::take(&mut self.sizes),
                    })
                } else {
                    Err(Error::Transaction {
                        exit,
                        error: self.error.take(),
                    })
                });
            }
            (Some(TRANSACTION_IFACE), "Destroy") => {
                return Some(Err(Error::Transaction {
                    exit: Exit::Other(0),
                    error: self
                        .error
                        .take()
                        .or(Some((0, "transaction destroyed before finishing".into()))),
                }));
            }
            (Some("org.freedesktop.DBus.Properties"), "PropertiesChanged") => {
                let Ok((_, changed, _)) =
                    body.deserialize::<(String, HashMap<String, OwnedValue>, Vec<String>)>()
                else {
                    return None;
                };
                let get = |k: &str| changed.get(k).and_then(|v| u32::try_from(&**v).ok());
                // The transaction's own Percentage restarts for every
                // preparation step: only its Status is used (Overall).
                if let Some(s) = get("Status") {
                    self.status = Some(s.into());
                    progress(Progress {
                        percentage: self.overall.value(),
                        status: self.status.unwrap_or(Status::Other(0)),
                        item: None,
                    });
                }
            }
            _ => {}
        }
        None
    }
}

impl PackageManager for PackageKitClient {
    async fn resolve(&self, names: &[&str], filters: &[Filter]) -> Result<Vec<PackageInfo>> {
        self.packages(Op::Resolve(filter_bits(filters), names))
            .await
    }

    async fn install(&self, ids: &[&str], progress: &mut dyn FnMut(Progress)) -> Result<()> {
        self.run(Op::Install(ids), progress).await.map(drop)
    }

    async fn update(&self, ids: &[&str], progress: &mut dyn FnMut(Progress)) -> Result<()> {
        self.run(Op::Update(ids), progress).await.map(drop)
    }

    async fn remove(&self, ids: &[&str], progress: &mut dyn FnMut(Progress)) -> Result<()> {
        self.run(Op::Remove(ids), progress).await.map(drop)
    }

    async fn get_updates(&self) -> Result<Vec<PackageInfo>> {
        self.packages(Op::GetUpdates).await
    }

    async fn search_names(&self, values: &[&str], filters: &[Filter]) -> Result<Vec<PackageInfo>> {
        self.packages(Op::SearchNames(filter_bits(filters), values))
            .await
    }

    async fn depends_on(&self, ids: &[&str]) -> Result<Vec<PackageInfo>> {
        self.packages(Op::DependsOn(ids)).await
    }

    async fn required_by(&self, ids: &[&str]) -> Result<Vec<PackageInfo>> {
        self.packages(Op::RequiredBy(ids)).await
    }

    async fn refresh_repo(&self, alias: &str) -> Result<()> {
        self.run(Op::RefreshRepo(alias), &mut |_| {})
            .await
            .map(drop)
    }

    async fn reload_installed(&self) -> Result<()> {
        let daemon = PackageKitProxy::new(&self.conn).await?;
        daemon.suggest_daemon_quit().await?;
        // Wait for it to go, at most 15 s: if another transaction keeps it
        // busy longer, carry on (the retry then fails as before).
        let bus = zbus::fdo::DBusProxy::new(&self.conn).await?;
        let name = zbus::names::BusName::try_from("org.freedesktop.PackageKit")
            .map_err(|e| Error::DBus(zbus::Error::from(e)))?;
        for _ in 0..75 {
            if !bus.name_has_owner(name.clone()).await? {
                break;
            }
            async_io::Timer::after(Duration::from_millis(200)).await;
        }
        Ok(())
    }

    async fn simulate_install(&self, ids: &[&str]) -> Result<Vec<PackageInfo>> {
        self.packages(Op::SimulateInstall(ids)).await
    }

    async fn simulate_update(&self, ids: &[&str]) -> Result<Vec<PackageInfo>> {
        self.packages(Op::SimulateUpdate(ids)).await
    }

    async fn simulate_remove(&self, ids: &[&str]) -> Result<Vec<PackageInfo>> {
        self.packages(Op::SimulateRemove(ids)).await
    }

    async fn download_sizes(&self, ids: &[&str]) -> Result<Vec<(String, u64)>> {
        if ids.is_empty() {
            return Ok(Vec::new());
        }
        Ok(self.run(Op::Details(ids), &mut |_| {}).await?.sizes)
    }
}

impl PackageKitClient {
    /// A transaction with no progress to show, for its packages.
    async fn packages(&self, op: Op<'_>) -> Result<Vec<PackageInfo>> {
        Ok(self.run(op, &mut |_| {}).await?.packages)
    }
}

/// The package id and size of a `Details` signal: `a{sv}` since
/// `PackageKit` 1.1 (`package-id`, and `download-size` or `size`), or the
/// older `(s s u s s t)` with the size last.
fn details_size(body: &zbus::message::Body) -> Option<(String, u64)> {
    if let Ok((map,)) = body.deserialize::<(HashMap<String, OwnedValue>,)>() {
        let id = map
            .get("package-id")
            .and_then(|v| <&str>::try_from(&**v).ok())?
            .to_owned();
        let size = ["download-size", "size"]
            .iter()
            .find_map(|k| map.get(*k).and_then(|v| u64::try_from(&**v).ok()))?;
        return Some((id, size));
    }
    let (id, _, _, _, _, size) = body
        .deserialize::<(String, String, u32, String, String, u64)>()
        .ok()?;
    Some((id, size))
}
