//! Apps' cgroups: each runner in `marathon.slice/marathon-apps/marathon-app-<id>`,
//! frozen and boosted by writing its cgroup v2 files. An app that runs in a
//! systemd scope of its own (flatpak's, a launcher's) stays there and the
//! user manager freezes it, with its other processes. Without a delegated
//! `marathon.slice` every call is a no-op and the lifecycle still runs.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::thread::sleep;
use std::time::{Duration, Instant};

use cxx_qt_lib::QString;

use crate::systemd::SystemdManagerProxy;
use crate::{io, log};

#[cxx_qt::bridge]
mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[namespace = "marathon::cgroup"]
    extern "Rust" {
        type AppCgroups;

        /// This session's app cgroups, once a previous session's are reaped.
        fn app_cgroups() -> Box<AppCgroups>;
        /// The app's process, whose own cgroup is `pid_cgroup`, in the
        /// app's cgroup, frozen or not and boosted in front.
        fn adopt(self: &mut AppCgroups, app_id: &QString, pid: i64, pid_cgroup: &QString, frozen: bool, front: bool);
        fn set_frozen(self: &AppCgroups, app_id: &QString, frozen: bool);
        /// The app in front gets a CPU-frequency floor (`cpu.uclamp.min`).
        fn set_front(self: &AppCgroups, app_id: &QString, front: bool);
        /// The app's process exited.
        fn forget(self: &mut AppCgroups, app_id: &QString);
        fn thaw_all(self: &AppCgroups);

        /// The process's cgroup v2 path, from `/proc/<pid>/cgroup`.
        fn cgroup_of_pid(pid: i64) -> QString;
        /// How readily the kernel's OOM killer picks the process.
        fn set_oom_score_adj(pid: i64, score: i32);
    }
}

const FRONT_UCLAMP_MIN: u8 = 30;

pub struct AppCgroups {
    // marathon.slice/marathon-apps, when the shell may write under it.
    root: Option<PathBuf>,
    shell: String,
    placed: HashSet<String>,
    // Apps in a systemd scope of their own, to its unit.
    scopes: HashMap<String, String>,
}

fn app_cgroups() -> Box<AppCgroups> {
    let shell = read_cgroup(Path::new("/proc/self/cgroup"));
    let root = apps_root(&shell);
    if root.is_none() {
        log::warn("cgroup", format_args!("no delegated marathon.slice (shell in {shell:?}); freezing is logged only"));
    }
    let cgroups = AppCgroups { root, shell, placed: HashSet::new(), scopes: HashMap::new() };
    cgroups.reap_stale();
    Box::new(cgroups)
}

/// `marathon-apps` beside the shell's `marathon-shell-*.scope`, in the
/// `marathon.slice` the session delegates: a child of the scope would break
/// cgroup v2's no-internal-processes rule.
fn apps_root(shell: &str) -> Option<PathBuf> {
    let fs_root = Path::new("/sys/fs/cgroup");
    if !fs_root.join("cgroup.controllers").exists() || shell.strip_suffix(".scope").is_none() {
        return None;
    }
    let slice = fs_root.join(shell.get(..shell.rfind("/marathon-shell-").filter(|&i| i > 0)?)?.trim_start_matches('/'));
    let root = slice.join("marathon-apps");
    // systemd chowns a delegated slice a moment after making it.
    let made = (0..5).any(|attempt| {
        if attempt > 0 {
            sleep(Duration::from_millis(150));
        }
        slice.is_dir() && (root.is_dir() || fs::create_dir(&root).is_ok())
    });
    if !made {
        return None;
    }
    // cpu.uclamp.min needs the cpu controller on the slice too.
    write(&slice.join("cgroup.subtree_control"), "+cpu");
    write(&root.join("cgroup.subtree_control"), "+cpu +memory +pids");
    Some(root)
}

