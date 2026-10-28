// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

//! Registering the Reef repository with ssu, pinned to the installed release.
//!
//! This produces the exact commands rather than running them, so the logic
//! is testable and the same commands can be shown to the user, logged, or
//! run by a privileged helper if Phase 0 probe 7 says the client needs one.
//! The installer RPM (reef/installer) runs the same sequence in shell; keep
//! the two in step.
//!
//! URL shape follows Chum's own registration (sailfishos-chum-gui-installer's
//! `%post`, sailfishos-chum-gui's `src/ssu.cpp`): the architecture is left as
//! ssu's `%(arch)` variable, which ssu expands per device. The release is
//! NOT left as `%(release)` / `%(releaseMajorMinor)`: those follow `ssu re`,
//! which can run ahead of the installed release. Like the Chum GUI does when
//! the user picks a version, we substitute a literal release string.

use crate::release::SailfishRelease;

/// Repository alias, shared with the installer and `ssu lr` output.
pub const DEFAULT_ALIAS: &str = "shipwright-reef";

/// The production repository, served by the reef-web Worker on the site's
/// own host. `{release}` and `{arch}` are substituted; see
/// [`RepoConfig::repo_url`].
pub const DEFAULT_URL_TEMPLATE: &str = "https://reefstore.app/sailfishos/{release}/{arch}/";

/// ssu's architecture variable, as Chum uses it.
pub const SSU_ARCH_VARIABLE: &str = "%(arch)";

/// How much of the release string goes into the repository path.
///
/// The plan pins Reef to the full installed release (`5.2.0.17`). Chum, by
/// contrast, publishes Sailfish 5.x per major.minor (`5.2_aarch64`; the
/// full-string paths 404), so a Reef mirror of Chum's Qt6 packages, or a
/// decision to publish per minor line, uses [`Self::MajorMinor`]. The client
/// takes it from the installed repo.conf ([`RepoConfig::from_repo_conf`]),
/// so it always matches what the installer registered.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReleaseGranularity {
    Full,
    MajorMinor,
}

impl ReleaseGranularity {
    pub fn path_component(self, release: &SailfishRelease) -> String {
        match self {
            ReleaseGranularity::Full => release.full(),
            ReleaseGranularity::MajorMinor => release.major_minor(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RepoConfig {
    pub alias: String,
    pub url_template: String,
    pub granularity: ReleaseGranularity,
    /// Local path of the Reef RPM signing key (shipped in the installer and
    /// client packages), imported with `rpm --import`.
    pub key_path: String,
}

impl Default for RepoConfig {
    fn default() -> Self {
        Self {
            alias: DEFAULT_ALIAS.into(),
            url_template: DEFAULT_URL_TEMPLATE.into(),
            granularity: ReleaseGranularity::Full,
            key_path: "/usr/share/shipwright-reef/RPM-GPG-KEY-shipwright-reef".into(),
        }
    }
}

/// One command to run, as argv. Nothing here goes through a shell.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Command {
    pub program: &'static str,
    pub args: Vec<String>,
}

impl Command {
    fn new(program: &'static str, args: &[&str]) -> Self {
        Self {
            program,
            args: args.iter().map(ToString::to_string).collect(),
        }
    }

    /// The command as a shell line, quoted so `%(arch)` survives, for logs
    /// and for showing the user.
    pub fn to_shell(&self) -> String {
        std::iter::once(self.program.to_string())
            .chain(self.args.iter().map(|a| shell_quote(a)))
            .collect::<Vec<_>>()
            .join(" ")
    }
}

fn shell_quote(s: &str) -> String {
    let safe = !s.is_empty()
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_./:=@".contains(&b));
    if safe {
        s.to_string()
    } else {
        format!("'{}'", s.replace('\'', r"'\''"))
    }
}

/// A repository as `ssu lr` lists it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SsuRepo {
    pub alias: String,
    pub url: String,
    pub enabled: bool,
}

/// Parses `ssu lr`, which must run with `LC_ALL=C` (`jobs::ssu_repos`, the
/// spec's `%post`): the section headers are matched in English. Lines look like ` - <alias> ... <url>` under section
/// headers starting `Enabled repositories` or `Disabled repositories` (the
/// Chum GUI installer parses the same shape with `sed 's/^ - / /;s/ ... / /'`).
pub fn parse_ssu_lr(text: &str) -> Vec<SsuRepo> {
    let mut enabled = true;
    let mut repos = Vec::new();
    for line in text.lines() {
        if line.starts_with("Enabled repositories") {
            enabled = true;
        } else if line.starts_with("Disabled repositories") {
            enabled = false;
        } else if let Some(rest) = line.trim_start().strip_prefix("- ") {
            if let Some((alias, url)) = rest.split_once(" ... ") {
                repos.push(SsuRepo {
                    alias: alias.trim().to_string(),
                    url: url.trim().to_string(),
                    enabled,
                });
            }
        }
    }
    repos
}

/// Where the Reef repository stands relative to the installed release.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PinState {
    /// Registered, enabled, and pointing at the installed release.
    Pinned,
    /// Not registered at all.
    Missing,
    /// Registered but disabled by the user or an OS upgrade.
    Disabled,
    /// Registered for another release (an OS update happened) or another URL.
    Drifted { registered: String },
}

impl RepoConfig {
    /// The URL registered with ssu: literal release, `%(arch)` for ssu.
    pub fn repo_url(&self, release: &SailfishRelease) -> String {
        self.url_template
            .replace("{release}", &self.granularity.path_component(release))
            .replace("{arch}", SSU_ARCH_VARIABLE)
    }

