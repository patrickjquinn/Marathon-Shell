// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Pure conversions from reef-backend types to what the QML sees: list
//! model rows, the `packageDetails()` map and the messages behind
//! `lastError`. Nothing here touches Qt, so every rule is unit-tested
//! without a QML engine; the bridge turns [`Value`]s into `QVariant`s.
//!
//! The role names and values are the contract in apps/reef/UI.md
//! ("Backend object API").

use reef_backend::catalogue::{parse_date, Catalogue, LicenceModel, Package};
use reef_backend::licences::StoredLicence;
use reef_backend::store::{entries, InstallState, PackageVersion};
use reef_licence::{Claims, Error as LicenceError, Plan, Standing};

/// One cell of a row, or one value of the details map.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Value {
    Str(String),
    Bool(bool),
    Int(i64),
    List(Vec<String>),
}

impl From<&str> for Value {
    fn from(s: &str) -> Self {
        Value::Str(s.to_string())
    }
}

impl From<String> for Value {
    fn from(s: String) -> Self {
        Value::Str(s)
    }
}

impl From<bool> for Value {
    fn from(b: bool) -> Self {
        Value::Bool(b)
    }
}

/// Roles of `catalogueModel` and `installedModel`, in column order.
pub const PACKAGE_ROLES: &[&str] = &[
    "name",
    "title",
    "summary",
    "category",
    "version",
    "installState",
    "installedVersion",
    "licenceModel",
    "licensed",
    "publisher",
    "iconPath",
    "featured",
    "isNew",
    "updated",
    "heroPath",
    "categoryLabel",
];

/// How many apps the home page's "New and updated" row shows.
pub const RECENT_COUNT: usize = 10;

/// A package is "new" for this many days after its `added` date.
pub const NEW_DAYS: i64 = 30;

/// Roles of `licenceModel`, in column order.
pub const LICENCE_ROLES: &[&str] = &[
    "appId",
    "title",
    "plan",
    "status",
    "expiresText",
    "licenceId",
];

/// One row of `catalogueModel` / `installedModel`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PackageRow {
    pub name: String,
    pub title: String,
    pub summary: String,
    pub category: String,
    pub version: String,
    pub install_state: &'static str,
    pub installed_version: String,
    pub licence_model: &'static str,
    pub licensed: bool,
    pub publisher: String,
    /// Local path of the cached icon, or empty.
    pub icon_path: String,
    pub featured: bool,
    pub is_new: bool,
    /// `YYYY-MM-DD` of the newest changelog entry, else `added`, else empty.
    pub updated: String,
    /// Local path of the first cached screenshot (the home page's banner
    /// for a featured app), or empty.
    pub hero_path: String,
    /// Search keywords (not a role: [`filter_rows`] reads them).
    pub keywords: Vec<String>,
    /// The category's name as the store shows it (`Music and audio` for
    /// `Audio`): the catalogue's category list, else the category itself.
    pub category_label: String,
}

impl PackageRow {
    /// Cells in [`PACKAGE_ROLES`] order.
    pub fn values(&self) -> Vec<Value> {
        vec![
            self.name.as_str().into(),
            self.title.as_str().into(),
            self.summary.as_str().into(),
            self.category.as_str().into(),
            self.version.as_str().into(),
            self.install_state.into(),
            self.installed_version.as_str().into(),
            self.licence_model.into(),
            self.licensed.into(),
            self.publisher.as_str().into(),
            self.icon_path.as_str().into(),
            self.featured.into(),
            self.is_new.into(),
            self.updated.as_str().into(),
            self.hero_path.as_str().into(),
            self.category_label.as_str().into(),
        ]
    }
}

/// Days since the epoch for a Unix time, the unit `is_new` compares in.
pub fn today(unix_now: i64) -> i64 {
    unix_now.div_euclid(86_400)
}

/// Whether a package added on `added` (`YYYY-MM-DD`) is still new today.
pub fn is_new(added: Option<&str>, today: i64) -> bool {
    added
        .and_then(parse_date)
        .is_some_and(|day| (0..=NEW_DAYS).contains(&(today - day)))
}

/// The search results for `query`, best first: rows where every
/// whitespace-separated word matches (case-insensitively) the title, a
/// keyword, the RPM name, the summary, the publisher or the category, or,
/// for a word of five letters or more, a title word or keyword with one
/// letter wrong, missing, extra or two swapped. A word counts most at the
/// start of the title, then at the start of a title word, then anywhere in
/// it, then as a keyword, and so on ([`word_score`]); equal scores keep
/// the rows' order. All rows, in order, for a blank query.
pub fn filter_rows(rows: &[PackageRow], query: &str) -> Vec<PackageRow> {
    let words: Vec<String> = query.split_whitespace().map(str::to_lowercase).collect();
    if words.is_empty() {
        return rows.to_vec();
    }
    let mut scored: Vec<(u32, usize)> = rows
        .iter()
        .enumerate()
        .filter_map(|(i, r)| {
            let mut total = 0;
            for w in &words {
                let s = word_score(r, w);
                if s == 0 {
                    return None;
                }
                total += s;
            }
            Some((total, i))
        })
        .collect();
    scored.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));
    scored.into_iter().map(|(_, i)| rows[i].clone()).collect()
}

/// How well one lower-case query word matches a row (0: not at all).
pub fn word_score(r: &PackageRow, w: &str) -> u32 {
    let title = r.title.to_lowercase();
    let title_words: Vec<&str> = title
        .split(|c: char| !c.is_alphanumeric())
        .filter(|t| !t.is_empty())
        .collect();
    let keywords: Vec<String> = r.keywords.iter().map(|k| k.to_lowercase()).collect();
    let summary = r.summary.to_lowercase();
    if title.starts_with(w) {
        100
    } else if title_words.iter().any(|t| t.starts_with(w)) {
        80
    } else if keywords.iter().any(|k| k == w) {
        70
    } else if title.contains(w) {
        60
    } else if keywords.iter().any(|k| k.starts_with(w)) {
        50
    } else if r.name.to_lowercase().contains(w) {
        40
    } else if summary
        .split(|c: char| !c.is_alphanumeric())
        .any(|t| t.starts_with(w))
    {
        30
    } else if w.chars().count() >= 5
        && title_words
            .iter()
            .copied()
            .chain(keywords.iter().map(String::as_str))
            .any(|t| one_edit(t, w))
    {
        25
    } else if summary.contains(w) {
        20
    } else if r.publisher.to_lowercase().contains(w) || r.category.to_lowercase().contains(w) {
        15
    } else {
        0
    }
}

