// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The store index (catalogue v2, docs/specs/reef-storefront.md): one
//! signed `store/index.json` per repository directory with what lists,
//! rows and search need, and one details file per app, fetched when its
//! page opens or before it is installed (`tools/build/reef/gen-store.py`).
//!
//! [`parse_index`] turns the index into the same [`Catalogue`] a
//! `catalogue.json` gives, every package carrying its
//! [`DetailsRef`](crate::catalogue::DetailsRef) until
//! [`Catalogue::merge_details`] fills it in. Each details file is checked
//! against the SHA-256 the index gives for it. The index's own signature
//! is not checked here, so the app does not read an index yet.
//!
//! An app is listed only when it has a source this client installs (an
//! RPM); the index may describe others (Flatpak, Android, Marathon
//! packages) for clients that can.

use std::collections::BTreeMap;

use serde::Deserialize;
use sha2::{Digest, Sha256};

use crate::catalogue::{
    Catalogue, CatalogueError, Category, Change, Collection, Component, DetailsRef, Install,
    LicenceModel, Origin, Package, Service, SystemChange,
};

/// The index schema this client reads.
pub const INDEX_SCHEMA: u32 = 2;

#[derive(Debug, Deserialize)]
struct Index {
    schema: u32,
    release: String,
    arch: String,
    #[serde(default)]
    generated_at: String,
    revision: u64,
    #[serde(default)]
    categories: Vec<Category>,
    #[serde(default)]
    collections: Vec<Collection>,
    #[serde(default)]
    featured: Vec<String>,
    /// The processor needs of the builds named in apps' variants.
    #[serde(default)]
    component_cpu: BTreeMap<String, Vec<String>>,
    apps: Vec<IndexApp>,
}

/// How an app can be installed.
#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
enum Source {
    Rpm {
        package: String,
    },
    Flatpak {
        #[serde(default)]
        remote: String,
        #[serde(rename = "ref")]
        reference: String,
    },
    Android {
        package: String,
        #[serde(default)]
        store: String,
    },
    /// Marathon packages: not installable here yet.
    #[serde(other)]
    Other,
}

impl Source {
    /// What the store handler installs it with, when it can.
    fn install(&self) -> Option<Install> {
        let install = match self {
            Source::Flatpak { remote, reference } => Install::Flatpak {
                remote: remote.clone(),
                reference: reference.clone(),
            },
            Source::Android { package, store } => Install::Android {
                package: package.clone(),
                store: store.clone(),
            },
            Source::Rpm { .. } | Source::Other => return None,
        };
        install.handler_id().is_some().then_some(install)
    }
}

#[derive(Debug, Deserialize)]
struct IndexApp {
    id: String,
    title: String,
    summary: String,
    #[serde(default = "other")]
    category: String,
    version: String,
    licence: LicenceModel,
    tested_on: Vec<String>,
    #[serde(default = "yes")]
    device_tested: bool,
    #[serde(default)]
    requires_cpu: Vec<String>,
    #[serde(default)]
    variants: Vec<Vec<String>>,
    #[serde(default = "yes")]
    sandboxed: bool,
    #[serde(default)]
    size: Option<u64>,
    #[serde(default)]
    icon: Option<String>,
    #[serde(default)]
    hero: Option<String>,
    #[serde(default)]
    publisher: String,
    #[serde(default)]
    added: Option<String>,
    #[serde(default)]
    updated: Option<String>,
    #[serde(default)]
    keel_tier: Option<String>,
    #[serde(default)]
    keywords: Vec<String>,
    sources: Vec<Source>,
    details: DetailsRef,
}

fn other() -> String {
    "Other".into()
}

fn yes() -> bool {
    true
}

/// An app's details file: its whole catalogue entry, and the components
/// of what it brings.
#[derive(Debug, Deserialize)]
struct Details {
    #[serde(flatten)]
    package: Package,
    #[serde(default)]
    components: BTreeMap<String, Component>,
}

