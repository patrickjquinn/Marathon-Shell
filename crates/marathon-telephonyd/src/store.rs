//! `messages.db`: messages, their threads and their attachments, whose
//! files live in `$XDG_DATA_HOME/marathon/mms/<message id>/` (docs/MMS.md).

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use rusqlite::{params, Connection, OptionalExtension};
use zbus::zvariant::Value;

pub type Row = HashMap<&'static str, Value<'static>>;

pub struct Message<'a> {
    pub sender: &'a str,
    pub recipient: &'a str,
    pub text: &'a str,
    pub timestamp: i64,
    pub outgoing: bool,
    /// `sending`, `sent`, `failed` or `received`.
    pub status: &'a str,
    pub mms_path: &'a str,
}

pub struct Attachment {
    pub content_type: String,
    pub name: String,
    pub size: i64,
    pub path: PathBuf,
}

pub struct Store {
    db: Connection,
    files: PathBuf,
}

/// A thread's id: the number's digits and `+`.
pub fn conversation_id(number: &str) -> String {
    marathon_rt::daemon::dialable(number)
}

impl Store {
    pub fn open(db: &Path, files: PathBuf) -> rusqlite::Result<Self> {
        if let Some(dir) = db.parent() {
            fs::create_dir_all(dir).ok();
        }
        let store = Self { db: Connection::open(db)?, files };
        store.migrate()?;
        Ok(store)
    }

    fn migrate(&self) -> rusqlite::Result<()> {
        self.db.execute_batch(
            "PRAGMA journal_mode = WAL;
             CREATE TABLE IF NOT EXISTS messages (id INTEGER PRIMARY KEY AUTOINCREMENT,
                 conversationId TEXT NOT NULL, sender TEXT NOT NULL, recipient TEXT NOT NULL,
                 text TEXT NOT NULL, timestamp INTEGER NOT NULL, isRead INTEGER DEFAULT 0,
                 isOutgoing INTEGER DEFAULT 0);
             CREATE INDEX IF NOT EXISTS idx_conversation ON messages(conversationId);
             CREATE INDEX IF NOT EXISTS idx_timestamp ON messages(timestamp);",
        )?;
        let columns: Vec<String> = self
            .db
            .prepare("PRAGMA table_info(messages)")?
            .query_map([], |row| row.get(1))?
            .collect::<rusqlite::Result<_>>()?;
        for column in ["status", "participants", "mmsPath"] {
            if !columns.iter().any(|c| c == column) {
                self.db.execute(&format!("ALTER TABLE messages ADD COLUMN {column} TEXT NOT NULL DEFAULT ''"), [])?;
            }
        }
        self.db.execute_batch(
            "UPDATE messages SET status = CASE WHEN isOutgoing = 1 THEN 'sent' ELSE 'received' END
                 WHERE status = '';
             CREATE TABLE IF NOT EXISTS attachments (id INTEGER PRIMARY KEY AUTOINCREMENT,
                 messageId INTEGER NOT NULL, contentType TEXT NOT NULL, name TEXT NOT NULL,
                 size INTEGER NOT NULL, path TEXT NOT NULL);
             CREATE INDEX IF NOT EXISTS idx_attachment_message ON attachments(messageId);",
        )
    }

    /// The threads, newest first.
    pub fn conversations(&self) -> rusqlite::Result<Vec<Row>> {
        let mut query = self.db.prepare(
            "SELECT conversationId, text, recipient, MAX(timestamp) AS last,
                    SUM(isRead = 0 AND isOutgoing = 0)
             FROM messages GROUP BY conversationId ORDER BY last DESC",
        )?;
        let rows = query.query_map([], |row| {
            let id: String = row.get(0)?;
            let recipient: String = row.get(2)?;
            let number = if recipient == "me" || recipient.is_empty() { id.clone() } else { recipient };
            Ok(Row::from([
                ("id", Value::from(id)),
                ("contactName", Value::from(number.clone())),
                ("contactNumber", Value::from(number)),
                ("lastMessage", Value::from(row.get::<_, String>(1)?)),
                ("lastTimestamp", Value::from(row.get::<_, i64>(3)?)),
                ("unreadCount", Value::from(row.get::<_, i32>(4)?)),
            ]))
        })?;
        rows.collect()
    }