/// Whether `a` and `b` differ by at most one letter changed, added or
/// removed, or two neighbours swapped.
pub fn one_edit(a: &str, b: &str) -> bool {
    let a: Vec<char> = a.chars().collect();
    let b: Vec<char> = b.chars().collect();
    if a == b {
        return true;
    }
    let (la, lb) = (a.len(), b.len());
    if la.abs_diff(lb) > 1 {
        return false;
    }
    let first = a.iter().zip(&b).take_while(|(x, y)| x == y).count();
    match la.cmp(&lb) {
        // One changed, or the first difference and the next swapped.
        std::cmp::Ordering::Equal => {
            a[first + 1..] == b[first + 1..]
                || (first + 1 < la
                    && a[first] == b[first + 1]
                    && a[first + 1] == b[first]
                    && a[first + 2..] == b[first + 2..])
        }
        std::cmp::Ordering::Greater => a[first + 1..] == b[first..],
        std::cmp::Ordering::Less => a[first..] == b[first + 1..],
    }
}

/// `recentModel`: the most recently updated rows, newest first (by
/// `updated`; rows without a date left out), at most [`RECENT_COUNT`].
pub fn recent_rows(rows: &[PackageRow]) -> Vec<PackageRow> {
    let mut recent: Vec<PackageRow> = rows
        .iter()
        .filter(|r| !r.updated.is_empty())
        .cloned()
        .collect();
    recent.sort_by(|a, b| {
        b.updated
            .cmp(&a.updated)
            .then_with(|| a.title.cmp(&b.title))
    });
    recent.truncate(RECENT_COUNT);
    recent
}

/// `featuredModel`: the featured rows, in the catalogue's order.
pub fn featured_rows(rows: &[PackageRow], catalogue: &Catalogue) -> Vec<PackageRow> {
    catalogue
        .featured
        .iter()
        .filter_map(|n| rows.iter().find(|r| &r.name == n))
        .cloned()
        .collect()
}

/// Roles of `categoriesModel`, in column order (`id` is QML's own word).
pub const CATEGORY_ROLES: &[&str] = &["categoryId", "label", "icon", "count"];

/// Roles of `collectionsModel`, in column order.
pub const COLLECTION_ROLES: &[&str] = &["collectionId", "title", "subtitle", "generated", "apps"];

/// `categoriesModel`: the store's categories that have apps this phone is
/// shown, in the store's order, with how many. A catalogue without a
/// category list (a `catalogue.json`) gets one row per category its apps
/// name, by name, with no icon.
pub fn category_rows(catalogue: &Catalogue, rows: &[PackageRow]) -> Vec<Vec<Value>> {
    let count = |id: &str| {
        rows.iter()
            .filter(|r| r.category.eq_ignore_ascii_case(id))
            .count()
    };
    let row = |id: &str, label: &str, icon: &str, n: usize| {
        vec![
            id.into(),
            label.into(),
            icon.into(),
            Value::Int(i64::try_from(n).unwrap_or(i64::MAX)),
        ]
    };
    if catalogue.categories.is_empty() {
        let mut names: Vec<&str> = rows.iter().map(|r| r.category.as_str()).collect();
        names.sort_unstable();
        names.dedup();
        return names.into_iter().map(|n| row(n, n, "", count(n))).collect();
    }
    catalogue
        .categories
        .iter()
        .map(|c| (c, count(&c.id)))
        .filter(|(_, n)| *n > 0)
        .map(|(c, n)| row(&c.id, &c.label, &c.icon, n))
        .collect()
}

/// A collection shows as a row on the home page with at least this many
/// apps shown here: a row of one or two is mostly empty space. Fewer, it
/// is left out (its page still opens from a link).
pub const MIN_COLLECTION_APPS: usize = 3;

/// `collectionsModel`: the catalogue's collections, each with the apps of
/// it this phone is shown, in order; collections with fewer than
/// [`MIN_COLLECTION_APPS`] of them are dropped.
pub fn collection_rows(catalogue: &Catalogue, rows: &[PackageRow]) -> Vec<Vec<Value>> {
    catalogue
        .collections
        .iter()
        .filter_map(|c| {
            let apps: Vec<String> = c
                .apps
                .iter()
                .filter(|n| rows.iter().any(|r| &r.name == *n))
                .cloned()
                .collect();
            (apps.len() >= MIN_COLLECTION_APPS).then(|| {
                vec![
                    c.id.as_str().into(),
                    c.title.as_str().into(),
                    c.subtitle.as_str().into(),
                    c.generated.into(),
                    Value::List(apps),
                ]
            })
        })
        .collect()
}

/// `browseModel`: the rows of one category (`kind` "category", by title),
/// one collection ("collection", in its order) or every app ("all", by
/// title). Nothing for an unknown kind or id.
pub fn browse_rows(
    catalogue: &Catalogue,
    rows: &[PackageRow],
    kind: &str,
    id: &str,
) -> Vec<PackageRow> {
    match kind {
        "all" => rows.to_vec(),
        "category" => rows
            .iter()
            .filter(|r| r.category.eq_ignore_ascii_case(id))
            .cloned()
            .collect(),
        "collection" => catalogue
            .collections
            .iter()
            .find(|c| c.id == id)
            .map(|c| {
                c.apps
                    .iter()
                    .filter_map(|n| rows.iter().find(|r| &r.name == n))
                    .cloned()
                    .collect()
            })
            .unwrap_or_default(),
        _ => Vec::new(),
    }
}

/// `installState` and `installedVersion`.
pub fn install_state(state: &InstallState) -> (&'static str, String) {
    match state {
        InstallState::NotInstalled => ("not_installed", String::new()),
        InstallState::Installed { version } => ("installed", version.clone()),
        InstallState::UpdateAvailable { installed, .. } => ("update_available", installed.clone()),
    }
}

/// `updateVersion`: the version an update would bring, which a cached
/// catalogue can lag behind (it may even list an older build than the one
/// installed); empty unless an update is available.
pub fn update_version(state: &InstallState) -> String {
    match state {
        InstallState::UpdateAvailable { available, .. } => available.clone(),
        _ => String::new(),
    }
}

/// `licenceModel`: `free`, `one_off` or `subscription`.
pub fn licence_model(model: &LicenceModel) -> &'static str {
    match model {
        LicenceModel::Free => "free",
        LicenceModel::OneOff { .. } => "one_off",
        LicenceModel::Subscription { .. } => "subscription",
    }
}

