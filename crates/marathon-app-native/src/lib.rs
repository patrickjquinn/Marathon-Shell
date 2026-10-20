//! The app runner's Rust half: `Marathon.Platform`'s clients of the shell's
//! services, on one I/O thread, never blocking the app's GUI thread but
//! where QML asks for an answer at once.

#![allow(clippy::unnecessary_box_returns, reason = "cxx-qt's generated constructors return a Box")]
#![allow(clippy::unused_self, reason = "invokables and setters are the QObject's methods, however little of it they read")]

#[macro_use]
extern crate marathon_rt;

pub mod alarms;
pub mod audio;
pub mod bluetooth;
pub mod contacts;
pub mod dav;
pub mod display;
pub mod haptics;
pub mod history;
pub mod lifecycle;
pub mod location;
pub mod media;
pub mod modem;
pub mod navigation;
pub mod network;
pub mod notifications;
pub mod permissions;
pub mod power;
pub mod security;
pub mod sensors;
pub mod settings;
mod shell;
pub mod sms;
pub mod store;
pub mod stores;
pub mod telephony;
pub mod updates;
mod variant;
