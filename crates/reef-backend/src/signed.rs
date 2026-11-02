// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The catalogue's signature, checked before the catalogue is parsed, as
//! Reef's Sailfish OS store checks its index: a detached ASCII `GnuPG`
//! signature (`<catalogue>.asc`) by the key Reef ships, checked with the
//! phone's `gpgv` against a keyring holding only that key, and a `revision`
//! that never goes backwards, so a replayed older catalogue, signed but
//! stale, is refused.

use std::path::Path;
use std::process::Command;

/// The catalogue key, dearmored: gpgv reads no armored keys.
pub const KEY: &str = "/usr/share/shipwright-reef/marathon-reef.gpg";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SignatureError {
    /// Not a good signature by the key.
    Bad(String),
    /// Older than a catalogue already accepted.
    Rollback { seen: u64, accepted: u64 },
    /// gpgv could not be run.
    Tool(String),
}

impl std::fmt::Display for SignatureError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SignatureError::Bad(why) => write!(f, "the catalogue's signature is not good ({why})"),
            SignatureError::Rollback { seen, accepted } => write!(
                f,
                "the catalogue is older (revision {seen}) than one already seen ({accepted})"
            ),
            SignatureError::Tool(why) => {
                write!(f, "could not check the catalogue's signature: {why}")
            }
        }
    }
}

/// gpgv's status lines: a good, valid signature and nothing against it.
fn good_signature(status: &str) -> bool {
    let tokens: Vec<&str> = status
        .lines()
        .filter_map(|l| l.strip_prefix("[GNUPG:] "))
        .filter_map(|l| l.split_whitespace().next())
        .collect();
    tokens.contains(&"GOODSIG")
        && tokens.contains(&"VALIDSIG")
        && !tokens.iter().any(|t| {
            matches!(
                *t,
                "BADSIG" | "ERRSIG" | "EXPSIG" | "EXPKEYSIG" | "REVKEYSIG"
            )
        })
}

/// Checks `signature` over `body` with the keyring at `keyring` alone.
pub fn verify(body: &[u8], signature: &[u8], keyring: &Path) -> Result<(), SignatureError> {
    if !keyring.is_absolute() {
        return Err(SignatureError::Tool(format!(
            "the key path must be absolute: {}",
            keyring.display()
        )));
    }
    let dir = tempfile::tempdir().map_err(|e| SignatureError::Tool(e.to_string()))?;
    let (data, sig) = (
        dir.path().join("catalogue"),
        dir.path().join("catalogue.asc"),
    );
    std::fs::write(&data, body).map_err(|e| SignatureError::Tool(e.to_string()))?;
    std::fs::write(&sig, signature).map_err(|e| SignatureError::Tool(e.to_string()))?;
    let out = Command::new("gpgv")
        .arg("--homedir")
        .arg(dir.path())
        .args(["--status-fd", "1", "--keyring"])
        .arg(keyring)
        .arg(&sig)
        .arg(&data)
        .output()
        .map_err(|e| SignatureError::Tool(format!("gpgv: {e}")))?;
    if out.status.success() && good_signature(&String::from_utf8_lossy(&out.stdout)) {
        Ok(())
    } else {
        let why = String::from_utf8_lossy(&out.stderr);
        Err(SignatureError::Bad(
            why.lines().last().unwrap_or("no good signature").to_owned(),
        ))
    }
}

/// A catalogue's `revision`; 0 for one without.
pub fn revision(body: &[u8]) -> u64 {
    serde_json::from_slice::<serde_json::Value>(body)
        .ok()
        .and_then(|v| v["revision"].as_u64())
        .unwrap_or(0)
}

/// Refuses `seen` when `state` holds a higher revision; else records it.
pub fn accept_revision(state: &Path, seen: u64) -> Result<(), SignatureError> {
    let accepted = std::fs::read_to_string(state)
        .ok()
        .and_then(|s| s.trim().parse::<u64>().ok())
        .unwrap_or(0);
    if seen < accepted {
        return Err(SignatureError::Rollback { seen, accepted });
    }
    if seen > accepted {
        let dir = state.parent().unwrap_or_else(|| Path::new("."));
        std::fs::create_dir_all(dir).map_err(|e| SignatureError::Tool(e.to_string()))?;
        let tmp = tempfile::NamedTempFile::new_in(dir)
            .and_then(|mut f| {
                use std::io::Write;
                f.write_all(seen.to_string().as_bytes())?;
                Ok(f)
            })
            .map_err(|e| SignatureError::Tool(e.to_string()))?;
        tmp.persist(state)
            .map_err(|e| SignatureError::Tool(e.error.to_string()))?;
    }
    Ok(())
}

