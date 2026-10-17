//! Minisign signatures over whole `.marathon` archives. The signature sits
//! beside the package as `<package>.minisig` and is checked against the
//! trusted keys before anything reads the archive.

use std::collections::BTreeSet;
use std::fs::{self, File};
use std::io::ErrorKind;
use std::path::{Path, PathBuf};

use minisign::{PublicKey, PublicKeyBox, SecretKey, SecretKeyBox, SignatureBox};

/// Name of the file in a trusted-keys directory that lists revoked key ids.
pub const REVOKED_FILE: &str = "revoked";

#[derive(Debug, PartialEq, Eq)]
pub enum Verdict {
    /// Signed by this trusted key.
    Valid(String),
    /// There is no signature file.
    Unsigned,
    InvalidSignature(String),
    UntrustedKey(String),
    RevokedKey(String),
    Failed(String),
}

pub fn signature_path(archive: &Path) -> PathBuf {
    let mut name = archive.as_os_str().to_owned();
    name.push(".minisig");
    PathBuf::from(name)
}

/// A key id as minisign prints it: the little-endian key number in hex.
fn key_id(keynum: &[u8]) -> String {
    let bytes: [u8; 8] = keynum.try_into().unwrap_or_default();
    format!("{:016X}", u64::from_le_bytes(bytes))
}

fn is_key_id(id: &str) -> bool {
    id.len() == 16 && id.bytes().all(|b| b.is_ascii_hexdigit())
}

/// The minisign public keys (`*.pub`) in some directories, less the key ids
/// any of them lists in its `revoked` file. A revocation in one directory
/// applies to a key trusted in another, so an OS update can withdraw a key
/// a user added themselves.
#[derive(Default)]
pub struct TrustStore {
    keys: Vec<(String, PublicKey)>,
    revoked: BTreeSet<String>,
}

impl TrustStore {
    /// Missing directories are skipped. A key or revocation file that does
    /// not parse is an error rather than something to skip, so a typo can't
    /// quietly drop a revocation.
    pub fn load(dirs: &[&Path]) -> Result<Self, String> {
        let mut store = Self::default();
        for dir in dirs {
            let entries = match fs::read_dir(dir) {
                Ok(entries) => entries,
                Err(e) if e.kind() == ErrorKind::NotFound => continue,
                Err(e) => return Err(format!("{}: {e}", dir.display())),
            };
            let mut paths: Vec<_> = entries
                .filter_map(Result::ok)
                .map(|entry| entry.path())
                .filter(|path| path.is_file())
                .collect();
            paths.sort();
            for path in paths {
                if path.file_name().is_some_and(|name| name == REVOKED_FILE) {
                    store.load_revoked(&path)?;
                } else if path.extension().is_some_and(|ext| ext == "pub") {
                    let name = path.display();
                    let text = fs::read_to_string(&path).map_err(|e| format!("{name}: {e}"))?;
                    let key = PublicKeyBox::from_string(&text)
                        .and_then(PublicKeyBox::into_public_key)
                        .map_err(|e| format!("{name}: {e}"))?;
                    store.keys.push((key_id(key.keynum()), key));
                }
            }
        }
        Ok(store)
    }

    fn load_revoked(&mut self, path: &Path) -> Result<(), String> {
        let name = path.display();
        let text = fs::read_to_string(path).map_err(|e| format!("{name}: {e}"))?;
        for line in text.lines() {
            let id = line.split('#').next().unwrap_or_default().trim();
            if id.is_empty() {
                continue;
            }
            if !is_key_id(id) {
                return Err(format!("{name}: not a key id: {id}"));
            }
            self.revoked.insert(id.to_ascii_uppercase());
        }
        Ok(())
    }

    pub fn key_ids(&self) -> impl Iterator<Item = &str> {
        self.keys.iter().map(|(id, _)| id.as_str())
    }
}

