// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Public keys an app trusts, looked up by key id.

use std::collections::BTreeMap;

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use ed25519_dalek::{Signature, VerifyingKey};

use crate::claims::check_id;
use crate::Error;

/// The verifying keys an app embeds, by key id.
///
/// Holding more than one key is how rotation works: ship the next key in an
/// app update before the service starts signing with it.
#[derive(Debug, Clone, Default)]
pub struct KeySet {
    keys: BTreeMap<String, VerifyingKey>,
}

impl KeySet {
    pub fn new() -> Self {
        Self::default()
    }

    /// Adds a raw 32-byte Ed25519 public key.
    pub fn insert(&mut self, kid: &str, public: [u8; 32]) -> Result<(), Error> {
        check_id("kid", kid).map_err(|e| Error::InvalidKey(format!("bad key id {kid:?}: {e}")))?;
        let key = VerifyingKey::from_bytes(&public)
            .map_err(|_| Error::InvalidKey(format!("{kid}: not a curve point")))?;
        // A small-order key would accept forged signatures under non-strict
        // verification; refuse it outright.
        if key.is_weak() {
            return Err(Error::InvalidKey(format!("{kid}: weak key")));
        }
        self.keys.insert(kid.to_string(), key);
        Ok(())
    }

    /// Adds a key in the text form `<kid>:<base64url public key>`, as printed
    /// by the licence service's `public-key` command.
    pub fn insert_text(&mut self, line: &str) -> Result<(), Error> {
        let (kid, b64) = line
            .trim()
            .split_once(':')
            .ok_or_else(|| Error::InvalidKey("expected <kid>:<base64url key>".into()))?;
        let bytes = URL_SAFE_NO_PAD
            .decode(b64)
            .map_err(|e| Error::InvalidKey(format!("{kid}: bad base64url: {e}")))?;
        let public: [u8; 32] = bytes.try_into().map_err(|b: Vec<u8>| {
            Error::InvalidKey(format!("{kid}: key is {} bytes, not 32", b.len()))
        })?;
        self.insert(kid, public)
    }

    /// Builds a set from `(kid, base64url key)` pairs, the form apps embed as
    /// a `const`.
    pub fn from_embedded(keys: &[(&str, &str)]) -> Result<Self, Error> {
        let mut set = Self::new();
        for (kid, b64) in keys {
            set.insert_text(&format!("{kid}:{b64}"))?;
        }
        Ok(set)
    }

    pub fn is_empty(&self) -> bool {
        self.keys.is_empty()
    }

    pub fn key_ids(&self) -> impl Iterator<Item = &str> {
        self.keys.keys().map(String::as_str)
    }

    /// Verifies `sig` over `message` with key `kid`. Strict verification
    /// rejects non-canonical signatures, so a valid signature cannot be
    /// altered into a second valid one.
    pub(crate) fn verify(&self, kid: &str, message: &[u8], sig: &[u8]) -> Result<(), Error> {
        let key = self
            .keys
            .get(kid)
            .ok_or_else(|| Error::UnknownKey(kid.to_string()))?;
        let sig = Signature::from_slice(sig).map_err(|_| Error::BadSignature)?;
        key.verify_strict(message, &sig)
            .map_err(|_| Error::BadSignature)
    }
}

/// Text form of a public key: `<kid>:<base64url>`.
#[cfg(any(test, feature = "sign"))]
pub(crate) fn public_key_text(kid: &str, key: &VerifyingKey) -> String {
    format!("{kid}:{}", URL_SAFE_NO_PAD.encode(key.as_bytes()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testkeys::signer_a;

    #[test]
    fn parses_text_form() {
        let text = signer_a().public_key_text();
        let mut set = KeySet::new();
        set.insert_text(&text).unwrap();
        assert_eq!(set.key_ids().collect::<Vec<_>>(), ["test-a"]);
    }

    #[test]
    fn rejects_bad_keys() {
        let mut set = KeySet::new();
        assert!(set.insert_text("no-colon").is_err());
        assert!(set.insert_text("k:!!!").is_err());
        assert!(set.insert_text("k:AAAA").is_err(), "wrong length");
        assert!(set.insert("bad id", [1; 32]).is_err());
        // The identity point is small-order: a weak key.
        let mut identity = [0u8; 32];
        identity[0] = 1;
        assert!(set.insert("k", identity).is_err());
        assert!(set.is_empty());
    }

    #[test]
    fn from_embedded_builds_set() {
        let text = signer_a().public_key_text();
        let (kid, b64) = text.split_once(':').unwrap();
        let set = KeySet::from_embedded(&[(kid, b64)]).unwrap();
        assert!(!set.is_empty());
    }
}
