//! `mail.db`: the accounts, their folders, and the newest messages of each
//! folder as the server sent them (RFC 822), parsed for the lists.

use std::collections::HashMap;
use std::fs;
use std::path::Path;

use mail_parser::{MessageParser, MimeHeaders};
use rusqlite::{params, Connection, OptionalExtension};
use zbus::zvariant::Value;

pub type Row = HashMap<&'static str, Value<'static>>;

/// How a server is reached: 0 plain, 1 TLS, 2 STARTTLS.
#[derive(Clone, Debug, Default)]
pub struct Server {
    pub host: String,
    pub port: u16,
    pub security: u8,
}

#[derive(Clone, Debug, Default)]
pub struct Account {
    pub id: i64,
    pub name: String,
    pub address: String,
    pub username: String,
    pub imap: Server,
    pub smtp: Server,
    /// "" for a password, else the OAuth provider ("gmail", "outlook").
    pub provider: String,
}

/// A message's list entry, from its headers and first text.
pub struct Summary {
    pub subject: String,
    pub sender: String,
    pub address: String,
    pub date: i64,
    pub snippet: String,
    pub attachment: bool,
}

pub fn summarise(raw: &[u8]) -> Summary {
    let Some(m) = MessageParser::default().parse(raw) else {
        return Summary { subject: String::new(), sender: String::new(), address: String::new(), date: 0, snippet: String::new(), attachment: false };
    };
    let from = m.from().and_then(|a| a.first());
    let address = from.and_then(|a| a.address()).unwrap_or_default().to_owned();
    let sender = from.and_then(|a| a.name()).map_or_else(|| address.clone(), str::to_owned);
    let snippet: String = m.body_text(0).unwrap_or_default().split_whitespace().collect::<Vec<_>>().join(" ").chars().take(200).collect();
    Summary {
        subject: m.subject().unwrap_or_default().to_owned(),
        sender,
        address,
        date: m.date().map_or(0, |d| d.to_timestamp() * 1000),
        snippet,
        attachment: m.attachment_count() > 0,
    }
}

/// The folder kind from its special-use attribute or its name.
pub fn kind(path: &str, special: Option<&str>) -> &'static str {
    let name = path.rsplit(['/', '.']).next().unwrap_or(path).to_lowercase();
    match special {
        _ if path.eq_ignore_ascii_case("inbox") => "inbox",
        Some("\\Sent") => "sent",
        Some("\\Drafts") => "drafts",
        Some("\\Trash") => "trash",
        Some("\\Junk") => "junk",
        Some("\\Archive" | "\\All") => "archive",
        _ => match name.as_str() {
            "sent" | "sent items" | "sent mail" | "sent messages" => "sent",
            "drafts" => "drafts",
            "trash" | "deleted items" | "deleted messages" | "bin" => "trash",
            "junk" | "spam" => "junk",
            "archive" | "all mail" => "archive",
            _ => "other",
        },
    }
}

pub struct Store {
    db: Connection,
}

fn text(s: impl Into<String>) -> Value<'static> {
    Value::from(s.into())
}