/// Checks `<archive>.minisig` over the bytes of `archive`. Only prehashed
/// signatures (minisign's default since 0.8) are accepted.
pub fn verify(archive: &Path, store: &TrustStore) -> Verdict {
    let signature = signature_path(archive);
    let text = match fs::read_to_string(&signature) {
        Ok(text) => text,
        Err(e) if e.kind() == ErrorKind::NotFound => return Verdict::Unsigned,
        Err(e) => return Verdict::Failed(format!("{}: {e}", signature.display())),
    };
    let sig = match SignatureBox::from_string(&text) {
        Ok(sig) => sig,
        Err(e) => return Verdict::InvalidSignature(format!("unreadable signature: {e}")),
    };
    let id = key_id(sig.keynum());
    if store.revoked.contains(&id) {
        return Verdict::RevokedKey(id);
    }
    let mut candidates = store.keys.iter().filter(|(k, _)| *k == id).peekable();
    if candidates.peek().is_none() {
        return Verdict::UntrustedKey(id);
    }
    let mut last_error = String::new();
    for (_, key) in candidates {
        let file = match File::open(archive) {
            Ok(file) => file,
            Err(e) => return Verdict::Failed(format!("{}: {e}", archive.display())),
        };
        match minisign::verify(key, &sig, file, true, false, false) {
            Ok(()) => return Verdict::Valid(id),
            Err(e) => last_error = e.to_string(),
        }
    }
    Verdict::InvalidSignature(last_error)
}

