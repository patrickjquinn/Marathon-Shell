// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

//! Embeds the licence keys named by `SHIPWRIGHT_LICENCE_KEYS` at build time
//! (`reef_licence::build`) as the value of `EMBEDDED_KEYS`.

fn main() {
    reef_licence::build::embed_keys();
}