/// Parses a verified index into a catalogue; with it, the index revision
/// (which must never go backwards: `metadata::verify_index`).
pub fn parse_index(bytes: &[u8], arch: &str) -> Result<(Catalogue, u64), CatalogueError> {
    let index: Index =
        serde_json::from_slice(bytes).map_err(|e| CatalogueError::Json(e.to_string()))?;
    if index.schema != INDEX_SCHEMA {
        return Err(CatalogueError::UnsupportedSchema(index.schema));
    }
    if index.arch != arch {
        return Err(CatalogueError::WrongArch {
            expected: arch.into(),
            found: index.arch,
        });
    }
    let packages: Vec<Package> = index
        .apps
        .into_iter()
        .filter_map(|a| {
            let install = a.sources.iter().find_map(Source::install);
            let rpm = a
                .sources
                .iter()
                .any(|s| matches!(s, Source::Rpm { package } if *package == a.id));
            (rpm || install.is_some()).then_some((a, install))
        })
        .map(|(a, install)| Package {
            name: a.id,
            version: a.version,
            title: a.title,
            summary: a.summary,
            description: String::new(),
            category: a.category,
            tested_on: a.tested_on,
            device_tested: a.device_tested,
            permissions: Vec::new(),
            sandboxed: a.sandboxed,
            licence: a.licence,
            spdx: None,
            size: a.size,
            requires_cpu: a.requires_cpu,
            variants: a.variants,
            homepage: None,
            source: None,
            icon: a.icon,
            screenshots: Vec::new(),
            publisher: a.publisher,
            added: a.added,
            keel_tier: a.keel_tier,
            changelog: Vec::<Change>::new(),
            services: Vec::<Service>::new(),
            system_changes: Vec::<SystemChange>::new(),
            requires: Vec::new(),
            keywords: a.keywords,
            updated: a.updated,
            hero: a.hero,
            details: Some(a.details),
            install,
            origin: Origin::Reef,
            android: None,
        })
        .collect();
    let components = index
        .component_cpu
        .into_iter()
        .map(|(name, requires_cpu)| {
            (
                name,
                Component {
                    summary: String::new(),
                    desktop: false,
                    listed: false,
                    sandboxed: true,
                    permissions: Vec::new(),
                    services: Vec::new(),
                    system_changes: Vec::new(),
                    requires_cpu,
                },
            )
        })
        .collect();
    let mut cat = Catalogue {
        schema: crate::catalogue::SCHEMA_VERSION,
        release: index.release,
        arch: index.arch,
        generated_at: index.generated_at,
        packages,
        featured: index.featured,
        components,
        categories: index.categories,
        collections: index.collections,
    };
    cat.sanitize()?;
    Ok((cat, index.revision))
}

impl Catalogue {
    /// Fills in `name`'s details from the bytes of its details file. They
    /// must be exactly what the index named (size and SHA-256) and describe
    /// the same build; the package then has everything a `catalogue.json`
    /// entry has. What only the index carries (keywords, the update day,
    /// the banner) is kept.
    pub fn merge_details(&mut self, name: &str, bytes: &[u8]) -> Result<(), CatalogueError> {
        let invalid = |why: String| CatalogueError::InvalidPackage {
            name: name.to_owned(),
            why,
        };
        let pos = self
            .packages
            .iter()
            .position(|p| p.name == name)
            .ok_or_else(|| invalid("not in the catalogue".into()))?;
        let Some(want) = self.packages[pos].details.clone() else {
            return Ok(());
        };
        if bytes.len() as u64 != want.size || !sha256_matches(bytes, &want.sha256) {
            return Err(invalid(format!("{} does not match the index", want.path)));
        }
        let details: Details =
            serde_json::from_slice(bytes).map_err(|e| CatalogueError::Json(e.to_string()))?;
        let mut package = details.package;
        let known = &self.packages[pos];
        if package.name != known.name || package.version != known.version {
            return Err(invalid(format!(
                "{} describes {} {}",
                want.path, package.name, package.version
            )));
        }
        package.keywords.clone_from(&known.keywords);
        package.updated.clone_from(&known.updated);
        package.hero.clone_from(&known.hero);
        package.details = None;
        crate::catalogue::sanitize_package(&mut package)?;
        self.packages[pos] = package;
        for (n, mut c) in details.components {
            crate::catalogue::sanitize_component(&mut c);
            self.components.insert(n, c);
        }
        Ok(())
    }

    /// Packages whose details are not merged yet.
    pub fn pending_details(&self) -> Vec<(&str, &DetailsRef)> {
        self.packages
            .iter()
            .filter_map(|p| p.details.as_ref().map(|d| (p.name.as_str(), d)))
            .collect()
    }
}

/// Whether `bytes` hash to `hex` (lower-case SHA-256).
pub fn sha256_matches(bytes: &[u8], hex: &str) -> bool {
    use std::fmt::Write as _;
    let digest = Sha256::digest(bytes);
    let mut s = String::with_capacity(64);
    for b in &digest {
        write!(s, "{b:02x}").ok();
    }
    s == hex
}

#[cfg(test)]
#[allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    reason = "tests"
)]
mod tests {
    use super::*;

    fn sha(bytes: &[u8]) -> String {
        use std::fmt::Write as _;
        Sha256::digest(bytes)
            .iter()
            .fold(String::new(), |mut s, b| {
                write!(s, "{b:02x}").ok();
                s
            })
    }

    fn details(name: &str, version: &str) -> Vec<u8> {
        serde_json::json!({
            "name": name, "version": version, "title": "Full title", "summary": "s",
            "description": "The long text", "category": "Utilities",
            "tested_on": ["5.2.0.22"], "licence": {"model": "free"},
            "screenshots": ["assets/shots/a.png", "https://evil.example/x.png"],
            "changelog": [{"version": version, "date": "2026-10-20", "notes": ["Faster"]}],
            "requires": ["fx-lib"],
            "components": {"fx-lib": {"summary": "the library"}},
        })
        .to_string()
        .into_bytes()
    }

