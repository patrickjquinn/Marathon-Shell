// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

//! What an install, update or removal will do, before it does it.
//!
//! Reef asks before every install, update and removal, and shows everything
//! that comes with it (Sailfish forum, October 2026: the store "installs
//! stuff in the background without asking"). A [`Plan`] is that list: every
//! package the transaction touches, from `PackageKit`'s own simulation of
//! it (`TRANSACTION_FLAG_SIMULATE`) and, for a removal, Reef's own cascade
//! ([`crate::store::Store::remove`]), each labelled from the catalogue's
//! disclosures as an app, an add-on, a library or a background service.
//!
//! The person agrees to a plan; the store then runs a transaction only if
//! it still does what the plan says ([`Plan::covers`]), so nothing is
//! installed or removed that the person did not see.

use serde::Serialize;

use crate::catalogue::{Catalogue, Service};
use crate::packagekit::{Info, PackageId, PackageInfo};

/// What the person asked for.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Action {
    Install,
    Update,
    UpdateAll,
    Remove,
}

/// What happens to one package.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Change {
    Install,
    Update,
    Remove,
    Reinstall,
    Downgrade,
    /// A removal leaves it installed: Reef's repository offers it and only
    /// what goes needed it, but Reef has no record of installing it, so it
    /// is not Reef's to remove. Shown so the person knows it stays.
    Keep,
}

impl Change {
    /// The change a simulated transaction's `Package` signal announces;
    /// `default` for a backend that sends a plain info.
    pub fn from_info(info: Info, default: Change) -> Change {
        match info {
            Info::Installing => Change::Install,
            Info::Updating => Change::Update,
            Info::Removing | Info::Obsoleting => Change::Remove,
            Info::Reinstalling => Change::Reinstall,
            Info::Downgrading => Change::Downgrade,
            _ => default,
        }
    }

    /// Whether the package is downloaded.
    pub fn downloads(self) -> bool {
        matches!(
            self,
            Change::Install | Change::Update | Change::Reinstall | Change::Downgrade
        )
    }
}

/// What a package is, for the person.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Kind {
    /// Something with a launcher icon.
    App,
    /// Listed in the store for an app, with no launcher of its own (Pilot's
    /// gesture bar).
    AddOn,
    /// Code other packages use.
    Library,
    /// Runs by itself: ships systemd units, or runs outside the sandbox.
    BackgroundService,
}

/// Why a package is in a removal.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Reason {
    /// The person asked for it.
    Asked,
    /// Named after what goes (`shoal-pilot-gesture-patch` for `shoal-pilot`).
    Part,
    /// It needs something that goes: it would stop working.
    NeedsIt,
    /// Only what goes needed it.
    OnlyFor,
}

/// One package in a plan.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[allow(
    clippy::struct_excessive_bools,
    reason = "independent facts the confirmation sheet shows, serialised as they are"
)]
pub struct Item {
    /// The `PackageKit` id.
    pub id: String,
    pub name: String,
    pub version: String,
    pub change: Change,
    pub kind: Kind,
    /// The store's title for it, or the package's summary, or its name.
    pub title: String,
    pub summary: String,
    /// The repository it comes from, or `installed`.
    pub repo: String,
    /// From Reef's repository (for a removal: Reef's to remove).
    pub reef: bool,
    /// The package the person asked for (every one, for Update all).
    pub requested: bool,
    /// Removals only.
    pub reason: Option<Reason>,
    /// A removal takes an app that needs what goes: it would stop working.
    pub stops_working: bool,
    pub sandboxed: bool,
    pub services: Vec<Service>,
    pub system_changes: Vec<String>,
    pub permissions: Vec<String>,
    /// Bytes to download, when `PackageKit` says.
    pub size: Option<u64>,
}

/// Everything one install, update or removal will do.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Plan {
    pub action: Action,
    /// The RPM name asked for; empty for Update all.
    pub target: String,
    pub items: Vec<Item>,
    /// The sum of the items' sizes, when `PackageKit` gave any.
    pub download_size: Option<u64>,
    /// Installs only: packages asked for together with the target, the
    /// build of each of its variants groups this phone runs
    /// ([`Catalogue::variant_picks`]: Pacific's engine for this processor).
    /// They appear among the items as what comes with the app.
    pub alongside: Vec<String>,
}

