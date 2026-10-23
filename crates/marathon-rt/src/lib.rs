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

/// The calling thread under `SCHED_RR | SCHED_RESET_ON_FORK` at `priority`,
/// or `SCHED_OTHER` for 0 (`docs/RT_SCHEDULING.md`); `pthread_setschedparam`'s
/// error number on failure.
#[must_use = "real-time scheduling failures must be handled"]
pub fn set_thread_priority(priority: i32) -> Result<(), i32> {
    let policy = if priority > 0 {
        libc::SCHED_RR | libc::SCHED_RESET_ON_FORK
    } else {
        libc::SCHED_OTHER
    };
    // SAFETY: sched_param is plain integers (musl pads it with private
    // fields), so all zeroes is a valid value.
    let mut param: libc::sched_param = unsafe { std::mem::zeroed() };
    param.sched_priority = priority.max(0);
    // SAFETY: the calling thread's own handle and a parameter it outlives.
    let error =
        unsafe { libc::pthread_setschedparam(libc::pthread_self(), policy, &raw const param) };
    if error == 0 {
        Ok(())
    } else {
        Err(error)
    }
}