    fn index(details: &[u8]) -> Vec<u8> {
        serde_json::json!({
            "schema": 2, "release": "5.2.0.22", "arch": "aarch64", "revision": 1_793_102_400_u64,
            "generated_at": "2026-10-27T12:00:00Z",
            "categories": [
                {"id": "Utilities", "label": "Utilities", "icon": "icon-m-flashlight", "count": 1},
                {"id": "Games", "label": "Games", "icon": "../../etc/passwd", "count": 0}],
            "collections": [
                {"id": "picks", "title": "Picks", "apps": ["fx", "gone"]},
                {"id": "empty", "title": "Empty", "apps": ["gone"]}],
            "featured": ["fx"],
            "component_cpu": {"engine": ["asimddp"], "engine-v80": []},
            "apps": [
                {"id": "fx", "title": "Fx", "summary": "s", "category": "Utilities",
                 "version": "1.0-1", "licence": {"model": "free"}, "tested_on": ["5.2.0.22"],
                 "keywords": ["torch"], "updated": "2026-10-20", "hero": "assets/shots/a.png",
                 "variants": [["engine", "engine-v80"]],
                 "sources": [{"kind": "rpm", "package": "fx"}],
                 "details": {"path": "apps/fx.0123456789abcdef.json", "sha256": sha(details),
                             "size": details.len()}},
                {"id": "org.example.Flat", "title": "Flat", "summary": "s", "version": "1",
                 "licence": {"model": "free"}, "tested_on": ["5.2.0.22"],
                 "sources": [{"kind": "flatpak", "ref": "app/org.example.Flat/aarch64/stable"}],
                 "details": {"path": "apps/flat.json", "sha256": sha(b"x"), "size": 1}}]
        })
        .to_string()
        .into_bytes()
    }

    #[test]
    fn index_becomes_a_catalogue_awaiting_details() {
        let d = details("fx", "1.0-1");
        let (cat, revision) = parse_index(&index(&d), "aarch64").unwrap();
        assert_eq!(revision, 1_793_102_400);
        // Only what this client installs.
        assert_eq!(cat.packages.len(), 1);
        let p = &cat.packages[0];
        assert_eq!(p.keywords, ["torch"]);
        assert!(p.details.is_some());
        assert!(p.description.is_empty());
        assert_eq!(cat.collections.len(), 1);
        assert_eq!(cat.collections[0].apps, ["fx"]);
        assert_eq!(cat.categories[0].icon, "icon-m-flashlight");
        assert_eq!(cat.categories[1].icon, "", "not a theme icon");
        // The variant builds' processor needs, so the app is shown or hidden
        // before its details come.
        let v80: std::collections::BTreeSet<String> = ["asimd".to_string()].into();
        assert_eq!(cat.variant_picks("fx", Some(&v80)).unwrap(), ["engine-v80"]);
        assert_eq!(cat.visible_on(Some(&v80)).len(), 1);
        assert_eq!(cat.pending_details().len(), 1);
    }

    #[test]
    fn details_merge_after_their_hash_is_checked() {
        let d = details("fx", "1.0-1");
        let (mut cat, _) = parse_index(&index(&d), "aarch64").unwrap();
        let mut tampered = d.clone();
        tampered[10] ^= 1;
        assert!(cat.merge_details("fx", &tampered).is_err());
        cat.merge_details("fx", &d).unwrap();
        let p = &cat.packages[0];
        assert!(p.details.is_none());
        assert_eq!(p.description, "The long text");
        assert_eq!(
            p.screenshots,
            ["assets/shots/a.png"],
            "a URL is not an asset"
        );
        assert_eq!(p.keywords, ["torch"], "kept from the index");
        assert_eq!(p.requires, ["fx-lib"]);
        assert_eq!(cat.components["fx-lib"].summary, "the library");
        assert!(cat.pending_details().is_empty());
        // Merged once; again is a no-op.
        cat.merge_details("fx", b"anything").unwrap();
    }

    #[test]
    fn details_of_another_build_are_refused() {
        let d = details("fx", "2.0-1");
        let (mut cat, _) = parse_index(&index(&d), "aarch64").unwrap();
        let err = cat.merge_details("fx", &d).unwrap_err().to_string();
        assert!(err.contains("describes fx 2.0-1"), "{err}");
    }

    #[test]
    fn wrong_schema_arch_or_details_path() {
        let d = details("fx", "1.0-1");
        let ix = index(&d);
        assert!(matches!(
            parse_index(&ix, "armv7hl"),
            Err(CatalogueError::WrongArch { .. })
        ));
        let mut v: serde_json::Value = serde_json::from_slice(&ix).unwrap();
        v["schema"] = 1.into();
        assert!(parse_index(v.to_string().as_bytes(), "aarch64").is_err());
        let mut v: serde_json::Value = serde_json::from_slice(&ix).unwrap();
        v["apps"][0]["details"]["path"] = "../../catalogue.json".into();
        assert!(parse_index(v.to_string().as_bytes(), "aarch64").is_err());
    }
}
