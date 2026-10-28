// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Declares `cfg(release_build)`, which a release build sets in RUSTFLAGS
//! and `config.rs` checks the built-in relay URL against.

fn main() {
    println!("cargo::rustc-check-cfg=cfg(release_build)");
    println!("cargo::rerun-if-env-changed=PILOT_RELAY_URL");
    println!("cargo::rerun-if-changed=build.rs");
}
