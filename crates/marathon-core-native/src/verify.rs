//! Detached signature checks for app packages, against the keys in
//! the trusted-keys directory and nothing else.

use std::fs::{self, File};
use std::path::Path;

use pgp::composed::{Deserializable, DetachedSignature, SignedPublicKey};
use pgp::types::KeyDetails;

#[derive(Debug, PartialEq, Eq)]
pub enum Verdict {
    Valid,
    InvalidSignature(String),
    UntrustedKey,
    NoTrustedKeys,
    Failed(String),
}

/// Every key in `*.asc` / `*.gpg` under `dir`, armoured or binary. A key
/// that fails to parse or whose self-signatures don't verify is an error,
/// as `gpg --import` refusing it was.
pub fn load_trusted_keys(dir: &Path) -> Result<Vec<SignedPublicKey>, String> {
    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(e) => return Err(format!("{}: {e}", dir.display())),
    };
    let mut paths: Vec<_> = entries
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| {
            path.is_file()
                && path
                    .extension()
                    .is_some_and(|ext| ext == "asc" || ext == "gpg")
        })
        .collect();
    paths.sort();

    let mut keys = Vec::new();
    for path in paths {
        let name = path.display();
        let file = File::open(&path).map_err(|e| format!("{name}: {e}"))?;
        let (parsed, _) =
            SignedPublicKey::from_reader_many(file).map_err(|e| format!("{name}: {e}"))?;
        for key in parsed {
            let key = key.map_err(|e| format!("{name}: {e}"))?;
            key.verify_bindings().map_err(|e| format!("{name}: {e}"))?;
            keys.push(key);
        }
    }
    Ok(keys)
}

/// Checks `signature` (armoured or binary) over `data`. Only the primary key
/// or a signing-capable subkey named as the issuer can make it valid.
pub fn verify_detached(data: &[u8], signature: &[u8], keys: &[SignedPublicKey]) -> Verdict {
    let sig = match DetachedSignature::from_reader_single(signature) {
        Ok((sig, _)) => sig,
        Err(e) => return Verdict::InvalidSignature(format!("unreadable signature: {e}")),
    };
    let fingerprints = sig.signature.issuer_fingerprint();
    let key_ids = sig.signature.issuer_key_id();
    let names_issuer = |key: &dyn KeyDetails| {
        (fingerprints.is_empty() && key_ids.is_empty())
            || fingerprints.contains(&&key.fingerprint())
            || key_ids.contains(&&key.legacy_key_id())
    };

    let mut issuer_trusted = false;
    let mut last_error = String::new();
    let mut attempt = |result: pgp::errors::Result<()>| {
        issuer_trusted = true;
        result.map_err(|e| last_error = e.to_string()).is_ok()
    };
    for key in keys {
        if names_issuer(&key.primary_key) && attempt(sig.verify(&key.primary_key, data)) {
            return Verdict::Valid;
        }
        for sub in &key.public_subkeys {
            let can_sign = sub.signatures.iter().any(|s| s.key_flags().sign());
            if can_sign && names_issuer(&sub.key) && attempt(sig.verify(&sub.key, data)) {
                return Verdict::Valid;
            }
        }
    }
    if issuer_trusted {
        Verdict::InvalidSignature(last_error)
    } else {
        Verdict::UntrustedKey
    }
}

pub fn verify_file(manifest: &Path, signature: &Path, trusted_keys_dir: &Path) -> Verdict {
    let keys = match load_trusted_keys(trusted_keys_dir) {
        Ok(keys) if keys.is_empty() => return Verdict::NoTrustedKeys,
        Ok(keys) => keys,
        Err(e) => return Verdict::Failed(format!("Failed to import trusted keys: {e}")),
    };
    let data = match fs::read(manifest) {
        Ok(data) => data,
        Err(e) => return Verdict::Failed(format!("{}: {e}", manifest.display())),
    };
    let sig = match fs::read(signature) {
        Ok(sig) => sig,
        Err(e) => return Verdict::Failed(format!("{}: {e}", signature.display())),
    };
    verify_detached(&data, &sig, &keys)
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, reason = "tests")]
mod tests {
    use super::*;
    use pgp::composed::{
        ArmorOptions, EncryptionCaps, KeyType, SecretKeyParamsBuilder, SignedSecretKey,
        SubkeyParamsBuilder,
    };
    use pgp::crypto::hash::HashAlgorithm;
    use pgp::ser::Serialize;
    use pgp::types::Password;
    use rand::thread_rng;

    const MANIFEST: &[u8] = br#"{"id":"org.test.app","name":"Test","entryPoint":"Main.qml"}"#;

