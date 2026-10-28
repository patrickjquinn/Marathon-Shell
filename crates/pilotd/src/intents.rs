// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Local, deterministic understanding of the five spike intents (spec
//! section 15, phase 0: timer, alarm, reminder, media, calendar query).
//!
//! Jev says *which* intent; these parsers pull the slots (a duration, a
//! clock time, a media action) out of the original utterance on the device.
//! A slot that cannot be parsed is the "missing required detail" case and
//! gets a templated clarifying question, not a model call.
//!
//! [`local_intent`] also recognises them without Jev, so that with the
//! privacy switch engaged the deterministic handlers still work from text
//! input (section 8.3). English only for now.

use std::sync::OnceLock;

use regex::Regex;
use serde::Serialize;

/// The Jev intent options of section 5.1, in order.
pub const INTENTS: &[&str] = &[
    "alarm",
    "timer",
    "reminder",
    "call",
    "message",
    "calendar_add",
    "calendar_query",
    "media",
    "device_toggle",
    "navigation",
    "camera_vision",
    "weather",
    "note",
    "email",
    "settings_page",
    "open_ended",
    "cancel",
];

/// Intents with a deterministic handler in this build.
pub const DETERMINISTIC: &[&str] = &[
    "alarm",
    "timer",
    "reminder",
    "media",
    "calendar_query",
    "cancel",
];

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum MediaAction {
    Play,
    Pause,
    Toggle,
    Stop,
    Next,
    Previous,
}

impl MediaAction {
    pub fn as_str(self) -> &'static str {
        match self {
            MediaAction::Play => "play",
            MediaAction::Pause => "pause",
            MediaAction::Toggle => "toggle",
            MediaAction::Stop => "stop",
            MediaAction::Next => "next",
            MediaAction::Previous => "previous",
        }
    }

    pub fn parse(s: &str) -> Option<MediaAction> {
        Some(match s {
            "play" => MediaAction::Play,
            "pause" => MediaAction::Pause,
            "toggle" => MediaAction::Toggle,
            "stop" => MediaAction::Stop,
            "next" => MediaAction::Next,
            "previous" => MediaAction::Previous,
            _ => return None,
        })
    }
}

/// When a reminder fires.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum When {
    /// Seconds from now.
    In(u32),
    /// A local clock time, `day_offset` days from today (0 = the next
    /// occurrence today or tomorrow, decided by the handler).
    At {
        hour: u32,
        minute: u32,
        day_offset: u32,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum DayRange {
    Today,
    Tomorrow,
    /// The next seven days.
    Week,
    /// The next event, whenever it is.
    Next,
    /// A named day of the week (0 is Sunday): the next one, or today on
    /// that day.
    Weekday(u32),
}

/// The days of the week, from Sunday (0), as the calendar names them.
pub const WEEKDAYS: [&str; 7] = [
    "sunday",
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
];

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub enum Slots {
    Timer {
        seconds: u32,
        label: Option<String>,
    },
    Alarm {
        hour: u32,
        minute: u32,
        label: Option<String>,
    },
    Reminder {
        what: String,
        when: When,
    },
    Media(MediaAction),
    CalendarQuery(DayRange),
    Cancel,
}

/// Why slots could not be filled: drives the clarifying question.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Missing {
    Duration,
    Time,
    /// A clock time that could be morning or evening ("7:15").
    DayPart {
        hour: u32,
        minute: u32,
    },
    ReminderText,
    MediaAction,
    Unsupported,
}

fn re(cell: &'static OnceLock<Regex>, pattern: &str) -> &'static Regex {
    cell.get_or_init(|| Regex::new(pattern).expect("static regex"))
}

const ONES: [&str; 9] = [
    "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
];
const TEENS: [&str; 10] = [
    "ten",
    "eleven",
    "twelve",
    "thirteen",
    "fourteen",
    "fifteen",
    "sixteen",
    "seventeen",
    "eighteen",
    "nineteen",
];
const TENS: [&str; 8] = [
    "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
];

/// A whole number from 1 to 99 in words ("eleven", "twenty five",
/// "forty-five") or digits.
pub fn whole_number(w: &str) -> Option<u32> {
    let w = w.trim().to_lowercase().replace('-', " ");
    if let Ok(n) = w.parse() {
        return Some(n);
    }
    let pos = |list: &[&str], x: &str| list.iter().position(|y| *y == x);
    let mut parts = w.split_whitespace();
    let first = parts.next()?;
    let second = parts.next();
    if parts.next().is_some() {
        return None;
    }
    let n = if let Some(i) = pos(&ONES, first) {
        i + 1
    } else if let Some(i) = pos(&TEENS, first) {
        i + 10
    } else {
        (pos(&TENS, first)? + 2) * 10
    };
    let n = match second {
        None => n,
        Some(o) if n >= 20 && n % 10 == 0 => n + pos(&ONES, o)? + 1,
        Some(_) => return None,
    };
    u32::try_from(n).ok()
}

/// [`whole_number`]'s words as a regex alternative.
fn number_pattern() -> String {
    format!(
        r"(?:{})(?:[\s-](?:{}))?|{}|{}",
        TENS.join("|"),
        ONES.join("|"),
        TEENS.join("|"),
        ONES.join("|")
    )
}

fn number_word(w: &str) -> Option<f64> {
    Some(match w {
        "a" | "an" => 1.0,
        "half" | "half an" | "half a" => 0.5,
        "a quarter of an" | "quarter of an" | "a quarter" => 0.25,
        _ => match whole_number(w) {
            Some(n) => f64::from(n),
            None => w.parse().ok()?,
        },
    })
}

/// A duration such as "5 minutes", "1h30m", "an hour and a half",
/// "half an hour", "90 seconds". Seconds, capped at one week.
pub fn parse_duration(text: &str) -> Option<u32> {
    static RE: OnceLock<Regex> = OnceLock::new();
    static SPLIT: OnceLock<Regex> = OnceLock::new();
    let r = re(
        &RE,
        &format!(
            r"(?i)\b(\d+(?:\.\d+)?|{}|an?|half(?: an?)?|(?:a )?quarter(?: of an)?)\s*-?\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b(\s+and\s+a\s+half)?",
            number_pattern()
        ),
    );
    // "1h30m" -> "1h 30m", so each part has its word boundary.
    let spaced = re(&SPLIT, r"([a-zA-Z])(\d)").replace_all(text, "$1 $2");
    let mut total = 0.0;
    let mut any = false;
    for c in r.captures_iter(&spaced) {
        let n = number_word(&c[1].to_lowercase())?;
        let unit = c[2].to_lowercase();
        let secs = if unit.starts_with('h') {
            3600.0
        } else if unit.starts_with('m') {
            60.0
        } else {
            1.0
        };
        let half = if c.get(3).is_some() { 0.5 } else { 0.0 };
        total += (n + half) * secs;
        any = true;
    }
    if !any || !(1.0..=7.0 * 86400.0).contains(&total) {
        return None;
    }
    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        reason = "bounded to one week above"
    )]
    Some(total.round() as u32)
}

