// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Token decoding and offline verification.

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;

use crate::{Claims, Error, KeySet, Plan};

/// Every v1 token starts with this, and it is part of the signed bytes.
pub const VERSION_PREFIX: &str = "v1.";

/// Tokens are about 250 bytes; anything much longer is not ours and is
/// rejected before any decoding.
pub const MAX_TOKEN_LEN: usize = 2048;

/// Time rules applied after the signature checks out.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Policy {
    /// How far the phone's clock may be off, in seconds. Applied to both
    /// issue time and expiry. Phones without network time drift, and a
    /// licence must not flicker invalid because of it.
    pub clock_skew_secs: i64,
    /// How long a subscription stays usable past its expiry, in seconds, so
    /// an app used offline for a while keeps working until it can refresh.
    /// One-off licences with an expiry get no grace.
    pub subscription_grace_secs: i64,
}

impl Default for Policy {
    fn default() -> Self {
        Self {
            clock_skew_secs: 5 * 60,
            subscription_grace_secs: 7 * 24 * 60 * 60,
        }
    }
}

/// Whether a verified licence is fully current or running on grace.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Standing {
    Active,
    /// Subscription past `expired_at` but before `grace_ends`: the app keeps
    /// working and should refresh the token (and nag if refresh fails).
    Grace {
        expired_at: i64,
        grace_ends: i64,
    },
}

/// A token that passed every check.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Licence {
    pub claims: Claims,
    pub standing: Standing,
}

impl Licence {
    /// Verifies `token` for `app_id` at Unix time `now`.
    ///
    /// This is the call an app makes. The Reef client, which holds licences
    /// for many apps, uses [`Licence::verify_any_app`].
    pub fn verify(
        token: &str,
        app_id: &str,
        keys: &KeySet,
        policy: &Policy,
        now: i64,
    ) -> Result<Self, Error> {
        // The app is checked before time (README, "Verification order"): a
        // token for another app reports WrongApp even when it has expired.
        let claims = verify_signed(token, keys)?;
        if claims.app != app_id {
            return Err(Error::WrongApp {
                expected: app_id.to_string(),
                found: claims.app,
            });
        }
        let standing = standing(&claims, policy, now)?;
        Ok(Self { claims, standing })
    }

    /// Verifies signature, format and time, without checking which app the
    /// token is for.
    pub fn verify_any_app(
        token: &str,
        keys: &KeySet,
        policy: &Policy,
        now: i64,
    ) -> Result<Self, Error> {
        let claims = verify_signed(token, keys)?;
        let standing = standing(&claims, policy, now)?;
        Ok(Self { claims, standing })
    }
}

impl Claims {
    /// Reads a token's claims **without verifying anything**: no signature,
    /// no canonical form, no time. For display only, and as the handle for a
    /// refresh of a token whose signature already verified but which has
    /// expired (so `verify` no longer returns its claims). Never use the
    /// result to grant anything.
    pub fn peek_unverified(token: &str) -> Option<Claims> {
        let (_, payload, _) = split(token.trim()).ok()?;
        serde_json::from_slice(&payload).ok()
    }
}

/// Signature, canonical form and semantic checks: everything but the app id
/// and time.
fn verify_signed(token: &str, keys: &KeySet) -> Result<Claims, Error> {
    let (signed, payload, sig) = split(token)?;
    // The payload is parsed before the signature is checked only to learn
    // the key id; nothing in it is trusted until verification succeeds.
    let claims: Claims =
        serde_json::from_slice(&payload).map_err(|e| Error::InvalidClaims(e.to_string()))?;
    keys.verify(&claims.kid, signed.as_bytes(), &sig)?;
    let claims = Claims::from_canonical_json(&payload)?;
    claims.validate()?;
    Ok(claims)
}

