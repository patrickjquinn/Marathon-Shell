// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The models local mode answers with (packaging/packages/marathon-llm),
//! downloaded only when the person asks (`DownloadModels`), on a network
//! that is not metered and with room for them. A first question used to
//! start a silent download of up to 1.4 GB behind a 120 s timeout.
//! `run models` names the files this phone needs, `run download` fetches
//! them.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use serde::Serialize;

/// Room left over once the models are in.
const MARGIN: u64 = 256 << 20;

/// What the UI shows for the models (`ModelState`, JSON).
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Status {
    /// "none" (no model on the phone in this mode), "absent",
    /// "downloading", "loading", "ready" or "failed".
    pub state: &'static str,
    /// Downloaded so far, of `total`.
    pub bytes: u64,
    pub total: u64,
    /// Why the last download did not start or finish: "offline",
    /// "metered", "no-space" or "download".
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<&'static str>,
}

pub struct Models {
    /// marathon-llm's `run`; `None` when the model is not on the phone.
    run: Option<PathBuf>,
    system: Option<zbus::Connection>,
    plan: OnceLock<Vec<(PathBuf, u64)>>,
    downloading: AtomicBool,
    loading: AtomicBool,
    error: Mutex<Option<&'static str>>,
    changed: tokio::sync::watch::Sender<u64>,
}

impl Models {
    pub fn new(run: Option<PathBuf>, system: Option<zbus::Connection>) -> Models {
        Models {
            run,
            system,
            plan: OnceLock::new(),
            downloading: AtomicBool::new(false),
            loading: AtomicBool::new(false),
            error: Mutex::new(None),
            changed: tokio::sync::watch::channel(0).0,
        }
    }

    /// Ticks whenever [`Self::status`] may have changed.
    pub fn subscribe(&self) -> tokio::sync::watch::Receiver<u64> {
        self.changed.subscribe()
    }

    fn touch(&self) {
        self.changed.send_modify(|n| *n = n.wrapping_add(1));
    }

    /// The files this phone needs and their sizes.
    fn plan(&self) -> &[(PathBuf, u64)] {
        self.plan.get_or_init(|| {
            let Some(run) = &self.run else {
                return Vec::new();
            };
            let out = crate::privilege::unprivileged(&mut std::process::Command::new(run))
                .arg("models")
                .output();
            match out {
                Ok(o) if o.status.success() => parse_plan(&String::from_utf8_lossy(&o.stdout)),
                Ok(o) => {
                    log::warn!("{} models: {}", run.display(), o.status);
                    Vec::new()
                }
                Err(e) => {
                    log::warn!("{} models: {e}", run.display());
                    Vec::new()
                }
            }
        })
    }

    pub fn status(&self) -> Status {
        let error = *self
            .error
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if self.run.is_none() {
            return Status {
                state: "none",
                bytes: 0,
                total: 0,
                error: None,
            };
        }
        let plan = self.plan();
        let total = plan.iter().map(|(_, n)| n).sum();
        let bytes = plan.iter().map(|(p, n)| on_disk(p).min(*n)).sum();
        let complete = !plan.is_empty() && plan.iter().all(|(p, _)| p.is_file());
        let state = if self.downloading.load(Ordering::SeqCst) {
            "downloading"
        } else if complete && self.loading.load(Ordering::SeqCst) {
            "loading"
        } else if complete {
            "ready"
        } else if error.is_some() || plan.is_empty() {
            "failed"
        } else {
            "absent"
        };
        Status {
            state,
            bytes,
            total,
            error: error.filter(|_| state != "ready"),
        }
    }

    /// Not a model on the phone, or it is all there.
    pub fn present(&self) -> bool {
        matches!(self.status().state, "none" | "ready" | "loading")
    }

    /// The model is being read into memory (the app opened).
    pub fn set_loading(&self, loading: bool) {
        self.loading.store(loading, Ordering::SeqCst);
        self.touch();
    }

    /// Starts `run download` unless it runs, the models are in, or the
    /// network or the room says no; the status after.
    pub async fn download(self: std::sync::Arc<Self>, allow_metered: bool) -> Status {
        let status = self.status();
        let Some(run) = self.run.clone() else {
            return status;
        };
        if matches!(status.state, "downloading" | "ready" | "loading") {
            return status;
        }
        let (state, metered) = match &self.system {
            Some(system) => network(system).await,
            None => (None, 0),
        };
        let dir = self.plan().first().and_then(|(p, _)| p.parent());
        let free = dir.and_then(free_bytes);
        let needed = status.total.saturating_sub(status.bytes);
        if let Some(why) = refusal(state, metered, allow_metered, free, needed) {
            self.fail(Some(why));
            return self.status();
        }
        self.fail(None);
        if self.downloading.swap(true, Ordering::SeqCst) {
            return self.status();
        }
        let mut command = std::process::Command::new(&run);
        crate::privilege::unprivileged(&mut command).arg("download");
        let child = tokio::process::Command::from(command).spawn();
        let models = std::sync::Arc::clone(&self);
        tokio::spawn(async move {
            let done = match child {
                Ok(mut child) => loop {
                    tokio::select! {
                        s = child.wait() => break s.is_ok_and(|s| s.success()),
                        () = tokio::time::sleep(Duration::from_secs(1)) => models.touch(),
                    }
                },
                Err(e) => {
                    log::warn!("{} download: {e}", run.display());
                    false
                }
            };
            models.downloading.store(false, Ordering::SeqCst);
            models.fail((!done).then_some("download"));
        });
        self.touch();
        self.status()
    }

