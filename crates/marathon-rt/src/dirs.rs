//! The XDG base directories, with their fallbacks under `$HOME`.

use std::path::PathBuf;

pub fn home() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_default()
}

fn base(var: &str, fallback: &str) -> PathBuf {
    std::env::var_os(var).filter(|v| !v.is_empty()).map_or_else(|| home().join(fallback), PathBuf::from)
}

pub fn config() -> PathBuf {
    base("XDG_CONFIG_HOME", ".config")
}

pub fn data() -> PathBuf {
    base("XDG_DATA_HOME", ".local/share")
}

pub fn cache() -> PathBuf {
    base("XDG_CACHE_HOME", ".cache")
}

pub fn state() -> PathBuf {
    base("XDG_STATE_HOME", ".local/state")
}