/// Splits a token into the signed prefix, the decoded payload and the
/// decoded signature.
fn split(token: &str) -> Result<(&str, Vec<u8>, Vec<u8>), Error> {
    if token.len() > MAX_TOKEN_LEN {
        return Err(Error::Malformed("too long"));
    }
    let Some(rest) = token.strip_prefix(VERSION_PREFIX) else {
        return match token.split_once('.') {
            Some((v, _)) if v.starts_with('v') => Err(Error::UnsupportedVersion),
            _ => Err(Error::Malformed("missing version prefix")),
        };
    };
    let (payload_b64, sig_b64) = rest
        .split_once('.')
        .ok_or(Error::Malformed("expected three segments"))?;
    if sig_b64.contains('.') {
        return Err(Error::Malformed("expected three segments"));
    }
    let payload = URL_SAFE_NO_PAD
        .decode(payload_b64)
        .map_err(|_| Error::Malformed("payload is not base64url"))?;
    let sig = URL_SAFE_NO_PAD
        .decode(sig_b64)
        .map_err(|_| Error::Malformed("signature is not base64url"))?;
    let signed = &token[..VERSION_PREFIX.len() + payload_b64.len()];
    Ok((signed, payload, sig))
}

fn standing(claims: &Claims, policy: &Policy, now: i64) -> Result<Standing, Error> {
    let skew = policy.clock_skew_secs.max(0);
    if claims.iat > now.saturating_add(skew) {
        return Err(Error::NotYetValid {
            issued_at: claims.iat,
        });
    }
    let Some(exp) = claims.exp else {
        return Ok(Standing::Active);
    };
    let hard_end = exp.saturating_add(skew);
    if now <= hard_end {
        return Ok(Standing::Active);
    }
    if claims.plan == Plan::Subscription {
        let grace_ends = hard_end.saturating_add(policy.subscription_grace_secs.max(0));
        if now <= grace_ends {
            return Ok(Standing::Grace {
                expired_at: exp,
                grace_ends,
            });
        }
    }
    Err(Error::Expired { expired_at: exp })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testkeys::{signer_a, signer_b};

    const T0: i64 = 1_790_000_000;
    const DAY: i64 = 86_400;

    fn keys() -> KeySet {
        let mut set = KeySet::new();
        set.insert_text(&signer_a().public_key_text()).unwrap();
        set
    }

    fn claims(plan: Plan, exp: Option<i64>) -> Claims {
        Claims {
            app: "shoal-bridge".into(),
            exp,
            iat: T0,
            kid: "test-a".into(),
            lid: "LIC-0001".into(),
            plan,
        }
    }

    fn one_off_token() -> String {
        signer_a().issue(&claims(Plan::OneOff, None)).unwrap()
    }

    fn verify(token: &str, now: i64) -> Result<Licence, Error> {
        Licence::verify(token, "shoal-bridge", &keys(), &Policy::default(), now)
    }

    #[test]
    fn accepts_valid_one_off() {
        let lic = verify(&one_off_token(), T0 + 400 * DAY).unwrap();
        assert_eq!(lic.standing, Standing::Active);
        assert_eq!(lic.claims.lid, "LIC-0001");
    }

    #[test]
    fn token_has_three_segments_and_prefix() {
        let token = one_off_token();
        assert!(token.starts_with("v1."));
        assert_eq!(token.split('.').count(), 3);
        assert!(token.len() < 300, "{} bytes", token.len());
    }

    #[test]
    fn wrong_app() {
        let err = Licence::verify(
            &one_off_token(),
            "other-app",
            &keys(),
            &Policy::default(),
            T0,
        )
        .unwrap_err();
        assert!(matches!(err, Error::WrongApp { .. }));
    }

    #[test]
    fn peek_reads_claims_without_verifying() {
        let token = one_off_token();
        assert_eq!(
            Claims::peek_unverified(&token).unwrap().lid,
            "LIC-0001".to_string()
        );
        // A forged signature still peeks: that is why it is display-only.
        let forged = format!("{}.AAAA", token.rsplit_once('.').unwrap().0);
        assert!(Claims::peek_unverified(&forged).is_some());
        assert!(Claims::peek_unverified("v1.garbage").is_none());
        assert!(Claims::peek_unverified("nonsense").is_none());
    }

    #[test]
    fn wrong_app_is_reported_before_time() {
        // L-03: an expired token for another app says WrongApp, not Expired,
        // as the README's verification order states.
        let token = crate::testkeys::signer_a()
            .issue(&claims(Plan::OneOff, Some(T0 + DAY)))
            .unwrap();
        let later = T0 + 30 * DAY;
        assert!(matches!(
            Licence::verify(&token, "shoal-bridge", &keys(), &Policy::default(), later),
            Err(Error::Expired { .. })
        ));
        assert!(matches!(
            Licence::verify(&token, "other-app", &keys(), &Policy::default(), later),
            Err(Error::WrongApp { .. })
        ));
    }

    #[test]
    fn wrong_key_same_kid_fails_signature() {
        // Signed by B's secret but claiming A's key id.
        let forged = crate::sign::Signer::from_seed("test-a", crate::testkeys::SEED_B)
            .unwrap()
            .issue(&claims(Plan::OneOff, None))
            .unwrap();
        assert_eq!(verify(&forged, T0), Err(Error::BadSignature));
    }

    #[test]
    fn unknown_key_id() {
        let mut c = claims(Plan::OneOff, None);
        c.kid = "test-b".into();
        let token = signer_b().issue(&c).unwrap();
        assert_eq!(verify(&token, T0), Err(Error::UnknownKey("test-b".into())));
    }

    #[test]
    fn rotation_accepts_either_key() {
        let mut set = keys();
        set.insert_text(&signer_b().public_key_text()).unwrap();
        let mut c = claims(Plan::OneOff, None);
        c.kid = "test-b".into();
        let token = signer_b().issue(&c).unwrap();
        assert!(Licence::verify(&token, "shoal-bridge", &set, &Policy::default(), T0).is_ok());
        assert!(Licence::verify(
            &one_off_token(),
            "shoal-bridge",
            &set,
            &Policy::default(),
            T0
        )
        .is_ok());
    }

    #[test]
    fn tampered_payload_fails() {
        let token = one_off_token();
        let (_, rest) = token.split_once('.').unwrap();
        let (_, sig) = rest.split_once('.').unwrap();
        // Same signature, different claims (another app).
        let mut c = claims(Plan::OneOff, None);
        c.app = "paid-app".into();
        let payload = URL_SAFE_NO_PAD.encode(c.to_canonical_json());
        let tampered = format!("v1.{payload}.{sig}");
        assert_eq!(
            Licence::verify_any_app(&tampered, &keys(), &Policy::default(), T0),
            Err(Error::BadSignature)
        );
    }

    #[test]
    fn every_single_character_flip_is_rejected() {
        let token = one_off_token();
        let bytes = token.as_bytes();
        for i in 0..bytes.len() {
            let mut flipped = bytes.to_vec();
            flipped[i] = if bytes[i] == b'A' { b'B' } else { b'A' };
            let Ok(s) = String::from_utf8(flipped) else {
                continue;
            };
            if s == token {
                continue;
            }
            assert!(verify(&s, T0).is_err(), "flip at {i} accepted: {s}");
        }
    }

    #[test]
    fn tampered_signature_fails() {
        let token = one_off_token();
        let (head, sig) = token.rsplit_once('.').unwrap();
        let mut raw = URL_SAFE_NO_PAD.decode(sig).unwrap();
        raw[10] ^= 1;
        let bad = format!("{head}.{}", URL_SAFE_NO_PAD.encode(raw));
        assert_eq!(verify(&bad, T0), Err(Error::BadSignature));
    }

    #[test]
    fn signature_valid_but_non_canonical_payload_rejected() {
        // Sign a non-canonical payload directly: only a key holder could do
        // this, but the verifier must still refuse a second encoding.
        let payload = br#"{"app":"shoal-bridge", "iat":1790000000,"kid":"test-a","lid":"LIC-0001","plan":"one_off"}"#;
        let token = signer_a().sign_raw_payload(payload);
        assert_eq!(verify(&token, T0), Err(Error::NonCanonical));
    }

    #[test]
    fn malformed_tokens() {
        assert_eq!(
            verify("", T0),
            Err(Error::Malformed("missing version prefix"))
        );
        assert_eq!(verify("v2.abc.def", T0), Err(Error::UnsupportedVersion));
        assert!(matches!(verify("v1.abc", T0), Err(Error::Malformed(_))));
        assert!(matches!(verify("v1.a.b.c", T0), Err(Error::Malformed(_))));
        assert!(matches!(verify("v1.***.abc", T0), Err(Error::Malformed(_))));
        let long = format!("v1.{}.x", "A".repeat(MAX_TOKEN_LEN));
        assert_eq!(verify(&long, T0), Err(Error::Malformed("too long")));
        // Padded base64 is not the canonical encoding.
        let token = one_off_token();
        assert!(verify(&format!("{token}="), T0).is_err());
    }

    #[test]
    fn not_yet_valid_respects_skew() {
        let token = one_off_token();
        let skew = Policy::default().clock_skew_secs;
        assert!(verify(&token, T0 - skew).is_ok());
        assert_eq!(
            verify(&token, T0 - skew - 1),
            Err(Error::NotYetValid { issued_at: T0 })
        );
    }

    #[test]
    fn one_off_with_expiry_has_no_grace() {
        let exp = T0 + 30 * DAY;
        let token = signer_a().issue(&claims(Plan::OneOff, Some(exp))).unwrap();
        let skew = Policy::default().clock_skew_secs;
        assert_eq!(
            verify(&token, exp + skew).unwrap().standing,
            Standing::Active
        );
        assert_eq!(
            verify(&token, exp + skew + 1),
            Err(Error::Expired { expired_at: exp })
        );
    }

    #[test]
    fn subscription_grace_period() {
        let exp = T0 + 30 * DAY;
        let token = signer_a()
            .issue(&claims(Plan::Subscription, Some(exp)))
            .unwrap();
        let p = Policy::default();
        assert_eq!(verify(&token, exp).unwrap().standing, Standing::Active);
        let grace_ends = exp + p.clock_skew_secs + p.subscription_grace_secs;
        assert_eq!(
            verify(&token, exp + p.clock_skew_secs + 1)
                .unwrap()
                .standing,
            Standing::Grace {
                expired_at: exp,
                grace_ends
            }
        );
        assert!(matches!(
            verify(&token, grace_ends).unwrap().standing,
            Standing::Grace { .. }
        ));
        assert_eq!(
            verify(&token, grace_ends + 1),
            Err(Error::Expired { expired_at: exp })
        );
    }

    #[test]
    fn zero_policy_is_strict() {
        let exp = T0 + DAY;
        let token = signer_a()
            .issue(&claims(Plan::Subscription, Some(exp)))
            .unwrap();
        let strict = Policy {
            clock_skew_secs: 0,
            subscription_grace_secs: 0,
        };
        assert!(Licence::verify(&token, "shoal-bridge", &keys(), &strict, exp).is_ok());
        assert!(Licence::verify(&token, "shoal-bridge", &keys(), &strict, exp + 1).is_err());
    }

    #[test]
    fn signer_refuses_invalid_claims() {
        let bad = claims(Plan::Subscription, None);
        assert!(signer_a().issue(&bad).is_err());
        let mut other_kid = claims(Plan::OneOff, None);
        other_kid.kid = "test-b".into();
        assert!(signer_a().issue(&other_kid).is_err());
    }

    #[test]
    fn issuing_is_deterministic() {
        // Ed25519 signatures are deterministic and the payload is canonical,
        // so the same claims always give the same token.
        assert_eq!(one_off_token(), one_off_token());
    }
}
