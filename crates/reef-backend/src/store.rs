// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The store view the UI shows: catalogue entries joined with what
//! `PackageKit` says is installed and upgradable, and the store's install,
//! update and removal, each of which runs only as the person agreed to it
//! ([`crate::plan`]).

use std::collections::BTreeSet;
use std::io::Write;
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};

use crate::catalogue::{Catalogue, Package};
use crate::packagekit::{
    reef_updates, resolve_installable, Error, Filter, Info, PackageId, PackageInfo, PackageManager,
    Progress, Result,
};
use crate::plan::{self, Action, Change, Plan, Reason};
use crate::release::SailfishRelease;

/// Where a catalogue package stands on this phone.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InstallState {
    NotInstalled,
    Installed {
        version: String,
    },
    UpdateAvailable {
        installed: String,
        available: String,
    },
}

/// One row of the catalogue page.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry<'a> {
    pub package: &'a Package,
    pub state: InstallState,
}

/// Joins visible catalogue packages with installed and update lists.
/// Pure, so the rules are unit-tested without a bus.
pub fn entries<'a>(
    catalogue: &'a Catalogue,
    release: &SailfishRelease,
    installed: &[PackageInfo],
    updates: &[PackageInfo],
) -> Vec<Entry<'a>> {
    catalogue
        .visible(release)
        .into_iter()
        .map(|package| {
            let inst = installed
                .iter()
                .find(|p| p.id.name == package.name && p.id.is_installed());
            let upd = updates.iter().find(|p| p.id.name == package.name);
            let state = match (inst, upd) {
                (None, _) => InstallState::NotInstalled,
                (Some(i), Some(u)) => InstallState::UpdateAvailable {
                    installed: i.id.version.clone(),
                    available: u.id.version.clone(),
                },
                (Some(i), None) => InstallState::Installed {
                    version: i.id.version.clone(),
                },
            };
            Entry { package, state }
        })
        .collect()
}

/// The packages Reef itself installed, kept on the phone so ownership does
/// not depend on the Reef repository still offering them (disabled
/// repository, withdrawn build): `installed.json`, the RPM names the person
/// installed, and beside it `pulled-in.json`, what came with them from the
/// Reef repository (the earbuds service with the earbuds app). Each is one
/// JSON array, written atomically after each successful install, update or
/// removal.
///
/// Only the person's account may read or change them (directory 0700,
/// files 0600): a list another user could write would let it make Reef
/// remove a package. The phone's app launcher runs Reef with a umask that
/// made them world-writable; [`repair_permissions`](Self::repair_permissions)
/// fixes those at start.
#[derive(Debug, Clone)]
pub struct InstallLedger {
    path: PathBuf,
}

/// The ledger's directory and files: the owner only.
const PRIVATE_DIR: u32 = 0o700;
const PRIVATE_FILE: u32 = 0o600;

impl InstallLedger {
    pub fn new(path: impl Into<PathBuf>) -> Self {
        Self { path: path.into() }
    }

    /// `$XDG_DATA_HOME/shipwright-reef/installed.json`, or under
    /// `~/.local/share`.
    pub fn default_path() -> Option<PathBuf> {
        let env = |v: &str| {
            std::env::var_os(v)
                .filter(|x| !x.is_empty())
                .map(PathBuf::from)
        };
        let base = env("XDG_DATA_HOME").or_else(|| env("HOME").map(|h| h.join(".local/share")))?;
        Some(base.join("shipwright-reef/installed.json"))
    }

    fn pulled_in_path(&self) -> PathBuf {
        self.path.with_file_name("pulled-in.json")
    }

    /// The names in `path`: none when the file does not exist yet. A file
    /// that exists but cannot be read or parsed is an error, never an empty
    /// list, so [`update`](Self::update) does not write a list built from
    /// nothing over the person's records.
    fn load(path: &Path) -> std::io::Result<BTreeSet<String>> {
        match std::fs::read(path) {
            Ok(bytes) => serde_json::from_slice(&bytes).map_err(|e| {
                std::io::Error::new(
                    std::io::ErrorKind::InvalidData,
                    format!("{}: {e}", path.display()),
                )
            }),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(BTreeSet::new()),
            Err(e) => Err(e),
        }
    }

    /// [`load`](Self::load) for showing what Reef installed: an unreadable
    /// file shows as empty, and stays as it is on disk.
    fn read(path: &Path) -> BTreeSet<String> {
        Self::load(path).unwrap_or_default()
    }

    /// What the person installed through Reef; empty when the file is
    /// missing or unreadable.
    pub fn names(&self) -> BTreeSet<String> {
        Self::read(&self.path)
    }

    /// What came with those from the Reef repository.
    pub fn pulled_in(&self) -> BTreeSet<String> {
        Self::read(&self.pulled_in_path())
    }

    /// Everything Reef installed: [`names`](Self::names) and
    /// [`pulled_in`](Self::pulled_in).
    pub fn all(&self) -> BTreeSet<String> {
        let mut all = self.names();
        all.extend(self.pulled_in());
        all
    }

    /// Changes the list in `path` with `f` and writes it back atomically.
    /// Refuses, leaving the file alone, when it cannot be read or parsed.
    fn update(path: &Path, f: impl FnOnce(&mut BTreeSet<String>)) -> std::io::Result<()> {
        let mut names = Self::load(path)?;
        let before = names.clone();
        f(&mut names);
        if names == before && path.exists() {
            return Ok(());
        }
        let bytes = serde_json::to_vec(&names)?;
        if let Some(dir) = path.parent() {
            std::fs::DirBuilder::new()
                .recursive(true)
                .mode(PRIVATE_DIR)
                .create(dir)?;
            set_mode(dir, PRIVATE_DIR)?;
        }
        // A name unique to this process: the app and the background check
        // may write at the same time.
        let tmp = path.with_extension(format!("json.{}.tmp", std::process::id()));
        let written = std::fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(PRIVATE_FILE)
            .open(&tmp)
            .and_then(|mut f| {
                // An old temporary file of the same name keeps its mode.
                f.set_permissions(std::fs::Permissions::from_mode(PRIVATE_FILE))?;
                f.write_all(&bytes)
            });
        if let Err(e) = written {
            let _ = std::fs::remove_file(&tmp);
            return Err(e);
        }
        std::fs::rename(tmp, path)
    }

    /// Records that the person installed `name` (it is no longer only
    /// pulled in).
    pub fn record(&self, name: &str) -> std::io::Result<()> {
        Self::update(&self.path, |n| {
            n.insert(name.to_string());
        })?;
        Self::update(&self.pulled_in_path(), |n| {
            n.remove(name);
        })
    }

    /// Records what an install or update brought from the Reef repository
    /// along with what was asked for.
    pub fn record_pulled_in(&self, names: &[&str]) -> std::io::Result<()> {
        if names.is_empty() {
            return Ok(());
        }
        let asked = self.names();
        Self::update(&self.pulled_in_path(), |n| {
            n.extend(
                names
                    .iter()
                    .filter(|x| !asked.contains(**x))
                    .map(|x| (*x).to_string()),
            );
        })
    }

    pub fn forget(&self, name: &str) -> std::io::Result<()> {
        Self::update(&self.path, |n| {
            n.remove(name);
        })?;
        Self::update(&self.pulled_in_path(), |n| {
            n.remove(name);
        })
    }

    /// Makes the ledger's directory 0700 and its files 0600 where they are
    /// anything else (Reef 27 and earlier left them world-writable).
    pub fn repair_permissions(&self) -> std::io::Result<()> {
        if let Some(dir) = self.path.parent().filter(|d| d.is_dir()) {
            set_mode(dir, PRIVATE_DIR)?;
        }
        for file in [self.path.clone(), self.pulled_in_path()] {
            if file.is_file() {
                set_mode(&file, PRIVATE_FILE)?;
            }
        }
        Ok(())
    }
}

/// Sets `path`'s permission bits to `mode` when they differ.
fn set_mode(path: &Path, mode: u32) -> std::io::Result<()> {
    let meta = std::fs::metadata(path)?;
    if meta.permissions().mode() & 0o7777 != mode {
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode))?;
    }
    Ok(())
}

/// Store operations on top of a [`PackageManager`], scoped to Reef's repo.
pub struct Store<P> {
    pub pm: P,
    pub alias: String,
    /// What Reef installed; see [`InstallLedger`]. Without one, only
    /// packages `PackageKit` says came from Reef's repository are Reef's to
    /// remove.
    pub ledger: Option<InstallLedger>,
    /// Checks the repository's signed metadata before anything is
    /// installed or updated ([`crate::metadata`]); `None` skips it (tests,
    /// and hosts without the phone's paths).
    pub metadata: Option<crate::metadata::MetadataCheck>,
    /// This phone's CPU features, which pick the build of an app's parts
    /// made for several processors ([`Catalogue::variant_picks`]); `None`
    /// where unknown. [`crate::catalogue::cpu_features`] by default.
    pub cpu: Option<BTreeSet<String>>,
}

/// A transaction (or its simulation) that failed because `PackageKit`'s view
/// of the repository is stale: the repository no longer has the file the
/// phone's cached metadata names (`PkErrorEnum` package download failed,
/// repository not available, file not found, no more mirrors), or the
/// package resolved a moment ago is not in its pool (package not found:
/// after a removal, a reinstall of the same app failed so until a refresh,
/// lifecycle test, 12 October 2026). Refreshing fixes it.
fn stale_metadata(e: &Error) -> bool {
    matches!(
        e,
        Error::Transaction {
            error: Some((8 | 10 | 37 | 42 | 43, _)),
            ..
        }
    )
}

/// `PackageKit` refused a removal because something staying needs a
/// package in it (`PkErrorEnum` dependency resolution failed).
fn still_needed(e: &Error) -> bool {
    matches!(
        e,
        Error::Transaction {
            error: Some((13, _)),
            ..
        }
    )
}

/// The (name, change) pairs a simulation announces, an upgrade's old copy
/// left out (its install or update stands for it).
fn simulated_changes(simulated: &[PackageInfo], default: Change) -> Vec<(String, Change)> {
    let mut out: Vec<(String, Change)> = Vec::new();
    for p in simulated {
        let change = Change::from_info(p.info, default);
        match out.iter_mut().find(|(n, _)| *n == p.id.name) {
            Some(existing) if existing.1 == Change::Remove => existing.1 = change,
            Some(_) => {}
            None => out.push((p.id.name.clone(), change)),
        }
    }
    out
}

impl<P: PackageManager> Store<P> {
    pub fn new(pm: P, alias: impl Into<String>) -> Self {
        Self {
            pm,
            alias: alias.into(),
            ledger: None,
            metadata: None,
            cpu: crate::catalogue::cpu_features().cloned(),
        }
    }

    /// Picks variant builds for a phone with these CPU features instead
    /// of this one's (tests, tools).
    #[must_use]
    pub fn with_cpu_features(mut self, cpu: Option<BTreeSet<String>>) -> Self {
        self.cpu = cpu;
        self
    }

    /// Verifies the repository metadata (signature, no rollback) before
    /// every install and update.
    #[must_use]
    pub fn with_metadata_check(mut self, check: Option<crate::metadata::MetadataCheck>) -> Self {
        self.metadata = check;
        self
    }

    fn check_metadata(&self) -> Result<()> {
        match &self.metadata {
            Some(check) => check
                .verify()
                .map(drop)
                .map_err(|e| Error::Untrusted(e.to_string())),
            None => Ok(()),
        }
    }

    /// Records installs in, and reads ownership from, `ledger`.
    #[must_use]
    pub fn with_ledger(mut self, ledger: Option<InstallLedger>) -> Self {
        self.ledger = ledger;
        self
    }

    /// Everything the ledger says Reef installed.
    fn recorded(&self) -> BTreeSet<String> {
        self.ledger
            .as_ref()
            .map(InstallLedger::all)
            .unwrap_or_default()
    }

    /// What the person installed through Reef for itself.
    fn asked_for(&self) -> BTreeSet<String> {
        self.ledger
            .as_ref()
            .map(InstallLedger::names)
            .unwrap_or_default()
    }

    /// Installed packages among the catalogue's names that are Reef's: see
    /// [`reef_owned`]. A catalogue entry that names an OS package (the
    /// catalogue is not signed) does not make Reef show it as installed.
    pub async fn installed(&self, catalogue: &Catalogue) -> Result<Vec<PackageInfo>> {
        let names: Vec<&str> = catalogue.packages.iter().map(|p| p.name.as_str()).collect();
        if names.is_empty() {
            return Ok(Vec::new());
        }
        let found = resolve_with_offers(&self.pm, &names).await?;
        Ok(reef_owned(&found, &self.alias, &self.recorded()))
    }

    /// The names among `installed` (from [`installed`](Self::installed))
    /// that Reef may remove: all but a `harbour-` app Reef cannot show it
    /// installed itself, as [`reef_app_removable`] says.
    pub fn removable(&self, installed: &[PackageInfo]) -> Vec<String> {
        let recorded = self.recorded();
        installed
            .iter()
            .filter(|p| !harbour_not_reefs(p, &self.alias, &recorded))
            .map(|p| p.id.name.clone())
            .collect()
    }

    /// Updates from Reef's repository only.
    pub async fn updates(&self) -> Result<Vec<PackageInfo>> {
        Ok(reef_updates(&self.pm.get_updates().await?, &self.alias))
    }

