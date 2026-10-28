// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The Reef repository's signature, checked by Reef itself before it
//! installs or updates anything.
//!
//! Sailfish OS registers every repository through ssu, which writes
//! `gpgcheck=0` into each repository file (Jolla's own included) and
//! rewrites any change to it on `ssu ur`; a repository file ssu does not
//! know is deleted. zypp therefore never checks the signature on Reef's
//! `repomd.xml` (found on a Jolla Phone, 5.2.0.18, 11 October 2026), and the
//! packages are trusted on HTTPS alone.
//!
//! zypp keeps the metadata it installs from, signature included, in its
//! metadata cache (`<metadatadir>/<alias>/repodata/repomd.xml` and `.asc`).
//! `repomd.xml` carries the SHA-256 of `primary.xml`, which carries the
//! checksum of every package, and zypp checks each package it downloads
//! against those. So checking that one signature with the Reef key Reef
//! ships (`/usr/share/shipwright-reef/RPM-GPG-KEY-shipwright-reef`), with
//! the phone's own `gpgv2`, covers every package installed from it.
//!
//! Rollback: the metadata's `<revision>` (the publish time) must not go
//! backwards. Reef keeps the highest it has accepted, so a replayed older
//! snapshot, signed but stale (withholding an update), is refused.

use std::path::{Path, PathBuf};
use std::process::Command;

/// Why the metadata was refused.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MetaError {
    /// No metadata or signature in zypp's cache (not refreshed yet).
    Missing(String),
    /// The signature does not verify with Reef's key.
    BadSignature(String),
    /// Older than metadata already accepted.
    Rollback { seen: u64, accepted: u64 },
    /// gpg could not be run.
    Tool(String),
}

impl std::fmt::Display for MetaError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MetaError::Missing(m) => write!(f, "the store's package list is missing ({m})"),
            MetaError::BadSignature(m) => {
                write!(f, "the store's package list failed its signature check ({m})")
            }
            MetaError::Rollback { seen, accepted } => write!(
                f,
                "the store's package list is older than one already seen (revision {seen}, had {accepted})"
            ),
            MetaError::Tool(m) => write!(f, "the store's package list could not be checked ({m})"),
        }
    }
}

/// Where and how to check.
#[derive(Debug, Clone)]
pub struct MetadataCheck {
    /// zypp's configuration (for `metadatadir`).
    pub zypp_conf: PathBuf,
    /// Repository alias.
    pub alias: String,
    /// The armoured public key Reef trusts.
    pub key: PathBuf,
    /// Where the highest accepted revision is kept.
    pub state: PathBuf,
    /// `gpg` and `gpgv` programs (Sailfish ships `gpg2`/`gpgv2`).
    pub gpg: String,
    pub gpgv: String,
}

impl MetadataCheck {
    /// The phone's paths, or `None` without a home directory.
    pub fn device(alias: &str) -> Option<MetadataCheck> {
        let env = |v: &str| {
            std::env::var_os(v)
                .filter(|x| !x.is_empty())
                .map(PathBuf::from)
        };
        let data = env("XDG_DATA_HOME").or_else(|| env("HOME").map(|h| h.join(".local/share")))?;
        Some(MetadataCheck {
            zypp_conf: PathBuf::from("/etc/zypp/zypp.conf"),
            alias: alias.to_owned(),
            key: PathBuf::from("/usr/share/shipwright-reef/RPM-GPG-KEY-shipwright-reef"),
            state: data.join("shipwright-reef/metadata-revision"),
            gpg: "gpg2".into(),
            gpgv: "gpgv2".into(),
        })
    }

    /// The repository's metadata directory in zypp's cache.
    pub fn repodata(&self) -> PathBuf {
        let conf = std::fs::read_to_string(&self.zypp_conf).unwrap_or_default();
        metadata_dir(&conf).join(&self.alias).join("repodata")
    }

    /// Verifies the cached metadata; its revision on success, which is then
    /// remembered as the lowest acceptable.
    pub fn verify(&self) -> Result<u64, MetaError> {
        let dir = self.repodata();
        let repomd = dir.join("repomd.xml");
        let asc = dir.join("repomd.xml.asc");
        let xml = std::fs::read_to_string(&repomd)
            .map_err(|e| MetaError::Missing(format!("{}: {e}", repomd.display())))?;
        if !asc.is_file() {
            return Err(MetaError::Missing(format!("{} not found", asc.display())));
        }
        verify_signature(&self.gpg, &self.gpgv, &self.key, &repomd, &asc)?;
        let seen = revision(&xml).unwrap_or(0);
        accept_revision(&self.state, seen)?;
        Ok(seen)
    }

