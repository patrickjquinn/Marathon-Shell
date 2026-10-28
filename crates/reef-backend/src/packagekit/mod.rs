// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Package operations through `PackageKit`.
//!
//! On Sailfish, `PackageKit` (zypp backend) is the supported way for an app to
//! install packages; the Chum GUI uses it through PackageKit-Qt, and the
//! Chum GUI installer through `pkcon`. Reef talks to the same daemon
//! directly over D-Bus with zbus.
//!
//! [`PackageManager`] is the seam: the store logic is written against it,
//! [`dbus::PackageKitClient`] implements it for the real daemon, and tests
//! use a fake (or the mock `PackageKit` in `tests/packagekit_mock.rs`).

pub mod dbus;
mod types;

use std::fmt;

pub use types::{
    filter_bits, Exit, Filter, Info, Overall, PackageId, PackageInfo, Progress, Status,
    SteadyProgress, TRANSACTION_FLAG_ONLY_TRUSTED, TRANSACTION_FLAG_SIMULATE,
};

#[derive(Debug)]
pub enum Error {
    /// Talking to `PackageKit` failed (daemon missing, access denied, ...).
    DBus(zbus::Error),
    /// The transaction ran and did not succeed.
    Transaction {
        exit: Exit,
        /// `PkErrorEnum` value and `PackageKit`'s message, when it sent one.
        error: Option<(u32, String)>,
    },
    /// A name did not resolve to any package.
    NotFound(String),
    /// The repository's signed metadata did not check out
    /// ([`crate::metadata`]): nothing was installed.
    Untrusted(String),
    /// What the transaction would do now is not what the person agreed to
    /// (the repository changed in between): nothing was done, and the
    /// person is asked again with the new list.
    PlanChanged,
    /// Reef did not install the package (no record of it, and `PackageKit`
    /// does not name Reef's repository as its origin), so Reef leaves it
    /// alone.
    NotReefs(String),
    /// None of the builds of a part the app needs (the catalogue's
    /// variants group, named) runs on this phone's processor.
    NoBuild(String, String),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::DBus(e) => write!(f, "PackageKit unavailable: {e}"),
            // PK_ERROR_ENUM_DEP_RESOLUTION_FAILED: what the person can do
            // about it, not the number (a Store user saw "error 13").
            Error::Transaction {
                error: Some((13, details)),
                ..
            } => write!(
                f,
                "Other installed software needs this package, so it was left in place. {details}"
            ),
            Error::Transaction {
                exit,
                error: Some((code, details)),
            } => write!(f, "{exit:?} (error {code}): {details}"),
            Error::Transaction { exit, error: None } => write!(f, "transaction ended {exit:?}"),
            Error::NotFound(name) => write!(f, "no package named {name}"),
            Error::Untrusted(why) => write!(f, "Nothing was installed: {why}."),
            Error::PlanChanged => write!(
                f,
                "What this would install or remove changed since you looked, so nothing was done. Please look again."
            ),
            Error::NotReefs(name) => write!(
                f,
                "Reef did not install {name}, so it does not remove it. Remove it where it came from."
            ),
            Error::NoBuild(name, group) => write!(
                f,
                "{name} needs one of {group}, and none of them is built for this phone's processor."
            ),
        }
    }
}

impl std::error::Error for Error {}

impl From<zbus::Error> for Error {
    fn from(e: zbus::Error) -> Self {
        Error::DBus(e)
    }
}

impl From<zbus::fdo::Error> for Error {
    fn from(e: zbus::fdo::Error) -> Self {
        Error::DBus(e.into())
    }
}

pub type Result<T> = std::result::Result<T, Error>;

/// What the store needs from a package manager.
///
/// Installs and updates always run with `ONLY_TRUSTED`, so a package whose
/// RPM signature does not verify is refused by `PackageKit` itself.
#[allow(
    async_fn_in_trait,
    reason = "used with concrete types only; no Send bound needed"
)]
pub trait PackageManager {
    /// Resolves package names to ids, filtered by `filters`.
    async fn resolve(&self, names: &[&str], filters: &[Filter]) -> Result<Vec<PackageInfo>>;

    async fn install(&self, ids: &[&str], progress: &mut dyn FnMut(Progress)) -> Result<()>;

    async fn update(&self, ids: &[&str], progress: &mut dyn FnMut(Progress)) -> Result<()>;

