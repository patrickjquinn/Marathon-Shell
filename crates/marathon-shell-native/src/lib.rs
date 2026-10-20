//! The shell's Rust half: `QObject`s QML binds to, backed by D-Bus and system
//! I/O that runs on one I/O thread, never on the GUI thread.

#![allow(clippy::unnecessary_box_returns, reason = "cxx-qt's generated constructors return a Box")]

/// Sets a property's field and notifies, if it changed.
macro_rules! set {
    ($obj:expr, $field:ident, $changed:ident, $value:expr) => {{
        let value = $value;
        if $obj.$field != value {
            $obj.as_mut().rust_mut().$field = value;
            $obj.as_mut().$changed();
        }
    }};
}

mod audit;
pub mod display;
mod identity;
mod io;
mod log;
pub mod modem;
pub mod network;
mod pam;
pub mod power;
pub mod security;
mod wake_timer;