/// A clock time: "7:30", "7.30pm", "at 7", "6 am", "noon", "midnight".
/// A bare number counts only after "at"/"for", so "5 minutes" is not 5:00.
const HOUR_WORDS: [&str; 12] = [
    "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
    "twelve",
];

/// "six thirty" → "6:30", "half six" → "6:30", "quarter past seven" →
/// "7:15", "quarter to eight" → "7:45", "seven o'clock" → "7:00", "at six"
/// → "at 6": times as people say them (and as speech recognition writes
/// them), in digits for [`parse_clock`].
fn time_words(lower: &str) -> String {
    static MINUTES: OnceLock<Regex> = OnceLock::new();
    static HALF: OnceLock<Regex> = OnceLock::new();
    static QUARTER: OnceLock<Regex> = OnceLock::new();
    static OCLOCK: OnceLock<Regex> = OnceLock::new();
    static AT: OnceLock<Regex> = OnceLock::new();
    let hours = HOUR_WORDS.join("|");
    let hour = |w: &str| {
        HOUR_WORDS
            .iter()
            .position(|h| *h == w)
            .map_or_else(|| w.parse().unwrap_or(0), |i| i + 1)
    };
    let minute = |w: &str| -> Option<usize> {
        let w = w.replace('-', " ");
        let mut parts = w.split_whitespace();
        let tens = match parts.next()? {
            "oh" => 0,
            "ten" => return Some(10),
            "fifteen" => return Some(15),
            "twenty" => 20,
            "thirty" => 30,
            "forty" => 40,
            "fifty" => 50,
            _ => return None,
        };
        let ones = match parts.next() {
            None => 0,
            Some(u) => HOUR_WORDS[..9].iter().position(|h| *h == u)? + 1,
        };
        Some(tens + ones)
    };
    let half = re(
        &HALF,
        &format!(r"\bhalf\s+(?:past\s+)?({hours}|\d{{1,2}})\b"),
    );
    let mut out = half
        .replace_all(lower, |c: &regex::Captures| format!("{}:30", hour(&c[1])))
        .into_owned();
    let quarter = re(
        &QUARTER,
        &format!(r"\b(?:a\s+)?quarter\s+(past|after|to)\s+({hours}|\d{{1,2}})\b"),
    );
    out = quarter
        .replace_all(&out, |c: &regex::Captures| {
            let h = hour(&c[2]);
            if &c[1] == "to" {
                format!("{}:45", if h <= 1 { 12 } else { h - 1 })
            } else {
                format!("{h}:15")
            }
        })
        .into_owned();
    let oclock = re(&OCLOCK, &format!(r"\b({hours})\s+o'?\s?clock\b"));
    out = oclock
        .replace_all(&out, |c: &regex::Captures| format!("{}:00", hour(&c[1])))
        .into_owned();
    let minutes = re(
        &MINUTES,
        &format!(
            r"\b({hours})\s+(oh[\s-](?:one|two|three|four|five|six|seven|eight|nine)|ten|fifteen|(?:twenty|thirty|forty|fifty)(?:[\s-](?:one|two|three|four|five|six|seven|eight|nine))?)\b"
        ),
    );
    out = minutes
        .replace_all(&out, |c: &regex::Captures| match minute(&c[2]) {
            Some(m) => format!("{}:{m:02}", hour(&c[1])),
            None => c[0].to_owned(),
        })
        .into_owned();
    let at = re(&AT, &format!(r"\b(at|for|until|till)\s+({hours})\b"));
    at.replace_all(&out, |c: &regex::Captures| {
        format!("{} {}", &c[1], hour(&c[2]))
    })
    .into_owned()
}

pub fn parse_clock(text: &str) -> Option<(u32, u32)> {
    static RE: OnceLock<Regex> = OnceLock::new();
    let lower = time_words(&text.to_lowercase());
    if lower.contains("noon") || lower.contains("midday") {
        return Some((12, 0));
    }
    if lower.contains("midnight") {
        return Some((0, 0));
    }
    let r = re(
        &RE,
        r"(?i)(?:\b(at|for|until|till)\s+)?\b(\d{1,2})(?:[:.](\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?(?:\s|$|[,.!?])",
    );
    for c in r.captures_iter(&lower) {
        let has_min = c.get(3).is_some();
        let ampm = c.get(4).map(|m| m.as_str().replace('.', ""));
        let anchored = c.get(1).is_some();
        if !has_min && ampm.is_none() && !anchored {
            continue;
        }
        let mut h: u32 = c[2].parse().ok()?;
        let m: u32 = c.get(3).map_or(Some(0), |m| m.as_str().parse().ok())?;
        // "for 5 minutes": a duration, not a time.
        let rest = &lower[c.get(0)?.end()..];
        if !has_min && ampm.is_none() && starts_with_unit(rest) {
            continue;
        }
        match ampm.as_deref() {
            Some("pm") if h < 12 => h += 12,
            Some("am") if h == 12 => h = 0,
            None if h < 12 && evening(&lower) => h += 12,
            _ => {}
        }
        if h < 24 && m < 60 {
            return Some((h, m));
        }
    }
    None
}

/// "in the evening", "tonight", "7 at night" (not "midnight").
fn evening(lower: &str) -> bool {
    let has = |w: &str| lower.split(|c: char| !c.is_alphanumeric()).any(|x| x == w);
    has("afternoon") || has("evening") || has("tonight") || has("night")
}

/// A clock time in `text` that could be morning or evening: an hour from 1
/// to 11 with no "am"/"pm", no part of the day and not "wake me" (a morning).
pub fn open_day_part(text: &str) -> Option<(u32, u32)> {
    // "7am", "7 p.m.", and a leading zero ("07:15"), meant as written.
    static RE: OnceLock<Regex> = OnceLock::new();
    let lower = text.to_lowercase();
    let has = |w: &str| lower.split(|c: char| !c.is_alphanumeric()).any(|x| x == w);
    let written = re(&RE, r"\d\s*[ap]\.?m\b|\b[ap]\.?m\b|\b0\d[:.]\d{2}\b");
    if written.is_match(&lower) || has("morning") || evening(&lower) || lower.contains("wake me") {
        return None;
    }
    parse_clock(text).filter(|&(h, _)| (1..12).contains(&h))
}

fn starts_with_unit(rest: &str) -> bool {
    let w = rest
        .trim_start()
        .split(|c: char| !c.is_alphabetic())
        .next()
        .unwrap_or("");
    matches!(
        w,
        "h" | "hr"
            | "hrs"
            | "hour"
            | "hours"
            | "m"
            | "min"
            | "mins"
            | "minute"
            | "minutes"
            | "s"
            | "sec"
            | "secs"
            | "second"
            | "seconds"
    )
}

fn label_after(text: &str, keywords: &[&str]) -> Option<String> {
    let lower = text.to_ascii_lowercase();
    for k in keywords {
        if let Some(i) = lower.find(k) {
            let label = text[i + k.len()..]
                .trim()
                .trim_end_matches(['.', '!', '?'])
                .trim();
            if !label.is_empty() && label.len() <= 60 {
                return Some(label.to_owned());
            }
        }
    }
    None
}

