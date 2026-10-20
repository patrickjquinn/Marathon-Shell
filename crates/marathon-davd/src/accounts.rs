//! DAV accounts: `dav-accounts.json` beside the address book, the secrets
//! in the keyring. Accounts the shell kept in its settings file move here
//! on first start, their plaintext secrets to the keyring.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use zbus::zvariant::Value;

#[derive(Serialize, Deserialize, Clone, Default, Debug, PartialEq)]
#[serde(rename_all = "camelCase", default)]
pub struct Account {
    pub id: String,
    pub display_name: String,
    pub base_url: String,
    pub username: String,
    pub auth_kind: String,
    pub home_url_contacts: String,
    pub home_url_calendar: String,
    pub collections_contacts: Vec<String>,
    pub collections_calendar: Vec<String>,
    pub enabled: bool,
    /// A secret from before the keyring, kept until the keyring takes it.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub secret: Option<String>,
}

impl Account {
    pub fn row(&self) -> HashMap<&'static str, Value<'static>> {
        HashMap::from([
            ("id", Value::from(self.id.clone())),
            ("displayName", Value::from(self.display_name.clone())),
            ("baseUrl", Value::from(self.base_url.clone())),
            ("username", Value::from(self.username.clone())),
            ("authKind", Value::from(self.auth_kind.clone())),
            ("homeUrlContacts", Value::from(self.home_url_contacts.clone())),
            ("homeUrlCalendar", Value::from(self.home_url_calendar.clone())),
            ("collectionsContacts", Value::from(self.collections_contacts.clone())),
            ("collectionsCalendar", Value::from(self.collections_calendar.clone())),
            ("enabled", Value::from(self.enabled)),
        ])
    }
}

#[derive(Serialize, Deserialize, Default, Debug, PartialEq)]
#[serde(rename_all = "camelCase", default)]
pub struct Saved {
    pub accounts: Vec<Account>,
    /// Accounts removed while the keyring could not delete their secret.
    pub pending_secret_removals: Vec<String>,
}

/// What the keyring still has to do.
pub enum SecretOp {
    Store { id: String, label: String, secret: String },
    Load(String),
    Remove(String),
}

pub struct Accounts {
    file: PathBuf,
    pub saved: Saved,
    /// Secrets in memory, by account.
    pub secrets: HashMap<String, String>,
    /// Accounts whose keyring secret is not read yet: they neither sync nor
    /// are discovered.
    pub waiting: HashSet<String>,
    /// New secrets the keyring has not taken yet; never written to disk.
    pub unstored: HashMap<String, String>,
}

impl Accounts {
    pub fn open(file: PathBuf, shell_settings: &Path) -> Self {
        let saved = fs::read_to_string(&file)
            .ok()
            .and_then(|text| serde_json::from_str(&text).ok())
            .unwrap_or_else(|| fs::read_to_string(shell_settings).map(|ini| from_shell_settings(&ini)).unwrap_or_default());
        let mut accounts = Self { file, saved, secrets: HashMap::new(), waiting: HashSet::new(), unstored: HashMap::new() };
        for a in &accounts.saved.accounts {
            match &a.secret {
                Some(secret) => {
                    accounts.secrets.insert(a.id.clone(), secret.clone());
                    accounts.unstored.insert(a.id.clone(), secret.clone());
                }
                None => {
                    accounts.waiting.insert(a.id.clone());
                }
            }
        }
        accounts.save();
        accounts
    }

    pub fn save(&self) {
        let written = serde_json::to_string_pretty(&self.saved).map_err(std::io::Error::other).and_then(|json| {
            if let Some(dir) = self.file.parent() {
                fs::create_dir_all(dir)?;
            }
            fs::write(&self.file, json)
        });
        if let Err(e) = written {
            marathon_rt::log::warn("Dav", format_args!("cannot save {}: {e}", self.file.display()));
        }
    }

