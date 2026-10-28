// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Sailfish's own apps, through the D-Bus entry points they publish for the
//! system (sharing, notifications, the lock screen): nothing is injected
//! into them and their screens are not driven. Each call opens the app with
//! the work filled in, and the person finishes it there (sends the e-mail,
//! keeps the note, changes the setting).
//!
//! | App | Service, object, interface | Method |
//! |---|---|---|
//! | Email | `com.jolla.email.ui`, `/com/jolla/email/ui` | `compose(subject, to, cc, bcc, body)` |
//! | Notes | `com.jolla.notes`, `/`, `com.jolla.notes` | `importNoteFile([url])`: a vNote's `file://` URL (a bare path is ignored), added as a new note |
//! | Settings | `com.jolla.settings`, `/com/jolla/settings/ui`, `com.jolla.settings.ui` | `showPage(path)` |
//! | Messages | `org.sailfishos.Messages`, `/` | `startSMS(as numbers, s body)`; not D-Bus activatable, so started first by its `sms:` link |

use std::path::PathBuf;
use std::time::Duration;

use async_trait::async_trait;

use super::AdapterError;

#[async_trait]
pub trait StockApps: Send + Sync {
    /// Opens a new e-mail in Email, filled in (nothing is sent). False when
    /// there is no e-mail account: Email then only offers to add one.
    async fn compose_email(
        &self,
        to: &str,
        subject: &str,
        body: &str,
    ) -> Result<bool, AdapterError>;
    /// Adds a note in Notes and opens it.
    async fn new_note(&self, text: &str) -> Result<(), AdapterError>;
    /// Opens Settings at a page (`system_settings/connectivity/bluetooth`).
    async fn open_settings(&self, path: &str) -> Result<(), AdapterError>;
    /// Opens a text message to `number` in Messages with `body` written in
    /// (nothing is sent).
    async fn compose_sms(&self, number: &str, body: &str) -> Result<(), AdapterError>;
}

/// The settings pages Pilot opens, by the name the model uses, as Sailfish
/// 5.2's Settings entries name them (`/usr/share/jolla-settings/entries`).
pub const SETTINGS_PAGES: &[(&str, &str)] = &[
    ("about", "system_settings/info/about_device"),
    ("battery", "system_settings/system/battery"),
    ("bluetooth", "system_settings/connectivity/bluetooth"),
    ("date_time", "system_settings/system/date_time"),
    ("developer_mode", "system_settings/system/developer_mode"),
    ("device_lock", "system_settings/security/device_lock"),
    ("display", "system_settings/look_and_feel/display"),
    ("flight_mode", "system_settings/connectivity/flight"),
    ("gestures", "system_settings/look_and_feel/gestures"),
    ("location", "system_settings/connectivity/gps_and_location"),
    ("language", "system_settings/system/language_and_region"),
    ("lock_screen", "system_settings/look_and_feel/lockscreen"),
    ("mobile_network", "system_settings/connectivity/mobile"),
    ("nfc", "system_settings/connectivity/nfc"),
    ("privacy_switch", "system_settings/security/privacy_switch"),
    ("sounds", "system_settings/look_and_feel/sounds"),
    ("storage", "system_settings/system/storage"),
    ("tethering", "system_settings/connectivity/tethering"),
    ("text_input", "system_settings/system/text_input"),
    ("updates", "system_settings/system/sailfishos"),
    ("usb", "system_settings/connectivity/usb"),
    ("vpn", "system_settings/connectivity/vpn"),
    ("wifi", "system_settings/connectivity/wlan"),
];

/// The Settings path for a page name.
pub fn settings_path(page: &str) -> Option<&'static str> {
    SETTINGS_PAGES
        .iter()
        .find(|(name, _)| *name == page)
        .map(|(_, path)| *path)
}

/// A vNote 1.1 of `text`, as Notes' own export writes it (8-bit UTF-8).
/// Its importer ends the body at the first CR LF or LF and decodes neither
/// quoted-printable nor escapes (all tried on the phone), but keeps a lone
/// CR, which its editor shows as a line break: lines are joined by CR.
pub fn vnote(text: &str) -> String {
    let body = text
        .lines()
        .map(str::trim_end)
        .collect::<Vec<_>>()
        .join("\r");
    let body = body.trim_matches('\r');
    format!(
        "BEGIN:VNOTE\r\nVERSION:1.1\r\nBODY;CHARSET=UTF-8;ENCODING=8BIT:{body}\r\nEND:VNOTE\r\n"
    )
}

/// Whether an enabled account offers e-mail (libaccounts-glib's database,
/// readable by the person's own processes).
pub fn email_account(db: &std::path::Path) -> bool {
    let Ok(c) =
        rusqlite::Connection::open_with_flags(db, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)
    else {
        return false;
    };
    c.query_row(
        "SELECT COUNT(*) FROM Accounts a JOIN Services s ON s.provider = a.provider \
         WHERE a.enabled = 1 AND s.type = 'e-mail'",
        [],
        |r| r.get::<_, i64>(0),
    )
    .is_ok_and(|n| n > 0)
}

/// The stock apps on the session bus.
pub struct JollaApps {
    pub session: zbus::Connection,
}

