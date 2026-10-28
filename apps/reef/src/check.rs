// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

//! `shipwright-reef --check-updates`: the background update check behind
//! the "Check in the background" setting. No window and no Qt: the systemd
//! user timer `shipwright-reef-check.timer` (packaging/systemd/) starts it
//! every 4 hours once the person has turned background checks on in Reef
//! (Reef asks at first start; the package no longer enables the timer),
//! and it decides from the setting whether a check is due (every few hours
//! or weekly) and, with "Wi-Fi only", whether the phone is on Wi-Fi. A check is the same refresh the app
//! runs: catalogue (cached for the next start), `ssu lr`, `PackageKit`'s
//! Reef updates, and licence refreshes.
//!
//! When an update appears that has not been announced yet, it posts one
//! notification through `org.freedesktop.Notifications` (Lipstick on a
//! phone): the apps by name, a popup, and a tap that opens Reef on its
//! updates (`org.shipwright.reef.ui.openUpdates`, the app's `DBusAdaptor`).
//! The same updates are not announced again on the next check; a newer
//! version is, replacing the earlier notification.

use std::path::{Path, PathBuf};

use reef_backend::catalogue::Catalogue;
use reef_backend::licences::LicenceStore;
use reef_backend::release;

use crate::jobs::{self, RefreshInput};
use crate::settings::Settings;

/// Whether a check is due: `days` is the setting (0 never, 1 every few
/// hours, 7 weekly), `last` the time of the last completed check. Half an
/// hour of slack keeps a timer that fires a little early from skipping a
/// turn. A
/// last check in the future means the clock was wrong when it was recorded
/// (a phone's RTC at boot): it is due, rather than waiting until the clock
/// catches up.
pub fn due(days: i32, last: Option<i64>, now: i64) -> bool {
    const SLACK: i64 = 1800;
    match (days, last) {
        (d, _) if d <= 0 => false,
        (_, None) => true,
        (_, Some(last)) if last > now => true,
        (d, Some(last)) => now.saturating_sub(last) >= interval_secs(d) - SLACK,
    }
}

/// The time between checks for the setting: 1 is "every few hours" (each
/// firing of the 4-hourly timer), 7 is weekly.
pub fn interval_secs(days: i32) -> i64 {
    if days == 1 {
        4 * 3600
    } else {
        i64::from(days) * 86_400
    }
}

/// `$XDG_CACHE_HOME/shipwright-reef/last-check`: Unix seconds of the last
/// completed check.
pub fn stamp_path() -> Option<PathBuf> {
    jobs::cache_dir().map(|d| d.join("last-check"))
}

fn read_stamp(path: &Path) -> Option<i64> {
    std::fs::read_to_string(path).ok()?.trim().parse().ok()
}

/// The user timer that starts the check.
pub const TIMER: &str = "shipwright-reef-check.timer";

/// The command that turns the timer on or off for this user, now and at
/// later logins: Reef runs it when the person chooses ("Never" disables the
/// timer rather than leaving it to wake the phone for nothing).
pub fn timer_command(enabled: bool) -> Vec<&'static str> {
    vec![
        "systemctl",
        "--user",
        if enabled { "enable" } else { "disable" },
        "--now",
        TIMER,
    ]
}

/// Runs [`timer_command`], as the person ([`crate::launch::as_person`]):
/// with Reef's privileged group it ran in secure mode, ignored the session's
/// `XDG_RUNTIME_DIR` and failed ("Failed to connect to bus"), so the person's
/// choice never reached the timer (found on the phone, 12 October 2026).
pub fn set_timer(enabled: bool) -> Result<(), String> {
    let cmd = timer_command(enabled);
    let out = crate::launch::as_person(std::process::Command::new(cmd[0]).args(&cmd[1..]))
        .output()
        .map_err(|e| format!("{}: {e}", cmd.join(" ")))?;
    if out.status.success() {
        Ok(())
    } else {
        Err(format!(
            "{} failed: {}",
            cmd.join(" "),
            String::from_utf8_lossy(&out.stderr).trim()
        ))
    }
}