pub fn parse_timer(text: &str) -> Result<Slots, Missing> {
    let seconds = parse_duration(text).ok_or(Missing::Duration)?;
    let label = label_after(
        text,
        &[" called ", " named ", " labelled ", " for the ", " for my "],
    );
    Ok(Slots::Timer { seconds, label })
}

pub fn parse_alarm(text: &str) -> Result<Slots, Missing> {
    let (hour, minute) = parse_clock(text).ok_or(Missing::Time)?;
    let label = label_after(text, &[" called ", " named ", " labelled "]);
    Ok(Slots::Alarm {
        hour,
        minute,
        label,
    })
}

pub fn parse_reminder(text: &str) -> Result<Slots, Missing> {
    static WHAT: OnceLock<Regex> = OnceLock::new();
    static AFTER: OnceLock<Regex> = OnceLock::new();
    let what_re = re(
        &WHAT,
        r"(?i)\bremind\s+me\s+(?:to|about|that)\s+(.+?)(?:\s+(?:in|at|on|tomorrow|tonight|this|by|after)\b.*)?$",
    );
    let lower = text.to_lowercase();
    let day_offset = u32::from(lower.contains("tomorrow"));
    // "in 20 minutes" wins over a clock time; "tomorrow" needs a time.
    let when = if lower.contains(" in ") && day_offset == 0 {
        parse_duration(text).map(When::In)
    } else {
        None
    };
    let when = when.or_else(|| {
        parse_clock(text).map(|(hour, minute)| When::At {
            hour,
            minute,
            day_offset,
        })
    });
    // "remind me tomorrow at 9 to put the bins out": the time first.
    let after_re = re(
        &AFTER,
        r"(?i)\bremind\s+me\s+(?:(?:tomorrow|tonight|today|this\s+\w+|on\s+\w+|at\s+[\w:.]+(?:\s*[ap]\.?m\.?)?|in\s+\S+\s+\w+|first\s+thing)[\s,]+)+(?:to|about|that)\s+(.+)$",
    );
    let trimmed = text.trim().trim_end_matches(['.', '!', '?']);
    let what = what_re
        .captures(trimmed)
        .or_else(|| after_re.captures(trimmed))
        .and_then(|c| c.get(1))
        .map(|m| m.as_str().trim().to_owned())
        .filter(|w| !w.is_empty());
    let what = what.ok_or(Missing::ReminderText)?;
    let when = when.ok_or(Missing::Time)?;
    Ok(Slots::Reminder { what, when })
}

pub fn parse_media(text: &str) -> Result<Slots, Missing> {
    let lower = text.to_lowercase();
    let words: Vec<&str> = lower
        .split(|c: char| !c.is_alphanumeric())
        .filter(|w| !w.is_empty())
        .collect();
    let has = |w: &str| words.contains(&w);
    let action = if has("next") || has("skip") {
        MediaAction::Next
    } else if has("previous") || has("back") || (has("last") && has("track")) {
        MediaAction::Previous
    } else if has("pause") {
        MediaAction::Pause
    } else if has("stop") {
        MediaAction::Stop
    } else if has("resume") || has("unpause") || has("continue") {
        MediaAction::Play
    } else if has("play") {
        // "play" alone, "play music", "play it again" are transport
        // controls; "play Sibelius" is a search, which needs the model.
        const FILLER: &[&str] = &[
            "play", "music", "the", "it", "again", "please", "my", "media", "song", "track",
        ];
        if words.iter().all(|w| FILLER.contains(w)) {
            MediaAction::Play
        } else {
            return Err(Missing::Unsupported);
        }
    } else {
        return Err(Missing::MediaAction);
    };
    Ok(Slots::Media(action))
}

pub fn parse_calendar_query(text: &str) -> Slots {
    let lower = text.to_lowercase();
    // "Monday", "mondays", or "mon" as a word of its own.
    let words: Vec<&str> = lower.split(|c: char| !c.is_alphabetic()).collect();
    let weekday = WEEKDAYS
        .iter()
        .position(|d| lower.contains(d) || words.contains(&&d[..3]))
        .and_then(|i| u32::try_from(i).ok());
    let range = if let Some(d) = weekday {
        DayRange::Weekday(d)
    } else if lower.contains("tomorrow") {
        DayRange::Tomorrow
    } else if lower.contains("week") {
        DayRange::Week
    } else if lower.contains("next") {
        DayRange::Next
    } else {
        DayRange::Today
    };
    Slots::CalendarQuery(range)
}

/// Slots for a Jev-chosen intent.
pub fn slots_for(intent: &str, text: &str) -> Result<Slots, Missing> {
    match intent {
        "timer" => parse_timer(text),
        "alarm" => parse_alarm(text),
        "reminder" => parse_reminder(text),
        "media" => parse_media(text),
        "calendar_query" => Ok(parse_calendar_query(text)),
        "cancel" => Ok(Slots::Cancel),
        _ => Err(Missing::Unsupported),
    }
}

/// A request to cancel a timer, alarm or reminder ("cancel the timer",
/// "turn off my alarm", "delete that reminder"): which kind, or `None` for
/// "cancel it" right after one was set. `Some(None)` only with "it"/"that".
pub fn clock_cancel(text: &str) -> Option<Option<&'static str>> {
    static RE: OnceLock<Regex> = OnceLock::new();
    let m = re(
        &RE,
        r"(?i)^\s*(?:please\s+)?(?:cancel|stop|delete|remove|turn off|switch off|dismiss|clear|get rid of)\s+(?:the\s+|my\s+|that\s+|this\s+)?(timer|alarm|reminder|it|that)s?\b[\s.!]*$",
    )
    .captures(text)?;
    Some(match m[1].to_lowercase().as_str() {
        "timer" => Some("timer"),
        "alarm" => Some("alarm"),
        "reminder" => Some("reminder"),
        _ => None,
    })
}

/// Whether `text` reads as the answer to a clarifying question ("evening",
/// "7am", "10 minutes", "the kitchen one") rather than a request of its
/// own: a few words, not itself a question, and no request Pilot knows.
pub fn answers_a_question(text: &str) -> bool {
    let t = text.trim();
    t.split_whitespace().count() <= 4 && !t.ends_with('?') && local_intent(t).is_none()
}

/// A short follow-up naming another day ("and tomorrow?", "what about
/// Friday?", "next week?"): the calendar question for that day.
pub fn calendar_follow_up(text: &str) -> Option<Slots> {
    let lower = text.trim().trim_end_matches(['?', '.', '!']).to_lowercase();
    let rest = [
        "and ",
        "what about ",
        "how about ",
        "and on ",
        "what about on ",
    ]
    .iter()
    .find_map(|p| lower.strip_prefix(p))
    .unwrap_or(&lower);
    if rest.split_whitespace().count() > 3 {
        return None;
    }
    let names_day = rest.contains("tomorrow")
        || rest.contains("week")
        || WEEKDAYS.iter().any(|d| rest.contains(d));
    names_day.then(|| parse_calendar_query(rest))
}

