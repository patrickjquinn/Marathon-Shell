//! Where Marathon apps live. An app's code and the record of what the user
//! approved are never inside a directory the app can write: user installs
//! sit under [`user_installs`] (bound read-only into the sandbox), the app's
//! own data under [`data_dir`] (bound read-write), as Flatpak keeps /app
//! apart from ~/.var/app/<id>.

use std::path::PathBuf;

/// Marathon's own apps, installed read-only by the OS. `MARATHON_APPS_DIR`
/// points a development shell at a build's install tree instead.
pub fn system_apps() -> PathBuf {
    std::env::var_os("MARATHON_APPS_DIR")
        .filter(|v| !v.is_empty())
        .map_or_else(|| PathBuf::from("/usr/share/marathon-apps"), PathBuf::from)
}

pub fn system_app(app_id: &str) -> PathBuf {
    system_apps().join(app_id)
}

/// `<id>/files` is the package as installed, `<id>/receipt.json` what the
/// installer recorded about it.
pub fn user_installs() -> PathBuf {
    dirs::data_dir().unwrap_or_default().join("marathon/apps")
}

pub fn install_dir(app_id: &str) -> PathBuf {
    user_installs().join(app_id)
}

pub fn files_dir(app_id: &str) -> PathBuf {
    install_dir(app_id).join("files")
}

pub fn receipt(app_id: &str) -> PathBuf {
    install_dir(app_id).join("receipt.json")
}

/// Before installs moved out, the data directory was also the install one.
pub fn legacy_installs() -> PathBuf {
    dirs::data_dir().unwrap_or_default().join("marathon-apps")
}

pub fn data_dir(app_id: &str) -> PathBuf {
    legacy_installs().join(app_id)
}

pub fn config_dir(app_id: &str) -> PathBuf {
    dirs::config_dir()
        .unwrap_or_default()
        .join("marathon-apps")
        .join(app_id)
}

pub fn cache_dir(app_id: &str) -> PathBuf {
    dirs::cache_dir()
        .unwrap_or_default()
        .join("marathon-apps")
        .join(app_id)
}

/// The running OS's os-release. `MARATHON_OS_RELEASE` overrides it.
pub fn os_release() -> PathBuf {
    std::env::var_os("MARATHON_OS_RELEASE")
        .filter(|v| !v.is_empty())
        .map_or_else(|| PathBuf::from("/etc/os-release"), PathBuf::from)
}

/// The keys Marathon's own apps are signed with: only a package one of them
/// signed may be a protected system app. `MARATHON_SYSTEM_KEYS_DIR`
/// overrides it.
pub fn system_keys() -> PathBuf {
    std::env::var_os("MARATHON_SYSTEM_KEYS_DIR")
        .filter(|v| !v.is_empty())
        .map_or_else(
            || PathBuf::from("/usr/share/marathon/system-keys"),
            PathBuf::from,
        )
}

/// Every key a package may be signed with; their `revoked` lists apply to
/// all of them.
pub fn trusted_keys() -> Vec<PathBuf> {
    vec![
        PathBuf::from("/usr/share/marathon/trusted-keys"),
        system_keys(),
        dirs::config_dir()
            .unwrap_or_default()
            .join("marathon/trusted-keys"),
    ]
}

/// Where an app kept its data before it ran in the runner's sandbox,
/// relative to the XDG data and cache homes: Pacific ran under the Keel
/// host with Sailjail's directory names.
const LEGACY_DIRS: &[(&str, &str)] = &[("shipwright-pacific", "org.shipwright/pacific")];

/// Moves `app_id`'s pre-sandbox data and cache under `<home>/marathon-apps/<id>`
/// (for each of `homes`, the XDG data and cache homes), once: only while the
/// new directory is missing or empty and the old one exists. The sandbox
/// binds only the new one.
pub fn adopt_legacy_dirs(app_id: &str, homes: &[&std::path::Path]) -> std::io::Result<()> {
    let Some((_, legacy)) = LEGACY_DIRS.iter().find(|(id, _)| *id == app_id) else {
        return Ok(());
    };
    for home in homes {
        let old = home.join(legacy);
        let new = home.join("marathon-apps").join(app_id);
        if !old.is_dir() {
            continue;
        }
        // An earlier launch may have made it empty; remove_dir leaves a full one.
        if new.exists() && std::fs::remove_dir(&new).is_err() {
            continue;
        }
        std::fs::create_dir_all(home.join("marathon-apps"))?;
        std::fs::rename(&old, &new)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, reason = "tests")]

    use super::*;
    use std::fs;

    #[test]
    fn adopts_pacific_once() {
        let root = tempfile::tempdir().unwrap();
        let (data, cache) = (root.path().join("share"), root.path().join("cache"));
        fs::create_dir_all(data.join("org.shipwright/pacific/web")).unwrap();
        fs::write(data.join("org.shipwright/pacific/places.db"), "db").unwrap();
        fs::create_dir_all(cache.join("org.shipwright/pacific")).unwrap();
        fs::create_dir_all(cache.join("marathon-apps/shipwright-pacific")).unwrap();
        adopt_legacy_dirs("shipwright-pacific", &[data.as_path(), cache.as_path()]).unwrap();
        let moved = data.join("marathon-apps/shipwright-pacific");
        assert_eq!(fs::read_to_string(moved.join("places.db")).unwrap(), "db");
        assert!(moved.join("web").is_dir());
        assert!(!data.join("org.shipwright/pacific").exists());
        assert!(!cache.join("org.shipwright/pacific").exists());
        assert!(cache.join("marathon-apps/shipwright-pacific").is_dir());

        // Never over data the app already has in its own directory.
        fs::create_dir_all(data.join("org.shipwright/pacific")).unwrap();
        fs::write(data.join("org.shipwright/pacific/places.db"), "old").unwrap();
        adopt_legacy_dirs("shipwright-pacific", &[data.as_path(), cache.as_path()]).unwrap();
        assert_eq!(fs::read_to_string(moved.join("places.db")).unwrap(), "db");
        assert!(data.join("org.shipwright/pacific/places.db").exists());

        // Other apps have nothing to adopt.
        fs::create_dir_all(data.join("org.shipwright/notes")).unwrap();
        adopt_legacy_dirs("notes", &[data.as_path()]).unwrap();
        assert!(!data.join("marathon-apps/notes").exists());
    }
}