impl AppCgroups {
    fn dir(&self, app_id: &str) -> Option<PathBuf> {
        Some(self.root.as_ref()?.join(format!("marathon-app-{app_id}")))
    }

    fn adopt(&mut self, app_id: &QString, pid: i64, pid_cgroup: &QString, frozen: bool, front: bool) {
        let app_id = app_id.to_string();
        if let Some(unit) = scope_unit(&pid_cgroup.to_string(), &self.shell) {
            self.scopes.insert(app_id, unit);
            return;
        }
        let Some(dir) = self.dir(&app_id).filter(|_| pid > 0 && !app_id.is_empty()) else { return };
        // A previous instance may have left the cgroup frozen, which would
        // freeze this one at birth.
        if !write(&dir.join("cgroup.freeze"), "0") && fs::create_dir(&dir).is_err() {
            return;
        }
        if write(&dir.join("cgroup.procs"), &pid.to_string()) {
            write(&dir.join("cgroup.freeze"), if frozen { "1" } else { "0" });
            self.placed.insert(app_id);
            write_uclamp(&dir, front);
        }
    }

    fn set_frozen(&self, app_id: &QString, frozen: bool) {
        let app_id = app_id.to_string();
        if let Some(unit) = self.scopes.get(&app_id).cloned() {
            io::spawn(async move {
                let done = async {
                    let manager = SystemdManagerProxy::new(&io::session_bus().await?).await?;
                    if frozen { manager.freeze_unit(&unit).await } else { manager.thaw_unit(&unit).await }
                };
                if let Err(e) = done.await {
                    log::warn("cgroup", format_args!("freezing {unit} {frozen}: {e}"));
                }
            });
        } else if self.placed.contains(&app_id) {
            self.dir(&app_id).map(|dir| write(&dir.join("cgroup.freeze"), if frozen { "1" } else { "0" }));
        }
    }

    // The pid's cgroup can come after the app is in front, so the path is
    // tried even before it is placed.
    fn set_front(&self, app_id: &QString, front: bool) {
        if let Some(dir) = self.dir(&app_id.to_string()) {
            write_uclamp(&dir, front);
        }
    }

    fn forget(&mut self, app_id: &QString) {
        let app_id = app_id.to_string();
        self.scopes.remove(&app_id);
        if self.placed.remove(&app_id) {
            self.dir(&app_id).map(fs::remove_dir);
        }
    }

    fn thaw_all(&self) {
        for app_id in &self.placed {
            self.dir(app_id).map(|dir| write(&dir.join("cgroup.freeze"), "0"));
        }
    }

    /// App cgroups outlive a greetd restart, frozen pids and all. Thawed
    /// first, as a frozen task runs no signal handler: SIGTERM, 1.5 s for
    /// the apps to save, then SIGKILL and rmdir.
    fn reap_stale(&self) {
        let Some(root) = &self.root else { return };
        let dirs: Vec<PathBuf> = fs::read_dir(root)
            .into_iter()
            .flatten()
            .flatten()
            .filter(|e| e.file_name().to_string_lossy().starts_with("marathon-app-") && e.path().is_dir())
            .map(|e| e.path())
            .collect();
        let signal_all = |signal| dirs.iter().flat_map(|d| pids(d)).filter(|&pid| kill(pid, signal)).count();
        for dir in &dirs {
            write(&dir.join("cgroup.freeze"), "0");
        }
        if signal_all(libc::SIGTERM) > 0 {
            let deadline = Instant::now() + Duration::from_millis(1500);
            while Instant::now() < deadline && dirs.iter().any(|d| !pids(d).is_empty()) {
                sleep(Duration::from_millis(50));
            }
        }
        let killed = signal_all(libc::SIGKILL);
        // A dir that stays, its pids not yet reaped, is reused thawed.
        let removed = dirs.iter().filter(|d| fs::remove_dir(d).is_ok()).count();
        log::warn("cgroup", format_args!("reaped {} stale app cgroups ({removed} removed, {killed} pids SIGKILLed)", dirs.len()));
    }
}

