// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The store handler (`marathon-store-handler`), which installs, updates and
//! removes apps: Reef asks it through `marathon-store://` links and reads
//! the files it keeps in `$XDG_RUNTIME_DIR/marathon-store-state`.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use reef_backend::catalogue::{Install, Origin, Package};
use reef_backend::sources;
use reef_backend::store::PackageVersion;
use serde_json::Value;

/// One app's running or finished operation.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Job {
    /// `pending`, `installing`, `removing`, `cancelling`, `done`,
    /// `removed` or `failed`.
    pub state: String,
    /// -1 while unknown.
    pub percent: i32,
    pub error: String,
}

impl Job {
    pub fn running(&self) -> bool {
        matches!(
            self.state.as_str(),
            "pending" | "installing" | "removing" | "cancelling"
        )
    }
}

/// What is installed and running, from the handler's small files (read on
/// every poll; the catalogues are read by [`sources`]).
#[derive(Debug, Clone, Default)]
pub struct Status {
    pub installed: Vec<PackageVersion>,
    pub updates: Vec<PackageVersion>,
    /// By the handler's app id.
    pub jobs: BTreeMap<String, Job>,
    /// `installed.json` as listed (names and icons of installed apps).
    listing: Value,
}

impl Status {
    pub fn running(&self) -> bool {
        self.jobs.values().any(Job::running)
    }
}

pub fn state_dir() -> Option<PathBuf> {
    std::env::var_os("XDG_RUNTIME_DIR").map(|d| PathBuf::from(d).join("marathon-store-state"))
}

fn json(dir: &Path, name: &str) -> Value {
    fs::read(dir.join(name))
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or_default()
}

/// Flathub's and F-Droid's apps as the handler keeps them.
pub fn sources(dir: &Path) -> Vec<Package> {
    let mut packages = sources::flathub(&fs::read(dir.join("flathub.json")).unwrap_or_default());
    packages.extend(sources::fdroid(
        &fs::read(dir.join("fdroid.json")).unwrap_or_default(),
    ));
    packages
}

/// When the catalogue files last changed: [`sources`] is read again when
/// this does.
pub fn sources_stamp(dir: &Path) -> u64 {
    ["flathub.json", "fdroid.json"]
        .iter()
        .filter_map(|f| fs::metadata(dir.join(f)).and_then(|m| m.modified()).ok())
        .filter_map(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .sum()
}

/// `sources` and the installed apps no catalogue lists, to update or remove.
pub fn with_installed(sources: &[Package], status: &Status) -> Vec<Package> {
    let mut all = sources.to_vec();
    for a in status.listing["installed"].as_array().into_iter().flatten() {
        let Some(id) = a["app_id"].as_str() else {
            continue;
        };
        if !sources.iter().any(|p| p.name == id) {
            all.push(installed_only(id, a));
        }
    }
    all
}

/// Reads the handler's status; anything missing reads as empty.
pub fn status(dir: &Path) -> Status {
    let listed = json(dir, "installed.json");
    let installed: Vec<PackageVersion> = listed["installed"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|a| {
            Some(PackageVersion {
                name: a["app_id"].as_str()?.to_owned(),
                version: a["version"].as_str().unwrap_or_default().to_owned(),
            })
        })
        .collect();
    let updates = json(dir, "updates.json")["updates"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|u| {
            Some(PackageVersion {
                name: u["app_id"].as_str()?.to_owned(),
                version: String::new(),
            })
        })
        .collect();
    let jobs = fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name().into_string().ok()?;
            let id = name
                .strip_prefix("install-progress-")?
                .strip_suffix(".json")?
                .to_owned();
            let record = json(dir, &name);
            let job = Job {
                state: record["state"].as_str()?.to_owned(),
                percent: record["percent"]
                    .as_i64()
                    .and_then(|p| i32::try_from(p).ok())
                    .unwrap_or(-1),
                error: record["error"].as_str().unwrap_or_default().to_owned(),
            };
            Some((id, job))
        })
        .collect();
    Status {
        installed,
        updates,
        jobs,
        listing: listed,
    }
}

