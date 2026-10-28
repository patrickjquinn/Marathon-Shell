// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! shoal-pilot: the Pilot UI on Keel. Loads the QML (installed to
//! /usr/share/shoal-pilot/qml) with the `Pilot` singleton from [`bridge`],
//! which talks to pilotd over the session bus. Built as a shared object that
//! is also executable, as every Keel app (tools/keel-launcher).

// cxx does not carry the `# Safety` doc of an extern fn into the wrapper
// it generates, and CXX-Qt allows no lint attribute on the bridge itself.
#[allow(clippy::missing_safety_doc)]
pub mod bridge;
pub mod client;

use std::ffi::{c_char, c_int};
use std::path::PathBuf;

use cxx_qt_lib::QString;

const DEFAULT_QML: &str = "/usr/share/shoal-pilot/qml/shoal-pilot.qml";

fn usage() -> ! {
    eprintln!(
        "usage: shoal-pilot [--qml FILE] [--events | --sheet]\n\
         \n\
         --qml FILE   main QML file (default {DEFAULT_QML}, or $SHOAL_PILOT_QML)\n\
         --events     open on the events page (Pilot's Events view entry)\n\
         --sheet      open with the sheet up (the system-wide gesture)\n\
         \n\
         Test override (never set on a phone):\n\
         SHOAL_PILOT_DOWNLOADS=<dir>   where exports are written (default ~/Downloads)"
    );
    std::process::exit(2)
}

/// The entry point for the C start code and booster-keel.
#[cfg_attr(not(test), no_mangle)]
pub extern "C" fn main(_argc: c_int, _argv: *const *const c_char) -> c_int {
    bridge::keel_main(run)
}

fn run() {
    let mut qml = std::env::var_os("SHOAL_PILOT_QML")
        .filter(|v| !v.is_empty())
        .map_or_else(|| PathBuf::from(DEFAULT_QML), PathBuf::from);
    let launch_args = bridge::launch_args();
    let mut args = launch_args.iter().skip(1).cloned();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--qml" => qml = args.next().map_or_else(|| usage(), PathBuf::from),
            "--version" => {
                println!("shoal-pilot {}", env!("CARGO_PKG_VERSION"));
                return;
            }
            "-h" | "--help" => usage(),
            _ => {}
        }
    }
    let qml = std::fs::canonicalize(&qml).unwrap_or_else(|e| {
        eprintln!("shoal-pilot: cannot open {}: {e}", qml.display());
        std::process::exit(1)
    });
    let Some(mut app) = bridge::keel_application() else {
        eprintln!("shoal-pilot: cannot create the Qt application");
        std::process::exit(1)
    };
    app.as_mut()
        .set_application_name(&QString::from("shoal-pilot"));
    app.as_mut()
        .set_application_version(&QString::from(env!("CARGO_PKG_VERSION")));
    // Started by the system-wide gesture: the overlay over the app the
    // person was in, without the app's own window (cpp/launcher.cpp).
    let over_app =
        bridge::launch_request() == "sheet" || launch_args.iter().skip(1).any(|a| a == "--sheet");
    if !bridge::qobject::keel_show_main_view(
        &QString::from(qml.to_string_lossy().as_ref()),
        !over_app,
    ) {
        eprintln!("shoal-pilot: could not load {}", qml.display());
        std::process::exit(1);
    }
    std::process::exit(app.exec());
}
