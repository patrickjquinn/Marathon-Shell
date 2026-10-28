// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

//! The three user settings behind `refreshOnStart`, `backgroundCheckDays`
//! and `licenceServer`, kept in `$XDG_CONFIG_HOME/shipwright-reef/settings.json`.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

/// The production licence service.
pub const PRODUCTION_LICENCE_SERVER: &str = "https://licences.reefstore.app";

/// The licence server a fresh install uses: `$REEF_LICENCE_SERVER` at build
/// time when set and not empty (a staging phone build points it at the
/// staging service), else [`PRODUCTION_LICENCE_SERVER`]. Cargo rebuilds the
/// crate when the variable changes.
pub const DEFAULT_LICENCE_SERVER: &str = match option_env!("REEF_LICENCE_SERVER") {
    Some(v) if !v.is_empty() => v,
    _ => PRODUCTION_LICENCE_SERVER,
};

// A build-time override that is not an https URL fails the build.
const _: () = assert!(
    is_valid_licence_server(DEFAULT_LICENCE_SERVER),
    "REEF_LICENCE_SERVER must be an https:// URL with a host and no spaces, query or fragment"
);

/// Whether `value` can be the built-in licence server: `https://`, then a
/// host (not empty, not starting with `/`), with no whitespace, control
/// characters, `?` or `#`. A path and a trailing `/` are allowed.
pub const fn is_valid_licence_server(value: &str) -> bool {
    const SCHEME: &[u8] = b"https://";
    let b = value.as_bytes();
    if b.len() <= SCHEME.len() {
        return false;
    }
    let mut i = 0;
    while i < SCHEME.len() {
        if b[i] != SCHEME[i] {
            return false;
        }
        i += 1;
    }
    if b[i] == b'/' {
        return false;
    }
    while i < b.len() {
        if b[i] <= b' ' || b[i] == 0x7f || b[i] == b'?' || b[i] == b'#' {
            return false;
        }
        i += 1;
    }
    true
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
#[allow(
    clippy::struct_excessive_bools,
    reason = "independent settings, stored as they are"
)]
pub struct Settings {
    pub refresh_on_start: bool,
    /// 0 (never), 1 or 7. Acted on only once `background_check_asked`.
    pub background_check_days: i32,
    /// The person has answered Reef's question about checking in the
    /// background, or picked a setting. Until then the check's timer is not
    /// enabled and nothing is checked in the background (M3: Reef started
    /// a 4-hourly timer at install without asking).
    pub background_check_asked: bool,
    /// Background checks only on Wi-Fi or a wired connection, never on
    /// mobile data.
    pub background_wifi_only: bool,
    pub licence_server: String,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            refresh_on_start: true,
            background_check_days: 1,
            background_check_asked: false,
            background_wifi_only: false,
            licence_server: DEFAULT_LICENCE_SERVER.into(),
        }
    }
}

impl Settings {
    /// Whether the background check's timer should run: the person said
    /// yes, to a setting other than "Never".
    pub fn background_checks_on(&self) -> bool {
        self.background_check_asked && self.background_check_days > 0
    }
}

impl Settings {
    /// `$XDG_CONFIG_HOME/shipwright-reef/settings.json`, or under
    /// `~/.config`.
    pub fn default_path() -> Option<PathBuf> {
        let base = std::env::var_os("XDG_CONFIG_HOME")
            .filter(|v| !v.is_empty())
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|h| Path::new(&h).join(".config")))?;
        Some(base.join("shipwright-reef/settings.json"))
    }

    /// Reads settings; a missing or unreadable file gives the defaults.
    pub fn load(path: &Path) -> Self {
        std::fs::read(path)
            .ok()
            .and_then(|b| serde_json::from_slice::<Settings>(&b).ok())
            .map(Settings::normalised)
            .unwrap_or_default()
    }

    /// Clamps values the UI cannot produce back to something it shows.
    #[must_use]
    pub fn normalised(mut self) -> Self {
        self.background_check_days = normalise_days(self.background_check_days);
        self
    }

    pub fn save(&self, path: &Path) -> std::io::Result<()> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let tmp = path.with_extension("json.tmp");
        let json = serde_json::to_vec_pretty(self).map_err(std::io::Error::other)?;
        std::fs::write(&tmp, json)?;
        std::fs::rename(tmp, path)
    }
}

/// 0, 1 or 7; anything else becomes the nearest of those.
pub fn normalise_days(days: i32) -> i32 {
    match days {
        i32::MIN..=0 => 0,
        1..=3 => 1,
        _ => 7,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_and_defaults() {
        let dir =
            std::env::temp_dir().join(format!("shipwright-reef-settings-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let path = dir.join("sub/settings.json");
        assert_eq!(Settings::load(&path), Settings::default());
        let s = Settings {
            refresh_on_start: false,
            background_check_days: 7,
            background_check_asked: true,
            background_wifi_only: true,
            licence_server: "https://l.example.invalid".into(),
        };
        s.save(&path).unwrap();
        assert_eq!(Settings::load(&path), s);
        assert!(s.background_checks_on());
        // Unknown and missing keys: defaults fill in.
        std::fs::write(&path, br#"{"refresh_on_start": false, "extra": 1}"#).unwrap();
        let loaded = Settings::load(&path);
        assert!(!loaded.refresh_on_start);
        assert_eq!(loaded.licence_server, DEFAULT_LICENCE_SERVER);
        // A Reef 27 settings file: the person has not been asked yet, so
        // nothing runs in the background, whatever it said.
        std::fs::write(&path, br#"{"background_check_days": 1}"#).unwrap();
        let old = Settings::load(&path);
        assert!(!old.background_check_asked && !old.background_checks_on());
        assert!(!Settings::default().background_checks_on());
        let never = Settings {
            background_check_days: 0,
            ..s
        };
        assert!(!never.background_checks_on());
        std::fs::write(&path, b"not json").unwrap();
        assert_eq!(Settings::load(&path), Settings::default());
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn licence_server_validation() {
        assert!(is_valid_licence_server(PRODUCTION_LICENCE_SERVER));
        assert!(is_valid_licence_server(DEFAULT_LICENCE_SERVER));
        assert!(is_valid_licence_server(
            "https://licences-staging.reefstore.app"
        ));
        assert!(is_valid_licence_server("https://l.example.invalid:8443/"));
        assert!(is_valid_licence_server("https://192.168.1.20/licences"));
        for bad in [
            "",
            "https://",
            "https:///path",
            "http://licences.reefstore.app",
            "HTTPS://licences.reefstore.app",
            "licences.reefstore.app",
            " https://licences.reefstore.app",
            "https://licences.reefstore.app ",
            "https://licences reefstore.app",
            "https://licences.reefstore.app\n",
            "https://licences.reefstore.app/?x=1",
            "https://licences.reefstore.app/#x",
        ] {
            assert!(!is_valid_licence_server(bad), "{bad:?}");
        }
    }

    #[test]
    fn default_licence_server_follows_the_build() {
        match option_env!("REEF_LICENCE_SERVER") {
            Some(v) if !v.is_empty() => assert_eq!(DEFAULT_LICENCE_SERVER, v),
            _ => assert_eq!(DEFAULT_LICENCE_SERVER, "https://licences.reefstore.app"),
        }
    }

    #[test]
    fn days_are_normalised() {
        assert_eq!(normalise_days(-3), 0);
        assert_eq!(normalise_days(0), 0);
        assert_eq!(normalise_days(1), 1);
        assert_eq!(normalise_days(2), 1);
        assert_eq!(normalise_days(7), 7);
        assert_eq!(normalise_days(30), 7);
    }
}
