//! `arm-wake`: run as root before every suspend (sleep.target). Proxies the
//! users' `marathon-wake-*` timers, background tasks' and the alarm clock's,
//! to one system timer with `WakeSystem=`, since a user manager cannot hold
//! a wake alarm: systemd fails such a timer with EOPNOTSUPP there.

use std::fs;
use std::path::Path;
use std::process::Command;

use serde::Deserialize;

pub const UNIT: &str = "marathon-wake";
pub const TIMER_PATTERN: &str = "marathon-wake-*";
/// The shell's alarm clock (`WakeTimers` key `alarm`).
const ALARM_PREFIX: &str = "marathon-wake-alarm-";
/// Never resume sooner than this after suspending.
const MIN_AHEAD_SECS: u64 = 30;

#[derive(Deserialize)]
struct User {
    user: String,
}

#[derive(Deserialize)]
struct Timer {
    next: Option<u64>,
    unit: String,
}

/// A timer's next elapse, in seconds since the epoch.
#[derive(Debug, PartialEq, Eq)]
pub struct Elapse {
    pub unit: String,
    pub at: u64,
}

/// `loginctl --json=short list-users`.
pub fn parse_users(json: &str) -> Vec<String> {
    serde_json::from_str::<Vec<User>>(json)
        .map(|users| users.into_iter().map(|u| u.user).collect())
        .unwrap_or_default()
}

