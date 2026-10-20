//! The app runner's Rust half: `Marathon.Platform`'s clients of the shell's
//! services, on one I/O thread, never blocking the app's GUI thread but
//! where QML asks for an answer at once.

#![allow(clippy::unnecessary_box_returns, reason = "cxx-qt's generated constructors return a Box")]
#![allow(clippy::unused_self, reason = "invokables and setters are the QObject's methods, however little of it they read")]

#[macro_use]
extern crate marathon_rt;

pub mod alarms;
pub mod contacts;
pub mod display;
pub mod location;
pub mod modem;
pub mod network;
pub mod permissions;
pub mod power;
pub mod sensors;
pub mod settings;
pub mod telephony;
mod shell;
mod variant;
