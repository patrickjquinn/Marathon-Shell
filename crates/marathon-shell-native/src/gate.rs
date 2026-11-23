//! Who is calling the shell, and whether they may: the gate in front of
//! every permissioned D-Bus method.
//!
//! A caller is a Marathon app (by the pid the launch service registered, or
//! the `marathon-app-<id>` cgroup the lifecycle placed it in), a declared
//! session service (`service:<unit>`, by its unit and executable), or no one.
//! It needs any one of the method's permissions; one it declared but was never
//! asked about is asked for now, and the call is refused meanwhile.

use std::collections::{HashMap, VecDeque};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{LazyLock, Mutex, MutexGuard};
use std::time::{Duration, Instant};

use cxx_qt_lib::QString;

use crate::audit::{self, Severity};
use crate::permissions;

#[cxx_qt::bridge]
mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[namespace = "marathon::gate"]
    extern "Rust" {
        /// The caller behind a process, empty when unknown.
        fn caller_of_pid(pid: i64) -> QString;
    }
}

const SERVICES: &str = "/usr/share/marathon-shell/services";
const SERVICE: &str = "service:";
const SPEAK_FOR_PERSON: &str = "speak-for-person";
const KEEL_MCP: &str = "/usr/bin/keel-mcp";
const TEST_CALLER: &str = "_marathon_test_caller";
const MAX_CALLS: usize = 30;
const WINDOW: Duration = Duration::from_secs(1);

#[derive(Debug, PartialEq, Eq)]
pub enum Refusal {
    RateLimited,
    UnknownCaller,
    Requested(String),
    Missing(String),
}

impl Refusal {
    pub fn message(&self) -> String {
        match self {
            Self::RateLimited => "Rate limit exceeded".into(),
            Self::UnknownCaller => "Unknown caller".into(),
            Self::Requested(p) => format!("Permission requested: {p}"),
            Self::Missing(p) => format!("Missing permission: {p}"),
        }
    }
}

impl From<Refusal> for zbus::fdo::Error {
    fn from(r: Refusal) -> Self {
        if r == Refusal::RateLimited {
            Self::LimitsExceeded(r.message())
        } else {
            Self::AccessDenied(r.message())
        }
    }
}

static PIDS: LazyLock<Mutex<HashMap<u32, String>>> = LazyLock::new(Mutex::default);
// Each sender and area's calls in the last window.
type Calls = HashMap<(String, String), VecDeque<Instant>>;
static CALLS: LazyLock<Mutex<Calls>> = LazyLock::new(Mutex::default);

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|_| std::process::abort())
}

fn trusted_tests() -> bool {
    std::env::var("MARATHON_TEST_TRUSTED").is_ok_and(|v| v.parse::<i32>().is_ok_and(|n| n != 0))
}

/// The app behind a process, as the launcher knows it; "" forgets it.
/// The launcher knows `pid` as `app_id`.
pub(crate) fn remember_pid(pid: i64, app_id: &str) {
    let Ok(pid) = u32::try_from(pid) else { return };
    lock(&PIDS).insert(pid, app_id.to_owned());
}

/// The process exited: its pid may come back as another's.
pub(crate) fn forget_pid(pid: i64) {
    let Ok(pid) = u32::try_from(pid) else { return };
    lock(&PIDS).remove(&pid);
}

fn cgroup(pid: u32) -> String {
    fs::read_to_string(format!("/proc/{pid}/cgroup"))
        .unwrap_or_default()
        .lines()
        .find_map(|l| l.strip_prefix("0::"))
        .unwrap_or_default()
        .to_owned()
}

fn parent(pid: u32) -> Option<u32> {
    let stat = fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    stat.rsplit_once(')')?
        .1
        .split_whitespace()
        .nth(1)?
        .parse()
        .ok()
}

/// `service:<unit>` when `pid` runs a declared service's executable in its unit.
fn service(pid: u32, dir: &Path) -> Option<String> {
    let unit = cgroup(pid).rsplit('/').next()?.to_owned();
    if !unit.ends_with(".service")
        || !unit
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || "@._-".contains(c))
    {
        return None;
    }
    let declared: serde_json::Value =
        serde_json::from_slice(&fs::read(dir.join(format!("{unit}.json"))).ok()?).ok()?;
    let exec = fs::canonicalize(declared["exec"].as_str()?).ok()?;
    (running_exe(pid)? == exec).then(|| format!("{SERVICE}{unit}"))
}

/// The executable `pid` runs, by the path it was started from even when an
/// update has since replaced the file.
fn running_exe(pid: u32) -> Option<PathBuf> {
    let link = format!("/proc/{pid}/exe");
    fs::canonicalize(&link).ok().or_else(|| {
        let target = fs::read_link(&link).ok()?;
        let target = target.to_str()?.strip_suffix(" (deleted)")?;
        fs::canonicalize(target).ok()
    })
}

