// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! The live catalogue: every app's manifest, from the installed
//! `actions.json` files (`/usr/share/keel/actions/*.json`) and from running
//! apps that answer `Describe`. An installed manifest wins, so a running
//! app cannot change its contract.
//!
//! MCP names: a manifest names tools and prompts `<app-id>/<name>`
//! (`docs/specs/pilot.md` 9.3). MCP tool names are `[A-Za-z0-9_.-]{1,128}`
//! (the 2025-11-25 tool-name rule), so keel-mcp exposes them with `__` for
//! the `/` (`org.example.notes__notes.create`) and keeps the manifest name
//! in `_meta["org.shipwright.keel/name"]`. Both forms are accepted in calls
//! and plans.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use keel_actions_schema::{is_app_id, meta_key};
use serde_json::Value;

/// `<app-id>/<name>` as an MCP name.
pub fn exposed(canonical: &str) -> String {
    canonical.replacen('/', "__", 1)
}

/// An MCP name (or a manifest name) as the manifest name.
pub fn canonical(name: &str) -> String {
    if name.contains('/') {
        name.to_owned()
    } else {
        name.replacen("__", "/", 1)
    }
}

/// One tool of one app.
#[derive(Clone, Debug)]
pub struct ToolEntry {
    pub app: String,
    /// The manifest's tool.
    pub tool: Value,
}

impl ToolEntry {
    fn meta(&self, key: &str) -> Option<&Value> {
        self.tool.get("_meta").and_then(|m| m.get(meta_key(key)))
    }
    /// The action name ("notes.create"), or None for a find tool.
    pub fn action(&self) -> Option<&str> {
        self.meta("action").and_then(Value::as_str)
    }
    /// The entity type of a find tool.
    pub fn find_type(&self) -> Option<&str> {
        self.meta("find").and_then(Value::as_str)
    }
    /// The result carries content the app does not vouch for.
    pub fn untrusted(&self) -> bool {
        self.meta("untrusted")
            .and_then(Value::as_bool)
            .unwrap_or(false)
    }
    pub fn sensitive(&self) -> bool {
        self.meta("sensitive")
            .and_then(Value::as_bool)
            .unwrap_or(false)
    }
    pub fn timeout_ms(&self) -> u64 {
        self.meta("timeoutMs")
            .and_then(Value::as_u64)
            .unwrap_or(25_000)
    }
    pub fn name(&self) -> &str {
        self.tool["name"].as_str().unwrap_or_default()
    }
}

#[derive(Clone, Debug, Default)]
pub struct Catalogue {
    /// App ID -> manifest.
    pub apps: BTreeMap<String, Value>,
    /// Manifest name -> tool.
    pub tools: BTreeMap<String, ToolEntry>,
}

impl Catalogue {
    /// Builds the catalogue: `installed` first, then `running` for apps
    /// not installed.
    pub fn build(installed: Vec<Value>, running: Vec<Value>) -> Self {
        let mut c = Self::default();
        for manifest in installed.into_iter().chain(running) {
            let Some(app) = manifest
                .get("appId")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned)
            else {
                continue;
            };
            if !is_app_id(&app)
                || c.apps.contains_key(&app)
                || manifest.get("version").and_then(Value::as_u64) != Some(1)
            {
                continue;
            }
            for tool in manifest
                .get("tools")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
            {
                let Some(name) = tool.get("name").and_then(Value::as_str) else {
                    continue;
                };
                if !name.starts_with(&format!("{app}/")) {
                    continue;
                }
                c.tools.insert(
                    name.to_owned(),
                    ToolEntry {
                        app: app.clone(),
                        tool: tool.clone(),
                    },
                );
            }
            c.apps.insert(app, manifest);
        }
        c
    }

    pub fn tool(&self, name: &str) -> Option<&ToolEntry> {
        self.tools.get(&canonical(name))
    }

    pub fn entity(&self, app: &str, ty: &str) -> Option<&Value> {
        self.apps
            .get(app)?
            .get("entities")?
            .as_array()?
            .iter()
            .find(|e| e["type"].as_str() == Some(ty))
    }

    pub fn prompt(&self, name: &str) -> Option<(&str, &Value)> {
        let canonical = canonical(name);
        self.apps.iter().find_map(|(app, m)| {
            m.get("prompts")?
                .as_array()?
                .iter()
                .find(|p| p["name"].as_str() == Some(canonical.as_str()))
                .map(|p| (app.as_str(), p))
        })
    }
}

/// The JSON files in `dirs`, with their modification times (to notice
/// changes).
pub fn scan(dirs: &[PathBuf]) -> Vec<(PathBuf, SystemTime)> {
    let mut out = Vec::new();
    for dir in dirs {
        let Ok(entries) = std::fs::read_dir(dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().is_some_and(|e| e == "json") {
                let modified = entry
                    .metadata()
                    .and_then(|m| m.modified())
                    .unwrap_or(SystemTime::UNIX_EPOCH);
                out.push((path, modified));
            }
        }
    }
    out.sort();
    out
}

/// Reads the manifests in the scanned files; unreadable ones are skipped
/// with a message on stderr.
pub fn load(files: &[(PathBuf, SystemTime)]) -> Vec<Value> {
    files.iter().filter_map(|(path, _)| read(path)).collect()
}

fn read(path: &Path) -> Option<Value> {
    let text = std::fs::read_to_string(path).ok()?;
    match serde_json::from_str::<Value>(&text) {
        Ok(v) => Some(v),
        Err(e) => {
            eprintln!("keel-mcp: {}: {e}", path.display());
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn names_and_precedence() {
        assert_eq!(exposed("org.a.b/notes.create"), "org.a.b__notes.create");
        assert_eq!(canonical("org.a.b__notes.create"), "org.a.b/notes.create");
        assert_eq!(canonical("org.a.b/notes.create"), "org.a.b/notes.create");
        let m = |desc: &str| json!({ "version": 1, "appId": "org.a.b", "tools": [ { "name": "org.a.b/x.y", "description": desc } ] });
        let c = Catalogue::build(
            vec![m("installed")],
            vec![m("running"), json!({ "appId": "bad" })],
        );
        assert_eq!(c.apps.len(), 1);
        assert_eq!(
            c.tool("org.a.b__x.y").unwrap().tool["description"],
            "installed"
        );
    }
}