    pub fn messages(&self, conversation: &str) -> rusqlite::Result<Vec<Row>> {
        let mut query = self.db.prepare(
            "SELECT id, conversationId, sender, recipient, text, timestamp, isRead, isOutgoing, status
             FROM messages WHERE conversationId = ? ORDER BY timestamp ASC",
        )?;
        let rows = query.query_map([conversation], |row| {
            let id: i32 = row.get(0)?;
            Ok((
                id,
                Row::from([
                    ("id", Value::from(id)),
                    ("conversationId", Value::from(row.get::<_, String>(1)?)),
                    ("sender", Value::from(row.get::<_, String>(2)?)),
                    ("recipient", Value::from(row.get::<_, String>(3)?)),
                    ("text", Value::from(row.get::<_, String>(4)?)),
                    ("timestamp", Value::from(row.get::<_, i64>(5)?)),
                    ("isRead", Value::from(row.get::<_, bool>(6)?)),
                    ("isOutgoing", Value::from(row.get::<_, bool>(7)?)),
                    ("status", Value::from(row.get::<_, String>(8)?)),
                ]),
            ))
        })?;
        let mut attachments = self
            .db
            .prepare("SELECT id, contentType, name, size FROM attachments WHERE messageId = ? ORDER BY id")?;
        rows.map(|row| {
            let (id, mut message) = row?;
            let list: Vec<Value> = attachments
                .query_map([id], |a| {
                    Ok(Value::from(Row::from([
                        ("id", Value::from(a.get::<_, i32>(0)?)),
                        ("contentType", Value::from(a.get::<_, String>(1)?)),
                        ("name", Value::from(a.get::<_, String>(2)?)),
                        ("size", Value::from(a.get::<_, i64>(3)?)),
                    ])))
                })?
                .collect::<rusqlite::Result<_>>()?;
            message.insert("attachments", Value::from(list));
            Ok(message)
        })
        .collect()
    }