/// The caller behind `pid`.
pub fn resolve(pid: u32) -> Option<String> {
    let known = lock(&PIDS).get(&pid).cloned();
    if known.is_some() {
        return known;
    }
    if let Some(app) = cgroup(pid)
        .split('/')
        .find_map(|c| c.strip_prefix("marathon-app-"))
    {
        return Some(app.to_owned());
    }
    if let Some(service) = service(pid, Path::new(SERVICES)) {
        return Some(service);
    }
    // A sandbox's inner processes: the launch service knows an ancestor.
    let mut cursor = parent(pid);
    for _ in 0..8 {
        let p = cursor.filter(|&p| p > 1)?;
        let known = lock(&PIDS).get(&p).cloned();
        if let Some(app) = known {
            lock(&PIDS).insert(pid, app.clone());
            return Some(app);
        }
        cursor = parent(p);
    }
    None
}

/// The caller behind a process, or the tests' stand-in.
pub fn caller(pid: Option<u32>) -> Option<String> {
    pid.and_then(resolve)
        .or_else(|| trusted_tests().then(|| TEST_CALLER.to_owned()))
}

/// The tests' stand-in caller, while the tests run.
pub fn is_test_caller(caller: &str) -> bool {
    caller == TEST_CALLER && trusted_tests()
}

/// The tests' stand-in, or a declared service that holds `permission`.
pub fn service_or_test(caller: &str, permission: &str) -> bool {
    is_test_caller(caller)
        || declared_by_service(caller, &[permission.to_owned()], Path::new(SERVICES))
}

fn caller_of_pid(pid: i64) -> QString {
    QString::from(&caller(u32::try_from(pid).ok()).unwrap_or_default())
}

fn declared_by_service(caller: &str, permissions: &[String], dir: &Path) -> bool {
    let Some(unit) = caller.strip_prefix(SERVICE) else {
        return false;
    };
    let declared: serde_json::Value = fs::read(dir.join(format!("{unit}.json")))
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or_default();
    declared["permissions"].as_array().is_some_and(|d| {
        permissions
            .iter()
            .any(|p| d.iter().any(|v| v.as_str() == Some(p)))
    })
}

/// Whether process `pid` may tell an app that the person started a request
/// (Keel Actions' `userInitiated`): a declared service holding
/// "speak-for-person" (pilotd), or keel-mcp started by one.
pub fn speaks_for_person(pid: u32) -> bool {
    speaks_for_person_in(pid, Path::new(SERVICES), Path::new(KEEL_MCP))
}

fn speaks_for_person_in(pid: u32, dir: &Path, keel_mcp: &Path) -> bool {
    let holds = |pid| {
        service(pid, dir)
            .is_some_and(|s| declared_by_service(&s, &[SPEAK_FOR_PERSON.to_owned()], dir))
    };
    holds(pid)
        || (running_exe(pid).is_some_and(|exe| fs::canonicalize(keel_mcp).is_ok_and(|k| k == exe))
            && parent(pid).is_some_and(holds))
}

pub(crate) fn in_window(sender: &str, area: &str) -> bool {
    let now = Instant::now();
    let mut calls = lock(&CALLS);
    let window = calls
        .entry((sender.to_owned(), area.to_owned()))
        .or_default();
    while window
        .front()
        .is_some_and(|t| now.duration_since(*t) > WINDOW)
    {
        window.pop_front();
    }
    if window.len() >= MAX_CALLS {
        return false;
    }
    window.push_back(now);
    true
}

/// The caller, when `sender` (process `pid`) may use any of `permissions` for `area`.
pub fn admit(
    pid: Option<u32>,
    sender: &str,
    area: &str,
    permissions: &[String],
) -> Result<String, Refusal> {
    if !in_window(sender, area) {
        audit::log(
            Severity::Warning,
            &format!("rate limit exceeded: {sender} {area}"),
        );
        return Err(Refusal::RateLimited);
    }
    let caller = caller(pid).ok_or(Refusal::UnknownCaller)?;
    let allowed = if caller.starts_with(SERVICE) {
        declared_by_service(&caller, permissions, Path::new(SERVICES))
    } else {
        caller == TEST_CALLER || permissions.iter().any(|p| permissions::has(&caller, p))
    };
    if allowed {
        return Ok(caller);
    }
    if let Some(asked) = permissions::ask_if_undecided(&caller, permissions) {
        audit::log(
            Severity::Info,
            &format!("permission requested: {caller} {asked}"),
        );
        return Err(Refusal::Requested(asked));
    }
    let primary = permissions.first().cloned().unwrap_or_default();
    audit::log(
        Severity::Warning,
        &format!("permission denied: {caller} {primary}"),
    );
    Err(Refusal::Missing(primary))
}

