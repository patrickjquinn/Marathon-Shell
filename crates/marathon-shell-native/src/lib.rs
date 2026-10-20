//! The shell's Rust half: `QObject`s QML binds to, backed by D-Bus and system
//! I/O that runs on one I/O thread, never on the GUI thread.

#![allow(clippy::unnecessary_box_returns, reason = "cxx-qt's generated constructors return a Box")]

#[macro_use]
extern crate marathon_rt;

pub(crate) use marathon_rt::{io, log};

mod audit;
pub mod bluetooth;
mod cgroup;
mod clock;
pub mod clipboard;
pub mod contacts;
mod desktop;
pub mod display;
pub mod flashlight;
mod identity;
pub mod modem;
pub mod motion;
pub mod mpris;
pub mod network;
pub mod ngf;
mod notifications;
mod pam;
pub mod pilot;
pub mod power;
mod sandbox;
pub mod pressure;
mod push;
pub mod security;
mod stored;
mod systemd;
mod timezone;
mod variant;
pub mod telephonyd;
pub mod updates;
mod wake_timer;
pub mod weather;
pub mod words;
