// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! The app's home before anything is asked: what is running (timers,
//! alarms, reminders), what is next (the calendar), what needs the person
//! (triage), and questions that fit the moment. All of it read on the
//! phone, nothing sent anywhere, so it is there the instant the app opens.

use serde::Serialize;

use crate::adapters::{Adapters, CalendarEvent, ClockItem};
use crate::localtime::LocalNow;
use crate::store::{Store, TriageItem};

/// How far ahead the calendar part looks.
const EVENTS_AHEAD_SECS: i64 = 36 * 3600;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Now {
    /// "Good morning", "Good afternoon", "Good evening".
    pub greeting: String,
    /// "Wednesday 7 October".
    pub date: String,
    pub clock: Vec<ClockItem>,
    pub events: Vec<CalendarEvent>,
    /// Triaged items that need the person (act now or today).
    pub attention: Vec<TriageItem>,
    pub suggestions: Vec<Suggestion>,
    pub offline: bool,
    /// The app Pilot was opened over, whose screen is the context now.
    pub on_screen: Option<String>,
}

/// A question for one tap, with what the UI draws beside it: calendar,
/// news, weather-day, weather-night, timer, alarm or reminder.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Suggestion {
    pub text: String,
    pub icon: String,
}

/// The home's first line, with some personality: the time of day said
/// several ways ("Hello, night owl"), the person's name when Pilot has
/// one ("Morning, Patrick"), and a welcome after days away ("Patrick
/// returns!"). The day picks among the ways, so it stays put while the app
/// is open and changes from one day to the next.
pub fn greeting(now: &LocalNow, name: &str, away_days: i64) -> String {
    let n = name.trim();
    let named = |with: &str, without: &str| {
        if n.is_empty() {
            without.to_owned()
        } else {
            with.replace("{n}", n)
        }
    };
    if away_days >= 3 {
        return named("{n} returns!", "Welcome back");
    }
    let options: Vec<String> = match now.hour {
        5..=11 => vec![
            "Good morning".into(),
            named("Morning, {n}", "Morning"),
            "Rise and shine".into(),
        ],
        12..=16 => vec![
            "Good afternoon".into(),
            named("Afternoon, {n}", "Afternoon"),
            named("Hi, {n}", "Hello there"),
        ],
        17..=21 => vec![
            "Good evening".into(),
            named("Evening, {n}", "Evening"),
            named("Hi, {n}", "Hello there"),
        ],
        _ => vec![
            "Hello, night owl".into(),
            named("Still up, {n}?", "Still up?"),
            "Burning the midnight oil".into(),
        ],
    };
    let day = usize::try_from(now.epoch.div_euclid(86_400)).unwrap_or(0);
    options[day % options.len()].clone()
}

/// Four questions worth one tap now: the day ahead in the morning and
/// tomorrow in the evening, the weather and the news (online), and a timer.
/// Offline, only what the phone answers itself.
pub fn suggestions(now: &LocalNow, has_events: bool, offline: bool) -> Vec<Suggestion> {
    let evening = now.hour >= 17 || now.hour < 5;
    let mut s: Vec<(&str, &str)> = Vec::new();
    s.push(match now.hour {
        5..=11 if has_events => ("What's on today?", "calendar"),
        5..=11 => ("What's on today?", "calendar"),
        12..=16 => ("What's on this afternoon?", "calendar"),
        _ => ("What's on tomorrow?", "calendar"),
    });
    if offline {
        s.push(("Wake me at 7", "alarm"));
        s.push(("Remind me in an hour", "reminder"));
    } else {
        s.push(if evening {
            ("Weather tomorrow?", "weather-night")
        } else {
            ("Weather today?", "weather-day")
        });
        s.push(("What's in the news?", "news"));
    }
    s.push(("Timer for 10 minutes", "timer"));
    s.into_iter()
        .map(|(text, icon)| Suggestion {
            text: text.into(),
            icon: icon.into(),
        })
        .collect()
}

pub async fn snapshot(
    adapters: &Adapters,
    store: &Store,
    now: &LocalNow,
    offline: bool,
    name: &str,
) -> Now {
    // Days since the home was last shown (the first time: none).
    let last: Option<i64> = store
        .meta("home.last_ms")
        .ok()
        .flatten()
        .and_then(|v| v.parse().ok());
    let _ = store.set_meta("home.last_ms", &crate::store::now_ms().to_string());
    let away_days = last.map_or(0, |l| (crate::store::now_ms() - l) / 86_400_000);
    let clock = adapters.clock.upcoming().await.unwrap_or_default();
    let events = adapters
        .calendar
        .events(now.epoch, now.epoch + EVENTS_AHEAD_SECS, 3)
        .unwrap_or_default();
    let attention = store
        .triage(20)
        .unwrap_or_default()
        .into_iter()
        .filter(|t| t.bucket == "act_now" || t.bucket == "today")
        .take(3)
        .collect();
    // "Wednesday 7 October", "Mittwoch, 7. Oktober": in the person's
    // language.
    let date = now.day_and_month_in(&crate::lang::current());
    Now {
        greeting: greeting(now, name, away_days),
        date,
        suggestions: suggestions(now, !events.is_empty(), offline),
        clock,
        events,
        attention,
        offline,
        on_screen: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn suggestions_fit_the_hour() {
        let at = |h: u32| LocalNow {
            hour: h,
            ..LocalNow::fixed_utc(1_791_374_400)
        };
        let texts = |v: Vec<Suggestion>| v.into_iter().map(|s| s.text).collect::<Vec<_>>();
        assert_eq!(
            texts(suggestions(&at(8), true, false))[0],
            "What's on today?"
        );
        assert_eq!(
            texts(suggestions(&at(20), false, false)),
            [
                "What's on tomorrow?",
                "Weather tomorrow?",
                "What's in the news?",
                "Timer for 10 minutes"
            ]
        );
        assert!(texts(suggestions(&at(20), false, true))
            .iter()
            .all(|s| !s.contains("news") && !s.contains("Weather")));
        assert_eq!(suggestions(&at(9), false, false)[1].icon, "weather-day");
        let day = |d: i64, h: u32| LocalNow {
            hour: h,
            epoch: d * 86_400,
            ..LocalNow::fixed_utc(0)
        };
        // Late at night, three ways over three days, the name in one.
        let late: Vec<String> = (0..3)
            .map(|d| greeting(&day(d, 23), "Patrick", 0))
            .collect();
        assert!(late.contains(&"Hello, night owl".to_owned()));
        assert!(late.contains(&"Still up, Patrick?".to_owned()));
        assert_eq!(greeting(&day(5, 23), "", 0), greeting(&day(5, 23), "", 0));
        assert!(!(0..3).any(|d| greeting(&day(d, 8), "", 0).contains("{n}")));
        assert_eq!(greeting(&day(1, 9), "Patrick", 4), "Patrick returns!");
        assert_eq!(greeting(&day(1, 9), "", 4), "Welcome back");
    }
}
