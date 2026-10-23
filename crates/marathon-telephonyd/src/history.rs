//! `callhistory.db`: the last 500 calls.

use std::fs;
use std::path::Path;

use rusqlite::{params, Connection, OptionalExtension};
use zbus::zvariant::Value;

use crate::store::Row;

const KEPT: i64 = 500;

pub struct CallLog {
    db: Connection,
}

const COLUMNS: &str =
    "SELECT id, number, contact_name, type, timestamp, duration FROM call_history";

fn row(r: &rusqlite::Row) -> rusqlite::Result<Row> {
    Ok(Row::from([
        ("id", Value::from(r.get::<_, i32>(0)?)),
        ("number", Value::from(r.get::<_, String>(1)?)),
        (
            "contactName",
            Value::from(r.get::<_, Option<String>>(2)?.unwrap_or_default()),
        ),
        ("type", Value::from(r.get::<_, String>(3)?)),
        ("timestamp", Value::from(r.get::<_, i64>(4)?)),
        ("duration", Value::from(r.get::<_, i32>(5)?)),
    ]))
}

impl CallLog {
    pub fn open(path: &Path) -> rusqlite::Result<Self> {
        if let Some(dir) = path.parent() {
            fs::create_dir_all(dir).ok();
        }
        let db = Connection::open(path)?;
        db.execute_batch(
            "PRAGMA journal_mode = WAL;
             CREATE TABLE IF NOT EXISTS call_history (id INTEGER PRIMARY KEY AUTOINCREMENT,
                 number TEXT NOT NULL, contact_name TEXT, type TEXT NOT NULL,
                 timestamp INTEGER NOT NULL, duration INTEGER DEFAULT 0);",
        )?;
        Ok(Self { db })
    }

    /// The newest calls, or those with `number`.
    pub fn calls(&self, number: Option<&str>) -> rusqlite::Result<Vec<Row>> {
        let mut query = self
            .db
            .prepare(&format!("{COLUMNS} ORDER BY timestamp DESC LIMIT {KEPT}"))?;
        let rows = query
            .query_map([], row)?
            .collect::<rusqlite::Result<Vec<Row>>>()?;
        Ok(match number {
            Some(number) => rows
                .into_iter()
                .filter(|r| r["number"] == Value::from(number))
                .collect(),
            None => rows,
        })
    }

    pub fn call(&self, id: i32) -> rusqlite::Result<Option<Row>> {
        self.db
            .query_row(&format!("{COLUMNS} WHERE id = ?"), [id], row)
            .optional()
    }

    pub fn add(
        &self,
        number: &str,
        name: &str,
        kind: &str,
        timestamp: i64,
        duration: i32,
    ) -> rusqlite::Result<i32> {
        self.db.execute(
            "INSERT INTO call_history (number, contact_name, type, timestamp, duration) VALUES (?, ?, ?, ?, ?)",
            params![number, name, kind, timestamp, duration],
        )?;
        let id = self.db.last_insert_rowid();
        self.db.execute(
            &format!("DELETE FROM call_history WHERE id NOT IN (SELECT id FROM call_history ORDER BY timestamp DESC LIMIT {KEPT})"),
            [],
        )?;
        Ok(i32::try_from(id).unwrap_or(i32::MAX))
    }

    pub fn delete(&self, id: Option<i32>) -> rusqlite::Result<usize> {
        match id {
            Some(id) => self
                .db
                .execute("DELETE FROM call_history WHERE id = ?", [id]),
            None => self.db.execute("DELETE FROM call_history", []),
        }
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn only_the_newest_calls_are_kept() {
        let dir = tempfile::tempdir().unwrap();
        let log = CallLog::open(&dir.path().join("callhistory.db")).unwrap();
        for at in 0..=KEPT {
            log.add("+15550100", "Unknown", "missed", at, 0).unwrap();
        }
        let calls = log.calls(None).unwrap();
        assert_eq!(calls.len(), 500);
        assert_eq!(calls[0]["timestamp"], Value::from(KEPT));
        assert_eq!(calls[499]["timestamp"], Value::from(1_i64));
    }
}
