//! An app's `backgroundTasks`, read from its manifest.json and checked.

use serde::Deserialize;
use serde_json::Value;

use crate::check::Network;

/// Wake-up slots, as nemo-keepalive's `BackgroundActivity` frequencies: every
/// app on one interval elapses at the same wall-clock instant.
const INTERVALS: [(u32, &str); 9] = [
    (15, "*:00/15"),
    (30, "*:00/30"),
    (60, "hourly"),
    (120, "00/2:00"),
    (240, "00/4:00"),
    (360, "00/6:00"),
    (480, "00/8:00"),
    (720, "00/12:00"),
    (1440, "daily"),
];
const MIN_WAKE_INTERVAL: u32 = 60;
const MAX_TIMEOUT: u32 = 600;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Manifest {
    id: String,
    name: String,
    #[serde(default)]
    background_tasks: Vec<Value>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Declared {
    id: String,
    action: String,
    interval_minutes: u32,
    network: Option<Network>,
    #[serde(default)]
    requires_charging: bool,
    #[serde(default)]
    requires_battery_not_low: bool,
    #[serde(default)]
    wake: bool,
    #[serde(default = "default_timeout")]
    timeout_seconds: u32,
}

fn default_timeout() -> u32 {
    60
}

#[derive(Debug, PartialEq, Eq)]
pub struct Task {
    pub app_id: String,
    pub app_name: String,
    pub id: String,
    pub action: String,
    pub on_calendar: &'static str,
    pub network: Option<Network>,
    pub requires_charging: bool,
    pub requires_battery_not_low: bool,
    pub wake: bool,
    pub timeout_seconds: u32,
}

impl Task {
    /// `marathon-wake-*` timers may wake a suspended device; `marathon-bg-*`
    /// ones run while it is awake or dozing.
    pub fn unit_stem(&self) -> String {
        let kind = if self.wake { "wake" } else { "bg" };
        format!("marathon-{kind}-{}.{}", self.app_id, self.id)
    }
}

/// Each element is `[A-Za-z_][A-Za-z0-9_-]*`, so `org.marathonos.<id>` is a
/// bus name and the id is safe in a unit name.
fn valid_app_id(id: &str) -> bool {
    id.len() <= 64
        && id.split('.').all(|part| {
            let mut chars = part.chars();
            chars
                .next()
                .is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
                && chars.all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
        })
}

fn valid_task_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 32
        && !id.starts_with('-')
        && !id.ends_with('-')
        && id
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

fn valid_action(action: &str) -> bool {
    !action.is_empty()
        && action.len() <= 64
        && action
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
}

fn plain_name(name: &str) -> String {
    let cleaned: String = name
        .chars()
        .filter(|c| !c.is_control() && *c != '%')
        .collect();
    cleaned.trim().to_owned()
}

/// The app's tasks, and one message for each declaration that was refused.
pub fn parse(manifest: &str) -> Result<(Vec<Task>, Vec<String>), String> {
    let manifest: Manifest =
        serde_json::from_str(manifest).map_err(|e| format!("manifest: {e}"))?;
    if !valid_app_id(&manifest.id) {
        return Err(format!("app id {:?} cannot name a unit", manifest.id));
    }
    let mut tasks: Vec<Task> = Vec::new();
    let mut refused = Vec::new();
    for value in manifest.background_tasks {
        match validate(&manifest.id, &manifest.name, value) {
            Ok(task) if tasks.iter().any(|t| t.id == task.id) => {
                refused.push(format!("task {:?} is declared twice", task.id));
            }
            Ok(task) => tasks.push(task),
            Err(e) => refused.push(e),
        }
    }
    Ok((tasks, refused))
}

fn validate(app_id: &str, app_name: &str, value: Value) -> Result<Task, String> {
    let d: Declared = serde_json::from_value(value).map_err(|e| format!("task: {e}"))?;
    let name = &d.id;
    if !valid_task_id(name) {
        return Err(format!("task id {name:?} is not [a-z0-9-]"));
    }
    if !valid_action(&d.action) {
        return Err(format!("task {name:?}: action {:?} is not valid", d.action));
    }
    let Some(&(_, on_calendar)) = INTERVALS.iter().find(|(m, _)| *m == d.interval_minutes) else {
        return Err(format!(
            "task {name:?}: intervalMinutes {} is not one of {:?}",
            d.interval_minutes,
            INTERVALS.map(|(m, _)| m)
        ));
    };
    if d.wake && d.interval_minutes < MIN_WAKE_INTERVAL {
        return Err(format!(
            "task {name:?}: a task that wakes the device runs at most hourly"
        ));
    }
    if d.timeout_seconds == 0 || d.timeout_seconds > MAX_TIMEOUT {
        return Err(format!(
            "task {name:?}: timeoutSeconds must be 1..={MAX_TIMEOUT}"
        ));
    }
    Ok(Task {
        app_id: app_id.to_owned(),
        app_name: plain_name(app_name),
        id: d.id,
        action: d.action,
        on_calendar,
        network: d.network,
        requires_charging: d.requires_charging,
        requires_battery_not_low: d.requires_battery_not_low,
        wake: d.wake,
        timeout_seconds: d.timeout_seconds,
    })
}

/// Whether the app's Keel Actions manifest (actions.json) declares `action`
/// as one that runs unattended: no one is there to confirm it.
pub fn keel_declares(keel_manifest: &str, action: &str) -> bool {
    let Ok(value) = serde_json::from_str::<Value>(keel_manifest) else {
        return false;
    };
    value["tools"].as_array().is_some_and(|tools| {
        tools.iter().any(|tool| {
            let meta = &tool["_meta"];
            meta["org.shipwright.keel/action"] == action
                && meta["org.shipwright.keel/confirm"] != true
        })
    })
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    fn manifest(tasks: &str) -> String {
        format!(r#"{{"id": "email", "name": "Mail", "backgroundTasks": [{tasks}]}}"#)
    }

    #[test]
    fn a_full_declaration_is_read() {
        let (tasks, refused) = parse(&manifest(
            r#"{"id": "sync", "action": "mail.sync", "intervalMinutes": 60,
                "network": "unmetered", "requiresCharging": true,
                "requiresBatteryNotLow": true, "wake": true, "timeoutSeconds": 120}"#,
        ))
        .unwrap();
        assert!(refused.is_empty(), "{refused:?}");
        assert_eq!(
            tasks,
            [Task {
                app_id: "email".into(),
                app_name: "Mail".into(),
                id: "sync".into(),
                action: "mail.sync".into(),
                on_calendar: "hourly",
                network: Some(Network::Unmetered),
                requires_charging: true,
                requires_battery_not_low: true,
                wake: true,
                timeout_seconds: 120,
            }]
        );
        assert_eq!(tasks[0].unit_stem(), "marathon-wake-email.sync");
    }

    #[test]
    fn defaults_make_an_awake_only_task_without_constraints() {
        let (tasks, _) = parse(&manifest(
            r#"{"id": "sync", "action": "mail.sync", "intervalMinutes": 15}"#,
        ))
        .unwrap();
        let task = &tasks[0];
        assert_eq!(task.on_calendar, "*:00/15");
        assert_eq!(task.network, None);
        assert!(!task.wake && !task.requires_charging && !task.requires_battery_not_low);
        assert_eq!(task.timeout_seconds, 60);
        assert_eq!(task.unit_stem(), "marathon-bg-email.sync");
    }

    #[test]
    fn a_manifest_without_tasks_has_none() {
        let (tasks, refused) = parse(r#"{"id": "calculator", "name": "Calculator"}"#).unwrap();
        assert!(tasks.is_empty() && refused.is_empty());
    }

    #[test]
    fn intervals_off_the_slots_are_refused() {
        for minutes in [0, 1, 14, 45, 90, 2880] {
            let (tasks, refused) = parse(&manifest(&format!(
                r#"{{"id": "sync", "action": "mail.sync", "intervalMinutes": {minutes}}}"#
            )))
            .unwrap();
            assert!(tasks.is_empty(), "{minutes}");
            assert!(refused[0].contains("intervalMinutes"), "{refused:?}");
        }
    }

    #[test]
    fn a_wake_task_runs_at_most_hourly() {
        let (tasks, refused) = parse(&manifest(
            r#"{"id": "sync", "action": "mail.sync", "intervalMinutes": 30, "wake": true}"#,
        ))
        .unwrap();
        assert_eq!(tasks, Vec::<Task>::new());
        assert!(refused[0].contains("at most hourly"));
    }

    #[test]
    fn timeouts_are_bounded() {
        for timeout in [0, 601] {
            let (tasks, _) = parse(&manifest(&format!(
                r#"{{"id": "sync", "action": "a", "intervalMinutes": 60, "timeoutSeconds": {timeout}}}"#
            )))
            .unwrap();
            assert!(tasks.is_empty(), "{timeout}");
        }
    }

    #[test]
    fn ids_and_actions_that_could_escape_a_unit_line_are_refused() {
        for (id, action) in [
            ("Sync", "a"),
            ("sy nc", "a"),
            ("-sync", "a"),
            ("sync.x", "a"),
            ("sync", "a b"),
            ("sync", "a\nExecStart=/bin/sh"),
            ("sync", "%h"),
            ("sync", ""),
        ] {
            let json = serde_json::json!({"id": id, "action": action, "intervalMinutes": 60});
            let (tasks, refused) = parse(&manifest(&json.to_string())).unwrap();
            assert!(tasks.is_empty(), "{id:?} {action:?}");
            assert_eq!(refused.len(), 1);
        }
    }

    #[test]
    fn app_ids_must_be_bus_name_elements() {
        for id in ["", "1app", "a..b", "a b", "a/b", "../x"] {
            let json = serde_json::json!({"id": id, "name": "x"});
            assert!(parse(&json.to_string()).is_err(), "{id:?}");
        }
        assert!(parse(r#"{"id": "org.example.My_App-2", "name": "x"}"#).is_ok());
    }

    #[test]
    fn one_bad_task_does_not_hide_the_others() {
        let (tasks, refused) = parse(&manifest(
            r#"{"id": "a", "action": "x", "intervalMinutes": 60},
               {"id": "b", "action": "x", "intervalMinutes": 7},
               {"id": "a", "action": "y", "intervalMinutes": 30},
               {"action": "x"}"#,
        ))
        .unwrap();
        assert_eq!(tasks.len(), 1);
        assert_eq!(refused.len(), 3);
    }

    #[test]
    fn unprintable_app_names_are_cleaned() {
        let (tasks, _) = parse(
            r#"{"id": "email", "name": " Mail\n100%", "backgroundTasks":
               [{"id": "a", "action": "x", "intervalMinutes": 60}]}"#,
        )
        .unwrap();
        assert_eq!(tasks[0].app_name, "Mail100");
    }

    #[test]
    fn keel_manifests_are_searched_for_the_action() {
        let keel = r#"{"tools": [{"_meta": {"org.shipwright.keel/action": "mail.sync"}}]}"#;
        assert!(keel_declares(keel, "mail.sync"));
        assert!(!keel_declares(keel, "mail.send"));
        assert!(!keel_declares("not json", "mail.sync"));
        assert!(!keel_declares(r#"{"tools": 3}"#, "mail.sync"));
    }

    #[test]
    fn actions_that_ask_for_confirmation_cannot_run_in_the_background() {
        let keel = r#"{"tools": [{"_meta": {"org.shipwright.keel/action": "mail.purge",
                                            "org.shipwright.keel/confirm": true}},
                                 {"_meta": {"org.shipwright.keel/action": "mail.sync",
                                            "org.shipwright.keel/confirm": false}}]}"#;
        assert!(!keel_declares(keel, "mail.purge"));
        assert!(keel_declares(keel, "mail.sync"));
    }
}
