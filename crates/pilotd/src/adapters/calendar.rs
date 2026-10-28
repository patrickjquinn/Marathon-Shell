// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Calendar queries, read-only, straight from mkcal's SQLite store.
//!
//! mkcal has no query D-Bus API (its D-Bus use is change notification),
//! and its C++ library is Qt 5 only (spec section 2), so `pilotd` reads
//! the database the library writes: `Components` rows (schema in mkcal's
//! `src/sqliteformat.h`), times in Unix seconds (`SqliteFormat::
//! toOriginTime`). The default location is
//! `~/.local/share/system/privileged/Calendar/mkcal/db`, readable with the
//! `Calendar` Sailjail permission.
//!
//! Limits: recurring events (the `Rules` table) are returned only at their
//! first occurrence, and all-day ("floating") dates are read from the
//! local-time column. Both are listed under "Needs device verification".

use std::path::PathBuf;

use rusqlite::{Connection, OpenFlags};

use super::{AdapterError, Calendar, CalendarEvent};

pub struct Mkcal {
    pub path: PathBuf,
    /// Seconds east of UTC, to read floating all-day dates.
    pub utc_offset: fn() -> i64,
}

/// mkcal's marker for all-day dates in `StartTimeZone`.
const FLOATING: &str = "FloatingDate";

pub fn default_path() -> Option<PathBuf> {
    crate::privilege::home().map(|h| h.join(".local/share/system/privileged/Calendar/mkcal/db"))
}

impl Calendar for Mkcal {
    fn events(&self, from: i64, to: i64, limit: usize) -> Result<Vec<CalendarEvent>, AdapterError> {
        crate::privilege::with_privileged(|| self.events_raised(from, to, limit))
    }

    /// The size and modification time of the database and its write-ahead
    /// log, folded together: SQLite changes one of them on every commit.
    /// A `stat` instead of opening the database on every triage poll.
    fn stamp(&self) -> Option<u64> {
        crate::privilege::with_privileged(|| file_stamp(&self.path))
    }
}

/// `None` when the database is not there (so every poll reports that).
pub fn file_stamp(db: &std::path::Path) -> Option<u64> {
    use std::hash::{Hash as _, Hasher as _};
    let main = std::fs::metadata(db).ok()?;
    let mut h = std::collections::hash_map::DefaultHasher::new();
    let mut wal = db.as_os_str().to_owned();
    wal.push("-wal");
    for meta in [Some(main), std::fs::metadata(wal).ok()] {
        match meta {
            Some(m) => {
                m.len().hash(&mut h);
                m.modified().ok().hash(&mut h);
            }
            None => 0u8.hash(&mut h),
        }
    }
    Some(h.finish())
}