    fn fail(&self, why: Option<&'static str>) {
        *self
            .error
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = why;
        self.touch();
    }
}

/// `run models`' lines: "PATH BYTES".
fn parse_plan(text: &str) -> Vec<(PathBuf, u64)> {
    text.lines()
        .filter_map(|l| {
            let (path, bytes) = l.trim().rsplit_once(' ')?;
            Some((PathBuf::from(path), bytes.parse().ok()?))
        })
        .collect()
}

/// The file's size, or its partial download's.
fn on_disk(path: &Path) -> u64 {
    let mut part = path.as_os_str().to_owned();
    part.push(".part");
    std::fs::metadata(path)
        .or_else(|_| std::fs::metadata(&part))
        .map_or(0, |m| m.len())
}

/// Why a download of `needed` bytes must not start now: no connection
/// (`NetworkManager`'s state below connected-global, 70), a metered one (1
/// yes, 3 guess-yes) unless the person allowed it, or no room. Without
/// `NetworkManager` (`state` none) the network is not judged.
pub fn refusal(
    state: Option<u32>,
    metered: u32,
    allow_metered: bool,
    free: Option<u64>,
    needed: u64,
) -> Option<&'static str> {
    if state.is_some_and(|s| s < 70) {
        Some("offline")
    } else if !allow_metered && matches!(metered, 1 | 3) {
        Some("metered")
    } else if free.is_some_and(|f| f < needed.saturating_add(MARGIN)) {
        Some("no-space")
    } else {
        None
    }
}

/// `NetworkManager`'s `State` and `Metered`.
async fn network(system: &zbus::Connection) -> (Option<u32>, u32) {
    let nm = "org.freedesktop.NetworkManager";
    let Ok(proxy) = zbus::Proxy::new(system, nm, "/org/freedesktop/NetworkManager", nm).await
    else {
        return (None, 0);
    };
    let state = proxy.get_property::<u32>("State").await.ok();
    let metered = proxy.get_property::<u32>("Metered").await.unwrap_or(0);
    (state, metered)
}

/// Bytes free for the person in the file system `dir` is (or would be) on.
fn free_bytes(dir: &Path) -> Option<u64> {
    use std::os::unix::ffi::OsStrExt as _;
    let existing = dir.ancestors().find(|d| d.exists())?;
    let path = std::ffi::CString::new(existing.as_os_str().as_bytes()).ok()?;
    // SAFETY: statvfs is plain data; all zeros is a valid value.
    let mut st: libc::statvfs = unsafe { std::mem::zeroed() };
    // SAFETY: `path` is NUL-terminated and outlives the call; `st` is ours.
    let r = unsafe { libc::statvfs(path.as_ptr(), &raw mut st) };
    (r == 0).then(|| st.f_bavail.saturating_mul(st.f_frsize))
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn a_download_waits_for_wifi_and_room() {
        let gb = 1 << 30;
        assert_eq!(refusal(Some(70), 2, false, Some(4 * gb), gb), None);
        assert_eq!(refusal(None, 0, false, None, gb), None);
        assert_eq!(
            refusal(Some(50), 2, false, Some(4 * gb), gb),
            Some("offline")
        );
        assert_eq!(
            refusal(Some(70), 1, false, Some(4 * gb), gb),
            Some("metered")
        );
        assert_eq!(
            refusal(Some(70), 3, false, Some(4 * gb), gb),
            Some("metered")
        );
        assert_eq!(refusal(Some(70), 1, true, Some(4 * gb), gb), None);
        assert_eq!(refusal(Some(70), 2, false, Some(gb), gb), Some("no-space"));
    }

    #[test]
    fn the_status_follows_the_files() {
        let dir = tempfile::tempdir().unwrap();
        let run = dir.path().join("run");
        let (chat, embed) = (dir.path().join("chat.gguf"), dir.path().join("e5.gguf"));
        std::fs::write(
            &run,
            format!(
                "#!/bin/sh\necho \"{} 10\"\necho \"{} 4\"\n",
                chat.display(),
                embed.display()
            ),
        )
        .unwrap();
        std::fs::set_permissions(&run, std::os::unix::fs::PermissionsExt::from_mode(0o755))
            .unwrap();
        let m = Models::new(Some(run), None);
        let s = m.status();
        assert_eq!((s.state, s.bytes, s.total), ("absent", 0, 14));
        assert!(!m.present());

        std::fs::write(dir.path().join("chat.gguf.part"), [0; 6]).unwrap();
        assert_eq!(m.status().bytes, 6);
        std::fs::write(&chat, [0; 10]).unwrap();
        std::fs::write(&embed, [0; 4]).unwrap();
        let s = m.status();
        assert_eq!((s.state, s.bytes), ("ready", 14));
        m.set_loading(true);
        assert_eq!(m.status().state, "loading");
        assert!(m.present());

        let none = Models::new(None, None);
        assert_eq!(none.status().state, "none");
        assert!(none.present());
    }

    #[test]
    fn a_plan_line_is_a_path_and_a_size() {
        assert_eq!(
            parse_plan("/a b/c.gguf 12\n\nbad\n/d.gguf 3\n"),
            vec![
                (PathBuf::from("/a b/c.gguf"), 12),
                (PathBuf::from("/d.gguf"), 3)
            ]
        );
    }
}