/// Whether the connection in use is Wi-Fi or wired, from `ConnMan`'s
/// services `(type, state)` in its order (the default route first): the
/// first that is `ready` or `online` decides.
pub fn unmetered(services: &[(String, String)]) -> bool {
    services
        .iter()
        .find(|(_, state)| state == "ready" || state == "online")
        .is_some_and(|(kind, _)| kind == "wifi" || kind == "ethernet")
}

/// [`unmetered`] for this phone (`net.connman.Manager.GetServices` on the
/// system bus); `None` when `ConnMan` cannot be asked.
pub fn on_unmetered() -> Option<bool> {
    use std::collections::HashMap;
    use zbus::zvariant::{OwnedObjectPath, OwnedValue};
    futures_lite::future::block_on(async {
        let conn = zbus::Connection::system().await.ok()?;
        let reply = conn
            .call_method(
                Some("net.connman"),
                "/",
                Some("net.connman.Manager"),
                "GetServices",
                &(),
            )
            .await
            .ok()?;
        let services: Vec<(OwnedObjectPath, HashMap<String, OwnedValue>)> =
            reply.body().deserialize().ok()?;
        let text = |props: &HashMap<String, OwnedValue>, key: &str| {
            props
                .get(key)
                .and_then(|v| <&str>::try_from(&**v).ok())
                .unwrap_or_default()
                .to_owned()
        };
        let pairs: Vec<(String, String)> = services
            .iter()
            .map(|(_, props)| (text(props, "Type"), text(props, "State")))
            .collect();
        Some(unmetered(&pairs))
    })
}

/// Runs one background check if the setting says it is due. Returns the
/// process exit status: 0 for "nothing to do" and for a check that ran
/// (its errors are logged), 1 when the phone's release is unknown.
///
/// Until the person has chosen background checks in Reef, or after they
/// chose "Never", the timer should not be running at all: if it is (left
/// from an older Reef, or a failed `systemctl` when they chose), the check
/// turns it off and does nothing else.
#[allow(
    clippy::too_many_lines,
    reason = "the background check's steps in order, in one place"
)]
pub fn run() -> i32 {
    let settings = Settings::default_path()
        .as_deref()
        .map(Settings::load)
        .unwrap_or_default();
    jobs::secure_ledger();
    if !settings.background_checks_on() {
        log::info!("background checks are not turned on in Reef; turning the timer off");
        if let Err(e) = set_timer(false) {
            log::warn!("{e}");
        }
        return 0;
    }
    if settings.background_wifi_only && on_unmetered() != Some(true) {
        log::info!("background check skipped: not on Wi-Fi");
        return 0;
    }
    let now = jobs::unix_now();
    let stamp = stamp_path();
    let last = stamp.as_deref().and_then(read_stamp);
    if !due(settings.background_check_days, last, now) {
        log::info!(
            "background check not due (every {} day(s); last {last:?})",
            settings.background_check_days
        );
        return 0;
    }
    let root = jobs::sysroot();
    let Some(release) = release::detect(&root) else {
        log::error!("cannot determine the installed Sailfish OS release");
        return 1;
    };
    let arch = release::native_arch().to_string();
    let cache_path = jobs::cache_path();
    let previous = cache_path
        .as_deref()
        .and_then(|p| std::fs::read(p).ok())
        .and_then(|b| Catalogue::parse(&b, &arch).ok());
    let config = jobs::repo_config(&root);
    let out = jobs::refresh(&RefreshInput {
        index_check: jobs::index_check(&config.alias),
        config,
        release: Some(release),
        arch,
        previous,
        licence_dir: LicenceStore::default_dir(),
        licence_server: settings.licence_server.clone(),
        cache_path,
    });
    for e in &out.errors {
        log::warn!("background check: {e}");
    }
    if let Some(path) = &stamp {
        let written = path
            .parent()
            .map_or(Ok(()), std::fs::create_dir_all)
            .and_then(|()| std::fs::write(path, now.to_string()));
        if let Err(e) = written {
            log::warn!("recording the check in {}: {e}", path.display());
        }
    }
    let updates: Vec<Update> = out
        .pk
        .as_ref()
        .map(|pk| {
            pk.updates
                .iter()
                .map(|u| Update {
                    title: out
                        .catalogue
                        .as_ref()
                        .and_then(|c| c.packages.iter().find(|p| p.name == u.id.name))
                        .map_or_else(|| u.id.name.clone(), |p| p.title.clone()),
                    key: format!("{} {}", u.id.name, u.id.version),
                })
                .collect()
        })
        .unwrap_or_default();
    log::info!("background check done: {} Reef update(s)", updates.len());
    let record = jobs::cache_dir().map(|d| d.join("announced-updates"));
    let announced = record
        .as_deref()
        .and_then(|p| std::fs::read_to_string(p).ok())
        .unwrap_or_default();
    if !news(&updates, &announced) {
        return 0;
    }
    let previous_id = record
        .as_deref()
        .and_then(|p| std::fs::read_to_string(p.with_extension("id")).ok())
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0);
    match notify(&updates, previous_id) {
        Ok(id) => {
            if let Some(p) = &record {
                let keys: Vec<&str> = updates.iter().map(|u| u.key.as_str()).collect();
                let _ = std::fs::write(p, keys.join("\n"));
                let _ = std::fs::write(p.with_extension("id"), id.to_string());
            }
        }
        Err(e) => log::warn!("posting the update notification: {e}"),
    }
    0
}

