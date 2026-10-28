// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The Flathub and F-Droid catalogues the store handler keeps
//! (`flathub.json`, `fdroid.json`), as Reef packages.

use std::collections::BTreeSet;

use serde::Deserialize;

use crate::catalogue::{Catalogue, Install, LicenceModel, Origin, Package};

#[derive(Deserialize)]
struct Listing<T> {
    #[serde(default)]
    icons: String,
    apps: Vec<T>,
}

#[derive(Deserialize)]
struct FlathubApp {
    id: String,
    name: String,
    #[serde(default)]
    summary: String,
    #[serde(default)]
    description: String,
    #[serde(default)]
    categories: Vec<String>,
    #[serde(default)]
    developer: String,
    #[serde(default)]
    license: String,
    #[serde(default)]
    homepage: String,
    #[serde(default)]
    icon: String,
    #[serde(default)]
    screenshots: Vec<String>,
    #[serde(default)]
    version: String,
    #[serde(default)]
    released: u64,
}

#[derive(Deserialize)]
struct FdroidApp {
    app_id: String,
    pkg: String,
    name: String,
    #[serde(default)]
    summary: String,
    #[serde(default)]
    description: String,
    #[serde(default)]
    author: String,
    #[serde(default)]
    categories: Vec<String>,
    #[serde(default)]
    icon: String,
    #[serde(default)]
    license: String,
    #[serde(default)]
    website: String,
    #[serde(default, rename = "lastUpdated")]
    last_updated: u64,
    #[serde(default)]
    version: serde_json::Value,
}

/// Flathub's phone-fit apps; icons are files in the listing's `icons`.
pub fn flathub(json: &[u8]) -> Vec<Package> {
    let Ok(listing) = serde_json::from_slice::<Listing<FlathubApp>>(json) else {
        return Vec::new();
    };
    listing
        .apps
        .into_iter()
        .map(|a| {
            let icon = (!a.icon.is_empty() && !a.icon.contains('/'))
                .then(|| format!("{}/{}", listing.icons, a.icon));
            let mut p = blank(&a.id, a.name, Origin::Flathub);
            p.install = Some(Install::Flatpak {
                remote: "flathub".into(),
                reference: a.id,
            });
            p.version = a.version;
            p.summary = a.summary;
            p.description = a.description;
            p.category = store_category(&a.categories);
            p.publisher = a.developer;
            p.spdx = (!a.license.is_empty()).then_some(a.license);
            p.homepage = https(a.homepage);
            p.icon = icon;
            p.screenshots = a
                .screenshots
                .into_iter()
                .filter_map(https)
                .take(5)
                .collect();
            p.updated = day(a.released);
            p
        })
        .collect()
}

/// F-Droid's apps this phone runs, installed through Deckard.
pub fn fdroid(json: &[u8]) -> Vec<Package> {
    let Ok(listing) = serde_json::from_slice::<Listing<FdroidApp>>(json) else {
        return Vec::new();
    };
    listing
        .apps
        .into_iter()
        .filter(|a| a.app_id == format!("android:{}", a.pkg))
        .map(|a| {
            let mut p = blank(&a.app_id, a.name, Origin::Fdroid);
            p.install = Some(Install::Android {
                package: a.pkg,
                store: "fdroid".into(),
            });
            a.version["name"]
                .as_str()
                .unwrap_or_default()
                .clone_into(&mut p.version);
            p.summary = a.summary;
            p.description = plain_text(&a.description);
            p.category = store_category(&a.categories);
            p.publisher = a.author;
            p.spdx = (!a.license.is_empty()).then_some(a.license);
            p.homepage = https(a.website);
            p.icon = https(a.icon);
            p.updated = day(a.last_updated);
            p
        })
        .collect()
}