fn purchase_url(model: &LicenceModel) -> &str {
    match model {
        LicenceModel::Free => "",
        LicenceModel::OneOff { purchase_url, .. }
        | LicenceModel::Subscription { purchase_url, .. } => purchase_url,
    }
}

/// Whether the package is paid for and a usable licence for it is stored.
/// Free packages report false: there is nothing to license.
pub fn is_licensed(package: &Package, licensed_app: &dyn Fn(&str) -> bool) -> bool {
    package.licence.app_id().is_some_and(licensed_app)
}

/// `catalogueModel`: visible packages joined with install state
/// (`catalogue.visible` through `store::entries`), sorted by title (the
/// home page's A to Z list; the category is in each row). `asset`
/// maps a repository-relative icon path to its cached local path (or
/// empty); `today` is [`today`]'s value.
pub fn package_rows(
    catalogue: &Catalogue,
    installed: &[PackageVersion],
    updates: &[PackageVersion],
    licensed_app: &dyn Fn(&str) -> bool,
    asset: &dyn Fn(&str) -> String,
    today: i64,
) -> Vec<PackageRow> {
    let mut rows: Vec<PackageRow> = entries(catalogue, installed, updates)
        .into_iter()
        .map(|e| {
            let (state, installed_version) = install_state(&e.state);
            PackageRow {
                name: e.package.name.clone(),
                title: e.package.title.clone(),
                summary: e.package.summary.clone(),
                category: e.package.category.clone(),
                category_label: catalogue
                    .categories
                    .iter()
                    .find(|c| c.id.eq_ignore_ascii_case(&e.package.category))
                    .map_or_else(|| e.package.category.clone(), |c| c.label.clone()),
                version: e.package.version.clone(),
                install_state: state,
                installed_version,
                licence_model: licence_model(&e.package.licence),
                licensed: is_licensed(e.package, licensed_app),
                publisher: e.package.publisher.clone(),
                icon_path: e.package.icon.as_deref().map(asset).unwrap_or_default(),
                featured: catalogue.featured.contains(&e.package.name),
                is_new: is_new(e.package.added.as_deref(), today),
                updated: e
                    .package
                    .changelog
                    .first()
                    .map(|c| c.date.clone())
                    .or_else(|| e.package.updated.clone())
                    .or_else(|| e.package.added.clone())
                    .unwrap_or_default(),
                hero_path: e
                    .package
                    .hero
                    .iter()
                    .chain(e.package.screenshots.iter())
                    .map(|s| asset(s))
                    .find(|p| !p.is_empty())
                    .unwrap_or_default(),
                keywords: e.package.keywords.clone(),
            }
        })
        .collect();
    rows.sort_by(|a, b| {
        a.title
            .to_lowercase()
            .cmp(&b.title.to_lowercase())
            .then_with(|| a.name.cmp(&b.name))
    });
    rows
}

/// `installedModel`: the same rows, only those installed.
pub fn installed_rows(rows: &[PackageRow]) -> Vec<PackageRow> {
    rows.iter()
        .filter(|r| r.install_state != "not_installed")
        .cloned()
        .collect()
}

/// The `packageDetails(name)` map, in the README's key order. `asset` is as
/// for [`package_rows`]; screenshots not yet cached are left out.
pub fn package_details(
    package: &Package,
    state: &InstallState,
    licensed: bool,
    asset: &dyn Fn(&str) -> String,
) -> Vec<(&'static str, Value)> {
    let (install_state, installed_version) = install_state(state);
    vec![
        ("name", package.name.as_str().into()),
        ("title", package.title.as_str().into()),
        ("summary", package.summary.as_str().into()),
        ("description", package.description.as_str().into()),
        ("category", package.category.as_str().into()),
        ("version", package.version.as_str().into()),
        ("installState", install_state.into()),
        ("installedVersion", installed_version.into()),
        ("updateVersion", update_version(state).into()),
        ("testedOn", Value::List(package.tested_on.clone())),
        ("deviceTested", package.device_tested.into()),
        ("permissions", Value::List(package.permissions.clone())),
        ("sandboxed", package.sandboxed.into()),
        ("licenceModel", licence_model(&package.licence).into()),
        ("licensed", licensed.into()),
        ("purchaseUrl", purchase_url(&package.licence).into()),
        ("spdx", package.spdx.clone().unwrap_or_default().into()),
        ("sizeText", size_text(package.size).into()),
        (
            "keelTier",
            package.keel_tier.clone().unwrap_or_default().into(),
        ),
        (
            "homepage",
            package.homepage.clone().unwrap_or_default().into(),
        ),
        ("source", package.source.clone().unwrap_or_default().into()),
        ("publisher", package.publisher.as_str().into()),
        (
            "iconPath",
            package
                .icon
                .as_deref()
                .map(asset)
                .unwrap_or_default()
                .into(),
        ),
        (
            "screenshotPaths",
            Value::List(
                package
                    .screenshots
                    .iter()
                    .map(|s| asset(s))
                    .filter(|p| !p.is_empty())
                    .collect(),
            ),
        ),
        ("added", package.added.clone().unwrap_or_default().into()),
        // The newest changelog entry's day, else the day it was published.
        (
            "updated",
            package
                .changelog
                .first()
                .map(|c| c.date.clone())
                .or_else(|| package.added.clone())
                .unwrap_or_default()
                .into(),
        ),
        // [{version, date, notes}], newest first, for QML's JSON.parse
        // (a list of maps does not fit `Value`).
        (
            "changelogJson",
            serde_json::to_string(&package.changelog)
                .unwrap_or_else(|_| "[]".into())
                .into(),
        ),
        // What it brings that runs by itself, and what it changes on the
        // phone, over everything it pulls in: [{name, package, scope,
        // starts, description}] and [{package, description}], as JSON.
        (
            "servicesJson",
            serde_json::to_string(&package.services)
                .unwrap_or_else(|_| "[]".into())
                .into(),
        ),
        (
            "systemChangesJson",
            serde_json::to_string(&package.system_changes)
                .unwrap_or_else(|_| "[]".into())
                .into(),
        ),
    ]
}

/// Install state of one visible package, for `packageDetails`.
pub fn state_of(
    catalogue: &Catalogue,
    installed: &[PackageVersion],
    updates: &[PackageVersion],
    name: &str,
) -> Option<InstallState> {
    entries(catalogue, installed, updates)
        .into_iter()
        .find(|e| e.package.name == name)
        .map(|e| e.state)
}

