// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! reef-backend: the Rust half of the Reef store client.
//!
//! The QML UI (apps/reef/ui) talks to one backend object exposed through
//! CXX-Qt (`apps/reef/src/bridge.rs`); that object is a thin shell over
//! this crate:
//!
//! * [`catalogue`]: the per-arch catalogue, hiding packages this phone's
//!   processor cannot run.
//! * [`index`]: the store index (catalogue v2): the same catalogue from a
//!   signed index, each app's details merged when they are fetched.
//! * [`licences`]: storage and offline verification of licence tokens.
//! * [`claim_codes`]: the codes that fetch a licence bought on the web.
//! * [`licenced`]: the session-bus service that hands tokens to apps
//!   (`shipwright-reef-licenced`, src/bin).
//! * [`store`]: the catalogue joined with install state, for the UI.
//!
//! No networking lives here: the UI layer downloads the catalogue, tokens
//! and revocation list and passes the bytes in.

pub mod catalogue;
pub mod claim_codes;
pub mod index;
pub mod licenced;
pub mod licences;
pub mod store;