impl Store {
    pub fn open(path: &Path) -> rusqlite::Result<Self> {
        if let Some(dir) = path.parent() {
            fs::create_dir_all(dir).ok();
        }
        let db = Connection::open(path)?;
        db.execute_batch(
            "PRAGMA journal_mode = WAL;
             CREATE TABLE IF NOT EXISTS accounts (id INTEGER PRIMARY KEY, name TEXT, address TEXT,
                 username TEXT, imap_host TEXT, imap_port INTEGER, imap_security INTEGER,
                 smtp_host TEXT, smtp_port INTEGER, smtp_security INTEGER, provider TEXT);
             CREATE TABLE IF NOT EXISTS folders (account INTEGER, path TEXT, name TEXT, kind TEXT,
                 unread INTEGER DEFAULT 0, total INTEGER DEFAULT 0, validity INTEGER DEFAULT 0,
                 PRIMARY KEY (account, path));
             CREATE TABLE IF NOT EXISTS messages (id INTEGER PRIMARY KEY, account INTEGER, folder TEXT,
                 uid INTEGER, seen INTEGER, subject TEXT, sender TEXT, address TEXT, date INTEGER,
                 snippet TEXT, attachment INTEGER, raw BLOB, UNIQUE (account, folder, uid));
             CREATE INDEX IF NOT EXISTS messages_folder ON messages (account, folder, date);
             CREATE TABLE IF NOT EXISTS outbox (id INTEGER PRIMARY KEY, account INTEGER, raw BLOB, recipients TEXT);
             CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT);",
        )?;
        Ok(Self { db })
    }

    pub fn add_account(&self, a: &Account) -> rusqlite::Result<i64> {
        self.db.execute(
            "INSERT INTO accounts (name, address, username, imap_host, imap_port, imap_security,
                 smtp_host, smtp_port, smtp_security, provider) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
            params![a.name, a.address, a.username, a.imap.host, a.imap.port, a.imap.security, a.smtp.host, a.smtp.port, a.smtp.security, a.provider],
        )?;
        Ok(self.db.last_insert_rowid())
    }

    pub fn remove_account(&self, id: i64) -> rusqlite::Result<()> {
        for table in ["accounts WHERE id", "folders WHERE account", "messages WHERE account", "outbox WHERE account"] {
            self.db.execute(&format!("DELETE FROM {table} = ?1"), [id])?;
        }
        Ok(())
    }

    pub fn accounts(&self) -> rusqlite::Result<Vec<Account>> {
        let mut q = self.db.prepare(
            "SELECT id, name, address, username, imap_host, imap_port, imap_security, smtp_host, smtp_port,
                 smtp_security, provider FROM accounts ORDER BY id",
        )?;
        let rows = q.query_map([], |r| {
            Ok(Account {
                id: r.get(0)?,
                name: r.get(1)?,
                address: r.get(2)?,
                username: r.get(3)?,
                imap: Server { host: r.get(4)?, port: r.get(5)?, security: r.get(6)? },
                smtp: Server { host: r.get(7)?, port: r.get(8)?, security: r.get(9)? },
                provider: r.get(10)?,
            })
        })?;
        rows.collect()
    }

    pub fn account(&self, id: i64) -> Option<Account> {
        self.accounts().ok()?.into_iter().find(|a| a.id == id)
    }

    /// The server's folders; any other is forgotten with its messages.
    pub fn set_folders(&mut self, account: i64, folders: &[(String, &'static str)]) -> rusqlite::Result<()> {
        let tx = self.db.transaction()?;
        for (path, kind) in folders {
            let name = if *kind == "inbox" { "Inbox" } else { path.rsplit(['/', '.']).next().unwrap_or(path) };
            tx.execute(
                "INSERT INTO folders (account, path, name, kind) VALUES (?1, ?2, ?3, ?4)
                 ON CONFLICT (account, path) DO UPDATE SET name = ?3, kind = ?4",
                params![account, path, name, kind],
            )?;
        }
        let keep: Vec<&str> = folders.iter().map(|(p, _)| p.as_str()).collect();
        let mut gone = Vec::new();
        {
            let mut q = tx.prepare("SELECT path FROM folders WHERE account = ?1")?;
            for path in q.query_map([account], |r| r.get::<_, String>(0))? {
                let path = path?;
                if !keep.contains(&path.as_str()) {
                    gone.push(path);
                }
            }
        }
        for path in gone {
            tx.execute("DELETE FROM folders WHERE account = ?1 AND path = ?2", params![account, path])?;
            tx.execute("DELETE FROM messages WHERE account = ?1 AND folder = ?2", params![account, path])?;
        }
        tx.commit()
    }

    pub fn set_counts(&self, account: i64, folder: &str, unread: u32, total: u32) -> rusqlite::Result<()> {
        self.db.execute("UPDATE folders SET unread = ?3, total = ?4 WHERE account = ?1 AND path = ?2", params![account, folder, unread, total]).map(drop)
    }

    pub fn folder_of_kind(&self, account: i64, kind: &str) -> Option<String> {
        self.db.query_row("SELECT path FROM folders WHERE account = ?1 AND kind = ?2", params![account, kind], |r| r.get(0)).optional().ok().flatten()
    }

    /// The folder's UIDVALIDITY changed: its UIDs mean other messages now.
    pub fn validate(&self, account: i64, folder: &str, validity: u32) -> rusqlite::Result<()> {
        let old: u32 = self.db.query_row("SELECT validity FROM folders WHERE account = ?1 AND path = ?2", params![account, folder], |r| r.get(0)).optional()?.unwrap_or(0);
        if old != validity {
            self.db.execute("DELETE FROM messages WHERE account = ?1 AND folder = ?2", params![account, folder])?;
            self.db.execute("UPDATE folders SET validity = ?3 WHERE account = ?1 AND path = ?2", params![account, folder, validity])?;
        }
        Ok(())
    }

    pub fn uids(&self, account: i64, folder: &str) -> rusqlite::Result<HashMap<u32, bool>> {
        let mut q = self.db.prepare("SELECT uid, seen FROM messages WHERE account = ?1 AND folder = ?2")?;
        let rows = q.query_map(params![account, folder], |r| Ok((r.get(0)?, r.get(1)?)))?.collect();
        rows
    }

    /// The server's view of the folder's newest messages: their seen flags,
    /// and the rest gone.
    pub fn reconcile(&mut self, account: i64, folder: &str, server: &HashMap<u32, bool>) -> rusqlite::Result<()> {
        let tx = self.db.transaction()?;
        let local: Vec<u32> = {
            let mut q = tx.prepare("SELECT uid FROM messages WHERE account = ?1 AND folder = ?2")?;
            let uids = q.query_map(params![account, folder], |r| r.get(0))?.collect::<rusqlite::Result<_>>()?;
            uids
        };
        for uid in local {
            match server.get(&uid) {
                Some(seen) => tx.execute("UPDATE messages SET seen = ?4 WHERE account = ?1 AND folder = ?2 AND uid = ?3", params![account, folder, uid, seen])?,
                None => tx.execute("DELETE FROM messages WHERE account = ?1 AND folder = ?2 AND uid = ?3", params![account, folder, uid])?,
            };
        }
        tx.commit()
    }

    /// A new message; its id, or none when it was already there.
    pub fn insert(&self, account: i64, folder: &str, uid: u32, seen: bool, raw: &[u8]) -> rusqlite::Result<Option<i64>> {
        let s = summarise(raw);
        let added = self.db.execute(
            "INSERT OR IGNORE INTO messages (account, folder, uid, seen, subject, sender, address, date, snippet, attachment, raw)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
            params![account, folder, uid, seen, s.subject, s.sender, s.address, s.date, s.snippet, s.attachment, raw],
        )?;
        Ok((added > 0).then(|| self.db.last_insert_rowid()))
    }

    pub fn set_seen(&self, id: i64, seen: bool) -> rusqlite::Result<()> {
        self.db.execute("UPDATE messages SET seen = ?2 WHERE id = ?1", params![id, seen]).map(drop)
    }

    pub fn delete(&self, id: i64) -> rusqlite::Result<()> {
        self.db.execute("DELETE FROM messages WHERE id = ?1", [id]).map(drop)
    }

    /// Where a message is: its account, folder and UID.
    pub fn locate(&self, id: i64) -> Option<(i64, String, u32)> {
        self.db.query_row("SELECT account, folder, uid FROM messages WHERE id = ?1", [id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).optional().ok().flatten()
    }

    pub fn raw(&self, id: i64) -> Option<Vec<u8>> {
        self.db.query_row("SELECT raw FROM messages WHERE id = ?1", [id], |r| r.get(0)).optional().ok().flatten()
    }

    pub fn messages(&self, account: i64, folder: &str) -> rusqlite::Result<Vec<Row>> {
        if folder == "outbox" {
            let mut q = self.db.prepare("SELECT id, raw FROM outbox WHERE account = ?1 ORDER BY id DESC")?;
            let rows = q.query_map([account], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, Vec<u8>>(1)?)))?;
            return rows
                .map(|row| {
                    let (id, raw) = row?;
                    let s = summarise(&raw);
                    Ok(Row::from([
                        ("messageId", text(format!("outbox:{id}"))),
                        ("subject", text(s.subject)),
                        ("from", text(s.sender)),
                        ("address", text(s.address)),
                        ("snippet", text(s.snippet)),
                        ("date", Value::from(s.date)),
                        ("unread", Value::from(false)),
                        ("hasAttachment", Value::from(s.attachment)),
                    ]))
                })
                .collect();
        }
        let mut q = self.db.prepare(
            "SELECT id, subject, sender, address, snippet, date, seen, attachment FROM messages
             WHERE account = ?1 AND folder = ?2 ORDER BY date DESC",
        )?;
        let rows = q.query_map(params![account, folder], |r| {
            Ok(Row::from([
                ("messageId", text(r.get::<_, i64>(0)?.to_string())),
                ("subject", text(r.get::<_, String>(1)?)),
                ("from", text(r.get::<_, String>(2)?)),
                ("address", text(r.get::<_, String>(3)?)),
                ("snippet", text(r.get::<_, String>(4)?)),
                ("date", Value::from(r.get::<_, i64>(5)?)),
                ("unread", Value::from(!r.get::<_, bool>(6)?)),
                ("hasAttachment", Value::from(r.get::<_, bool>(7)?)),
            ]))
        })?;
        rows.collect()
    }

    /// Every account with its folders, as `MailService.accountList` shows them.
    pub fn account_list(&self) -> rusqlite::Result<Vec<Row>> {
        let mut out = Vec::new();
        for a in self.accounts()? {
            let mut q = self.db.prepare(
                "SELECT path, name, kind, unread, total FROM folders WHERE account = ?1
                 ORDER BY CASE kind WHEN 'inbox' THEN 0 WHEN 'drafts' THEN 1 WHEN 'sent' THEN 2
                 WHEN 'archive' THEN 3 WHEN 'junk' THEN 4 WHEN 'trash' THEN 5 ELSE 6 END, name",
            )?;
            let mut folders: Vec<Value<'static>> = q
                .query_map([a.id], |r| {
                    Ok(Value::from(HashMap::from([
                        ("id", text(r.get::<_, String>(0)?)),
                        ("name", text(r.get::<_, String>(1)?)),
                        ("kind", text(r.get::<_, String>(2)?)),
                        ("unread", Value::from(r.get::<_, i64>(3)?)),
                        ("count", Value::from(r.get::<_, i64>(4)?)),
                    ])))
                })?
                .collect::<rusqlite::Result<_>>()?;
            let queued: i64 = self.db.query_row("SELECT COUNT(*) FROM outbox WHERE account = ?1", [a.id], |r| r.get(0))?;
            if queued > 0 {
                folders.push(Value::from(HashMap::from([
                    ("id", text("outbox")),
                    ("name", text("Outbox")),
                    ("kind", text("outbox")),
                    ("unread", Value::from(0i64)),
                    ("count", Value::from(queued)),
                ])));
            }
            let unread: i64 = self.db.query_row("SELECT COALESCE(SUM(unread), 0) FROM folders WHERE account = ?1 AND kind = 'inbox'", [a.id], |r| r.get(0))?;
            out.push(Row::from([
                ("id", text(a.id.to_string())),
                ("name", text(a.name)),
                ("address", text(a.address)),
                ("unread", Value::from(unread)),
                ("outbox", Value::from(queued)),
                ("folders", Value::from(folders)),
            ]));
        }
        Ok(out)
    }

    /// A message to send; `recipients` are its envelope's, Bcc included.
    pub fn queue(&self, account: i64, raw: &[u8], recipients: &str) -> rusqlite::Result<()> {
        self.db.execute("INSERT INTO outbox (account, raw, recipients) VALUES (?1, ?2, ?3)", params![account, raw, recipients]).map(drop)
    }

    /// What waits: id, account, the message and its envelope's recipients.
    #[allow(clippy::type_complexity, reason = "one row's columns")]
    pub fn queued(&self) -> rusqlite::Result<Vec<(i64, i64, Vec<u8>, String)>> {
        let mut q = self.db.prepare("SELECT id, account, raw, recipients FROM outbox ORDER BY id")?;
        let rows = q.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))?;
        rows.collect()
    }

    pub fn sent(&self, id: i64) -> rusqlite::Result<()> {
        self.db.execute("DELETE FROM outbox WHERE id = ?1", [id]).map(drop)
    }

    pub fn setting(&self, key: &str) -> String {
        self.db.query_row("SELECT value FROM settings WHERE key = ?1", [key], |r| r.get(0)).optional().ok().flatten().unwrap_or_default()
    }

    pub fn set_setting(&self, key: &str, value: &str) -> rusqlite::Result<()> {
        self.db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?1, ?2)", params![key, value]).map(drop)
    }
}