    /// Checks a downloaded store index (`store/index.json`, `crate::index`)
    /// the same way: its detached signature `sig` with Reef's key, and its
    /// `revision` (from the index, read after this check passes) against
    /// the highest accepted, kept beside the metadata's.
    pub fn verify_index(&self, index: &Path, sig: &Path) -> Result<(), MetaError> {
        verify_signature(&self.gpg, &self.gpgv, &self.key, index, sig)
    }

    /// Refuses an index revision older than one accepted before, and
    /// remembers a newer one.
    pub fn accept_index_revision(&self, seen: u64) -> Result<(), MetaError> {
        accept_revision(&self.state.with_file_name("index-revision"), seen)
    }
}

/// The rollback rule: `seen` below the revision stored in `state` is
/// refused; above it, it is stored.
fn accept_revision(state: &Path, seen: u64) -> Result<(), MetaError> {
    let accepted = std::fs::read_to_string(state)
        .ok()
        .and_then(|s| s.trim().parse::<u64>().ok())
        .unwrap_or(0);
    if seen < accepted {
        return Err(MetaError::Rollback { seen, accepted });
    }
    if seen > accepted {
        if let Some(parent) = state.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let tmp = state.with_extension(format!("{}.tmp", std::process::id()));
        if std::fs::write(&tmp, seen.to_string()).is_ok() {
            let _ = std::fs::rename(tmp, state);
        }
    }
    Ok(())
}

/// zypp's metadata directory from `zypp.conf`: `metadatadir`, else
/// `<cachedir>/raw`, else `/var/cache/zypp/raw` (zypp's defaults; Sailfish
/// sets `/home/.zypp-cache/raw`).
pub fn metadata_dir(conf: &str) -> PathBuf {
    let value = |key: &str| {
        conf.lines()
            .map(str::trim)
            .filter(|l| !l.starts_with('#') && !l.starts_with(';'))
            .filter_map(|l| l.split_once('='))
            .find(|(k, _)| k.trim() == key)
            .map(|(_, v)| PathBuf::from(v.trim()))
    };
    value("metadatadir")
        .or_else(|| value("cachedir").map(|c| c.join("raw")))
        .unwrap_or_else(|| PathBuf::from("/var/cache/zypp/raw"))
}

/// `<revision>` of a `repomd.xml`.
pub fn revision(repomd: &str) -> Option<u64> {
    let start = repomd.find("<revision>")? + "<revision>".len();
    let end = repomd[start..].find("</revision>")? + start;
    repomd[start..end].trim().parse().ok()
}

/// Whether gpgv's status lines (`--status-fd`) report a good, valid
/// signature: `GOODSIG` and `VALIDSIG`, with no `BADSIG`, `ERRSIG`,
/// `EXPSIG`, `EXPKEYSIG` or `REVKEYSIG`.
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

