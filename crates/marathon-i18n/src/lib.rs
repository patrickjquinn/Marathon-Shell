//! The languages Marathon ships (`translations/languages.json`) and which
//! one the system speaks.

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

/// The shipped languages; the pseudo-language only under `MARATHON_PSEUDO_LOCALE=1`.
pub fn languages() -> Vec<Language> {
    let pseudo = std::env::var("MARATHON_PSEUDO_LOCALE").is_ok_and(|v| v == "1");
    serde_json::from_str::<Vec<Language>>(LANGUAGES)
        .unwrap_or_default()
        .into_iter()
        .filter(|l| pseudo || l.status != Status::Pseudo)
        .collect()
}

/// The language to speak: `setting` if listed, else the language part of
/// `env` (`fr_FR.UTF-8` is `fr`) if listed, else English.
pub fn resolve(setting: &str, env: Option<&str>) -> &'static str {
    let all = languages();
    let listed = |code: &str| all.iter().find(|l| l.code == code).map(|l| l.code);
    listed(setting)
        .or_else(|| {
            let env = env?;
            listed(env.split(['_', '.', '@']).next()?)
        })
        .unwrap_or("en")
}

#[cfg(test)]
mod tests {
    use super::{languages, resolve};

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
