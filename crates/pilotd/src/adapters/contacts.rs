// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The address book, read-only, from qtcontacts-sqlite's database
//! (`~/.local/share/system/privileged/Contacts/qtcontacts-sqlite/contacts.db`,
//! schema in qtcontacts-sqlite's `src/engine/contactsdatabase.cpp`). The
//! `QtContacts` API is Qt 5 on the device and not Harbour-allowed (spec
//! section 8.1); the `Contacts` Sailjail permission grants this directory.
//!
//! Names feed the redactor on every turn, so they are cached for a minute.

use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use rusqlite::{Connection, OpenFlags};

use super::{AdapterError, Contact, Contacts};

pub struct SqliteContacts {
    pub path: PathBuf,
    cache: Mutex<Option<(Instant, Vec<String>)>>,
    ttl: Duration,
}

pub fn default_path() -> Option<PathBuf> {
    crate::privilege::home()
        .map(|h| h.join(".local/share/system/privileged/Contacts/qtcontacts-sqlite/contacts.db"))
}

impl SqliteContacts {
    pub fn new(path: PathBuf) -> SqliteContacts {
        SqliteContacts {
            path,
            cache: Mutex::new(None),
            ttl: Duration::from_secs(60),
        }
    }

    fn open(&self) -> Result<Connection, AdapterError> {
        if !self.path.exists() {
            return Err(AdapterError::Unavailable("the address book".into()));
        }
        Connection::open_with_flags(
            &self.path,
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .map_err(|e| AdapterError::Failed(format!("contacts: {e}")))
    }

    fn load_names(&self) -> Result<Vec<String>, AdapterError> {
        let conn = self.open()?;
        let mut stmt = conn
            .prepare(
                "SELECT DISTINCT d.displayLabel FROM DisplayLabels d
                 JOIN Contacts c ON c.contactId = d.contactId
                 WHERE c.deleted IS NULL AND d.displayLabel IS NOT NULL AND d.displayLabel != ''
                 UNION
                 SELECT DISTINCT trim(coalesce(n.firstName, '') || ' ' || coalesce(n.lastName, ''))
                 FROM Names n JOIN Contacts c ON c.contactId = n.contactId
                 WHERE c.deleted IS NULL",
            )
            .map_err(|e| AdapterError::Failed(format!("contacts schema: {e}")))?;
        let names = stmt
            .query_map([], |r| r.get::<_, String>(0))
            .and_then(Iterator::collect::<Result<Vec<_>, _>>)
            .map_err(|e| AdapterError::Failed(format!("contacts: {e}")))?;
        Ok(names.into_iter().filter(|n| !n.trim().is_empty()).collect())
    }
}

impl Contacts for SqliteContacts {
    fn names(&self) -> Vec<String> {
        let mut cache = self
            .cache
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some((at, names)) = cache.as_ref() {
            if at.elapsed() < self.ttl {
                return names.clone();
            }
        }
        match crate::privilege::with_privileged(|| self.load_names()) {
            Ok(names) => {
                *cache = Some((Instant::now(), names.clone()));
                names
            }
            Err(e) => {
                // Kept for the same minute as a good read, so a phone without
                // an address book (or with a broken one) is not asked again,
                // and logged again, on every turn.
                match e {
                    AdapterError::Unavailable(_) => {
                        log::info!("no contact names for redaction: {e}");
                    }
                    AdapterError::Failed(_) => {
                        log::warn!("contact names unavailable for redaction: {e}");
                    }
                }
                *cache = Some((Instant::now(), Vec::new()));
                Vec::new()
            }
        }
    }