/// A correction of what was just asked ("make it 10 minutes instead",
/// "actually 7 o'clock", "change it to half six").
pub fn is_correction(text: &str) -> bool {
    static RE: OnceLock<Regex> = OnceLock::new();
    re(
        &RE,
        r"(?i)\binstead\b|^\s*(?:no,?\s+)?actually\b|^\s*(?:make|change)\s+(?:it|that)\b",
    )
    .is_match(text)
}

/// "text Anna I quit", "send a message to Anna saying running late": the
/// words after the verb, to be split into a contact and the message by the
/// address book. `None` for anything else, or a message that speaks of its
/// recipient ("text Anna that she should bring the keys": the model turns
/// that into words to her).
pub fn text_request(text: &str) -> Option<String> {
    let t = text.trim().trim_end_matches(['.', '!']);
    let lower = t.to_ascii_lowercase();
    let lower = lower.strip_prefix("please ").unwrap_or(&lower);
    let skip = t.len() - lower.len();
    let verbs = [
        "send a text message to ",
        "send a text to ",
        "send a message to ",
        "send a sms to ",
        "send an sms to ",
        "send text to ",
        "text ",
        "message ",
        "sms ",
    ];
    let verb = verbs.iter().find(|v| lower.starts_with(*v))?;
    let rest = t[skip + verb.len()..].trim();
    let rest_lower = rest.to_lowercase();
    if rest_lower.starts_with("me ") || rest.split_whitespace().count() < 2 {
        return None;
    }
    let speaks_of = rest_lower.split(|c: char| !c.is_alphanumeric()).any(|w| {
        matches!(
            w,
            "she" | "he" | "her" | "him" | "his" | "hers" | "they" | "them" | "their"
        )
    });
    if speaks_of || needs_model(text) {
        return None;
    }
    Some(rest.to_owned())
}

/// The message once the contact's name is taken off the front: "that I'm
/// late" → "I'm late", "saying hi" → "hi".
pub fn message_body(after_name: &str) -> Option<String> {
    let mut b = after_name.trim_start_matches([',', ':', ' ']).trim();
    for c in ["saying ", "that ", "to say ", "and say ", "and tell them "] {
        if b.to_lowercase().starts_with(c) {
            b = b[c.len()..].trim();
            break;
        }
    }
    let b = b.trim_matches(['"', '\u{201c}', '\u{201d}']).trim();
    // Words to compose, not to send as they are ("about dinner", "asking
    // if the shop is open", "to let them know"): the model writes those.
    let compose = [
        "about ",
        "asking ",
        "ask ",
        "to ask ",
        "and ask ",
        "to let ",
        "letting ",
        "let ",
        "telling ",
        "to tell ",
        "regarding ",
    ];
    let lower = b.to_lowercase();
    if compose.iter().any(|c| lower.starts_with(c)) {
        return None;
    }
    (!b.is_empty()).then(|| b.to_owned())
}

/// A lasting fact the person states about themselves in passing ("I'm
/// vegetarian, so what could I cook?", "we live in Cork now", "my wife's
/// name is Niamh"): the clause, to offer to remember. Only what lasts
/// (diet, allergies, home, work, family names), never a passing state
/// ("I'm tired", "I'm having pasta tonight").
pub fn personal_fact(text: &str) -> Option<String> {
    static RE: OnceLock<Regex> = OnceLock::new();
    let r = re(
        &RE,
        r"(?i)^(?:(?:by the way|btw|well|so|also)[, ]+)?((?:i'm|i am) (?:a )?(?:vegetarian|vegan|pescatarian|coeliac|celiac|diabetic|lactose[- ]intolerant|gluten[- ]free|allergic to [a-z ]{3,30}|left[- ]handed)|(?:i|we) (?:live|now live) in [A-Z][\w' -]{1,40}|(?:i|we)(?:'ve| have)? moved (?:from [A-Z][\w' -]{1,30} )?to [A-Z][\w' -]{1,40}|i work (?:at|for|as) [\w' -]{2,40}|my (?:wife|husband|partner|son|daughter|mum|mom|dad|brother|sister|dog|cat)(?:'s name)? is (?:called )?[A-Z][\w'-]{1,20}(?: [A-Z][\w'-]{1,20})?)",
    );
    text.split([',', '.', ';', '!', '?'])
        .flat_map(|c| c.split(" so "))
        .map(str::trim)
        .find_map(|clause| {
            let m = r.captures(clause)?.get(1)?;
            // A whole clause, or the fact ends it ("I work at Intel and...").
            let rest = clause[m.end()..].trim();
            let fact = if rest.is_empty() || rest.split_whitespace().count() > 3 {
                m.as_str()
            } else {
                clause
            };
            Some(fact.trim().to_owned())
        })
}

/// What a remembered fact is about, when a newer one of the same kind
/// replaces it: "where they live", "diet", "work", or a family member's
/// name ("my wife"). `None` for anything else (allergies add up).
pub fn fact_kind(fact: &str) -> Option<String> {
    let l = fact.to_lowercase();
    if l.contains(" live in ") || l.starts_with("i live in") || l.contains("moved") {
        return Some("home".into());
    }
    if ["vegetarian", "vegan", "pescatarian"]
        .iter()
        .any(|d| l.contains(d))
    {
        return Some("diet".into());
    }
    if l.contains("i work ") {
        return Some("work".into());
    }
    let words: Vec<&str> = l.split_whitespace().collect();
    if words.first() == Some(&"my") {
        let who = words.get(1)?.trim_end_matches("'s");
        if [
            "wife", "husband", "partner", "son", "daughter", "mum", "mom", "dad", "brother",
            "sister", "dog", "cat",
        ]
        .contains(&who)
        {
            return Some(format!("my {who}"));
        }
    }
    None
}

/// Whether a request is more than a fixed handler can do, though it may
/// look like one: two things at once ("what's my first meeting today? then
/// text Anna the time"), or a question about the calendar rather than a
/// look at it ("am I free this afternoon?", "when is my first meeting").
/// The handler would answer half of it; the model, with the same tools,
/// answers all of it.
pub fn needs_model(text: &str) -> bool {
    let l = format!(
        " {} ",
        text.to_lowercase().replace(['?', '!', ',', '.'], " ")
    );
    let compound = [
        " then ",
        " and then ",
        " after that ",
        " and text ",
        " and call ",
        " and email ",
        " and send ",
        " and make a note",
        " and remind ",
        " and tell ",
    ]
    .iter()
    .any(|k| l.contains(k));
    let calendar_question = [
        " free ",
        " busy ",
        " first ",
        " last ",
        " when is ",
        " when's ",
        " what time is ",
        " how many ",
        " clash",
        " conflict",
        " before ",
        " after ",
    ]
    .iter()
    .any(|k| l.contains(k))
        && [
            " meeting",
            " calendar",
            " free ",
            " busy ",
            " appointment",
            " event",
            " schedule",
        ]
        .iter()
        .any(|k| l.contains(k));
    compound || calendar_question
}

