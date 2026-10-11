// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! Who keel-mcp's client is, and binding its socket.
//!
//! Only Pilot speaks for the person: a request's `_meta` saying the person
//! started (`userInitiated`) or confirmed (`confirmed`) something is
//! believed only from `pilotd`, which shows the person its cards. Anything
//! else on the device can start `keel-mcp --stdio` or connect to its socket,
//! and must not get "the person did this" relayed to apps with keel-mcp's
//! name on it (apps trust keel-mcp by its executable; see
//! keel/actions/plugin/keelcallertrust.h). The client is identified by its
//! process: the parent for `--stdio`, the socket peer's credentials for
//! `--socket`. It is trusted when it runs `/usr/bin/pilotd` (compared by
//! file, device and inode, so neither `argv[0]` nor a lookalike path passes)
//! or runs with Sailfish OS's `privileged` group as its effective group, the
//! platform's mark of a system component. pilotd is installed setgid
//! `privileged`, which also makes it non-dumpable: its `/proc/<pid>/exe`
//! cannot be read by keel-mcp, so on a device the group is what recognises
//! it.

use std::io;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};

/// The executables whose requests may speak for the person.
pub const TRUSTED_CLIENTS: &[&str] = &["/usr/bin/pilotd"];

/// Whether process `pid` runs one of `paths` (the same file, by device and
/// inode). False when the process cannot be inspected.
#[must_use]
pub fn runs_one_of(pid: u32, paths: &[&Path]) -> bool {
    if pid == 0 {
        return false;
    }
    let Ok(exe) = std::fs::metadata(format!("/proc/{pid}/exe")) else {
        return false;
    };
    paths
        .iter()
        .any(|p| std::fs::metadata(p).is_ok_and(|m| m.dev() == exe.dev() && m.ino() == exe.ino()))
}

/// The effective group of process `pid` (`/proc/<pid>/status`).
#[must_use]
pub fn effective_gid(pid: u32) -> Option<u32> {
    if pid == 0 {
        return None;
    }
    let status = std::fs::read_to_string(format!("/proc/{pid}/status")).ok()?;
    // "Gid:\t<real>\t<effective>\t<saved>\t<filesystem>"
    let line = status.lines().find_map(|l| l.strip_prefix("Gid:"))?;
    line.split_whitespace().nth(1)?.parse().ok()
}

/// The id of the group `name` in `group_file` (`/etc/group` format).
#[must_use]
pub fn group_id(group_file: &str, name: &str) -> Option<u32> {
    group_file.lines().find_map(|line| {
        let mut fields = line.split(':');
        if fields.next()? != name {
            return None;
        }
        fields.nth(1)?.parse().ok()
    })
}

/// Whether process `pid` is a trusted client: [`TRUSTED_CLIENTS`], or a
/// process whose effective group is `privileged`.
#[must_use]
pub fn is_trusted_client(pid: u32) -> bool {
    let paths: Vec<&Path> = TRUSTED_CLIENTS.iter().map(Path::new).collect();
    if runs_one_of(pid, &paths) {
        return true;
    }
    let privileged = std::fs::read_to_string("/etc/group")
        .ok()
        .and_then(|g| group_id(&g, "privileged"));
    privileged.is_some() && effective_gid(pid) == privileged
}