/// Pre-formatted size (Keel v1 has no `Format`). Binary units, one decimal
/// below 10, as Silica's `Format.formatFileSize` shows them.
pub fn size_text(bytes: Option<u64>) -> String {
    const UNITS: [&str; 4] = ["kB", "MB", "GB", "TB"];
    let Some(bytes) = bytes else {
        return String::new();
    };
    if bytes < 1024 {
        return format!("{bytes} B");
    }
    #[allow(
        clippy::cast_precision_loss,
        reason = "a size shown with at most one decimal; f64 is exact up to 8 PiB"
    )]
    let mut value = bytes as f64 / 1024.0;
    let mut unit = 0;
    while value >= 1024.0 && unit < UNITS.len() - 1 {
        value /= 1024.0;
        unit += 1;
    }
    if value < 10.0 {
        format!("{value:.1} {}", UNITS[unit])
    } else {
        format!("{value:.0} {}", UNITS[unit])
    }
}

/// Marks a message the UI translates: `\u{1e}<key>` followed by its
/// arguments, each after a `\u{1f}`. apps/reef/ui/components/Texts.js maps
/// each key to a `qsTr` string; text without the marker (errors from the
/// network or reef-licence) is shown as it is.
pub const MESSAGE_MARK: char = '\u{1e}';
const MESSAGE_ARG: char = '\u{1f}';

/// A translatable message (see [`MESSAGE_MARK`]). Keys:
/// `no_licence_store`, `licence_remove_failed` (error), `catalogue_missing`
/// (arch), `catalogue_download_failed` (error), `no_licence_server`,
/// `revocations_unsigned`, `worker_failed` (error), `licence_add_failed`
/// (error), `claim_failed` (error).
pub fn message(key: &str, args: &[&str]) -> String {
    let mut s = String::from(MESSAGE_MARK);
    s.push_str(key);
    for a in args {
        s.push(MESSAGE_ARG);
        // An argument cannot end the message early or add one.
        s.extend(
            a.chars()
                .filter(|c| *c != MESSAGE_MARK && *c != MESSAGE_ARG),
        );
    }
    s
}

/// One row of `licenceModel`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LicenceRow {
    pub app_id: String,
    pub title: String,
    pub plan: &'static str,
    pub status: &'static str,
    pub expires_text: String,
    pub licence_id: String,
}

impl LicenceRow {
    /// Cells in [`LICENCE_ROLES`] order.
    pub fn values(&self) -> Vec<Value> {
        vec![
            self.app_id.as_str().into(),
            self.title.as_str().into(),
            self.plan.into(),
            self.status.into(),
            self.expires_text.as_str().into(),
            self.licence_id.as_str().into(),
        ]
    }
}

fn plan_str(plan: Plan) -> &'static str {
    match plan {
        Plan::OneOff => "one_off",
        Plan::Subscription => "subscription",
    }
}

/// `status` role: `active`, `grace`, `expired`, `revoked` or `invalid`.
pub fn licence_status(stored: &StoredLicence) -> &'static str {
    match &stored.status {
        Ok(_) if stored.revoked => "revoked",
        Ok(l) => match l.standing {
            Standing::Active => "active",
            Standing::Grace { .. } => "grace",
        },
        Err(LicenceError::Expired { .. }) => "expired",
        Err(_) => "invalid",
    }
}

/// Whether a stored licence unlocks its app now (active or in grace, not
/// revoked).
pub fn licence_usable(stored: &StoredLicence) -> bool {
    stored.status.is_ok() && !stored.revoked
}

/// Claims to show and refresh with: verified ones, or for an expired token
/// (whose signature did verify, but which `verify_any_app` no longer
/// returns claims for) the payload read by [`Claims::peek_unverified`],
/// which is display-only and never grants anything.
pub fn display_claims(stored: &StoredLicence) -> Option<Claims> {
    match &stored.status {
        Ok(l) => Some(l.claims.clone()),
        Err(LicenceError::Expired { .. }) => Claims::peek_unverified(&stored.token),
        Err(_) => None,
    }
}

/// `licenceModel` row. `title_for` looks the app id up in the catalogue.
pub fn licence_row(
    stored: &StoredLicence,
    title_for: &dyn Fn(&str) -> Option<String>,
) -> LicenceRow {
    let claims = display_claims(stored);
    LicenceRow {
        app_id: stored.app_id.clone(),
        title: title_for(&stored.app_id).unwrap_or_else(|| stored.app_id.clone()),
        plan: claims.as_ref().map_or("", |c| plan_str(c.plan)),
        status: licence_status(stored),
        expires_text: claims
            .as_ref()
            .and_then(|c| c.exp)
            .map(date_text)
            .unwrap_or_default(),
        licence_id: claims.map(|c| c.lid).unwrap_or_default(),
    }
}

/// Catalogue title for a licence app id (any package, visible or not).
pub fn title_for_app(catalogue: Option<&Catalogue>, app_id: &str) -> Option<String> {
    catalogue?
        .packages
        .iter()
        .find(|p| p.licence.app_id() == Some(app_id))
        .map(|p| p.title.clone())
}

