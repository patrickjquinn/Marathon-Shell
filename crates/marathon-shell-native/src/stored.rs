//! What the shell's Rust half keeps between runs, as JSON files in
//! `$XDG_STATE_HOME/marathon`, and what the C++ shell kept in `QSettings`.

use std::fmt;
use std::io::Write;
use std::path::{Path, PathBuf};

use serde::de::DeserializeOwned;
use serde::Serialize;

fn path(name: &str) -> PathBuf {
    marathon_rt::dirs::state().join("marathon").join(name)
}

#[derive(Debug)]
pub enum SaveError {
    Serialize(serde_json::Error),
    Io(std::io::Error),
}

impl fmt::Display for SaveError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Serialize(error) => write!(f, "cannot serialize state: {error}"),
            Self::Io(error) => write!(f, "cannot write state: {error}"),
        }
    }
}

impl std::error::Error for SaveError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Serialize(error) => Some(error),
            Self::Io(error) => Some(error),
        }
    }
}

pub fn load<T: DeserializeOwned>(name: &str) -> Option<T> {
    serde_json::from_str(&std::fs::read_to_string(path(name)).ok()?).ok()
}

/// Replaces the file whole, so a crash leaves the old one.
pub fn save<T: Serialize>(name: &str, value: &T) -> Result<(), SaveError> {
    save_to(&path(name), value)
}

fn save_to<T: Serialize>(path: &Path, value: &T) -> Result<(), SaveError> {
    let encoded = serde_json::to_vec(value).map_err(SaveError::Serialize)?;
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(SaveError::Io)?;
    }

    let temporary = path.with_extension("tmp");
    let write = || -> std::io::Result<()> {
        let mut file = std::fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .open(&temporary)?;
        file.write_all(&encoded)?;
        file.sync_all()?;
        drop(file);
        std::fs::rename(&temporary, path)
    };
    if let Err(error) = write() {
        std::fs::remove_file(temporary).ok();
        return Err(SaveError::Io(error));
    }
    Ok(())
}

/// The `key=value` lines of a `QSettings` INI file's `[group]`.
pub fn qsettings(path: &Path, group: &str) -> Vec<(String, String)> {
    let header = format!("[{group}]");
    let text = std::fs::read_to_string(path).unwrap_or_default();
    text.lines()
        .skip_while(|l| l.trim() != header)
        .skip(1)
        .take_while(|l| !l.starts_with('['))
        .filter_map(|l| l.split_once('='))
        .map(|(k, v)| (k.trim().to_owned(), v.trim().trim_matches('"').to_owned()))
        .collect()
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    struct CannotSerialize;

    impl Serialize for CannotSerialize {
        fn serialize<S>(&self, _serializer: S) -> Result<S::Ok, S::Error>
        where
            S: serde::Serializer,
        {
            Err(serde::ser::Error::custom("intentional failure"))
        }
    }

    #[test]
    fn serialization_failure_preserves_existing_state() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("state.json");
        std::fs::write(&path, br#"{"valid":true}"#).unwrap();

        assert!(matches!(
            save_to(&path, &CannotSerialize),
            Err(SaveError::Serialize(_))
        ));
        assert_eq!(std::fs::read(path).unwrap(), br#"{"valid":true}"#);
    }

    #[test]
    fn temporary_write_failure_preserves_existing_state() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("state.json");
        std::fs::write(&path, br#"{"valid":true}"#).unwrap();
        std::fs::create_dir(path.with_extension("tmp")).unwrap();

        assert!(matches!(
            save_to(&path, &serde_json::json!({ "valid": false })),
            Err(SaveError::Io(_))
        ));
        assert_eq!(std::fs::read(path).unwrap(), br#"{"valid":true}"#);
    }
}