/// The store's categories, the specific ones first: each Flathub
/// (freedesktop) and F-Droid category id an app names, mapped to one of
/// them. F-Droid alone names 115.
const CATEGORIES: [(&str, &[&str]); 13] = [
    (
        "Communication",
        &[
            "Phone & SMS",
            "Messaging",
            "Social Network",
            "Email",
            "Chat",
            "InstantMessaging",
            "Telephony",
            "VideoConference",
        ],
    ),
    (
        "Health & Fitness",
        &[
            "Sports & Health",
            "Health Manager",
            "Workout",
            "Habit Tracker",
            "Medical",
        ],
    ),
    (
        "Money",
        &[
            "Money",
            "Finance Manager",
            "Wallet",
            "Market & Price",
            "Finance",
        ],
    ),
    (
        "Navigation & Travel",
        &[
            "Navigation",
            "Location Tracker & Sharer",
            "Weather",
            "Maps",
            "Travel",
        ],
    ),
    (
        "Reading",
        &[
            "Reading",
            "Ebook Reader",
            "Translation & Dictionary",
            "News",
            "Feed",
            "Dictionary",
            "Literature",
        ],
    ),
    (
        "Productivity",
        &[
            "Writing",
            "Note",
            "Task",
            "Calendar & Agenda",
            "Time Tracker",
            "Schedule",
            "Office",
            "TextTools",
            "WordProcessor",
            "Spreadsheet",
            "Calendar",
            "ProjectManagement",
        ],
    ),
    (
        "Music & Video",
        &[
            "Multimedia",
            "Local Media Player",
            "Online Media Player",
            "Recorder",
            "Music Practice Tool",
            "AudioVideo",
            "Audio",
            "Video",
            "Music",
            "Player",
            "Podcast",
        ],
    ),
    (
        "Photo & Graphics",
        &[
            "Graphics",
            "Camera",
            "Wallpaper",
            "2DGraphics",
            "3DGraphics",
            "Photography",
            "Viewer",
        ],
    ),
    (
        "Education & Science",
        &[
            "Science & Education",
            "Education",
            "Science",
            "Math",
            "Astronomy",
        ],
    ),
    (
        "Security & Privacy",
        &[
            "Security",
            "Password & 2FA",
            "VPN & Proxy",
            "File Encryption & Vault",
        ],
    ),
    ("Developer Tools", &["Development", "IDE", "Debugger"]),
    (
        "Internet",
        &[
            "Internet",
            "Browser",
            "Download",
            "Network",
            "WebBrowser",
            "FileTransfer",
            "File Transfer",
            "Cloud Storage & File Sync",
        ],
    ),
    (
        "Utilities",
        &[
            "System",
            "Connectivity",
            "Timer",
            "Calculator",
            "Clock",
            "Alarm Clock",
            "Keyboard & IME",
            "Launcher",
            "App Manager",
            "Remote Controller",
            "Notification",
            "Utility",
            "Settings",
            "FileManager",
            "Accessibility",
        ],
    ),
];

/// The theme icon of a store category (`icon-m-<base>`, in
/// marathon-icon-theme's map).
pub fn category_icon(category: &str) -> &'static str {
    match category {
        "Games" => "icon-m-game",
        "Communication" => "icon-m-message",
        "Health & Fitness" => "icon-m-health",
        "Money" => "icon-m-store-money",
        "Navigation & Travel" => "icon-m-store-navigation",
        "Reading" => "icon-m-store-reading",
        "Productivity" => "icon-m-note",
        "Music & Video" => "icon-m-music",
        "Photo & Graphics" => "icon-m-store-graphics",
        "Education & Science" => "icon-m-education",
        "Security & Privacy" => "icon-m-store-security",
        "Developer Tools" => "icon-m-store-developer",
        "Internet" => "icon-m-website",
        "Utilities" => "icon-m-store-utilities",
        _ => "icon-m-other",
    }
}

/// How many apps the front page's banner turns through without a
/// catalogue that names its own.
const FEATURED_FALLBACK: usize = 6;

/// The store category of an app from the categories it names: Games for
/// any game, else the first of [`CATEGORIES`] one of them belongs to.
fn store_category(names: &[String]) -> String {
    if names.iter().any(|n| n.contains("Game")) {
        return "Games".into();
    }
    CATEGORIES
        .iter()
        .find(|(_, members)| names.iter().any(|n| members.contains(&n.as_str())))
        .map_or_else(|| "Other".into(), |(category, _)| (*category).to_owned())
}

