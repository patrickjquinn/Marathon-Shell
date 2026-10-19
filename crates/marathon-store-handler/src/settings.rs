//! The Store's settings, kept by the handler alone in
//! `$XDG_CONFIG_HOME/marathon-store/settings.json` and changed through
//! `marathon-store://settings/set?<key>=<0|1>`. The Store and Settings read
//! the copy the handler writes beside its other state. Whether the Store
//! shows only apps made for phones is the shell's "apps/filterMobileFriendly",
//! which the home grid follows too.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::json;

use crate::state::{now, StateDir};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
#[allow(clippy::struct_excessive_bools, reason = "one switch per setting")]
pub struct Settings {
    pub flathub: bool,
    pub fdroid: bool,
    /// F-Droid apps with anti-features are listed, flagged; off leaves them out.
    pub anti_features: bool,
    pub auto_update: bool,
    pub update_on_metered: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            flathub: true,
            fdroid: true,
            anti_features: true,
            auto_update: true,
            update_on_metered: false,
        }
    }
}

pub const KEYS: [&str; 5] = [
    "flathub",
    "fdroid",
    "antiFeatures",
    "autoUpdate",
    "updateOnMetered",
];

/// `key=0|1` pairs, every key known.
pub fn parse_changes(query: &str) -> Option<Vec<(String, bool)>> {
    let changes: Option<Vec<(String, bool)>> = query
        .split('&')
        .filter(|pair| !pair.is_empty())
        .map(|pair| {
            let (key, value) = pair.split_once('=')?;
            let value = match value {
                "1" | "true" => true,
                "0" | "false" => false,
                _ => return None,
            };
            KEYS.contains(&key).then(|| (key.to_owned(), value))
        })
        .collect();
    changes.filter(|c| !c.is_empty())
}

fn config_dir() -> PathBuf {
    std::env::var_os("XDG_CONFIG_HOME").map_or_else(
        || Path::new(&std::env::var_os("HOME").unwrap_or_default()).join(".config"),
        PathBuf::from,
    )
}

fn path() -> PathBuf {
    config_dir().join("marathon-store/settings.json")
}

pub fn load() -> Settings {
    fs::read(path())
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default()
}

impl Settings {
    fn apply(&mut self, key: &str, value: bool) {
        match key {
            "flathub" => self.flathub = value,
            "fdroid" => self.fdroid = value,
            "antiFeatures" => self.anti_features = value,
            "autoUpdate" => self.auto_update = value,
            "updateOnMetered" => self.update_on_metered = value,
            _ => {}
        }
    }
}

/// The Store's and Settings' copy.
pub fn publish(state: &StateDir, settings: Settings) -> io::Result<()> {
    let mut record = serde_json::to_value(settings).map_err(io::Error::other)?;
    record["ts"] = json!(now());
    state.write_json("settings.json", &record)
}

pub fn set(state: &StateDir, changes: &[(String, bool)]) -> io::Result<()> {
    let mut settings = load();
    for (key, value) in changes {
        settings.apply(key, *value);
    }
    let bytes = serde_json::to_vec_pretty(&settings).map_err(io::Error::other)?;
    crate::fdroid::write_atomic(&path(), &bytes)?;
    publish(state, settings)
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn changes_must_be_known_booleans() {
        assert_eq!(
            parse_changes("fdroid=0&autoUpdate=1").unwrap(),
            [
                ("fdroid".to_owned(), false),
                ("autoUpdate".to_owned(), true)
            ]
        );
        assert!(parse_changes("").is_none());
        assert!(parse_changes("phoneOnly=1").is_none());
        assert!(parse_changes("fdroid=yes").is_none());
        assert!(parse_changes("fdroid").is_none());
    }

    #[test]
    fn defaults() {
        let s = Settings::default();
        assert!(s.flathub && s.fdroid && s.anti_features && s.auto_update);
        assert!(!s.update_on_metered);
    }

    #[test]
    fn defaults_fill_missing_keys() {
        let s: Settings = serde_json::from_str(r#"{"fdroid": false, "extra": 1}"#).unwrap();
        assert_eq!(
            s,
            Settings {
                fdroid: false,
                ..Settings::default()
            }
        );
        let mut s = Settings::default();
        s.apply("updateOnMetered", true);
        s.apply("antiFeatures", false);
        assert!(s.update_on_metered && !s.anti_features);
        let json = serde_json::to_value(s).unwrap();
        for key in KEYS {
            assert!(json.get(key).is_some(), "{key}");
        }
    }
}
