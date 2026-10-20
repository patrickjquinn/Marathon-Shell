//! The shell's Rust half: `QObject`s QML binds to, backed by D-Bus and system
//! I/O that runs on one I/O thread, never on the GUI thread.

#![allow(clippy::unnecessary_box_returns, reason = "cxx-qt's generated constructors return a Box")]

pub mod backlight;
mod identity;
mod io;
mod log;
pub mod network;
pub mod power;
pub mod security;
mod wake_timer;
