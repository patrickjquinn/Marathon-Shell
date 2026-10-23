//! `CardDAV` and `CalDAV`: discovery (RFC 6764, then the principal's homes and
//! their collections) and sync-collection pulls (RFC 6578) into the address
//! book and `dav-events.db`.

use std::io::BufReader;
use std::path::Path;

use rusqlite::{params, Connection};

use crate::accounts::Account;
use crate::contacts::Contact;
use crate::webdav::{self, multistatus};

/// Finds the account's principal, its homes and their collections.
pub fn discover(agent: &ureq::Agent, account: &mut Account, secret: &str) -> Result<(), String> {
    let auth = webdav::authorization(&account.auth_kind, &account.username, secret);
    let propfind = |url: &str, depth: &str, xml: &str| {
        webdav::request(agent, &auth, "PROPFIND", url, Some(depth), Some(xml))
            .map(|body| multistatus(&body))
    };
    let mut well_known = account.base_url.clone();
    if !well_known.contains("/.well-known") {
        if !well_known.ends_with('/') {
            well_known.push('/');
        }
        well_known.push_str(".well-known/carddav");
    }
    let principal = [well_known.as_str(), account.base_url.as_str()]
        .into_iter()
        .find_map(|url| {
            propfind(url, "0", webdav::PRINCIPAL)
                .ok()
                .map(|m| m.principal)
                .filter(|p| !p.is_empty())
        })
        .ok_or("principal not found")?;
    let principal = webdav::resolve(&account.base_url, &principal);
    let homes = propfind(&principal, "0", webdav::HOMES)?;
    let home = |href: &str| {
        if href.is_empty() {
            String::new()
        } else {
            webdav::resolve(&principal, href)
        }
    };
    account.home_url_contacts = home(&homes.addressbook_home);
    account.home_url_calendar = home(&homes.calendar_home);
    let collections = |home: &str, kind: &str| -> Result<Vec<String>, String> {
        if home.is_empty() {
            return Ok(Vec::new());
        }
        let listed = propfind(home, "1", webdav::COLLECTIONS)?;
        Ok(listed
            .responses
            .iter()
            .filter(|r| r.resource_type.iter().any(|t| t == kind))
            .map(|r| webdav::resolve(home, &r.href))
            .collect())
    };
    account.collections_contacts = collections(&account.home_url_contacts, "addressbook")?;
    account.collections_calendar = collections(&account.home_url_calendar, "calendar")?;
    Ok(())
}

#[derive(Default)]
pub struct Pulled {
    pub contacts: Vec<Contact>,
    pub events: Vec<Event>,
    pub token: String,
}

/// What changed in a collection since `token`: each new or changed
/// resource, fetched.
pub fn pull(
    agent: &ureq::Agent,
    account: &Account,
    secret: &str,
    collection: &str,
    token: &str,
) -> Result<Pulled, String> {
    let auth = webdav::authorization(&account.auth_kind, &account.username, secret);
    let report = webdav::request(
        agent,
        &auth,
        "REPORT",
        collection,
        Some("1"),
        Some(&webdav::sync_collection(token)),
    )?;
    let changes = multistatus(&report);
    let mut pulled = Pulled {
        token: changes.sync_token,
        ..Pulled::default()
    };
    for change in changes
        .responses
        .iter()
        .filter(|r| !r.gone && !r.href.is_empty())
    {
        let url = webdav::resolve(collection, &change.href);
        if url.trim_end_matches('/') == collection.trim_end_matches('/') {
            continue;
        }
        let body = webdav::request(agent, &auth, "GET", &url, None, None)?;
        let reader = || BufReader::new(body.as_bytes());
        pulled.contacts.extend(
            ical::VcardParser::new(reader())
                .flatten()
                .map(|card| Contact::from_vcard(&card))
                .filter(|c| !c.name.is_empty()),
        );
        for calendar in ical::IcalParser::new(reader()).flatten() {
            pulled
                .events
                .extend(calendar.events.iter().filter_map(Event::from_ical));
        }
    }
    Ok(pulled)
}

#[derive(Default, Debug, PartialEq)]
pub struct Event {
    pub uid: String,
    pub summary: String,
    pub description: String,
    pub location: String,
    pub start_ms: i64,
    pub end_ms: i64,
    pub all_day: bool,
}