/// `YYYY-MM-DD` (UTC) for Unix seconds. ISO 8601 rather than a localised
/// date: the Rust side has no locale data and Keel v1 has no `Format`.
pub fn date_text(unix: i64) -> String {
    // Howard Hinnant's civil_from_days.
    let days = unix.div_euclid(86_400);
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use reef_licence::{KeySet, Licence, Policy, Signer};

    const CATALOGUE: &str = r#"{
      "schema": 1, "release": "5.2.0.17", "arch": "aarch64",
      "packages": [
        {"name": "shipwright-keel-silica", "version": "0.1.0-1",
         "title": "Keel", "summary": "Silica for Qt6", "category": "System",
         "tested_on": ["5.2.0.17"], "sandboxed": false,
         "licence": {"model": "free"}, "size": 1536000,
         "spdx": "BSD-3-Clause", "homepage": "https://example.invalid/keel"},
        {"name": "shipwright-shoal-bridge-airpods-ui", "version": "1.0.0-1",
         "title": "Shoal Bridge", "summary": "AirPods", "category": "Audio",
         "description": "Battery and modes.", "tested_on": ["5.2.0.17", "5.2.0.18"],
         "permissions": ["Bluetooth", "Audio"],
         "licence": {"model": "one_off", "app_id": "shoal-bridge",
                     "purchase_url": "https://example.invalid/buy"}},
        {"name": "shipwright-shoal-messages", "version": "0.3.0-1",
         "title": "Messages", "summary": "Matrix", "category": "Communication",
         "tested_on": ["5.2.0.18"],
         "licence": {"model": "subscription", "app_id": "shoal-messages",
                     "purchase_url": "https://example.invalid/sub"}}
      ]}"#;

    fn cat() -> Catalogue {
        Catalogue::parse(CATALOGUE.as_bytes(), "aarch64").unwrap()
    }

    fn pkg(name: &str, version: &str) -> PackageVersion {
        PackageVersion {
            name: name.into(),
            version: version.into(),
        }
    }

    fn no_asset(_: &str) -> String {
        String::new()
    }

    #[test]
    fn rows_follow_visibility_install_state_and_licences() {
        let installed = [
            pkg("shipwright-keel-silica", "0.1.0-1"),
            pkg("shipwright-shoal-bridge-airpods-ui", "0.9.0-1"),
        ];
        let updates = [pkg("shipwright-shoal-bridge-airpods-ui", "1.0.0-1")];
        let licensed = |app: &str| app == "shoal-bridge";
        let rows = package_rows(&cat(), &installed, &updates, &licensed, &no_asset, 0);
        // Sorted by title.
        assert_eq!(
            rows.iter().map(|r| r.title.as_str()).collect::<Vec<_>>(),
            ["Keel", "Messages", "Shoal Bridge"]
        );
        assert_eq!(rows[0].install_state, "installed");
        assert_eq!(rows[0].installed_version, "0.1.0-1");
        assert_eq!(rows[0].licence_model, "free");
        assert!(!rows[0].licensed, "free packages carry no licence");
        assert_eq!(rows[1].install_state, "not_installed");
        assert_eq!(rows[2].install_state, "update_available");
        assert_eq!(rows[2].installed_version, "0.9.0-1");
        assert_eq!(rows[2].version, "1.0.0-1");
        assert_eq!(rows[2].licence_model, "one_off");
        assert!(rows[2].licensed);

        let values = rows[2].values();
        assert_eq!(values.len(), PACKAGE_ROLES.len());
        assert_eq!(
            values[0],
            Value::Str("shipwright-shoal-bridge-airpods-ui".into())
        );
        assert_eq!(values[5], Value::Str("update_available".into()));
        assert_eq!(values[8], Value::Bool(true));

        // Nothing installed.
        let rows = package_rows(&cat(), &[], &[], &|_| false, &no_asset, 0);
        assert_eq!(rows.len(), 3);
        assert!(rows.iter().all(|r| r.install_state == "not_installed"));
        assert!(installed_rows(&rows).is_empty());
        assert_eq!(rows[1].licence_model, "subscription");
    }

    #[test]
    fn installed_model_keeps_installed_and_upgradable() {
        let installed = [pkg("shipwright-keel-silica", "0.1.0-1")];
        let rows = package_rows(&cat(), &installed, &[], &|_| false, &no_asset, 0);
        let inst = installed_rows(&rows);
        assert_eq!(inst.len(), 1);
        assert_eq!(inst[0].name, "shipwright-keel-silica");
    }

    #[test]
    fn search_featured_new_and_icons() {
        let json = CATALOGUE
            .replace(
                r#""title": "Keel", "summary": "Silica for Qt6", "category": "System","#,
                r#""title": "Keel", "summary": "Silica for Qt6", "category": "System",
                   "publisher": "Shipwright", "icon": "assets/keel.png", "added": "2026-10-01",
                   "screenshots": ["assets/shots/k1.jpg", "assets/shots/k2.jpg"],"#,
            )
            .replace(
                r#""packages": ["#,
                r#""featured": ["shipwright-shoal-bridge-airpods-ui", "shipwright-keel-silica"], "packages": ["#,
            );
        let c = Catalogue::parse(json.as_bytes(), "aarch64").unwrap();
        // Only keel.png and k1 are cached.
        let asset = |rel: &str| match rel {
            "assets/keel.png" => "/cache/assets__keel.png".to_string(),
            "assets/shots/k1.jpg" => "/cache/assets__shots__k1.jpg".to_string(),
            _ => String::new(),
        };
        let day = parse_date("2026-10-03").unwrap();
        let rows = package_rows(&c, &[], &[], &|_| false, &asset, day);
        let keel = rows
            .iter()
            .find(|r| r.name == "shipwright-keel-silica")
            .unwrap();
        assert_eq!(keel.publisher, "Shipwright");
        assert_eq!(keel.icon_path, "/cache/assets__keel.png");
        assert!(keel.featured && keel.is_new);
        let bridge = rows
            .iter()
            .find(|r| r.name == "shipwright-shoal-bridge-airpods-ui")
            .unwrap();
        assert!(bridge.featured && !bridge.is_new && bridge.icon_path.is_empty());
        // The banner is the first screenshot that is cached; "updated" falls
        // back to the day it was added when there is no changelog.
        assert_eq!(keel.hero_path, "/cache/assets__shots__k1.jpg");
        assert_eq!(keel.updated, "2026-10-01");
        assert!(bridge.hero_path.is_empty());
        assert_eq!(keel.values().len(), PACKAGE_ROLES.len());

        // New for 30 days, not before the date and not after.
        assert!(is_new(Some("2026-10-01"), day));
        assert!(is_new(Some("2026-09-03"), day));
        assert!(!is_new(Some("2026-09-02"), day));
        assert!(!is_new(Some("2026-10-04"), day), "not before it exists");
        assert!(!is_new(None, day) && !is_new(Some("nonsense"), day));
        assert_eq!(today(86_400 * 3 + 5), 3);

        // Featured keeps the catalogue's order, not the list's.
        let names = |rows: &[PackageRow]| rows.iter().map(|r| r.name.clone()).collect::<Vec<_>>();
        assert_eq!(
            names(&featured_rows(&rows, &c)),
            [
                "shipwright-shoal-bridge-airpods-ui",
                "shipwright-keel-silica"
            ]
        );

        // Search: every word must match, in any field, any case.
        assert_eq!(names(&filter_rows(&rows, "")), names(&rows));
        assert_eq!(names(&filter_rows(&rows, "  ")), names(&rows));
        assert_eq!(
            names(&filter_rows(&rows, "SILICA")),
            ["shipwright-keel-silica"]
        );
        assert_eq!(
            names(&filter_rows(&rows, "shipwright audio")),
            ["shipwright-shoal-bridge-airpods-ui"]
        );
        assert_eq!(
            names(&filter_rows(&rows, "qt6 shipwright")),
            ["shipwright-keel-silica"]
        );
        assert!(filter_rows(&rows, "zebra").is_empty());

        // Details carry the publisher, the icon and the cached screenshots only.
        let p = c.visible_package("shipwright-keel-silica").unwrap();
        let d = package_details(p, &InstallState::NotInstalled, false, &asset);
        let get = |k: &str| d.iter().find(|(key, _)| *key == k).unwrap().1.clone();
        assert_eq!(get("publisher"), Value::Str("Shipwright".into()));
        assert_eq!(
            get("iconPath"),
            Value::Str("/cache/assets__keel.png".into())
        );
        assert_eq!(
            get("screenshotPaths"),
            Value::List(vec!["/cache/assets__shots__k1.jpg".into()])
        );
        assert_eq!(get("added"), Value::Str("2026-10-01".into()));
    }

    #[test]
    fn categories_collections_and_browsing() {
        let row = |name: &str, category: &str| PackageRow {
            name: name.into(),
            title: name.to_uppercase(),
            summary: String::new(),
            category: category.into(),
            version: String::new(),
            install_state: "not_installed",
            installed_version: String::new(),
            licence_model: "free",
            licensed: false,
            publisher: String::new(),
            icon_path: String::new(),
            featured: false,
            is_new: false,
            updated: String::new(),
            hero_path: String::new(),
            keywords: Vec::new(),
            category_label: String::new(),
        };
        // Rows are what this phone is shown: "hidden" is not among them.
        let rows = [
            row("a", "Audio"),
            row("b", "Utilities"),
            row("c", "Utilities"),
        ];
        let mut cat = cat();
        assert_eq!(
            category_rows(&cat, &rows),
            [
                vec!["Audio".into(), "Audio".into(), "".into(), Value::Int(1)],
                vec![
                    "Utilities".into(),
                    "Utilities".into(),
                    "".into(),
                    Value::Int(2)
                ],
            ],
            "no list: the apps' own categories"
        );
        cat.categories = vec![
            reef_backend::catalogue::Category {
                id: "Utilities".into(),
                label: "Utilities".into(),
                icon: "icon-m-flashlight".into(),
                count: 9,
            },
            reef_backend::catalogue::Category {
                id: "Games".into(),
                label: "Games".into(),
                icon: "icon-m-game-controller".into(),
                count: 3,
            },
            reef_backend::catalogue::Category {
                id: "Audio".into(),
                label: "Music and audio".into(),
                icon: "icon-m-music".into(),
                count: 1,
            },
        ];
        let got = category_rows(&cat, &rows);
        assert_eq!(got.len(), 2, "Games has nothing shown here");
        assert_eq!(got[0][3], Value::Int(2), "counted from what is shown");
        assert_eq!(got[1][1], Value::Str("Music and audio".into()));
        cat.collections = vec![
            reef_backend::catalogue::Collection {
                id: "picks".into(),
                title: "Picks".into(),
                subtitle: String::new(),
                generated: false,
                apps: vec!["c".into(), "hidden".into(), "b".into(), "a".into()],
            },
            reef_backend::catalogue::Collection {
                id: "gone".into(),
                title: "Gone".into(),
                subtitle: String::new(),
                generated: true,
                apps: vec!["hidden".into()],
            },
        ];
        let got = collection_rows(&cat, &rows);
        assert_eq!(got.len(), 1, "a row needs three apps shown here");
        assert_eq!(
            got[0][4],
            Value::List(vec!["c".into(), "b".into(), "a".into()])
        );
        let names = |kind: &str, id: &str| -> Vec<String> {
            browse_rows(&cat, &rows, kind, id)
                .into_iter()
                .map(|r| r.name)
                .collect()
        };
        assert_eq!(names("collection", "picks"), ["c", "b", "a"]);
        // Its page opens whatever the home page shows.
        assert_eq!(names("collection", "gone"), Vec::<String>::new());
        assert_eq!(names("category", "utilities"), ["b", "c"]);
        assert_eq!(names("all", ""), ["a", "b", "c"]);
        assert!(names("category", "Games").is_empty() && names("nope", "x").is_empty());
    }

    #[test]
    fn search_ranks_and_forgives_one_typo() {
        let row = |name: &str, title: &str, summary: &str, keywords: &[&str]| PackageRow {
            name: name.into(),
            title: title.into(),
            summary: summary.into(),
            category: "Utilities".into(),
            version: String::new(),
            install_state: "not_installed",
            installed_version: String::new(),
            licence_model: "free",
            licensed: false,
            publisher: "Shipwright".into(),
            icon_path: String::new(),
            featured: false,
            is_new: false,
            updated: String::new(),
            hero_path: String::new(),
            keywords: keywords.iter().map(|k| (*k).to_string()).collect(),
            category_label: String::new(),
        };
        let rows = [
            row("notes", "Notes", "Write down a browser link", &[]),
            row(
                "pacific",
                "Pacific",
                "A web browser that blocks trackers",
                &["browser", "web"],
            ),
            row("webcam", "Web camera", "Use the phone as a webcam", &[]),
            row("mail", "Shoal Mail", "Email for your accounts", &[]),
        ];
        let names = |q: &str| -> Vec<String> {
            filter_rows(&rows, q).into_iter().map(|r| r.name).collect()
        };
        // A keyword outranks a summary word.
        assert_eq!(names("browser"), ["pacific", "notes"]);
        // The start of the title first, then a title word.
        assert_eq!(names("web"), ["webcam", "pacific"]);
        assert_eq!(names("mail"), ["mail"]);
        // One letter wrong, missing or swapped, in words of five or more.
        assert_eq!(names("broswer"), ["pacific"]);
        assert_eq!(names("pacfic"), ["pacific"]);
        assert!(names("mial").is_empty(), "too short to guess");
        // Every word must match; blank keeps everything in order.
        assert_eq!(names("web phone"), ["webcam"]);
        assert_eq!(names("  ").len(), 4);
        assert!(one_edit("browser", "browsr") && one_edit("abc", "acb") && !one_edit("abc", "cab"));
    }

    #[test]
    fn recent_rows_are_newest_first() {
        let row = |title: &str, updated: &str| PackageRow {
            name: title.to_lowercase(),
            title: title.into(),
            summary: String::new(),
            category: String::new(),
            version: String::new(),
            install_state: "not_installed",
            installed_version: String::new(),
            licence_model: "free",
            licensed: false,
            publisher: String::new(),
            icon_path: String::new(),
            featured: false,
            is_new: false,
            updated: updated.into(),
            hero_path: String::new(),
            keywords: Vec::new(),
            category_label: String::new(),
        };
        let rows = [
            row("Keys", "2026-10-08"),
            row("Undated", ""),
            row("Pilot", "2026-10-11"),
            row("Migrate", "2026-10-11"),
        ];
        let titles: Vec<String> = recent_rows(&rows).into_iter().map(|r| r.title).collect();
        assert_eq!(titles, ["Migrate", "Pilot", "Keys"]);
        let many: Vec<PackageRow> = (0..15)
            .map(|i| row(&format!("A{i:02}"), "2026-10-01"))
            .collect();
        assert_eq!(recent_rows(&many).len(), RECENT_COUNT);
    }

    #[test]
    fn details_map_has_every_documented_key() {
        let c = cat();
        let p = c
            .visible_package("shipwright-shoal-bridge-airpods-ui")
            .unwrap();
        let d = package_details(p, &InstallState::NotInstalled, false, &no_asset);
        let keys: Vec<&str> = d.iter().map(|(k, _)| *k).collect();
        assert_eq!(
            keys,
            [
                "name",
                "title",
                "summary",
                "description",
                "category",
                "version",
                "installState",
                "installedVersion",
                "updateVersion",
                "testedOn",
                "deviceTested",
                "permissions",
                "sandboxed",
                "licenceModel",
                "licensed",
                "purchaseUrl",
                "spdx",
                "sizeText",
                "keelTier",
                "homepage",
                "source",
                "publisher",
                "iconPath",
                "screenshotPaths",
                "added",
                "updated",
                "changelogJson",
                "servicesJson",
                "systemChangesJson"
            ]
        );
        let get = |k: &str| d.iter().find(|(key, _)| *key == k).unwrap().1.clone();
        assert_eq!(
            get("testedOn"),
            Value::List(vec!["5.2.0.17".into(), "5.2.0.18".into()])
        );
        assert_eq!(
            get("permissions"),
            Value::List(vec!["Bluetooth".into(), "Audio".into()])
        );
        assert_eq!(get("sandboxed"), Value::Bool(true));
        assert_eq!(
            get("purchaseUrl"),
            Value::Str("https://example.invalid/buy".into())
        );
        assert_eq!(get("installState"), Value::Str("not_installed".into()));
        assert_eq!(get("sizeText"), Value::Str(String::new()));

        let keel = c.visible_package("shipwright-keel-silica").unwrap();
        let d = package_details(
            keel,
            &InstallState::Installed {
                version: "0.1.0-1".into(),
            },
            false,
            &no_asset,
        );
        let get = |k: &str| d.iter().find(|(key, _)| *key == k).unwrap().1.clone();
        assert_eq!(get("sandboxed"), Value::Bool(false));
        assert_eq!(get("spdx"), Value::Str("BSD-3-Clause".into()));
        assert_eq!(get("sizeText"), Value::Str("1.5 MB".into()));
        assert_eq!(get("installedVersion"), Value::Str("0.1.0-1".into()));
        assert_eq!(get("updateVersion"), Value::Str(String::new()));
        assert_eq!(get("purchaseUrl"), Value::Str(String::new()));

        // An update names PackageKit's version, not the catalogue's, which a
        // stale cache can leave older than the installed build.
        let d = package_details(
            keel,
            &InstallState::UpdateAvailable {
                installed: "0.1.0-9".into(),
                available: "0.1.0-10".into(),
            },
            false,
            &no_asset,
        );
        let get = |k: &str| d.iter().find(|(key, _)| *key == k).unwrap().1.clone();
        assert_eq!(get("updateVersion"), Value::Str("0.1.0-10".into()));
    }

    #[test]
    fn state_of_matches_rows() {
        let installed = [pkg("shipwright-keel-silica", "0.1.0-1")];
        let c = cat();
        assert_eq!(
            state_of(&c, &installed, &[], "shipwright-keel-silica"),
            Some(InstallState::Installed {
                version: "0.1.0-1".into()
            })
        );
        assert_eq!(
            state_of(&c, &installed, &[], "shipwright-shoal-messages"),
            Some(InstallState::NotInstalled)
        );
        // Not in the catalogue, so no details.
        assert_eq!(state_of(&c, &[], &[], "unlisted"), None);
    }

    #[test]
    fn sizes_and_messages() {
        assert_eq!(size_text(None), "");
        assert_eq!(size_text(Some(512)), "512 B");
        assert_eq!(size_text(Some(2048)), "2.0 kB");
        assert_eq!(size_text(Some(200 * 1024)), "200 kB");
        assert_eq!(size_text(Some(3 * 1024 * 1024 * 1024)), "3.0 GB");
        assert_eq!(message("no_licence_server", &[]), "\u{1e}no_licence_server");
        assert_eq!(
            message("catalogue_missing", &["aarch64"]),
            "\u{1e}catalogue_missing\u{1f}aarch64"
        );
        // Arguments cannot smuggle in separators.
        assert_eq!(
            message("claim_failed", &["a\u{1f}b\u{1e}c"]),
            "\u{1e}claim_failed\u{1f}abc"
        );
    }

    #[test]
    fn dates() {
        assert_eq!(date_text(0), "1970-01-01");
        assert_eq!(date_text(1_790_000_000), "2026-09-21");
        assert_eq!(date_text(951_782_400), "2000-02-29");
    }

    const T0: i64 = 1_790_000_000;
    const DAY: i64 = 86_400;

    fn signer() -> (Signer, KeySet) {
        let s = Signer::from_seed("test", [7; 32]).unwrap();
        let mut k = KeySet::new();
        k.insert_text(&s.public_key_text()).unwrap();
        (s, k)
    }

    fn stored(token: String, keys: &KeySet, now: i64, revoked: bool) -> StoredLicence {
        let status = Licence::verify_any_app(&token, keys, &Policy::default(), now);
        StoredLicence {
            app_id: "shoal-messages".into(),
            token,
            status,
            revoked,
        }
    }

    #[test]
    fn licence_rows_map_every_status() {
        let (s, keys) = signer();
        let claims = Claims {
            app: "shoal-messages".into(),
            exp: Some(T0 + 30 * DAY),
            iat: T0,
            kid: "test".into(),
            lid: "lid-1".into(),
            plan: Plan::Subscription,
        };
        let token = s.issue(&claims).unwrap();
        let title = |app: &str| (app == "shoal-messages").then(|| "Messages".to_string());

        let row = licence_row(&stored(token.clone(), &keys, T0, false), &title);
        assert_eq!(row.status, "active");
        assert_eq!(row.title, "Messages");
        assert_eq!(row.plan, "subscription");
        assert_eq!(row.licence_id, "lid-1");
        assert_eq!(row.expires_text, date_text(T0 + 30 * DAY));
        assert_eq!(row.values().len(), LICENCE_ROLES.len());

        // Past expiry, inside the 7-day grace.
        let row = licence_row(&stored(token.clone(), &keys, T0 + 32 * DAY, false), &title);
        assert_eq!(row.status, "grace");

        // Past grace: expired, but the (unverified) claims still identify it
        // for a refresh.
        let st = stored(token.clone(), &keys, T0 + 60 * DAY, false);
        assert!(!licence_usable(&st));
        let row = licence_row(&st, &title);
        assert_eq!(row.status, "expired");
        assert_eq!(row.licence_id, "lid-1");
        assert_eq!(row.plan, "subscription");

        let st = stored(token.clone(), &keys, T0, true);
        assert_eq!(licence_status(&st), "revoked");
        assert!(!licence_usable(&st));

        // Unknown key: invalid, and nothing from the payload is shown.
        let row = licence_row(&stored(token, &KeySet::new(), T0, false), &|_| None);
        assert_eq!(row.status, "invalid");
        assert_eq!(row.title, "shoal-messages");
        assert_eq!(row.plan, "");
        assert_eq!(row.licence_id, "");
        assert_eq!(row.expires_text, "");
    }

    #[test]
    fn catalogue_titles_for_licences() {
        let c = cat();
        assert_eq!(
            title_for_app(Some(&c), "shoal-messages").as_deref(),
            Some("Messages")
        );
        assert_eq!(title_for_app(Some(&c), "nope"), None);
        assert_eq!(title_for_app(None, "shoal-messages"), None);
    }
}