impl Mkcal {
    /// [`Calendar::events`], with the group raised.
    fn events_raised(
        &self,
        from: i64,
        to: i64,
        limit: usize,
    ) -> Result<Vec<CalendarEvent>, AdapterError> {
        if !self.path.exists() {
            return Err(AdapterError::Unavailable("the calendar".into()));
        }
        let conn = Connection::open_with_flags(
            &self.path,
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .map_err(|e| AdapterError::Failed(format!("calendar: {e}")))?;
        let offset = (self.utc_offset)();
        // A floating date's DateStartLocal is local clock time counted as
        // if it were UTC: subtract the offset to get the real instant.
        let mut stmt = conn
            .prepare(
                "SELECT Summary, Location, StartTimeZone,
                        CASE WHEN StartTimeZone = ?4 THEN DateStartLocal - ?5 ELSE DateStart END AS s,
                        CASE WHEN StartTimeZone = ?4 THEN DateEndDueLocal - ?5 ELSE DateEndDue END AS e
                 FROM Components
                 WHERE Type = 'Event' AND (DateDeleted IS NULL OR DateDeleted = 0)
                   AND (CASE WHEN StartTimeZone = ?4 THEN DateStartLocal - ?5 ELSE DateStart END) < ?2
                   AND (CASE WHEN StartTimeZone = ?4 THEN DateEndDueLocal - ?5 ELSE DateEndDue END) > ?1
                 ORDER BY s ASC LIMIT ?3",
            )
            .map_err(|e| AdapterError::Failed(format!("calendar schema: {e}")))?;
        let lim = i64::try_from(limit).unwrap_or(i64::MAX);
        let rows = stmt
            .query_map(rusqlite::params![from, to, lim, FLOATING, offset], |r| {
                let tz: Option<String> = r.get(2)?;
                let start: i64 = r.get(3)?;
                let end: Option<i64> = r.get(4)?;
                Ok(CalendarEvent {
                    title: r.get::<_, Option<String>>(0)?.unwrap_or_default(),
                    location: r.get::<_, Option<String>>(1)?.filter(|l| !l.is_empty()),
                    all_day: tz.as_deref() == Some(FLOATING),
                    start,
                    end: end.unwrap_or(start),
                })
            })
            .map_err(|e| AdapterError::Failed(format!("calendar: {e}")))?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| AdapterError::Failed(format!("calendar: {e}")))
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    #[test]
    fn the_stamp_moves_with_any_commit() {
        let dir = tempfile::tempdir().unwrap();
        let db = dir.path().join("db");
        assert_eq!(file_stamp(&db), None);
        fixture(&db, &[("Dentist", 100, 200, None, 0)]);
        let first = file_stamp(&db).unwrap();
        assert_eq!(file_stamp(&db), Some(first), "stable while untouched");
        // WAL mode commits touch only the -wal file.
        std::fs::write(dir.path().join("db-wal"), b"frame").unwrap();
        let with_wal = file_stamp(&db).unwrap();
        assert_ne!(with_wal, first);
        std::fs::write(dir.path().join("db-wal"), b"frame two").unwrap();
        assert_ne!(file_stamp(&db).unwrap(), with_wal);
    }

    /// The subset of mkcal's `Components` table the adapter reads.
    pub fn fixture(path: &std::path::Path, rows: &[(&str, i64, i64, Option<&str>, i64)]) {
        let c = Connection::open(path).unwrap();
        c.execute_batch(
            "CREATE TABLE Components(ComponentId INTEGER PRIMARY KEY AUTOINCREMENT, Notebook TEXT, Type TEXT,
             Summary TEXT, Category TEXT, DateStart INTEGER, DateStartLocal INTEGER, StartTimeZone TEXT,
             HasDueDate INTEGER, DateEndDue INTEGER, DateEndDueLocal INTEGER, EndDueTimeZone TEXT,
             Location TEXT, DateDeleted INTEGER)",
        )
        .unwrap();
        for (title, start, end, tz, deleted) in rows {
            c.execute(
                "INSERT INTO Components (Type, Summary, DateStart, DateStartLocal, StartTimeZone,
                 DateEndDue, DateEndDueLocal, Location, DateDeleted)
                 VALUES ('Event', ?1, ?2, ?2, ?4, ?3, ?3, 'Room 1', ?5)",
                rusqlite::params![title, start, end, tz, deleted],
            )
            .unwrap();
        }
    }

    #[test]
    fn reads_overlapping_events_in_order() {
        let dir = tempfile::tempdir().unwrap();
        let db = dir.path().join("db");
        fixture(
            &db,
            &[
                ("Standup", 1_000, 2_000, Some("Europe/Helsinki"), 0),
                ("Lunch", 500, 900, Some("Europe/Helsinki"), 0),
                ("Deleted", 1_100, 1_200, None, 99),
                ("Later", 9_000, 9_500, None, 0),
                ("Holiday", 0, 86_400, Some("FloatingDate"), 0),
            ],
        );
        let cal = Mkcal {
            path: db,
            utc_offset: || 3600,
        };
        let got = cal.events(600, 5_000, 10).unwrap();
        let titles: Vec<&str> = got.iter().map(|e| e.title.as_str()).collect();
        assert_eq!(titles, ["Holiday", "Lunch", "Standup"]);
        assert!(got[0].all_day);
        assert_eq!(got[0].start, -3600);
        assert_eq!(got[1].location.as_deref(), Some("Room 1"));
        assert_eq!(cal.events(600, 5_000, 1).unwrap().len(), 1);
        let missing = Mkcal {
            path: dir.path().join("nope"),
            utc_offset: || 0,
        };
        assert!(matches!(
            missing.events(0, 1, 1),
            Err(AdapterError::Unavailable(_))
        ));
    }
}