/// Writes `<archive>.minisig` with the minisign secret key at `secret_key`,
/// asking on the terminal for its password if it has one.
pub fn sign(archive: &Path, secret_key: &Path) -> Result<(), String> {
    let name = secret_key.display();
    let text = fs::read_to_string(secret_key).map_err(|e| format!("{name}: {e}"))?;
    let unencrypted =
        SecretKeyBox::from_string(&text).and_then(SecretKeyBox::into_unencrypted_secret_key);
    let key = match unencrypted {
        Ok(key) => key,
        Err(_) => SecretKeyBox::from_string(&text)
            .and_then(|sk| SecretKey::from_box(sk, None))
            .map_err(|e| format!("{name}: {e}"))?,
    };
    let data = File::open(archive).map_err(|e| format!("{}: {e}", archive.display()))?;
    let sig = minisign::sign(None, &key, data, None, None).map_err(|e| e.to_string())?;
    let out = signature_path(archive);
    fs::write(&out, sig.into_string()).map_err(|e| format!("{}: {e}", out.display()))
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;
    use minisign::KeyPair;

    struct Fixture {
        dir: tempfile::TempDir,
    }

    impl Fixture {
        fn new() -> Self {
            let dir = tempfile::tempdir().unwrap();
            fs::create_dir(dir.path().join("system")).unwrap();
            fs::create_dir(dir.path().join("user")).unwrap();
            fs::write(
                dir.path().join("app.marathon"),
                b"PK\x03\x04 pretend archive",
            )
            .unwrap();
            Self { dir }
        }

        fn path(&self, name: &str) -> PathBuf {
            self.dir.path().join(name)
        }

        fn archive(&self) -> PathBuf {
            self.path("app.marathon")
        }

        /// A new key pair: the secret key written to `name.key`, the public
        /// key to `<keys>/name.pub` when `keys` is given. Returns the key id.
        fn key(&self, name: &str, keys: Option<&str>) -> String {
            let pair = KeyPair::generate_unencrypted_keypair().unwrap();
            fs::write(
                self.path(&format!("{name}.key")),
                pair.sk.to_box(None).unwrap().into_string(),
            )
            .unwrap();
            if let Some(keys) = keys {
                fs::write(
                    self.path(keys).join(format!("{name}.pub")),
                    pair.pk.to_box().unwrap().into_string(),
                )
                .unwrap();
            }
            key_id(pair.pk.keynum())
        }

        fn sign(&self, name: &str) {
            sign(&self.archive(), &self.path(&format!("{name}.key"))).unwrap();
        }

        fn verify(&self) -> Verdict {
            let system = self.path("system");
            let user = self.path("user");
            let store = TrustStore::load(&[&system, &user]).unwrap();
            verify(&self.archive(), &store)
        }
    }

    #[test]
    fn signature_by_a_trusted_key_is_valid() {
        let f = Fixture::new();
        let id = f.key("alice", Some("system"));
        f.sign("alice");
        assert_eq!(f.verify(), Verdict::Valid(id));
    }

    #[test]
    fn any_of_several_trusted_keys_can_sign() {
        let f = Fixture::new();
        f.key("alice", Some("system"));
        let bob = f.key("bob", Some("user"));
        f.sign("bob");
        assert_eq!(f.verify(), Verdict::Valid(bob));
    }

    #[test]
    fn missing_signature_is_unsigned() {
        let f = Fixture::new();
        f.key("alice", Some("system"));
        assert_eq!(f.verify(), Verdict::Unsigned);
    }

    #[test]
    fn tampered_archive_is_invalid() {
        let f = Fixture::new();
        f.key("alice", Some("system"));
        f.sign("alice");
        let mut bytes = fs::read(f.archive()).unwrap();
        bytes.push(b'!');
        fs::write(f.archive(), bytes).unwrap();
        assert!(matches!(f.verify(), Verdict::InvalidSignature(_)));
    }

    #[test]
    fn untrusted_key_is_refused() {
        let f = Fixture::new();
        f.key("alice", Some("system"));
        let mallory = f.key("mallory", None);
        f.sign("mallory");
        assert_eq!(f.verify(), Verdict::UntrustedKey(mallory));
    }

    #[test]
    fn revocation_in_any_directory_wins() {
        let f = Fixture::new();
        let bob = f.key("bob", Some("user"));
        f.sign("bob");
        fs::write(
            f.path("system").join(REVOKED_FILE),
            format!("# leaked 2026-10\n{}\n", bob.to_ascii_lowercase()),
        )
        .unwrap();
        assert_eq!(f.verify(), Verdict::RevokedKey(bob));
    }

    #[test]
    fn garbage_signature_is_invalid() {
        let f = Fixture::new();
        f.key("alice", Some("system"));
        fs::write(signature_path(&f.archive()), "not a signature").unwrap();
        assert!(matches!(f.verify(), Verdict::InvalidSignature(_)));
    }

    // Made by the C minisign CLI; from rust-minisign-verify's tests.
    const CLI_PUBLIC_KEY: &str = "untrusted comment: minisign public key\n\
        RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3\n";
    const CLI_PREHASHED: &str = "untrusted comment: signature from minisign secret key\n\
        RUQf6LRCGA9i559r3g7V1qNyJDApGip8MfqcadIgT9CuhV3EMhHoN1mGTkUidF/\
        z7SrlQgXdy8ofjb7bNJJylDOocrCo8KLzZwo=\n\
        trusted comment: timestamp:1556193335\tfile:test\n\
        y/rUw2y8/hOUYjZU71eHp/Wo1KZ40fGy2VJEDl34XMJM+TX48Ss/17u3IvIfbVR1FkZZSNCisQbuQY+bHwhEBg==\n";
    const CLI_LEGACY: &str = "untrusted comment: signature from minisign secret key\n\
        RWQf6LRCGA9i59SLOFxz6NxvASXDJeRtuZykwQepbDEGt87ig1BNpWaVWuNrm73YiIiJbq71Wi+dP9eKL8OC351vwIasSSbXxwA=\n\
        trusted comment: timestamp:1555779966\tfile:test\n\
        QtKMXWyYcwdpZAlPF7tE2ENJkRd1ujvKjlj1m9RtHTBnZPa5WKU5uWRs5GoP5M/VqE81QFuMKI5k/SfNQUaOAA==\n";

    #[test]
    fn minisign_cli_signatures_verify_and_legacy_ones_are_refused() {
        let f = Fixture::new();
        fs::write(f.path("system").join("cli.pub"), CLI_PUBLIC_KEY).unwrap();
        fs::write(f.archive(), b"test").unwrap();
        fs::write(signature_path(&f.archive()), CLI_PREHASHED).unwrap();
        assert!(matches!(f.verify(), Verdict::Valid(_)));
        fs::write(signature_path(&f.archive()), CLI_LEGACY).unwrap();
        assert!(matches!(f.verify(), Verdict::InvalidSignature(_)));
    }

    #[test]
    fn unreadable_key_or_revocation_file_fails_to_load() {
        let f = Fixture::new();
        let system = f.path("system");
        fs::write(system.join("broken.pub"), "garbage").unwrap();
        assert!(TrustStore::load(&[&system]).is_err());
        fs::remove_file(system.join("broken.pub")).unwrap();
        fs::write(system.join(REVOKED_FILE), "not-an-id\n").unwrap();
        assert!(TrustStore::load(&[&system]).is_err());
    }

    #[test]
    fn only_pub_files_are_keys_and_missing_dirs_are_empty() {
        let f = Fixture::new();
        let system = f.path("system");
        fs::write(
            system.join("old.asc"),
            "-----BEGIN PGP PUBLIC KEY BLOCK-----",
        )
        .unwrap();
        let store = TrustStore::load(&[&system, &f.path("missing")]).unwrap();
        assert_eq!(store.key_ids().count(), 0);
    }
}
