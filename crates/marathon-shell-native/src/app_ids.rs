//! Android apps' ids, and `marathon-shell-bin --rename-app-ids FROM TO`,
//! which Deckard's migration runs with the shell stopped to move them between
//! the Waydroid and Deckard prefixes in the stores the shell keeps.

#[cxx_qt::bridge]
mod ffi {
    #[namespace = "marathon::app_ids"]
    extern "Rust" {
        /// The process's exit status: 0 once every store is rewritten.
        fn rename_app_ids(from: &str, to: &str) -> i32;
    }
}

/// An Android app's id is this and its package.
pub const ANDROID: &str = "deckard.";
/// How a Deckard desktop entry launches its app.
pub const LAUNCHER: &str = "/usr/libexec/deckard-launch app ";
const PREFIXES: [&str; 2] = ["waydroid.", ANDROID];

/// The package of an Android app's id.
pub fn android_package(app_id: &str) -> Option<&str> {
    app_id.strip_prefix(ANDROID).filter(|pkg| !pkg.is_empty())
}

/// `id` under `to` when it is under `from`.
pub fn renamed(id: &str, from: &str, to: &str) -> Option<String> {
    id.strip_prefix(from).map(|pkg| format!("{to}{pkg}"))
}

fn rename_app_ids(from: &str, to: &str) -> i32 {
    if from == to || !PREFIXES.contains(&from) || !PREFIXES.contains(&to) {
        crate::log::warn(
            "app-ids",
            "usage: --rename-app-ids waydroid.|deckard. deckard.|waydroid.",
        );
        return 2;
    }
    let settings = crate::settings::rename_app_ids(from, to).map_err(|e| e.to_string());
    let history = crate::notifications::rename_app_ids(from, to).map_err(|e| e.to_string());
    match settings.and(history) {
        Ok(()) => 0,
        Err(error) => {
            crate::log::warn("app-ids", format_args!("cannot rename app ids: {error}"));
            1
        }
    }
}
