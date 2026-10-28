// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The store view the UI shows: catalogue entries joined with what is
//! installed and what has an update.

use crate::catalogue::{Catalogue, Package};

/// A package on the phone, or an update offered for one.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PackageVersion {
    pub name: String,
    pub version: String,
}

/// Where a catalogue package stands on this phone.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InstallState {
    NotInstalled,
    Installed {
        version: String,
    },
    UpdateAvailable {
        installed: String,
        available: String,
    },
}

/// One row of the catalogue page.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry<'a> {
    pub package: &'a Package,
    pub state: InstallState,
}

/// Joins visible catalogue packages with installed and update lists.
pub fn entries<'a>(
    catalogue: &'a Catalogue,
    installed: &[PackageVersion],
    updates: &[PackageVersion],
) -> Vec<Entry<'a>> {
    catalogue
        .visible()
        .into_iter()
        .map(|package| {
            let inst = installed.iter().find(|p| p.name == package.name);
            let upd = updates.iter().find(|p| p.name == package.name);
            let state = match (inst, upd) {
                (None, _) => InstallState::NotInstalled,
                (Some(i), Some(u)) => InstallState::UpdateAvailable {
                    installed: i.version.clone(),
                    available: u.version.clone(),
                },
                (Some(i), None) => InstallState::Installed {
                    version: i.version.clone(),
                },
            };
            Entry { package, state }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::catalogue::tests::SAMPLE;

    fn pkg(name: &str, version: &str) -> PackageVersion {
        PackageVersion {
            name: name.into(),
            version: version.into(),
        }
    }

    #[test]
    fn joins_install_state() {
        let cat = Catalogue::parse(SAMPLE.as_bytes(), "aarch64").unwrap();
        let installed = [
            pkg("shipwright-keel-silica", "0.1.0-1"),
            pkg("shipwright-shoal-bridge-airpods-ui", "0.9.0-1"),
        ];
        let updates = [pkg("shipwright-shoal-bridge-airpods-ui", "1.0.0-1")];
        let rows = entries(&cat, &installed, &updates);
        assert_eq!(rows.len(), 3);
        // Sorted by category: Audio (the bridge) before Libraries (Keel).
        assert_eq!(
            rows[0].state,
            InstallState::UpdateAvailable {
                installed: "0.9.0-1".into(),
                available: "1.0.0-1".into()
            }
        );
        assert_eq!(
            rows[1].state,
            InstallState::Installed {
                version: "0.1.0-1".into()
            }
        );
        assert_eq!(rows[2].state, InstallState::NotInstalled);
        let none = entries(&cat, &[], &[]);
        assert!(none.iter().all(|e| e.state == InstallState::NotInstalled));
    }
}
