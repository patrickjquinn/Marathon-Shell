//! Authentication audit lines in syslog's auth facility, written to
//! `/dev/log` as syslog(3) does, and echoed to the shell's log.

use std::os::unix::net::UnixDatagram;

/// Syslog severities the audit uses.
#[derive(Clone, Copy)]
pub enum Severity {
    Alert = 1,
    Warning = 4,
    Info = 6,
}

const AUTH: u8 = 4;

pub fn log(severity: Severity, message: &str) {
    let line = format!("[SECURITY] {message}");
    crate::log::warn("audit", &line);
    let priority = AUTH * 8 + severity as u8;
    if let Ok(socket) = UnixDatagram::unbound() {
        socket.send_to(format!("<{priority}>marathon-shell[{}]: {line}", std::process::id()).as_bytes(), "/dev/log").ok();
    }
}