#[async_trait]
impl StockApps for JollaApps {
    async fn compose_email(
        &self,
        to: &str,
        subject: &str,
        body: &str,
    ) -> Result<bool, AdapterError> {
        let accounts = std::env::var_os("HOME").map(|h| {
            PathBuf::from(h)
                .join(".local/share/system/privileged/Accounts/libaccounts-glib/accounts.db")
        });
        let ready = accounts.is_some_and(|p| email_account(&p));
        self.session
            .call_method(
                Some("com.jolla.email.ui"),
                "/com/jolla/email/ui",
                Some("com.jolla.email.ui"),
                "compose",
                &(subject, to, "", "", body),
            )
            .await?;
        Ok(ready)
    }

    async fn new_note(&self, text: &str) -> Result<(), AdapterError> {
        // Notes is sandboxed with the person's own folders (UserDirs): the
        // note goes through Downloads, and is removed once imported.
        let dir = std::env::var_os("HOME")
            .map(|h| PathBuf::from(h).join("Downloads"))
            .ok_or_else(|| AdapterError::Failed("no home folder".into()))?;
        let path = dir.join(format!(
            ".pilot-note-{}.vnt",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map_or(0, |d| d.as_millis())
        ));
        std::fs::write(&path, vnote(text))
            .map_err(|e| AdapterError::Failed(format!("writing the note: {e}")))?;
        let result = self
            .session
            .call_method(
                Some("com.jolla.notes"),
                "/",
                Some("com.jolla.notes"),
                "importNoteFile",
                &(vec![format!("file://{}", path.to_string_lossy())],),
            )
            .await;
        // Notes reads it when the call arrives (starting first if need be).
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_secs(30)).await;
            std::fs::remove_file(&path).ok();
        });
        result?;
        Ok(())
    }

    async fn compose_sms(&self, number: &str, body: &str) -> Result<(), AdapterError> {
        let owned = |s: &zbus::Connection| {
            let s = s.clone();
            async move {
                s.call_method(
                    Some("org.freedesktop.DBus"),
                    "/org/freedesktop/DBus",
                    Some("org.freedesktop.DBus"),
                    "NameHasOwner",
                    &("org.sailfishos.Messages",),
                )
                .await
                .ok()
                .and_then(|r| r.body().deserialize::<bool>().ok())
                .unwrap_or(false)
            }
        };
        if !owned(&self.session).await {
            // Messages' service file cannot start it; its sms: link can.
            let link = format!("sms:{}", number.replace(' ', ""));
            let mut child =
                crate::privilege::unprivileged(&mut std::process::Command::new("xdg-open"))
                    .arg(&link)
                    .spawn()
                    .map_err(|e| AdapterError::Failed(format!("starting Messages: {e}")))?;
            std::thread::spawn(move || child.wait());
            let mut up = false;
            for _ in 0..30 {
                tokio::time::sleep(Duration::from_millis(250)).await;
                if owned(&self.session).await {
                    up = true;
                    break;
                }
            }
            if !up {
                return Err(AdapterError::Failed("Messages did not start".into()));
            }
        }
        self.session
            .call_method(
                Some("org.sailfishos.Messages"),
                "/",
                Some("org.sailfishos.Messages"),
                "startSMS",
                &(vec![number], body),
            )
            .await?;
        Ok(())
    }

    async fn open_settings(&self, path: &str) -> Result<(), AdapterError> {
        self.session
            .call_method(
                Some("com.jolla.settings"),
                "/com/jolla/settings/ui",
                Some("com.jolla.settings.ui"),
                "showPage",
                &(path,),
            )
            .await?;
        Ok(())
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn a_note_keeps_its_lines_as_notes_reads_them() {
        let v = vnote("Shopping:\nmilk = 2 litres\nbread — fresh\n\n");
        assert_eq!(
            v,
            "BEGIN:VNOTE\r\nVERSION:1.1\r\nBODY;CHARSET=UTF-8;ENCODING=8BIT:Shopping:\rmilk = 2 litres\rbread — fresh\r\nEND:VNOTE\r\n"
        );
    }

    #[test]
    fn email_needs_an_enabled_account_with_e_mail() {
        let dir = tempfile::tempdir().unwrap();
        let db = dir.path().join("accounts.db");
        let c = rusqlite::Connection::open(&db).unwrap();
        c.execute_batch(
            "CREATE TABLE Accounts (id INTEGER, provider TEXT, enabled INTEGER);
             CREATE TABLE Services (id INTEGER, name TEXT, display TEXT, provider TEXT, type TEXT);
             INSERT INTO Accounts VALUES (1, 'jolla', 1);
             INSERT INTO Services VALUES (5, 'google-gmail', 'GMail', 'google', 'e-mail');",
        )
        .unwrap();
        assert!(!email_account(&db));
        c.execute("INSERT INTO Accounts VALUES (2, 'google', 1)", [])
            .unwrap();
        assert!(email_account(&db));
        assert!(!email_account(&dir.path().join("missing.db")));
    }

    #[test]
    fn settings_pages_are_known_paths() {
        assert_eq!(
            settings_path("bluetooth"),
            Some("system_settings/connectivity/bluetooth")
        );
        assert_eq!(settings_path("nonsense"), None);
    }
}
