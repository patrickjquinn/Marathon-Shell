//! The shell's Rust half: `QObject`s QML binds to, backed by D-Bus and system
//! I/O that runs on one I/O thread, never on the GUI thread.

#![allow(
    clippy::unnecessary_box_returns,
    reason = "cxx-qt's generated constructors return a Box"
)]

#[macro_use]
extern crate marathon_rt;

pub(crate) use marathon_rt::{io, log};

pub mod alarms;
pub mod ambience;
pub mod app_ids;
pub mod apps;
pub mod audio;
mod audit;
mod backdrop;
pub mod bluetooth;
mod boost;
mod cgroup;
pub mod clipboard;
mod clock;
pub mod contacts;
mod desktop;
pub mod device;
pub mod display;
pub mod file_model;
pub mod flashlight;
mod foreign_focus;
pub mod gate;
pub mod haptics;
mod i18n;
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
pub mod permissions;
pub mod pilot;
pub mod portal;
pub mod power;
pub mod pressure;
mod push;
mod qsettings;
mod rt;
mod sandbox;
pub mod search;
pub mod security;
pub mod session;
pub mod settings;
pub mod share;
mod stored;
mod svg;
mod systemd;
pub mod tasks;
pub mod telephonyd;
pub mod text_input;
mod theme;
mod timezone;
pub mod ui;
pub mod updates;
mod variant;
mod wake_timer;
pub mod weather;
pub mod words;
