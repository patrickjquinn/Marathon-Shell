use std::fmt::Display;

/// A warning in the process's log, which journald collects from stderr.
#[allow(clippy::print_stderr, reason = "journald collects stderr")]
pub fn warn(area: &str, message: impl Display) {
    eprintln!("[{area}] {message}");
}