    /// The same URL with the architecture expanded, which is what the
    /// client fetches `catalogue.json` from.
    pub fn resolved_url(&self, release: &SailfishRelease, arch: &str) -> String {
        self.repo_url(release).replace(SSU_ARCH_VARIABLE, arch)
    }

    pub fn catalogue_url(&self, release: &SailfishRelease, arch: &str) -> String {
        format!("{}catalogue.json", self.resolved_url(release, arch))
    }

    /// Compares `ssu lr` output with what should be registered. ssu may show
    /// the URL with `%(arch)` expanded or not, so both forms match.
    pub fn pin_state(&self, repos: &[SsuRepo], release: &SailfishRelease, arch: &str) -> PinState {
        let Some(repo) = repos.iter().find(|r| r.alias == self.alias) else {
            return PinState::Missing;
        };
        let expected = [self.repo_url(release), self.resolved_url(release, arch)];
        if !expected.contains(&repo.url) {
            return PinState::Drifted {
                registered: repo.url.clone(),
            };
        }
        if repo.enabled {
            PinState::Pinned
        } else {
            PinState::Disabled
        }
    }

    /// First-time registration, in the installer's order: add the
    /// repository, regenerate zypp configuration, trust the signing key,
    /// then refresh just this repository through `PackageKit`.
    pub fn register_commands(&self, release: &SailfishRelease) -> Vec<Command> {
        vec![
            Command::new("ssu", &["ar", &self.alias, &self.repo_url(release)]),
            Command::new("ssu", &["ur"]),
            Command::new("rpm", &["--import", &self.key_path]),
            self.refresh_command(),
        ]
    }

    /// `pkcon repo-set-data <alias> refresh-now true`: refreshes one
    /// repository, as the Chum GUI installer does, instead of `pkcon refresh`
    /// which refreshes every repository on the phone.
    pub fn refresh_command(&self) -> Command {
        Command::new(
            "pkcon",
            &["-p", "repo-set-data", &self.alias, "refresh-now", "true"],
        )
    }