fn installed_only(id: &str, listed: &Value) -> Package {
    let (origin, install) = match id.strip_prefix("android:") {
        Some(package) => (
            Origin::Fdroid,
            Install::Android {
                package: package.to_owned(),
                store: "fdroid".into(),
            },
        ),
        None => (
            Origin::Flathub,
            Install::Flatpak {
                remote: "flathub".into(),
                reference: id.to_owned(),
            },
        ),
    };
    let title = listed["name"]
        .as_str()
        .filter(|n| !n.is_empty())
        .unwrap_or(id);
    let mut p = sources::blank(id, title.to_owned(), origin);
    listed["version"]
        .as_str()
        .unwrap_or_default()
        .clone_into(&mut p.version);
    p.icon = listed["icon"]
        .as_str()
        .and_then(|i| i.strip_prefix("file://"))
        .map(str::to_owned);
    p.install = Some(install);
    p
}

/// Asks the handler for `verb` on the app it knows as `id`
/// (`marathon-store://<verb>/<id>?name=<title>`).
pub fn request(verb: &str, id: &str, title: &str) -> std::io::Result<()> {
    let mut url = format!("marathon-store://{verb}/{id}");
    if !title.is_empty() && verb != "uninstall" {
        url.push_str("?name=");
        url.push_str(&encode(title));
    }
    // Run directly, as the shell does: xdg-open has no handler for the
    // scheme on Marathon. Reaped off the GUI thread.
    let mut child = Command::new("/usr/bin/marathon-store-handler")
        .arg(url)
        .spawn()?;
    std::thread::spawn(move || child.wait());
    Ok(())
}

fn encode(text: &str) -> String {
    text.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                char::from(b).to_string()
            }
            _ => format!("%{b:02X}"),
        })
        .collect()
}

/// The `open` link's id: Deckard's app id for an Android app.
pub fn open_id(handler_id: &str) -> String {
    handler_id.strip_prefix("android:").map_or_else(
        || handler_id.to_owned(),
        |package| format!("deckard.{package}"),
    )
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn reads_installed_updates_and_jobs() {
        let dir =
            std::env::temp_dir().join(format!("shipwright-reef-handler-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let d = dir.as_path();
        fs::write(
            d.join("installed.json"),
            r#"{"installed":[{"app_id":"org.example.Notes","name":"Notes","version":"2",
                "icon":"file:///icons/notes.svg"}]}"#,
        )
        .unwrap();
        fs::write(
            d.join("updates.json"),
            r#"{"updates":[{"app_id":"org.example.Notes"}]}"#,
        )
        .unwrap();
        fs::write(
            d.join("install-progress-android:org.example.todo.json"),
            r#"{"state":"installing","percent":40}"#,
        )
        .unwrap();
        let status = status(d);
        assert_eq!(status.installed[0].name, "org.example.Notes");
        assert_eq!(status.updates[0].name, "org.example.Notes");
        let job = &status.jobs["android:org.example.todo"];
        assert!(job.running() && job.percent == 40 && status.running());
        let all = with_installed(&sources(d), &status);
        let notes = &all[0];
        assert_eq!(notes.title, "Notes");
        assert_eq!(notes.icon.as_deref(), Some("/icons/notes.svg"));
        assert_eq!(notes.origin, Origin::Flathub);
        fs::remove_dir_all(d).unwrap();
    }

    #[test]
    fn links_name_the_app() {
        assert_eq!(encode("Notes & more"), "Notes%20%26%20more");
        assert_eq!(
            open_id("android:org.example.todo"),
            "deckard.org.example.todo"
        );
        assert_eq!(open_id("org.example.Notes"), "org.example.Notes");
    }
}
