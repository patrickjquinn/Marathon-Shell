// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Global browser settings, stored as one JSON value in the profile.
//! Unknown keys are ignored and missing ones take their defaults, so
//! settings survive upgrades in both directions.

use serde::{Deserialize, Serialize};

use crate::db::Profile;
use crate::Result;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
#[allow(
    clippy::struct_excessive_bools,
    reason = "independent switches on the settings pages"
)]
pub struct Settings {
    /// Ask the search engine for suggestions while typing.
    pub search_suggestions: bool,
    /// Block ads and trackers.
    pub blocking: bool,
    /// Answer cookie banners with "reject all".
    pub cookie_banners: bool,
    /// Try HTTPS first.
    pub https_first: bool,
    /// Send Global Privacy Control (`Sec-GPC: 1`).
    pub global_privacy_control: bool,
    pub javascript: bool,
    /// Load desktop sites by default.
    pub desktop_mode: bool,
    /// Page zoom by default (1.0 = 100%).
    pub default_zoom: f64,
    /// Play media without a tap.
    pub autoplay: bool,
    /// Restore tabs at start: "always", "crash" (only after a crash) or
    /// "never".
    pub restore: String,
    /// Close the private tabs when the app goes to the background for
    /// more than 10 minutes.
    pub private_auto_close: bool,
    /// Clear all browsing data when the app quits.
    pub clear_on_exit: bool,
    /// Forget visits older than this many days (0: keep).
    pub history_days: i64,
    /// Hide the address bar while scrolling down.
    pub toolbar_autohide: bool,
    /// What websites are told the user prefers (`prefers-color-scheme`):
    /// "ambience" (dark on a dark ambience), "light" or "dark".
    pub color_scheme: String,
    pub reader_font_px: u32,
    /// Offer to fill and save logins with Shoal Keys.
    pub keys_autofill: bool,
    /// Let Pilot use the browser (Keel Actions).
    pub pilot_actions: bool,
    /// Downloads directory (empty: ~/Downloads).
    pub download_dir: String,
    /// Ask where to save each download.
    pub ask_download_dir: bool,
    /// Underline misspelt words in text fields.
    pub spell_check: bool,
    /// Spell-checking dictionaries such as `en_GB` (empty: the phone's
    /// language, as the engine picks it).
    pub spell_languages: Vec<String>,
    pub first_run_done: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            search_suggestions: true,
            blocking: true,
            cookie_banners: true,
            https_first: true,
            global_privacy_control: true,
            javascript: true,
            desktop_mode: false,
            default_zoom: 1.0,
            autoplay: false,
            restore: "always".into(),
            private_auto_close: false,
            clear_on_exit: false,
            history_days: 180,
            toolbar_autohide: true,
            color_scheme: "ambience".into(),
            reader_font_px: 18,
            keys_autofill: true,
            pilot_actions: true,
            download_dir: String::new(),
            ask_download_dir: false,
            spell_check: true,
            spell_languages: Vec::new(),
            first_run_done: false,
        }
    }
}

impl Settings {
    /// Brings out-of-range values back into range.
    pub fn normalise(&mut self) {
        self.default_zoom = if self.default_zoom.is_finite() {
            self.default_zoom.clamp(0.3, 3.0)
        } else {
            1.0
        };
        self.reader_font_px = self.reader_font_px.clamp(12, 40);
        // Dictionary names only (`en_GB`, `pt_BR`), each once.
        let mut seen = Vec::new();
        self.spell_languages.retain(|l| {
            let ok = !l.is_empty()
                && l.len() <= 16
                && l.chars()
                    .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
                && !seen.contains(l);
            if ok {
                seen.push(l.clone());
            }
            ok
        });
        self.history_days = self.history_days.clamp(0, 3650);
        if !matches!(self.restore.as_str(), "always" | "crash" | "never") {
            self.restore = "always".into();
        }
        if !matches!(self.color_scheme.as_str(), "ambience" | "light" | "dark") {
            self.color_scheme = "ambience".into();
        }
    }

    /// Applies a JSON object of changed keys on top of these settings.
    pub fn merged(&self, patch: &serde_json::Value) -> Result<Self> {
        let mut v = serde_json::to_value(self)?;
        if let (Some(obj), Some(p)) = (v.as_object_mut(), patch.as_object()) {
            for (k, val) in p {
                if obj.contains_key(k) {
                    obj.insert(k.clone(), val.clone());
                }
            }
        }
        let mut s: Self = serde_json::from_value(v)?;
        s.normalise();
        Ok(s)
    }
}

impl Profile {
    pub fn settings(&self) -> Result<Settings> {
        let mut s = self
            .pref("settings")?
            .and_then(|t| serde_json::from_str::<Settings>(&t).ok())
            .unwrap_or_default();
        s.normalise();
        Ok(s)
    }

    pub fn save_settings(&self, s: &Settings) -> Result<()> {
        self.set_pref("settings", &serde_json::to_string(s)?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_round_trip_and_merge() {
        let p = Profile::in_memory().unwrap();
        let s = p.settings().unwrap();
        assert!(s.blocking && s.https_first && s.cookie_banners);
        assert!(!s.first_run_done);
        let patched = s
            .merged(&serde_json::json!({"blocking": false, "default_zoom": 9.0, "restore": "weird", "unknown": 1}))
            .unwrap();
        assert!(!patched.blocking);
        assert!((patched.default_zoom - 3.0).abs() < f64::EPSILON);
        assert_eq!(patched.restore, "always");
        let spelling = s
            .merged(
                &serde_json::json!({"spell_languages": ["en_GB", "en_GB", "", "de_DE", "x;rm"]}),
            )
            .unwrap();
        assert_eq!(spelling.spell_languages, ["en_GB", "de_DE"]);
        p.save_settings(&patched).unwrap();
        assert_eq!(p.settings().unwrap(), patched);
        // Old or partial JSON keeps defaults for what is missing.
        p.set_pref("settings", "{\"javascript\": false}").unwrap();
        let s = p.settings().unwrap();
        assert!(!s.javascript && s.blocking);
        p.set_pref("settings", "not json").unwrap();
        assert_eq!(p.settings().unwrap(), Settings::default());
    }
}
