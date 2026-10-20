//! The shell's Rust half: `QObject`s QML binds to, backed by D-Bus and system
//! I/O that runs on one I/O thread, never on the GUI thread.

#![allow(clippy::unnecessary_box_returns, reason = "cxx-qt's generated constructors return a Box")]

#[macro_use]
extern crate marathon_rt;

pub(crate) use marathon_rt::{io, log};

mod audit;
mod cgroup;
mod desktop;
pub mod display;
mod identity;
pub mod modem;
pub mod network;
mod pam;
pub mod power;
mod sandbox;
pub mod pressure;
pub mod security;
mod systemd;
mod timezone;
mod variant;
mod wake_timer;
pub mod weather;