    /// Adds `PackageKit`'s download sizes to `plan`, when it has them.
    async fn add_sizes(&self, plan: &mut Plan) {
        let sizes = self.pm.download_sizes(&plan.download_ids()).await;
        if let Ok(sizes) = sizes {
            plan.set_sizes(&sizes);
        }
    }

    /// Resolves catalogue package `name` to Reef's build. `PackageKit`'s
    /// view of the repositories can be empty or older than the catalogue
    /// (nothing available from any repository until a refresh, seen on the
    /// phone, 12 October 2026): it refreshes once.
    async fn installable(&self, name: &str) -> Result<PackageId> {
        match resolve_installable(&self.pm, name, &self.alias).await {
            Err(Error::NotFound(_)) => {
                self.pm.refresh_repo(&self.alias).await?;
                resolve_installable(&self.pm, name, &self.alias).await
            }
            r => r,
        }
    }

    /// The variant builds to install with `name` ([`Plan::alongside`]):
    /// the catalogue's pick for this processor from each group, unless a
    /// build of that group is installed already (it stays, and updates
    /// keep it). [`Error::NoBuild`] when no build of a group runs here.
    async fn variant_builds(
        &self,
        name: &str,
        catalogue: Option<&Catalogue>,
    ) -> Result<Vec<String>> {
        let Some(catalogue) = catalogue else {
            return Ok(Vec::new());
        };
        let picks = catalogue
            .variant_picks(name, self.cpu.as_ref())
            .map_err(|group| Error::NoBuild(name.to_string(), group))?;
        let Some(package) = catalogue.packages.iter().find(|p| p.name == name) else {
            return Ok(picks);
        };
        let mut out = Vec::new();
        for (pick, group) in picks.into_iter().zip(&package.variants) {
            let members: Vec<&str> = group.iter().map(String::as_str).collect();
            let installed = self.pm.resolve(&members, &[Filter::Installed]).await?;
            if !installed
                .iter()
                .any(|p| p.id.is_installed() && members.contains(&p.id.name.as_str()))
            {
                out.push(pick);
            }
        }
        Ok(out)
    }

    /// The ids of `name` and of the variant builds `alongside` it, from
    /// Reef's repository.
    async fn install_ids(&self, name: &str, alongside: &[String]) -> Result<Vec<PackageId>> {
        let mut ids = vec![self.installable(name).await?];
        for n in alongside {
            ids.push(self.installable(n).await?);
        }
        Ok(ids)
    }

    /// Everything installing catalogue package `name` would do, from
    /// `PackageKit`'s simulation of it: the app and what comes with it,
    /// labelled from `catalogue`. With it go the builds of its parts for
    /// this phone's processor ([`Plan::alongside`]). A stale pool (the
    /// simulation fails as the install would, [`stale_metadata`]) is
    /// refreshed once.
    pub async fn preview_install(&self, name: &str, catalogue: Option<&Catalogue>) -> Result<Plan> {
        let alongside = self.variant_builds(name, catalogue).await?;
        let ids = self.install_ids(name, &alongside).await?;
        let raw = |ids: &[PackageId]| ids.iter().map(|i| i.raw.clone()).collect::<Vec<_>>();
        let (ids, simulated) = match self.pm.simulate_install(&refs(&raw(&ids))).await {
            Err(e) if stale_metadata(&e) => {
                self.reload_view().await?;
                let mut ids = vec![resolve_installable(&self.pm, name, &self.alias).await?];
                for n in &alongside {
                    ids.push(resolve_installable(&self.pm, n, &self.alias).await?);
                }
                let simulated = self.pm.simulate_install(&refs(&raw(&ids))).await?;
                (ids, simulated)
            }
            r => (ids, r?),
        };
        let id = ids
            .into_iter()
            .next()
            .ok_or_else(|| Error::NotFound(name.into()))?;
        let mut plan = Plan {
            action: Action::Install,
            target: name.into(),
            items: plan::items_from_simulation(
                &simulated,
                &[asked(id)],
                Change::Install,
                name,
                &self.alias,
                catalogue,
            ),
            download_size: None,
            alongside,
        };
        self.add_sizes(&mut plan).await;
        Ok(plan)
    }

    /// Reef's updates and `PackageKit`'s simulation of applying those of
    /// them `pick` keeps, refreshing once on a stale pool.
    async fn simulate_updates(
        &self,
        pick: impl Fn(&PackageInfo) -> bool,
    ) -> Result<(Vec<PackageInfo>, Vec<PackageInfo>)> {
        let mut retried = false;
        loop {
            let updates: Vec<PackageInfo> =
                self.updates().await?.into_iter().filter(&pick).collect();
            if updates.is_empty() {
                return Ok((updates, Vec::new()));
            }
            let ids: Vec<&str> = updates.iter().map(|p| p.id.raw.as_str()).collect();
            match self.pm.simulate_update(&ids).await {
                Err(e) if !retried && stale_metadata(&e) => {
                    retried = true;
                    self.reload_view().await?;
                }
                r => return Ok((updates, r?)),
            }
        }
    }

    /// Everything updating `name` would do; `None` when Reef has no update
    /// for it.
    pub async fn preview_update(
        &self,
        name: &str,
        catalogue: Option<&Catalogue>,
    ) -> Result<Option<Plan>> {
        let (updates, simulated) = self.simulate_updates(|p| p.id.name == name).await?;
        if updates.is_empty() {
            return Ok(None);
        }
        let mut plan = Plan {
            action: Action::Update,
            target: name.into(),
            items: plan::items_from_simulation(
                &simulated,
                &updates,
                Change::Update,
                name,
                &self.alias,
                catalogue,
            ),
            download_size: None,
            alongside: Vec::new(),
        };
        self.add_sizes(&mut plan).await;
        Ok(Some(plan))
    }

    /// Everything Update all would do: every Reef update, and what they
    /// bring or replace. No items when there is nothing to update.
    pub async fn preview_update_all(&self, catalogue: Option<&Catalogue>) -> Result<Plan> {
        let (updates, simulated) = self.simulate_updates(|_| true).await?;
        let mut plan = Plan {
            action: Action::UpdateAll,
            target: String::new(),
            items: Vec::new(),
            download_size: None,
            alongside: Vec::new(),
        };
        if updates.is_empty() {
            return Ok(plan);
        }
        plan.items = plan::items_from_simulation(
            &simulated,
            &updates,
            Change::Update,
            "",
            &self.alias,
            catalogue,
        );
        self.add_sizes(&mut plan).await;
        Ok(plan)
    }

    /// `simulated` if it does nothing `approved` (a plan for `action` on
    /// `target`) does not show; [`Error::PlanChanged`] otherwise.
    fn approve(
        approved: &Plan,
        action: Action,
        target: &str,
        simulated: Vec<PackageInfo>,
        default: Change,
    ) -> Result<Vec<PackageInfo>> {
        if approved.action != action
            || approved.target != target
            || !approved.covers(&simulated_changes(&simulated, default))
        {
            return Err(Error::PlanChanged);
        }
        Ok(simulated)
    }

    /// Records what an install or update brought from Reef's repository
    /// besides what was asked for, so that it can go with the app later.
    fn record_pulled_in(&self, simulated: &[PackageInfo], asked: &[&str], default: Change) {
        let Some(ledger) = &self.ledger else {
            return;
        };
        let pulled: Vec<&str> = simulated
            .iter()
            .filter(|p| p.id.from_repo(&self.alias) && !asked.contains(&p.id.name.as_str()))
            .filter(|p| Change::from_info(p.info, default) == Change::Install)
            .map(|p| p.id.name.as_str())
            .collect();
        // The install happened; a ledger that cannot be written only
        // keeps those packages from going with the app later.
        let _ = ledger.record_pulled_in(&pulled);
    }

    /// Installs catalogue package `name` as `approved` (its
    /// [`preview_install`](Self::preview_install), which the person agreed
    /// to) says: `PackageKit` simulates the transaction again first, and
    /// if it would now do anything the plan does not show, nothing is
    /// installed ([`Error::PlanChanged`]).
    ///
    /// When `PackageKit`'s view of the repository is stale
    /// ([`stale_metadata`]: a release since replaced a package the cached
    /// metadata lists, or a removal a moment ago left the app out of its
    /// pool), Reef's repository is refreshed and the install tried once
    /// more, simulation included, still only as approved: otherwise it
    /// failed with "not found on medium" or "package not found" until the
    /// next refresh (lifecycle test, 12 October 2026).
    ///
    /// The plan's [`alongside`](Plan::alongside) builds are installed in the
    /// same transaction, and recorded as having come with the app.
    pub async fn install(
        &self,
        name: &str,
        approved: &Plan,
        progress: &mut dyn FnMut(Progress),
    ) -> Result<()> {
        let mut retried = false;
        let simulated = loop {
            let attempt = async {
                let ids = self.install_ids(name, &approved.alongside).await?;
                let raw: Vec<String> = ids.into_iter().map(|i| i.raw).collect();
                let simulated = Self::approve(
                    approved,
                    Action::Install,
                    name,
                    self.pm.simulate_install(&refs(&raw)).await?,
                    Change::Install,
                )?;
                self.check_metadata()?;
                self.pm.install(&refs(&raw), &mut *progress).await?;
                Ok::<_, Error>(simulated)
            }
            .await;
            match attempt {
                Err(e) if !retried && stale_metadata(&e) => {
                    retried = true;
                    self.reload_view().await?;
                }
                r => break r?,
            }
        };
        if let Some(ledger) = &self.ledger {
            // The install happened; a ledger that cannot be written only
            // narrows what Reef removes later.
            let _ = ledger.record(name);
        }
        self.record_pulled_in(&simulated, &[name], Change::Install);
        Ok(())
    }

    /// Applies the Reef update for one package, as `approved` says (see
    /// [`install`](Self::install), retries included). `Ok(false)` when Reef
    /// has no update for it (already up to date); updates from other
    /// repositories are never applied.
    pub async fn update(
        &self,
        name: &str,
        approved: &Plan,
        progress: &mut dyn FnMut(Progress),
    ) -> Result<bool> {
        let mut retried = false;
        loop {
            let updates = self.updates().await?;
            let Some(u) = updates.iter().find(|p| p.id.name == name) else {
                return Ok(false);
            };
            let attempt = async {
                let simulated = Self::approve(
                    approved,
                    Action::Update,
                    name,
                    self.pm.simulate_update(&[u.id.raw.as_str()]).await?,
                    Change::Update,
                )?;
                self.check_metadata()?;
                self.pm.update(&[u.id.raw.as_str()], &mut *progress).await?;
                Ok::<_, Error>(simulated)
            }
            .await;
            match attempt {
                // As in install: refresh, then the update the new metadata
                // lists.
                Err(e) if !retried && stale_metadata(&e) => {
                    retried = true;
                    self.reload_view().await?;
                }
                r => {
                    self.record_pulled_in(&r?, &[name], Change::Update);
                    return Ok(true);
                }
            }
        }
    }

    /// Applies every Reef update in one transaction, as `approved` (its
    /// [`preview_update_all`](Self::preview_update_all)) says, with
    /// [`install`](Self::install)'s retry.
    pub async fn update_all(
        &self,
        approved: &Plan,
        progress: &mut dyn FnMut(Progress),
    ) -> Result<usize> {
        let mut retried = false;
        loop {
            let updates = self.updates().await?;
            if updates.is_empty() {
                return Ok(0);
            }
            let ids: Vec<&str> = updates.iter().map(|p| p.id.raw.as_str()).collect();
            let attempt = async {
                let simulated = Self::approve(
                    approved,
                    Action::UpdateAll,
                    "",
                    self.pm.simulate_update(&ids).await?,
                    Change::Update,
                )?;
                self.check_metadata()?;
                self.pm.update(&ids, &mut *progress).await?;
                Ok::<_, Error>(simulated)
            }
            .await;
            match attempt {
                Err(e) if !retried && stale_metadata(&e) => {
                    retried = true;
                    self.reload_view().await?;
                }
                r => {
                    let names: Vec<&str> = updates.iter().map(|p| p.id.name.as_str()).collect();
                    self.record_pulled_in(&r?, &names, Change::Update);
                    return Ok(updates.len());
                }
            }
        }
    }

    /// Everything removing `name` would remove ([`remove`](Self::remove)'s
    /// cascade), each with why, checked by `PackageKit`'s simulation, and
    /// what stays though only the app needed it. When `PackageKit` refuses
    /// the cascade because something staying needs one of the dependencies
    /// (a requirement its `RequiredBy` does not report), the plan is
    /// [`remove`](Self::remove)'s fallback: the app with its parts and
    /// add-ons, the dependencies staying. An OS package that needs the app
    /// itself still fails the preview, as it would fail the removal.
    pub async fn preview_remove(&self, name: &str, catalogue: Option<&Catalogue>) -> Result<Plan> {
        // A stale view of what is installed (a package changed outside
        // PackageKit) fails already while working out the plan: reload it
        // and plan once more.
        match self.preview_remove_once(name, catalogue).await {
            Err(e) if stale_metadata(&e) => {
                self.reload_view().await?;
                self.preview_remove_once(name, catalogue).await
            }
            r => r,
        }
    }

    /// Makes `PackageKit` read what is installed and Reef's repository
    /// afresh ([`PackageManager::reload_installed`]).
    async fn reload_view(&self) -> Result<()> {
        self.pm.reload_installed().await?;
        self.pm.refresh_repo(&self.alias).await
    }

