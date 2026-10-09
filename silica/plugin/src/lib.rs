// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! Native part of Keel's Silica module. The `QObject` bridges live in
//! `ambience` and `linkparser`; `palette`, `config` and `linkify` are plain Rust and unit-tested with
//! `cargo test`.

pub mod ambience;
pub mod config;
pub mod linkify;
pub mod linkparser;
pub mod palette;
