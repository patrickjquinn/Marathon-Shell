// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! On-device records, in one SQLite file (0600):
//!
//! - the **egress log** (spec section 4, step 8, and section 10): one row
//!   per remote call with timestamp, provider, purpose, redacted payload
//!   size, latency and result type. Never the payload itself.
//! - the **decision log** (section 5.2, calibration): every Jev answer with
//!   the route taken and how the turn ended. Intent labels and numbers
//!   only, never the utterance.
//!
//! Both are visible and exportable in settings, and wiped together. Both
//! are bounded: rows older than [`LOG_KEEP_DAYS`] go, and at most
//! [`LOG_KEEP_ROWS`] stay, trimmed as rows are added.

use std::path::Path;
use std::sync::Mutex;

use rusqlite::{params, Connection};
use serde::Serialize;

/// One remote call.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct EgressEntry {
    /// Unix milliseconds.
    pub ts_ms: i64,
    /// "jev", "groq", "lighthouse-llm", "lighthouse-score", "relay".
    pub provider: String,
    /// "decide", "chat", "tool-loop", "triage", "vision", ...
    pub purpose: String,
    /// Size of the redacted request body.
    pub bytes_out: u64,
    pub bytes_in: u64,
    pub latency_ms: u64,
    /// "ok", "http-429", "transport", "region-blocked", "offline", ...
    pub result: String,
}

/// Where remote clients report their calls. The store is the real one;
/// tests use a vector.
pub trait EgressSink: Send + Sync {
    fn record(&self, entry: EgressEntry);
}

/// One routing decision, for threshold calibration.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Decision {
    pub turn: String,
    pub ts_ms: i64,
    pub top_intent: String,
    pub confidence: f64,
    pub second_intent: Option<String>,
    pub needs_generation: f64,
    pub ambiguity: f64,
    pub route: String,
    /// "pending", "done", "confirmed", "declined", "cancelled", "failed",
    /// "corrected".
    pub outcome: String,
}

/// One triaged notification, SMS or calendar change (spec section 5.3).
/// Kept on the device only; what went to Jev was redacted.
/// A fact the person asked Pilot to remember ("my partner is Anna").
/// Kept on the phone; used as context for the person's own questions.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Memory {
    pub id: i64,
    pub ts_ms: i64,
    pub fact: String,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct TriageItem {
    pub id: i64,
    pub ts_ms: i64,
    /// "notification", "sms", "message", "call" or "calendar".
    pub source: String,
    pub app: String,
    pub title: String,
    pub body: String,
    /// `act_now`, `today`, `later` or `ignore`.
    pub bucket: String,
    /// Position on routine (0), time-sensitive (1), urgent (2).
    pub urgency: f64,
    /// Jev's `worth_interrupting`.
    pub interrupt: f64,
}

/// Triage results kept: the newest this many.
pub const TRIAGE_KEEP: i64 = 200;

/// Egress and decision rows older than this many days are dropped.
pub const LOG_KEEP_DAYS: i64 = 90;
/// And at most this many of each are kept, newest first.
pub const LOG_KEEP_ROWS: i64 = 5000;

/// Drops rows of `table` (egress or decisions) older than
/// [`LOG_KEEP_DAYS`] before `now_ms`, then all but the newest
/// [`LOG_KEEP_ROWS`]. `table` is one of two constants, never input.
fn trim_log(conn: &Connection, table: &str, now_ms: i64) -> Result<(), StoreError> {
    let cutoff = now_ms.saturating_sub(LOG_KEEP_DAYS * 86_400_000);
    conn.execute(&format!("DELETE FROM {table} WHERE ts_ms < ?1"), [cutoff])?;
    conn.execute(
        &format!(
            "DELETE FROM {table} WHERE rowid IN
             (SELECT rowid FROM {table} ORDER BY ts_ms DESC, rowid DESC LIMIT -1 OFFSET ?1)"
        ),
        [LOG_KEEP_ROWS],
    )?;
    Ok(())
}