    async fn preview_remove_once(&self, name: &str, catalogue: Option<&Catalogue>) -> Result<Plan> {
        let (going, minimal, mut kept) = self.removal(name).await?;
        let ids: Vec<&str> = going.iter().map(|(p, _)| p.id.raw.as_str()).collect();
        let (going, simulated) = match self.pm.simulate_remove(&ids).await {
            Err(e) if still_needed(&e) && going.len() > minimal => {
                let fallback: Vec<&str> = ids[..minimal].to_vec();
                let simulated = self.pm.simulate_remove(&fallback).await?;
                // The dependencies stay; whatever needed the app beyond
                // its parts is not in the fallback, so PackageKit decides.
                for (p, why) in &going[minimal..] {
                    if *why != Reason::NeedsIt {
                        kept.push(p.clone());
                    }
                }
                (going[..minimal].to_vec(), simulated)
            }
            r => {
                let simulated = r?;
                (going, simulated)
            }
        };
        let mut items: Vec<plan::Item> = going
            .iter()
            .map(|(p, why)| {
                let mut item = plan::describe(p, Change::Remove, name, &self.alias, catalogue);
                item.reef = true;
                item.requested = *why == Reason::Asked;
                item.reason = Some(*why);
                item.stops_working = *why == Reason::NeedsIt;
                item
            })
            .collect();
        // Anything else PackageKit would take (it should take nothing
        // else: the removal never allows dependencies).
        for p in &simulated {
            if !items.iter().any(|i| i.name == p.id.name) {
                let mut item = plan::describe(p, Change::Remove, name, &self.alias, catalogue);
                item.reef = false;
                item.reason = Some(Reason::NeedsIt);
                item.stops_working = true;
                items.push(item);
            }
        }
        for p in &kept {
            let mut item = plan::describe(p, Change::Keep, name, &self.alias, catalogue);
            item.reason = Some(Reason::OnlyFor);
            items.push(item);
        }
        plan::sort(&mut items);
        Ok(Plan {
            action: Action::Remove,
            target: name.into(),
            items,
            download_size: None,
            alongside: Vec::new(),
        })
    }

    /// Removes an installed app, only if it is Reef's to remove
    /// ([`reef_app_removable`]): Reef never removes an OS package, a Jolla
    /// Store (`harbour-`) app, or a package installed from another
    /// repository, whatever the catalogue says. Runs only as `approved`
    /// (the person's [`preview_remove`](Self::preview_remove)) shows;
    /// anything more, and nothing is removed ([`Error::PlanChanged`]).
    ///
    /// Everything of Reef's that belongs to the app goes with it, in the same
    /// transaction:
    /// - its parts, the installed Reef packages named after it
    ///   (`shoal-pilot-gesture-patch`, `shoal-pilot-piper` for `shoal-pilot`):
    ///   removing Pilot alone failed with `PackageKit`'s dependency error 13,
    ///   because its gesture patch needs it;
    /// - Reef packages that need something going (an add-on such as the
    ///   earbuds service's Device ID setting);
    /// - Reef packages it needed ([`reef_removable`]) that nothing staying
    ///   needs, neither them nor any of their parts, and that were not
    ///   installed for themselves (the earbuds service and volume watcher,
    ///   pulled in by the earbuds app), with their own parts: removing that
    ///   app left its service running, scanning for Bluetooth devices
    ///   (forum, 12 October 2026). Keel goes once no app is left on it,
    ///   unless installed for itself. A part with users of its own keeps
    ///   its package: Keel's nemo-compat-configuration, needed by
    ///   keel-silica, which other apps keep (removing Camera failed with
    ///   error 13, lifecycle test, 12 October 2026).
    ///
    /// When `PackageKit` still refuses (error 13: a requirement its
    /// `RequiredBy` does not report), the app goes with its parts and
    /// add-ons and the dependencies stay. An OS package that needs the app
    /// stops the removal.
    pub async fn remove(
        &self,
        name: &str,
        approved: &Plan,
        progress: &mut dyn FnMut(Progress),
    ) -> Result<()> {
        if approved.action != Action::Remove || approved.target != name {
            return Err(Error::PlanChanged);
        }
        let changes = |going: &[(PackageInfo, Reason)]| -> Vec<(String, Change)> {
            going
                .iter()
                .map(|(p, _)| (p.id.name.clone(), Change::Remove))
                .collect()
        };
        // PackageKit's view of what is installed can be stale too (a
        // package updated outside it, with rpm or another tool: its old id
        // is "not found", error 8, lifecycle test, 12 October 2026). Then
        // refresh, work the removal out again and try once more, still only
        // as approved.
        let mut retried = false;
        loop {
            let (mut going, minimal, _) = match self.removal(name).await {
                Err(e) if !retried && stale_metadata(&e) => {
                    retried = true;
                    self.reload_view().await?;
                    continue;
                }
                r => r?,
            };
            // The whole cascade, or the fallback the preview settled on.
            if !approved.covers(&changes(&going)) {
                if approved.covers(&changes(&going[..minimal])) {
                    going.truncate(minimal);
                } else {
                    return Err(Error::PlanChanged);
                }
            }
            let ids: Vec<&str> = going.iter().map(|(p, _)| p.id.raw.as_str()).collect();
            let result = match self.pm.remove(&ids, &mut *progress).await {
                Err(e) if still_needed(&e) && going.len() > minimal => {
                    going.truncate(minimal);
                    let ids: Vec<&str> = going.iter().map(|(p, _)| p.id.raw.as_str()).collect();
                    self.pm.remove(&ids, &mut *progress).await
                }
                r => r,
            };
            match result {
                Err(e) if !retried && stale_metadata(&e) => {
                    retried = true;
                    self.reload_view().await?;
                }
                r => {
                    r?;
                    if let Some(ledger) = &self.ledger {
                        for (p, _) in &going {
                            let _ = ledger.forget(&p.id.name);
                        }
                    }
                    return Ok(());
                }
            }
        }
    }

    /// [`remove`](Self::remove)'s cascade: what goes and why (the first
    /// `minimal` are the app and its parts, the fallback), and the packages
    /// only what goes needed that stay because Reef cannot tell they are
    /// its own.
    #[allow(
        clippy::type_complexity,
        reason = "one private result, named at its one use"
    )]
    async fn removal(
        &self,
        name: &str,
    ) -> Result<(Vec<(PackageInfo, Reason)>, usize, Vec<PackageInfo>)> {
        let recorded = self.recorded();
        let for_themselves = self.asked_for();
        let mut found = resolve_with_offers(&self.pm, &[name]).await?;
        // The repository always offers a catalogue app. When PackageKit
        // does not list that offer, its view is stale (after another
        // removal, until a refresh), and the parts and dependencies Reef
        // tells by the offer would look foreign and stay: removing Migrate
        // left its command-line tool installed (lifecycle test, 12 October
        // 2026). Refresh first; offline, carry on with what is known.
        if !found.iter().any(|p| p.id.data == self.alias)
            && self.pm.refresh_repo(&self.alias).await.is_ok()
        {
            found = resolve_with_offers(&self.pm, &[name]).await?;
        }
        let Some(id) = reef_app_removable(&found, &self.alias, &recorded)
            .into_iter()
            .find(|p| p.id.name == name)
        else {
            return Err(if found.iter().any(|p| p.id.is_installed()) {
                Error::NotReefs(name.into())
            } else {
                Error::NotFound(name.into())
            });
        };
        let mut going: Vec<(PackageInfo, Reason)> = vec![(id, Reason::Asked)];
        going.extend(
            self.parts(name)
                .await?
                .into_iter()
                .map(|p| (p, Reason::Part)),
        );
        let minimal = going.len();
        let mut kept: Vec<PackageInfo> = Vec::new();
        let is_going = |going: &[(PackageInfo, Reason)], p: &PackageInfo| {
            going.iter().any(|(g, _)| g.id.name == p.id.name)
        };
        loop {
            let ids: Vec<&str> = going.iter().map(|(p, _)| p.id.raw.as_str()).collect();
            // Reef's packages that need what goes.
            let needing = self
                .owned_installed(&self.pm.required_by(&ids).await?, reef_removable)
                .await?;
            let mut added: Vec<(PackageInfo, Reason)> = needing
                .into_iter()
                .filter(|p| !is_going(&going, p))
                .map(|p| (p, Reason::NeedsIt))
                .collect();
            // Reef's packages only what goes needs, not installed for themselves.
            let deps = self.pm.depends_on(&ids).await?;
            let owned = self.owned_installed(&deps, reef_removable).await?;
            for dep in self.owned_installed(&deps, reef_owned).await? {
                if is_going(&going, &dep)
                    || is_going(&added, &dep)
                    || for_themselves.contains(&dep.id.name)
                {
                    continue;
                }
                // Its own parts (the earbuds service's Device ID add-on) go
                // with it, so they do not count as keeping it.
                let part_of_dep = |u: &PackageInfo| {
                    u.id.name
                        .strip_prefix(dep.id.name.as_str())
                        .is_some_and(|rest| rest.starts_with('-'))
                };
                // Its parts go only where nothing staying needs them (Keel's
                // nemo-compat-configuration is needed by keel-silica, which
                // other apps keep). The dependency itself goes when nothing
                // staying needs it, a part that stays included: a part
                // staying is fine unless it needs the dependency (removing
                // Camera failed with error 13 when that was not checked, and
                // left all of nemo-compat when every part's users kept it).
                let parts = self.parts(&dep.id.name).await?;
                let mut parts_going = Vec::new();
                for part in &parts {
                    let users = self.pm.required_by(&[part.id.raw.as_str()]).await?;
                    if users
                        .iter()
                        .all(|u| is_going(&going, u) || u.id.name == dep.id.name || part_of_dep(u))
                    {
                        parts_going.push(part.clone());
                    }
                }
                let users = self.pm.required_by(&[dep.id.raw.as_str()]).await?;
                let goes_with =
                    |u: &PackageInfo| parts_going.iter().any(|p| p.id.name == u.id.name);
                if !users
                    .iter()
                    .all(|u| is_going(&going, u) || u.id.name == dep.id.name || goes_with(u))
                {
                    continue;
                }
                if !owned.iter().any(|o| o.id.name == dep.id.name) {
                    // Only the app needed it, but Reef cannot tell it is
                    // its own (another repository offers it too): it stays,
                    // and the person is told.
                    if !kept.iter().any(|k| k.id.name == dep.id.name) {
                        kept.push(dep);
                    }
                    continue;
                }
                for part in parts_going {
                    if !is_going(&going, &part) && !is_going(&added, &part) {
                        added.push((part, Reason::Part));
                    }
                }
                added.push((dep, Reason::OnlyFor));
            }
            if added.is_empty() {
                break;
            }
            going.extend(added);
        }
        let (going, minimal) = self.core_first(going, minimal).await?;
        Ok((going, minimal, kept))
    }

    /// Orders a removal with what goes in any case first: the app and its
    /// parts (the first `minimal`), and everything going that, in turn,
    /// needs them (add-ons, and services that require the app). That is the
    /// fallback when `PackageKit` refuses the whole removal (error 13); only
    /// the dependencies Reef judged unused stay. Returns the new count.
    async fn core_first(
        &self,
        going: Vec<(PackageInfo, Reason)>,
        minimal: usize,
    ) -> Result<(Vec<(PackageInfo, Reason)>, usize)> {
        let mut core: Vec<String> = going[..minimal]
            .iter()
            .map(|(p, _)| p.id.name.clone())
            .collect();
        loop {
            let ids: Vec<&str> = going
                .iter()
                .filter(|(p, _)| core.contains(&p.id.name))
                .map(|(p, _)| p.id.raw.as_str())
                .collect();
            let needing = self.pm.required_by(&ids).await?;
            let new: Vec<String> = needing
                .iter()
                .filter(|p| {
                    !core.contains(&p.id.name) && going.iter().any(|(g, _)| g.id.name == p.id.name)
                })
                .map(|p| p.id.name.clone())
                .collect();
            if new.is_empty() {
                break;
            }
            core.extend(new);
        }
        let (mut first, rest): (Vec<_>, Vec<_>) = going
            .into_iter()
            .partition(|(p, _)| core.contains(&p.id.name));
        let minimal = first.len();
        first.extend(rest);
        Ok((first, minimal))
    }

    /// Those of `packages` that are installed and Reef's by `rule`
    /// ([`reef_removable`] or [`reef_owned`]).
    async fn owned_installed(
        &self,
        packages: &[PackageInfo],
        rule: fn(&[PackageInfo], &str, &BTreeSet<String>) -> Vec<PackageInfo>,
    ) -> Result<Vec<PackageInfo>> {
        let mut names: Vec<&str> = packages
            .iter()
            .filter(|p| p.id.is_installed())
            .map(|p| p.id.name.as_str())
            .collect();
        names.sort_unstable();
        names.dedup();
        if names.is_empty() {
            return Ok(Vec::new());
        }
        let found = resolve_with_offers(&self.pm, &names).await?;
        Ok(rule(&found, &self.alias, &self.recorded()))
    }

    /// The installed packages Reef may remove that are parts of `name`:
    /// named `<name>-...`.
    async fn parts(&self, name: &str) -> Result<Vec<PackageInfo>> {
        let prefix = format!("{name}-");
        let mut names: Vec<String> = self
            .pm
            .search_names(&[prefix.as_str()], &[Filter::Installed])
            .await?
            .into_iter()
            .filter(|p| p.id.name.starts_with(&prefix) && p.id.is_installed())
            .map(|p| p.id.name)
            .collect();
        names.sort();
        names.dedup();
        if names.is_empty() {
            return Ok(Vec::new());
        }
        let refs: Vec<&str> = names.iter().map(String::as_str).collect();
        let found = resolve_with_offers(&self.pm, &refs).await?;
        Ok(reef_removable(&found, &self.alias, &self.recorded()))
    }
}