/// Whether `text` asks for a plan around places ("help me plan a 3 day
/// trip to Kerry", "things to do in Galway", "where should we stay in
/// Dingle"): answered from a web search first, not from the model's memory,
/// which put Slea Head on the Ring of Kerry and Loop Head in Kerry.
pub fn place_plan(text: &str) -> bool {
    let l = format!(" {} ", text.to_lowercase());
    [
        " trip ",
        " trip?",
        " itinerary",
        " things to do",
        " what to see",
        " places to visit",
        " day out",
        " weekend in ",
        " weekend away",
        " holiday in ",
        " road trip",
        " where to stay",
        " where should we stay",
        " where should i stay",
        " sightseeing",
        " walking tour",
        " what to do in ",
        " visit to ",
        " a day in ",
        " days in ",
    ]
    .iter()
    .any(|k| l.contains(k))
}

/// The web search for a [`place_plan`] question: the question without its
/// asking ("help me plan", "can you suggest"), with "things to do" added
/// unless it already says what it wants, so a keyword index finds travel
/// guides ("Plan a day in Helsinki" searches "day in Helsinki things to
/// do").
pub fn trip_query(text: &str) -> String {
    const ASKING: &[&str] = &[
        "please", "can", "could", "would", "will", "you", "help", "me", "us", "plan", "suggest",
        "give", "make", "i", "we", "want", "need", "a", "an", "some", "to", "for", "my", "our",
        "with", "lets", "let's",
    ];
    let words: Vec<&str> = text
        .trim_end_matches(['?', '.', '!'])
        .split_whitespace()
        .collect();
    let start = words
        .iter()
        .position(|w| !ASKING.contains(&w.to_lowercase().as_str()))
        .unwrap_or(0);
    let mut query = words[start..].join(" ");
    let l = format!(" {} ", query.to_lowercase());
    let says_what = [
        " itinerary",
        " things to do",
        " what to see",
        " places to visit",
        " where to stay",
        " stay in ",
        " sightseeing",
        " walking tour",
        " what to do",
    ]
    .iter()
    .any(|k| l.contains(k));
    if !says_what {
        query.push_str(" things to do");
    }
    query
}

/// Whether `text` asks about the weather, however it is put ("how warm is
/// it outside?", "do I need an umbrella", "what's the weekend looking
/// like weather wise"): a word only weather has, or a word weather often
/// has with a when or where ("cold" with "outside", "coat" with "today").
/// Such a question is answered from the weather tool, never from memory.
pub fn about_weather(text: &str) -> bool {
    let l = text.to_lowercase();
    let words: Vec<&str> = l
        .split(|c: char| !c.is_alphanumeric())
        .filter(|w| !w.is_empty())
        .collect();
    let has = |list: &[&str]| words.iter().any(|w| list.contains(w));
    let strong = [
        "weather", "forecast", "rain", "raining", "rainy", "umbrella", "snow", "snowing", "sunny",
        "windy", "drizzle", "showers", "frost", "frosty", "foggy", "humid", "humidity",
    ];
    let weak = [
        "warm",
        "hot",
        "cold",
        "chilly",
        "freezing",
        "coat",
        "jacket",
        "wind",
        "degrees",
        "temperature",
        "sunshine",
        "sun",
        "storm",
        "wet",
        "dry",
        "mild",
    ];
    let when_where = [
        "outside",
        "out",
        "today",
        "tonight",
        "tomorrow",
        "now",
        "morning",
        "afternoon",
        "evening",
        "weekend",
        "week",
        "later",
        "saturday",
        "sunday",
        "monday",
        "tuesday",
        "wednesday",
        "thursday",
        "friday",
    ];
    has(&strong) || (has(&weak) && has(&when_where))
}

/// A correction to the clock just set, as a request for the new one:
/// after a timer, "make it 12" is "set a timer for 12 minutes" (a bare
/// number keeps minutes) and "actually 20 seconds" keeps its unit; after an
/// alarm or reminder, a time is "set an alarm for 7:30". `None` when the
/// correction says nothing this can read (the model gets it as said).
pub fn correction_request(kind: &str, text: &str) -> Option<String> {
    static BARE: OnceLock<Regex> = OnceLock::new();
    match kind {
        "timer" => {
            if let Some(s) = parse_duration(text) {
                return Some(format!("set a timer for {s} seconds"));
            }
            let bare = re(&BARE, &format!(r"(?i)\b(\d{{1,3}}|{})\b", number_pattern()));
            let n = bare
                .captures_iter(text)
                .filter_map(|c| whole_number(&c[1]))
                .last()?;
            Some(format!("set a timer for {n} minutes"))
        }
        "alarm" => {
            let (h, m) =
                parse_clock(&format!("at {}", text.trim())).or_else(|| parse_clock(text))?;
            Some(format!("set an alarm for {h}:{m:02}"))
        }
        _ => None,
    }
}

/// Recognises a deterministic intent without Jev (offline mode). Only
/// unambiguous phrasings: anything else needs the network.
/// A question about whether a setting is on ("is wifi on?", "is bluetooth
/// enabled", "am I in flight mode"): the setting, as `device.status` names it.
pub fn status_question(text: &str) -> Option<&'static str> {
    let l = text.to_lowercase().replace(['?', '.', '!'], "");
    let asks = l.starts_with("is ")
        || l.starts_with("am i ")
        || l.starts_with("are ")
        || l.starts_with("check ")
        || l.contains(" on or off")
        || l.starts_with("do i have ");
    if !asks || l.split_whitespace().count() > 8 {
        return None;
    }
    let target = if l.contains("wifi") || l.contains("wi-fi") || l.contains("wlan") {
        "wifi"
    } else if l.contains("bluetooth") {
        "bluetooth"
    } else if l.contains("mobile data") || l.contains("cellular") || l.contains("data on") {
        "mobile_data"
    } else if l.contains("flight") || l.contains("airplane") || l.contains("aeroplane") {
        "flight_mode"
    } else {
        return None;
    };
    // An instruction phrased as a question is not a status check.
    (!l.contains("turn ") && !l.contains("switch ")).then_some(target)
}

/// "What can you do?" and its kin.
pub fn asks_capabilities(text: &str) -> bool {
    let l = text.to_lowercase().replace(['?', '.', '!'], "");
    let l = l.trim();
    [
        "what can you do",
        "what can you help with",
        "what can you help me with",
        "what are you able to do",
        "what do you do",
        "help",
        "what can pilot do",
        "how can you help",
    ]
    .contains(&l)
}

