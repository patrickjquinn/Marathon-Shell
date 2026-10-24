//! Android apps' ids.

/// An Android app's id is this and its package.
pub const ANDROID: &str = "deckard.";
/// How a Deckard desktop entry launches its app.
pub const LAUNCHER: &str = "/usr/libexec/deckard-launch app ";

/// The package of an Android app's id.
pub fn android_package(app_id: &str) -> Option<&str> {
    app_id.strip_prefix(ANDROID).filter(|pkg| !pkg.is_empty())
}