/// `gpgv` with a keyring holding only `key`: the signature must be good and
/// made by that key.
fn verify_signature(
    gpg: &str,
    gpgv: &str,
    key: &Path,
    data: &Path,
    sig: &Path,
) -> Result<(), MetaError> {
    let dir = std::env::temp_dir().join(format!(
        "reef-meta-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos())
    ));
    std::fs::create_dir_all(&dir).map_err(|e| MetaError::Tool(e.to_string()))?;
    let result = (|| {
        let keyring = dir.join("reef.gpg");
        let armoured =
            std::fs::read(key).map_err(|e| MetaError::Tool(format!("{}: {e}", key.display())))?;
        let out = Command::new(gpg)
            .args(["--batch", "--homedir"])
            .arg(&dir)
            .arg("--dearmor")
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::null())
            .spawn()
            .and_then(|mut child| {
                use std::io::Write as _;
                if let Some(mut stdin) = child.stdin.take() {
                    stdin.write_all(&armoured)?;
                }
                child.wait_with_output()
            })
            .map_err(|e| MetaError::Tool(format!("{gpg}: {e}")))?;
        if !out.status.success() || out.stdout.is_empty() {
            return Err(MetaError::Tool(format!("{gpg} --dearmor failed")));
        }
        std::fs::write(&keyring, &out.stdout).map_err(|e| MetaError::Tool(e.to_string()))?;
        // The verdict comes from gpgv's machine-readable status lines, not
        // its message: that is translated ("Firma correcta" on a Spanish
        // phone), and reading the English one failed every phone not set
        // to English (forum, 12 October 2026). The C locale keeps the
        // message we pass on readable too.
        let out = Command::new(gpgv)
            .env("LC_ALL", "C")
            .env("LANGUAGE", "C")
            .arg("--homedir")
            .arg(&dir)
            .arg("--status-fd")
            .arg("1")
            .arg("--keyring")
            .arg(&keyring)
            .arg(sig)
            .arg(data)
            .output()
            .map_err(|e| MetaError::Tool(format!("{gpgv}: {e}")))?;
        let said = String::from_utf8_lossy(&out.stderr).into_owned();
        if out.status.success() && good_signature(&String::from_utf8_lossy(&out.stdout)) {
            Ok(())
        } else {
            Err(MetaError::BadSignature(
                said.lines()
                    .last()
                    .unwrap_or("no good signature")
                    .trim()
                    .to_owned(),
            ))
        }
    })();
    let _ = std::fs::remove_dir_all(&dir);
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_good_signature_in_any_language() {
        let good = "[GNUPG:] NEWSIG\n[GNUPG:] GOODSIG 0123 Shipwright Reef <repo@reefstore.app>\n\
                    [GNUPG:] VALIDSIG ABCD 2026-10-11 1791700000 0 4 0 1 10 00 ABCD\n";
        assert!(good_signature(good));
        assert!(!good_signature("[GNUPG:] BADSIG 0123 Shipwright Reef\n"));
        assert!(!good_signature(
            "[GNUPG:] ERRSIG 0123 1 10 00 1791700000 9 -\n"
        ));
        assert!(!good_signature(&format!(
            "{good}[GNUPG:] EXPKEYSIG 0123 Shipwright Reef\n"
        )));
        assert!(!good_signature(""));
    }

    /// The forum's Spanish phone: gpgv says "Firma correcta" and succeeds.
    /// A stand-in gpgv answers as it does there; the check must pass.
    #[test]
    #[cfg(unix)]
    fn a_phone_not_in_english_verifies() {
        use std::os::unix::fs::PermissionsExt as _;
        let t = tempfile::tempdir().unwrap();
        let fake = t.path().join("gpgv-es");
        std::fs::write(
            &fake,
            "#!/bin/sh\n\
             echo 'gpgv: Firma correcta de \"Shipwright Reef <repo@reefstore.app>\"' >&2\n\
             echo '[GNUPG:] GOODSIG 0123 Shipwright Reef <repo@reefstore.app>'\n\
             echo '[GNUPG:] VALIDSIG ABCD 2026-10-11 1791700000 0 4 0 1 10 00 ABCD'\n",
        )
        .unwrap();
        std::fs::set_permissions(&fake, std::fs::Permissions::from_mode(0o755)).unwrap();
        // gpg itself is only asked to dearmor the key: `cat` stands in.
        let key = t.path().join("key.asc");
        std::fs::write(&key, "not empty").unwrap();
        let data = t.path().join("repomd.xml");
        std::fs::write(&data, "<repomd/>").unwrap();
        let sig = t.path().join("repomd.xml.asc");
        std::fs::write(&sig, "sig").unwrap();
        let fake_gpg = t.path().join("gpg-cat");
        std::fs::write(&fake_gpg, "#!/bin/sh\ncat\n").unwrap();
        std::fs::set_permissions(&fake_gpg, std::fs::Permissions::from_mode(0o755)).unwrap();
        assert_eq!(
            verify_signature(
                fake_gpg.to_str().unwrap(),
                fake.to_str().unwrap(),
                &key,
                &data,
                &sig
            ),
            Ok(())
        );
    }

    #[test]
    fn finds_zypps_metadata_directory() {
        let sailfish = "## comment\n[main]\n cachedir = /home/.zypp-cache\n metadatadir = /home/.zypp-cache/raw\n";
        assert_eq!(
            metadata_dir(sailfish),
            PathBuf::from("/home/.zypp-cache/raw")
        );
        assert_eq!(metadata_dir("cachedir = /c\n"), PathBuf::from("/c/raw"));
        assert_eq!(
            metadata_dir("# metadatadir = /x\n"),
            PathBuf::from("/var/cache/zypp/raw")
        );
    }

    #[test]
    fn reads_the_revision() {
        assert_eq!(
            revision("<repomd><revision>1791729204</revision></repomd>"),
            Some(1_791_729_204)
        );
        assert_eq!(revision("<repomd/>"), None);
    }

    /// With the host's gpg: a key made for the test signs a repomd.xml;
    /// genuine passes, tampered and other-key fail, and an older revision
    /// after a newer one is refused. Skipped without gpg.
    #[test]
    #[allow(
        clippy::too_many_lines,
        reason = "one key, then the metadata's and the index's checks in turn"
    )]
    fn checks_signature_and_rollback_with_real_gpg() {
        let gpg = ["gpg2", "gpg"]
            .into_iter()
            .find(|g| Command::new(g).arg("--version").output().is_ok());
        let gpgv = ["gpgv2", "gpgv"]
            .into_iter()
            .find(|g| Command::new(g).arg("--version").output().is_ok());
        let (Some(gpg), Some(gpgv)) = (gpg, gpgv) else {
            eprintln!("no gpg; skipped");
            return;
        };
        let t = tempfile::tempdir().unwrap();
        let home = t.path().join("gnupg");
        std::fs::create_dir_all(&home).unwrap();
        let g = |args: &[&str]| {
            let out = Command::new(gpg)
                .arg("--batch")
                .arg("--homedir")
                .arg(&home)
                .args(args)
                .output()
                .unwrap();
            assert!(
                out.status.success(),
                "{}",
                String::from_utf8_lossy(&out.stderr)
            );
            out.stdout
        };
        g(&[
            "--passphrase",
            "",
            "--quick-gen-key",
            "Reef Test <t@example.com>",
            "rsa2048",
            "sign",
            "never",
        ]);
        g(&[
            "--passphrase",
            "",
            "--quick-gen-key",
            "Other <o@example.com>",
            "rsa2048",
            "sign",
            "never",
        ]);
        let key = t.path().join("key.asc");
        std::fs::write(&key, g(&["--armor", "--export", "t@example.com"])).unwrap();
        let repodata = t.path().join("raw/shipwright-reef/repodata");
        std::fs::create_dir_all(&repodata).unwrap();
        let conf = t.path().join("zypp.conf");
        std::fs::write(
            &conf,
            format!("metadatadir = {}\n", t.path().join("raw").display()),
        )
        .unwrap();
        let sign = |rev: u64, who: &str| {
            let xml = repodata.join("repomd.xml");
            std::fs::write(&xml, format!("<repomd><revision>{rev}</revision></repomd>")).unwrap();
            let _ = std::fs::remove_file(repodata.join("repomd.xml.asc"));
            g(&[
                "--local-user",
                who,
                "--armor",
                "--detach-sign",
                "--output",
                repodata.join("repomd.xml.asc").to_str().unwrap(),
                xml.to_str().unwrap(),
            ]);
        };
        let check = MetadataCheck {
            zypp_conf: conf,
            alias: "shipwright-reef".into(),
            key,
            state: t.path().join("state/metadata-revision"),
            gpg: gpg.into(),
            gpgv: gpgv.into(),
        };
        sign(200, "t@example.com");
        assert_eq!(check.verify(), Ok(200));
        // Tampered after signing.
        std::fs::write(
            repodata.join("repomd.xml"),
            "<repomd><revision>201</revision></repomd>",
        )
        .unwrap();
        assert!(matches!(check.verify(), Err(MetaError::BadSignature(_))));
        // Signed, but by another key.
        sign(300, "o@example.com");
        assert!(matches!(check.verify(), Err(MetaError::BadSignature(_))));
        // Signed and genuine, but older than what was accepted.
        sign(100, "t@example.com");
        assert_eq!(
            check.verify(),
            Err(MetaError::Rollback {
                seen: 100,
                accepted: 200
            })
        );
        sign(250, "t@example.com");
        assert_eq!(check.verify(), Ok(250));
        std::fs::remove_file(repodata.join("repomd.xml.asc")).unwrap();
        assert!(matches!(check.verify(), Err(MetaError::Missing(_))));

        // The store index: the same key, its own rollback record.
        let index = t.path().join("index.json");
        let sig = t.path().join("index.json.asc");
        let sign_index = |body: &str, who: &str| {
            std::fs::write(&index, body).unwrap();
            let _ = std::fs::remove_file(&sig);
            g(&[
                "--local-user",
                who,
                "--armor",
                "--detach-sign",
                "--output",
                sig.to_str().unwrap(),
                index.to_str().unwrap(),
            ]);
        };
        sign_index("{\"revision\": 7}", "t@example.com");
        assert_eq!(check.verify_index(&index, &sig), Ok(()));
        std::fs::write(&index, "{\"revision\": 8}").unwrap();
        assert!(matches!(
            check.verify_index(&index, &sig),
            Err(MetaError::BadSignature(_))
        ));
        sign_index("{\"revision\": 9}", "o@example.com");
        assert!(matches!(
            check.verify_index(&index, &sig),
            Err(MetaError::BadSignature(_))
        ));
        assert_eq!(check.accept_index_revision(7), Ok(()));
        assert_eq!(
            check.accept_index_revision(6),
            Err(MetaError::Rollback {
                seen: 6,
                accepted: 7
            })
        );
        // Separate from the metadata's record (250).
        assert_eq!(check.accept_index_revision(8), Ok(()));
    }
}
