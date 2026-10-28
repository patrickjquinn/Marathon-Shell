// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Embeds the licence keys named by `SHIPWRIGHT_LICENCE_KEYS` at build time
//! (`reef_licence::build`) as the value of `EMBEDDED_KEYS`.

fn main() {
    reef_licence::build::embed_keys();
}
