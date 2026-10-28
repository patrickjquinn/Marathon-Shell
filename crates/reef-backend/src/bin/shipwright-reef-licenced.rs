// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

//! shipwright-reef-licenced: Reef's licence hand-off service.
//!
//! Started by the session bus on the first call to
//! `org.shipwright.Reef.Licences` (packaging:
//! /usr/share/dbus-1/services/org.shipwright.Reef.Licences.service) and
//! exits after `SHIPWRIGHT_REEF_LICENCED_IDLE_SECS` (default 30) seconds
//! without a call. See `reef_backend::licenced`.

use std::time::Duration;

use reef_backend::licenced::{serve, Activity, LicenceService};

fn main() {
    let idle = std::env::var("SHIPWRIGHT_REEF_LICENCED_IDLE_SECS")
        .ok()
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(30);
    let activity = Activity::new();
    let Some(service) = LicenceService::from_env(activity.clone()) else {
        eprintln!("shipwright-reef-licenced: neither XDG_DATA_HOME nor HOME is set");
        std::process::exit(1);
    };
    // zbus runs its own executor thread for the connection; this thread
    // only keeps the process (and connection) alive until idle.
    let conn = match futures_lite::future::block_on(serve(service, None)) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("shipwright-reef-licenced: {e}");
            std::process::exit(1);
        }
    };
    while activity.idle() < Duration::from_secs(idle) {
        std::thread::sleep(Duration::from_millis(250));
    }
    // Release the name before closing, so a call arriving now activates a
    // fresh instance instead of reaching one that is going away.
    let _ = futures_lite::future::block_on(async {
        let _ = conn.release_name(reef_backend::licenced::BUS_NAME).await;
        conn.close().await
    });
}