/// An attachment's bytes and name, by its index among the message's
/// attachments (its `location`).
pub fn attachment(raw: &[u8], location: usize) -> Option<(String, Vec<u8>)> {
    let m = MessageParser::default().parse(raw)?;
    let part = m.attachment(u32::try_from(location).ok()?)?;
    let name = part.attachment_name().unwrap_or("attachment").replace(['/', '\\'], "_");
    Some((name, part.contents().to_vec()))
}

/// A message as `MailService.openMessage` gives it.
pub fn open(raw: &[u8]) -> Row {
    let Some(m) = MessageParser::default().parse(raw) else { return Row::new() };
    let addresses = |a: Option<&mail_parser::Address<'_>>| -> Vec<String> {
        a.map(|a| a.iter().map(|x| match (x.name(), x.address()) {
            (Some(n), Some(e)) => format!("{n} <{e}>"),
            (n, e) => n.or(e).unwrap_or_default().to_owned(),
        }).collect()).unwrap_or_default()
    };
    let attachments: Vec<Value<'static>> = m
        .attachments()
        .enumerate()
        .map(|(i, p)| {
            Value::from(HashMap::from([
                ("name", text(p.attachment_name().unwrap_or("attachment"))),
                ("size", Value::from(u64::try_from(p.contents().len()).unwrap_or(0))),
                ("mime", text(p.content_type().map_or_else(|| "application/octet-stream".to_owned(), |c| c.subtype().map_or_else(|| c.ctype().to_owned(), |s| format!("{}/{s}", c.ctype()))))),
                ("location", text(i.to_string())),
            ]))
        })
        .collect();
    let mut row = Row::from([
        ("subject", text(m.subject().unwrap_or_default())),
        ("from", text(addresses(m.from()).join(", "))),
        ("to", Value::from(addresses(m.to()))),
        ("cc", Value::from(addresses(m.cc()))),
        ("date", Value::from(m.date().map_or(0, |d| d.to_timestamp() * 1000))),
        ("bodyPlain", text(m.body_text(0).unwrap_or_default())),
        ("attachments", Value::from(attachments)),
    ]);
    if m.html_part(0).is_some_and(mail_parser::MessagePart::is_text_html) {
        row.insert("bodyHtml", text(m.body_html(0).unwrap_or_default()));
    }
    row
}