/// The unit of a systemd scope the app runs in (`systemd.io/DESKTOP_ENVIRONMENTS`),
/// never the shell's own cgroup or an ancestor of it: a process the shell
/// started shares the shell's, a terminal's `app-*.scope` on a dev host.
fn scope_unit(cgroup: &str, shell: &str) -> Option<String> {
    if cgroup.is_empty() || cgroup == shell || shell.starts_with(&format!("{cgroup}/")) {
        return None;
    }
    let unit = cgroup.rsplit('/').next()?;
    (unit.starts_with("app-") && unit.strip_suffix(".scope").is_some()).then(|| unit.to_owned())
}

fn read_cgroup(proc_file: &Path) -> String {
    fs::read_to_string(proc_file).ok().as_deref().map(unified).unwrap_or_default()
}

fn unified(contents: &str) -> String {
    contents.lines().find_map(|l| l.strip_prefix("0::")).unwrap_or_default().trim().to_owned()
}

fn cgroup_of_pid(pid: i64) -> QString {
    QString::from(&read_cgroup(Path::new(&format!("/proc/{pid}/cgroup"))))
}

fn set_oom_score_adj(pid: i64, score: i32) {
    if pid > 0 {
        write(Path::new(&format!("/proc/{pid}/oom_score_adj")), &score.to_string());
    }
}

fn write_uclamp(dir: &Path, front: bool) {
    write(&dir.join("cpu.uclamp.min"), &if front { FRONT_UCLAMP_MIN } else { 0 }.to_string());
}

fn pids(dir: &Path) -> Vec<i32> {
    fs::read_to_string(dir.join("cgroup.procs")).unwrap_or_default().lines().filter_map(|l| l.trim().parse().ok()).collect()
}

fn kill(pid: i32, signal: i32) -> bool {
    // SAFETY: kill(2) takes plain integers.
    unsafe { libc::kill(pid, signal) == 0 }
}

fn write(path: &Path, value: &str) -> bool {
    fs::write(path, value).is_ok()
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    const APPS: &str = "/user.slice/user-1000.slice/user@1000.service/app.slice";

    #[test]
    fn a_launchers_scope_is_the_apps() {
        let shell = "/user.slice/user-1000.slice/user@1000.service/marathon.slice/marathon-shell-1.scope";
        let flatpak = format!("{APPS}/app-flatpak-org.gnome.Maps-1234.scope");
        assert_eq!(scope_unit(&flatpak, shell).as_deref(), Some("app-flatpak-org.gnome.Maps-1234.scope"));
        assert_eq!(scope_unit(&format!("{APPS}/app-gnome-foot-99.scope"), shell).as_deref(), Some("app-gnome-foot-99.scope"));
        assert_eq!(scope_unit(shell, shell), None);
        assert_eq!(scope_unit(&format!("{APPS}/dbus.service"), shell), None);
        assert_eq!(scope_unit("", shell), None);
    }

    #[test]
    fn the_shells_own_scope_never_freezes() {
        let terminal = format!("{APPS}/app-gnome-ptyxis-7.scope");
        assert_eq!(scope_unit(&terminal, &format!("{terminal}/vte-spawn")), None);
        assert_eq!(scope_unit(&terminal, &terminal), None);
    }

    #[test]
    fn the_unified_line_is_the_cgroup() {
        assert_eq!(unified("0::/user.slice/app-x-1.scope\n"), "/user.slice/app-x-1.scope");
        assert_eq!(unified("1:name=systemd:/a\n0::/b\n"), "/b");
        assert_eq!(unified(""), "");
    }

    #[test]
    fn without_marathon_slice_nothing_is_written() {
        assert_eq!(apps_root("/user.slice/user-1000.slice/session-1.scope"), None);
        assert_eq!(apps_root(""), None);
    }
}
