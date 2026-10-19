//! The `WirePlumber` config marathon-audiod ships.

#![allow(clippy::unwrap_used, clippy::panic, reason = "tests")]

use std::fs;
use std::path::Path;

/// `WirePlumber` stops its `BlueZ` monitor while the login session isn't
/// active, which drops every Bluetooth audio device on a shell restart.
#[test]
fn bluetooth_audio_outlives_the_login_session() {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("data/wireplumber/wireplumber.conf.d");
    let found = fs::read_dir(&dir).unwrap().any(|entry| {
        let text = fs::read_to_string(entry.unwrap().path()).unwrap();
        let lines: Vec<&str> = text
            .lines()
            .map(str::trim)
            .filter(|l| !l.starts_with('#'))
            .collect();
        lines.iter().any(|l| l.starts_with("wireplumber.profiles"))
            && lines.iter().any(|l| l.starts_with("main"))
            && lines
                .iter()
                .any(|l| l.replace(' ', "") == "monitor.bluez.seat-monitoring=disabled")
    });
    assert!(found, "no conf.d file disables monitor.bluez.seat-monitoring in the main profile");
}