/// A throwaway `GnuPG` key for tests: signs with `sign`, checks with
/// `keyring`. Its agent stops when it is dropped.
#[cfg(any(test, feature = "test-support"))]
pub mod test_key {
    use std::path::{Path, PathBuf};
    use std::process::Command;

    pub struct TestKey {
        home: tempfile::TempDir,
        pub keyring: PathBuf,
    }

    fn gpg(home: &Path) -> Command {
        let mut cmd = Command::new("gpg");
        cmd.arg("--homedir").arg(home).args(["--batch", "--quiet"]);
        cmd
    }

    impl TestKey {
        /// `None` without gpg and gpgv.
        pub fn new() -> Option<Self> {
            let home = tempfile::tempdir().ok()?;
            let made = gpg(home.path())
                .args([
                    "--passphrase",
                    "",
                    "--pinentry-mode",
                    "loopback",
                    "--quick-generate-key",
                    "Reef test <test@example.invalid>",
                    "ed25519",
                    "sign",
                    "never",
                ])
                .status()
                .ok()?;
            let keyring = home.path().join("key.gpg");
            let exported = gpg(home.path())
                .args(["--output"])
                .arg(&keyring)
                .args(["--export", "test@example.invalid"])
                .status()
                .ok()?;
            let gpgv = Command::new("gpgv").arg("--version").output().ok()?;
            (made.success() && exported.success() && gpgv.status.success())
                .then_some(Self { home, keyring })
        }

        /// The detached ASCII signature over `body`.
        ///
        /// # Panics
        ///
        /// When gpg cannot sign.
        #[allow(clippy::unwrap_used, reason = "tests")]
        pub fn sign(&self, body: &[u8]) -> Vec<u8> {
            let data = self.home.path().join("data");
            std::fs::write(&data, body).unwrap();
            let out = gpg(self.home.path())
                .args(["--armor", "--detach-sign", "--output", "-"])
                .arg(&data)
                .output()
                .unwrap();
            assert!(out.status.success(), "gpg --detach-sign failed");
            out.stdout
        }
    }

    impl Drop for TestKey {
        fn drop(&mut self) {
            Command::new("gpgconf")
                .arg("--homedir")
                .arg(self.home.path())
                .args(["--kill", "all"])
                .status()
                .ok();
        }
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::print_stderr, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn only_a_good_signature_by_the_key_passes() {
        let Some(key) = test_key::TestKey::new() else {
            eprintln!("skipped: needs gpg and gpgv");
            return;
        };
        let body = br#"{"schema":1,"revision":7}"#;
        let sig = key.sign(body);
        assert_eq!(verify(body, &sig, &key.keyring), Ok(()));
        // Another body, a signature by another key, or none.
        assert!(matches!(
            verify(br#"{"schema":1,"revision":8}"#, &sig, &key.keyring),
            Err(SignatureError::Bad(_))
        ));
        let other = test_key::TestKey::new().unwrap();
        assert!(matches!(
            verify(body, &other.sign(body), &key.keyring),
            Err(SignatureError::Bad(_))
        ));
        assert!(matches!(
            verify(body, b"", &key.keyring),
            Err(SignatureError::Bad(_))
        ));
    }

    #[test]
    fn status_needs_good_and_valid_and_nothing_against() {
        assert!(good_signature(
            "[GNUPG:] GOODSIG 1 x\n[GNUPG:] VALIDSIG 1 x\n"
        ));
        assert!(!good_signature("[GNUPG:] GOODSIG 1 x\n"));
        assert!(!good_signature(
            "[GNUPG:] GOODSIG 1 x\n[GNUPG:] VALIDSIG 1 x\n[GNUPG:] EXPKEYSIG 1 x\n"
        ));
        assert!(!good_signature(""));
    }

    #[test]
    fn revisions_never_go_backwards() {
        let dir = tempfile::tempdir().unwrap();
        let state = dir.path().join("reef/catalogue-revision");
        assert_eq!(revision(br#"{"revision": 1793657077}"#), 1_793_657_077);
        assert_eq!(revision(b"{}"), 0);
        assert_eq!(accept_revision(&state, 10), Ok(()));
        assert_eq!(accept_revision(&state, 10), Ok(()));
        assert_eq!(accept_revision(&state, 11), Ok(()));
        assert_eq!(
            accept_revision(&state, 9),
            Err(SignatureError::Rollback {
                seen: 9,
                accepted: 11
            })
        );
    }
}
