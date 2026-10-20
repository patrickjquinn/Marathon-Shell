//! What Marathon's Rust `QObject`s share: one I/O thread and its buses, the
//! log, and the property setter.

pub mod dirs;
pub mod io;
pub mod log;

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
