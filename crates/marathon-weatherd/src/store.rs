//! What survives a restart: the pinned location in
//! `$XDG_CONFIG_HOME/marathon-weather/location.json`, and under
//! `$XDG_CACHE_HOME/marathon-weather/` the last `GeoClue` fix plus the raw MET
//! response with its HTTP cache metadata. Every write is atomic.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Location {
    pub name: String,
    pub region: String,
    pub latitude: f64,
    pub longitude: f64,
}

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct Settings {
    /// `None` follows `GeoClue`.
    pub manual: Option<Location>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct CacheMeta {
    pub latitude: f64,
    pub longitude: f64,
    /// The `Last-Modified` header, echoed verbatim as `If-Modified-Since`.
    pub last_modified: Option<String>,
    /// Unix time from the `Expires` header.
    pub expires: i64,
}

pub struct Store {
    config: PathBuf,
    cache: PathBuf,
}


fn read<T: DeserializeOwned>(path: &Path) -> Option<T> {
    serde_json::from_slice(&fs::read(path).ok()?).ok()
}

fn write(path: &Path, bytes: &[u8]) -> io::Result<()> {
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir)?;
    }
    let tmp = path.with_extension("tmp");
    fs::write(&tmp, bytes)?;
    fs::rename(tmp, path)
}

fn write_json<T: Serialize>(path: &Path, value: &T) -> io::Result<()> {
    write(path, &serde_json::to_vec(value).map_err(io::Error::other)?)
}

impl Store {
    pub fn from_env() -> Self {
        Store {
            config: marathon_rt::dirs::config().join("marathon-weather"),
            cache: marathon_rt::dirs::cache().join("marathon-weather"),
        }
    }

    #[cfg(test)]
    pub fn at(dir: &Path) -> Self {
        Store {
            config: dir.join("config"),
            cache: dir.join("cache"),
        }
    }

    pub fn settings(&self) -> Settings {
        read(&self.config.join("location.json")).unwrap_or_default()
    }

    pub fn save_settings(&self, settings: &Settings) -> io::Result<()> {
        write_json(&self.config.join("location.json"), settings)
    }

    pub fn last_fix(&self) -> Option<Location> {
        read(&self.cache.join("last-location.json"))
    }

    pub fn save_last_fix(&self, location: &Location) -> io::Result<()> {
        write_json(&self.cache.join("last-location.json"), location)
    }

    /// The raw MET body and its cache metadata, if both are readable.
    pub fn forecast(&self) -> Option<(serde_json::Value, CacheMeta)> {
        Some((
            read(&self.cache.join("met.json"))?,
            read(&self.cache.join("met-meta.json"))?,
        ))
    }

    pub fn save_forecast(&self, body: &str, meta: &CacheMeta) -> io::Result<()> {
        write(&self.cache.join("met.json"), body.as_bytes())?;
        self.save_meta(meta)
    }

    pub fn save_meta(&self, meta: &CacheMeta) -> io::Result<()> {
        write_json(&self.cache.join("met-meta.json"), meta)
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn round_trips_settings_and_forecast() {
        let tmp = std::env::temp_dir().join(format!("weatherd-store-{}", std::process::id()));
        let store = Store::at(&tmp);
        assert!(store.settings().manual.is_none());
        assert!(store.forecast().is_none());

        let dublin = Location {
            name: "Dublin".into(),
            region: "Ireland".into(),
            latitude: 53.3498,
            longitude: -6.2603,
        };
        store
            .save_settings(&Settings {
                manual: Some(dublin.clone()),
            })
            .unwrap();
        assert_eq!(store.settings().manual, Some(dublin));

        let meta = CacheMeta {
            latitude: 53.3498,
            longitude: -6.2603,
            last_modified: Some("Fri, 16 Oct 2026 22:03:14 GMT".into()),
            expires: 1_792_189_000,
        };
        store.save_forecast("{\"a\":1}", &meta).unwrap();
        let (body, read_meta) = store.forecast().unwrap();
        assert_eq!(body["a"], 1);
        assert_eq!(read_meta, meta);
        fs::remove_dir_all(tmp).unwrap();
    }
}
