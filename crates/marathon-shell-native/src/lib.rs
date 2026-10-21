//! The shell's Rust half: `QObject`s QML binds to, backed by D-Bus and system
//! I/O that runs on one I/O thread, never on the GUI thread.

#![allow(clippy::unnecessary_box_returns, reason = "cxx-qt's generated constructors return a Box")]

#[macro_use]
extern crate marathon_rt;

pub(crate) use marathon_rt::{io, log};

pub mod alarms;
pub mod ambience;
pub mod apps;
mod audit;
pub mod audio;
pub mod bluetooth;
mod cgroup;
mod clock;
pub mod clipboard;
pub mod contacts;
mod desktop;
pub mod display;
pub mod flashlight;
pub mod haptics;
pub mod gate;
mod identity;
pub mod ipc;
pub mod location;
pub mod modem;
pub mod motion;
pub mod mpris;
pub mod network;
pub mod ngf;
mod notifications;
mod pam;
pub mod pilot;
pub mod permissions;
pub mod power;
mod sandbox;
pub mod pressure;
mod push;
pub mod security;
pub mod settings;
mod qsettings;
mod stored;
mod systemd;
mod timezone;
mod variant;
pub mod telephonyd;
pub mod updates;
mod wake_timer;
pub mod weather;
pub mod words;