    /// What to run to bring the repository to [`PinState::Pinned`].
    pub fn repair_commands(&self, state: &PinState, release: &SailfishRelease) -> Vec<Command> {
        match state {
            PinState::Pinned => Vec::new(),
            PinState::Missing => self.register_commands(release),
            PinState::Disabled => vec![
                Command::new("ssu", &["er", &self.alias]),
                Command::new("ssu", &["ur"]),
                self.refresh_command(),
            ],
            // Remove then add, as the Chum GUI does, rather than relying on
            // `ssu ar` overwriting an existing alias.
            PinState::Drifted { .. } => vec![
                Command::new("ssu", &["rr", &self.alias]),
                Command::new("ssu", &["ar", &self.alias, &self.repo_url(release)]),
                Command::new("ssu", &["ur"]),
                self.refresh_command(),
            ],
        }
    }
}

/// Where the client package installs the repository configuration it shares
/// with the installer (reef/installer/repo.conf; reef/rpm's spec).
pub const CLIENT_REPO_CONF: &str = "/usr/share/shipwright-reef/repo.conf";

impl RepoConfig {
    /// Reads the installed `repo.conf` (POSIX sh assignments, as the
    /// installer's scripts source it): `REEF_ALIAS`, `REEF_URL_TEMPLATE`,
    /// `REEF_RELEASE_GRANULARITY` and `REEF_KEY_FILE`. Absent keys keep the
    /// defaults, so the client and the installer always agree on the
    /// repository, including a switch to `major-minor`.
    pub fn from_repo_conf(text: &str) -> Result<Self, String> {
        let mut cfg = Self::default();
        for (n, line) in text.lines().enumerate() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let Some((key, raw)) = line.split_once('=') else {
                continue;
            };
            let value = unquote(raw.trim())
                .ok_or_else(|| format!("repo.conf line {}: unsupported quoting", n + 1))?;
            match key.trim() {
                "REEF_ALIAS" => cfg.alias = value,
                // The conf leaves %(arch) for ssu; RepoConfig uses {arch}.
                "REEF_URL_TEMPLATE" => {
                    cfg.url_template = value.replace(SSU_ARCH_VARIABLE, "{arch}");
                }
                "REEF_RELEASE_GRANULARITY" => {
                    cfg.granularity = match value.as_str() {
                        "full" => ReleaseGranularity::Full,
                        "major-minor" => ReleaseGranularity::MajorMinor,
                        other => {
                            return Err(format!(
                                "repo.conf line {}: REEF_RELEASE_GRANULARITY {other:?} \
                                 is not full or major-minor",
                                n + 1
                            ))
                        }
                    }
                }
                "REEF_KEY_FILE" => cfg.key_path = value,
                _ => {}
            }
        }
        if cfg.alias.is_empty() || !cfg.url_template.contains("{release}") {
            return Err(
                "repo.conf: REEF_ALIAS is empty or REEF_URL_TEMPLATE has no {release}".into(),
            );
        }
        Ok(cfg)
    }
}

