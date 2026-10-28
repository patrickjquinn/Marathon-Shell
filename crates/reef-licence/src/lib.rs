// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT OR Apache-2.0

//! reef-licence: the licence token that Reef apps verify offline.
//!
//! docs/plan.md ("Payments and licences") asks for an Ed25519-signed token
//! carrying app id, plan, expiry and a device-independent licence id, which an
//! app verifies against an embedded public key without network access. This
//! crate is that format and its verifier. The issuing side (`Signer`) sits
//! behind the `sign` feature so apps never ship it.
//!
//! # Wire format (version 1)
//!
//! ```text
//! v1.<base64url(payload)>.<base64url(signature)>
//! ```
//!
//! * `payload` is canonical JSON of [`Claims`]: keys in lexicographic order, no
//!   whitespace, integers only, absent optional fields omitted (never `null`),
//!   identifier strings limited to `[A-Za-z0-9._-]` so no escaping is possible.
//! * `signature` is Ed25519 over the ASCII bytes `v1.<base64url(payload)>`, so
//!   the verifier checks exactly the bytes it received and never has to
//!   re-serialise before checking the signature.
//! * base64url is unpadded (RFC 4648 section 5) and trailing bits must be zero.
//!
//! Why canonical JSON rather than CBOR: the payload is six short fields, JSON
//! keeps tokens debuggable with `base64 -d`, the licence service and the store
//! client already depend on `serde_json`, and canonical form is enforced by
//! re-encoding the parsed claims and requiring byte equality. That makes every
//! licence have exactly one valid encoding, so two tokens for the same claims
//! cannot differ, and a token cannot smuggle unknown or duplicate fields past
//! the verifier. CBOR would save a few dozen bytes for a new dependency and a
//! harder-to-inspect format.
//!
//! The `v1` prefix versions the whole format. A future `v2` can change any of
//! the above; a v1 verifier rejects it as [`Error::UnsupportedVersion`].
//!
//! # Key rotation
//!
//! Every token names the key that signed it (`kid`). Apps embed a [`KeySet`]
//! holding the current and next public keys, so the service can switch signing
//! keys ahead of retiring the old one.

#[cfg(feature = "build")]
pub mod build;
mod claims;
mod detached;
mod error;
pub mod handoff;
mod keys;
#[cfg(any(test, feature = "sign"))]
#[cfg_attr(
    not(feature = "sign"),
    allow(
        dead_code,
        reason = "without the sign feature, signing is compiled for tests only"
    )
)]
mod sign;
mod token;

pub use claims::{Claims, Plan};
pub use detached::{RevocationList, DETACHED_CONTEXT};
pub use error::Error;
pub use keys::KeySet;
#[cfg(feature = "sign")]
pub use sign::Signer;
pub use token::{Licence, Policy, Standing, MAX_TOKEN_LEN, VERSION_PREFIX};

#[cfg(test)]
pub(crate) mod testkeys {
    //! Fixed test keys. Never use these outside tests: their seeds are public.
    use crate::sign::Signer;

    pub const SEED_A: [u8; 32] = [7; 32];
    pub const SEED_B: [u8; 32] = [9; 32];

    pub fn signer_a() -> Signer {
        Signer::from_seed("test-a", SEED_A).unwrap()
    }

    pub fn signer_b() -> Signer {
        Signer::from_seed("test-b", SEED_B).unwrap()
    }
}