/// `systemctl list-timers -o json`: the next elapse of each. An inactive
/// timer has no next elapse (null or 0).
pub fn parse_next_elapses(json: &str) -> Vec<Elapse> {
    serde_json::from_str::<Vec<Timer>>(json)
        .map(|timers| {
            timers
                .into_iter()
                .filter_map(|t| {
                    let usec = t.next.filter(|usec| *usec > 0)?;
                    Some(Elapse {
                        unit: t.unit,
                        at: usec / 1_000_000,
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

/// When to resume, in seconds since the epoch, or `None` to sleep through.
/// A low battery sleeps through background work, never through an alarm.
pub fn next_wake(elapses: &[Elapse], now: u64, battery_low: bool) -> Option<u64> {
    elapses
        .iter()
        .filter(|e| !battery_low || e.unit.starts_with(ALARM_PREFIX))
        .map(|e| e.at)
        .min()
        .map(|next| next.max(now + MIN_AHEAD_SECS))
}

pub fn timer_args(at: u64) -> Vec<String> {
    [
        "--quiet",
        &format!("--unit={UNIT}"),
        "--description=Marathon background work wake-up",
        &format!("--on-calendar=@{at}"),
        "--timer-property=WakeSystem=true",
        "--timer-property=AccuracySec=1s",
        "true",
    ]
    .map(str::to_owned)
    .to_vec()
}

#[allow(clippy::print_stderr, reason = "journald collects stderr")]
fn log(message: &str) {
    eprintln!("marathon-background arm-wake: {message}");
}

fn output(program: &str, args: &[&str]) -> String {
    match Command::new(program).args(args).output() {
        Ok(out) if out.status.success() => String::from_utf8_lossy(&out.stdout).into_owned(),
        Ok(out) => {
            log(&format!(
                "{program} {args:?}: {}",
                String::from_utf8_lossy(&out.stderr).trim()
            ));
            String::new()
        }
        Err(e) => {
            log(&format!("{program}: {e}"));
            String::new()
        }
    }
}

fn elapses() -> Vec<Elapse> {
    parse_users(&output("loginctl", &["--json=short", "list-users"]))
        .iter()
        .flat_map(|user| {
            let machine = format!("--machine={user}@");
            parse_next_elapses(&output(
                "systemctl",
                &[
                    "--user",
                    &machine,
                    "list-timers",
                    "--all",
                    "--output=json",
                    TIMER_PATTERN,
                ],
            ))
        })
        .collect()
}

fn clear(marker: &Path) {
    match fs::remove_file(marker) {
        Err(e) if e.kind() != std::io::ErrorKind::NotFound => {
            log(&format!("{}: {e}", marker.display()));
        }
        _ => {}
    }
}

/// Replaces the wake-up timer, and records its time at `marker` for the
/// shell to tell this resume from one the person caused.
pub fn arm(now: u64, power_supply: &Path, marker: &Path) -> bool {
    let at = next_wake(&elapses(), now, crate::check::battery_low(power_supply));
    // A transient unit's name is free again once it is stopped; stopping
    // one that is not loaded fails, harmlessly.
    if let Err(e) = Command::new("systemctl")
        .args(["stop", "--quiet", &format!("{UNIT}.timer")])
        .status()
    {
        log(&format!("systemctl: {e}"));
    }
    let Some(at) = at else {
        clear(marker);
        return true;
    };
    let armed = Command::new("systemd-run")
        .args(timer_args(at))
        .status()
        .is_ok_and(|s| s.success());
    if !armed {
        log(&format!("could not arm a wake-up at {at}"));
        clear(marker);
        return false;
    }
    if let Err(e) = fs::write(marker, format!("{at}\n")) {
        log(&format!("{}: {e}", marker.display()));
    }
    true
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn users_come_from_loginctl_json() {
        assert_eq!(
            parse_users(
                r#"[{"uid":1000,"user":"user","linger":true,"state":"active"},
                    {"uid":1001,"user":"guest","linger":false,"state":"online"}]"#
            ),
            ["user", "guest"]
        );
        assert!(parse_users("").is_empty());
    }

    fn task(at: u64) -> Elapse {
        Elapse {
            unit: "marathon-wake-email.sync.timer".to_owned(),
            at,
        }
    }

    fn alarm(at: u64) -> Elapse {
        Elapse {
            unit: format!("marathon-wake-alarm-{at}.timer"),
            at,
        }
    }

    #[test]
    fn timers_without_a_next_elapse_are_left_out() {
        assert_eq!(
            parse_next_elapses(
                r#"[{"next":1792236376383528,"left":1,"last":1,"passed":1,
                     "unit":"marathon-wake-email.sync.timer","activates":"x"},
                    {"next":null,"unit":"marathon-wake-a.b.timer"},
                    {"next":0,"unit":"marathon-wake-c.d.timer"}]"#
            ),
            [task(1_792_236_376)]
        );
        assert!(parse_next_elapses("[]").is_empty());
        assert!(parse_next_elapses("garbage").is_empty());
    }

    #[test]
    fn the_earliest_task_wakes_the_device() {
        assert_eq!(
            next_wake(&[task(5000), task(4000), task(9000)], 1000, false),
            Some(4000)
        );
        assert_eq!(next_wake(&[], 1000, false), None);
    }

    #[test]
    fn an_alarm_before_a_task_wakes_the_device() {
        assert_eq!(
            next_wake(&[task(5000), alarm(4000)], 1000, false),
            Some(4000)
        );
        assert_eq!(
            next_wake(&[task(4000), alarm(5000)], 1000, false),
            Some(4000)
        );
    }

    #[test]
    fn a_task_already_due_wakes_shortly_after_suspend() {
        assert_eq!(next_wake(&[task(900), task(4000)], 1000, false), Some(1030));
    }

    #[test]
    fn a_low_battery_sleeps_through_tasks_but_not_alarms() {
        assert_eq!(next_wake(&[task(4000)], 1000, true), None);
        assert_eq!(
            next_wake(&[task(4000), alarm(5000)], 1000, true),
            Some(5000)
        );
    }

    #[test]
    fn the_wake_up_is_a_transient_system_timer() {
        assert_eq!(
            timer_args(1_792_236_376),
            [
                "--quiet",
                "--unit=marathon-wake",
                "--description=Marathon background work wake-up",
                "--on-calendar=@1792236376",
                "--timer-property=WakeSystem=true",
                "--timer-property=AccuracySec=1s",
                "true",
            ]
        );
    }
}
