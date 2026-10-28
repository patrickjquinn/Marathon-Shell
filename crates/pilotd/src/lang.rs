// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The person's language and region: what the Pilot app tells pilotd
//! (`SetLocale`, from the app's own locale, which follows Settings >
//! Language), else pilotd's environment (`LC_ALL`, `LC_MESSAGES`, `LANG`),
//! else English. It decides the language Pilot is asked to answer in, the
//! weather's units and the language of place names and dates.

use std::sync::RwLock;

/// A POSIX or Qt locale name, parsed: "de_DE.UTF-8" -> de, DE.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Locale {
    /// ISO 639 language, lower case ("de", "fi", "nb").
    pub language: String,
    /// ISO 3166 region, upper case ("DE"), or empty.
    pub region: String,
}

impl Default for Locale {
    fn default() -> Locale {
        Locale {
            language: "en".into(),
            region: String::new(),
        }
    }
}

impl Locale {
    /// `de_DE.UTF-8`, `de-DE`, `fi_FI@euro`, `sv`. None for `C`, `POSIX`
    /// and anything that is not a language.
    pub fn parse(name: &str) -> Option<Locale> {
        let base = name.split(['.', '@']).next()?.trim();
        let mut parts = base.split(['_', '-']);
        let language = parts.next()?.to_ascii_lowercase();
        if !(2..=3).contains(&language.len())
            || !language.chars().all(|c| c.is_ascii_lowercase())
            || language == "c"
        {
            return None;
        }
        let region = parts
            .next()
            .filter(|r| r.len() == 2 && r.chars().all(|c| c.is_ascii_alphabetic()))
            .map(str::to_ascii_uppercase)
            .unwrap_or_default();
        Some(Locale { language, region })
    }

    /// The first usable locale in `LC_ALL`, `LC_MESSAGES`, `LANG`.
    pub fn from_env() -> Option<Locale> {
        ["LC_ALL", "LC_MESSAGES", "LANG"]
            .iter()
            .filter_map(|v| std::env::var(v).ok())
            .find_map(|v| Locale::parse(&v))
    }

    pub fn is_english(&self) -> bool {
        self.language == "en"
    }

    /// The language's English name, for the model ("German"); None for a
    /// language not listed (the model is then told the code).
    pub fn language_name(&self) -> Option<&'static str> {
        Some(match self.language.as_str() {
            "en" => "English",
            "de" => "German",
            "fr" => "French",
            "es" => "Spanish",
            "it" => "Italian",
            "pt" => "Portuguese",
            "nl" => "Dutch",
            "sv" => "Swedish",
            "fi" => "Finnish",
            "nb" | "no" | "nn" => "Norwegian",
            "da" => "Danish",
            "pl" => "Polish",
            "cs" => "Czech",
            "sk" => "Slovak",
            "hu" => "Hungarian",
            "et" => "Estonian",
            "lv" => "Latvian",
            "lt" => "Lithuanian",
            "ru" => "Russian",
            "uk" => "Ukrainian",
            "el" => "Greek",
            "tr" => "Turkish",
            "ro" => "Romanian",
            "hr" => "Croatian",
            "sl" => "Slovenian",
            "ca" => "Catalan",
            "ga" => "Irish",
            "zh" => "Chinese",
            "ja" => "Japanese",
            "ar" => "Arabic",
            _ => return None,
        })
    }

    /// Fahrenheit, mph and inches: the United States, Liberia and Myanmar.
    pub fn imperial(&self) -> bool {
        matches!(self.region.as_str(), "US" | "LR" | "MM")
    }

    /// The language for a web service's `language=` parameter ("de"; the
    /// Norwegian variants as "nb").
    pub fn service_language(&self) -> &str {
        match self.language.as_str() {
            "no" | "nn" => "nb",
            l => l,
        }
    }
}

fn slot() -> &'static RwLock<Option<Locale>> {
    static S: RwLock<Option<Locale>> = RwLock::new(None);
    &S
}

/// The locale the app reported (`SetLocale`). False if `name` is not one.
pub fn set(name: &str) -> bool {
    let Some(l) = Locale::parse(name) else {
        return false;
    };
    if let Ok(mut s) = slot().write() {
        *s = Some(l);
    }
    true
}

/// The person's locale now.
pub fn current() -> Locale {
    slot()
        .read()
        .ok()
        .and_then(|s| s.clone())
        .or_else(Locale::from_env)
        .unwrap_or_default()
}

/// The line of the system prompt that sets the answer's language, empty
/// for English.
pub fn prompt_line(l: &Locale) -> String {
    if l.is_english() {
        return String::new();
    }
    let name = l.language_name().map_or_else(
        || format!("the language with code {}", l.language),
        str::to_owned,
    );
    format!(
        " The phone is set to {name}: answer in {name}, unless the person writes to you in \
         another language, then answer in theirs."
    )
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn names_parse() {
        let de = Locale::parse("de_DE.UTF-8").unwrap();
        assert_eq!((de.language.as_str(), de.region.as_str()), ("de", "DE"));
        let fi = Locale::parse("fi_FI@euro").unwrap();
        assert_eq!(fi.region, "FI");
        assert_eq!(Locale::parse("sv").unwrap().region, "");
        assert_eq!(Locale::parse("en-US").unwrap().region, "US");
        assert_eq!(Locale::parse("C"), None);
        assert_eq!(Locale::parse("C.UTF-8"), None);
        assert_eq!(Locale::parse("POSIX"), None);
        assert_eq!(Locale::parse(""), None);
    }

    #[test]
    fn units_and_prompt() {
        assert!(Locale::parse("en_US").unwrap().imperial());
        assert!(Locale::parse("en_LR").unwrap().imperial());
        assert!(Locale::parse("my_MM").unwrap().imperial());
        assert!(!Locale::parse("en_GB").unwrap().imperial());
        assert!(!Locale::parse("en_CA").unwrap().imperial());
        assert_eq!(prompt_line(&Locale::parse("en_IE").unwrap()), "");
        let de = prompt_line(&Locale::parse("de_AT").unwrap());
        assert!(de.contains("answer in German"), "{de}");
        assert_eq!(Locale::parse("no_NO").unwrap().service_language(), "nb");
    }
}
