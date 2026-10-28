// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

//! reef-backend: the Rust half of the Reef store client.
//!
//! The QML UI (reef/client/ui) talks to one backend object exposed through
//! CXX-Qt (`reef/client/app/src/bridge.rs`); that object is a thin shell
//! over this crate:
//!
//! * [`release`]: which Sailfish release is installed (not `ssu re`).
//! * [`repo`]: the exact ssu/rpm/pkcon commands that register the Reef
//!   repository pinned to that release, and drift detection after an OS
//!   update.
//! * [`catalogue`]: the per-release, per-arch catalogue, hiding packages not
//!   tested on this release.
//! * [`index`]: the store index (catalogue v2): the same catalogue from a
//!   signed index, each app's details merged when they are fetched.
//! * [`packagekit`]: resolve, install, update and remove through `PackageKit`
//!   over D-Bus, with progress.
//! * [`licences`]: storage and offline verification of licence tokens.
//! * [`claim_codes`]: the codes that fetch a licence bought on the web.
//! * [`licenced`]: the session-bus service that hands tokens to sandboxed
//!   apps (`shipwright-reef-licenced`, src/bin).
//! * [`store`]: the catalogue joined with install state, for the UI.
//! * [`plan`]: what an install, update or removal will do, which the
//!   person sees and agrees to before anything happens.
//!
//! No networking lives here: the UI layer downloads the catalogue, tokens
//! and revocation list and passes the bytes in.

pub mod catalogue;
pub mod claim_codes;
pub mod index;
pub mod licenced;
pub mod licences;
pub mod metadata;
pub mod packagekit;
pub mod plan;
pub mod release;
pub mod repo;
pub mod store;

/// `cmd` set to run in the C locale (`LC_ALL=C`, `LANGUAGE=C`): for every
/// tool whose output Reef reads (ssu, rpm, gpgv, version). On a phone not
/// set to English their messages are translated, and Reef refused every
/// install on such phones while it read gpgv's English one.
pub fn c_locale(cmd: &mut std::process::Command) -> &mut std::process::Command {
    cmd.env("LC_ALL", "C").env("LANGUAGE", "C")
}

#[cfg(test)]
mod tests {
    #[test]
    fn c_locale_overrides_the_phones_language() {
        let mut cmd = std::process::Command::new("ssu");
        cmd.env("LC_ALL", "de_DE.UTF-8");
        super::c_locale(&mut cmd);
        let envs: Vec<_> = cmd.get_envs().collect();
        assert!(envs.contains(&("LC_ALL".as_ref(), Some("C".as_ref()))));
        assert!(envs.contains(&("LANGUAGE".as_ref(), Some("C".as_ref()))));
    }
}
