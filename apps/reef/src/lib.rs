// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! shipwright-reef: the Reef store client. Loads the QML UI (installed to
//! /usr/share/shipwright-reef/qml) on Keel, with the `Reef` singleton from
//! [`bridge`]. The shell starts it under marathon-keel-host.
//!
//! Built as a shared object that is also executable: the package installs
//! it as /usr/bin/shipwright-reef (tools/keel-launcher/link_sailfishapp.rs
//! says why).

#[allow(
    clippy::missing_safety_doc,
    reason = "cxx does not carry an extern fn's # Safety doc into the wrapper it \
              generates, and CXX-Qt allows no lint attribute on the bridge itself"
)]
pub mod bridge;
pub mod handler;
pub mod jobs;
pub mod logging;
pub mod release_gate;
pub mod rows;
pub mod settings;

// The generated Keel Actions manifest (build.rs), enforced by the
// Keel.Actions runtime.
keel::manifest!();

use std::ffi::{c_char, c_int};
use std::path::PathBuf;

use cxx_qt_lib::QString;

/// Where the package installs the UI.
const DEFAULT_QML: &str = "/usr/share/shipwright-reef/qml/shipwright-reef.qml";

fn usage() -> ! {
    eprintln!(
        "usage: shipwright-reef [--qml FILE]\n\
         \n\
         --qml FILE       main QML file (default {DEFAULT_QML}, or $REEF_QML)\n\
         \n\
         Extra QML import paths come from QML_IMPORT_PATH, as for any Qt6 app.\n\
         REEF_LOG sets the log level (error, warn, info, debug).\n\
         REEF_STORE_URL sets the store directory (development and tests)."
    );
    std::process::exit(2)
}

/// The program's entry point, for the C start code and booster-keel: runs
/// `run` through `bridge::keel_main`. `run` takes the arguments from Keel's
/// launcher, which has the right ones under booster-keel too.
#[cfg_attr(not(test), no_mangle)]
pub extern "C" fn main(_argc: c_int, _argv: *const *const c_char) -> c_int {
    bridge::keel_main(run)
}

fn run() {
    // Sailfish's launcher started Reef with umask 0, so every file it wrote
    // (settings, licences) was world-writable. Files Reef writes are
    // readable by others at most.
    // SAFETY: umask only sets the process's file mode mask; it cannot fail.
    unsafe {
        libc::umask(0o022);
    }
    let level = std::env::var("REEF_LOG")
        .ok()
        .and_then(|l| logging::parse_level(&l))
        .unwrap_or(log::LevelFilter::Info);
    logging::init(level);
    let mut qml = std::env::var_os("REEF_QML")
        .filter(|v| !v.is_empty())
        .map_or_else(|| PathBuf::from(DEFAULT_QML), PathBuf::from);
    // Keel's launcher has the real command line, also under booster-keel.
    let launch_args = bridge::launch_args();
    let mut args = launch_args.iter().skip(1).cloned();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--qml" => qml = args.next().map_or_else(|| usage(), PathBuf::from),
            "--version" => {
                println!("shipwright-reef {}", env!("CARGO_PKG_VERSION"));
                return;
            }
            "-h" | "--help" => usage(),
            // Qt's own options (-platform, -style, ...) are for QGuiApplication.
            _ => {}
        }
    }
    let qml = std::fs::canonicalize(&qml).unwrap_or_else(|e| {
        log::error!("cannot open {}: {e}", qml.display());
        std::process::exit(1)
    });
    let Some(qml) = qml.to_str() else {
        log::error!("the QML path is not UTF-8: {}", qml.display());
        std::process::exit(1)
    };

    // Keel's launcher owns the application: booster-keel's, created before
    // the launch, when boosted (ADR-0016); otherwise a new one.
    let Some(mut app) = bridge::keel_application() else {
        log::error!("cannot create the Qt application");
        std::process::exit(1)
    };
    app.as_mut()
        .set_application_name(&QString::from("shipwright-reef"));
    app.as_mut()
        .set_application_version(&QString::from(env!("CARGO_PKG_VERSION")));

    // Keel's ApplicationWindow is an Item, not a window: SailfishApp's view
    // (cpp/launcher.cpp) gives it one, full screen on a phone.
    if !bridge::qobject::keel_show_main_view(&QString::from(qml)) {
        log::error!("could not load {qml}");
        std::process::exit(1);
    }
    let code = app.exec();
    // The engine's threads (asynchronous image decoding, native QML
    // backends) must stop before exit() runs Qt's global destructors.
    bridge::qobject::keel_destroy_main_view();
    std::process::exit(code);
}
