// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT OR Apache-2.0

//! The signed payload and its canonical JSON form.

use serde::{Deserialize, Serialize};

use crate::Error;

/// Longest app id, licence id or key id accepted. Keeps tokens small enough
/// to pass on a command line or in a D-Bus property.
pub const MAX_ID_LEN: usize = 128;

/// How the licence was bought (docs/plan.md, "Pricing model").
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Plan {
    /// Bought once. Usually has no expiry.
    OneOff,
    /// Hosted service. Always has an expiry, which the service moves forward
    /// on each renewal and the app refreshes when online.
    Subscription,
}

/// What a licence token asserts.
///
/// Field order here is the canonical key order (lexicographic): serde
/// serialises struct fields in declaration order, and canonical form is
/// checked by re-encoding, so reordering these fields changes the format.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Claims {
    /// App id the licence unlocks, for example `shipwright-shoal-bridge-airpods-ui`.
    pub app: String,
    /// Expiry, Unix seconds. Required for subscriptions.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub exp: Option<i64>,
    /// Issued at, Unix seconds.
    pub iat: i64,
    /// Id of the key that signed this token.
    pub kid: String,
    /// Licence id. Device-independent: the same licence id is valid on any
    /// phone the buyer owns, and is the handle for refresh and revocation.
    pub lid: String,
    pub plan: Plan,
}

impl Claims {
    /// The canonical JSON bytes of these claims.
    ///
    /// # Panics
    ///
    /// Never in practice: serialising a struct of strings and integers
    /// cannot fail.
    pub fn to_canonical_json(&self) -> Vec<u8> {
        // Serialising a struct of strings and integers cannot fail.
        serde_json::to_vec(self).expect("claims serialise")
    }

    /// Parses claims, requiring the input to be exactly the canonical encoding.
    pub(crate) fn from_canonical_json(bytes: &[u8]) -> Result<Self, Error> {
        let claims: Claims =
            serde_json::from_slice(bytes).map_err(|e| Error::InvalidClaims(e.to_string()))?;
        if claims.to_canonical_json() != bytes {
            return Err(Error::NonCanonical);
        }
        Ok(claims)
    }

    /// Checks the rules the JSON schema cannot express.
    pub fn validate(&self) -> Result<(), Error> {
        check_id("app", &self.app)?;
        check_id("lid", &self.lid)?;
        check_id("kid", &self.kid)?;
        if self.iat < 0 {
            return Err(Error::InvalidClaims("iat is negative".into()));
        }
        match (self.plan, self.exp) {
            (Plan::Subscription, None) => {
                return Err(Error::InvalidClaims("subscription without exp".into()))
            }
            (_, Some(exp)) if exp <= self.iat => {
                return Err(Error::InvalidClaims("exp is not after iat".into()))
            }
            _ => {}
        }
        Ok(())
    }
}

/// Identifiers are restricted so canonical JSON never needs escapes, which
/// would otherwise give one string several valid encodings.
pub(crate) fn check_id(field: &str, value: &str) -> Result<(), Error> {
    let ok = !value.is_empty()
        && value.len() <= MAX_ID_LEN
        && value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-'));
    if ok {
        Ok(())
    } else {
        Err(Error::InvalidClaims(format!(
            "{field} must be 1 to {MAX_ID_LEN} characters of [A-Za-z0-9._-]"
        )))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn one_off() -> Claims {
        Claims {
            app: "shoal-bridge".into(),
            exp: None,
            iat: 1_790_000_000,
            kid: "k1".into(),
            lid: "L0123".into(),
            plan: Plan::OneOff,
        }
    }

    #[test]
    fn canonical_json_is_sorted_and_compact() {
        let json = String::from_utf8(one_off().to_canonical_json()).unwrap();
        assert_eq!(
            json,
            r#"{"app":"shoal-bridge","iat":1790000000,"kid":"k1","lid":"L0123","plan":"one_off"}"#
        );
        let mut sub = one_off();
        sub.plan = Plan::Subscription;
        sub.exp = Some(1_790_086_400);
        let json = String::from_utf8(sub.to_canonical_json()).unwrap();
        assert_eq!(
            json,
            r#"{"app":"shoal-bridge","exp":1790086400,"iat":1790000000,"kid":"k1","lid":"L0123","plan":"subscription"}"#
        );
    }

    #[test]
    fn round_trips_canonical_form() {
        let c = one_off();
        assert_eq!(Claims::from_canonical_json(&c.to_canonical_json()), Ok(c));
    }

    #[test]
    fn rejects_non_canonical_encodings() {
        for json in [
            // Whitespace.
            r#"{"app":"shoal-bridge", "iat":1790000000,"kid":"k1","lid":"L0123","plan":"one_off"}"#,
            // Key order.
            r#"{"iat":1790000000,"app":"shoal-bridge","kid":"k1","lid":"L0123","plan":"one_off"}"#,
            // Explicit null instead of omission.
            r#"{"app":"shoal-bridge","exp":null,"iat":1790000000,"kid":"k1","lid":"L0123","plan":"one_off"}"#,
            // Escaped character that decodes to the same string.
            r#"{"app":"shoal\u002dbridge","iat":1790000000,"kid":"k1","lid":"L0123","plan":"one_off"}"#,
        ] {
            assert_eq!(
                Claims::from_canonical_json(json.as_bytes()),
                Err(Error::NonCanonical),
                "{json}"
            );
        }
    }

    #[test]
    fn rejects_unknown_and_duplicate_fields() {
        let unknown = r#"{"app":"a","iat":1,"kid":"k","lid":"l","plan":"one_off","x":1}"#;
        assert!(matches!(
            Claims::from_canonical_json(unknown.as_bytes()),
            Err(Error::InvalidClaims(_))
        ));
        let dup = r#"{"app":"a","app":"b","iat":1,"kid":"k","lid":"l","plan":"one_off"}"#;
        assert!(Claims::from_canonical_json(dup.as_bytes()).is_err());
    }

    #[test]
    fn validates_semantics() {
        assert_eq!(one_off().validate(), Ok(()));

        let mut sub = one_off();
        sub.plan = Plan::Subscription;
        assert!(sub.validate().is_err(), "subscription needs exp");

        let mut c = one_off();
        c.exp = Some(c.iat);
        assert!(c.validate().is_err(), "exp must be after iat");

        for bad in [
            "",
            "has space",
            "slash/",
            "ünï",
            &"x".repeat(MAX_ID_LEN + 1),
        ] {
            let mut c = one_off();
            c.app = bad.to_string();
            assert!(c.validate().is_err(), "{bad:?}");
        }
    }
}
