// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The speech recognition models pilot-voice downloads on first use
//! (shoal/pilot/voice/src/models.rs): 78 to 148 MB each, in
//! `$XDG_DATA_HOME/shoal-pilot/models`. No package owns them, so removing
//! Pilot leaves them; Settings shows their size and removes them
//! (`VoiceModels`, `RemoveVoiceModels`). pilot-voice fetches one again the
//! next time the microphone is used.

use std::path::{Path, PathBuf};

/// Where pilot-voice keeps them: the same rule as its `models_dir`.
pub fn dir() -> Option<PathBuf> {
    dir_from(
        std::env::var_os("PILOT_VOICE_MODELS"),
        std::env::var_os("XDG_DATA_HOME"),
        std::env::var_os("HOME"),
    )
}

fn dir_from(
    explicit: Option<std::ffi::OsString>,
    data_home: Option<std::ffi::OsString>,
    home: Option<std::ffi::OsString>,
) -> Option<PathBuf> {
    if let Some(d) = explicit.filter(|v| !v.is_empty()) {
        return Some(PathBuf::from(d));
    }
    data_home
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .or_else(|| home.map(|h| PathBuf::from(h).join(".local/share")))
        .map(|d| d.join("shoal-pilot/models"))
}

/// Bytes of the files under `dir` (partial downloads included); 0 when it
/// does not exist. Symbolic links are not followed.
pub fn bytes(dir: &Path) -> u64 {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return 0;
    };
    entries
        .flatten()
        .map(|e| match e.file_type() {
            Ok(t) if t.is_dir() => bytes(&e.path()),
            Ok(t) if t.is_file() => e.metadata().map_or(0, |m| m.len()),
            _ => 0,
        })
        .sum()
}

/// Deletes `dir` and everything in it; the bytes freed (0 if there was
/// nothing).
pub fn remove(dir: &Path) -> std::io::Result<u64> {
    let freed = bytes(dir);
    match std::fs::remove_dir_all(dir) {
        Ok(()) => Ok(freed),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(0),
        Err(e) => Err(e),
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn same_place_as_pilot_voice() {
        assert_eq!(
            dir_from(Some("/m".into()), Some("/d".into()), Some("/h".into())),
            Some(PathBuf::from("/m"))
        );
        assert_eq!(
            dir_from(Some("".into()), Some("/d".into()), Some("/h".into())),
            Some(PathBuf::from("/d/shoal-pilot/models"))
        );
        assert_eq!(
            dir_from(None, Some("".into()), Some("/h".into())),
            Some(PathBuf::from("/h/.local/share/shoal-pilot/models"))
        );
        assert_eq!(dir_from(None, None, None), None);
    }

    #[test]
    fn measures_and_removes() {
        let base = std::env::temp_dir().join(format!("pilotd-voice-models-{}", std::process::id()));
        let dir = base.join("shoal-pilot/models");
        std::fs::create_dir_all(dir.join("sub")).unwrap();
        std::fs::write(dir.join("ggml-tiny.bin"), vec![0u8; 1000]).unwrap();
        std::fs::write(dir.join("ggml-base.bin.part"), vec![0u8; 24]).unwrap();
        std::fs::write(dir.join("sub/x"), vec![0u8; 6]).unwrap();
        assert_eq!(bytes(&dir), 1030);
        assert_eq!(remove(&dir).unwrap(), 1030);
        assert!(!dir.exists());
        assert!(base.join("shoal-pilot").exists(), "only the models go");
        assert_eq!(bytes(&dir), 0);
        assert_eq!(remove(&dir).unwrap(), 0);
        std::fs::remove_dir_all(base).ok();
    }
}
