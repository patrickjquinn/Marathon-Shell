// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! The privacy switch (spec section 8.3): when engaged, Pilot is offline
//! and the microphone path is closed. No exceptions, no queued uploads.
//!
//! The Jolla Phone's switch is exposed on the **session bus** as
//! `org.sailfishos.privacyswitch` at `/privacyswitch`, interface
//! `org.sailfishos.privacyswitch`: method `privacyModeActive() -> b` and
//! signal `privacyModeActiveChanged(b)` (Sailfish OS 5.2.0.13 and later,
//! as reported on forum.sailfishos.org, "The free association Privacy
//! Toggle thread"; not in Jolla's developer documentation). The hardware
//! switch also emits `KEY_F22` (engaged) and `KEY_F21` (released) on an
//! input device, but reading `/dev/input` needs the `input` group, so
//! `pilotd` uses the D-Bus service. The switch's own action list is user
//! configurable; Pilot treats "privacy mode active" as offline whatever
//! the user chose for microphones.
//!
//! Sources are behind [`PrivacySwitch`] so tests and other devices can
//! inject one: `file:PATH` (contents `1`/`0`) or `none`.

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;
use tokio::sync::watch;

pub const SWITCH_BUS_NAME: &str = "org.sailfishos.privacyswitch";
pub const SWITCH_PATH: &str = "/privacyswitch";
pub const SWITCH_INTERFACE: &str = "org.sailfishos.privacyswitch";

/// Read side of the offline state, cheap to clone into every client.
#[derive(Clone, Debug)]
pub struct Offline {
    rx: watch::Receiver<bool>,
}

/// Write side, owned by the daemon's switch watcher.
#[derive(Debug)]
pub struct OfflineControl {
    tx: watch::Sender<bool>,
}

pub fn offline_state(initial: bool) -> (OfflineControl, Offline) {
    let (tx, rx) = watch::channel(initial);
    (OfflineControl { tx }, Offline { rx })
}

impl Offline {
    /// Never offline; for tests and `--ask` runs.
    pub fn never() -> Offline {
        let (tx, rx) = watch::channel(false);
        // Keep the sender alive for the program's lifetime so `engaged`
        // waits forever instead of seeing a closed channel.
        std::mem::forget(tx);
        Offline { rx }
    }

    pub fn is_offline(&self) -> bool {
        *self.rx.borrow()
    }

    /// Resolves once offline (immediately if already). Used to abandon
    /// in-flight requests the moment the switch engages.
    pub async fn engaged(&self) {
        let mut rx = self.rx.clone();
        if rx.wait_for(|v| *v).await.is_err() {
            // Controller dropped: the daemon is shutting down. Never
            // resolve, so a request is not abandoned for that.
            std::future::pending::<()>().await;
        }
    }

    pub fn subscribe(&self) -> watch::Receiver<bool> {
        self.rx.clone()
    }
}

impl OfflineControl {
    /// Sets the state; returns whether it changed.
    pub fn set(&self, offline: bool) -> bool {
        self.tx.send_if_modified(|v| {
            let changed = *v != offline;
            *v = offline;
            changed
        })
    }

    pub fn reader(&self) -> Offline {
        Offline {
            rx: self.tx.subscribe(),
        }
    }
}

/// A source of the switch state.
#[async_trait]
pub trait PrivacySwitch: Send + Sync {
    /// Current state; `Err` means unknown.
    async fn current(&self) -> Result<bool, String>;
    /// Calls `on_change` for every change until the source ends.
    async fn watch(&self, on_change: Box<dyn Fn(bool) + Send + Sync>);
    fn describe(&self) -> String;
}

/// Parses the `privacy.source` config value.
pub fn from_config(source: &str, session: Option<zbus::Connection>) -> Arc<dyn PrivacySwitch> {
    if let Some(path) = source.strip_prefix("file:") {
        return Arc::new(FileSwitch {
            path: PathBuf::from(path),
            poll: Duration::from_millis(500),
        });
    }
    match (source, session) {
        ("none", _) => Arc::new(NoSwitch),
        (_, Some(conn)) => Arc::new(SailfishSwitch { conn }),
        // No session bus: treat as engaged, the safe direction.
        (_, None) => Arc::new(Unknown),
    }
}

/// No switch on this device.
pub struct NoSwitch;

#[async_trait]
impl PrivacySwitch for NoSwitch {
    async fn current(&self) -> Result<bool, String> {
        Ok(false)
    }
    async fn watch(&self, _: Box<dyn Fn(bool) + Send + Sync>) {
        std::future::pending::<()>().await;
    }
    fn describe(&self) -> String {
        "none".into()
    }
}

struct Unknown;