pub fn local_intent(text: &str) -> Option<(&'static str, Slots)> {
    let lower = text.to_lowercase();
    let has = |w: &str| lower.split(|c: char| !c.is_alphanumeric()).any(|x| x == w);
    if has("cancel") || lower.contains("never mind") || lower.contains("nevermind") {
        return Some(("cancel", Slots::Cancel));
    }
    if has("timer") {
        return parse_timer(text).ok().map(|s| ("timer", s));
    }
    if lower.contains("remind me") {
        return parse_reminder(text).ok().map(|s| ("reminder", s));
    }
    if has("alarm") || lower.contains("wake me") {
        return parse_alarm(text).ok().map(|s| ("alarm", s));
    }
    if has("calendar")
        || has("agenda")
        || has("schedule")
        || has("meetings")
        || lower.contains("what's on")
    {
        return Some(("calendar_query", parse_calendar_query(text)));
    }
    if [
        "play", "pause", "resume", "skip", "next", "previous", "stop", "unpause",
    ]
    .iter()
    .any(|w| has(w))
        && lower.split_whitespace().count() <= 5
    {
        return parse_media(text).ok().map(|s| ("media", s));
    }
    None
}

/// Something to do with what Pilot remembers, said plainly.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MemoryCommand {
    /// "Remember that my partner is Anna": the fact, as said.
    Remember(String),
    /// "Forget that my partner is Anna", "forget about the gym".
    Forget(String),
    /// "What do you remember?", "what do you know about me?"
    List,
}

/// A memory command in `text`, recognised on the phone (no model): it
/// works offline and the fact goes nowhere. "Remember to …" is a reminder,
/// not a fact, and is left to the reminder handler.
pub fn memory_command(text: &str) -> Option<MemoryCommand> {
    let t = text.trim().trim_end_matches(['.', '!']);
    let lower = t.to_ascii_lowercase();
    let mut start = 0;
    for p in [
        "hey pilot, ",
        "hey pilot ",
        "pilot, ",
        "pilot ",
        "please ",
        "can you ",
        "could you ",
    ] {
        if lower[start..].starts_with(p) {
            start += p.len();
        }
    }
    let rest = &lower[start..];
    let original = &t[start..];
    let tail = |prefix: &str| original[prefix.len()..].trim().to_owned();
    if [
        "what do you remember",
        "what do you know about me",
        "what have i told you",
    ]
    .iter()
    .any(|p| rest.starts_with(p))
    {
        return Some(MemoryCommand::List);
    }
    // "my wife's name is Niamh by the way, keep that in mind": the fact
    // first, the request after it.
    for suffix in [
        "keep that in mind",
        "bear that in mind",
        "remember that",
        "don't forget that",
        "keep it in mind",
    ] {
        if let Some(head) = rest.strip_suffix(suffix) {
            let head = head.trim_end();
            let comma =
                head.ends_with(',') || head.ends_with(" by the way") || head.ends_with(" btw");
            if !comma {
                continue;
            }
            let fact = original[..head.len()]
                .trim_end_matches(',')
                .trim_end()
                .trim_end_matches("by the way")
                .trim_end_matches("btw")
                .trim_end_matches(',')
                .trim()
                .to_owned();
            return (fact.chars().count() >= 3).then_some(MemoryCommand::Remember(fact));
        }
    }
    for p in [
        "remember that ",
        "don't forget that ",
        "keep in mind that ",
        "note that ",
    ] {
        if rest.starts_with(p) {
            let fact = tail(p);
            return (fact.chars().count() >= 3).then_some(MemoryCommand::Remember(fact));
        }
    }
    if rest.starts_with("remember ")
        && !rest.starts_with("remember to ")
        && !rest.starts_with("remember me")
    {
        let fact = tail("remember ");
        return (fact.chars().count() >= 3).then_some(MemoryCommand::Remember(fact));
    }
    // "Forget it" is "never mind".
    if rest == "forget it" {
        return None;
    }
    for p in ["forget that ", "forget about ", "forget "] {
        if rest.starts_with(p) {
            let what = tail(p);
            return (!what.is_empty()).then_some(MemoryCommand::Forget(what));
        }
    }
    None
}