    /// Removes packages. Fails if other installed packages depend on them
    /// (removing Keel must not silently take every Keel app with it), and
    /// never autoremoves, which could take out packages the user relies on.
    async fn remove(&self, ids: &[&str], progress: &mut dyn FnMut(Progress)) -> Result<()>;

    /// Available updates for everything installed, from every repository.
    async fn get_updates(&self) -> Result<Vec<PackageInfo>>;

    /// Packages whose names contain any of `values` (`SearchNames`).
    async fn search_names(&self, values: &[&str], filters: &[Filter]) -> Result<Vec<PackageInfo>>;

    /// The installed packages that `ids` need directly (`DependsOn`,
    /// installed only, not recursive).
    async fn depends_on(&self, ids: &[&str]) -> Result<Vec<PackageInfo>>;

    /// The installed packages that need `ids` directly (`RequiredBy`,
    /// installed only, not recursive).
    async fn required_by(&self, ids: &[&str]) -> Result<Vec<PackageInfo>>;

    /// Refreshes one repository's metadata (`RepoSetData(alias,
    /// "refresh-now", "true")`), as the Chum GUI installer does.
    async fn refresh_repo(&self, alias: &str) -> Result<()>;

    /// Makes `PackageKit` read what is installed afresh: its view goes stale
    /// when packages change outside it (rpm -U, another tool), and neither
    /// a resolve nor a repository refresh reads the RPM database again (on
    /// the Jolla Phone, 12 October 2026). `SuggestDaemonQuit` lets the
    /// daemon exit once idle (it never stops a transaction); the next call
    /// starts it again with a new view.
    async fn reload_installed(&self) -> Result<()>;

    /// What [`install`](Self::install) would do, doing nothing
    /// ([`TRANSACTION_FLAG_SIMULATE`]): every package the transaction would
    /// install, update or remove, dependencies included.
    async fn simulate_install(&self, ids: &[&str]) -> Result<Vec<PackageInfo>>;

    /// What [`update`](Self::update) would do, doing nothing.
    async fn simulate_update(&self, ids: &[&str]) -> Result<Vec<PackageInfo>>;

    /// What [`remove`](Self::remove) would do, doing nothing (with the same
    /// rules: fails when other installed software needs a package).
    async fn simulate_remove(&self, ids: &[&str]) -> Result<Vec<PackageInfo>>;

    /// Download sizes in bytes (`GetDetails`), for the ids `PackageKit`
    /// has a size for. Informational: an empty answer is not an error.
    async fn download_sizes(&self, ids: &[&str]) -> Result<Vec<(String, u64)>> {
        let _ = ids;
        Ok(Vec::new())
    }
}

/// Updates Reef may offer: only packages coming from Reef's own repository.
/// Reef must never update system packages; that is Settings' job, and doing
/// it from a third-party store is how phones get half-upgraded.
pub fn reef_updates(updates: &[PackageInfo], alias: &str) -> Vec<PackageInfo> {
    updates
        .iter()
        .filter(|p| p.id.from_repo(alias))
        .cloned()
        .collect()
}

/// Resolves `name` to the id to install: the newest available build from
/// Reef's repository.
pub async fn resolve_installable<P: PackageManager>(
    pm: &P,
    name: &str,
    alias: &str,
) -> Result<PackageId> {
    let found = pm
        .resolve(&[name], &[Filter::NotInstalled, Filter::Newest])
        .await?;
    found
        .into_iter()
        .map(|p| p.id)
        .find(|id| id.name == name && id.from_repo(alias))
        .ok_or_else(|| Error::NotFound(name.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pkg(id: &str) -> PackageInfo {
        PackageInfo {
            info: Info::Normal,
            id: PackageId::parse(id).unwrap(),
            summary: String::new(),
        }
    }

    #[test]
    fn only_reef_updates_are_offered() {
        let updates = [
            pkg("shipwright-keel-silica;0.2.0-1;aarch64;shipwright-reef"),
            pkg("sailfish-browser;3.0-1;aarch64;jolla"),
            pkg("qt6-qtbase;6.8.3-1;aarch64;sailfishos-chum"),
        ];
        let reef = reef_updates(&updates, "shipwright-reef");
        assert_eq!(reef.len(), 1);
        assert_eq!(reef[0].id.name, "shipwright-keel-silica");
    }
}