#[async_trait]
impl PrivacySwitch for Unknown {
    async fn current(&self) -> Result<bool, String> {
        Err("no session bus".into())
    }
    async fn watch(&self, _: Box<dyn Fn(bool) + Send + Sync>) {
        std::future::pending::<()>().await;
    }
    fn describe(&self) -> String {
        "unknown".into()
    }
}

/// `file:PATH`: `1` (or `true`, `on`) engaged; anything else released; a
/// missing file is released. Polled, for tests and for wiring the switch
/// through a udev rule on hardware without the D-Bus service.
pub struct FileSwitch {
    pub path: PathBuf,
    pub poll: Duration,
}

impl FileSwitch {
    fn read(&self) -> bool {
        std::fs::read_to_string(&self.path)
            .map(|s| matches!(s.trim(), "1" | "true" | "on"))
            .unwrap_or(false)
    }
}

#[async_trait]
impl PrivacySwitch for FileSwitch {
    async fn current(&self) -> Result<bool, String> {
        Ok(self.read())
    }
    async fn watch(&self, on_change: Box<dyn Fn(bool) + Send + Sync>) {
        let mut last = self.read();
        loop {
            tokio::time::sleep(self.poll).await;
            let now = self.read();
            if now != last {
                last = now;
                on_change(now);
            }
        }
    }
    fn describe(&self) -> String {
        format!("file:{}", self.path.display())
    }
}

/// The Sailfish OS session-bus service.
pub struct SailfishSwitch {
    pub conn: zbus::Connection,
}

impl SailfishSwitch {
    async fn proxy(&self) -> zbus::Result<zbus::Proxy<'static>> {
        zbus::Proxy::new(&self.conn, SWITCH_BUS_NAME, SWITCH_PATH, SWITCH_INTERFACE).await
    }
}

#[async_trait]
impl PrivacySwitch for SailfishSwitch {
    async fn current(&self) -> Result<bool, String> {
        let p = self.proxy().await.map_err(|e| e.to_string())?;
        match p.call::<_, _, bool>("privacyModeActive", &()).await {
            Ok(v) => Ok(v),
            // No switch service on this device or OS release: there is no
            // switch to honour. Any other failure is "unknown", which the
            // daemon treats as engaged.
            Err(e) => match zbus::fdo::Error::from(e) {
                zbus::fdo::Error::ServiceUnknown(_) | zbus::fdo::Error::NameHasNoOwner(_) => {
                    log::info!("no {SWITCH_BUS_NAME} service; no privacy switch");
                    Ok(false)
                }
                other => Err(other.to_string()),
            },
        }
    }

    async fn watch(&self, on_change: Box<dyn Fn(bool) + Send + Sync>) {
        use futures_util::StreamExt as _;
        let Ok(p) = self.proxy().await else {
            std::future::pending::<()>().await;
            return;
        };
        let Ok(mut signals) = p.receive_signal("privacyModeActiveChanged").await else {
            log::warn!("cannot subscribe to privacyModeActiveChanged");
            std::future::pending::<()>().await;
            return;
        };
        while let Some(msg) = signals.next().await {
            match msg.body().deserialize::<bool>() {
                Ok(v) => on_change(v),
                Err(e) => log::warn!("malformed privacyModeActiveChanged: {e}"),
            }
        }
    }

    fn describe(&self) -> String {
        format!("{SWITCH_BUS_NAME}{SWITCH_PATH}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn engaged_resolves_and_set_reports_changes() {
        let (ctl, off) = offline_state(false);
        assert!(!off.is_offline());
        let waiter = tokio::spawn({
            let off = off.clone();
            async move { off.engaged().await }
        });
        assert!(ctl.set(true));
        assert!(!ctl.set(true));
        tokio::time::timeout(Duration::from_secs(1), waiter)
            .await
            .expect("engaged resolves")
            .unwrap();
        assert!(off.is_offline());
    }

    #[tokio::test]
    async fn file_switch_reads_and_watches() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("switch");
        let sw = FileSwitch {
            path: path.clone(),
            poll: Duration::from_millis(10),
        };
        assert_eq!(sw.current().await, Ok(false));
        std::fs::write(&path, "1\n").unwrap();
        assert_eq!(sw.current().await, Ok(true));
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        let task = tokio::spawn(async move {
            sw.watch(Box::new(move |v| {
                let _ = tx.send(v);
            }))
            .await;
        });
        tokio::time::sleep(Duration::from_millis(30)).await;
        std::fs::write(&path, "0").unwrap();
        let got = tokio::time::timeout(Duration::from_secs(1), rx.recv())
            .await
            .unwrap();
        assert_eq!(got, Some(false));
        task.abort();
    }
}