/// The remembered fact that best matches `query` by shared words, if any
/// word is shared.
pub fn best_memory<'a>(query: &str, facts: &'a [(i64, String)]) -> Option<&'a (i64, String)> {
    let words = |s: &str| -> Vec<String> {
        s.to_lowercase()
            .split(|c: char| !c.is_alphanumeric())
            .filter(|w| w.len() > 2 && !["the", "that", "and", "about", "you", "with"].contains(w))
            .map(str::to_owned)
            .collect()
    };
    let q = words(query);
    facts
        .iter()
        .map(|f| (words(&f.1).iter().filter(|w| q.contains(w)).count(), f))
        .filter(|(n, _)| *n > 0)
        .max_by_key(|(n, f)| (*n, f.0))
        .map(|(_, f)| f)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn day_parts() {
        assert_eq!(
            parse_clock("remind me at 7:15 in the evening"),
            Some((19, 15))
        );
        assert_eq!(parse_clock("alarm at 9 tonight"), Some((21, 0)));
        assert_eq!(parse_clock("alarm at 7:15 morning"), Some((7, 15)));
        assert_eq!(parse_clock("alarm at midnight"), Some((0, 0)));
        assert_eq!(open_day_part("remind me to call at 7:15"), Some((7, 15)));
        assert_eq!(
            open_day_part("remind me to call at 7:15 tomorrow"),
            Some((7, 15))
        );
        for settled in [
            "wake me up at 7:15",
            "alarm at 7:15am",
            "alarm at 7.15 p.m.",
            "alarm at 07:15",
            "alarm at 19:15",
            "alarm at 7:15 in the evening",
            "remind me to stretch in 5 minutes",
            "alarm at 12:30",
        ] {
            assert_eq!(open_day_part(settled), None, "{settled}");
        }
        // Times as said.
        for (said, want) in [
            ("set an alarm for six thirty", (6, 30)),
            ("wake me at half six", (6, 30)),
            ("alarm at quarter past seven", (7, 15)),
            ("alarm at quarter to eight", (7, 45)),
            ("alarm at seven o'clock", (7, 0)),
            ("remind me to call at six", (6, 0)),
            ("alarm for seven forty-five pm", (19, 45)),
            ("alarm at six oh five", (6, 5)),
            ("set an alarm for six thirty evening", (18, 30)),
        ] {
            assert_eq!(parse_clock(said), Some(want), "{said}");
        }
        // Durations stay durations.
        assert_eq!(parse_clock("timer for six minutes"), None);
        assert_eq!(parse_clock("in half an hour"), None);
        // The answer to "7:15 in the morning or the evening?", joined.
        assert_eq!(parse_clock("set an alarm at 7:15 evening"), Some((19, 15)));
    }

    #[test]
    fn durations() {
        assert_eq!(parse_duration("set a timer for 5 minutes"), Some(300));
        assert_eq!(parse_duration("timer 1h30m"), Some(5400));
        assert_eq!(parse_duration("an hour and a half"), Some(5400));
        assert_eq!(parse_duration("half an hour"), Some(1800));
        assert_eq!(parse_duration("90 seconds"), Some(90));
        assert_eq!(parse_duration("2 hours 15 minutes"), Some(8100));
        assert_eq!(parse_duration("ten minute timer"), Some(600));
        assert_eq!(parse_duration("a timer"), None);
        assert_eq!(parse_duration("100 hours"), Some(360_000));
        assert_eq!(parse_duration("200 hours"), None);
        assert_eq!(parse_duration("pasta timer, eleven minutes"), Some(660));
        assert_eq!(parse_duration("twenty-five minutes"), Some(1500));
        assert_eq!(parse_duration("forty five seconds"), Some(45));
        assert_eq!(parse_duration("1.5 hours"), Some(5400));
        assert_eq!(whole_number("ninety nine"), Some(99));
        assert_eq!(whole_number("eleven five"), None);
    }

    #[test]
    fn clock_times() {
        assert_eq!(parse_clock("alarm at 7:30"), Some((7, 30)));
        assert_eq!(parse_clock("wake me at 6 am"), Some((6, 0)));
        assert_eq!(parse_clock("alarm for 7.15pm"), Some((19, 15)));
        assert_eq!(parse_clock("alarm 12am"), Some((0, 0)));
        assert_eq!(parse_clock("alarm at noon"), Some((12, 0)));
        assert_eq!(parse_clock("alarm at 7"), Some((7, 0)));
        assert_eq!(parse_clock("timer for 5 minutes"), None);
        assert_eq!(parse_clock("set an alarm"), None);
        assert_eq!(parse_clock("alarm at 25:00"), None);
    }

    #[test]
    fn reminders() {
        assert_eq!(
            parse_reminder("Remind me to ring <CONTACT_1> in 20 minutes"),
            Ok(Slots::Reminder {
                what: "ring <CONTACT_1>".into(),
                when: When::In(1200)
            })
        );
        assert_eq!(
            parse_reminder("remind me to take the bins out tomorrow at 7:30"),
            Ok(Slots::Reminder {
                what: "take the bins out".into(),
                when: When::At {
                    hour: 7,
                    minute: 30,
                    day_offset: 1
                }
            })
        );
        assert_eq!(
            parse_reminder("remind me to ring Anna when I get home"),
            Err(Missing::Time)
        );
        assert_eq!(
            parse_reminder("remind me at 5pm"),
            Err(Missing::ReminderText)
        );
        assert_eq!(
            parse_reminder("remind me tomorrow at 9 to put the bins out"),
            Ok(Slots::Reminder {
                what: "put the bins out".into(),
                when: When::At {
                    hour: 9,
                    minute: 0,
                    day_offset: 1
                }
            })
        );
        assert_eq!(
            parse_reminder("remind me in 2 hours to call the plumber"),
            Ok(Slots::Reminder {
                what: "call the plumber".into(),
                when: When::In(7200)
            })
        );
    }

    #[test]
    fn media() {
        assert_eq!(parse_media("pause"), Ok(Slots::Media(MediaAction::Pause)));
        assert_eq!(
            parse_media("skip this song"),
            Ok(Slots::Media(MediaAction::Next))
        );
        assert_eq!(
            parse_media("play music"),
            Ok(Slots::Media(MediaAction::Play))
        );
        assert_eq!(
            parse_media("go back a track"),
            Ok(Slots::Media(MediaAction::Previous))
        );
        assert_eq!(parse_media("play Sibelius"), Err(Missing::Unsupported));
        assert_eq!(parse_media("louder"), Err(Missing::MediaAction));
    }

    #[test]
    fn offline_recognition() {
        assert_eq!(
            local_intent("Set a timer for 10 minutes for the pasta"),
            Some((
                "timer",
                Slots::Timer {
                    seconds: 600,
                    label: Some("pasta".into())
                }
            ))
        );
        assert_eq!(
            local_intent("wake me at 6:45"),
            Some((
                "alarm",
                Slots::Alarm {
                    hour: 6,
                    minute: 45,
                    label: None
                }
            ))
        );
        assert_eq!(
            local_intent("next track"),
            Some(("media", Slots::Media(MediaAction::Next)))
        );
        assert_eq!(
            local_intent("what's on my calendar tomorrow"),
            Some(("calendar_query", Slots::CalendarQuery(DayRange::Tomorrow)))
        );
        assert_eq!(local_intent("never mind"), Some(("cancel", Slots::Cancel)));
        assert_eq!(local_intent("why is the sky blue"), None);
        assert_eq!(local_intent("set a timer"), None);
    }

    #[test]
    fn status_questions_and_capabilities() {
        assert_eq!(status_question("Is wifi on?"), Some("wifi"));
        assert_eq!(status_question("is bluetooth enabled"), Some("bluetooth"));
        assert_eq!(status_question("Am I in flight mode?"), Some("flight_mode"));
        assert_eq!(
            status_question("Is mobile data on or off?"),
            Some("mobile_data")
        );
        assert_eq!(status_question("Can you turn wifi off?"), None);
        assert_eq!(status_question("Is it going to rain?"), None);
        assert!(asks_capabilities("What can you do?"));
        assert!(asks_capabilities("help"));
        assert!(!asks_capabilities(
            "what can you do about the weather in Cork tomorrow"
        ));
    }

    #[test]
    fn intent_list_matches_spec() {
        assert_eq!(INTENTS.len(), 17);
        assert!(DETERMINISTIC.iter().all(|d| INTENTS.contains(d)));
    }

    #[test]
    fn memory_commands() {
        use MemoryCommand::*;
        assert_eq!(
            memory_command("Remember that my partner is Anna."),
            Some(Remember("my partner is Anna".into()))
        );
        assert_eq!(
            memory_command("Pilot, remember my baby naps from 1 to 3"),
            Some(Remember("my baby naps from 1 to 3".into()))
        );
        assert_eq!(memory_command("remember to buy milk"), None);
        assert_eq!(
            memory_command("Forget about the gym"),
            Some(Forget("the gym".into()))
        );
        assert_eq!(memory_command("What do you remember about me?"), Some(List));
        assert_eq!(memory_command("set a timer for 5 minutes"), None);
        // Letters that grow when lowercased ("İ" is two bytes, "i̇" three)
        // must not shift where the fact is cut.
        assert_eq!(
            memory_command("İrem is my sister, keep that in mind"),
            Some(Remember("İrem is my sister".into()))
        );
        let facts = vec![
            (1, "my partner is Anna".to_owned()),
            (2, "I go to the gym on Mondays".to_owned()),
        ];
        assert_eq!(best_memory("the gym", &facts).map(|f| f.0), Some(2));
        assert_eq!(best_memory("partner", &facts).map(|f| f.0), Some(1));
        assert!(best_memory("weather", &facts).is_none());
    }

    #[test]
    fn cancelling_and_correcting_clocks() {
        assert_eq!(clock_cancel("Cancel the timer"), Some(Some("timer")));
        assert_eq!(clock_cancel("turn off my alarm."), Some(Some("alarm")));
        assert_eq!(clock_cancel("delete that reminder"), Some(Some("reminder")));
        assert_eq!(clock_cancel("cancel it"), Some(None));
        // Not about a clock, or more than a cancel.
        assert_eq!(clock_cancel("cancel my dentist appointment"), None);
        assert_eq!(clock_cancel("stop the music"), None);
        assert_eq!(
            clock_cancel("cancel the timer and set a new one for 5 minutes"),
            None
        );
    }

    #[test]
    fn corrections_texts_facts_and_weather() {
        assert_eq!(
            correction_request("timer", "actually make it 12").as_deref(),
            Some("set a timer for 12 minutes")
        );
        assert_eq!(
            correction_request("timer", "make it twenty five seconds instead").as_deref(),
            Some("set a timer for 25 seconds")
        );
        assert_eq!(
            correction_request("alarm", "actually 7:30").as_deref(),
            Some("set an alarm for 7:30")
        );
        assert_eq!(correction_request("timer", "actually never mind"), None);
        assert_eq!(
            text_request("text Anna I quit").as_deref(),
            Some("Anna I quit")
        );
        assert_eq!(
            text_request("Send a message to Anna Virtanen saying running late.").as_deref(),
            Some("Anna Virtanen saying running late")
        );
        assert_eq!(
            text_request("text Anna that she should bring the keys"),
            None
        );
        assert_eq!(text_request("text me a joke"), None);
        assert_eq!(text_request("texting is fun"), None);
        assert_eq!(
            text_request("text İrem I'm on my way").as_deref(),
            Some("İrem I'm on my way")
        );
        assert!(matches!(
            parse_timer("5 minute timer for İrem called pasta"),
            Ok(Slots::Timer { label: Some(l), .. }) if l == "pasta"
        ));
        assert_eq!(message_body(" that I'm late").as_deref(), Some("I'm late"));
        assert_eq!(message_body(", \"hi\"").as_deref(), Some("hi"));
        assert_eq!(message_body(" "), None);
        assert_eq!(message_body(" about dinner tomorrow"), None);
        assert_eq!(message_body(" asking if the shop is open"), None);
        assert_eq!(
            personal_fact("I'm vegetarian, so what could I cook tonight?").as_deref(),
            Some("I'm vegetarian")
        );
        assert_eq!(
            personal_fact("by the way I'm allergic to shellfish").as_deref(),
            Some("I'm allergic to shellfish")
        );
        assert_eq!(
            personal_fact("we moved from Galway to Cork last month").as_deref(),
            Some("we moved from Galway to Cork last month")
        );
        assert_eq!(
            personal_fact("My wife's name is Niamh").as_deref(),
            Some("My wife's name is Niamh")
        );
        assert_eq!(
            personal_fact("I'm having pasta tonight, how long do I boil it?"),
            None
        );
        assert_eq!(personal_fact("I'm tired"), None);
        assert_eq!(fact_kind("I live in Galway").as_deref(), Some("home"));
        assert_eq!(
            fact_kind("we moved from Galway to Cork").as_deref(),
            Some("home")
        );
        assert_eq!(
            fact_kind("My wife's name is Niamh").as_deref(),
            Some("my wife")
        );
        assert_eq!(fact_kind("I'm allergic to shellfish"), None);
        assert_eq!(personal_fact("what's the weather in Cork?"), None);
        assert!(needs_model("am I free this afternoon?"));
        assert!(needs_model(
            "what's my first meeting today? then text Anna the time of it"
        ));
        assert!(needs_model(
            "set a timer for 5 minutes and then remind me to stretch"
        ));
        assert!(!needs_model("what's on today?"));
        assert!(!needs_model("set a timer for 10 minutes"));
        assert!(!needs_model("remind me to call the plumber in 2 hours"));
    }

    #[test]
    fn plans_around_places() {
        for q in [
            "help me plan a 3 day trip to Kerry",
            "things to do in Galway this weekend",
            "where should we stay in Dingle?",
            "what to do in Cork with kids",
        ] {
            assert!(place_plan(q), "{q}");
        }
        for q in ["plan my week", "what's the capital of Peru?", "set a timer"] {
            assert!(!place_plan(q), "{q}");
        }
        assert_eq!(
            trip_query("Plan a day in Helsinki"),
            "day in Helsinki things to do"
        );
        assert_eq!(
            trip_query("help me plan a 3 day trip to Kerry"),
            "3 day trip to Kerry things to do"
        );
        assert_eq!(
            trip_query("things to do in Galway this weekend"),
            "things to do in Galway this weekend"
        );
        assert_eq!(
            trip_query("where should we stay in Dingle?"),
            "where should we stay in Dingle"
        );
    }

    #[test]
    fn weather_questions_and_memory_phrasings() {
        for q in [
            "how warm is it outside?",
            "do I need an umbrella this afternoon?",
            "what's the weekend looking like weather wise",
            "will I need a coat today?",
            "is it cold out?",
        ] {
            assert!(about_weather(q), "{q}");
        }
        for q in [
            "what colour coat should I buy",
            "how hot is the sun",
            "brainstorm names for a dog",
            "set a timer for 5 minutes",
        ] {
            assert!(!about_weather(q), "{q}");
        }
        assert_eq!(
            memory_command("my wife's name is Niamh by the way, keep that in mind"),
            Some(MemoryCommand::Remember("my wife's name is Niamh".into()))
        );
        assert_eq!(
            memory_command("I take the 8:10 train, remember that"),
            Some(MemoryCommand::Remember("I take the 8:10 train".into()))
        );
        assert_eq!(memory_command("did you remember that"), None);
        assert!(is_correction("Make it 10 minutes instead"));
        assert!(is_correction("actually 7 o'clock"));
        assert!(is_correction("change it to half six"));
        assert!(!is_correction("set a timer for 10 minutes"));
        assert!(!is_correction("make dinner reservations"));
    }

    #[test]
    fn what_answers_a_clarifying_question() {
        for a in ["evening", "7am", "10 minutes", "the kitchen one"] {
            assert!(answers_a_question(a), "{a}");
        }
        for q in [
            "What is on my calendar today?",
            "set a timer for 5 minutes",
            "who won?",
        ] {
            assert!(!answers_a_question(q), "{q}");
        }
    }

    #[test]
    fn calendar_questions_name_a_day() {
        let day = |t: &str| match parse_calendar_query(t) {
            Slots::CalendarQuery(r) => r,
            other => panic!("{other:?}"),
        };
        assert_eq!(day("Do I have anything on Monday?"), DayRange::Weekday(1));
        assert_eq!(day("what's on fri"), DayRange::Weekday(5));
        assert_eq!(day("Sunday plans"), DayRange::Weekday(0));
        // Words that only contain a day's letters are not days.
        assert_eq!(day("what's on this month"), DayRange::Today);
        assert_eq!(day("anything tomorrow"), DayRange::Tomorrow);
    }

    #[test]
    fn calendar_follow_ups() {
        let range = |t| match calendar_follow_up(t) {
            Some(Slots::CalendarQuery(r)) => Some(r),
            _ => None,
        };
        assert_eq!(range("And tomorrow?"), Some(DayRange::Tomorrow));
        assert_eq!(range("what about Friday"), Some(DayRange::Weekday(5)));
        assert_eq!(range("next week?"), Some(DayRange::Week));
        assert_eq!(range("And the weather?"), None);
        assert_eq!(range("And what is the capital of Peru tomorrow?"), None);
    }
}
