//! Apps' cgroups: each runner in `marathon.slice/marathon-apps/marathon-app-<id>`,
//! frozen and boosted by writing its cgroup v2 files. An app that runs in a
//! systemd scope of its own (flatpak's, a launcher's) stays there and the
//! user manager freezes it, with its other processes. Without a delegated
//! `marathon.slice` every call is a no-op and the lifecycle still runs.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::thread::sleep;
use std::time::{Duration, Instant};

use crate::systemd::SystemdManagerProxy;
use crate::{app_ids, io, log};
use zbus::Variant;

const FRONT_UCLAMP_MIN: u8 = 30;

pub struct AppCgroups {
    // marathon.slice/marathon-apps, when the shell may write under it.
    root: Option<PathBuf>,
    shell: String,
    placed: HashSet<String>,
    // Apps in a systemd scope of their own, to its unit.
    scopes: HashMap<String, String>,
    scope_priorities: Arc<ScopePriorities>,
}

#[derive(Clone, Copy)]
pub(crate) struct Placement {
    pub(crate) frozen: bool,
    pub(crate) foreground: bool,
}

/// This session's app cgroups, once a previous session's are reaped.
pub(crate) fn app_cgroups() -> AppCgroups {
    let shell = read_cgroup(Path::new("/proc/self/cgroup"));
    let root = apps_root(&shell);
    if root.is_none() {
        log::warn(
            "cgroup",
            format_args!(
                "no delegated marathon.slice (shell in {shell:?}); freezing is logged only"
            ),
        );
    }
    let cgroups = AppCgroups {
        root,
        shell,
        placed: HashSet::new(),
        scopes: HashMap::new(),
        scope_priorities: Arc::default(),
    };
    cgroups.reap_stale();
    cgroups
}

/// `marathon-apps` beside the shell's `marathon-shell-*.scope`, in the
/// `marathon.slice` the session delegates: a child of the scope would break
/// cgroup v2's no-internal-processes rule.
fn apps_root(shell: &str) -> Option<PathBuf> {
    let fs_root = Path::new("/sys/fs/cgroup");
    if !fs_root.join("cgroup.controllers").exists() || shell.strip_suffix(".scope").is_none() {
        return None;
    }
    let slice = fs_root.join(
        shell
            .get(..shell.rfind("/marathon-shell-").filter(|&i| i > 0)?)?
            .trim_start_matches('/'),
    );
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
    write(&slice.join("cgroup.subtree_control"), "+io");
    write(&root.join("cgroup.subtree_control"), "+cpu +memory +pids");
    write(&root.join("cgroup.subtree_control"), "+io");
    Some(root)
}

impl AppCgroups {
    fn dir(&self, app_id: &str) -> Option<PathBuf> {
        Some(self.root.as_ref()?.join(format!("marathon-app-{app_id}")))
    }

    /// The app's process, whose own cgroup is `pid_cgroup`, in the app's
    /// cgroup, frozen or not and boosted in front.
    pub(crate) fn adopt(&mut self, app_id: &str, pid: i64, pid_cgroup: &str, placement: Placement) {
        if let Some(unit) = scope_unit(pid_cgroup, &self.shell) {
            self.scopes.insert(app_id.to_owned(), unit);
            self.set_front(app_id, placement.foreground);
            return;
        }
        let Some(dir) = self.dir(app_id).filter(|_| pid > 0 && !app_id.is_empty()) else {
            return;
        };
        // A previous instance may have left the cgroup frozen, which would
        // freeze this one at birth.
        if !write(&dir.join("cgroup.freeze"), "0") && fs::create_dir(&dir).is_err() {
            return;
        }
        if write(&dir.join("cgroup.procs"), &pid.to_string()) {
            // A pool runner starts helpers (QtWebEngine's zygotes) before it
            // is adopted; they come too, or they stay in the shell's scope,
            // unfrozen and charged to the shell.
            for child in descendants(pid) {
                write(&dir.join("cgroup.procs"), &child.to_string());
            }
            write(
                &dir.join("cgroup.freeze"),
                if placement.frozen { "1" } else { "0" },
            );
            self.placed.insert(app_id.to_owned());
            write_resource_profile(&dir, placement.foreground);
        }
    }