/// Binds a Unix socket at `path` that is never reachable with wider
/// permissions than 0600: it is bound inside a fresh 0700 directory next to
/// `path`, set to 0600 there, and only then renamed into place.
pub fn bind_private(path: &Path) -> io::Result<std::os::unix::net::UnixListener> {
    use std::os::unix::fs::{DirBuilderExt, PermissionsExt};
    let parent = match path.parent() {
        Some(p) if !p.as_os_str().is_empty() => p.to_path_buf(),
        _ => PathBuf::from("."),
    };
    let name = path.file_name().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "the socket path has no file name",
        )
    })?;
    let staging = parent.join(format!(
        ".{}.{}.bind",
        name.to_string_lossy(),
        std::process::id()
    ));
    // A directory left by a crashed process with the same pid. (mkdir below
    // fails if anything still sits there, so nobody else's file is used.)
    let _ = std::fs::remove_dir_all(&staging);
    std::fs::DirBuilder::new().mode(0o700).create(&staging)?;
    let inner = staging.join("socket");
    let bound = (|| {
        let listener = std::os::unix::net::UnixListener::bind(&inner)?;
        std::fs::set_permissions(&inner, std::fs::Permissions::from_mode(0o600))?;
        match std::fs::remove_file(path) {
            Ok(()) => {}
            Err(e) if e.kind() == io::ErrorKind::NotFound => {}
            Err(e) => return Err(e),
        }
        std::fs::rename(&inner, path)?;
        Ok(listener)
    })();
    let _ = std::fs::remove_file(&inner);
    let _ = std::fs::remove_dir(&staging);
    bound
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn a_process_runs_its_own_executable_only() {
        let me = std::process::id();
        let exe = std::env::current_exe().unwrap();
        assert!(runs_one_of(me, &[exe.as_path()]));
        assert!(!runs_one_of(me, &[Path::new("/bin/sh")]));
        // A path naming the same file another way (a symlink) still matches;
        // what counts is the file.
        let dir = std::env::temp_dir().join(format!("keel-mcp-peer-{me}"));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir(&dir).unwrap();
        let link = dir.join("link");
        std::os::unix::fs::symlink(&exe, &link).unwrap();
        assert!(runs_one_of(me, &[link.as_path()]));
        // A copy is another file.
        let copy = dir.join("copy");
        std::fs::copy(&exe, &copy).unwrap();
        assert!(!runs_one_of(me, &[copy.as_path()]));
        std::fs::remove_dir_all(&dir).unwrap();
        assert!(!runs_one_of(0, &[exe.as_path()]));
        assert!(!runs_one_of(u32::MAX, &[exe.as_path()]));
    }

    #[test]
    fn groups_and_effective_gids() {
        let file = "root:x:0:\nprivileged:x:996:alice\nprivileged2:x:7:\nbroken\n";
        assert_eq!(group_id(file, "privileged"), Some(996));
        assert_eq!(group_id(file, "root"), Some(0));
        assert_eq!(group_id(file, "privilege"), None);
        assert_eq!(group_id(file, "broken"), None);
        // This process's effective group, as the kernel reports it.
        let status = std::fs::read_to_string("/proc/self/status").unwrap();
        let egid: u32 = status
            .lines()
            .find_map(|l| l.strip_prefix("Gid:"))
            .and_then(|l| l.split_whitespace().nth(1))
            .unwrap()
            .parse()
            .unwrap();
        assert_eq!(effective_gid(std::process::id()), Some(egid));
        assert_eq!(effective_gid(0), None);
    }

    #[test]
    fn the_test_runner_is_not_pilotd() {
        assert!(!is_trusted_client(std::process::id()));
        assert!(!is_trusted_client(std::os::unix::process::parent_id()));
    }

    #[test]
    fn the_socket_is_private_from_the_start() {
        let dir = std::env::temp_dir().join(format!("keel-mcp-bind-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir(&dir).unwrap();
        let path = dir.join("keel-mcp.sock");
        // A stale socket from an earlier run is replaced.
        drop(std::os::unix::net::UnixListener::bind(&path).unwrap());
        let listener = bind_private(&path).unwrap();
        let mode = std::fs::symlink_metadata(&path)
            .unwrap()
            .permissions()
            .mode();
        assert_eq!(mode & 0o777, 0o600);
        // Only the socket is left: no staging directory.
        let names: Vec<_> = std::fs::read_dir(&dir)
            .unwrap()
            .map(|e| e.unwrap().file_name())
            .collect();
        assert_eq!(names, vec![std::ffi::OsString::from("keel-mcp.sock")]);
        // It answers at its final path.
        let _client = std::os::unix::net::UnixStream::connect(&path).unwrap();
        let (_server, _) = listener.accept().unwrap();
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