    pub fn get(&self, id: &str) -> Option<&Account> {
        self.saved.accounts.iter().find(|a| a.id == id)
    }

    pub fn get_mut(&mut self, id: &str) -> Option<&mut Account> {
        self.saved.accounts.iter_mut().find(|a| a.id == id)
    }

    /// An account that can be reached now, with its secret.
    pub fn ready(&self, id: &str) -> Option<(Account, String)> {
        let account = self.get(id).filter(|a| a.enabled && !self.waiting.contains(id))?;
        Some((account.clone(), self.secrets.get(id).cloned().unwrap_or_default()))
    }

    pub fn add(&mut self, account: Account, secret: String) {
        self.secrets.insert(account.id.clone(), secret.clone());
        self.unstored.insert(account.id.clone(), secret);
        self.saved.accounts.push(account);
        self.save();
    }

    pub fn remove(&mut self, id: &str) -> bool {
        let before = self.saved.accounts.len();
        self.saved.accounts.retain(|a| a.id != id);
        if self.saved.accounts.len() == before {
            return false;
        }
        for map in [&mut self.secrets, &mut self.unstored] {
            map.remove(id);
        }
        self.waiting.remove(id);
        self.saved.pending_secret_removals.push(id.to_owned());
        self.save();
        true
    }

    pub fn secret_work(&self) -> Vec<SecretOp> {
        let label = |id: &str| self.get(id).map_or(id, |a| if a.display_name.is_empty() { id } else { &a.display_name }).to_owned();
        let stores = self.unstored.iter().map(|(id, secret)| SecretOp::Store { id: id.clone(), label: format!("Marathon DAV · {}", label(id)), secret: secret.clone() });
        let loads = self.waiting.iter().cloned().map(SecretOp::Load);
        let removals = self.saved.pending_secret_removals.iter().cloned().map(SecretOp::Remove);
        stores.chain(loads).chain(removals).collect()
    }

    pub fn stored(&mut self, id: &str, secret: &str) {
        if self.unstored.get(id).is_some_and(|s| s == secret) {
            self.unstored.remove(id);
        }
        if let Some(a) = self.get_mut(id) {
            a.secret = None;
        }
        self.save();
    }

    pub fn loaded(&mut self, id: &str, secret: Option<String>) {
        if self.waiting.remove(id) {
            match secret {
                Some(secret) => {
                    self.secrets.insert(id.to_owned(), secret);
                }
                None => marathon_rt::log::warn("Dav", format_args!("no keyring secret for account {id}")),
            }
        }
    }

    pub fn removed(&mut self, id: &str) {
        self.saved.pending_secret_removals.retain(|r| r != id);
        self.save();
    }
}

/// `QSettings`' INI value: quoted or not, a list as `a, b`.
fn ini_values(raw: &str) -> Vec<String> {
    let mut values = vec![String::new()];
    let (mut quoted, mut escaped) = (false, false);
    for c in raw.trim().chars() {
        match (escaped, c) {
            (true, _) => {
                escaped = false;
                values.last_mut().into_iter().for_each(|v| v.push(c));
            }
            (false, '\\') => escaped = true,
            (false, '"') => quoted = !quoted,
            (false, ',') if !quoted => values.push(String::new()),
            (false, _) => values.last_mut().into_iter().for_each(|v| v.push(c)),
        }
    }
    values.into_iter().map(|v| v.trim().to_owned()).filter(|v| !v.is_empty()).collect()
}