pub(crate) fn denied(app_id: &str, permission: &str) {
    audit::log(
        Severity::Warning,
        &format!("permission denied: {app_id} {permission}"),
    );
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn a_service_updated_while_running_is_still_its_executable() {
        let dir = tempfile::tempdir().unwrap();
        let exe = dir.path().join("daemon");
        fs::copy("/bin/sleep", &exe).unwrap();
        let mut child = std::process::Command::new(&exe).arg("5").spawn().unwrap();
        // An update unlinks the old file and puts a new one at the same path.
        fs::remove_file(&exe).unwrap();
        fs::copy("/bin/sleep", &exe).unwrap();
        let running = running_exe(child.id());
        child.kill().unwrap();
        child.wait().unwrap();
        assert_eq!(running, Some(fs::canonicalize(&exe).unwrap()));
    }

    #[test]
    fn thirty_calls_a_second_per_sender_and_area() {
        for _ in 0..MAX_CALLS {
            assert!(in_window(":1.5", "Power"));
        }
        assert!(!in_window(":1.5", "Power"));
        assert!(in_window(":1.5", "Display"));
        assert!(in_window(":1.6", "Power"));
    }

    #[test]
    fn a_service_holds_what_its_declaration_lists() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("pilotd.service.json"),
            r#"{"exec":"/usr/bin/pilotd","permissions":["contacts"]}"#,
        )
        .unwrap();
        assert!(declared_by_service(
            "service:pilotd.service",
            &["sms".into(), "contacts".into()],
            dir.path()
        ));
        assert!(!declared_by_service(
            "service:pilotd.service",
            &["sms".into()],
            dir.path()
        ));
        assert!(!declared_by_service(
            "notes",
            &["contacts".into()],
            dir.path()
        ));
    }

    fn main_pid(unit: &str) -> Option<u32> {
        let out = std::process::Command::new("systemctl")
            .args(["--user", "show", "-p", "MainPID", "--value", unit])
            .output()
            .ok()?;
        String::from_utf8(out.stdout)
            .ok()?
            .trim()
            .parse()
            .ok()
            .filter(|&p| p > 0)
    }

    fn first_child(pid: u32) -> Option<u32> {
        fs::read_to_string(format!("/proc/{pid}/task/{pid}/children"))
            .ok()?
            .split_whitespace()
            .next()?
            .parse()
            .ok()
    }

    struct Unit(String);

    impl Drop for Unit {
        fn drop(&mut self) {
            std::process::Command::new("systemctl")
                .args(["--user", "stop", &self.0])
                .status()
                .ok();
        }
    }

    #[test]
    fn pilotd_and_the_keel_mcp_it_starts_speak_for_the_person() {
        let dir = tempfile::tempdir().unwrap();
        let (agent, helper) = (dir.path().join("agent"), dir.path().join("helper"));
        fs::copy("/bin/sh", &agent).unwrap();
        fs::copy("/bin/sleep", &helper).unwrap();
        let unit = format!("marathon-gate-test-{}.service", std::process::id());
        let started = std::process::Command::new("systemd-run")
            .args(["--user", "--quiet", "--collect", &format!("--unit={unit}")])
            .arg(&agent)
            .args(["-c", &format!("{} 30 & wait", helper.display())])
            .status();
        // Without a systemd user manager (a CI container) there is no unit.
        if !started.is_ok_and(|s| s.success()) {
            return;
        }
        let _unit = Unit(unit.clone());
        let mut pids = None;
        for _ in 0..50 {
            pids = main_pid(&unit).and_then(|m| Some((m, first_child(m)?)));
            if pids.is_some() {
                break;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        let (agent_pid, helper_pid) = pids.unwrap();
        let declare = |permission: &str| {
            fs::write(
                dir.path().join(format!("{unit}.json")),
                format!(
                    r#"{{"exec":"{}","permissions":["{permission}"]}}"#,
                    agent.display()
                ),
            )
            .unwrap();
        };
        let speaks = |pid| speaks_for_person_in(pid, dir.path(), &helper);

        declare("contacts");
        assert!(!speaks(agent_pid), "a service without the permission");
        assert!(!speaks(helper_pid), "keel-mcp started by it");

        declare(SPEAK_FOR_PERSON);
        assert!(speaks(agent_pid), "the service");
        assert!(speaks(helper_pid), "keel-mcp started by it");
        assert!(
            !speaks_for_person_in(helper_pid, dir.path(), Path::new("/bin/true")),
            "another program it started"
        );
        let mut stray = std::process::Command::new(&helper)
            .arg("30")
            .spawn()
            .unwrap();
        assert!(!speaks(stray.id()), "keel-mcp started by anyone else");
        stray.kill().unwrap();
        stray.wait().unwrap();
        assert!(!speaks(std::process::id()));
        assert!(!speaks(0));
    }

    #[test]
    fn the_launch_service_names_a_pid_and_its_children() {
        let (me, parent) = (std::process::id(), parent(std::process::id()).unwrap());
        remember_pid(i64::from(parent), "notes");
        assert_eq!(
            resolve(me).as_deref(),
            Some("notes"),
            "a child of a known pid, found once"
        );
        assert_eq!(resolve(me).as_deref(), Some("notes"), "and remembered");
        forget_pid(i64::from(me));
        forget_pid(i64::from(parent));
        assert_ne!(resolve(me).as_deref(), Some("notes"));
    }
}