#[derive(Debug, thiserror::Error)]
pub enum StoreError {
    #[error("database: {0}")]
    Sql(#[from] rusqlite::Error),
    #[error("{0}")]
    Io(#[from] std::io::Error),
}

pub struct Store {
    conn: Mutex<Connection>,
}

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS egress (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts_ms INTEGER NOT NULL,
    provider TEXT NOT NULL,
    purpose TEXT NOT NULL,
    bytes_out INTEGER NOT NULL,
    bytes_in INTEGER NOT NULL,
    latency_ms INTEGER NOT NULL,
    result TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS decisions (
    turn TEXT PRIMARY KEY,
    ts_ms INTEGER NOT NULL,
    top_intent TEXT NOT NULL,
    confidence REAL NOT NULL,
    second_intent TEXT,
    needs_generation REAL NOT NULL,
    ambiguity REAL NOT NULL,
    route TEXT NOT NULL,
    outcome TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS meta (
    k TEXT PRIMARY KEY,
    v TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS memory (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts_ms INTEGER NOT NULL,
    fact TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS conversation (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts_ms INTEGER NOT NULL,
    question TEXT NOT NULL,
    answer TEXT NOT NULL
);
CREATE VIRTUAL TABLE IF NOT EXISTS conversation_fts USING fts5(
    question, answer, content='conversation', content_rowid='id',
    tokenize='unicode61 remove_diacritics 2'
);
CREATE TRIGGER IF NOT EXISTS conversation_ai AFTER INSERT ON conversation BEGIN
    INSERT INTO conversation_fts(rowid, question, answer) VALUES (new.id, new.question, new.answer);
END;
CREATE TRIGGER IF NOT EXISTS conversation_ad AFTER DELETE ON conversation BEGIN
    INSERT INTO conversation_fts(conversation_fts, rowid, question, answer)
        VALUES ('delete', old.id, old.question, old.answer);
END;
CREATE TABLE IF NOT EXISTS triage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts_ms INTEGER NOT NULL,
    source TEXT NOT NULL,
    app TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    bucket TEXT NOT NULL,
    urgency REAL NOT NULL,
    interrupt REAL NOT NULL
);
";

impl Store {
    /// Opens or creates the database at `path`, readable by the user only.
    pub fn open(path: &Path) -> Result<Store, StoreError> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let conn = Connection::open(path)?;
        restrict(path)?;
        Self::init(conn)
    }

    /// An in-memory store, for tests and `--ask` runs without a data dir.
    pub fn memory() -> Result<Store, StoreError> {
        Self::init(Connection::open_in_memory()?)
    }

    fn init(conn: Connection) -> Result<Store, StoreError> {
        conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA secure_delete=ON;")?;
        conn.execute_batch(SCHEMA)?;
        Ok(Store {
            conn: Mutex::new(conn),
        })
    }

    fn conn(&self) -> std::sync::MutexGuard<'_, Connection> {
        self.conn
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    pub fn add_egress(&self, e: &EgressEntry) -> Result<(), StoreError> {
        let conn = self.conn();
        conn.execute(
            "INSERT INTO egress (ts_ms, provider, purpose, bytes_out, bytes_in, latency_ms, result)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                e.ts_ms,
                e.provider,
                e.purpose,
                to_i64(e.bytes_out),
                to_i64(e.bytes_in),
                to_i64(e.latency_ms),
                e.result
            ],
        )?;
        trim_log(&conn, "egress", e.ts_ms)
    }

    /// Newest first; `limit` 0 means all.
    pub fn egress(&self, limit: u32) -> Result<Vec<EgressEntry>, StoreError> {
        let conn = self.conn();
        let lim = if limit == 0 { -1 } else { i64::from(limit) };
        let mut stmt = conn.prepare(
            "SELECT ts_ms, provider, purpose, bytes_out, bytes_in, latency_ms, result
             FROM egress ORDER BY id DESC LIMIT ?1",
        )?;
        let rows = stmt.query_map([lim], |r| {
            Ok(EgressEntry {
                ts_ms: r.get(0)?,
                provider: r.get(1)?,
                purpose: r.get(2)?,
                bytes_out: from_i64(r.get(3)?),
                bytes_in: from_i64(r.get(4)?),
                latency_ms: from_i64(r.get(5)?),
                result: r.get(6)?,
            })
        })?;
        Ok(rows.collect::<Result<_, _>>()?)
    }

    pub fn add_decision(&self, d: &Decision) -> Result<(), StoreError> {
        let conn = self.conn();
        conn.execute(
            "INSERT OR REPLACE INTO decisions
             (turn, ts_ms, top_intent, confidence, second_intent, needs_generation, ambiguity, route, outcome)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            params![
                d.turn,
                d.ts_ms,
                d.top_intent,
                d.confidence,
                d.second_intent,
                d.needs_generation,
                d.ambiguity,
                d.route,
                d.outcome
            ],
        )?;
        trim_log(&conn, "decisions", d.ts_ms)
    }

    /// Records how a turn ended. Unknown turns (no Jev call was made) are
    /// ignored.
    pub fn set_outcome(&self, turn: &str, outcome: &str) -> Result<(), StoreError> {
        self.conn().execute(
            "UPDATE decisions SET outcome = ?2 WHERE turn = ?1",
            params![turn, outcome],
        )?;
        Ok(())
    }

    pub fn decisions(&self, limit: u32) -> Result<Vec<Decision>, StoreError> {
        let conn = self.conn();
        let lim = if limit == 0 { -1 } else { i64::from(limit) };
        let mut stmt = conn.prepare(
            "SELECT turn, ts_ms, top_intent, confidence, second_intent, needs_generation, ambiguity, route, outcome
             FROM decisions ORDER BY ts_ms DESC, rowid DESC LIMIT ?1",
        )?;
        let rows = stmt.query_map([lim], |r| {
            Ok(Decision {
                turn: r.get(0)?,
                ts_ms: r.get(1)?,
                top_intent: r.get(2)?,
                confidence: r.get(3)?,
                second_intent: r.get(4)?,
                needs_generation: r.get(5)?,
                ambiguity: r.get(6)?,
                route: r.get(7)?,
                outcome: r.get(8)?,
            })
        })?;
        Ok(rows.collect::<Result<_, _>>()?)
    }

    /// Stores a triage result (its `id` is assigned) and keeps the newest
    /// [`TRIAGE_KEEP`].
    pub fn add_triage(&self, t: &TriageItem) -> Result<i64, StoreError> {
        let conn = self.conn();
        conn.execute(
            "INSERT INTO triage (ts_ms, source, app, title, body, bucket, urgency, interrupt)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                t.ts_ms,
                t.source,
                t.app,
                t.title,
                t.body,
                t.bucket,
                t.urgency,
                t.interrupt
            ],
        )?;
        let id = conn.last_insert_rowid();
        conn.execute(
            "DELETE FROM triage WHERE id NOT IN (SELECT id FROM triage ORDER BY ts_ms DESC, id DESC LIMIT ?1)",
            [TRIAGE_KEEP],
        )?;
        Ok(id)
    }

    /// Internal state that must survive a restart (the Events view entry's
    /// notification id); never exported.
    pub fn meta(&self, key: &str) -> Result<Option<String>, StoreError> {
        let conn = self.conn();
        let mut stmt = conn.prepare("SELECT v FROM meta WHERE k = ?1")?;
        let mut rows = stmt.query([key])?;
        Ok(match rows.next()? {
            Some(r) => Some(r.get(0)?),
            None => None,
        })
    }

    pub fn set_meta(&self, key: &str, value: &str) -> Result<(), StoreError> {
        self.conn().execute(
            "INSERT OR REPLACE INTO meta (k, v) VALUES (?1, ?2)",
            params![key, value],
        )?;
        Ok(())
    }

    /// Newest first; `limit` 0 for all.
    pub fn triage(&self, limit: u32) -> Result<Vec<TriageItem>, StoreError> {
        let conn = self.conn();
        let lim = if limit == 0 { -1 } else { i64::from(limit) };
        let mut stmt = conn.prepare(
            "SELECT id, ts_ms, source, app, title, body, bucket, urgency, interrupt
             FROM triage ORDER BY ts_ms DESC, id DESC LIMIT ?1",
        )?;
        let rows = stmt.query_map([lim], |r| {
            Ok(TriageItem {
                id: r.get(0)?,
                ts_ms: r.get(1)?,
                source: r.get(2)?,
                app: r.get(3)?,
                title: r.get(4)?,
                body: r.get(5)?,
                bucket: r.get(6)?,
                urgency: r.get(7)?,
                interrupt: r.get(8)?,
            })
        })?;
        Ok(rows.collect::<Result<_, _>>()?)
    }

    /// Everything the user can export: the egress and decision logs and
    /// the triage list.
    pub fn export(&self) -> Result<serde_json::Value, StoreError> {
        Ok(serde_json::json!({
            "format": "shoal-pilot-export/1",
            "egress": self.egress(0)?,
            "decisions": self.decisions(0)?,
            "triage": self.triage(0)?,
            "memory": self.memories()?,
        }))
    }

    /// Keeps a fact the person asked Pilot to remember; its id.
    pub fn remember(&self, fact: &str) -> Result<i64, StoreError> {
        let conn = self.conn();
        conn.execute(
            "INSERT INTO memory (ts_ms, fact) VALUES (?1, ?2)",
            rusqlite::params![now_ms(), fact],
        )?;
        Ok(conn.last_insert_rowid())
    }

    /// Everything remembered, oldest first.
    pub fn memories(&self) -> Result<Vec<Memory>, StoreError> {
        let conn = self.conn();
        let mut stmt = conn.prepare("SELECT id, ts_ms, fact FROM memory ORDER BY id")?;
        let rows = stmt
            .query_map([], |r| {
                Ok(Memory {
                    id: r.get(0)?,
                    ts_ms: r.get(1)?,
                    fact: r.get(2)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    /// Keeps one exchange of the conversation, and lets go of those older
    /// than [`HISTORY_DAYS`].
    pub fn log_exchange(&self, question: &str, answer: &str) -> Result<(), StoreError> {
        let conn = self.conn();
        let now = now_ms();
        conn.execute(
            "INSERT INTO conversation (ts_ms, question, answer) VALUES (?1, ?2, ?3)",
            rusqlite::params![now, question, answer],
        )?;
        conn.execute(
            "DELETE FROM conversation WHERE ts_ms < ?1",
            [now - HISTORY_DAYS * 86_400_000],
        )?;
        Ok(())
    }

    /// Earlier exchanges that best match `query` (its words, any of them,
    /// ranked by BM25), newest first among equals.
    pub fn search_conversation(
        &self,
        query: &str,
        limit: u32,
    ) -> Result<Vec<Exchange>, StoreError> {
        let terms: Vec<String> = query
            .split(|c: char| !c.is_alphanumeric())
            .filter(|w| w.chars().count() >= 3 && !STOPWORDS.contains(&w.to_lowercase().as_str()))
            .map(|w| format!("\"{}\"", w.replace('"', "")))
            .collect();
        if terms.is_empty() {
            return Ok(Vec::new());
        }
        let conn = self.conn();
        let mut stmt = conn.prepare(
            "SELECT c.ts_ms, c.question, c.answer FROM conversation_fts f \
             JOIN conversation c ON c.id = f.rowid \
             WHERE conversation_fts MATCH ?1 ORDER BY bm25(conversation_fts), c.id DESC LIMIT ?2",
        )?;
        let rows = stmt
            .query_map(rusqlite::params![terms.join(" OR "), limit], |r| {
                Ok(Exchange {
                    ts_ms: r.get(0)?,
                    question: r.get(1)?,
                    answer: r.get(2)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    /// The conversation since `ts_ms`, oldest first.
    pub fn conversation_since(&self, ts_ms: i64) -> Result<Vec<Exchange>, StoreError> {
        let conn = self.conn();
        let mut stmt = conn.prepare(
            "SELECT ts_ms, question, answer FROM conversation WHERE ts_ms >= ?1 ORDER BY id",
        )?;
        let rows = stmt
            .query_map([ts_ms], |r| {
                Ok(Exchange {
                    ts_ms: r.get(0)?,
                    question: r.get(1)?,
                    answer: r.get(2)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    /// Deletes the kept conversation (the history switch turned off).
    pub fn clear_conversation(&self) -> Result<(), StoreError> {
        self.conn()
            .execute_batch("DELETE FROM conversation; PRAGMA wal_checkpoint(TRUNCATE);")?;
        Ok(())
    }

    /// Forgets one fact; `false` when there was none with `id`.
    pub fn forget(&self, id: i64) -> Result<bool, StoreError> {
        Ok(self
            .conn()
            .execute("DELETE FROM memory WHERE id = ?1", [id])?
            > 0)
    }

    /// Deletes the logs, the triage list and what Pilot remembers. `secure_delete` overwrites the freed pages, and
    /// the WAL is checkpointed and truncated so nothing lingers there.
    pub fn wipe(&self) -> Result<(), StoreError> {
        let conn = self.conn();
        conn.execute_batch(
            "DELETE FROM egress; DELETE FROM decisions; DELETE FROM triage; DELETE FROM memory; DELETE FROM conversation; VACUUM; PRAGMA wal_checkpoint(TRUNCATE);",
        )?;
        Ok(())
    }
}

impl EgressSink for Store {
    fn record(&self, entry: EgressEntry) {
        if let Err(e) = self.add_egress(&entry) {
            // The call already happened; failing to log it must be loud.
            log::error!("egress log write failed: {e}");
        }
    }
}

/// An in-memory sink for tests.
#[derive(Default)]
pub struct MemorySink(pub Mutex<Vec<EgressEntry>>);

impl EgressSink for MemorySink {
    fn record(&self, entry: EgressEntry) {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .push(entry);
    }
}

fn to_i64(x: u64) -> i64 {
    i64::try_from(x).unwrap_or(i64::MAX)
}

fn from_i64(x: i64) -> u64 {
    u64::try_from(x).unwrap_or(0)
}

#[cfg(unix)]
fn restrict(path: &Path) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt as _;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))
}

#[cfg(not(unix))]
fn restrict(_: &Path) -> std::io::Result<()> {
    Ok(())
}

/// How long the conversation is kept on the phone.
pub const HISTORY_DAYS: i64 = 30;

/// Words too common to search by.
const STOPWORDS: &[&str] = &[
    "the", "and", "you", "that", "what", "was", "for", "with", "about", "did", "this", "are",
    "have", "had", "when", "where", "which", "who", "how", "your", "from", "said", "told", "tell",
    "last", "week", "time", "again", "remember",
];

/// One question and answer kept from an earlier conversation.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Exchange {
    pub ts_ms: i64,
    pub question: String,
    pub answer: String,
}

/// Unix milliseconds now.
pub fn now_ms() -> i64 {
    let d = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    i64::try_from(d.as_millis()).unwrap_or(i64::MAX)
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    fn entry(n: i64) -> EgressEntry {
        EgressEntry {
            ts_ms: n,
            provider: "jev".into(),
            purpose: "decide".into(),
            bytes_out: 120,
            bytes_in: 300,
            latency_ms: 80,
            result: "ok".into(),
        }
    }

    #[test]
    fn the_conversation_is_searchable_kept_30_days_and_wiped() {
        let s = Store::memory().unwrap();
        s.log_exchange(
            "give me a quick dinner idea",
            "Try a chickpea curry with spinach.",
        )
        .unwrap();
        s.log_exchange("what's the capital of Australia?", "Canberra.")
            .unwrap();
        s.log_exchange(
            "any good Thai restaurants in Galway?",
            "Try Kai or Thai Garden.",
        )
        .unwrap();
        let hits = s
            .search_conversation("that curry recipe you gave me", 5)
            .unwrap();
        assert_eq!(hits.len(), 1);
        assert!(hits[0].answer.contains("chickpea"));
        let hits = s
            .search_conversation("the restaurant in Galway", 5)
            .unwrap();
        assert!(hits[0].question.contains("Thai"));
        let empty = s.search_conversation("the", 5).unwrap();
        assert!(empty.is_empty(), "{empty:?}");
        let empty = s.search_conversation("\"\" OR *", 5).unwrap();
        assert!(empty.is_empty(), "{empty:?}");
        // Older than 30 days goes at the next write.
        s.conn()
            .execute(
                "UPDATE conversation SET ts_ms = 0 WHERE question LIKE '%capital%'",
                [],
            )
            .unwrap();
        s.log_exchange("thanks", "You're welcome.").unwrap();
        let empty = s.search_conversation("Australia", 5).unwrap();
        assert!(empty.is_empty(), "{empty:?}");
        assert_eq!(s.conversation_since(0).unwrap().len(), 3);
        // The export holds no utterances (README, smoke test): the
        // conversation stays out of it.
        assert!(!s.export().unwrap().to_string().contains("Thai"));
        s.clear_conversation().unwrap();
        let empty = s.search_conversation("Thai", 5).unwrap();
        assert!(empty.is_empty(), "{empty:?}");
        s.log_exchange("x y z", "Thai again").unwrap();
        s.wipe().unwrap();
        let empty = s.conversation_since(0).unwrap();
        assert!(empty.is_empty(), "{empty:?}");
    }

    #[test]
    fn egress_round_trip_export_and_wipe() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("sub/pilot.db");
        let s = Store::open(&path).unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt as _;
            let mode = std::fs::metadata(&path).unwrap().permissions().mode();
            assert_eq!(mode & 0o777, 0o600);
        }
        s.record(entry(1));
        s.record(entry(2));
        let got = s.egress(1).unwrap();
        assert_eq!(got, vec![entry(2)]);
        s.add_decision(&Decision {
            turn: "t1".into(),
            ts_ms: 5,
            top_intent: "timer".into(),
            confidence: 0.9,
            second_intent: Some("alarm".into()),
            needs_generation: 0.1,
            ambiguity: 0.2,
            route: "handler".into(),
            outcome: "pending".into(),
        })
        .unwrap();
        s.set_outcome("t1", "cancelled").unwrap();
        assert_eq!(s.decisions(0).unwrap()[0].outcome, "cancelled");
        let ex = s.export().unwrap();
        assert_eq!(ex["egress"].as_array().unwrap().len(), 2);
        assert_eq!(ex["decisions"][0]["route"], "handler");
        // The export carries sizes and timings, never payload fields.
        let mut keys: Vec<&String> = ex["egress"][0].as_object().unwrap().keys().collect();
        keys.sort();
        assert_eq!(
            keys,
            [
                "bytes_in",
                "bytes_out",
                "latency_ms",
                "provider",
                "purpose",
                "result",
                "ts_ms"
            ]
        );
        s.wipe().unwrap();
        let empty = s.egress(0).unwrap();
        assert!(empty.is_empty(), "{empty:?}");
        let empty = s.decisions(0).unwrap();
        assert!(empty.is_empty(), "{empty:?}");
    }

    #[test]
    fn egress_and_decisions_are_bounded_by_age_and_count() {
        let s = Store::memory().unwrap();
        let now = now_ms();
        let day = 86_400_000;
        // Older than the keep window: gone at the next write.
        s.add_egress(&entry(now - (LOG_KEEP_DAYS + 1) * day))
            .unwrap();
        s.add_egress(&entry(now - (LOG_KEEP_DAYS - 1) * day))
            .unwrap();
        s.add_egress(&entry(now)).unwrap();
        let kept: Vec<i64> = s.egress(0).unwrap().iter().map(|e| e.ts_ms).collect();
        assert_eq!(kept, vec![now, now - (LOG_KEEP_DAYS - 1) * day]);

        let decision = |turn: String, ts_ms: i64| Decision {
            turn,
            ts_ms,
            top_intent: "timer".into(),
            confidence: 0.9,
            second_intent: None,
            needs_generation: 0.1,
            ambiguity: 0.1,
            route: "local".into(),
            outcome: "done".into(),
        };
        s.add_decision(&decision("old".into(), now - (LOG_KEEP_DAYS + 5) * day))
            .unwrap();
        // More than the row cap, all recent: the newest LOG_KEEP_ROWS stay.
        {
            let conn = s.conn();
            for i in 0..LOG_KEEP_ROWS + 10 {
                conn.execute(
                    "INSERT INTO egress (ts_ms, provider, purpose, bytes_out, bytes_in, latency_ms, result)
                     VALUES (?1, 'jev', 'decide', 1, 1, 1, 'ok')",
                    [now - 1000 + i % 1000],
                )
                .unwrap();
            }
        }
        s.add_egress(&entry(now + 1)).unwrap();
        s.add_decision(&decision("new".into(), now)).unwrap();
        let egress = s.egress(0).unwrap();
        assert_eq!(egress.len(), usize::try_from(LOG_KEEP_ROWS).unwrap());
        assert_eq!(egress[0].ts_ms, now + 1);
        let turns: Vec<String> = s
            .decisions(0)
            .unwrap()
            .into_iter()
            .map(|d| d.turn)
            .collect();
        assert_eq!(turns, vec!["new".to_owned()]);
    }

    #[test]
    fn triage_keeps_the_newest_and_wipes() {
        let s = Store::memory().unwrap();
        let item = |ts: i64| TriageItem {
            id: 0,
            ts_ms: ts,
            source: "sms".into(),
            app: "Messages".into(),
            title: format!("t{ts}"),
            body: String::new(),
            bucket: "today".into(),
            urgency: 1.0,
            interrupt: 0.2,
        };
        for ts in 0..TRIAGE_KEEP + 5 {
            s.add_triage(&item(ts)).unwrap();
        }
        let all = s.triage(0).unwrap();
        assert_eq!(all.len(), usize::try_from(TRIAGE_KEEP).unwrap());
        assert_eq!(all[0].title, format!("t{}", TRIAGE_KEEP + 4));
        assert_eq!(
            s.export().unwrap()["triage"].as_array().unwrap().len(),
            all.len()
        );
        s.wipe().unwrap();
        let empty = s.triage(0).unwrap();
        assert!(empty.is_empty(), "{empty:?}");
    }
}