    fn key(uid: &str, signing_subkey: bool) -> SignedSecretKey {
        let mut params = SecretKeyParamsBuilder::default();
        params
            .key_type(KeyType::Ed25519Legacy)
            .can_certify(true)
            .can_sign(!signing_subkey)
            .can_encrypt(EncryptionCaps::None)
            .primary_user_id(uid.into());
        if signing_subkey {
            let mut sub = SubkeyParamsBuilder::default();
            sub.key_type(KeyType::Ed25519Legacy)
                .can_sign(true)
                .can_encrypt(EncryptionCaps::None)
                .can_authenticate(false);
            params.subkeys(vec![sub.build().unwrap()]);
        }
        params.build().unwrap().generate(thread_rng()).unwrap()
    }

    fn sign(signer: &dyn pgp::types::SigningKey, data: &[u8]) -> Vec<u8> {
        DetachedSignature::sign_binary_data(
            thread_rng(),
            &Box::new(signer),
            &Password::empty(),
            HashAlgorithm::Sha256,
            data,
        )
        .unwrap()
        .to_armored_bytes(ArmorOptions::default())
        .unwrap()
    }

    fn trust(dir: &Path, name: &str, key: &SignedSecretKey) {
        let public = key.to_public_key();
        let bytes = if Path::new(name).extension().is_some_and(|ext| ext == "asc") {
            public.to_armored_bytes(ArmorOptions::default()).unwrap()
        } else {
            public.to_bytes().unwrap()
        };
        fs::write(dir.join(name), bytes).unwrap();
    }

    #[test]
    fn trusted_primary_key_signature_is_valid() {
        let dir = tempfile::tempdir().unwrap();
        let alice = key("alice@test", false);
        trust(dir.path(), "alice.asc", &alice);
        let keys = load_trusted_keys(dir.path()).unwrap();
        assert_eq!(
            verify_detached(MANIFEST, &sign(&alice.primary_key, MANIFEST), &keys),
            Verdict::Valid
        );
    }

    #[test]
    fn signing_subkey_signature_is_valid() {
        let dir = tempfile::tempdir().unwrap();
        let alice = key("alice@test", true);
        trust(dir.path(), "alice.gpg", &alice);
        let keys = load_trusted_keys(dir.path()).unwrap();
        let sig = sign(&alice.secret_subkeys[0].key, MANIFEST);
        assert_eq!(verify_detached(MANIFEST, &sig, &keys), Verdict::Valid);
    }

    #[test]
    fn tampered_data_is_invalid() {
        let dir = tempfile::tempdir().unwrap();
        let alice = key("alice@test", false);
        trust(dir.path(), "alice.asc", &alice);
        let keys = load_trusted_keys(dir.path()).unwrap();
        let sig = sign(&alice.primary_key, MANIFEST);
        let mut tampered = MANIFEST.to_vec();
        tampered.push(b' ');
        assert!(matches!(
            verify_detached(&tampered, &sig, &keys),
            Verdict::InvalidSignature(_)
        ));
    }

    #[test]
    fn signature_from_other_key_is_untrusted() {
        let dir = tempfile::tempdir().unwrap();
        trust(dir.path(), "alice.asc", &key("alice@test", false));
        let mallory = key("mallory@test", false);
        let keys = load_trusted_keys(dir.path()).unwrap();
        assert_eq!(
            verify_detached(MANIFEST, &sign(&mallory.primary_key, MANIFEST), &keys),
            Verdict::UntrustedKey
        );
    }

    #[test]
    fn garbage_signature_is_invalid() {
        let dir = tempfile::tempdir().unwrap();
        trust(dir.path(), "alice.asc", &key("alice@test", false));
        let keys = load_trusted_keys(dir.path()).unwrap();
        assert!(matches!(
            verify_detached(MANIFEST, b"not a signature", &keys),
            Verdict::InvalidSignature(_)
        ));
    }

    #[test]
    fn only_asc_and_gpg_files_are_keys() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("README"), "not a key").unwrap();
        assert!(load_trusted_keys(dir.path()).unwrap().is_empty());
        assert!(load_trusted_keys(&dir.path().join("missing"))
            .unwrap()
            .is_empty());
    }

    #[test]
    fn unreadable_key_file_fails() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("broken.asc"), "garbage").unwrap();
        assert!(load_trusted_keys(dir.path()).is_err());
    }

    #[test]
    fn verify_file_reports_missing_keys_and_files() {
        let dir = tempfile::tempdir().unwrap();
        let keys = dir.path().join("keys");
        fs::create_dir(&keys).unwrap();
        let manifest = dir.path().join("manifest.json");
        let signature = dir.path().join("SIGNATURE.txt");
        assert_eq!(
            verify_file(&manifest, &signature, &keys),
            Verdict::NoTrustedKeys
        );

        let alice = key("alice@test", false);
        trust(&keys, "alice.asc", &alice);
        assert!(matches!(
            verify_file(&manifest, &signature, &keys),
            Verdict::Failed(_)
        ));

        fs::write(&manifest, MANIFEST).unwrap();
        fs::write(&signature, sign(&alice.primary_key, MANIFEST)).unwrap();
        assert_eq!(verify_file(&manifest, &signature, &keys), Verdict::Valid);
    }
}
