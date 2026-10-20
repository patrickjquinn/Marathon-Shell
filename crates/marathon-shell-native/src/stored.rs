//! What the shell's Rust half keeps between runs, as JSON files in
//! `$XDG_STATE_HOME/marathon`, and what the C++ shell kept in `QSettings`.

use std::path::{Path, PathBuf};

use serde::de::DeserializeOwned;
use serde::Serialize;

use crate::log;

fn path(name: &str) -> PathBuf {
    marathon_rt::dirs::state().join("marathon").join(name)
}

pub fn load<T: DeserializeOwned>(name: &str) -> Option<T> {
    serde_json::from_str(&std::fs::read_to_string(path(name)).ok()?).ok()
}

/// Replaces the file whole, so a crash leaves the old one.
pub fn save<T: Serialize>(name: &str, value: &T) {
    let path = path(name);
    let written = path.parent().map_or(Ok(()), std::fs::create_dir_all).and_then(|()| {
        let tmp = path.with_extension("tmp");
        std::fs::write(&tmp, serde_json::to_vec(value).unwrap_or_default())?;
        std::fs::rename(tmp, &path)
    });
    if let Err(e) = written {
        log::warn("stored", format_args!("saving {}: {e}", path.display()));
    }
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