/// One step from a list model's rows to new ones (`ReefListModel::set_rows`),
/// applied in order; indices are the rows' places at that step.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RowEdit {
    Remove(usize),
    Insert(usize),
    Change(usize),
}

/// The removals, insertions and in-place changes that turn `old` into
/// `new`, a row being the same row when its first value (the package name)
/// is; `None` when a reset is the honest answer (rows kept in a different
/// order, or a name twice).
pub fn edits(old: &[Vec<Value>], new: &[Vec<Value>]) -> Option<Vec<RowEdit>> {
    let key = |r: &Vec<Value>| r.first().cloned();
    let old_keys: Vec<_> = old.iter().map(key).collect();
    let new_keys: Vec<_> = new.iter().map(key).collect();
    let unique =
        |keys: &[Option<Value>]| keys.iter().enumerate().all(|(i, k)| !keys[..i].contains(k));
    if !unique(&old_keys) || !unique(&new_keys) {
        return None;
    }
    let kept_old = old_keys.iter().filter(|k| new_keys.contains(k));
    let kept_new = new_keys.iter().filter(|k| old_keys.contains(k));
    if !kept_old.eq(kept_new) {
        return None;
    }
    let mut out = Vec::new();
    let mut current: Vec<Option<Value>> = old_keys.clone();
    for i in (0..old_keys.len()).rev() {
        if !new_keys.contains(&old_keys[i]) {
            out.push(RowEdit::Remove(i));
            current.remove(i);
        }
    }
    for (i, k) in new_keys.iter().enumerate() {
        if current.get(i) == Some(k) {
            let was = old_keys.iter().position(|o| o == k).map(|j| &old[j]);
            if was != Some(&new[i]) {
                out.push(RowEdit::Change(i));
            }
        } else {
            out.push(RowEdit::Insert(i));
            current.insert(i, k.clone());
        }
    }
    Some(out)
}

