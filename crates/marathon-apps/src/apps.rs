//! Marathon's apps as their manifests and install receipts describe them:
//! the OS's own under [`paths::system_apps`], the user's under
//! [`paths::user_installs`], each a directory with a `manifest.json`.

use std::fs;
use std::path::{Path, PathBuf};

use serde::Deserialize;

use crate::{paths, signature};

#[derive(Debug, Clone, PartialEq, Default, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct App {
    pub id: String,
    pub name: String,
    pub icon: String,
    pub entry_point: String,
    pub version: String,
    #[serde(rename = "protected")]
    pub is_protected: bool,
    pub permissions: Vec<String>,
    pub search_keywords: Vec<String>,
    pub deep_links: serde_json::Map<String, serde_json::Value>,
    pub categories: Vec<String>,
    pub handles_uri_schemes: Vec<String>,
    pub default_for: Vec<String>,
    pub background_capabilities: Vec<String>,
    pub requires_qt_modules: Vec<String>,
    pub toolkit: String,
    /// The app's directory.
    #[serde(skip)]
    pub path: PathBuf,
    /// Installed by the OS, or signed with a system key.
    #[serde(skip)]
    pub is_system: bool,
}

impl App {
    /// The manifest in `dir`, if it names what an app needs.
    pub fn read(dir: &Path) -> Option<Self> {
        let bytes = fs::read(dir.join("manifest.json")).ok()?;
        let mut app: Self = serde_json::from_slice(&bytes).ok()?;
        if app.id.is_empty() || app.name.is_empty() || app.entry_point.is_empty() {
            return None;
        }
        if app.version.is_empty() {
            "1.0.0".clone_into(&mut app.version);
        }
        if app.toolkit.is_empty() {
            "keel".clone_into(&mut app.toolkit);
        }
        if !app.icon.is_empty() && !app.icon.starts_with("qrc:") && !app.icon.starts_with("file://") {
            let icon = if app.icon.starts_with('/') { PathBuf::from(&app.icon) } else { dir.join(&app.icon) };
            app.icon = format!("file://{}", icon.display());
        }
        dir.clone_into(&mut app.path);
        Some(app)
    }

    pub fn deep_links_json(&self) -> String {
        serde_json::to_string(&self.deep_links).unwrap_or_default()
    }
}

#[derive(Deserialize, Default)]
#[serde(default)]
struct Receipt {
    id: String,
    signer: String,
    permissions: Vec<String>,
}

fn receipt(app_id: &str) -> Option<Receipt> {
    let receipt: Receipt = serde_json::from_slice(&fs::read(paths::receipt(app_id)).ok()?).ok()?;
    (receipt.id == app_id).then_some(receipt)
}

pub fn is_system_signer(key_id: &str) -> bool {
    let system = paths::system_keys();
    let trusted = paths::trusted_keys();
    let trusted: Vec<&Path> = trusted.iter().map(PathBuf::as_path).collect();
    !key_id.is_empty() && signature::is_trusted_key(key_id, &[system.as_path()], &trusted)
}

fn system(app_id: &str) -> Option<App> {
    let mut app = App::read(&paths::system_app(app_id))?;
    app.is_system = true;
    Some(app)
}

/// A user install counts only with the installer's receipt, whose
/// permissions are the ones the user approved: the manifest beside the code
/// is not trusted for them.
fn user(app_id: &str) -> Option<App> {
    let receipt = receipt(app_id)?;
    let mut app = App::read(&paths::files_dir(app_id)).filter(|a| a.id == app_id)?;
    app.permissions = receipt.permissions;
    app.is_system = is_system_signer(&receipt.signer);
    app.is_protected &= app.is_system;
    Some(app)
}

/// The app of `app_id`, the OS's before the user's.
pub fn find(app_id: &str) -> Option<App> {
    if app_id.is_empty() {
        return None;
    }
    if paths::system_app(app_id).join("manifest.json").exists() {
        system(app_id).filter(|a| a.id == app_id)
    } else {
        user(app_id)
    }
}

fn ids(dir: &Path) -> Vec<String> {
    let mut ids: Vec<String> = fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| e.path().is_dir())
        .filter_map(|e| e.file_name().into_string().ok())
        .collect();
    ids.sort();
    ids
}

/// Every app, the OS's first; a user install never shadows one of them.
pub fn scan() -> Vec<App> {
    let mut apps: Vec<App> = ids(&paths::system_apps()).iter().filter_map(|id| system(id)).collect();
    for app in ids(&paths::user_installs()).iter().filter_map(|id| user(id)) {
        if !apps.iter().any(|a| a.id == app.id) {
            apps.push(app);
        }
    }
    apps
}