impl Plan {
    /// Whether a transaction that would make `changes` (name, change) does
    /// nothing this plan does not show. Versions are not compared: a
    /// rebuild published in between is the same package doing the same
    /// thing; a package added, or a change of kind (an update that now
    /// removes something), is not.
    pub fn covers(&self, changes: &[(String, Change)]) -> bool {
        changes.iter().all(|(name, change)| {
            *change == Change::Keep
                || self
                    .items
                    .iter()
                    .any(|i| &i.name == name && i.change == *change)
        })
    }

    /// The (name, change) pairs of the items, for [`covers`](Self::covers).
    pub fn changes(&self) -> Vec<(String, Change)> {
        self.items
            .iter()
            .map(|i| (i.name.clone(), i.change))
            .collect()
    }

    /// Sets [`download_size`](Self::download_size) and the items' sizes
    /// from `PackageKit`'s `(id, bytes)`.
    pub fn set_sizes(&mut self, sizes: &[(String, u64)]) {
        let mut total = None;
        for item in &mut self.items {
            if let Some((_, size)) = sizes.iter().find(|(id, _)| *id == item.id) {
                item.size = Some(*size);
                total = Some(total.unwrap_or(0) + size);
            }
        }
        self.download_size = total;
    }

    /// The ids `PackageKit` downloads.
    pub fn download_ids(&self) -> Vec<&str> {
        self.items
            .iter()
            .filter(|i| i.change.downloads())
            .map(|i| i.id.as_str())
            .collect()
    }

    /// The plan as JSON, for the confirmation sheet.
    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_default()
    }
}

/// What the catalogue says about one package, wherever it says it: its
/// `components` entry, or the disclosures of a listed app that pulls it in.
#[derive(Debug, Default)]
struct Facts {
    title: Option<String>,
    summary: Option<String>,
    listed: bool,
    desktop: Option<bool>,
    sandboxed: Option<bool>,
    services: Vec<Service>,
    system_changes: Vec<String>,
    permissions: Vec<String>,
}

fn facts(name: &str, catalogue: Option<&Catalogue>) -> Facts {
    let mut f = Facts::default();
    let Some(cat) = catalogue else {
        return f;
    };
    if let Some(p) = cat.packages.iter().find(|p| p.name == name) {
        f.listed = true;
        f.title = Some(p.title.clone());
        f.summary = Some(p.summary.clone());
        f.permissions.clone_from(&p.permissions);
    }
    if let Some(c) = cat.components.get(name) {
        f.desktop = Some(c.desktop);
        f.sandboxed = Some(c.sandboxed);
        if f.summary.is_none() && !c.summary.is_empty() {
            f.summary = Some(c.summary.clone());
        }
        f.services = c
            .services
            .iter()
            .map(|s| Service {
                package: name.to_owned(),
                ..s.clone()
            })
            .collect();
        f.system_changes.clone_from(&c.system_changes);
        if !c.permissions.is_empty() {
            f.permissions.clone_from(&c.permissions);
        }
    }
    // An app's entry lists what its dependencies bring, by package: the
    // only word on a dependency in a catalogue without components.
    for p in &cat.packages {
        for s in p.services.iter().filter(|s| s.package == name) {
            if !f.services.iter().any(|x| x.name == s.name) {
                f.services.push(s.clone());
            }
        }
        for c in p.system_changes.iter().filter(|c| c.package == name) {
            if !f.system_changes.contains(&c.description) {
                f.system_changes.push(c.description.clone());
            }
        }
    }
    f
}

/// What `name` is: a background service when it ships units or runs
/// outside the sandbox; an app when it has a launcher entry; an add-on when
/// the store lists it without one (or it is named after the app asked
/// for); otherwise a library.
fn kind(name: &str, target: &str, f: &Facts) -> Kind {
    if !f.services.is_empty() || f.sandboxed == Some(false) {
        return Kind::BackgroundService;
    }
    let part_of_target = !target.is_empty()
        && name
            .strip_prefix(target)
            .is_some_and(|rest| rest.starts_with('-'));
    match (f.desktop, f.listed) {
        (Some(true), _) => Kind::App,
        (Some(false), true) => Kind::AddOn,
        _ if part_of_target => Kind::AddOn,
        // No components (an older catalogue): a listed package is an app.
        (None, true) => Kind::App,
        _ => Kind::Library,
    }
}