/// `&str`s of `ids`, for the package manager.
fn refs(ids: &[String]) -> Vec<&str> {
    ids.iter().map(String::as_str).collect()
}

/// The package asked for, as a plan's requested item.
fn asked(id: PackageId) -> PackageInfo {
    PackageInfo {
        info: Info::Available,
        id,
        summary: String::new(),
    }
}

/// An unfiltered `Resolve` plus the repositories' offers. The zypp backend
/// leaves a repository's copy out of an unfiltered `Resolve` when the same
/// version is installed, so [`reef_owned`]'s "the Reef repository also
/// offers it" fallback missed every app installed at the repository's
/// current version (Pilot showed Install while installed, on the Jolla
/// Phone); a `NotInstalled` `Resolve` lists those copies.
async fn resolve_with_offers<P: PackageManager>(
    pm: &P,
    names: &[&str],
) -> Result<Vec<PackageInfo>> {
    let mut found = pm.resolve(names, &[Filter::None]).await?;
    for offer in pm.resolve(names, &[Filter::NotInstalled]).await? {
        if !found.iter().any(|p| p.id.raw == offer.id.raw) {
            found.push(offer);
        }
    }
    Ok(found)
}

/// Whether an installed package's id names another repository as its
/// origin (`installed:<other>`): never Reef's.
fn from_other_repo(id: &PackageId, alias: &str) -> bool {
    id.data
        .strip_prefix("installed:")
        .is_some_and(|origin| origin != alias)
}

/// Whether `found` holds an offer of `name` from a repository `pred` picks.
fn offered(found: &[PackageInfo], name: &str, pred: impl Fn(&str) -> bool) -> bool {
    found
        .iter()
        .any(|q| q.id.name == name && !q.id.is_installed() && pred(&q.id.data))
}

/// The installed packages in `found` (an unfiltered `Resolve` and the
/// repositories' offers, [`resolve_with_offers`]) that Reef shows as its
/// own: Reef recorded installing them (`recorded`, the [`InstallLedger`],
/// which does not depend on the repository), or `PackageKit` names the
/// origin (`installed:<alias>`), or, as the zypp backend reports a plain
/// `installed`, the Reef repository also offers the same name (installs
/// made before the ledger, or by another tool). An installed package
/// matching none of these (an OS package), or whose origin is another
/// repository, is left out.
pub fn reef_owned(
    found: &[PackageInfo],
    alias: &str,
    recorded: &BTreeSet<String>,
) -> Vec<PackageInfo> {
    found
        .iter()
        .filter(|p| p.id.is_installed() && !from_other_repo(&p.id, alias))
        .filter(|p| {
            recorded.contains(&p.id.name)
                || p.id.from_repo(alias)
                || (p.id.data == "installed" && offered(found, &p.id.name, |r| r == alias))
        })
        .cloned()
        .collect()
}

/// A `harbour-` package (the Jolla Store's naming) that Reef cannot show it
/// installed itself: neither its record nor `PackageKit`'s origin says so.
/// The Reef repository merely offering the name does not count: the same
/// app may have come from the Jolla Store. One Reef did install (Pilot
/// Lite, `harbour-shoal-pilot`, is a Reef app) stays Reef's to remove: a
/// blanket rule left it with no way out (lifecycle test, 12 October 2026).
fn harbour_not_reefs(p: &PackageInfo, alias: &str, recorded: &BTreeSet<String>) -> bool {
    p.id.name.starts_with("harbour-") && !recorded.contains(&p.id.name) && !p.id.from_repo(alias)
}

/// The installed catalogue apps in `found` Reef may remove when the person
/// asks: those [`reef_owned`] shows (zypp reports a plain `installed`, and
/// apps Reef installed before it kept a record are only known by the Reef
/// repository offering them), except a Jolla Store (`harbour-`) app Reef
/// cannot show it installed ([`harbour_not_reefs`]).
pub fn reef_app_removable(
    found: &[PackageInfo],
    alias: &str,
    recorded: &BTreeSet<String>,
) -> Vec<PackageInfo> {
    reef_owned(found, alias, recorded)
        .into_iter()
        .filter(|p| !harbour_not_reefs(p, alias, recorded))
        .collect()
}