/// Reef's catalogue with the handler's apps it does not list itself: an
/// app in both is Reef's row. Until Reef's catalogue features apps, the
/// newest Flathub apps with screenshots are the front page's banner.
pub fn merge(reef: &Catalogue, extra: Vec<Package>) -> Catalogue {
    let covered: BTreeSet<String> = reef
        .packages
        .iter()
        .filter_map(|p| p.install.as_ref().and_then(Install::handler_id))
        .chain(reef.packages.iter().map(|p| p.name.clone()))
        .collect();
    let mut merged = reef.clone();
    merged
        .packages
        .extend(extra.into_iter().filter(|p| !covered.contains(&p.name)));
    if merged.featured.is_empty() {
        let mut shown: Vec<&Package> = merged
            .packages
            .iter()
            .filter(|p| p.origin == Origin::Flathub && !p.screenshots.is_empty())
            .collect();
        shown.sort_by(|a, b| {
            b.updated
                .cmp(&a.updated)
                .then_with(|| a.title.cmp(&b.title))
        });
        merged.featured = shown
            .into_iter()
            .take(FEATURED_FALLBACK)
            .map(|p| p.name.clone())
            .collect();
    }
    merged
}

/// A package with only a name, title and origin; free, sandboxed, no
/// install target yet.
pub fn blank(name: &str, title: String, origin: Origin) -> Package {
    Package {
        name: name.to_owned(),
        version: String::new(),
        title,
        summary: String::new(),
        description: String::new(),
        category: "Other".into(),
        tested_on: Vec::new(),
        device_tested: true,
        permissions: Vec::new(),
        sandboxed: true,
        licence: LicenceModel::Free,
        spdx: None,
        size: None,
        requires_cpu: Vec::new(),
        variants: Vec::new(),
        homepage: None,
        source: None,
        icon: None,
        screenshots: Vec::new(),
        publisher: String::new(),
        added: None,
        keel_tier: None,
        changelog: Vec::new(),
        services: Vec::new(),
        system_changes: Vec::new(),
        requires: Vec::new(),
        keywords: Vec::new(),
        updated: None,
        hero: None,
        details: None,
        install: None,
        origin,
    }
}

fn https(url: String) -> Option<String> {
    url.starts_with("https://").then_some(url)
}

/// F-Droid's description markup as text: paragraphs and line breaks kept,
/// every other tag dropped.
fn plain_text(html: &str) -> String {
    let mut out = String::new();
    let mut rest = html;
    while let Some(start) = rest.find('<') {
        out.push_str(&rest[..start]);
        let Some(end) = rest[start..].find('>') else {
            rest = "";
            break;
        };
        let tag = rest[start + 1..start + end]
            .trim_start_matches('/')
            .to_ascii_lowercase();
        match tag.split_whitespace().next().unwrap_or_default() {
            "br" | "br/" => out.push('\n'),
            "p" | "ul" | "ol" if !out.ends_with("\n\n") && !out.is_empty() => out.push_str("\n\n"),
            "li" if !rest[start..].starts_with("</") => {
                if !out.ends_with('\n') {
                    out.push('\n');
                }
                out.push_str("• ");
            }
            _ => {}
        }
        rest = &rest[start + end + 1..];
    }
    out.push_str(rest);
    out.replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .trim()
        .to_owned()
}

