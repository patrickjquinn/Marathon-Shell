// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

// Rust side of Keel's launcher, shared by the Qt 6 apps (reef/client/app,
// shoal/*/app). Each app's src/bridge.rs pulls it in with
// `include!("<path to here>/launcher.rs")` next to its CXX-Qt bridge, which
// declares `keel_application()` and `keel_launch_arguments()` from the app's
// cpp/launcher.cpp (Keel::application() and Keel::launchArguments() in
// libkeel-sailfishapp, keel/sailfishapp/include/keellauncher.h).

/// The app's command line. Use it instead of `std::env::args()`: when
/// booster-keel (mapplauncherd) runs the app, the binary is loaded into the
/// booster process and Rust's arguments are the booster's.
pub fn launch_args() -> Vec<String> {
    qobject::keel_launch_arguments()
        .iter()
        .map(ToString::to_string)
        .collect()
}

/// The process's `QGuiApplication`: the one booster-keel created before the
/// launch when boosted, otherwise a new one (direct mode on Sailfish, see
/// ADR-0016). It lives until the process exits.
pub fn keel_application() -> Option<core::pin::Pin<&'static mut cxx_qt_lib::QGuiApplication>> {
    let app = qobject::keel_application();
    // SAFETY: Keel's launcher returns the process-wide application object
    // (or null); it is never freed or moved before the process exits, and
    // the app's main thread is its only user.
    unsafe { app.as_mut().map(|a| core::pin::Pin::new_unchecked(a)) }
}

/// Runs the app's entry point for the C `main` its src/lib.rs exports. The
/// app is a shared library that is also executable (`link_sailfishapp.rs`):
/// the kernel runs it directly, and booster-keel `dlopen()`s it and calls
/// `main`. Neither goes through Rust's start code for a binary, so this does
/// what that does and the app relies on: SIGPIPE ignored (a closed socket or
/// pipe is an `EPIPE` error, not death) and a panic ending the process with
/// status 101 rather than unwinding into C (the panic message is already
/// printed by then). `run` exits the process itself unless it returns
/// normally, which is status 0.
pub fn keel_main(run: fn()) -> core::ffi::c_int {
    extern "C" {
        fn signal(signum: core::ffi::c_int, handler: usize) -> usize;
    }
    // SIGPIPE is 13 and SIG_IGN is 1 on every Linux architecture.
    // SAFETY: setting a signal's disposition to "ignore" has no
    // preconditions.
    unsafe {
        signal(13, 1);
    }
    std::panic::catch_unwind(run).map_or(101, |()| 0)
}
