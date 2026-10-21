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
    dirs::config_dir().unwrap_or_default().join("marathon-apps").join(app_id)
}

pub fn cache_dir(app_id: &str) -> PathBuf {
    dirs::cache_dir().unwrap_or_default().join("marathon-apps").join(app_id)
}

/// The keys Marathon's own apps are signed with: only a package one of them
/// signed may be a protected system app. `MARATHON_SYSTEM_KEYS_DIR`
/// overrides it.
pub fn system_keys() -> PathBuf {
    std::env::var_os("MARATHON_SYSTEM_KEYS_DIR")
        .filter(|v| !v.is_empty())
        .map_or_else(|| PathBuf::from("/usr/share/marathon/system-keys"), PathBuf::from)
}

/// Every key a package may be signed with; their `revoked` lists apply to
/// all of them.
pub fn trusted_keys() -> Vec<PathBuf> {
    vec![
        PathBuf::from("/usr/share/marathon/trusted-keys"),
        system_keys(),
        dirs::config_dir().unwrap_or_default().join("marathon/trusted-keys"),
    ]
}