    pub(crate) fn set_frozen(&self, app_id: &str, frozen: bool) {
        if let Some(unit) = self.scopes.get(app_id).cloned() {
            io::spawn(async move {
                let done = async {
                    let manager = SystemdManagerProxy::new(&io::session_bus().await?).await?;
                    if frozen {
                        manager.freeze_unit(&unit).await
                    } else {
                        manager.thaw_unit(&unit).await
                    }
                };
                if let Err(e) = done.await {
                    log::warn("cgroup", format_args!("freezing {unit} {frozen}: {e}"));
                }
            });
        } else if self.placed.contains(app_id) {
            self.dir(app_id)
                .map(|dir| write(&dir.join("cgroup.freeze"), if frozen { "1" } else { "0" }));
        }
    }

    /// Foreground apps receive CPU and I/O shares under contention. Uclamp
    /// supplements them on kernels that implement it. Deckard's authenticated
    /// session watcher asks its root manager to apply the same host policy.
    pub(crate) fn set_front(&self, app_id: &str, front: bool) {
        if app_ids::android_package(app_id).is_some() {
            return;
        }
        if let Some(unit) = self.scopes.get(app_id).cloned() {
            let bfq_only = self.root.as_ref().is_some_and(|root| {
                root.join("io.bfq.weight").exists() && !root.join("io.weight").exists()
            });
            self.scope_priorities.set(&unit, front);
            let priorities = Arc::clone(&self.scope_priorities);
            io::spawn(async move {
                let Some((_guard, front)) = priorities.latest(&unit).await else {
                    return;
                };
                let (cpu, disk) = resource_weights(front);
                let disk = systemd_io_weight(disk, bfq_only);
                let properties = [
                    ("CPUWeight", Variant::from(cpu)),
                    ("IOWeight", Variant::from(disk)),
                ];
                let result = async {
                    let manager = SystemdManagerProxy::new(&io::session_bus().await?).await?;
                    manager.set_unit_properties(&unit, true, &properties).await
                }
                .await;
                if let Err(error) = result {
                    log::warn(
                        "cgroup",
                        format_args!("foreground shares for {unit}: {error}"),
                    );
                }
            });
        } else if let Some(dir) = self.dir(app_id) {
            write_resource_profile(&dir, front);
        }
    }

    /// The app's process exited or the app was closed. Its cgroup is thawed
    /// first: a process left frozen there (a Flatpak's bwrap or D-Bus proxy)
    /// would never exit.
    pub(crate) fn forget(&mut self, app_id: &str) {
        self.set_frozen(app_id, false);
        if let Some(unit) = self.scopes.remove(app_id) {
            self.scope_priorities.forget(&unit);
        }
        if self.placed.remove(app_id) {
            self.dir(app_id).map(fs::remove_dir);
        }
    }

    pub(crate) fn thaw_all(&self) {
        for app_id in &self.placed {
            self.dir(app_id)
                .map(|dir| write(&dir.join("cgroup.freeze"), "0"));
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
            .filter(|e| {
                e.file_name().to_string_lossy().starts_with("marathon-app-") && e.path().is_dir()
            })
            .map(|e| e.path())
            .collect();
        let signal_all = |signal| {
            dirs.iter()
                .flat_map(|d| pids(d))
                .filter(|&pid| kill(pid, signal))
                .count()
        };
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
        log::warn(
            "cgroup",
            format_args!(
                "reaped {} stale app cgroups ({removed} removed, {killed} pids SIGKILLed)",
                dirs.len()
            ),
        );
    }
}

// Serialize external-scope updates and read the newest request after taking
// the gate. Rapid focus changes must not let a late background job overwrite
// a newer foreground budget. Removed scopes discard queued requests.
#[derive(Default)]
struct ScopePriorities {
    updates: async_lock::Mutex<()>,
    desired: Mutex<HashMap<String, bool>>,
}

impl ScopePriorities {
    fn set(&self, unit: &str, front: bool) {
        if let Ok(mut desired) = self.desired.lock() {
            desired.insert(unit.to_owned(), front);
        }
    }

