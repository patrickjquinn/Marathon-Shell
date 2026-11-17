//! The person's stations: favourites and the recently played, kept as
//! the station's own record so they show without the catalogue.

use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::catalogue::Station;

const RECENTS: usize = 20;

#[derive(Default, Serialize, Deserialize)]
pub struct Library {
    #[serde(default)]
    pub favourites: Vec<Station>,
    #[serde(default)]
    pub recents: Vec<Station>,
    /// The last station played, for Play with nothing chosen.
    #[serde(default)]
    pub last: Option<Station>,
}

fn path() -> PathBuf {
    marathon_rt::dirs::data().join("marathon/radio/library.json")
}

impl Library {
    pub fn load() -> Self {
        std::fs::read(path())
            .ok()
            .and_then(|b| serde_json::from_slice(&b).ok())
            .unwrap_or_default()
    }

    fn save(&self) {
        let path = path();
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir).ok();
        }
        if let Ok(json) = serde_json::to_vec(self) {
            let tmp = path.with_extension("part");
            if std::fs::write(&tmp, json).is_ok() {
                std::fs::rename(tmp, path).ok();
            }
        }
    }

    pub fn is_favourite(&self, id: &str) -> bool {
        self.favourites.iter().any(|s| s.id == id)
    }

    pub fn set_favourite(&mut self, station: &Station, on: bool) {
        self.favourites.retain(|s| s.id != station.id);
        if on {
            self.favourites.push(station.clone());
        }
        self.save();
    }

    pub fn played(&mut self, station: &Station) {
        self.recents.retain(|s| s.id != station.id);
        self.recents.insert(0, station.clone());
        self.recents.truncate(RECENTS);
        self.last = Some(station.clone());
        self.save();
    }
}
