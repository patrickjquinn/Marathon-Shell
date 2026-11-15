// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Search engines and their suggestion services.
//!
//! DuckDuckGo is the default. The built-in list can be reordered, any
//! engine chosen as default, and custom engines added with a URL template
//! (`%s` or `{searchTerms}` for the query). Suggestions are fetched only
//! when the person has them on (Settings, off in private tabs), only from
//! the default engine, and never for text that looks like an address or
//! contains an `@` or digits run long enough to be private (suggest.rs).

use rusqlite::params;
use serde::{Deserialize, Serialize};

use crate::db::Profile;
use crate::{Error, Result};

/// How a suggestion service answers.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SuggestFormat {
    /// `["query", ["s1", "s2", ...], ...]` (OpenSearch suggestions JSON).
    OpenSearch,
    /// `[{"phrase": "s1"}, ...]` (DuckDuckGo's `ac` endpoint).
    Phrases,
}

impl SuggestFormat {
    fn as_str(self) -> &'static str {
        match self {
            Self::OpenSearch => "opensearch",
            Self::Phrases => "phrases",
        }
    }

    fn parse(s: &str) -> Self {
        if s == "phrases" {
            Self::Phrases
        } else {
            Self::OpenSearch
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SearchEngine {
    pub id: String,
    pub name: String,
    /// Typed before the query to use this engine once (`w rust`).
    pub keyword: String,
    /// `{searchTerms}` is replaced by the encoded query.
    pub search_url: String,
    /// Empty when the engine offers no suggestions.
    pub suggest_url: String,
    pub suggest_format: SuggestFormat,
    pub builtin: bool,
}

/// The Wikipedia edition for a locale name (`de_DE.UTF-8` -> `de`,
/// `nb_NO` -> `no`); English for C, POSIX or nothing.
pub fn wikipedia_language(locale: &str) -> String {
    let lang = locale
        .split(['_', '-', '.', '@'])
        .next()
        .unwrap_or("")
        .to_ascii_lowercase();
    if !(2..=3).contains(&lang.len()) || !lang.chars().all(|c| c.is_ascii_lowercase()) {
        return "en".into();
    }
    match lang.as_str() {
        // Bokmål is no.wikipedia.org; Nynorsk has its own (nn).
        "nb" => "no".into(),
        _ => lang,
    }
}

/// The phone's language for Wikipedia, from `LC_ALL`, `LC_MESSAGES` or
/// `LANG` (what Settings > Language starts apps with).
pub fn system_wikipedia_language() -> String {
    ["LC_ALL", "LC_MESSAGES", "LANG"]
        .iter()
        .filter_map(|v| std::env::var(v).ok())
        .find(|v| !v.is_empty())
        .map_or_else(|| "en".into(), |v| wikipedia_language(&v))
}

fn wikipedia_urls(lang: &str) -> (String, String) {
    (
        format!("https://{lang}.wikipedia.org/wiki/Special:Search?search={{searchTerms}}"),
        format!("https://{lang}.wikipedia.org/w/api.php?action=opensearch&search={{searchTerms}}"),
    )
}

/// The built-in engines, in their default order. DuckDuckGo first: it is
/// the default. Wikipedia in the phone's language.
pub fn builtin_engines() -> Vec<SearchEngine> {
    builtin_engines_for(&system_wikipedia_language())
}

/// [`builtin_engines`] with Wikipedia's edition `lang` (`de`).
pub fn builtin_engines_for(lang: &str) -> Vec<SearchEngine> {
    let (wiki_search, wiki_suggest) = wikipedia_urls(lang);
    let e = |id: &str, name: &str, keyword: &str, search: &str, suggest: &str, f: SuggestFormat| {
        SearchEngine {
            id: id.into(),
            name: name.into(),
            keyword: keyword.into(),
            search_url: search.into(),
            suggest_url: suggest.into(),
            suggest_format: f,
            builtin: true,
        }
    };
    vec![
        e(
            "duckduckgo",
            "DuckDuckGo",
            "d",
            "https://duckduckgo.com/?q={searchTerms}",
            "https://duckduckgo.com/ac/?q={searchTerms}&type=list",
            SuggestFormat::OpenSearch,
        ),
        e(
            "startpage",
            "Startpage",
            "sp",
            "https://www.startpage.com/sp/search?query={searchTerms}",
            "https://www.startpage.com/osuggestions?q={searchTerms}",
            SuggestFormat::OpenSearch,
        ),
        e(
            "brave",
            "Brave Search",
            "br",
            "https://search.brave.com/search?q={searchTerms}",
            "https://search.brave.com/api/suggest?q={searchTerms}",
            SuggestFormat::OpenSearch,
        ),
        e(
            "qwant",
            "Qwant",
            "q",
            "https://www.qwant.com/?q={searchTerms}",
            "",
            SuggestFormat::OpenSearch,
        ),
        e(
            "ecosia",
            "Ecosia",
            "e",
            "https://www.ecosia.org/search?q={searchTerms}",
            "https://ac.ecosia.org/autocomplete?q={searchTerms}&type=list",
            SuggestFormat::OpenSearch,
        ),
        e(
            "mojeek",
            "Mojeek",
            "m",
            "https://www.mojeek.com/search?q={searchTerms}",
            "",
            SuggestFormat::OpenSearch,
        ),
        e(
            "google",
            "Google",
            "g",
            "https://www.google.com/search?q={searchTerms}",
            "https://suggestqueries.google.com/complete/search?client=firefox&q={searchTerms}",
            SuggestFormat::OpenSearch,
        ),
        e(
            "bing",
            "Bing",
            "b",
            "https://www.bing.com/search?q={searchTerms}",
            "https://api.bing.com/osjson.aspx?query={searchTerms}",
            SuggestFormat::OpenSearch,
        ),
        e(
            "wikipedia",
            "Wikipedia",
            "w",
            &wiki_search,
            &wiki_suggest,
            SuggestFormat::OpenSearch,
        ),
    ]
}

pub(crate) fn ensure_defaults(p: &Profile) -> Result<()> {
    ensure_defaults_for(p, &system_wikipedia_language())
}

/// [`ensure_defaults`] for Wikipedia's edition `lang`. A profile made
/// before Pacific followed the language keeps its engines, but a Wikipedia
/// entry still at the English default moves to `lang`.
pub(crate) fn ensure_defaults_for(p: &Profile, lang: &str) -> Result<()> {
    let have: i64 = p
        .conn
        .query_row("SELECT count(*) FROM search_engines", [], |r| r.get(0))?;
    if have > 0 && lang != "en" {
        let (en_search, en_suggest) = wikipedia_urls("en");
        let (search, suggest) = wikipedia_urls(lang);
        p.conn.execute(
            "UPDATE search_engines SET search_url = ?1, suggest_url = ?2
             WHERE id = 'wikipedia' AND search_url = ?3 AND suggest_url = ?4",
            params![search, suggest, en_search, en_suggest],
        )?;
    }
    if have == 0 {
        for (i, e) in builtin_engines_for(lang).iter().enumerate() {
            p.conn.execute(
                "INSERT INTO search_engines(id, name, keyword, search_url, suggest_url, suggest_format, position)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                params![e.id, e.name, e.keyword, e.search_url, e.suggest_url, e.suggest_format.as_str(),
                        i64::try_from(i).unwrap_or(0)],
            )?;
        }
    }
    Ok(())
}

/// Percent-encodes a query for a URL template (spaces as `+`).
pub fn encode_query(q: &str) -> String {
    url::form_urlencoded::byte_serialize(q.as_bytes()).collect()
}

impl SearchEngine {
    /// The results page for `query`.
    pub fn search_url_for(&self, query: &str) -> String {
        self.search_url
            .replace("{searchTerms}", &encode_query(query))
    }

    /// The suggestion request for `query`, if the engine has one.
    pub fn suggest_url_for(&self, query: &str) -> Option<String> {
        (!self.suggest_url.is_empty()).then(|| {
            self.suggest_url
                .replace("{searchTerms}", &encode_query(query))
        })
    }

    /// Parses a suggestion response, at most `limit` entries, each trimmed
    /// and at most 200 characters; the query itself is dropped.
    pub fn parse_suggestions(&self, query: &str, body: &[u8], limit: usize) -> Vec<String> {
        parse_suggestions(self.suggest_format, query, body, limit)
    }
}

pub fn parse_suggestions(
    format: SuggestFormat,
    query: &str,
    body: &[u8],
    limit: usize,
) -> Vec<String> {
    let Ok(v) = serde_json::from_slice::<serde_json::Value>(body) else {
        return Vec::new();
    };
    let items: Vec<String> = match format {
        SuggestFormat::OpenSearch => v
            .get(1)
            .and_then(|a| a.as_array())
            .map(|a| {
                a.iter()
                    .filter_map(|s| s.as_str().map(str::to_owned))
                    .collect()
            })
            .unwrap_or_default(),
        SuggestFormat::Phrases => v
            .as_array()
            .map(|a| {
                a.iter()
                    .filter_map(|o| o.get("phrase").and_then(|s| s.as_str()).map(str::to_owned))
                    .collect()
            })
            .unwrap_or_default(),
    };
    let q = query.trim().to_lowercase();
    let mut out: Vec<String> = Vec::new();
    for s in items {
        let s = s.trim();
        if s.is_empty() || s.chars().count() > 200 || s.to_lowercase() == q {
            continue;
        }
        if !out.iter().any(|o| o.eq_ignore_ascii_case(s)) {
            out.push(s.to_owned());
        }
        if out.len() >= limit {
            break;
        }
    }
    out
}

/// Checks a custom engine's URL template: https, with a query placeholder.
fn normalise_template(t: &str) -> Result<String> {
    let t = t.trim().replace("%s", "{searchTerms}");
    if !t.contains("{searchTerms}") {
        return Err(Error::Invalid(
            "the address needs %s where the search words go".into(),
        ));
    }
    let probe = t.replace("{searchTerms}", "x");
    let u = url::Url::parse(&probe).map_err(|_| Error::BadUrl(t.clone()))?;
    if u.scheme() != "https" && u.scheme() != "http" {
        return Err(Error::BadUrl(t));
    }
    Ok(t)
}

impl Profile {
    /// All engines in the person's order.
    pub fn search_engines(&self) -> Result<Vec<SearchEngine>> {
        let builtin: Vec<String> = builtin_engines().into_iter().map(|e| e.id).collect();
        let mut stmt = self.conn.prepare_cached(
            "SELECT id, name, keyword, search_url, suggest_url, suggest_format FROM search_engines ORDER BY position, name",
        )?;
        let rows = stmt
            .query_map([], |r| {
                let id: String = r.get(0)?;
                Ok(SearchEngine {
                    builtin: builtin.contains(&id),
                    id,
                    name: r.get(1)?,
                    keyword: r.get(2)?,
                    search_url: r.get(3)?,
                    suggest_url: r.get(4)?,
                    suggest_format: SuggestFormat::parse(&r.get::<_, String>(5)?),
                })
            })?
            .collect::<rusqlite::Result<_>>()?;
        Ok(rows)
    }

    /// The default engine (DuckDuckGo unless changed).
    pub fn default_engine(&self) -> Result<SearchEngine> {
        let id = self
            .pref("search.default")?
            .unwrap_or_else(|| "duckduckgo".into());
        let all = self.search_engines()?;
        Ok(all
            .iter()
            .find(|e| e.id == id)
            .or_else(|| all.first())
            .cloned()
            .unwrap_or_else(|| builtin_engines().remove(0)))
    }

    pub fn set_default_engine(&self, id: &str) -> Result<()> {
        if !self.search_engines()?.iter().any(|e| e.id == id) {
            return Err(Error::NotFound(format!("search engine {id}")));
        }
        self.set_pref("search.default", id)
    }

    pub fn engine_by_keyword(&self, keyword: &str) -> Result<Option<SearchEngine>> {
        let k = keyword.to_lowercase();
        Ok(self
            .search_engines()?
            .into_iter()
            .find(|e| !e.keyword.is_empty() && e.keyword.to_lowercase() == k))
    }

    /// Adds a custom engine; returns its id.
    pub fn add_search_engine(
        &self,
        name: &str,
        keyword: &str,
        template: &str,
        suggest: &str,
    ) -> Result<String> {
        let name = name.trim();
        if name.is_empty() {
            return Err(Error::Invalid("the engine needs a name".into()));
        }
        let search_url = normalise_template(template)?;
        let suggest_url = if suggest.trim().is_empty() {
            String::new()
        } else {
            normalise_template(suggest)?
        };
        let keyword = keyword.trim();
        if !keyword.is_empty() && self.engine_by_keyword(keyword)?.is_some() {
            return Err(Error::Invalid(format!(
                "the keyword {keyword} is already used"
            )));
        }
        let id = format!("custom-{}", crate::util::now_ms());
        let pos: i64 = self.conn.query_row(
            "SELECT coalesce(max(position) + 1, 0) FROM search_engines",
            [],
            |r| r.get(0),
        )?;
        self.conn.execute(
            "INSERT INTO search_engines(id, name, keyword, search_url, suggest_url, suggest_format, position)
             VALUES (?1, ?2, ?3, ?4, ?5, 'opensearch', ?6)",
            params![id, name, keyword, search_url, suggest_url, pos],
        )?;
        Ok(id)
    }

    /// Removes a custom engine (built-in ones stay). The default falls back
    /// to DuckDuckGo if it was this one.
    pub fn remove_search_engine(&self, id: &str) -> Result<()> {
        if builtin_engines().iter().any(|e| e.id == id) {
            return Err(Error::Invalid("built-in engines cannot be removed".into()));
        }
        self.conn
            .execute("DELETE FROM search_engines WHERE id = ?1", [id])?;
        if self.pref("search.default")?.as_deref() == Some(id) {
            self.set_pref("search.default", "duckduckgo")?;
        }
        Ok(())
    }

    pub fn search_engine(&self, id: &str) -> Result<Option<SearchEngine>> {
        Ok(self.search_engines()?.into_iter().find(|e| e.id == id))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wikipedia_follows_the_phones_language() {
        assert_eq!(wikipedia_language("de_DE.UTF-8"), "de");
        assert_eq!(wikipedia_language("fi_FI"), "fi");
        assert_eq!(wikipedia_language("nb_NO.utf8"), "no");
        assert_eq!(wikipedia_language("C.UTF-8"), "en");
        assert_eq!(wikipedia_language(""), "en");
        let wiki = |lang: &str| {
            builtin_engines_for(lang)
                .into_iter()
                .find(|e| e.id == "wikipedia")
                .unwrap()
        };
        assert_eq!(
            wiki("de").search_url_for("Jolla"),
            "https://de.wikipedia.org/wiki/Special:Search?search=Jolla"
        );
        assert!(wiki("fi")
            .suggest_url
            .starts_with("https://fi.wikipedia.org/w/api.php"));
        // A profile made in English moves to the phone's language; one the
        // person edited does not.
        let p = Profile::in_memory().unwrap();
        ensure_defaults_for(&p, "sv").unwrap();
        let url: String = p
            .conn
            .query_row(
                "SELECT search_url FROM search_engines WHERE id = 'wikipedia'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert!(url.starts_with("https://sv.wikipedia.org/"), "{url}");
        p.conn
            .execute("UPDATE search_engines SET search_url = 'https://x.example/?q={searchTerms}' WHERE id = 'wikipedia'", [])
            .unwrap();
        ensure_defaults_for(&p, "de").unwrap();
        let url: String = p
            .conn
            .query_row(
                "SELECT search_url FROM search_engines WHERE id = 'wikipedia'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(url, "https://x.example/?q={searchTerms}");
    }

    #[test]
    fn duckduckgo_is_default_and_urls_encode() {
        let p = Profile::in_memory().unwrap();
        let e = p.default_engine().unwrap();
        assert_eq!(e.id, "duckduckgo");
        assert_eq!(
            e.search_url_for("a b&c"),
            "https://duckduckgo.com/?q=a+b%26c"
        );
        assert_eq!(
            e.suggest_url_for("rust").as_deref(),
            Some("https://duckduckgo.com/ac/?q=rust&type=list")
        );
        p.set_default_engine("wikipedia").unwrap();
        assert_eq!(p.default_engine().unwrap().id, "wikipedia");
        assert!(p.set_default_engine("nope").is_err());
        assert_eq!(p.engine_by_keyword("W").unwrap().unwrap().id, "wikipedia");
    }

    #[test]
    fn parses_both_suggestion_formats() {
        let body = br#"["rust", ["rust", "rust lang", "Rust Lang", "rustup", ""]]"#;
        assert_eq!(
            parse_suggestions(SuggestFormat::OpenSearch, "rust", body, 5),
            ["rust lang", "rustup"]
        );
        let body = br#"[{"phrase":"sailfish os"},{"phrase":"sailfish"},{"x":1}]"#;
        assert_eq!(
            parse_suggestions(SuggestFormat::Phrases, "sail", body, 1),
            ["sailfish os"]
        );
        assert!(parse_suggestions(SuggestFormat::OpenSearch, "x", b"<html>", 5).is_empty());
    }

    #[test]
    fn custom_engines() {
        let p = Profile::in_memory().unwrap();
        let id = p
            .add_search_engine("Docs", "rs", "https://docs.rs/releases/search?query=%s", "")
            .unwrap();
        let e = p.search_engine(&id).unwrap().unwrap();
        assert_eq!(
            e.search_url_for("serde json"),
            "https://docs.rs/releases/search?query=serde+json"
        );
        assert!(!e.builtin);
        assert!(p
            .add_search_engine("X", "", "https://x.example/", "")
            .is_err());
        assert!(p
            .add_search_engine("X", "rs", "https://x.example/?q=%s", "")
            .is_err());
        assert!(p
            .add_search_engine("X", "", "ftp://x.example/?q=%s", "")
            .is_err());
        p.set_default_engine(&id).unwrap();
        p.remove_search_engine(&id).unwrap();
        assert_eq!(p.default_engine().unwrap().id, "duckduckgo");
        assert!(p.remove_search_engine("duckduckgo").is_err());
    }
}