/// One plan item for package `info` changing by `change`.
pub fn describe(
    info: &PackageInfo,
    change: Change,
    target: &str,
    alias: &str,
    catalogue: Option<&Catalogue>,
) -> Item {
    let id: &PackageId = &info.id;
    let f = facts(&id.name, catalogue);
    let kind = kind(&id.name, target, &f);
    let summary = f
        .summary
        .clone()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| info.summary.clone());
    Item {
        id: id.raw.clone(),
        name: id.name.clone(),
        version: id.version.clone(),
        change,
        kind,
        title: f
            .title
            .clone()
            .filter(|t| !t.is_empty())
            .unwrap_or_else(|| {
                if summary.is_empty() {
                    id.name.clone()
                } else {
                    summary.clone()
                }
            }),
        summary,
        repo: id.data.clone(),
        reef: id.from_repo(alias),
        requested: id.name == target,
        reason: None,
        stops_working: false,
        // A library runs inside whatever loads it.
        sandboxed: f.sandboxed.unwrap_or(true),
        services: f.services,
        system_changes: f.system_changes,
        permissions: f.permissions,
        size: None,
    }
}

/// The items of a simulated install or update: one per package (a name
/// both installed and removed is an upgrade's old copy: the install stands),
/// requested packages first, then by kind and title. `requested` are the
/// ids asked for; one the simulation did not mention is added as `default`.
pub fn items_from_simulation(
    simulated: &[PackageInfo],
    requested: &[PackageInfo],
    default: Change,
    target: &str,
    alias: &str,
    catalogue: Option<&Catalogue>,
) -> Vec<Item> {
    let mut items: Vec<Item> = Vec::new();
    for p in simulated.iter().chain(requested) {
        let change = Change::from_info(p.info, default);
        if let Some(i) = items.iter_mut().find(|i| i.name == p.id.name) {
            if i.change == Change::Remove && change != Change::Remove {
                *i = describe(p, change, target, alias, catalogue);
            }
            continue;
        }
        items.push(describe(p, change, target, alias, catalogue));
    }
    for i in &mut items {
        if requested.iter().any(|r| r.id.name == i.name) {
            i.requested = true;
        }
    }
    sort(&mut items);
    items
}

