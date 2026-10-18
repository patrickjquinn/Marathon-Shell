//! The JSON files in `$XDG_RUNTIME_DIR/marathon-store-state` that the Store
//! app reads. Every write is atomic (write, then rename).

use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::{json, Value};

pub struct StateDir(PathBuf);

/// One app's operation, as `install-progress-<appId>.json`.
pub struct Progress<'a> {
    pub app_id: &'a str,
    pub verb: &'a str,
    pub state: &'a str,
    pub percent: i32,
    pub error: &'a str,
}

pub fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs())
}

impl StateDir {
    pub fn open(runtime_dir: &Path) -> io::Result<Self> {
        let dir = runtime_dir.join("marathon-store-state");
        fs::create_dir_all(&dir)?;
        Ok(StateDir(dir))
    }

    #[cfg(test)]
    pub fn path(&self) -> &Path {
        &self.0
    }

    fn progress_path(&self, app_id: &str) -> PathBuf {
        self.0.join(format!("install-progress-{app_id}.json"))
    }

    pub fn write_json(&self, name: &str, value: &Value) -> io::Result<()> {
        let mut tmp = tempfile::Builder::new()
            .prefix(&format!("{name}."))
            .tempfile_in(&self.0)?;
        writeln!(tmp, "{value}")?;
        tmp.persist(self.0.join(name)).map_err(|e| e.error)?;
        Ok(())
    }

    pub fn write_progress(&self, p: &Progress) -> io::Result<()> {
        let record = json!({
            "appId": p.app_id,
            "verb": p.verb,
            "state": p.state,
            "percent": p.percent,
            "error": crate::progress::sanitize(p.error),
            "ts": now(),
        });
        self.write_json(&format!("install-progress-{}.json", p.app_id), &record)
    }

    pub fn read_progress(&self, app_id: &str) -> Option<Value> {
        let text = fs::read_to_string(self.progress_path(app_id)).ok()?;
        serde_json::from_str(&text).ok()
    }

    /// The app's name as installed.json last listed it.
    pub fn installed_name(&self, app_id: &str) -> Option<String> {
        let text = fs::read_to_string(self.0.join("installed.json")).ok()?;
        let listing: Value = serde_json::from_str(&text).ok()?;
        listing
            .get("installed")?
            .as_array()?
            .iter()
            .find(|app| app.get("app_id").and_then(Value::as_str) == Some(app_id))?
            .get("name")?
            .as_str()
            .filter(|name| !name.is_empty())
            .map(str::to_owned)
    }

    pub fn progress_state(&self, app_id: &str) -> Option<String> {
        self.read_progress(app_id)?
            .get("state")?
            .as_str()
            .map(str::to_owned)
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn progress_round_trips_with_the_store_app_keys() {
        let tmp = tempfile::tempdir().unwrap();
        let state = StateDir::open(tmp.path()).unwrap();
        state
            .write_progress(&Progress {
                app_id: "org.x.Y",
                verb: "install",
                state: "failed",
                percent: -1,
                error: "No \"remote\"\nrefs",
            })
            .unwrap();
        let record = state.read_progress("org.x.Y").unwrap();
        assert_eq!(record["appId"], "org.x.Y");
        assert_eq!(record["verb"], "install");
        assert_eq!(record["state"], "failed");
        assert_eq!(record["percent"], -1);
        assert_eq!(record["error"], "No \"remote\" refs");
        assert!(record["ts"].as_u64().unwrap() > 0);
        assert_eq!(state.progress_state("org.x.Y").as_deref(), Some("failed"));
        assert_eq!(state.progress_state("org.missing.App"), None);
    }

    #[test]
    fn names_an_installed_app() {
        let tmp = tempfile::tempdir().unwrap();
        let state = StateDir::open(tmp.path()).unwrap();
        assert_eq!(state.installed_name("org.x.Y"), None);
        state
            .write_json(
                "installed.json",
                &json!({"installed": [{"app_id": "org.x.Y", "name": "Why"}, {"app_id": "org.a.B", "name": ""}]}),
            )
            .unwrap();
        assert_eq!(state.installed_name("org.x.Y").as_deref(), Some("Why"));
        assert_eq!(state.installed_name("org.a.B"), None);
        assert_eq!(state.installed_name("org.c.D"), None);
    }

    #[test]
    fn writes_leave_no_temporary_files() {
        let tmp = tempfile::tempdir().unwrap();
        let state = StateDir::open(tmp.path()).unwrap();
        state
            .write_json("installed.json", &json!({"installed": []}))
            .unwrap();
        state
            .write_json("installed.json", &json!({"installed": []}))
            .unwrap();
        let names: Vec<_> = fs::read_dir(state.path())
            .unwrap()
            .map(|e| e.unwrap().file_name())
            .collect();
        assert_eq!(names, ["installed.json"]);
    }
}
