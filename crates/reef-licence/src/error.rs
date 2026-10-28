// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT OR Apache-2.0

use std::fmt;

/// Why a token, key or detached signature was rejected.
///
/// Variants are coarse on purpose: an app shows "licence invalid" for all of
/// the format errors, and only [`Error::Expired`], [`Error::NotYetValid`] and
/// [`Error::WrongApp`] need their own wording.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Error {
    /// Not three dot-separated segments, too long, or bad base64.
    Malformed(&'static str),
    /// A version prefix this verifier does not know (for example `v2`).
    UnsupportedVersion,
    /// Payload decoded but is not valid claims JSON.
    InvalidClaims(String),
    /// Payload is valid JSON but not in canonical form.
    NonCanonical,
    /// No embedded key has the token's key id.
    UnknownKey(String),
    /// Signature does not verify under the named key.
    BadSignature,
    /// Signed for a different app id.
    WrongApp { expected: String, found: String },
    /// Issued in the future, beyond the allowed clock skew.
    NotYetValid { issued_at: i64 },
    /// Past its expiry and, for subscriptions, past the grace period too.
    Expired { expired_at: i64 },
    /// A public or private key could not be parsed.
    InvalidKey(String),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Malformed(why) => write!(f, "malformed licence token: {why}"),
            Error::UnsupportedVersion => write!(f, "unsupported licence token version"),
            Error::InvalidClaims(why) => write!(f, "invalid licence claims: {why}"),
            Error::NonCanonical => write!(f, "licence payload is not canonical"),
            Error::UnknownKey(kid) => write!(f, "licence signed by unknown key {kid}"),
            Error::BadSignature => write!(f, "licence signature does not verify"),
            Error::WrongApp { expected, found } => {
                write!(f, "licence is for {found}, not {expected}")
            }
            Error::NotYetValid { issued_at } => {
                write!(f, "licence issued in the future (at {issued_at})")
            }
            Error::Expired { expired_at } => write!(f, "licence expired at {expired_at}"),
            Error::InvalidKey(why) => write!(f, "invalid key: {why}"),
        }
    }
}

impl std::error::Error for Error {}
