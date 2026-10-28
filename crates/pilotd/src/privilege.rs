// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The `privileged` group, held only while it is needed.
//!
//! pilotd is installed setgid `privileged`, as Sailfish's own services are,
//! because the calendar and the address book live under
//! `~/.local/share/system/privileged`. Everything else pilotd does needs no
//! more than the person's own rights, and some of it is decided by things
//! any process of the person's can change: the configuration file
//! (`[mcp] command`, `[events]`/`[sheet] open_command` start programs), the
//! command line (`/usr/bin/pilotd --config ...` gets the group by itself),
//! `$HOME`. Holding the group throughout made each of those a way from the
//! person's account into `privileged` (found 11 October 2026).
//!
//! So: [`drop_at_start`] sets the effective group to the person's own at
//! once (the group stays as the saved group, which is how keel-mcp still
//! recognises pilotd); [`with_privileged`] raises it around the calendar
//! and contacts reads only, one at a time; every program pilotd starts runs
//! with the person's group ([`unprivileged`]), so none inherits it even
//! during such a read; and while the group is held back, those databases
//! are found from the account's home in the user database, never from the
//! configuration or `$HOME` ([`home`]).

use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

/// The group pilotd was started with, when it differs from the person's.
static PRIVILEGED: OnceLock<Option<libc::gid_t>> = OnceLock::new();
/// One raised read at a time.
static RAISED: Mutex<()> = Mutex::new(());

/// Drops the effective group to the real one if pilotd was started setgid.
/// Call before any thread starts. True when it did.
pub fn drop_at_start() -> bool {
    // SAFETY: getgid, getegid and setegid have no memory-safety
    // preconditions.
    let (real, effective) = unsafe { (libc::getgid(), libc::getegid()) };
    if real == effective {
        PRIVILEGED.set(None).ok();
        return false;
    }
    // SAFETY: as above.
    if unsafe { libc::setegid(real) } != 0 {
        // Cannot drop: carry on as before rather than not start, but say so.
        log::error!(
            "could not drop the privileged group: {}",
            std::io::Error::last_os_error()
        );
        PRIVILEGED.set(None).ok();
        return false;
    }
    PRIVILEGED.set(Some(effective)).ok();
    true
}

/// Whether pilotd holds a group it dropped ([`drop_at_start`]).
pub fn held_back() -> bool {
    PRIVILEGED.get().copied().flatten().is_some()
}

/// Runs `f` with the dropped group raised again (the calendar and contacts
/// reads), then drops it. Without one, just runs `f`.
pub fn with_privileged<T>(f: impl FnOnce() -> T) -> T {
    let Some(group) = PRIVILEGED.get().copied().flatten() else {
        return f();
    };
    let _one = RAISED
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    // SAFETY: setegid to the saved group, which the kernel permits.
    if unsafe { libc::setegid(group) } != 0 {
        log::warn!(
            "could not raise the privileged group: {}",
            std::io::Error::last_os_error()
        );
    }
    let out = f();
    // SAFETY: back to the real group.
    unsafe {
        let _ = libc::setegid(libc::getgid());
    }
    out
}

/// Makes a program pilotd starts run with the person's own group.
pub fn unprivileged(cmd: &mut std::process::Command) -> &mut std::process::Command {
    use std::os::unix::process::CommandExt as _;
    // SAFETY: getgid has no preconditions.
    cmd.gid(unsafe { libc::getgid() })
}

/// [`unprivileged`] for a tokio command.
pub fn unprivileged_async(cmd: &mut tokio::process::Command) -> &mut tokio::process::Command {
    // SAFETY: getgid has no preconditions.
    cmd.gid(unsafe { libc::getgid() })
}

/// The person's home: from the user database while the group is held back
/// (`$HOME` is anyone's to set), else `$HOME`.
pub fn home() -> Option<PathBuf> {
    if held_back() {
        return passwd_home();
    }
    std::env::var_os("HOME").map(PathBuf::from)
}

fn passwd_home() -> Option<PathBuf> {
    use std::os::unix::ffi::OsStrExt as _;
    let mut buf = vec![0u8; 4096];
    // SAFETY: zeroed passwd is a valid out-parameter for getpwuid_r.
    let mut pwd: libc::passwd = unsafe { std::mem::zeroed() };
    let mut result: *mut libc::passwd = std::ptr::null_mut();
    // SAFETY: buf outlives the call and its length is passed; result is
    // only read when getpwuid_r reports success.
    let rc = unsafe {
        libc::getpwuid_r(
            libc::getuid(),
            &raw mut pwd,
            buf.as_mut_ptr().cast(),
            buf.len(),
            &raw mut result,
        )
    };
    if rc != 0 || result.is_null() || pwd.pw_dir.is_null() {
        return None;
    }
    // SAFETY: pw_dir points into buf, NUL-terminated by getpwuid_r.
    let dir = unsafe { std::ffi::CStr::from_ptr(pwd.pw_dir) };
    Some(PathBuf::from(std::ffi::OsStr::from_bytes(dir.to_bytes())))
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn without_a_setgid_start_nothing_changes() {
        // The test runner is not setgid: nothing is held back.
        assert!(!drop_at_start());
        assert!(!held_back());
        assert_eq!(with_privileged(|| 7), 7);
        assert_eq!(home(), std::env::var_os("HOME").map(PathBuf::from));
        assert!(passwd_home().is_some());
    }

    #[test]
    fn started_programs_get_the_persons_group() {
        let out = unprivileged(&mut std::process::Command::new("id"))
            .arg("-g")
            .output()
            .unwrap();
        // SAFETY: getgid has no preconditions.
        let gid = unsafe { libc::getgid() };
        assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), gid.to_string());
    }
}
