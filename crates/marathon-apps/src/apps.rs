//! Marathon's apps as their manifests and install receipts describe them:
//! the OS's own under [`paths::system_apps`], the user's under
//! [`paths::user_installs`], each a directory with a `manifest.json`. Reef
//! updates some of the OS's apps by installing a newer copy, signed with a
//! system key, among the user's; that copy runs instead of the OS's.

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
    /// For a copy Reef installs of an OS app: the oldest `IMAGE_VERSION`
    /// whose libraries it runs with (the image it was built against).
    pub min_image: String,
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
        if !app.icon.is_empty() && !app.icon.starts_with("qrc:") && !app.icon.starts_with("file://")
        {
            let icon = if app.icon.starts_with('/') {
                PathBuf::from(&app.icon)
            } else {
                dir.join(&app.icon)
            };
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

/// The OS's own copy of `app_id`.
pub fn system(app_id: &str) -> Option<App> {
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

/// Whether version `a` sorts after `b`: dot-separated parts, compared as
/// numbers where both are numbers, a missing part as 0.
pub fn is_newer(a: &str, b: &str) -> bool {
    let (a, b): (Vec<&str>, Vec<&str>) = (a.split('.').collect(), b.split('.').collect());
    (0..a.len().max(b.len()))
        .map(|i| {
            let (x, y) = (
                a.get(i).copied().unwrap_or("0"),
                b.get(i).copied().unwrap_or("0"),
            );
            match (x.parse::<u64>(), y.parse::<u64>()) {
                (Ok(x), Ok(y)) => x.cmp(&y),
                _ => x.cmp(y),
            }
        })
        .find(|o| o.is_ne())
        .is_some_and(std::cmp::Ordering::is_gt)
}

/// The running image's `IMAGE_VERSION`.
pub fn running_image() -> Option<String> {
    fs::read_to_string(paths::os_release())
        .ok()?
        .lines()
        .find_map(|l| l.strip_prefix("IMAGE_VERSION="))
        .map(|v| v.trim().trim_matches(['"', '\'']).to_owned())
        .filter(|v| !v.is_empty())
}

/// Whether the user's copy of an OS app runs instead of the OS's: a system
/// key signed it, it is newer, and this image has the libraries it was built
/// against. An OS update that brings the app's newer version wins again.
pub fn supersedes(user: &App, system: &App, image: Option<&str>) -> bool {
    user.is_system
        && is_newer(&user.version, &system.version)
        && (user.min_image.is_empty() || image.is_some_and(|i| !is_newer(&user.min_image, i)))
}

fn choose(system: App, user: Option<App>, image: Option<&str>) -> App {
    match user {
        Some(user) if supersedes(&user, &system, image) => user,
        _ => system,
    }
}

/// The app of `app_id`: the OS's, or the user's copy that supersedes it;
/// the user's for an app the OS doesn't have.
pub fn find(app_id: &str) -> Option<App> {
    if app_id.is_empty() {
        return None;
    }
    if paths::system_app(app_id).join("manifest.json").exists() {
        let system = system(app_id).filter(|a| a.id == app_id)?;
        Some(choose(system, user(app_id), running_image().as_deref()))
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

/// Every app, the OS's first, each the copy [`find`] picks.
pub fn scan() -> Vec<App> {
    let image = running_image();
    let mut apps: Vec<App> = ids(&paths::system_apps())
        .iter()
        .filter_map(|id| system(id))
        .map(|system| {
            let user = user(&system.id);
            choose(system, user, image.as_deref())
        })
        .collect();
    for app in ids(&paths::user_installs())
        .iter()
        .filter_map(|id| user(id))
    {
        if !apps.iter().any(|a| a.id == app.id) {
            apps.push(app);
        }
    }
    apps
}

/// The user's copies of OS apps that the OS's copy has caught up with.
pub fn superseded() -> Vec<String> {
    ids(&paths::user_installs())
        .into_iter()
        .filter(|id| {
            system(id).is_some_and(|system| {
                user(id).is_some_and(|user| !is_newer(&user.version, &system.version))
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn app(version: &str, is_system: bool, min_image: &str) -> App {
        App {
            id: "maps".into(),
            version: version.into(),
            is_system,
            min_image: min_image.into(),
            ..App::default()
        }
    }

    #[test]
    fn orders_versions() {
        assert!(is_newer("1.0.0.2611021530", "1.0.0"));
        assert!(is_newer("1.0.0.2611021530", "1.0.0.2611011200"));
        assert!(is_newer("1.10", "1.9"));
        assert!(!is_newer("1.0", "1.0.0"));
        assert!(!is_newer("1.0.0", "1.0"));
        assert!(!is_newer("1.0.0.1", "1.0.0.2"));
        assert!(is_newer("1.0.b", "1.0.a"));
    }

    #[test]
    fn a_newer_system_signed_copy_supersedes_the_os_app() {
        let os = app("1.0.0.2611010000", true, "");
        assert!(supersedes(&app("1.0.0.2611050000", true, ""), &os, None));
        // Not signed by a system key, not newer, or the OS caught up.
        assert!(!supersedes(&app("1.0.0.2611050000", false, ""), &os, None));
        assert!(!supersedes(&app("1.0.0.2611010000", true, ""), &os, None));
        let updated_os = app("1.0.0.2611060000", true, "");
        assert!(!supersedes(
            &app("1.0.0.2611050000", true, ""),
            &updated_os,
            None
        ));
    }

    #[test]
    fn needs_the_image_it_was_built_against() {
        let os = app("1.0.0.1", true, "");
        let copy = app("1.0.0.2", true, "26110501");
        assert!(supersedes(&copy, &os, Some("26110501")));
        assert!(supersedes(&copy, &os, Some("26110601")));
        assert!(!supersedes(&copy, &os, Some("26110401")));
        assert!(!supersedes(&copy, &os, None));
        assert_eq!(choose(os.clone(), Some(copy.clone()), Some("26110401")), os);
        assert_eq!(choose(os, Some(copy.clone()), Some("26110601")), copy);
    }
}
