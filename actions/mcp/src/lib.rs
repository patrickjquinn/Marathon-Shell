// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! keel-mcp (ADR-0018, `docs/specs/pilot.md` 9.4): one MCP server for every
//! Keel app on the device. It reads the installed manifests
//! (`/usr/share/keel/actions/*.json`) and asks running apps for theirs,
//! serves them as MCP tools, resources and prompts (rmcp; MCP 2026-07-28,
//! and 2025-11-25 and earlier through `initialize`), and turns tool calls
//! into `org.shipwright.Keel.Actions` calls on the session bus, validating
//! arguments before and results after.

pub mod backend;
pub mod catalogue;
pub mod server;

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

pub use server::KeelMcp;

/// Keeps `server`'s catalogue current: rescans `dirs` every 2 s (rebuilding
/// when a file appears, changes or goes) and asks running apps for their
/// manifests every `probe` interval.
pub async fn watch(
    server: KeelMcp,
    backend: Arc<dyn backend::Backend>,
    dirs: Vec<PathBuf>,
    probe: Duration,
) {
    let mut last_files = None;
    let mut last_running = Vec::new();
    let mut next_probe = tokio::time::Instant::now();
    loop {
        let files = catalogue::scan(&dirs);
        let mut changed = last_files.as_ref() != Some(&files);
        if tokio::time::Instant::now() >= next_probe {
            let running = backend.running_manifests().await;
            changed |= running != last_running;
            last_running = running;
            next_probe = tokio::time::Instant::now() + probe;
        }
        if changed {
            let built = catalogue::Catalogue::build(catalogue::load(&files), last_running.clone());
            eprintln!(
                "keel-mcp: {} app(s), {} tool(s)",
                built.apps.len(),
                built.tools.len()
            );
            server.set_catalogue(built);
            last_files = Some(files);
        }
        tokio::time::sleep(Duration::from_secs(2)).await;
    }
}