/// The installed packages in `found` that may go with an app as its parts
/// or dependencies: Reef recorded installing them (asked for or pulled in,
/// the [`InstallLedger`]), or `PackageKit` says they came from Reef's
/// repository (`installed:<alias>`), or (a plain `installed`) the Reef
/// repository offers them and no other repository does: Qt installed from
/// Chum, which the Reef repository mirrors, stays. A package `PackageKit`
/// says came from another repository, and a Jolla Store app (`harbour-`)
/// Reef cannot show it installed ([`harbour_not_reefs`]), never go.
pub fn reef_removable(
    found: &[PackageInfo],
    alias: &str,
    recorded: &BTreeSet<String>,
) -> Vec<PackageInfo> {
    found
        .iter()
        .filter(|p| p.id.is_installed() && !from_other_repo(&p.id, alias))
        .filter(|p| !harbour_not_reefs(p, alias, recorded))
        .filter(|p| {
            recorded.contains(&p.id.name)
                || p.id.from_repo(alias)
                || (p.id.data == "installed"
                    && offered(found, &p.id.name, |r| r == alias)
                    && !offered(found, &p.id.name, |r| r != alias))
        })
        .cloned()
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::catalogue::tests::SAMPLE;
    use crate::packagekit::{Exit, Info, PackageId};
    use crate::plan::Kind;
    use std::cell::RefCell;

    fn pkg(id: &str) -> PackageInfo {
        PackageInfo {
            info: Info::Normal,
            id: PackageId::parse(id).unwrap(),
            summary: String::new(),
        }
    }

    /// A ledger in a fresh temporary directory, recording `asked` as
    /// installed by the person and `pulled` as pulled in.
    fn ledger(test: &str, asked: &[&str], pulled: &[&str]) -> (InstallLedger, PathBuf) {
        let dir = std::env::temp_dir().join(format!("reef-ledger-{test}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let ledger = InstallLedger::new(dir.join("shipwright-reef/installed.json"));
        for a in asked {
            ledger.record(a).unwrap();
        }
        ledger.record_pulled_in(pulled).unwrap();
        (ledger, dir)
    }

    #[test]
    fn joins_install_state() {
        let cat = Catalogue::parse(SAMPLE.as_bytes(), "aarch64").unwrap();
        let release = SailfishRelease::parse("5.2.0.17").unwrap();
        let installed = [
            pkg("shipwright-keel-silica;0.1.0-1;aarch64;installed"),
            pkg("shipwright-shoal-bridge-airpods-ui;0.9.0-1;aarch64;installed"),
        ];
        let updates = [pkg(
            "shipwright-shoal-bridge-airpods-ui;1.0.0-1;aarch64;shipwright-reef",
        )];
        let rows = entries(&cat, &release, &installed, &updates);
        assert_eq!(rows.len(), 2);
        // Sorted by category: Audio (the bridge) before Libraries (Keel).
        assert_eq!(
            rows[0].state,
            InstallState::UpdateAvailable {
                installed: "0.9.0-1".into(),
                available: "1.0.0-1".into()
            }
        );
        assert_eq!(
            rows[1].state,
            InstallState::Installed {
                version: "0.1.0-1".into()
            }
        );
        let none = entries(&cat, &release, &[], &[]);
        assert!(none.iter().all(|e| e.state == InstallState::NotInstalled));
    }

    /// In-memory package manager recording calls.
    #[derive(Default)]
    struct Fake {
        calls: RefCell<Vec<String>>,
        available: Vec<PackageInfo>,
        updates: Vec<PackageInfo>,
        /// Copies only a `NotInstalled` resolve lists (zypp leaves a
        /// repository's copy of an installed version out of the others).
        offers: Vec<PackageInfo>,
        /// Installed dependencies: (package, what it needs), by name.
        needs: Vec<(&'static str, &'static str)>,
        /// The next install or update fails with this `PkErrorEnum`, once.
        fail_once: std::cell::Cell<Option<u32>>,
        /// The next `RequiredBy` query fails as with a stale installed id
        /// (error 8), once.
        stale_query_once: std::cell::Cell<bool>,
        /// What a simulated install or update also brings (`Package`
        /// signals with their info).
        brings: RefCell<Vec<PackageInfo>>,
        /// A simulated removal fails with this `PkErrorEnum`.
        remove_refused: Option<u32>,
        /// A simulated removal that includes this package fails with 13.
        refuses_removing: Option<&'static str>,
        /// The next simulated install or update fails with this, once.
        simulate_fails_once: std::cell::Cell<Option<u32>>,
        /// Listed only after a refresh (a stale or empty pool).
        after_refresh: Vec<PackageInfo>,
        refreshed: std::cell::Cell<bool>,
    }

    impl Fake {
        fn simulation(&self) -> Result<()> {
            match self.simulate_fails_once.take() {
                Some(code) => Err(Error::Transaction {
                    exit: Exit::Failed,
                    error: Some((code, "package not found".into())),
                }),
                None => Ok(()),
            }
        }

        fn transaction(&self) -> Result<()> {
            match self.fail_once.take() {
                Some(code) => Err(Error::Transaction {
                    exit: Exit::Failed,
                    error: Some((code, "File './x.rpm' not found on medium".into())),
                }),
                None => Ok(()),
            }
        }

        fn installed(&self, name: &str) -> Option<PackageInfo> {
            self.available
                .iter()
                .find(|p| p.id.name == name && p.id.is_installed())
                .cloned()
        }

        fn simulated(&self, ids: &[&str], info: Info) -> Vec<PackageInfo> {
            ids.iter()
                .map(|id| PackageInfo {
                    info,
                    id: PackageId::parse(id).unwrap(),
                    summary: String::new(),
                })
                .chain(self.brings.borrow().iter().cloned())
                .collect()
        }
    }

    impl PackageManager for Fake {
        async fn resolve(&self, names: &[&str], filters: &[Filter]) -> Result<Vec<PackageInfo>> {
            self.calls
                .borrow_mut()
                .push(format!("resolve {names:?} {filters:?}"));
            let offers = filters
                .contains(&Filter::NotInstalled)
                .then_some(&self.offers);
            let late = self.refreshed.get().then_some(&self.after_refresh);
            Ok(self
                .available
                .iter()
                .chain(offers.into_iter().flatten())
                .chain(late.into_iter().flatten())
                .filter(|p| names.contains(&p.id.name.as_str()))
                .cloned()
                .collect())
        }
        async fn install(&self, ids: &[&str], _: &mut dyn FnMut(Progress)) -> Result<()> {
            self.calls.borrow_mut().push(format!("install {ids:?}"));
            self.transaction()
        }
        async fn update(&self, ids: &[&str], _: &mut dyn FnMut(Progress)) -> Result<()> {
            self.calls.borrow_mut().push(format!("update {ids:?}"));
            self.transaction()
        }
        async fn remove(&self, ids: &[&str], _: &mut dyn FnMut(Progress)) -> Result<()> {
            self.calls.borrow_mut().push(format!("remove {ids:?}"));
            self.transaction()
        }
        async fn get_updates(&self) -> Result<Vec<PackageInfo>> {
            Ok(self.updates.clone())
        }
        async fn search_names(
            &self,
            values: &[&str],
            filters: &[Filter],
        ) -> Result<Vec<PackageInfo>> {
            self.calls
                .borrow_mut()
                .push(format!("search {values:?} {filters:?}"));
            Ok(self
                .available
                .iter()
                .filter(|p| !filters.contains(&Filter::Installed) || p.id.is_installed())
                .filter(|p| values.iter().any(|v| p.id.name.contains(v)))
                .cloned()
                .collect())
        }
        async fn depends_on(&self, ids: &[&str]) -> Result<Vec<PackageInfo>> {
            let names: Vec<String> = ids
                .iter()
                .map(|i| PackageId::parse(i).unwrap().name)
                .collect();
            Ok(self
                .needs
                .iter()
                .filter(|(who, _)| names.iter().any(|n| n == who))
                .filter_map(|(_, what)| self.installed(what))
                .collect())
        }
        async fn required_by(&self, ids: &[&str]) -> Result<Vec<PackageInfo>> {
            if self.stale_query_once.take() {
                return Err(crate::packagekit::Error::Transaction {
                    exit: Exit::Failed,
                    error: Some((8, "Package couldn't be found".into())),
                });
            }
            let names: Vec<String> = ids
                .iter()
                .map(|i| PackageId::parse(i).unwrap().name)
                .collect();
            Ok(self
                .needs
                .iter()
                .filter(|(_, what)| names.iter().any(|n| n == what))
                .filter_map(|(who, _)| self.installed(who))
                .collect())
        }
        async fn reload_installed(&self) -> Result<()> {
            self.calls.borrow_mut().push("reload".into());
            Ok(())
        }
        async fn refresh_repo(&self, alias: &str) -> Result<()> {
            self.calls.borrow_mut().push(format!("refresh {alias}"));
            self.refreshed.set(true);
            Ok(())
        }
        async fn simulate_install(&self, ids: &[&str]) -> Result<Vec<PackageInfo>> {
            self.calls
                .borrow_mut()
                .push(format!("simulate install {ids:?}"));
            self.simulation()?;
            Ok(self.simulated(ids, Info::Installing))
        }
        async fn simulate_update(&self, ids: &[&str]) -> Result<Vec<PackageInfo>> {
            self.calls
                .borrow_mut()
                .push(format!("simulate update {ids:?}"));
            self.simulation()?;
            Ok(self.simulated(ids, Info::Updating))
        }
        async fn simulate_remove(&self, ids: &[&str]) -> Result<Vec<PackageInfo>> {
            self.calls
                .borrow_mut()
                .push(format!("simulate remove {ids:?}"));
            if let Some(code) = self.remove_refused {
                return Err(Error::Transaction {
                    exit: Exit::Failed,
                    error: Some((code, "jolla-settings requires it".into())),
                });
            }
            if let Some(n) = self.refuses_removing {
                if ids.iter().any(|id| id.starts_with(&format!("{n};"))) {
                    return Err(Error::Transaction {
                        exit: Exit::Failed,
                        error: Some((13, format!("something staying requires {n}"))),
                    });
                }
            }
            Ok(ids
                .iter()
                .map(|id| PackageInfo {
                    info: Info::Removing,
                    id: PackageId::parse(id).unwrap(),
                    summary: String::new(),
                })
                .collect())
        }
        async fn download_sizes(&self, ids: &[&str]) -> Result<Vec<(String, u64)>> {
            Ok(ids.iter().map(|id| ((*id).to_string(), 1000)).collect())
        }
    }

    /// The real transactions the fake was asked for, without the lookups
    /// and simulations around them.
    fn transactions(calls: &[String]) -> Vec<String> {
        calls
            .iter()
            .filter(|c| {
                ["install ", "update ", "remove ", "refresh "]
                    .iter()
                    .any(|p| c.starts_with(p))
            })
            .cloned()
            .collect()
    }

    /// A release replaced the package the phone's cached metadata lists:
    /// install and update refresh Reef's repository and try once more; any
    /// other failure is not retried.
    #[test]
    fn stale_metadata_is_refreshed_and_tried_again() {
        let fake = Fake {
            available: vec![pkg(
                "shipwright-shoal-camera;0.1.0-26;aarch64;shipwright-reef",
            )],
            updates: vec![pkg(
                "shipwright-shoal-camera;0.1.0-27;aarch64;shipwright-reef",
            )],
            ..Fake::default()
        };
        let store = Store::new(fake, "shipwright-reef");
        futures_lite::future::block_on(async {
            let name = "shipwright-shoal-camera";
            let install = store.preview_install(name, None).await.unwrap();
            let update = store.preview_update(name, None).await.unwrap().unwrap();
            let all = store.preview_update_all(None).await.unwrap();
            store.pm.fail_once.set(Some(37));
            store.install(name, &install, &mut |_| {}).await.unwrap();
            store.pm.fail_once.set(Some(10));
            assert!(store.update(name, &update, &mut |_| {}).await.unwrap());
            store.pm.fail_once.set(Some(42));
            assert_eq!(store.update_all(&all, &mut |_| {}).await.unwrap(), 1);
            // Removed a moment ago, PackageKit's pool no longer has the app.
            store.pm.fail_once.set(Some(8));
            store.install(name, &install, &mut |_| {}).await.unwrap();
            // Dependency resolution is not a stale cache: no retry.
            store.pm.fail_once.set(Some(13));
            assert!(store.install(name, &install, &mut |_| {}).await.is_err());
        });
        let calls = transactions(&store.pm.calls.borrow());
        let count = |p: &str| calls.iter().filter(|c| c.starts_with(p)).count();
        assert_eq!(count("refresh"), 4, "{calls:?}");
        assert_eq!(count("install"), 5, "{calls:?}");
        assert_eq!(count("update"), 4, "{calls:?}");
    }

    /// The simulation meets the same stale pool as the transaction: the
    /// preview and the approved run refresh once and plan again; a fresh
    /// plan that shows more goes back to the person.
    #[test]
    fn a_stale_pool_is_refreshed_for_the_simulation_too() {
        let fake = Fake {
            available: vec![pkg("app;1-1;aarch64;shipwright-reef")],
            updates: vec![pkg("app;1-2;aarch64;shipwright-reef")],
            ..Fake::default()
        };
        let store = Store::new(fake, "shipwright-reef");
        futures_lite::future::block_on(async {
            store.pm.simulate_fails_once.set(Some(8));
            let plan = store.preview_install("app", None).await.unwrap();
            store.pm.simulate_fails_once.set(Some(37));
            store.install("app", &plan, &mut |_| {}).await.unwrap();
            store.pm.simulate_fails_once.set(Some(8));
            let update = store.preview_update("app", None).await.unwrap().unwrap();
            store.pm.simulate_fails_once.set(Some(10));
            assert!(store.update("app", &update, &mut |_| {}).await.unwrap());
            store.pm.simulate_fails_once.set(Some(42));
            let all = store.preview_update_all(None).await.unwrap();
            assert_eq!(all.items.len(), 1);
            // After the refresh the install brings something new: not
            // what the person saw.
            store.pm.simulate_fails_once.set(Some(8));
            store.pm.brings.borrow_mut().push(PackageInfo {
                info: Info::Installing,
                id: PackageId::parse("extra;1-1;aarch64;shipwright-reef").unwrap(),
                summary: String::new(),
            });
            assert!(matches!(
                store.install("app", &plan, &mut |_| {}).await,
                Err(Error::PlanChanged)
            ));
        });
        let calls = transactions(&store.pm.calls.borrow());
        let count = |p: &str| calls.iter().filter(|c| c.starts_with(p)).count();
        assert_eq!(count("refresh"), 6, "{calls:?}");
        assert_eq!(count("install"), 1, "{calls:?}");
        assert_eq!(count("update"), 1, "{calls:?}");
    }

    /// `PackageKit` lists nothing available until its repositories are
    /// refreshed: the preview and the install refresh once and find the
    /// app.
    #[test]
    fn an_app_missing_from_a_stale_pool_is_found_after_a_refresh() {
        let fake = Fake {
            after_refresh: vec![pkg(
                "shipwright-shoal-camera;0.1.0-26;aarch64;shipwright-reef",
            )],
            ..Fake::default()
        };
        let store = Store::new(fake, "shipwright-reef");
        let name = "shipwright-shoal-camera";
        futures_lite::future::block_on(async {
            let plan = store.preview_install(name, None).await.unwrap();
            store.install(name, &plan, &mut |_| {}).await.unwrap();
        });
        let calls = store.pm.calls.borrow();
        assert!(
            calls.iter().any(|c| c == "refresh shipwright-reef"),
            "{calls:?}"
        );
        assert!(calls.last().unwrap().starts_with("install"), "{calls:?}");
        drop(calls);
        // Not there even after a refresh: an error, after one refresh only.
        let store = Store::new(Fake::default(), "shipwright-reef");
        assert!(futures_lite::future::block_on(store.preview_install("absent", None)).is_err());
        assert_eq!(
            transactions(&store.pm.calls.borrow()),
            ["refresh shipwright-reef"]
        );
    }

    /// Camera's Keel compatibility package is needed only by Camera, but
    /// one of its parts is needed by keel-silica, which Mail keeps: it
    /// stays, with its parts (removing Camera failed with error 13).
    #[test]
    fn a_dependency_whose_part_is_still_needed_stays() {
        let both = |name: &'static str, v: &'static str| {
            [
                pkg(&format!("{name};{v};aarch64;installed")),
                pkg(&format!("{name};{v};aarch64;shipwright-reef")),
            ]
        };
        let available: Vec<PackageInfo> = [
            both("shipwright-shoal-camera", "0.1.0-26"),
            both("shipwright-keel-nemo-compat", "0.1.0-7"),
            both("shipwright-keel-nemo-compat-configuration", "0.1.0-7"),
            both("shipwright-keel-silica", "0.1.0-28"),
            both("shipwright-shoal-mail", "0.1.0-9"),
        ]
        .into_iter()
        .flatten()
        .collect();
        let fake = Fake {
            available,
            needs: vec![
                ("shipwright-shoal-camera", "shipwright-keel-nemo-compat"),
                ("shipwright-shoal-camera", "shipwright-keel-silica"),
                (
                    "shipwright-keel-silica",
                    "shipwright-keel-nemo-compat-configuration",
                ),
                (
                    "shipwright-keel-nemo-compat-configuration",
                    "shipwright-keel-nemo-compat",
                ),
                ("shipwright-shoal-mail", "shipwright-keel-silica"),
            ],
            ..Fake::default()
        };
        let store = Store::new(fake, "shipwright-reef");
        let name = "shipwright-shoal-camera";
        let plan = futures_lite::future::block_on(store.preview_remove(name, None)).unwrap();
        assert_eq!(
            plan.items
                .iter()
                .map(|i| i.name.as_str())
                .collect::<Vec<_>>(),
            [name]
        );
        futures_lite::future::block_on(store.remove(name, &plan, &mut |_| {})).unwrap();
        let calls = store.pm.calls.borrow();
        assert_eq!(
            calls.last().unwrap(),
            r#"remove ["shipwright-shoal-camera;0.1.0-26;aarch64;installed"]"#
        );
    }

    /// `PackageKit` refuses the removal for a dependency Reef judged unused:
    /// the app still goes, with its parts, and the dependencies stay; the
    /// preview already shows that when the simulation refuses.
    #[test]
    fn a_refused_cascade_still_removes_the_app() {
        let both = |name: &'static str, v: &'static str| {
            [
                pkg(&format!("{name};{v};aarch64;installed")),
                pkg(&format!("{name};{v};aarch64;shipwright-reef")),
            ]
        };
        let available: Vec<PackageInfo> = [
            both("shoal-pilot", "0.1.0-29"),
            both("shoal-pilot-piper", "1.2.0-1"),
            both("shipwright-keel-mcp", "0.1.0-6"),
        ]
        .into_iter()
        .flatten()
        .collect();
        let fake = Fake {
            available,
            needs: vec![
                ("shoal-pilot", "shoal-pilot-piper"),
                ("shoal-pilot", "shipwright-keel-mcp"),
            ],
            ..Fake::default()
        };
        let store = Store::new(fake, "shipwright-reef");
        // The real removal refuses (the simulation did not).
        let plan =
            futures_lite::future::block_on(store.preview_remove("shoal-pilot", None)).unwrap();
        assert!(plan.items.iter().any(|i| i.name == "shipwright-keel-mcp"));
        store.pm.fail_once.set(Some(13));
        futures_lite::future::block_on(store.remove("shoal-pilot", &plan, &mut |_| {})).unwrap();
        let removes: Vec<String> = transactions(&store.pm.calls.borrow())
            .into_iter()
            .filter(|c| c.starts_with("remove"))
            .collect();
        assert_eq!(removes.len(), 2, "{removes:?}");
        assert!(removes[0].contains("shipwright-keel-mcp"), "{}", removes[0]);
        let minimal = r#"remove ["shoal-pilot;0.1.0-29;aarch64;installed", "shoal-pilot-piper;1.2.0-1;aarch64;installed"]"#;
        assert_eq!(removes[1], minimal);

        // The simulation refuses: the plan is the app and its parts, the
        // dependency stays, and the removal runs that plan.
        let refusing = Store::new(
            Fake {
                available: store.pm.available.clone(),
                needs: store.pm.needs.clone(),
                refuses_removing: Some("shipwright-keel-mcp"),
                ..Fake::default()
            },
            "shipwright-reef",
        );
        let plan =
            futures_lite::future::block_on(refusing.preview_remove("shoal-pilot", None)).unwrap();
        let got: Vec<(&str, Change)> = plan
            .items
            .iter()
            .map(|i| (i.name.as_str(), i.change))
            .collect();
        assert_eq!(
            got,
            [
                ("shoal-pilot", Change::Remove),
                ("shoal-pilot-piper", Change::Remove),
                ("shipwright-keel-mcp", Change::Keep),
            ]
        );
        futures_lite::future::block_on(refusing.remove("shoal-pilot", &plan, &mut |_| {})).unwrap();
        assert_eq!(
            transactions(&refusing.pm.calls.borrow()),
            [minimal],
            "the plan's removal, at once"
        );
    }

    /// A package changed outside `PackageKit` makes its queries fail while
    /// the removal is worked out (`RequiredBy` with the old id, on the
    /// phone): preview and removal reload `PackageKit`'s view and plan again.
    #[test]
    fn planning_with_a_stale_installed_view_reloads_it() {
        let fake = Fake {
            available: vec![
                pkg("shipwright-shoal-keys;0.1.0-11;aarch64;installed"),
                pkg("shipwright-shoal-keys;0.1.0-11;aarch64;shipwright-reef"),
            ],
            ..Fake::default()
        };
        let store = Store::new(fake, "shipwright-reef");
        store.pm.stale_query_once.set(true);
        let plan =
            futures_lite::future::block_on(store.preview_remove("shipwright-shoal-keys", None))
                .unwrap();
        assert!(store.pm.calls.borrow().iter().any(|c| c == "reload"));
        store.pm.calls.borrow_mut().clear();
        store.pm.stale_query_once.set(true);
        futures_lite::future::block_on(store.remove("shipwright-shoal-keys", &plan, &mut |_| {}))
            .unwrap();
        let calls = store.pm.calls.borrow();
        assert!(calls.iter().any(|c| c == "reload"), "{calls:?}");
        assert!(calls.iter().any(|c| c.starts_with("remove")), "{calls:?}");
    }

    /// Camera 27 needs nemo-compat, which needs its configuration part,
    /// which keel-silica needs too (Mail keeps silica): nemo-compat goes
    /// with Camera and the part stays (all of nemo-compat used to stay).
    #[test]
    fn a_dependency_goes_while_its_needed_part_stays() {
        let both = |name: &'static str, v: &'static str| {
            [
                pkg(&format!("{name};{v};aarch64;installed")),
                pkg(&format!("{name};{v};aarch64;shipwright-reef")),
            ]
        };
        let available: Vec<PackageInfo> = [
            both("shipwright-shoal-camera", "0.1.0-27"),
            both("shipwright-keel-nemo-compat", "0.1.0-8"),
            both("shipwright-keel-nemo-compat-configuration", "0.1.0-8"),
            both("shipwright-keel-silica", "0.1.0-29"),
            both("shipwright-shoal-mail", "0.1.0-10"),
        ]
        .into_iter()
        .flatten()
        .collect();
        let fake = Fake {
            available,
            needs: vec![
                ("shipwright-shoal-camera", "shipwright-keel-nemo-compat"),
                ("shipwright-shoal-camera", "shipwright-keel-silica"),
                (
                    "shipwright-keel-nemo-compat",
                    "shipwright-keel-nemo-compat-configuration",
                ),
                (
                    "shipwright-keel-silica",
                    "shipwright-keel-nemo-compat-configuration",
                ),
                ("shipwright-shoal-mail", "shipwright-keel-silica"),
            ],
            ..Fake::default()
        };
        let store = Store::new(fake, "shipwright-reef");
        let plan =
            futures_lite::future::block_on(store.preview_remove("shipwright-shoal-camera", None))
                .unwrap();
        futures_lite::future::block_on(store.remove("shipwright-shoal-camera", &plan, &mut |_| {}))
            .unwrap();
        let calls = store.pm.calls.borrow();
        let removed = calls
            .iter()
            .rev()
            .find(|c| c.starts_with("remove"))
            .unwrap();
        assert!(removed.contains("shipwright-shoal-camera;"), "{removed}");
        assert!(
            removed.contains("shipwright-keel-nemo-compat;"),
            "{removed}"
        );
        assert!(
            !removed.contains("shipwright-keel-nemo-compat-configuration"),
            "{removed}"
        );
        assert!(!removed.contains("shipwright-keel-silica"), "{removed}");
    }

    /// Pilot Lite (`harbour-shoal-pilot`) installed by Reef, as zypp reports
    /// it (a plain `installed`): Reef's record makes it Reef's to remove; a
    /// `harbour-` app Reef has no record of is not.
    #[test]
    fn a_harbour_app_reef_installed_is_reefs() {
        let lite = pkg("harbour-shoal-pilot;0.1.0-4;noarch;installed");
        let mut recorded = BTreeSet::new();
        assert!(harbour_not_reefs(&lite, "shipwright-reef", &recorded));
        recorded.insert("harbour-shoal-pilot".to_string());
        assert!(!harbour_not_reefs(&lite, "shipwright-reef", &recorded));
        let other = pkg("shipwright-shoal-keys;0.1.0-12;aarch64;installed");
        assert!(!harbour_not_reefs(
            &other,
            "shipwright-reef",
            &BTreeSet::new()
        ));
    }

    /// The fallback after a refused removal keeps what must go with the
    /// app: add-ons and services that require it (the earbuds app's services require
    /// the app since 0.1.0-8). Leaving them in made the fallback refused too.
    #[test]
    fn a_refused_cascade_keeps_what_requires_the_app() {
        let both = |name: &'static str, v: &'static str| {
            [
                pkg(&format!("{name};{v};aarch64;installed")),
                pkg(&format!("{name};{v};aarch64;shipwright-reef")),
            ]
        };
        let available: Vec<PackageInfo> = [
            both("shipwright-shoal-bridge-airpods-ui", "0.1.0-8"),
            both("shipwright-shoal-bridge-airpods", "2.0.11-6"),
            both("shipwright-shoal-bridge-airpods-volume", "0.1.0-3"),
            both("shipwright-keel-silica", "0.1.0-29"),
        ]
        .into_iter()
        .flatten()
        .collect();
        let ui = "shipwright-shoal-bridge-airpods-ui";
        let fake = Fake {
            available,
            needs: vec![
                (ui, "shipwright-shoal-bridge-airpods"),
                (ui, "shipwright-shoal-bridge-airpods-volume"),
                (ui, "shipwright-keel-silica"),
                ("shipwright-shoal-bridge-airpods", ui),
                ("shipwright-shoal-bridge-airpods-volume", ui),
            ],
            ..Fake::default()
        };
        let store = Store::new(fake, "shipwright-reef");
        let plan = futures_lite::future::block_on(store.preview_remove(ui, None)).unwrap();
        store.pm.fail_once.set(Some(13));
        futures_lite::future::block_on(store.remove(ui, &plan, &mut |_| {})).unwrap();
        let removes: Vec<String> = transactions(&store.pm.calls.borrow())
            .into_iter()
            .filter(|c| c.starts_with("remove"))
            .collect();
        assert_eq!(removes.len(), 2, "{removes:?}");
        assert!(
            removes[0].contains("shipwright-keel-silica"),
            "{}",
            removes[0]
        );
        for goes in [
            "shipwright-shoal-bridge-airpods-ui;",
            "shipwright-shoal-bridge-airpods;",
            "shipwright-shoal-bridge-airpods-volume;",
        ] {
            assert!(
                removes[1].contains(goes),
                "{goes} in the fallback: {}",
                removes[1]
            );
        }
        assert!(
            !removes[1].contains("shipwright-keel-silica"),
            "{}",
            removes[1]
        );
    }

    /// A package updated outside `PackageKit` (rpm -U) leaves it with the
    /// old id: the removal fails with error 8; Reef refreshes and removes.
    #[test]
    fn a_removal_with_a_stale_installed_id_is_refreshed_and_tried_again() {
        let fake = Fake {
            available: vec![
                pkg("shipwright-shoal-camera;0.1.0-27;aarch64;installed"),
                pkg("shipwright-shoal-camera;0.1.0-27;aarch64;shipwright-reef"),
            ],
            ..Fake::default()
        };
        let store = Store::new(fake, "shipwright-reef");
        let plan =
            futures_lite::future::block_on(store.preview_remove("shipwright-shoal-camera", None))
                .unwrap();
        store.pm.fail_once.set(Some(8));
        futures_lite::future::block_on(store.remove("shipwright-shoal-camera", &plan, &mut |_| {}))
            .unwrap();
        let calls = store.pm.calls.borrow();
        let removes = calls.iter().filter(|c| c.starts_with("remove")).count();
        assert_eq!(removes, 2, "{calls:?}");
        assert!(calls.iter().any(|c| c == "reload"), "{calls:?}");
        assert!(
            calls.iter().any(|c| c == "refresh shipwright-reef"),
            "{calls:?}"
        );
    }

    /// `PackageKit`'s view is stale after another removal: the repository's
    /// copies are missing, so the app's command-line part looked foreign
    /// and stayed. Removal refreshes first and takes it.
    #[test]
    fn a_stale_pool_is_refreshed_before_a_removal() {
        let fake = Fake {
            available: vec![
                pkg("shipwright-shoal-migrate;0.1.0-9;aarch64;installed"),
                pkg("shipwright-shoal-migrate-cli;0.1.0-9;aarch64;installed"),
            ],
            after_refresh: vec![
                pkg("shipwright-shoal-migrate;0.1.0-9;aarch64;shipwright-reef"),
                pkg("shipwright-shoal-migrate-cli;0.1.0-9;aarch64;shipwright-reef"),
            ],
            ..Fake::default()
        };
        let store = Store::new(fake, "shipwright-reef");
        let name = "shipwright-shoal-migrate";
        let plan = futures_lite::future::block_on(store.preview_remove(name, None)).unwrap();
        futures_lite::future::block_on(store.remove(name, &plan, &mut |_| {})).unwrap();
        let calls = store.pm.calls.borrow();
        assert!(
            calls.iter().any(|c| c == "refresh shipwright-reef"),
            "{calls:?}"
        );
        assert!(
            calls
                .last()
                .unwrap()
                .contains("shipwright-shoal-migrate-cli;"),
            "{calls:?}"
        );
    }

    /// Nothing is installed, updated or removed that the person did not
    /// see: the preview lists every package with its label, and a
    /// transaction that would now do more is refused before it starts.
    #[test]
    fn only_what_the_person_saw_is_installed() {
        let cat = Catalogue::parse(
            br#"{"schema":1,"release":"5.2.0.18","arch":"aarch64",
              "components": {"airpods-service": {"summary": "Earbuds service",
                 "services": [{"name": "airpods.service", "starts": "login",
                               "description": "Keeps the earbuds connected"}]}},
              "packages": [{"name":"airpods-ui","version":"1-1","title":"AirPods","summary":"s",
                 "tested_on":["5.2.0.18"],"licence":{"model":"free"}}]}"#,
            "aarch64",
        )
        .unwrap();
        let fake = Fake {
            available: vec![pkg("airpods-ui;1-1;aarch64;shipwright-reef")],
            brings: RefCell::new(vec![PackageInfo {
                info: Info::Installing,
                id: PackageId::parse("airpods-service;2-1;aarch64;shipwright-reef").unwrap(),
                summary: String::new(),
            }]),
            ..Fake::default()
        };
        let (ledger, dir) = ledger("approve", &[], &[]);
        let store = Store::new(fake, "shipwright-reef").with_ledger(Some(ledger.clone()));
        futures_lite::future::block_on(async {
            let plan = store
                .preview_install("airpods-ui", Some(&cat))
                .await
                .unwrap();
            let got: Vec<(&str, Kind, Change)> = plan
                .items
                .iter()
                .map(|i| (i.name.as_str(), i.kind, i.change))
                .collect();
            assert_eq!(
                got,
                [
                    ("airpods-ui", Kind::App, Change::Install),
                    ("airpods-service", Kind::BackgroundService, Change::Install),
                ]
            );
            assert_eq!(plan.items[1].services[0].starts, "login");
            assert_eq!(plan.download_size, Some(2000));

            // The repository changed: the install now brings something more.
            store.pm.brings.borrow_mut().push(PackageInfo {
                info: Info::Installing,
                id: PackageId::parse("tracker;1-1;aarch64;shipwright-reef").unwrap(),
                summary: String::new(),
            });
            assert!(matches!(
                store.install("airpods-ui", &plan, &mut |_| {}).await,
                Err(Error::PlanChanged)
            ));
            // A plan for something else is no approval either.
            store.pm.brings.borrow_mut().pop();
            let mut other = plan.clone();
            other.target = "something-else".into();
            assert!(matches!(
                store.install("airpods-ui", &other, &mut |_| {}).await,
                Err(Error::PlanChanged)
            ));
            assert!(transactions(&store.pm.calls.borrow()).is_empty());
            // As seen: installed, and the service recorded as pulled in.
            store
                .install("airpods-ui", &plan, &mut |_| {})
                .await
                .unwrap();
        });
        assert_eq!(
            transactions(&store.pm.calls.borrow()),
            [r#"install ["airpods-ui;1-1;aarch64;shipwright-reef"]"#]
        );
        assert!(ledger.names().contains("airpods-ui"));
        assert!(ledger.pulled_in().contains("airpods-service"));
        assert!(!ledger.names().contains("airpods-service"));
        std::fs::remove_dir_all(dir).unwrap();
    }

    /// The forum's earbuds app: removing it left its service running and
    /// scanning. Everything of Reef's that only it needed goes with it, and
    /// its add-on; Keel (another app needs it) and the OS's packages stay.
    #[test]
    fn an_app_goes_with_what_only_it_needed() {
        let both = |name: &'static str, v: &'static str| {
            [
                pkg(&format!("{name};{v};aarch64;installed")),
                pkg(&format!("{name};{v};aarch64;shipwright-reef")),
            ]
        };
        let mut available: Vec<PackageInfo> = [
            both("shipwright-shoal-bridge-airpods-ui", "0.1.0-7"),
            both("shipwright-shoal-bridge-airpods", "2.0.11-5"),
            both("shipwright-shoal-bridge-airpods-volume", "0.1.0-2"),
            both("shipwright-shoal-bridge-airpods-vendorid", "0.1.0-1"),
            both("shipwright-keel-silica", "0.1.0-9"),
            both("shipwright-shoal-mail", "0.1.0-4"),
        ]
        .into_iter()
        .flatten()
        .collect();
        available.push(pkg("bluez5;5.66-1;aarch64;installed"));
        available.push(pkg("bluez5;5.66-1;aarch64;jolla"));
        let fake = Fake {
            available,
            needs: vec![
                (
                    "shipwright-shoal-bridge-airpods-ui",
                    "shipwright-shoal-bridge-airpods",
                ),
                (
                    "shipwright-shoal-bridge-airpods-ui",
                    "shipwright-shoal-bridge-airpods-volume",
                ),
                (
                    "shipwright-shoal-bridge-airpods-ui",
                    "shipwright-keel-silica",
                ),
                (
                    "shipwright-shoal-bridge-airpods-vendorid",
                    "shipwright-shoal-bridge-airpods",
                ),
                ("shipwright-shoal-bridge-airpods", "bluez5"),
                ("shipwright-shoal-bridge-airpods-volume", "bluez5"),
                ("shipwright-shoal-mail", "shipwright-keel-silica"),
            ],
            ..Fake::default()
        };
        // The person installed the app, mail and the Device ID add-on;
        // the service, volume watcher and Keel came with the app.
        let (ledger, dir) = ledger(
            "earbuds",
            &[
                "shipwright-shoal-bridge-airpods-ui",
                "shipwright-shoal-mail",
            ],
            &[
                "shipwright-shoal-bridge-airpods",
                "shipwright-shoal-bridge-airpods-volume",
                "shipwright-shoal-bridge-airpods-vendorid",
                "shipwright-keel-silica",
            ],
        );
        let store = Store::new(fake, "shipwright-reef").with_ledger(Some(ledger));
        let name = "shipwright-shoal-bridge-airpods-ui";
        let plan = futures_lite::future::block_on(store.preview_remove(name, None)).unwrap();
        futures_lite::future::block_on(store.remove(name, &plan, &mut |_| {})).unwrap();
        let calls = store.pm.calls.borrow();
        let removed = calls.iter().find(|c| c.starts_with("remove")).unwrap();
        for gone in [
            "shipwright-shoal-bridge-airpods-ui;",
            "shipwright-shoal-bridge-airpods;",
            "shipwright-shoal-bridge-airpods-volume;",
            "shipwright-shoal-bridge-airpods-vendorid;",
        ] {
            assert!(removed.contains(gone), "{gone} in {removed}");
            let n = gone.trim_end_matches(';');
            assert!(plan
                .items
                .iter()
                .any(|i| i.name == n && i.change == Change::Remove));
        }
        for stays in ["shipwright-keel-silica", "bluez5", "shipwright-shoal-mail"] {
            assert!(!removed.contains(stays), "{stays} in {removed}");
            assert!(!plan.items.iter().any(|i| i.name == stays));
        }
        let why = |n: &str| plan.items.iter().find(|i| i.name == n).unwrap().reason;
        assert_eq!(why(name), Some(Reason::Asked));
        assert_eq!(
            why("shipwright-shoal-bridge-airpods"),
            Some(Reason::OnlyFor)
        );
        // The Device ID add-on needs the service: it would stop working.
        assert_eq!(
            why("shipwright-shoal-bridge-airpods-vendorid"),
            Some(Reason::Part)
        );
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn what_reef_cannot_tell_it_installed_stays_and_the_person_is_told() {
        // Installed before the ledger recorded what came with an app, and
        // offered by Chum as well as Reef: Reef cannot tell it installed
        // the service. It stays, shown as staying; an app that needs what
        // goes is marked as one that stops working.
        let both = |name: &str| {
            [
                pkg(&format!("{name};1-1;aarch64;installed")),
                pkg(&format!("{name};1-1;aarch64;shipwright-reef")),
            ]
        };
        let fake = Fake {
            available: [both("keel"), both("service"), both("mail")]
                .into_iter()
                .flatten()
                .chain([pkg("service;1-1;aarch64;sailfishos-chum")])
                .collect(),
            needs: vec![("keel", "service"), ("mail", "keel")],
            ..Fake::default()
        };
        let (ledger, dir) = ledger("kept", &["keel", "mail"], &[]);
        let store = Store::new(fake, "shipwright-reef").with_ledger(Some(ledger));
        let plan = futures_lite::future::block_on(store.preview_remove("keel", None)).unwrap();
        let got: Vec<(&str, Change, bool)> = plan
            .items
            .iter()
            .map(|i| (i.name.as_str(), i.change, i.stops_working))
            .collect();
        assert_eq!(
            got,
            [
                ("keel", Change::Remove, false),
                ("mail", Change::Remove, true),
                ("service", Change::Keep, false),
            ]
        );
        // An OS package needs it: PackageKit's simulation says so before
        // anything happens.
        let refusing = Store::new(
            Fake {
                remove_refused: Some(13),
                ..store.pm
            },
            "shipwright-reef",
        )
        .with_ledger(store.ledger.clone());
        let e = futures_lite::future::block_on(refusing.preview_remove("keel", None)).unwrap_err();
        assert!(
            e.to_string().starts_with("Other installed software needs"),
            "{e}"
        );
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn an_app_goes_with_its_parts_and_nothing_else() {
        let fake = Fake {
            available: vec![
                pkg("shoal-pilot;0.1.0-23;aarch64;installed"),
                pkg("shoal-pilot;0.1.0-23;aarch64;shipwright-reef"),
                // Its gesture patch (needs Pilot) and its voice (Pilot needs it).
                pkg("shoal-pilot-gesture-patch;0.4.0-2;noarch;installed"),
                pkg("shoal-pilot-gesture-patch;0.4.0-2;noarch;shipwright-reef"),
                pkg("shoal-pilot-piper;1.2.0-1;aarch64;installed"),
                pkg("shoal-pilot-piper;1.2.0-1;aarch64;shipwright-reef"),
                // Named alike, but an OS package: never Reef's to remove.
                pkg("shoal-pilot-extras;1-1;aarch64;installed"),
                pkg("shoal-pilot-extras;1-1;aarch64;jolla"),
                // Another app whose name starts the same.
                pkg("shoal-pilotage;1-1;aarch64;installed"),
                pkg("shoal-pilotage;1-1;aarch64;shipwright-reef"),
            ],
            ..Fake::default()
        };
        let (ledger, dir) = ledger(
            "parts",
            &["shoal-pilot", "shoal-pilot-gesture-patch", "shoal-pilotage"],
            &["shoal-pilot-piper"],
        );
        let store = Store::new(fake, "shipwright-reef").with_ledger(Some(ledger));
        let plan =
            futures_lite::future::block_on(store.preview_remove("shoal-pilot", None)).unwrap();
        futures_lite::future::block_on(store.remove("shoal-pilot", &plan, &mut |_| {})).unwrap();
        let calls = store.pm.calls.borrow();
        assert_eq!(
            calls.last().unwrap(),
            r#"remove ["shoal-pilot;0.1.0-23;aarch64;installed", "shoal-pilot-gesture-patch;0.4.0-2;noarch;installed", "shoal-pilot-piper;1.2.0-1;aarch64;installed"]"#
        );
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn a_dependency_failure_says_what_happened() {
        let e = Error::Transaction {
            exit: crate::packagekit::Exit::Failed,
            error: Some((13, "shoal-pilot-gesture-patch requires shoal-pilot".into())),
        };
        assert!(e
            .to_string()
            .starts_with("Other installed software needs this package"));
    }

    /// Fix 8: a catalogue app is Reef's to remove when the ledger names it,
    /// `PackageKit` names Reef's repository as its origin, or (zypp's plain
    /// `installed`, and installs from before the ledger) the Reef
    /// repository offers it; a Jolla Store app or a package from another
    /// repository never is.
    #[test]
    fn only_reef_packages_count_as_installed_or_removable() {
        // B-06: the catalogue names an OS package; Reef must not claim it.
        let json = r#"{"schema":1,"release":"5.2.0.17","arch":"aarch64","packages":[
            {"name":"bash","version":"5-1","title":"Bash","summary":"s",
             "tested_on":["5.2.0.17"],"licence":{"model":"free"}},
            {"name":"weather","version":"1-1","title":"Weather","summary":"s",
             "tested_on":["5.2.0.17"],"licence":{"model":"free"}},
            {"name":"notes","version":"1-1","title":"Notes","summary":"s",
             "tested_on":["5.2.0.17"],"licence":{"model":"free"}},
            {"name":"harbour-maps","version":"1-1","title":"Maps","summary":"s",
             "tested_on":["5.2.0.17"],"licence":{"model":"free"}},
            {"name":"harbour-notes","version":"1-1","title":"Notes","summary":"s",
             "tested_on":["5.2.0.17"],"licence":{"model":"free"}},
            {"name":"chum-app","version":"1-1","title":"Chum app","summary":"s",
             "tested_on":["5.2.0.17"],"licence":{"model":"free"}}]}"#;
        let cat = Catalogue::parse(json.as_bytes(), "aarch64").unwrap();
        let fake = Fake {
            available: vec![
                pkg("bash;5.2-1;aarch64;installed"),
                pkg("bash;5.2-1;aarch64;jolla"),
                // zypp: plain "installed", with the Reef repository's copy:
                // an early user's install, before the ledger.
                pkg("weather;1-1;aarch64;installed"),
                pkg("weather;1-1;aarch64;shipwright-reef"),
                // A backend that names the origin.
                pkg("notes;1-1;aarch64;installed:shipwright-reef"),
                // Reef installed it (PackageKit names Reef's repository):
                // Reef's to remove, whatever its name.
                pkg("harbour-maps;1-1;aarch64;installed:shipwright-reef"),
                // From the Jolla Store: Reef offers the name, but neither
                // Reef's record nor the origin says Reef installed it.
                pkg("harbour-notes;1-1;aarch64;installed"),
                pkg("harbour-notes;1-1;aarch64;shipwright-reef"),
                // Installed from Chum, though the ledger names it.
                pkg("chum-app;1-1;aarch64;installed:sailfishos-chum"),
                pkg("chum-app;1-1;aarch64;shipwright-reef"),
            ],
            ..Fake::default()
        };
        let (ledger, dir) = ledger("owned", &["harbour-maps", "chum-app"], &[]);
        let store = Store::new(fake, "shipwright-reef").with_ledger(Some(ledger));
        futures_lite::future::block_on(async {
            let installed = store.installed(&cat).await.unwrap();
            let names: Vec<&str> = installed.iter().map(|p| p.id.name.as_str()).collect();
            assert_eq!(names, ["weather", "notes", "harbour-maps", "harbour-notes"]);
            assert_eq!(
                store.removable(&installed),
                ["weather", "notes", "harbour-maps"]
            );
            assert!(matches!(
                store.preview_remove("bash", None).await,
                Err(Error::NotReefs(_))
            ));
            // Reef installed harbour-maps (its origin says so): removable.
            assert!(store.preview_remove("harbour-maps", None).await.is_ok());
            for name in ["harbour-notes", "chum-app"] {
                assert!(
                    matches!(
                        store.preview_remove(name, None).await,
                        Err(Error::NotReefs(_))
                    ),
                    "{name}"
                );
            }
            assert!(matches!(
                store.preview_remove("absent", None).await,
                Err(Error::NotFound(_))
            ));
            let plan = store.preview_remove("notes", None).await.unwrap();
            store.remove("notes", &plan, &mut |_| {}).await.unwrap();
            // A plan for notes does not remove weather.
            assert!(store.remove("weather", &plan, &mut |_| {}).await.is_err());
            let plan = store.preview_remove("weather", None).await.unwrap();
            store.remove("weather", &plan, &mut |_| {}).await.unwrap();
        });
        let removes: Vec<String> = transactions(&store.pm.calls.borrow())
            .into_iter()
            .filter(|c| c.starts_with("remove"))
            .collect();
        assert_eq!(
            removes,
            [
                r#"remove ["notes;1-1;aarch64;installed:shipwright-reef"]"#,
                r#"remove ["weather;1-1;aarch64;installed"]"#
            ]
        );
        std::fs::remove_dir_all(dir).unwrap();
    }

    /// An early user's app, installed before Reef kept a record: with zypp's
    /// plain `installed` everywhere, the app and what only the Reef
    /// repository offers go with it; Qt, which Chum offers too (Reef
    /// mirrors it), and a Jolla Store package stay, whatever needs them.
    #[test]
    fn an_early_install_goes_with_what_only_reef_offers() {
        let installed = |name: &str| pkg(&format!("{name};1-1;aarch64;installed"));
        let offer = |name: &str, repo: &str| pkg(&format!("{name};1-1;aarch64;{repo}"));
        let fake = Fake {
            available: vec![
                installed("shipwright-shoal-keys"),
                offer("shipwright-shoal-keys", "shipwright-reef"),
                installed("shipwright-keel-silica"),
                offer("shipwright-keel-silica", "shipwright-reef"),
                installed("qt6-qtbase"),
                offer("qt6-qtbase", "shipwright-reef"),
                offer("qt6-qtbase", "sailfishos-chum"),
                installed("harbour-helper"),
                offer("harbour-helper", "shipwright-reef"),
            ],
            needs: vec![
                ("shipwright-shoal-keys", "shipwright-keel-silica"),
                ("shipwright-shoal-keys", "qt6-qtbase"),
                ("shipwright-shoal-keys", "harbour-helper"),
                ("shipwright-keel-silica", "qt6-qtbase"),
            ],
            ..Fake::default()
        };
        // No ledger at all.
        let store = Store::new(fake, "shipwright-reef");
        let name = "shipwright-shoal-keys";
        let plan = futures_lite::future::block_on(store.preview_remove(name, None)).unwrap();
        let got: Vec<(&str, Change)> = plan
            .items
            .iter()
            .map(|i| (i.name.as_str(), i.change))
            .collect();
        assert_eq!(
            got,
            [
                (name, Change::Remove),
                ("shipwright-keel-silica", Change::Remove),
                ("harbour-helper", Change::Keep),
                ("qt6-qtbase", Change::Keep),
            ]
        );
        futures_lite::future::block_on(store.remove(name, &plan, &mut |_| {})).unwrap();
        let calls = transactions(&store.pm.calls.borrow());
        let removed = calls.iter().find(|c| c.starts_with("remove")).unwrap();
        assert!(removed.contains("shipwright-keel-silica;"), "{removed}");
        for stays in ["qt6-qtbase", "harbour-helper"] {
            assert!(!removed.contains(stays), "{stays} in {removed}");
        }
    }

    #[test]
    fn installs_stay_reefs_without_the_repository() {
        // The Reef repository is disabled (or the build withdrawn): Resolve
        // returns only the installed copy, with zypp's plain "installed".
        let (ledger, dir) = ledger("norepo", &[], &[]);
        let json = r#"{"schema":1,"release":"5.2.0.17","arch":"aarch64","packages":[
            {"name":"weather","version":"1-1","title":"Weather","summary":"s",
             "tested_on":["5.2.0.17"],"licence":{"model":"free"}},
            {"name":"bash","version":"5-1","title":"Bash","summary":"s",
             "tested_on":["5.2.0.17"],"licence":{"model":"free"}}]}"#;
        let cat = Catalogue::parse(json.as_bytes(), "aarch64").unwrap();
        // Installed through Reef while the repository was there.
        let installing = Store::new(
            Fake {
                available: vec![pkg("weather;1-1;aarch64;shipwright-reef")],
                ..Fake::default()
            },
            "shipwright-reef",
        )
        .with_ledger(Some(ledger.clone()));
        futures_lite::future::block_on(async {
            let plan = installing.preview_install("weather", None).await.unwrap();
            installing.install("weather", &plan, &mut |_| {}).await
        })
        .unwrap();
        assert!(ledger.names().contains("weather"));

        let store = Store::new(
            Fake {
                available: vec![
                    pkg("weather;1-1;aarch64;installed"),
                    pkg("bash;5.2-1;aarch64;installed"),
                ],
                ..Fake::default()
            },
            "shipwright-reef",
        )
        .with_ledger(Some(ledger.clone()));
        futures_lite::future::block_on(async {
            let names: Vec<String> = store
                .installed(&cat)
                .await
                .unwrap()
                .into_iter()
                .map(|p| p.id.name)
                .collect();
            assert_eq!(names, ["weather"], "bash is still not Reef's");
            let plan = store.preview_remove("weather", None).await.unwrap();
            store.remove("weather", &plan, &mut |_| {}).await.unwrap();
            assert!(store.preview_remove("bash", None).await.is_err());
        });
        assert!(!ledger.names().contains("weather"), "removal forgets it");
        // Without the ledger the old rule applies: no repo copy, not Reef's.
        let bare = Store::new(
            Fake {
                available: vec![pkg("weather;1-1;aarch64;installed")],
                ..Fake::default()
            },
            "shipwright-reef",
        );
        let names = futures_lite::future::block_on(bare.installed(&cat)).unwrap();
        assert!(names.is_empty());
        std::fs::remove_dir_all(dir).unwrap();
    }

    /// Fix 5: the ledger is the owner's only, and a world-writable one left
    /// by an earlier Reef is repaired.
    #[test]
    fn an_unreadable_ledger_is_never_overwritten() {
        let (ledger, dir) = ledger("unreadable", &["a"], &[]);
        let path = dir.join("shipwright-reef/installed.json");
        std::fs::write(&path, b"[\"a\", truncated").unwrap();
        assert!(ledger.names().is_empty(), "shown as empty");
        assert!(ledger.record("b").is_err(), "a corrupt file is not rewritten");
        assert!(ledger.forget("a").is_err());
        assert_eq!(
            std::fs::read(&path).unwrap(),
            b"[\"a\", truncated",
            "the person's records stay on disk"
        );
        // A missing file is a new, empty ledger.
        std::fs::remove_file(&path).unwrap();
        ledger.record("b").unwrap();
        assert!(ledger.names().contains("b"));
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn the_ledger_is_private() {
        use std::os::unix::fs::PermissionsExt;
        let mode = |p: &Path| std::fs::metadata(p).unwrap().permissions().mode() & 0o7777;
        let (ledger, dir) = ledger("private", &["a"], &["b"]);
        let data = dir.join("shipwright-reef");
        assert_eq!(mode(&data), 0o700);
        assert_eq!(mode(&data.join("installed.json")), 0o600);
        assert_eq!(mode(&data.join("pulled-in.json")), 0o600);
        // As Reef 27 left them on a phone.
        std::fs::set_permissions(&data, std::fs::Permissions::from_mode(0o777)).unwrap();
        for f in ["installed.json", "pulled-in.json"] {
            std::fs::set_permissions(data.join(f), std::fs::Permissions::from_mode(0o666)).unwrap();
        }
        ledger.repair_permissions().unwrap();
        assert_eq!(mode(&data), 0o700);
        assert_eq!(mode(&data.join("installed.json")), 0o600);
        assert_eq!(mode(&data.join("pulled-in.json")), 0o600);
        // Recording again keeps them private, and forgetting covers both.
        ledger.record("b").unwrap();
        assert!(ledger.names().contains("b") && !ledger.pulled_in().contains("b"));
        ledger.forget("b").unwrap();
        assert_eq!(ledger.all(), BTreeSet::from(["a".to_string()]));
        assert_eq!(mode(&data.join("installed.json")), 0o600);
        // Nothing there yet: nothing to repair, no error.
        InstallLedger::new(dir.join("none/installed.json"))
            .repair_permissions()
            .unwrap();
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn an_app_at_the_repository_version_is_installed() {
        // zypp: the installed copy alone in an unfiltered resolve; the Reef
        // repository's identical copy only in a NotInstalled one.
        let json = r#"{"schema":1,"release":"5.2.0.18","arch":"aarch64","packages":[
            {"name":"shoal-pilot","version":"0.1.0-5","title":"Pilot","summary":"s",
             "tested_on":["5.2.0.18"],"licence":{"model":"free"}}]}"#;
        let cat = Catalogue::parse(json.as_bytes(), "aarch64").unwrap();
        let store = Store::new(
            Fake {
                available: vec![pkg("shoal-pilot;0.1.0-5;aarch64;installed")],
                offers: vec![pkg("shoal-pilot;0.1.0-5;aarch64;shipwright-reef")],
                ..Fake::default()
            },
            "shipwright-reef",
        );
        let names: Vec<String> = futures_lite::future::block_on(store.installed(&cat))
            .unwrap()
            .into_iter()
            .map(|p| p.id.name)
            .collect();
        assert_eq!(names, ["shoal-pilot"]);
    }

    #[test]
    fn install_picks_reef_build_and_update_skips_system() {
        let fake = Fake {
            available: vec![
                // Same name in another repository: must not be chosen.
                pkg("shipwright-keel-silica;9.9-1;aarch64;someone-else"),
                pkg("shipwright-keel-silica;0.1.0-1;aarch64;shipwright-reef"),
            ],
            updates: vec![
                pkg("shipwright-keel-silica;0.2.0-1;aarch64;shipwright-reef"),
                pkg("glibc;2.99-1;aarch64;jolla"),
            ],
            ..Fake::default()
        };
        let store = Store::new(fake, "shipwright-reef");
        let keel = "shipwright-keel-silica";
        futures_lite::future::block_on(async {
            let install = store.preview_install(keel, None).await.unwrap();
            store.install(keel, &install, &mut |_| {}).await.unwrap();
            let all = store.preview_update_all(None).await.unwrap();
            // Update all lists only Reef's update, never glibc.
            assert_eq!(
                all.items
                    .iter()
                    .map(|i| i.name.as_str())
                    .collect::<Vec<_>>(),
                [keel]
            );
            assert_eq!(store.update_all(&all, &mut |_| {}).await.unwrap(), 1);
            assert!(store.preview_install("absent", None).await.is_err());
            // A-06: one package, Reef's update only.
            let one = store.preview_update(keel, None).await.unwrap().unwrap();
            assert!(store.update(keel, &one, &mut |_| {}).await.unwrap());
            assert!(store.preview_update("glibc", None).await.unwrap().is_none());
            assert!(!store.update("glibc", &one, &mut |_| {}).await.unwrap());
        });
        let calls = transactions(&store.pm.calls.borrow());
        assert_eq!(
            calls,
            [
                r#"install ["shipwright-keel-silica;0.1.0-1;aarch64;shipwright-reef"]"#,
                r#"update ["shipwright-keel-silica;0.2.0-1;aarch64;shipwright-reef"]"#,
                // "absent" is looked for again after one refresh.
                "refresh shipwright-reef",
                r#"update ["shipwright-keel-silica;0.2.0-1;aarch64;shipwright-reef"]"#,
            ],
            "glibc is never updated"
        );
    }

    /// Pacific's engine comes in two builds: the install asks for the one
    /// this processor runs, with the app, in one transaction, and records
    /// it as having come with the app.
    #[test]
    fn installs_the_engine_build_the_cpu_runs() {
        let json = r#"{"schema":1,"release":"5.2.0.18","arch":"aarch64",
            "components":{
              "engine":{"summary":"ARMv8.2","requires_cpu":["asimddp","lrcpc"]},
              "engine-armv80":{"summary":"ARMv8.0"}},
            "packages":[
              {"name":"pacific","version":"1-1","title":"Pacific","summary":"s","tested_on":["5.2.0.18"],
               "requires":["engine","engine-armv80"],"variants":[["engine","engine-armv80"]],
               "licence":{"model":"free"}}]}"#;
        let cat = Catalogue::parse(json.as_bytes(), "aarch64").unwrap();
        let xperia = crate::catalogue::parse_cpu_features(
            "Features\t: fp asimd evtstrm aes pmull sha1 sha2 crc32 cpuid\n",
        );
        let jolla = crate::catalogue::parse_cpu_features(
            "Features\t: fp asimd aes crc32 atomics fphp asimdhp lrcpc dcpop asimddp\n",
        );
        let available = || {
            vec![
                pkg("pacific;1-1;aarch64;shipwright-reef"),
                pkg("engine;2-1;aarch64;shipwright-reef"),
                pkg("engine-armv80;2-1;aarch64;shipwright-reef"),
            ]
        };
        for (cpu, build) in [(xperia, "engine-armv80"), (jolla, "engine")] {
            let (ledger, dir) = ledger(&format!("variants-{build}"), &[], &[]);
            let fake = Fake {
                available: available(),
                ..Fake::default()
            };
            let store = Store::new(fake, "shipwright-reef")
                .with_ledger(Some(ledger.clone()))
                .with_cpu_features(cpu);
            futures_lite::future::block_on(async {
                let plan = store.preview_install("pacific", Some(&cat)).await.unwrap();
                assert_eq!(plan.alongside, [build]);
                let requested: Vec<_> = plan
                    .items
                    .iter()
                    .map(|i| (i.name.as_str(), i.requested))
                    .collect();
                assert!(requested.contains(&("pacific", true)), "{requested:?}");
                assert!(requested.contains(&(build, false)), "{requested:?}");
                store.install("pacific", &plan, &mut |_| {}).await.unwrap();
            });
            let calls = transactions(&store.pm.calls.borrow());
            assert_eq!(
                calls,
                [format!(
                    "install [\"pacific;1-1;aarch64;shipwright-reef\", \"{build};2-1;aarch64;shipwright-reef\"]"
                )]
            );
            assert_eq!(ledger.names(), BTreeSet::from(["pacific".to_string()]));
            assert_eq!(ledger.pulled_in(), BTreeSet::from([build.to_string()]));
            let _ = std::fs::remove_dir_all(dir);
        }
    }

    /// A build of the group is installed already: it stays, and nothing
    /// else is asked for. No build runs here: nothing is installed.
    #[test]
    fn an_installed_engine_build_stays_and_none_runnable_fails() {
        let json = r#"{"schema":1,"release":"5.2.0.18","arch":"aarch64",
            "components":{"engine":{"summary":"ARMv8.2","requires_cpu":["asimddp"]},
                          "engine-armv80":{"summary":"ARMv8.0","requires_cpu":["crc32"]}},
            "packages":[
              {"name":"pacific","version":"1-1","title":"Pacific","summary":"s","tested_on":["5.2.0.18"],
               "variants":[["engine","engine-armv80"]],"licence":{"model":"free"}}]}"#;
        let cat = Catalogue::parse(json.as_bytes(), "aarch64").unwrap();
        let fake = Fake {
            available: vec![
                pkg("pacific;1-1;aarch64;shipwright-reef"),
                pkg("engine-armv80;2-1;aarch64;installed"),
                pkg("engine;2-1;aarch64;shipwright-reef"),
            ],
            ..Fake::default()
        };
        let store = Store::new(fake, "shipwright-reef").with_cpu_features(
            crate::catalogue::parse_cpu_features("Features\t: fp asimd crc32 asimddp\n"),
        );
        futures_lite::future::block_on(async {
            let plan = store.preview_install("pacific", Some(&cat)).await.unwrap();
            assert!(plan.alongside.is_empty());
            // Without a catalogue (tools), nothing is added either.
            let no_catalogue = store.preview_install("pacific", None).await.unwrap();
            assert!(no_catalogue.alongside.is_empty());
        });
        let store = store.with_cpu_features(crate::catalogue::parse_cpu_features(
            "Features\t: fp asimd\n",
        ));
        futures_lite::future::block_on(async {
            let err = store
                .preview_install("pacific", Some(&cat))
                .await
                .unwrap_err();
            assert!(matches!(err, Error::NoBuild(..)), "{err}");
        });
        assert!(transactions(&store.pm.calls.borrow()).is_empty());
    }
}