    fn lookup(&self, query: &str, limit: usize) -> Result<Vec<Contact>, AdapterError> {
        crate::privilege::with_privileged(|| self.lookup_raised(query, limit))
    }
}

impl SqliteContacts {
    /// [`Contacts::lookup`], with the group raised.
    fn lookup_raised(&self, query: &str, limit: usize) -> Result<Vec<Contact>, AdapterError> {
        let conn = self.open()?;
        let like = format!("%{}%", query.trim().replace(['%', '_'], ""));
        let lim = i64::try_from(limit).unwrap_or(i64::MAX);
        let mut stmt = conn
            .prepare(
                "SELECT d.contactId, d.displayLabel FROM DisplayLabels d
                 JOIN Contacts c ON c.contactId = d.contactId
                 WHERE c.deleted IS NULL AND d.displayLabel LIKE ?1
                 ORDER BY d.displayLabel LIMIT ?2",
            )
            .map_err(|e| AdapterError::Failed(format!("contacts schema: {e}")))?;
        let hits: Vec<(i64, String)> = stmt
            .query_map(rusqlite::params![like, lim], |r| Ok((r.get(0)?, r.get(1)?)))
            .and_then(Iterator::collect)
            .map_err(|e| AdapterError::Failed(format!("contacts: {e}")))?;
        let column = |table: &str, col: &str, id: i64| -> Result<Vec<String>, AdapterError> {
            let mut s = conn
                .prepare(&format!("SELECT {col} FROM {table} WHERE contactId = ?1"))
                .map_err(|e| AdapterError::Failed(format!("contacts schema: {e}")))?;
            s.query_map([id], |r| r.get::<_, String>(0))
                .and_then(Iterator::collect)
                .map_err(|e| AdapterError::Failed(format!("contacts: {e}")))
        };
        let mut out = Vec::new();
        for (id, name) in hits {
            out.push(Contact {
                name,
                phones: column("PhoneNumbers", "phoneNumber", id)?,
                emails: column("EmailAddresses", "emailAddress", id)?,
            });
        }
        Ok(out)
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    fn fixture(path: &std::path::Path) {
        let c = Connection::open(path).unwrap();
        c.execute_batch(
            "CREATE TABLE Contacts (contactId INTEGER PRIMARY KEY, deleted DATETIME);
             CREATE TABLE DisplayLabels (detailId INTEGER PRIMARY KEY, contactId INTEGER, displayLabel TEXT);
             CREATE TABLE Names (detailId INTEGER PRIMARY KEY, contactId INTEGER, firstName TEXT, lastName TEXT);
             CREATE TABLE PhoneNumbers (detailId INTEGER PRIMARY KEY, contactId INTEGER, phoneNumber TEXT);
             CREATE TABLE EmailAddresses (detailId INTEGER PRIMARY KEY, contactId INTEGER, emailAddress TEXT);
             INSERT INTO Contacts VALUES (1, NULL), (2, NULL), (3, '2026-01-01');
             INSERT INTO DisplayLabels (contactId, displayLabel) VALUES (1, 'Anna Virtanen'), (2, 'Bob'), (3, 'Gone Person');
             INSERT INTO Names (contactId, firstName, lastName) VALUES (1, 'Anna', 'Virtanen'), (2, 'Robert', 'Smith');
             INSERT INTO PhoneNumbers (contactId, phoneNumber) VALUES (1, '+358401234567');
             INSERT INTO EmailAddresses (contactId, emailAddress) VALUES (1, 'anna@example.org');",
        )
        .unwrap();
    }

    #[test]
    fn names_and_lookup() {
        let dir = tempfile::tempdir().unwrap();
        let db = dir.path().join("contacts.db");
        fixture(&db);
        let c = SqliteContacts::new(db);
        let mut names = c.names();
        names.sort();
        assert_eq!(names, ["Anna Virtanen", "Bob", "Robert Smith"]);
        let hits = c.lookup("anna", 5).unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].phones, ["+358401234567"]);
        assert_eq!(hits[0].emails, ["anna@example.org"]);
        let empty = c.lookup("gone", 5).unwrap();
        assert!(empty.is_empty(), "{empty:?}");
        let mut none = SqliteContacts::new(dir.path().join("missing.db"));
        let empty = none.names();
        assert!(empty.is_empty(), "{empty:?}");
        // The miss is cached like a read: a database that appears is read
        // once the cache time is over.
        fixture(&dir.path().join("missing.db"));
        let empty = none.names();
        assert!(empty.is_empty(), "{empty:?}");
        none.ttl = Duration::ZERO;
        assert_eq!(none.names().len(), 3);
    }
}
