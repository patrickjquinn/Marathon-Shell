// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The user settings behind `refreshOnStart` and `licenceServer`, kept in
//! `$XDG_CONFIG_HOME/shipwright-reef/settings.json`.

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
pub struct Settings {
    pub refresh_on_start: bool,
    pub licence_server: String,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            refresh_on_start: true,
            licence_server: DEFAULT_LICENCE_SERVER.into(),
        }
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
            .unwrap_or_default()
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
            licence_server: "https://l.example.invalid".into(),
        };
        s.save(&path).unwrap();
        assert_eq!(Settings::load(&path), s);
        // Unknown and missing keys: defaults fill in.
        std::fs::write(&path, br#"{"refresh_on_start": false, "extra": 1}"#).unwrap();
        let loaded = Settings::load(&path);
        assert!(!loaded.refresh_on_start);
        assert_eq!(loaded.licence_server, DEFAULT_LICENCE_SERVER);
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
}