    fn forget(&self, unit: &str) {
        if let Ok(mut desired) = self.desired.lock() {
            desired.remove(unit);
        }
    }

    async fn latest(&self, unit: &str) -> Option<(async_lock::MutexGuard<'_, ()>, bool)> {
        let gate = self.updates.lock().await;
        let front = self.desired.lock().ok()?.get(unit).copied()?;
        Some((gate, front))
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
    fs::read_to_string(proc_file)
        .ok()
        .as_deref()
        .map(unified)
        .unwrap_or_default()
}

fn unified(contents: &str) -> String {
    contents
        .lines()
        .find_map(|l| l.strip_prefix("0::"))
        .unwrap_or_default()
        .trim()
        .to_owned()
}

/// The process's cgroup v2 path, from `/proc/<pid>/cgroup`.
pub(crate) fn cgroup_of_pid(pid: i64) -> String {
    read_cgroup(Path::new(&format!("/proc/{pid}/cgroup")))
}

/// How readily the kernel's OOM killer picks the process.
/// Also the pid's descendants, which a pool runner spawned while it still
/// carried the shell's score.
pub(crate) fn set_oom_score_adj(pid: i64, score: i32) {
    if pid > 0 {
        for p in std::iter::once(pid).chain(descendants(pid)) {
            write(
                Path::new(&format!("/proc/{p}/oom_score_adj")),
                &score.to_string(),
            );
        }
    }
}

/// Every process below `pid`, from each thread's `children` list.
fn descendants(pid: i64) -> Vec<i64> {
    let mut found = Vec::new();
    let mut pending = vec![pid];
    while let Some(parent) = pending.pop() {
        let Ok(tasks) = fs::read_dir(format!("/proc/{parent}/task")) else {
            continue;
        };
        for task in tasks.flatten() {
            let children = fs::read_to_string(task.path().join("children")).unwrap_or_default();
            for child in children
                .split_whitespace()
                .filter_map(|c| c.parse::<i64>().ok())
            {
                if !found.contains(&child) {
                    found.push(child);
                    pending.push(child);
                }
            }
        }
    }
    found
}

fn resource_weights(front: bool) -> (u64, u64) {
    if front {
        (200, 200)
    } else {
        (50, 25)
    }
}

// systemd normalizes IOWeight's 1..10000 range to BFQ's 1..1000.
// Above the default, its mapping is 100 + (weight - 100) / 11.
fn systemd_io_weight(weight: u64, bfq_only: bool) -> u64 {
    if bfq_only && weight > 100 {
        100 + (weight - 100) * 11
    } else {
        weight
    }
}

fn write_resource_profile(dir: &Path, front: bool) {
    let (cpu, disk) = resource_weights(front);
    write(&dir.join("cpu.weight"), &cpu.to_string());
    let bfq = dir.join("io.bfq.weight");
    let generic = dir.join("io.weight");
    if bfq.exists() {
        write(&bfq, &format!("default {disk}"));
    } else if generic.exists() {
        write(&generic, &format!("default {disk}"));
    }
    let clamp = dir.join("cpu.uclamp.min");
    if clamp.exists() {
        write(
            &clamp,
            &if front { FRONT_UCLAMP_MIN } else { 0 }.to_string(),
        );
    }
}

fn pids(dir: &Path) -> Vec<i32> {
    fs::read_to_string(dir.join("cgroup.procs"))
        .unwrap_or_default()
        .lines()
        .filter_map(|l| l.trim().parse().ok())
        .collect()
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
    fn queued_scope_update_uses_latest_focus_and_skips_closed_scopes() {
        let executor = async_executor::Executor::new();
        let priorities = Arc::new(ScopePriorities::default());
        async_io::block_on(executor.run(async {
            let gate = priorities.updates.lock().await;
            priorities.set("app-example.scope", false);
            let (started, ready) = async_channel::bounded(1);
            let worker = Arc::clone(&priorities);
            let job = executor.spawn(async move {
                started.send(()).await.unwrap();
                let (_gate, front) = worker.latest("app-example.scope").await.unwrap();
                front
            });
            ready.recv().await.unwrap();
            priorities.set("app-example.scope", true);
            drop(gate);
            assert!(job.await);
            priorities.forget("app-example.scope");
            assert!(priorities.latest("app-example.scope").await.is_none());
        }));
    }

    #[test]
    fn external_scopes_receive_the_same_effective_bfq_weight() {
        let property = systemd_io_weight(200, true);
        let effective_bfq = 100 + (property - 100) * 900 / 9900;
        assert_eq!(effective_bfq, 200);
        assert_eq!(systemd_io_weight(25, true), 25);
        assert_eq!(systemd_io_weight(200, false), 200);
    }

    #[test]
    fn foreground_and_background_shares_work_on_a_kernel_without_uclamp() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("cpu.weight"), "100").unwrap();
        fs::write(dir.path().join("io.bfq.weight"), "default 100").unwrap();
        write_resource_profile(dir.path(), true);
        assert_eq!(
            fs::read_to_string(dir.path().join("cpu.weight")).unwrap(),
            "200"
        );
        assert_eq!(
            fs::read_to_string(dir.path().join("io.bfq.weight")).unwrap(),
            "default 200"
        );
        write_resource_profile(dir.path(), false);
        assert_eq!(
            fs::read_to_string(dir.path().join("cpu.weight")).unwrap(),
            "50"
        );
        assert_eq!(
            fs::read_to_string(dir.path().join("io.bfq.weight")).unwrap(),
            "default 25"
        );
        assert!(!dir.path().join("cpu.uclamp.min").exists());
    }

