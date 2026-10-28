// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

//! The licence hand-off service: Reef's tokens for sandboxed apps.
//!
//! Interface `org.shipwright.Reef.Licences1` at `/org/shipwright/Reef/Licences`
//! on the session bus, name `org.shipwright.Reef.Licences`; the constants and
//! the client live in `reef_licence::handoff`, which also records why the
//! caller is not authenticated (tokens are signed bearer credentials for one
//! app, equivalent to pasting them).
//!
//! It runs in `shipwright-reef-licenced` (src/bin), a D-Bus-activated
//! process that exits when idle, not in the GUI app: an app asking at
//! start-up must not open Reef's window, and the GUI is not running most
//! of the time.
//!
//! The service hands out what [`LicenceStore`] holds. It refuses a token
//! the stored revocation list marks as revoked (when the store can verify
//! it); everything else is the asking app's job, which verifies the token
//! offline exactly as a pasted one.

use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use reef_licence::handoff::valid_app_id;
use reef_licence::{KeySet, Policy};

use crate::licences::{LicenceStore, EMBEDDED_KEYS};

pub use reef_licence::handoff::{BUS_NAME, INTERFACE, OBJECT_PATH};

/// Errors on the bus, named `org.shipwright.Reef.Licences1.Error.<Variant>`.
#[derive(Debug, zbus::DBusError)]
#[zbus(prefix = "org.shipwright.Reef.Licences1.Error")]
pub enum LicencesError {
    #[zbus(error)]
    ZBus(zbus::Error),
    /// No token stored for this app, or it was revoked.
    NotFound(String),
    /// The app id is not `[A-Za-z0-9._-]{1,128}` or starts with a dot.
    InvalidAppId(String),
}

/// Last activity, for the idle exit. Milliseconds since `start`.
#[derive(Clone)]
pub struct Activity {
    start: Instant,
    last_ms: Arc<AtomicU64>,
}

impl Activity {
    pub fn new() -> Self {
        Self {
            start: Instant::now(),
            last_ms: Arc::new(AtomicU64::new(0)),
        }
    }

    fn touch(&self) {
        self.last_ms.store(elapsed_ms(self.start), Ordering::SeqCst);
    }

    /// Time since the last call (or since start).
    pub fn idle(&self) -> std::time::Duration {
        let now = elapsed_ms(self.start);
        std::time::Duration::from_millis(now.saturating_sub(self.last_ms.load(Ordering::SeqCst)))
    }
}

impl Default for Activity {
    fn default() -> Self {
        Self::new()
    }
}

/// The D-Bus object.
pub struct LicenceService {
    store: LicenceStore,
    activity: Activity,
}

impl LicenceService {
    /// Serves the tokens in `dir`, checking revocations against `keys`.
    pub fn new(dir: impl Into<PathBuf>, keys: KeySet, activity: Activity) -> Self {
        Self {
            store: LicenceStore::new(dir, keys, Policy::default()),
            activity,
        }
    }

    /// With the default directory and the embedded keys.
    pub fn from_env(activity: Activity) -> Option<Self> {
        let keys = KeySet::from_embedded(EMBEDDED_KEYS).unwrap_or_default();
        Some(Self::new(LicenceStore::default_dir()?, keys, activity))
    }

    /// The answer to `GetLicence`, without D-Bus.
    pub fn lookup(&self, app_id: &str, now: i64) -> Result<String, LicencesError> {
        if !valid_app_id(app_id) {
            return Err(LicencesError::InvalidAppId(format!("{app_id:?}")));
        }
        let stored = self
            .store
            .check(app_id, now)
            .ok_or_else(|| LicencesError::NotFound(format!("no licence for {app_id}")))?;
        if stored.revoked {
            return Err(LicencesError::NotFound(format!(
                "the licence for {app_id} was revoked"
            )));
        }
        Ok(stored.token)
    }
}

/// Milliseconds since `start`, saturating instead of truncating.
fn elapsed_ms(start: Instant) -> u64 {
    u64::try_from(start.elapsed().as_millis()).unwrap_or(u64::MAX)
}

#[zbus::interface(name = "org.shipwright.Reef.Licences1")]
impl LicenceService {
    /// The stored token for `app_id`.
    #[zbus(name = "GetLicence")]
    fn get_licence(&self, app_id: &str) -> Result<String, LicencesError> {
        self.activity.touch();
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .ok()
            .and_then(|d| i64::try_from(d.as_secs()).ok())
            .unwrap_or(0);
        self.lookup(app_id, now)
    }
}

/// Builds a connection that serves `service` and owns [`BUS_NAME`] on the
/// bus at `address`, or on the session bus when `address` is `None`.
pub async fn serve(
    service: LicenceService,
    address: Option<&str>,
) -> zbus::Result<zbus::Connection> {
    let builder = match address {
        Some(a) => zbus::connection::Builder::address(a)?,
        None => zbus::connection::Builder::session()?,
    };
    builder
        .serve_at(OBJECT_PATH, service)?
        .name(BUS_NAME)?
        .build()
        .await
}