/// `YYYY-MM-DD` of a Unix time (seconds, or F-Droid's milliseconds).
fn day(time: u64) -> Option<String> {
    let secs = if time > 100_000_000_000 {
        time / 1000
    } else {
        time
    };
    if secs == 0 {
        return None;
    }
    // Howard Hinnant's civil_from_days.
    let z = i64::try_from(secs / 86_400).ok()? + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    Some(format!("{y:04}-{m:02}-{d:02}"))
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn flathub_rows_install_from_flathub() {
        let json = br#"{"icons": "/cat/icons/128x128", "apps": [{"id": "org.example.Notes",
            "name": "Notes", "summary": "Write", "categories": ["Office"], "developer": "Ex",
            "license": "MIT", "homepage": "http://insecure", "icon": "org.example.Notes.png",
            "screenshots": ["https://s.png", "http://x.png"], "version": "2.1",
            "released": 1700000000}]}"#;
        let p = &flathub(json)[0];
        assert_eq!(p.name, "org.example.Notes");
        assert_eq!(p.origin, Origin::Flathub);
        assert_eq!(
            p.icon.as_deref(),
            Some("/cat/icons/128x128/org.example.Notes.png")
        );
        assert_eq!(p.screenshots, ["https://s.png"]);
        assert_eq!(p.homepage, None);
        assert_eq!(p.updated.as_deref(), Some("2023-11-14"));
        assert_eq!(
            p.install.as_ref().and_then(Install::handler_id).as_deref(),
            Some("org.example.Notes")
        );
    }

    #[test]
    fn fdroid_rows_install_through_deckard() {
        let json = br#"{"index": "x", "apps": [{"app_id": "android:org.example.todo",
            "pkg": "org.example.todo", "name": "Todo", "description": "A <b>todo</b> list.<br>Two:<ul><li>one</li><li>two</li></ul>",
            "author": "A", "categories": ["Task"], "icon": "https://f-droid.org/i.png",
            "lastUpdated": 1788427366000, "version": {"name": "1.0", "code": 1}},
            {"app_id": "org.bad", "pkg": "org.bad", "name": "Bad"}]}"#;
        let rows = fdroid(json);
        assert_eq!(
            rows.len(),
            1,
            "an app id that is not android:<pkg> is dropped"
        );
        let p = &rows[0];
        assert_eq!(p.description, "A todo list.\nTwo:\n\n• one\n• two");
        assert_eq!(p.version, "1.0");
        assert_eq!(p.updated.as_deref(), Some("2026-09-03"));
        assert_eq!(
            p.install.as_ref().and_then(Install::handler_id).as_deref(),
            Some("android:org.example.todo")
        );
    }

    #[test]
    fn categories_fold_into_the_stores() {
        let cats = |names: &[&str]| {
            store_category(&names.iter().map(|n| (*n).to_owned()).collect::<Vec<_>>())
        };
        assert_eq!(cats(&["System", "Puzzle Game"]), "Games");
        assert_eq!(cats(&["Internet", "Messaging"]), "Communication");
        assert_eq!(cats(&["Utility", "AudioVideo"]), "Music & Video");
        assert_eq!(cats(&["GNOME", "GTK"]), "Other");
    }

    #[test]
    fn reef_rows_win_over_the_handlers() {
        let reef = Catalogue::parse(
            br#"{"schema": 1, "release": "marathon", "arch": "aarch64", "packages": [
                {"name": "notes", "version": "2", "title": "Notes", "summary": "s",
                 "tested_on": [], "licence": {"model": "free"},
                 "install": {"kind": "flatpak", "remote": "flathub", "ref": "app/org.example.Notes/aarch64/stable"}}]}"#,
            "aarch64",
        )
        .unwrap();
        let extra = flathub(
            br#"{"apps": [{"id": "org.example.Notes", "name": "Notes"},
            {"id": "org.example.Other", "name": "Other"}]}"#,
        );
        let merged = merge(&reef, extra);
        let names: Vec<&str> = merged.packages.iter().map(|p| p.name.as_str()).collect();
        assert_eq!(names, ["notes", "org.example.Other"]);
        assert_eq!(
            merged.featured,
            Vec::<String>::new(),
            "no screenshots, no banner"
        );
        let shots = flathub(
            br#"{"apps": [{"id": "org.example.Old", "name": "Old",
            "screenshots": ["https://dl.flathub.org/o.png"], "released": 1},
            {"id": "org.example.New", "name": "New",
            "screenshots": ["https://dl.flathub.org/n.png"], "released": 1700000000}]}"#,
        );
        assert_eq!(
            merge(&reef, shots).featured,
            ["org.example.New", "org.example.Old"]
        );
    }

    #[test]
    fn installs_marathon_cannot_take_are_dropped() {
        let other_remote = Install::Flatpak {
            remote: "elsewhere".into(),
            reference: "org.example.A".into(),
        };
        let other_store = Install::Android {
            package: "org.example.a".into(),
            store: "play".into(),
        };
        assert_eq!(other_remote.handler_id(), None);
        assert_eq!(other_store.handler_id(), None);
    }
}