    pub fn insert(&self, m: &Message) -> rusqlite::Result<i32> {
        let thread = if m.outgoing { m.recipient } else { m.sender };
        self.db.execute(
            "INSERT INTO messages (conversationId, sender, recipient, text, timestamp, isRead,
                 isOutgoing, status, mmsPath) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            params![conversation_id(thread), m.sender, m.recipient, m.text, m.timestamp, m.outgoing, m.outgoing, m.status, m.mms_path],
        )?;
        Ok(i32::try_from(self.db.last_insert_rowid()).unwrap_or(i32::MAX))
    }

    /// An incoming message already stored, as `ModemManager` lists a text
    /// until it is deleted.
    pub fn has(&self, sender: &str, timestamp: i64, text: &str) -> bool {
        self.db
            .query_row("SELECT 1 FROM messages WHERE sender = ? AND timestamp = ? AND text = ?", params![sender, timestamp, text], |_| Ok(()))
            .optional()
            .is_ok_and(|found| found.is_some())
    }

    pub fn set_status(&self, id: i32, status: &str) -> bool {
        self.db.execute("UPDATE messages SET status = ? WHERE id = ?", params![status, id]).is_ok_and(|n| n > 0)
    }

    pub fn set_mms_path(&self, id: i32, path: &str) -> rusqlite::Result<usize> {
        self.db.execute("UPDATE messages SET mmsPath = ? WHERE id = ?", params![path, id])
    }

    pub fn sent_as(&self, mms_path: &str) -> Option<i32> {
        self.db
            .query_row("SELECT id FROM messages WHERE mmsPath = ? AND isOutgoing = 1", [mms_path], |row| row.get(0))
            .optional()
            .ok()
            .flatten()
    }

    pub fn mark_read(&self, conversation: &str) -> rusqlite::Result<usize> {
        self.db.execute("UPDATE messages SET isRead = 1 WHERE conversationId = ?", [conversation])
    }

    pub fn delete_message(&self, id: i32) -> rusqlite::Result<bool> {
        self.remove_attachments("id", &id)?;
        Ok(self.db.execute("DELETE FROM messages WHERE id = ?", [id])? > 0)
    }

    pub fn delete_conversation(&self, conversation: &str) -> rusqlite::Result<usize> {
        self.remove_attachments("conversationId", &conversation)?;
        self.db.execute("DELETE FROM messages WHERE conversationId = ?", [conversation])
    }

    fn remove_attachments(&self, column: &str, value: &dyn rusqlite::ToSql) -> rusqlite::Result<()> {
        let ids: Vec<i32> = self
            .db
            .prepare(&format!("SELECT id FROM messages WHERE {column} = ?"))?
            .query_map([value], |row| row.get(0))?
            .collect::<rusqlite::Result<_>>()?;
        for id in ids {
            fs::remove_dir_all(self.files.join(id.to_string())).ok();
            self.db.execute("DELETE FROM attachments WHERE messageId = ?", [id])?;
        }
        Ok(())
    }

    /// Stores `data` as an attachment of `message`; `name` is reduced to a
    /// file name.
    pub fn add_attachment(&self, message: i32, content_type: &str, name: &str, data: &[u8]) -> Option<i32> {
        let file = match Path::new(name).file_name().and_then(|n| n.to_str()) {
            Some(file) if file != "." && file != ".." => file.to_owned(),
            _ => "attachment".to_owned(),
        };
        let dir = self.files.join(message.to_string());
        fs::create_dir_all(&dir).ok()?;
        let mut path = dir.join(&file);
        for n in 2.. {
            if !path.exists() {
                break;
            }
            path = dir.join(format!("{n}-{file}"));
        }
        fs::write(&path, data).ok()?;
        let size = i64::try_from(data.len()).ok()?;
        let stored = self.db.execute(
            "INSERT INTO attachments (messageId, contentType, name, size, path) VALUES (?, ?, ?, ?, ?)",
            params![message, content_type, file, size, path.to_string_lossy()],
        );
        if stored.is_err() {
            fs::remove_file(&path).ok();
            return None;
        }
        i32::try_from(self.db.last_insert_rowid()).ok()
    }

    pub fn attachment(&self, id: i32) -> Option<Attachment> {
        self.db
            .query_row("SELECT contentType, name, size, path FROM attachments WHERE id = ?", [id], |row| {
                Ok(Attachment {
                    content_type: row.get(0)?,
                    name: row.get(1)?,
                    size: row.get(2)?,
                    path: PathBuf::from(row.get::<_, String>(3)?),
                })
            })
            .optional()
            .ok()
            .flatten()
    }

    /// The attachment's file is now a JPEG of `size` bytes.
    pub fn became_jpeg(&self, id: i32, name: &str, size: i64) -> bool {
        let stem = Path::new(name).file_stem().map_or_else(|| "attachment".into(), |s| s.to_string_lossy());
        self.db
            .execute("UPDATE attachments SET contentType = 'image/jpeg', name = ?, size = ? WHERE id = ?", params![format!("{stem}.jpg"), size, id])
            .is_ok_and(|n| n > 0)
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    fn store(dir: &Path) -> Store {
        Store::open(&dir.join("messages.db"), dir.join("mms")).unwrap()
    }

    fn received<'a>(sender: &'a str, text: &'a str, timestamp: i64) -> Message<'a> {
        Message { sender, recipient: "me", text, timestamp, outgoing: false, status: "received", mms_path: "" }
    }

    fn text(row: &Row, key: &str) -> String {
        String::try_from(row[key].try_clone().unwrap()).unwrap()
    }

    #[test]
    fn deleting_a_message_leaves_the_rest_of_its_thread() {
        let dir = tempfile::tempdir().unwrap();
        let s = store(dir.path());
        let first = s.insert(&received("+15550001", "first", 1)).unwrap();
        s.insert(&received("+15550001", "second", 2)).unwrap();
        assert!(s.delete_message(first).unwrap());
        let left = s.messages("+15550001").unwrap();
        assert_eq!(left.len(), 1);
        assert_eq!(text(&left[0], "text"), "second");
        assert_eq!(text(&s.conversations().unwrap()[0], "lastMessage"), "second");
        assert!(!s.delete_message(999_999).unwrap());
    }

    #[test]
    fn deleting_the_last_message_drops_the_thread() {
        let dir = tempfile::tempdir().unwrap();
        let s = store(dir.path());
        let id = s.insert(&received("+15550002", "only", 1)).unwrap();
        assert!(s.delete_message(id).unwrap());
        assert_eq!(s.conversations().unwrap().len(), 0);
    }

    #[test]
    fn a_database_from_before_mms_is_migrated() {
        let dir = tempfile::tempdir().unwrap();
        let old = Connection::open(dir.path().join("messages.db")).unwrap();
        old.execute_batch(
            "CREATE TABLE messages (id INTEGER PRIMARY KEY AUTOINCREMENT, conversationId TEXT NOT NULL,
                 sender TEXT NOT NULL, recipient TEXT NOT NULL, text TEXT NOT NULL,
                 timestamp INTEGER NOT NULL, isRead INTEGER DEFAULT 0, isOutgoing INTEGER DEFAULT 0);
             INSERT INTO messages (conversationId, sender, recipient, text, timestamp, isRead, isOutgoing)
                 VALUES ('+1555', '+1555', 'me', 'in', 1, 0, 0), ('+1555', 'me', '+1555', 'out', 2, 1, 1);",
        )
        .unwrap();
        drop(old);
        let messages = store(dir.path()).messages("+1555").unwrap();
        assert_eq!(text(&messages[0], "status"), "received");
        assert_eq!(text(&messages[1], "status"), "sent");
    }

    #[test]
    fn an_attachment_goes_with_its_message() {
        let dir = tempfile::tempdir().unwrap();
        let s = store(dir.path());
        let id = s.insert(&received("+15550003", "", 1)).unwrap();
        let attachment = s.add_attachment(id, "image/png", "../../beach.png", b"\x89PNG data").unwrap();
        let stored = s.attachment(attachment).unwrap();
        assert_eq!(stored.name, "beach.png");
        assert_eq!(stored.size, 9);
        assert!(stored.path.starts_with(dir.path().join("mms")));
        assert_eq!(fs::read(&stored.path).unwrap(), b"\x89PNG data");
        assert!(s.delete_message(id).unwrap());
        assert!(!stored.path.exists());
        assert!(s.attachment(attachment).is_none());
    }
}
