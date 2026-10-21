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
mod boost;
mod cgroup;
mod clock;
pub mod clipboard;
pub mod contacts;
mod desktop;
pub mod device;
pub mod display;
pub mod file_model;
pub mod flashlight;
pub mod haptics;
pub mod gate;
pub mod ipc;
pub mod layouts;
pub mod links;
pub mod location;
pub mod modem;
pub mod mpris;
pub mod network;
pub mod ngf;
pub mod notifications;
mod pam;
pub mod pilot;
pub mod permissions;
pub mod portal;
pub mod power;
mod sandbox;
pub mod pressure;
mod push;
mod rt;
pub mod search;
pub mod security;
pub mod session;
pub mod share;
pub mod settings;
mod qsettings;
mod stored;
mod svg;
mod systemd;
mod theme;
mod timezone;
mod variant;
pub mod tasks;
pub mod telephonyd;
pub mod text_input;
pub mod ui;
pub mod updates;
mod wake_timer;
pub mod weather;
pub mod words;
