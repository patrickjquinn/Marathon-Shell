// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Issuing tokens. Compiled for the `sign` feature (the licence service) and
//! for this crate's own tests; apps and the store client never get it.

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use ed25519_dalek::{Signer as _, SigningKey};

use crate::claims::check_id;
use crate::detached::DETACHED_CONTEXT;
use crate::keys::public_key_text;
use crate::{Claims, Error, VERSION_PREFIX};

/// A signing key and the key id it signs as.
pub struct Signer {
    kid: String,
    key: SigningKey,
}

impl std::fmt::Debug for Signer {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Never print the secret.
        f.debug_struct("Signer")
            .field("kid", &self.kid)
            .finish_non_exhaustive()
    }
}

impl Signer {
    /// From a 32-byte Ed25519 seed (the RFC 8032 private key).
    pub fn from_seed(kid: &str, seed: [u8; 32]) -> Result<Self, Error> {
        check_id("kid", kid).map_err(|e| Error::InvalidKey(format!("bad key id {kid:?}: {e}")))?;
        Ok(Self {
            kid: kid.to_string(),
            key: SigningKey::from_bytes(&seed),
        })
    }

    /// From the seed as unpadded base64url, the form the licence service
    /// keeps in its key file. Surrounding whitespace is ignored.
    pub fn from_seed_text(kid: &str, text: &str) -> Result<Self, Error> {
        let bytes = URL_SAFE_NO_PAD
            .decode(text.trim())
            .map_err(|e| Error::InvalidKey(format!("seed is not base64url: {e}")))?;
        let seed: [u8; 32] = bytes.try_into().map_err(|b: Vec<u8>| {
            Error::InvalidKey(format!("seed is {} bytes, not 32", b.len()))
        })?;
        Self::from_seed(kid, seed)
    }

    pub fn kid(&self) -> &str {
        &self.kid
    }

    /// `<kid>:<base64url public key>`, for embedding in apps.
    pub fn public_key_text(&self) -> String {
        public_key_text(&self.kid, &self.key.verifying_key())
    }

    /// Signs `claims` into a v1 token. Refuses claims that a verifier would
    /// reject, and claims naming a different key id.
    pub fn issue(&self, claims: &Claims) -> Result<String, Error> {
        if claims.kid != self.kid {
            return Err(Error::InvalidClaims(format!(
                "claims name key {}, signer is {}",
                claims.kid, self.kid
            )));
        }
        claims.validate()?;
        Ok(self.sign_raw_payload(&claims.to_canonical_json()))
    }

    /// Signs payload bytes as they are, without checking them. [`issue`]
    /// calls it after validating the claims; tests call it directly for a
    /// validly signed but otherwise bad token.
    ///
    /// [`issue`]: Signer::issue
    pub(crate) fn sign_raw_payload(&self, payload: &[u8]) -> String {
        let signed = format!("{VERSION_PREFIX}{}", URL_SAFE_NO_PAD.encode(payload));
        let sig = self.key.sign(signed.as_bytes());
        format!("{signed}.{}", URL_SAFE_NO_PAD.encode(sig.to_bytes()))
    }

    /// Detached signature over `body`, in the form
    /// [`crate::KeySet::verify_detached`] accepts: `v1.<kid>.<base64url sig>`.
    pub fn sign_detached(&self, body: &[u8]) -> String {
        let mut message = DETACHED_CONTEXT.to_vec();
        message.extend_from_slice(body);
        let sig = self.key.sign(&message);
        format!(
            "{VERSION_PREFIX}{}.{}",
            self.kid,
            URL_SAFE_NO_PAD.encode(sig.to_bytes())
        )
    }
}
