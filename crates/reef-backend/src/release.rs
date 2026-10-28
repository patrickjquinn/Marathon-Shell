// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

//! Which Sailfish OS release is installed.
//!
//! docs/plan.md ("Repository mechanics"): Sailfish's update checker can move
//! the `ssu` release setting (`ssu re`) ahead of the installed release, and
//! third-party repositories that follow `ssu re` then offer packages built for
//! a release the phone is not running. Reef therefore reads the release the
//! phone actually runs, from the release file, and never asks ssu.

use std::fmt;
use std::path::Path;

/// An installed Sailfish OS release, such as `5.2.0.17`.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct SailfishRelease {
    parts: [u32; 4],
}

impl SailfishRelease {
    /// Parses a four-part release string. Sailfish release strings always
    /// have four numeric parts (major.minor.patch.build).
    pub fn parse(s: &str) -> Option<Self> {
        let mut parts = [0u32; 4];
        let mut it = s.trim().split('.');
        for part in &mut parts {
            let p = it.next()?;
            if p.is_empty() || !p.bytes().all(|b| b.is_ascii_digit()) {
                return None;
            }
            *part = p.parse().ok()?;
        }
        if it.next().is_some() {
            return None;
        }
        Some(Self { parts })
    }

    /// `5.2.0.17`, the string the Reef repository and catalogue are pinned to.
    pub fn full(&self) -> String {
        let [a, b, c, d] = self.parts;
        format!("{a}.{b}.{c}.{d}")
    }

    /// `5.2`. Chum publishes Sailfish 5.x repositories per major.minor
    /// (`.../chum/5.2_aarch64/`), which some Reef deployments may mirror.
    pub fn major_minor(&self) -> String {
        format!("{}.{}", self.parts[0], self.parts[1])
    }
}

impl fmt::Display for SailfishRelease {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.full())
    }
}

/// Reads `VERSION_ID` from os-release-style text (`/etc/sailfish-release`
/// and `/etc/os-release` share the format). Quotes are optional.
pub fn parse_release_file(text: &str) -> Option<SailfishRelease> {
    text.lines().find_map(|line| {
        let value = line.trim().strip_prefix("VERSION_ID=")?;
        SailfishRelease::parse(value.trim_matches(|c| c == '"' || c == '\''))
    })
}

/// Finds the release in the output of the `version` command (for example
/// `Sailfish OS 5.2.0.17 (Finlayson)`): the first whitespace-separated token
/// that is a four-part release.
pub fn parse_version_output(text: &str) -> Option<SailfishRelease> {
    text.split_whitespace().find_map(|tok| {
        SailfishRelease::parse(tok.trim_matches(|c: char| !c.is_ascii_digit() && c != '.'))
    })
}

/// Files consulted, in order, relative to the filesystem root.
pub const RELEASE_FILES: [&str; 2] = ["etc/sailfish-release", "etc/os-release"];

/// Detects the installed release under `root` (`/` on a phone; a fixture
/// directory in tests). Falls back to running `version` only when neither
/// release file names one.
pub fn detect(root: &Path) -> Option<SailfishRelease> {
    RELEASE_FILES
        .iter()
        .filter_map(|f| std::fs::read_to_string(root.join(f)).ok())
        .find_map(|text| parse_release_file(&text))
        .or_else(|| {
            let out = crate::c_locale(&mut std::process::Command::new("version"))
                .output()
                .ok()?;
            parse_version_output(&String::from_utf8_lossy(&out.stdout))
        })
}

/// RPM architecture name of the running binary, as used in repository paths
/// and by ssu's `%(arch)`.
pub fn native_arch() -> &'static str {
    match std::env::consts::ARCH {
        "aarch64" => "aarch64",
        "arm" => "armv7hl",
        "x86" => "i486",
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_release_strings() {
        let r = SailfishRelease::parse("5.2.0.17").unwrap();
        assert_eq!(r.full(), "5.2.0.17");
        assert_eq!(r.major_minor(), "5.2");
        for bad in [
            "",
            "5.2",
            "5.2.0",
            "5.2.0.17.1",
            "5.2.x.17",
            "5..0.1",
            "-5.2.0.1",
        ] {
            assert_eq!(SailfishRelease::parse(bad), None, "{bad}");
        }
    }

    #[test]
    fn orders_numerically() {
        let a = SailfishRelease::parse("5.2.0.9").unwrap();
        let b = SailfishRelease::parse("5.2.0.17").unwrap();
        assert!(a < b);
    }

    #[test]
    fn reads_sailfish_release_file() {
        // Shape of /etc/sailfish-release as documented for 4.x; Phase 0
        // re-records it on a 5.2 Jolla Phone.
        let text = "NAME=\"Sailfish OS\"\nID=sailfishos\nVERSION=\"5.2.0.17 (Finlayson)\"\n\
                    VERSION_ID=5.2.0.17\nPRETTY_NAME=\"Sailfish OS 5.2.0.17 (Finlayson)\"\n\
                    SAILFISH_FLAVOUR=release\n";
        assert_eq!(parse_release_file(text).unwrap().full(), "5.2.0.17");
        assert_eq!(
            parse_release_file("VERSION_ID=\"5.1.0.11\"")
                .unwrap()
                .full(),
            "5.1.0.11"
        );
        assert_eq!(parse_release_file("VERSION=5.2.0.17"), None);
    }

    #[test]
    fn reads_version_output() {
        let r = parse_version_output("Sailfish OS 5.2.0.18 (Finlayson)\n").unwrap();
        assert_eq!(r.full(), "5.2.0.18");
        assert_eq!(
            parse_version_output("Sailfish OS 5.1.0.11 (Tampella), EA").map(|r| r.full()),
            Some("5.1.0.11".into())
        );
        assert_eq!(parse_version_output("unknown"), None);
    }

    #[test]
    fn detects_from_fixture_root() {
        let dir = std::env::temp_dir().join(format!("reef-release-{}", std::process::id()));
        std::fs::create_dir_all(dir.join("etc")).unwrap();
        std::fs::write(dir.join("etc/os-release"), "VERSION_ID=5.1.0.11\n").unwrap();
        assert_eq!(detect(&dir).unwrap().full(), "5.1.0.11");
        // sailfish-release wins over os-release.
        std::fs::write(dir.join("etc/sailfish-release"), "VERSION_ID=5.2.0.17\n").unwrap();
        assert_eq!(detect(&dir).unwrap().full(), "5.2.0.17");
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
