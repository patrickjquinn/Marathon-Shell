// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! The app's `.desktop` file: its app ID (`[X-Sailjail]`
//! `OrganizationName.ApplicationName`) and executable.

use std::collections::BTreeMap;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Desktop {
    /// The file name, e.g. `shipwright-shoal-keys.desktop`.
    pub file_name: String,
    /// Section -> key -> value.
    pub sections: BTreeMap<String, BTreeMap<String, String>>,
}

impl Desktop {
    pub fn parse(file_name: &str, text: &str) -> Self {
        let mut sections: BTreeMap<String, BTreeMap<String, String>> = BTreeMap::new();
        let mut current = String::new();
        for line in text.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            if let Some(name) = line.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
                name.clone_into(&mut current);
                continue;
            }
            if let Some((k, v)) = line.split_once('=') {
                sections
                    .entry(current.clone())
                    .or_default()
                    .insert(k.trim().to_owned(), v.trim().to_owned());
            }
        }
        Self {
            file_name: file_name.to_owned(),
            sections,
        }
    }

    pub fn get(&self, section: &str, key: &str) -> Option<&str> {
        self.sections.get(section)?.get(key).map(String::as_str)
    }

    /// `OrganizationName.ApplicationName`.
    pub fn app_id(&self) -> Option<String> {
        Some(format!(
            "{}.{}",
            self.get("X-Sailjail", "OrganizationName")?,
            self.get("X-Sailjail", "ApplicationName")?
        ))
    }

    /// The executable: the first word of `Exec`, past any `keel-shell --`.
    pub fn executable(&self) -> Option<String> {
        let exec = self.get("Desktop Entry", "Exec")?;
        let words: Vec<&str> = exec.split_whitespace().collect();
        let start = words.iter().position(|w| *w == "--").map_or(0, |i| i + 1);
        words.get(start).map(|w| (*w).to_owned())
    }
}
