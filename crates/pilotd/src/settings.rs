// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! User settings (spec section 10, "Consent"): per-capability cloud
//! consent and the backend choice, stored as JSON (0600) in the data
//! directory and changed only through the UI's D-Bus calls.
//!
//! First-run defaults: everything off except text Q&A, which the opt-in
//! screen explains.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
#[allow(
    clippy::struct_excessive_bools,
    reason = "one independent switch per capability, as the settings page shows them"
)]
pub struct Consent {
    /// Typed questions go to Jev and Qwen.
    pub text_qa: bool,
    /// Spoken turns' transcripts go to the cloud (the audio never does).
    pub voice_cloud: bool,
    /// Camera frames go to Qwen.
    pub vision: bool,
    /// Notifications, SMS and calendar changes are triaged through Jev.
    pub triage: bool,
    /// Audio goes to Groq Whisper for hard-to-recognise speech.
    pub cloud_asr: bool,
    /// Triage may speak (`worth_interrupting >= 0.9`).
    pub spoken_nudges: bool,
    /// The conversation is kept on the phone for 30 days, so Pilot can
    /// look back at it ("the recipe you gave me last week"). Nothing is
    /// sent because of it; on by default, like the egress log.
    pub history: bool,
}

impl Default for Consent {
    fn default() -> Self {
        Consent {
            text_qa: true,
            voice_cloud: false,
            vision: false,
            triage: false,
            cloud_asr: false,
            spoken_nudges: false,
            history: true,
        }
    }
}

impl Consent {
    pub const NAMES: &'static [&'static str] = &[
        "text_qa",
        "voice_cloud",
        "vision",
        "triage",
        "cloud_asr",
        "spoken_nudges",
        "history",
    ];

    /// Sets one capability by name; `false` for an unknown name.
    pub fn set(&mut self, name: &str, on: bool) -> bool {
        let slot = match name {
            "text_qa" => &mut self.text_qa,
            "voice_cloud" => &mut self.voice_cloud,
            "vision" => &mut self.vision,
            "triage" => &mut self.triage,
            "cloud_asr" => &mut self.cloud_asr,
            "spoken_nudges" => &mut self.spoken_nudges,
            "history" => &mut self.history,
            _ => return false,
        };
        *slot = on;
        true
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    pub consent: Consent,
    /// A key of `[backends]` in the config file: "standard" or "lighthouse".
    pub backend: String,
    /// The user saw the opt-in screen.
    pub onboarded: bool,
    /// What Pilot calls the person on its home ("Morning, Patrick"); empty
    /// for no name. Stays on the phone.
    pub name: String,
    /// The getting-started guide in the app: the skills the person has
    /// tried ("gesture", "screen", "voice", "action", "how"), and "hidden"
    /// once they put it away.
    pub guide: Vec<String>,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            consent: Consent::default(),
            backend: "standard".into(),
            onboarded: false,
            name: String::new(),
            guide: Vec::new(),
        }
    }
}

/// Settings bound to their file.
pub struct SettingsFile {
    path: Option<PathBuf>,
    pub current: Settings,
}

impl SettingsFile {
    /// Loads `path`, or defaults when it does not exist. A corrupt file is
    /// replaced by defaults (all cloud consent off but text Q&A), logged.
    pub fn load(path: Option<PathBuf>) -> SettingsFile {
        let current = path
            .as_deref()
            .and_then(|p| std::fs::read(p).ok())
            .and_then(|b| match serde_json::from_slice(&b) {
                Ok(s) => Some(s),
                Err(e) => {
                    log::warn!("settings unreadable ({e}); using defaults");
                    None
                }
            })
            .unwrap_or_default();
        // In memory (`--ask`, tests) there is no first-run screen to make
        // the choice on: the defaults stand as chosen.
        let mut current: Settings = current;
        if path.is_none() {
            current.onboarded = true;
        }
        SettingsFile { path, current }
    }

    pub fn save(&self) -> std::io::Result<()> {
        let Some(path) = &self.path else {
            return Ok(());
        };
        write_private(path, &serde_json::to_vec_pretty(&self.current)?)
    }
}

/// Writes atomically with mode 0600.
pub fn write_private(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    use std::io::Write as _;
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let tmp = path.with_extension("tmp");
    {
        let mut opts = std::fs::OpenOptions::new();
        opts.write(true).create(true).truncate(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt as _;
            opts.mode(0o600);
        }
        let mut f = opts.open(&tmp)?;
        f.write_all(bytes)?;
        f.sync_all()?;
    }
    std::fs::rename(&tmp, path)
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn defaults_and_round_trip() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("settings.json");
        let mut s = SettingsFile::load(Some(path.clone()));
        assert!(s.current.consent.text_qa);
        assert!(
            !s.current.consent.vision
                && !s.current.consent.triage
                && !s.current.consent.voice_cloud
        );
        assert!(s.current.consent.set("vision", true));
        assert!(!s.current.consent.set("telepathy", true));
        s.current.backend = "lighthouse".into();
        s.save().unwrap();
        let again = SettingsFile::load(Some(path.clone()));
        assert_eq!(again.current, s.current);
        std::fs::write(&path, "{garbage").unwrap();
        assert_eq!(SettingsFile::load(Some(path)).current, Settings::default());
    }
}
