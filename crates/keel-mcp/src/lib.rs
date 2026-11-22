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
pub mod guard;
pub mod peer;
pub mod server;

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use inotify::{Inotify, WatchMask};
use tokio::sync::mpsc;

pub use server::KeelMcp;

/// How long changes must have stopped before the catalogue is rebuilt: an
/// install writes a file in several steps.
const SETTLE: Duration = Duration::from_millis(250);

/// Keeps `server`'s catalogue current: rebuilds it when a file in `dirs`
/// appears, changes or goes (inotify), and asks running apps for their
/// manifests every `probe` interval.
#[allow(clippy::print_stderr, reason = "journald collects stderr")]
pub async fn watch(
    server: KeelMcp,
    backend: Arc<dyn backend::Backend>,
    dirs: Vec<PathBuf>,
    probe: Duration,
) {
    let mut dir_changes = watch_dirs(&dirs);
    let mut files = None;
    let mut running = Vec::new();
    let mut asking = true;
    loop {
        let scanned = catalogue::scan(&dirs);
        let mut changed = files.as_ref() != Some(&scanned);
        if asking {
            let now = backend.running_manifests().await;
            changed |= now != running;
            running = now;
        }
        if changed {
            let built = catalogue::Catalogue::build(catalogue::load(&scanned), running.clone());
            eprintln!(
                "keel-mcp: {} app(s), {} tool(s)",
                built.apps.len(),
                built.tools.len()
            );
            server.set_catalogue(built);
        }
        files = Some(scanned);
        asking = tokio::select! {
            Some(()) = dir_changes.recv() => {
                while matches!(tokio::time::timeout(SETTLE, dir_changes.recv()).await, Ok(Some(()))) {}
                false
            }
            () = tokio::time::sleep(probe) => true,
        };
    }
}

/// A file written, replaced, moved or removed, or the directory itself
/// going.
const WATCHED: WatchMask = WatchMask::CREATE
    .union(WatchMask::DELETE)
    .union(WatchMask::MODIFY)
    .union(WatchMask::MOVED_FROM)
    .union(WatchMask::MOVED_TO)
    .union(WatchMask::CLOSE_WRITE)
    .union(WatchMask::DELETE_SELF)
    .union(WatchMask::MOVE_SELF);

/// Watches each of `dirs`, or its nearest existing ancestor while it does
/// not exist, so that it is watched itself once it appears.
fn follow(inotify: &mut Inotify, dirs: &[PathBuf]) -> std::io::Result<()> {
    for dir in dirs {
        for candidate in dir.ancestors() {
            match inotify.watches().add(candidate, WATCHED) {
                Ok(_) => break,
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                Err(e) => return Err(e),
            }
        }
    }
    Ok(())
}

/// Ticks when something may have changed in `dirs`; the watches are in
/// place on return. inotify blocks a thread of its own.
#[allow(clippy::print_stderr, reason = "journald collects stderr")]
fn watch_dirs(dirs: &[PathBuf]) -> mpsc::Receiver<()> {
    let (tx, rx) = mpsc::channel(1);
    let dirs: Vec<PathBuf> = dirs
        .iter()
        .filter_map(|d| std::path::absolute(d).ok())
        .collect();
    let mut inotify = match Inotify::init().and_then(|mut i| follow(&mut i, &dirs).map(|()| i)) {
        Ok(i) => i,
        Err(e) => {
            eprintln!("keel-mcp: not watching the manifest directories: {e}");
            return rx;
        }
    };
    let mut wait = move || -> std::io::Result<()> {
        let mut buffer = [0; 4096];
        loop {
            inotify.read_events_blocking(&mut buffer)?;
            if let Err(mpsc::error::TrySendError::Closed(())) = tx.try_send(()) {
                return Ok(());
            }
            follow(&mut inotify, &dirs)?;
        }
    };
    let watcher = std::thread::Builder::new()
        .name("keel-mcp-watch".into())
        .spawn(move || {
            if let Err(e) = wait() {
                eprintln!("keel-mcp: stopped watching the manifest directories: {e}");
            }
        });
    if let Err(e) = watcher {
        eprintln!("keel-mcp: not watching the manifest directories: {e}");
    }
    rx
}