/// The `[dav]` group of the shell's `QSettings` file.
fn from_shell_settings(ini: &str) -> Saved {
    let mut saved = Saved::default();
    let mut in_dav = false;
    for line in ini.lines() {
        if let Some(section) = line.strip_prefix('[') {
            in_dav = section.trim_end_matches(']') == "dav";
            continue;
        }
        let Some((key, raw)) = line.split_once('=').filter(|_| in_dav) else { continue };
        if key.trim() == "pendingSecretRemovals" {
            saved.pending_secret_removals = ini_values(raw);
            continue;
        }
        let Some((id, field)) = key.trim().strip_prefix("accounts\\").and_then(|rest| rest.split_once('\\')) else { continue };
        if !saved.accounts.iter().any(|a| a.id == id) {
            saved.accounts.push(Account { id: id.to_owned(), auth_kind: "basic".into(), enabled: true, ..Account::default() });
        }
        let Some(a) = saved.accounts.iter_mut().find(|a| a.id == id) else { continue };
        let mut values = ini_values(raw);
        let one = values.first().cloned().unwrap_or_default();
        match field {
            "displayName" => a.display_name = one,
            "baseUrl" => a.base_url = one,
            "username" => a.username = one,
            "authKind" => a.auth_kind = one,
            "homeUrlContacts" => a.home_url_contacts = one,
            "homeUrlCalendar" => a.home_url_calendar = one,
            "collectionsContacts" => a.collections_contacts = std::mem::take(&mut values),
            "collectionsCalendar" => a.collections_calendar = std::mem::take(&mut values),
            "enabled" => a.enabled = one != "false",
            "secret" => a.secret = Some(one).filter(|s| !s.is_empty()),
            _ => {}
        }
    }
    saved
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn the_shells_accounts_move_over() {
        let ini = "[General]\nfoo=1\n\n[dav]\naccounts\\a1\\displayName=Fastmail\naccounts\\a1\\baseUrl=https://carddav.fastmail.com/\naccounts\\a1\\secret=\"p,ss\\\"word\"\naccounts\\a1\\collectionsContacts=https://x/1/, https://x/2/\naccounts\\a1\\enabled=true\npendingSecretRemovals=old\n";
        let dir = tempfile::tempdir().unwrap();
        let shell = dir.path().join("Marathon Shell.conf");
        fs::write(&shell, ini).unwrap();
        let accounts = Accounts::open(dir.path().join("dav-accounts.json"), &shell);
        let a = accounts.get("a1").unwrap();
        assert_eq!((a.display_name.as_str(), a.auth_kind.as_str(), a.enabled), ("Fastmail", "basic", true));
        assert_eq!(a.collections_contacts, ["https://x/1/", "https://x/2/"]);
        assert_eq!(accounts.unstored.get("a1").map(String::as_str), Some("p,ss\"word"));
        assert_eq!(accounts.saved.pending_secret_removals, ["old"]);
    }

    // A plaintext secret stays on disk until the keyring takes it; a new
    // account's never reaches the disk.
    #[test]
    fn secrets_reach_the_disk_only_from_before_the_keyring() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("dav-accounts.json");
        let mut accounts = Accounts::open(file.clone(), &dir.path().join("none.conf"));
        accounts.add(Account { id: "n".into(), enabled: true, ..Account::default() }, "fresh".into());
        assert!(!fs::read_to_string(&file).unwrap().contains("fresh"));
        accounts.get_mut("n").unwrap().secret = Some("old".into());
        accounts.save();
        let mut accounts = Accounts::open(file.clone(), &dir.path().join("none.conf"));
        assert!(accounts.ready("n").is_some());
        accounts.stored("n", "old");
        assert!(!fs::read_to_string(&file).unwrap().contains("old"));
        assert!(accounts.remove("n"));
        let accounts = Accounts::open(file, &dir.path().join("none.conf"));
        assert!(matches!(accounts.secret_work().as_slice(), [SecretOp::Remove(id)] if id == "n"));
    }

    #[test]
    fn an_account_waits_for_its_keyring_secret() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("dav-accounts.json");
        fs::write(&file, r#"{"accounts":[{"id":"k","enabled":true}]}"#).unwrap();
        let mut accounts = Accounts::open(file, &dir.path().join("none.conf"));
        assert!(accounts.ready("k").is_none());
        accounts.loaded("k", Some("s".into()));
        assert_eq!(accounts.ready("k").map(|(_, s)| s), Some("s".to_owned()));
    }
}
