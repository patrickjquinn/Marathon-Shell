//! The languages Marathon ships (`translations/languages.json`) and which
//! one the system speaks.

use i18n_embed::fluent::FluentLanguageLoader;
use i18n_embed::{I18nAssets, LanguageLoader};
use serde::Deserialize;

const LANGUAGES: &str = include_str!("../../../translations/languages.json");

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    Complete,
    Preview,
    Pseudo,
}

impl Status {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Complete => "complete",
            Self::Preview => "preview",
            Self::Pseudo => "pseudo",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Language {
    pub code: &'static str,
    pub native_name: &'static str,
    pub english_name: &'static str,
    pub status: Status,
}

fn all() -> Vec<Language> {
    serde_json::from_str(LANGUAGES).unwrap_or_default()
}

/// The shipped languages; the pseudo-language only under `MARATHON_PSEUDO_LOCALE=1`.
pub fn languages() -> Vec<Language> {
    let pseudo = std::env::var("MARATHON_PSEUDO_LOCALE").is_ok_and(|v| v == "1");
    all()
        .into_iter()
        .filter(|l| pseudo || l.status != Status::Pseudo)
        .collect()
}

/// The language to speak: `setting` if listed, else `env` (`fr_FR.UTF-8`
/// is `fr`, `en_XA` itself) if listed, else English.
pub fn resolve(setting: &str, env: Option<&str>) -> &'static str {
    let all = all();
    let listed = |code: &str| all.iter().find(|l| l.code == code).map(|l| l.code);
    listed(setting)
        .or_else(|| {
            let env = env?.split(['.', '@']).next()?;
            listed(env).or_else(|| listed(env.split('_').next()?))
        })
        .unwrap_or("en")
}

/// The language the environment asks for: `LANGUAGE`, else `LANG`.
pub fn current() -> &'static str {
    let env = std::env::var("LANGUAGE")
        .ok()
        .filter(|v| !v.is_empty())
        .or_else(|| std::env::var("LANG").ok());
    resolve("", env.as_deref())
}

/// Loads `code`'s messages into `loader`; English fills whatever it lacks.
#[allow(clippy::print_stderr, reason = "journald collects stderr")]
pub fn select(loader: &FluentLanguageLoader, assets: &dyn I18nAssets, code: &str) {
    let wanted = code
        .replace('_', "-")
        .parse()
        .unwrap_or_else(|_| loader.fallback_language().clone());
    if let Err(e) = i18n_embed::select(loader, assets, &[wanted]) {
        eprintln!("[i18n] cannot load {code}: {e}");
    }
}

#[cfg(test)]
mod tests {
    use super::{languages, resolve, select};
    use i18n_embed::fluent::FluentLanguageLoader;
    use unic_langid::langid;

    #[derive(rust_embed::RustEmbed)]
    #[folder = "src/testdata/i18n"]
    struct Assets;

    fn loader(code: &str) -> FluentLanguageLoader {
        let loader = FluentLanguageLoader::new("test", langid!("en"));
        select(&loader, &Assets, code);
        loader
    }

    #[test]
    fn a_shipped_catalog_is_selected() {
        assert_eq!(loader("de").get("hello"), "Hallo");
    }

    #[test]
    fn a_language_without_a_catalog_reads_english() {
        assert_eq!(loader("ga").get("hello"), "Hello");
    }

    #[test]
    fn the_pseudo_language_is_honoured_from_the_setting_and_the_environment() {
        assert_eq!(resolve("en_XA", None), "en_XA");
        assert_eq!(resolve("", Some("en_XA")), "en_XA");
        assert_eq!(resolve("", Some("de_DE.UTF-8")), "de");
    }

    #[test]
    fn a_listed_setting_wins() {
        assert_eq!(resolve("de", None), "de");
        assert_eq!(resolve("de", Some("fr_FR.UTF-8")), "de");
    }

    #[test]
    fn an_empty_setting_follows_the_environment() {
        assert_eq!(resolve("", Some("fr_FR.UTF-8")), "fr");
    }

    #[test]
    fn anything_unlisted_is_english() {
        assert_eq!(resolve("xx", Some("C")), "en");
        assert_eq!(resolve("", None), "en");
    }

    #[test]
    fn the_list_has_the_shipped_languages_and_no_pseudo() {
        let codes: Vec<_> = languages().iter().map(|l| l.code).collect();
        for code in ["en", "de", "fr", "es", "ga"] {
            assert!(codes.contains(&code), "{code} missing");
        }
        assert!(!codes.contains(&"en_XA"));
    }
}