/// One waiting update: the app's name in the store, and `name version`.
pub struct Update {
    pub title: String,
    pub key: String,
}

/// Whether `updates` holds one not announced yet (`announced` is the
/// record, one `name version` a line).
pub fn news(updates: &[Update], announced: &str) -> bool {
    updates
        .iter()
        .any(|u| !announced.lines().any(|l| l.trim() == u.key))
}

/// The notification's title and text. English: this path runs without Qt,
/// so it has no translations (see the app README).
pub fn wording(updates: &[Update]) -> (String, String) {
    let names: Vec<&str> = updates.iter().map(|u| u.title.as_str()).collect();
    let title = if names.len() == 1 {
        format!("{} update ready", names[0])
    } else {
        format!("{} app updates ready", names.len())
    };
    let body = match names.as_slice() {
        [_] => "Tap to update it in Reef".to_string(),
        [a, b] => format!("{a} and {b}"),
        [a, b, c] => format!("{a}, {b} and {c}"),
        [a, b, rest @ ..] => format!("{a}, {b} and {} more", rest.len()),
        [] => String::new(),
    };
    (title, body)
}

/// Posts (or replaces `previous_id`'s) notification; returns its id.
fn notify(updates: &[Update], previous_id: u32) -> Result<u32, String> {
    use std::collections::HashMap;
    use zbus::zvariant::Value;
    let (title, body) = wording(updates);
    futures_lite::future::block_on(async {
        let conn = zbus::Connection::session()
            .await
            .map_err(|e| e.to_string())?;
        let mut hints: HashMap<&str, Value<'_>> = HashMap::new();
        // packaging/notifications: appName, icon, popup, removable.
        hints.insert("category", Value::from("x-shipwright.reef.updates"));
        hints.insert("x-nemo-preview-summary", Value::from(title.as_str()));
        hints.insert("x-nemo-preview-body", Value::from(body.as_str()));
        hints.insert(
            "x-nemo-item-count",
            Value::from(i32::try_from(updates.len()).unwrap_or(i32::MAX)),
        );
        // A tap opens Reef on its updates (the app's DBusAdaptor; the
        // session bus starts the app when it is not running).
        hints.insert(
            "x-nemo-remote-action-default",
            Value::from("org.shipwright.reef.ui / org.shipwright.reef.ui openUpdates"),
        );
        let reply = conn
            .call_method(
                Some("org.freedesktop.Notifications"),
                "/org/freedesktop/Notifications",
                Some("org.freedesktop.Notifications"),
                "Notify",
                &(
                    "shipwright-reef",
                    previous_id,
                    "",
                    title.as_str(),
                    body.as_str(),
                    vec!["default", ""],
                    hints,
                    -1i32,
                ),
            )
            .await
            .map_err(|e| e.to_string())?;
        reply.body().deserialize::<u32>().map_err(|e| e.to_string())
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const DAY: i64 = 86_400;

    #[test]
    fn checks_follow_the_setting() {
        let now = 1_790_000_000;
        // Never.
        assert!(!due(0, None, now));
        assert!(!due(0, Some(now - 30 * DAY), now));
        // First run.
        assert!(due(1, None, now));
        assert!(due(7, None, now));
        // Every few hours (each 4-hourly firing), with half an hour of
        // slack for a timer that fires early.
        assert!(!due(1, Some(now - 3600), now));
        assert!(due(1, Some(now - 4 * 3600 + 1200), now));
        assert!(due(1, Some(now - 2 * DAY), now));
        // Weekly.
        assert!(!due(7, Some(now - 3 * DAY), now));
        assert!(due(7, Some(now - 7 * DAY), now));
        // A recorded time in the future (a wrong clock then): due now. The
        // next check records the corrected time, so this does not repeat.
        assert!(due(1, Some(now + DAY), now));
        assert!(due(7, Some(now + 365 * DAY), now));
        assert!(!due(0, Some(now + DAY), now));
    }

    #[test]
    fn the_timer_follows_the_choice() {
        assert_eq!(
            timer_command(true).join(" "),
            "systemctl --user enable --now shipwright-reef-check.timer"
        );
        assert_eq!(
            timer_command(false).join(" "),
            "systemctl --user disable --now shipwright-reef-check.timer"
        );
    }

    #[test]
    fn wifi_only_follows_the_default_route() {
        let s = |pairs: &[(&str, &str)]| {
            pairs
                .iter()
                .map(|(a, b)| ((*a).to_string(), (*b).to_string()))
                .collect::<Vec<_>>()
        };
        assert!(unmetered(&s(&[("wifi", "online"), ("cellular", "ready")])));
        assert!(!unmetered(&s(&[("cellular", "online"), ("wifi", "ready")])));
        // A Wi-Fi network in range but not connected does not count.
        assert!(!unmetered(&s(&[("wifi", "idle"), ("cellular", "online")])));
        assert!(unmetered(&s(&[
            ("bluetooth", "idle"),
            ("ethernet", "ready")
        ])));
        assert!(!unmetered(&[]));
    }

    fn up(title: &str, key: &str) -> Update {
        Update {
            title: title.into(),
            key: key.into(),
        }
    }

    #[test]
    fn announces_each_update_once() {
        let pilot = up("Pilot", "shoal-pilot 0.1.0-28");
        assert!(news(std::slice::from_ref(&pilot), ""));
        assert!(!news(std::slice::from_ref(&pilot), "shoal-pilot 0.1.0-28"));
        // A newer version is news.
        let newer = up("Pilot", "shoal-pilot 0.1.0-29");
        assert!(news(&[newer], "shoal-pilot 0.1.0-28"));
        // So is another app joining the ones already announced.
        let migrate = up("Shoal Migrate", "shipwright-shoal-migrate 0.1.0-9");
        assert!(news(&[pilot, migrate], "shoal-pilot 0.1.0-28"));
        assert!(!news(&[], "shoal-pilot 0.1.0-28"));
    }

    #[test]
    fn names_the_apps() {
        let a = up("Pilot", "a 1");
        let b = up("Shoal Migrate", "b 1");
        let c = up("Reef", "c 1");
        let d = up("Pacific", "d 1");
        assert_eq!(
            wording(std::slice::from_ref(&a)),
            (
                "Pilot update ready".into(),
                "Tap to update it in Reef".into()
            )
        );
        assert_eq!(
            wording(&[a, b, c, d]),
            (
                "4 app updates ready".into(),
                "Pilot, Shoal Migrate and 2 more".into()
            )
        );
    }
}