#[cfg(test)]
mod edit_tests {
    use super::{edits, RowEdit, Value};

    fn rows(items: &[(&str, &str)]) -> Vec<Vec<Value>> {
        items
            .iter()
            .map(|(n, s)| vec![Value::from(*n), Value::from(*s)])
            .collect()
    }
    /// Applies `edits` as the model does and returns the result.
    fn apply(old: &[Vec<Value>], new: &[Vec<Value>]) -> Vec<Vec<Value>> {
        let mut out = old.to_vec();
        for e in edits(old, new).expect("incremental") {
            match e {
                RowEdit::Remove(i) => {
                    out.remove(i);
                }
                RowEdit::Insert(i) => out.insert(i, new[i].clone()),
                RowEdit::Change(i) => out[i] = new[i].clone(),
            }
        }
        out
    }

    #[test]
    fn a_changed_state_is_one_change_not_a_reset() {
        let old = rows(&[("a", "installed"), ("b", "available"), ("c", "installed")]);
        let new = rows(&[("a", "installed"), ("b", "installed"), ("c", "installed")]);
        assert_eq!(edits(&old, &new), Some(vec![RowEdit::Change(1)]));
        assert_eq!(apply(&old, &new), new);
    }

    #[test]
    fn rows_come_and_go_in_place() {
        let old = rows(&[("a", "1"), ("b", "1"), ("c", "1"), ("d", "1")]);
        let new = rows(&[("a", "1"), ("x", "1"), ("c", "2"), ("y", "1")]);
        assert_eq!(apply(&old, &new), new);
        let e = edits(&old, &new).unwrap();
        assert!(e.contains(&RowEdit::Remove(1)) && e.contains(&RowEdit::Remove(3)));
        assert!(e.contains(&RowEdit::Change(2)));
    }

    #[test]
    fn from_and_to_empty() {
        let full = rows(&[("a", "1"), ("b", "1")]);
        assert_eq!(apply(&[], &full), full);
        assert_eq!(apply(&full, &[]), Vec::<Vec<Value>>::new());
    }

    #[test]
    fn a_new_order_or_a_repeated_name_resets() {
        let old = rows(&[("a", "1"), ("b", "1")]);
        assert_eq!(edits(&old, &rows(&[("b", "1"), ("a", "1")])), None);
        assert_eq!(edits(&old, &rows(&[("a", "1"), ("a", "2")])), None);
    }
}