/// A shell word that is plain, or wholly in single or double quotes without
/// expansions. Anything else (`$`, backquotes) is refused, not evaluated.
fn unquote(raw: &str) -> Option<String> {
    let inner = if let Some(s) = raw.strip_prefix('\'').and_then(|s| s.strip_suffix('\'')) {
        return (!s.contains('\'')).then(|| s.to_string());
    } else if let Some(s) = raw.strip_prefix('"').and_then(|s| s.strip_suffix('"')) {
        s
    } else {
        raw
    };
    (!inner.contains(['$', '`', '"', '\\', '\'']) && !inner.contains(char::is_whitespace))
        .then(|| inner.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rel(s: &str) -> SailfishRelease {
        SailfishRelease::parse(s).unwrap()
    }

    #[test]
    fn url_pins_literal_release_and_leaves_arch_to_ssu() {
        let cfg = RepoConfig::default();
        assert_eq!(
            cfg.repo_url(&rel("5.2.0.17")),
            "https://reefstore.app/sailfishos/5.2.0.17/%(arch)/"
        );
        assert_eq!(
            cfg.catalogue_url(&rel("5.2.0.17"), "aarch64"),
            "https://reefstore.app/sailfishos/5.2.0.17/aarch64/catalogue.json"
        );
        let mm = RepoConfig {
            granularity: ReleaseGranularity::MajorMinor,
            ..RepoConfig::default()
        };
        assert_eq!(
            mm.repo_url(&rel("5.2.0.17")),
            "https://reefstore.app/sailfishos/5.2/%(arch)/"
        );
    }

    #[test]
    fn register_commands_are_exact() {
        let cmds: Vec<String> = RepoConfig::default()
            .register_commands(&rel("5.2.0.17"))
            .iter()
            .map(Command::to_shell)
            .collect();
        assert_eq!(
            cmds,
            [
                "ssu ar shipwright-reef 'https://reefstore.app/sailfishos/5.2.0.17/%(arch)/'",
                "ssu ur",
                "rpm --import /usr/share/shipwright-reef/RPM-GPG-KEY-shipwright-reef",
                "pkcon -p repo-set-data shipwright-reef refresh-now true",
            ]
        );
    }

    const SSU_LR: &str = "\
Enabled repositories (global):
 - adaptation0          ... https://store-repository.jolla.com/releases/5.2.0.17/jolla-hw/adaptation-qcom/aarch64/
 - apps                 ... https://releases.jolla.com/jolla-apps/5.2.0.17/aarch64/
Enabled repositories (user):
 - shipwright-reef      ... https://reefstore.app/sailfishos/5.2.0.15/aarch64/
Disabled repositories (global, might be overridden by user config):
 - sailfishos-chum      ... https://repo.sailfishos.org/obs/sailfishos:/chum/5.2_aarch64/
";

    #[test]
    fn parses_ssu_lr() {
        let repos = parse_ssu_lr(SSU_LR);
        assert_eq!(repos.len(), 4);
        assert_eq!(repos[2].alias, "shipwright-reef");
        assert!(repos[2].enabled);
        assert_eq!(repos[3].alias, "sailfishos-chum");
        assert!(!repos[3].enabled);
    }

    #[test]
    fn detects_drift_after_os_update() {
        let cfg = RepoConfig::default();
        let repos = parse_ssu_lr(SSU_LR);
        let state = cfg.pin_state(&repos, &rel("5.2.0.17"), "aarch64");
        assert_eq!(
            state,
            PinState::Drifted {
                registered: "https://reefstore.app/sailfishos/5.2.0.15/aarch64/".into()
            }
        );
        let fix: Vec<String> = cfg
            .repair_commands(&state, &rel("5.2.0.17"))
            .iter()
            .map(Command::to_shell)
            .collect();
        assert_eq!(fix[0], "ssu rr shipwright-reef");
        assert!(fix[1].contains("/5.2.0.17/%(arch)/"));
        // Still on 5.2.0.15: pinned, whether ssu shows %(arch) expanded or not.
        assert_eq!(
            cfg.pin_state(&repos, &rel("5.2.0.15"), "aarch64"),
            PinState::Pinned
        );
        let unexpanded = vec![SsuRepo {
            alias: "shipwright-reef".into(),
            url: cfg.repo_url(&rel("5.2.0.15")),
            enabled: false,
        }];
        assert_eq!(
            cfg.pin_state(&unexpanded, &rel("5.2.0.15"), "aarch64"),
            PinState::Disabled
        );
        assert_eq!(
            cfg.pin_state(&[], &rel("5.2.0.15"), "aarch64"),
            PinState::Missing
        );
    }

    #[test]
    fn repo_conf_matches_the_installer() {
        // B-07: the client reads the same repo.conf the installer sources.
        let shipped = include_str!("../../../installer/repo.conf");
        assert_eq!(
            RepoConfig::from_repo_conf(shipped).unwrap(),
            RepoConfig {
                key_path: "/usr/share/shipwright-reef-installer/RPM-GPG-KEY-shipwright-reef".into(),
                ..RepoConfig::default()
            }
        );
        let mm = shipped.replace(
            "REEF_RELEASE_GRANULARITY=full",
            "REEF_RELEASE_GRANULARITY=major-minor",
        );
        let cfg = RepoConfig::from_repo_conf(&mm).unwrap();
        assert_eq!(cfg.granularity, ReleaseGranularity::MajorMinor);
        let release = rel("5.2.0.17");
        assert_eq!(
            cfg.repo_url(&release),
            "https://reefstore.app/sailfishos/5.2/%(arch)/"
        );
        // A major-minor registration is pinned, not drifted (no 404 repair).
        let repos = [SsuRepo {
            alias: "shipwright-reef".into(),
            url: cfg.repo_url(&release),
            enabled: true,
        }];
        assert_eq!(cfg.pin_state(&repos, &release, "aarch64"), PinState::Pinned);
    }

    #[test]
    fn repo_conf_refuses_expansions_and_bad_values() {
        for bad in [
            "REEF_RELEASE_GRANULARITY=weekly",
            "REEF_ALIAS=$(id)",
            "REEF_URL_TEMPLATE=\"https://x/$HOME/{release}/\"",
            "REEF_URL_TEMPLATE='https://x/no-release/'",
        ] {
            assert!(RepoConfig::from_repo_conf(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn shell_quoting() {
        assert_eq!(shell_quote("plain-1.0"), "plain-1.0");
        assert_eq!(shell_quote("%(arch)"), "'%(arch)'");
        assert_eq!(shell_quote("it's"), r"'it'\''s'");
        assert_eq!(shell_quote(""), "''");
    }
}