/// Requested first, then apps, add-ons, services, libraries; by title.
pub fn sort(items: &mut [Item]) {
    let rank = |k: Kind| match k {
        Kind::App => 0,
        Kind::AddOn => 1,
        Kind::BackgroundService => 2,
        Kind::Library => 3,
    };
    items.sort_by_cached_key(|i| {
        (
            !i.requested,
            i.change == Change::Keep,
            rank(i.kind),
            i.title.to_lowercase(),
        )
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pkg(info: Info, id: &str) -> PackageInfo {
        PackageInfo {
            info,
            id: PackageId::parse(id).unwrap(),
            summary: format!("{} summary", id.split(';').next().unwrap()),
        }
    }

    const CATALOGUE: &str = r#"{"schema":1,"release":"5.2.0.18","arch":"aarch64",
      "components": {
        "shipwright-shoal-bridge-airpods-ui": {"summary": "AirPods app", "desktop": true, "listed": true},
        "shipwright-shoal-bridge-airpods": {"summary": "AirPods service",
          "services": [{"name": "airpods.service", "scope": "user", "starts": "login",
                        "description": "Keeps the earbuds connected"}]},
        "shipwright-keel-silica": {"summary": "Silica for Qt 6"},
        "shoal-pilot-gesture-patch": {"summary": "Gesture", "listed": true,
          "system_changes": ["Changes the home screen (Lipstick)"]}},
      "packages": [
        {"name": "shipwright-shoal-bridge-airpods-ui", "version": "1-1", "title": "AirPods",
         "summary": "Your earbuds", "tested_on": ["5.2.0.18"], "licence": {"model": "free"},
         "permissions": ["Bluetooth"]},
        {"name": "shoal-pilot-gesture-patch", "version": "1-1", "title": "Pilot gesture",
         "summary": "s", "tested_on": ["5.2.0.18"], "licence": {"model": "free"}}]}"#;

    fn cat() -> Catalogue {
        Catalogue::parse(CATALOGUE.as_bytes(), "aarch64").unwrap()
    }

    #[test]
    fn a_simulated_install_lists_and_labels_everything() {
        let target = pkg(
            Info::Available,
            "shipwright-shoal-bridge-airpods-ui;1-1;aarch64;shipwright-reef",
        );
        let simulated = [
            pkg(
                Info::Installing,
                "shipwright-shoal-bridge-airpods-ui;1-1;aarch64;shipwright-reef",
            ),
            pkg(
                Info::Installing,
                "shipwright-shoal-bridge-airpods;2-5;aarch64;shipwright-reef",
            ),
            pkg(
                Info::Installing,
                "shipwright-keel-silica;0.1-9;aarch64;shipwright-reef",
            ),
            pkg(Info::Installing, "bluez5-obexd;5.66-1;aarch64;jolla"),
        ];
        let items = items_from_simulation(
            &simulated,
            &[target],
            Change::Install,
            "shipwright-shoal-bridge-airpods-ui",
            "shipwright-reef",
            Some(&cat()),
        );
        let got: Vec<(&str, Kind, bool, bool)> = items
            .iter()
            .map(|i| (i.name.as_str(), i.kind, i.requested, i.reef))
            .collect();
        assert_eq!(
            got,
            [
                ("shipwright-shoal-bridge-airpods-ui", Kind::App, true, true),
                (
                    "shipwright-shoal-bridge-airpods",
                    Kind::BackgroundService,
                    false,
                    true
                ),
                ("bluez5-obexd", Kind::Library, false, false),
                ("shipwright-keel-silica", Kind::Library, false, true),
            ]
        );
        assert_eq!(items[0].title, "AirPods");
        assert_eq!(items[0].permissions, ["Bluetooth"]);
        let service = &items[1].services[0];
        assert_eq!(
            (service.package.as_str(), service.starts.as_str()),
            ("shipwright-shoal-bridge-airpods", "login")
        );
        assert_eq!(items[2].repo, "jolla");
    }

    #[test]
    fn labels_without_components_and_add_ons() {
        // An older catalogue: no components; the gesture patch is listed
        // with no launcher, named after Pilot.
        let mut c = cat();
        c.components.clear();
        let f = facts("shoal-pilot-gesture-patch", Some(&c));
        assert_eq!(
            kind("shoal-pilot-gesture-patch", "shoal-pilot", &f),
            Kind::AddOn
        );
        assert_eq!(
            kind(
                "shipwright-shoal-bridge-airpods-ui",
                "",
                &facts("shipwright-shoal-bridge-airpods-ui", Some(&c))
            ),
            Kind::App
        );
        assert_eq!(kind("libfoo", "x", &facts("libfoo", None)), Kind::Library);
        assert_eq!(
            kind(
                "shoal-pilot-piper",
                "shoal-pilot",
                &facts("shoal-pilot-piper", None)
            ),
            Kind::AddOn
        );
        // With components: listed without a desktop file is an add-on, and
        // its system change is carried.
        let f = facts("shoal-pilot-gesture-patch", Some(&cat()));
        assert_eq!(kind("shoal-pilot-gesture-patch", "", &f), Kind::AddOn);
        assert_eq!(f.system_changes, ["Changes the home screen (Lipstick)"]);
    }

    #[test]
    fn an_upgrade_is_one_item_and_plans_cover_only_what_they_show() {
        let items = items_from_simulation(
            &[
                pkg(Info::Removing, "a;1-1;noarch;installed"),
                pkg(Info::Updating, "a;1-2;noarch;shipwright-reef"),
            ],
            &[pkg(Info::Available, "a;1-2;noarch;shipwright-reef")],
            Change::Update,
            "a",
            "shipwright-reef",
            None,
        );
        assert_eq!(items.len(), 1);
        assert_eq!(items[0].change, Change::Update);
        let mut plan = Plan {
            action: Action::Update,
            target: "a".into(),
            items,
            download_size: None,
            alongside: Vec::new(),
        };
        assert!(plan.covers(&[("a".into(), Change::Update)]));
        assert!(!plan.covers(&[("a".into(), Change::Update), ("b".into(), Change::Install)]));
        assert!(!plan.covers(&[("a".into(), Change::Remove)]));
        plan.set_sizes(&[("a;1-2;noarch;shipwright-reef".into(), 4096)]);
        assert_eq!(plan.download_size, Some(4096));
        assert_eq!(plan.download_ids(), ["a;1-2;noarch;shipwright-reef"]);
        let json: serde_json::Value = serde_json::from_str(&plan.to_json()).unwrap();
        assert_eq!(json["action"], "update");
        assert_eq!(json["items"][0]["kind"], "library");
        assert_eq!(json["items"][0]["change"], "update");
    }
}