    #[test]
    fn a_launchers_scope_is_the_apps() {
        let shell =
            "/user.slice/user-1000.slice/user@1000.service/marathon.slice/marathon-shell-1.scope";
        let flatpak = format!("{APPS}/app-flatpak-org.gnome.Maps-1234.scope");
        assert_eq!(
            scope_unit(&flatpak, shell).as_deref(),
            Some("app-flatpak-org.gnome.Maps-1234.scope")
        );
        assert_eq!(
            scope_unit(&format!("{APPS}/app-gnome-foot-99.scope"), shell).as_deref(),
            Some("app-gnome-foot-99.scope")
        );
        assert_eq!(scope_unit(shell, shell), None);
        assert_eq!(scope_unit(&format!("{APPS}/dbus.service"), shell), None);
        assert_eq!(scope_unit("", shell), None);
    }

    #[test]
    fn the_shells_own_scope_never_freezes() {
        let terminal = format!("{APPS}/app-gnome-ptyxis-7.scope");
        assert_eq!(
            scope_unit(&terminal, &format!("{terminal}/vte-spawn")),
            None
        );
        assert_eq!(scope_unit(&terminal, &terminal), None);
    }

    #[test]
    fn the_unified_line_is_the_cgroup() {
        assert_eq!(
            unified("0::/user.slice/app-x-1.scope\n"),
            "/user.slice/app-x-1.scope"
        );
        assert_eq!(unified("1:name=systemd:/a\n0::/b\n"), "/b");
        assert_eq!(unified(""), "");
    }

    #[test]
    fn without_marathon_slice_nothing_is_written() {
        assert_eq!(
            apps_root("/user.slice/user-1000.slice/session-1.scope"),
            None
        );
        assert_eq!(apps_root(""), None);
    }
}