/// `YYYYMMDD` (`VALUE=DATE`, midnight UTC) or `YYYYMMDDTHHMMSS`, UTC with
/// `Z`, else local time.
fn ical_ms(value: &str, date_only: bool) -> Option<i64> {
    let n = |range: std::ops::Range<usize>| value.get(range)?.parse::<u8>().ok();
    let year: i32 = value.get(0..4)?.parse().ok()?;
    let (month, day) = (n(4..6)?, n(6..8)?);
    let (hour, minute, second) = if date_only {
        (0, 0, 0)
    } else {
        (n(9..11)?, n(11..13)?, n(13..15)?)
    };
    let unix = tz::UtcDateTime::new(year, month, day, hour, minute, second, 0)
        .ok()?
        .unix_time();
    let offset = if date_only || value.ends_with('Z') {
        0
    } else {
        let local = tz::TimeZone::local().ok()?;
        i64::from(local.find_local_time_type(unix).ok()?.ut_offset())
    };
    Some((unix - offset) * 1000)
}

impl Event {
    fn from_ical(event: &ical::parser::ical::component::IcalEvent) -> Option<Self> {
        let mut e = Self::default();
        for p in &event.properties {
            let value = p.value.as_deref().unwrap_or_default().trim();
            let date_only = p.params.iter().flatten().any(|(k, v)| {
                k.eq_ignore_ascii_case("VALUE") && v.iter().any(|t| t.eq_ignore_ascii_case("DATE"))
            });
            match p.name.to_ascii_uppercase().as_str() {
                "UID" => value.clone_into(&mut e.uid),
                "SUMMARY" => value.clone_into(&mut e.summary),
                "DESCRIPTION" => value.clone_into(&mut e.description),
                "LOCATION" => value.clone_into(&mut e.location),
                "DTSTART" => {
                    e.start_ms = ical_ms(value, date_only).unwrap_or_default();
                    e.all_day = date_only;
                }
                "DTEND" => e.end_ms = ical_ms(value, date_only).unwrap_or_default(),
                _ => {}
            }
        }
        (!e.uid.is_empty()).then_some(e)
    }
}

/// `dav-events.db`, the synced events, last write wins by UID.
pub struct Events(Connection);

impl Events {
    pub fn open(path: &Path) -> rusqlite::Result<Self> {
        let db = Connection::open(path)?;
        db.execute_batch(
            "PRAGMA journal_mode = WAL;
             CREATE TABLE IF NOT EXISTS events (uid TEXT PRIMARY KEY, account_id TEXT, summary TEXT,
                 description TEXT, start_ms INTEGER, end_ms INTEGER, all_day INTEGER DEFAULT 0,
                 location TEXT, updated_at INTEGER);
             CREATE INDEX IF NOT EXISTS idx_events_start ON events(start_ms);",
        )?;
        Ok(Self(db))
    }

    pub fn upsert(&self, account: &str, e: &Event, now_ms: i64) -> rusqlite::Result<usize> {
        self.0.execute(
            "INSERT INTO events (uid, account_id, summary, description, start_ms, end_ms, all_day, location, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
             ON CONFLICT(uid) DO UPDATE SET account_id = ?2, summary = ?3, description = ?4,
                 start_ms = ?5, end_ms = ?6, all_day = ?7, location = ?8, updated_at = ?9",
            params![e.uid, account, e.summary, e.description, e.start_ms, e.end_ms, e.all_day, e.location, now_ms],
        )
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn an_event_is_read() {
        let ics = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:e1\r\nSUMMARY:Standup\r\nDTSTART:20261020T100000Z\r\nDTEND:20261020T101500Z\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:e2\r\nDTSTART;VALUE=DATE:20261021\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";
        let calendar = ical::IcalParser::new(BufReader::new(ics.as_bytes()))
            .next()
            .unwrap()
            .unwrap();
        let events: Vec<Event> = calendar
            .events
            .iter()
            .filter_map(Event::from_ical)
            .collect();
        assert_eq!(
            (
                events[0].summary.as_str(),
                events[0].start_ms,
                events[0].end_ms
            ),
            ("Standup", 1_792_490_400_000, 1_792_491_300_000)
        );
        assert_eq!(
            (events[1].start_ms, events[1].all_day),
            (1_792_540_800_000, true)
        );
        let dir = tempfile::tempdir().unwrap();
        let store = Events::open(&dir.path().join("dav-events.db")).unwrap();
        assert_eq!(store.upsert("a", &events[0], 1).unwrap(), 1);
        assert_eq!(store.upsert("a", &events[0], 2).unwrap(), 1);
    }
}
