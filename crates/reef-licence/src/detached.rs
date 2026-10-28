// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Detached signatures, used for the revocation list.
//!
//! The revocation list is served as plain JSON so any HTTP client can fetch
//! it, with the signature in a response header. Signing it with the licence
//! key lets the store client cache it and trust the cached copy offline.

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use serde::{Deserialize, Serialize};

use crate::{Error, KeySet, VERSION_PREFIX};

/// Prepended to the body before signing. Tokens sign bytes starting `v1.`,
/// so a detached signature can never be replayed as a token signature or the
/// other way round.
pub const DETACHED_CONTEXT: &[u8] = b"shipwright-detached-signature-v1\n";

impl KeySet {
    /// Verifies a detached signature header `v1.<kid>.<base64url sig>` over
    /// the exact response `body` bytes.
    pub fn verify_detached(&self, body: &[u8], header: &str) -> Result<(), Error> {
        let rest = header
            .trim()
            .strip_prefix(VERSION_PREFIX)
            .ok_or(Error::UnsupportedVersion)?;
        let (kid, sig_b64) = rest
            .split_once('.')
            .ok_or(Error::Malformed("expected v1.<kid>.<sig>"))?;
        let sig = URL_SAFE_NO_PAD
            .decode(sig_b64)
            .map_err(|_| Error::Malformed("signature is not base64url"))?;
        let mut message = DETACHED_CONTEXT.to_vec();
        message.extend_from_slice(body);
        self.verify(kid, &message, &sig)
    }
}

/// Licence ids revoked after refund or chargeback.
///
/// Revocation only reaches phones that go online; an offline phone keeps a
/// one-off licence working. That is the accepted trade-off of offline
/// verification (docs/plan.md, "Payments and licences").
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RevocationList {
    /// When the service produced this list, Unix seconds. Clients keep the
    /// newest list they have seen and ignore older ones, so an attacker
    /// replaying an old (shorter) list cannot un-revoke a licence.
    pub generated_at: i64,
    /// Sorted, de-duplicated licence ids.
    pub revoked: Vec<String>,
}

impl RevocationList {
    /// Parses a list after checking its detached signature. The ids are
    /// sorted and de-duplicated here, so [`RevocationList::is_revoked`]'s
    /// binary search never depends on the server's sort order (an SQL
    /// collation need not match Rust's byte order).
    pub fn verify(body: &[u8], signature_header: &str, keys: &KeySet) -> Result<Self, Error> {
        keys.verify_detached(body, signature_header)?;
        let mut list: Self =
            serde_json::from_slice(body).map_err(|e| Error::InvalidClaims(e.to_string()))?;
        list.revoked.sort_unstable();
        list.revoked.dedup();
        Ok(list)
    }

    pub fn is_revoked(&self, licence_id: &str) -> bool {
        self.revoked
            .binary_search_by(|id| id.as_str().cmp(licence_id))
            .is_ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testkeys::{signer_a, signer_b};

    fn keys() -> KeySet {
        let mut set = KeySet::new();
        set.insert_text(&signer_a().public_key_text()).unwrap();
        set
    }

    #[test]
    fn signed_list_round_trip() {
        let list = RevocationList {
            generated_at: 10,
            revoked: vec!["A".into(), "C".into()],
        };
        let body = serde_json::to_vec(&list).unwrap();
        let header = signer_a().sign_detached(&body);
        let parsed = RevocationList::verify(&body, &header, &keys()).unwrap();
        assert_eq!(parsed, list);
        assert!(parsed.is_revoked("C"));
        assert!(!parsed.is_revoked("B"));
    }

    #[test]
    fn unsorted_lists_are_sorted_before_lookup() {
        // A server whose collation sorts "b" before "B" (or not at all).
        let body = br#"{"generated_at":10,"revoked":["lic_b","LIC_A","lic_a","lic_b","Z"]}"#;
        let header = signer_a().sign_detached(body);
        let parsed = RevocationList::verify(body, &header, &keys()).unwrap();
        assert_eq!(parsed.revoked, ["LIC_A", "Z", "lic_a", "lic_b"]);
        for id in ["lic_b", "LIC_A", "lic_a", "Z"] {
            assert!(parsed.is_revoked(id), "{id}");
        }
        assert!(!parsed.is_revoked("lic_c"));
    }

    #[test]
    fn tampered_body_or_wrong_key_rejected() {
        let body = br#"{"generated_at":10,"revoked":["A"]}"#;
        let header = signer_a().sign_detached(body);
        let tampered = br#"{"generated_at":10,"revoked":[]}"#;
        assert_eq!(
            keys().verify_detached(tampered, &header),
            Err(Error::BadSignature)
        );
        let other = signer_b().sign_detached(body);
        assert_eq!(
            keys().verify_detached(body, &other),
            Err(Error::UnknownKey("test-b".into()))
        );
        assert!(keys().verify_detached(body, "garbage").is_err());
    }

    #[test]
    fn detached_signature_is_not_a_token_signature() {
        // A detached signature over bytes that look like a token's signed
        // prefix must not verify as that token.
        let claims = crate::Claims {
            app: "paid-app".into(),
            exp: None,
            iat: 0,
            kid: "test-a".into(),
            lid: "L1".into(),
            plan: crate::Plan::OneOff,
        };
        let signed_prefix = format!("v1.{}", URL_SAFE_NO_PAD.encode(claims.to_canonical_json()));
        let detached = signer_a().sign_detached(signed_prefix.as_bytes());
        let sig = detached.rsplit_once('.').unwrap().1;
        let forged = format!("{signed_prefix}.{sig}");
        assert_eq!(
            crate::Licence::verify_any_app(&forged, &keys(), &crate::Policy::default(), 0),
            Err(Error::BadSignature)
        );
    }
}
