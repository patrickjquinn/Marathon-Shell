//! What Marathon's Rust `QObject`s and daemons share: one I/O thread and its
//! buses, the log, the property setter and the shell's permission gate.

pub mod daemon;
pub mod dirs;
pub mod io;
pub mod log;
#[cfg(feature = "testing")]
pub mod testing;

/// Sets a property's field and notifies, if it changed.
#[macro_export]
macro_rules! set {
    ($obj:expr, $field:ident, $changed:ident, $value:expr) => {{
        let value = $value;
        if $obj.$field != value {
            $obj.as_mut().rust_mut().$field = value;
            $obj.as_mut().$changed();
        }
    }};
}
