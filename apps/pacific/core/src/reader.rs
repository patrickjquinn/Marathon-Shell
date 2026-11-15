// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Reader mode: the article of a page, without the rest, in a clean page
//! with an estimated reading time.
//!
//! Extraction uses `dom_smoothie` (MIT), a Rust port of Mozilla's
//! Readability. It was preferred over `readabilityrs` for its maintenance
//! and release record (validation report, section 5). The page HTML comes
//! from the live DOM (`document.documentElement.outerHTML`, read in an
//! isolated script world), so what the person sees is what is extracted.
//!
//! The reader page is static HTML with a Content Security Policy that
//! allows no script at all (inline handlers included), no frames, no
//! forms, no fonts or styles from elsewhere, and images only over HTTPS
//! or as data URLs. Page text is never trusted.

use dom_smoothie::{Config, Readability, TextMode};
use serde::Serialize;

use crate::util::{html_escape, truncate_chars};
use crate::{Error, Result};

/// Pages larger than this are not parsed (a reader view of a 20 MB page
/// would not be a pleasant read either).
pub const MAX_HTML: usize = 8 * 1024 * 1024;

/// Reading speeds: words per minute for space-separated scripts and
/// characters per minute for Chinese, Japanese and Korean.
const WORDS_PER_MINUTE: usize = 230;
const CJK_CHARS_PER_MINUTE: usize = 500;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Article {
    pub title: String,
    pub byline: String,
    pub site_name: String,
    pub excerpt: String,
    pub lang: String,
    /// `ltr` or `rtl`.
    pub dir: String,
    pub published: String,
    /// The article's HTML (as extracted; render it with [`render`]).
    pub content_html: String,
    /// The article as plain text with paragraph breaks.
    pub text: String,
    pub words: usize,
    pub minutes: usize,
}

fn is_cjk(c: char) -> bool {
    matches!(c as u32,
        0x3040..=0x30FF | 0x3400..=0x4DBF | 0x4E00..=0x9FFF | 0xAC00..=0xD7AF | 0xF900..=0xFAFF)
}

/// Words (or CJK characters counted as such) and minutes to read `text`,
/// at least one minute for any text.
#[allow(clippy::cast_precision_loss, reason = "word counts are far below 2^52")]
pub fn reading_time(text: &str) -> (usize, usize) {
    let cjk = text.chars().filter(|c| is_cjk(*c)).count();
    let words = text
        .split_whitespace()
        .filter(|w| w.chars().any(char::is_alphanumeric) && !w.chars().all(is_cjk))
        .count();
    let minutes =
        (words as f64 / WORDS_PER_MINUTE as f64 + cjk as f64 / CJK_CHARS_PER_MINUTE as f64).round();
    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        reason = "a small positive count"
    )]
    let minutes = minutes as usize;
    let total = words + cjk;
    (total, if total == 0 { 0 } else { minutes.max(1) })
}

/// Whether the page is likely to give a useful reader view (shown as the
/// reader button in the address bar).
pub fn is_readable(html: &str, url: &str) -> bool {
    if html.len() > MAX_HTML {
        return false;
    }
    Readability::new(html, Some(url), None).is_ok_and(|r| r.is_probably_readable())
}

/// Extracts the article of `html` (the page at `url`).
pub fn extract(html: &str, url: &str) -> Result<Article> {
    if html.len() > MAX_HTML {
        return Err(Error::Reader("the page is too large".into()));
    }
    let cfg = Config {
        text_mode: TextMode::Formatted,
        ..Config::default()
    };
    // Collapsed sections (mobile Wikipedia's `hidden="until-found"`) are
    // content the reader can find and open, but Readability drops anything
    // hidden: on the phone the live page gave the lead only ("1 min read").
    let html = html
        .replace(" hidden=\"until-found\"", "")
        .replace(" hidden=until-found", "");
    let mut r = Readability::new(html.as_str(), Some(url), Some(cfg))
        .map_err(|e| Error::Reader(e.to_string()))?;
    let a = r.parse().map_err(|e| Error::Reader(e.to_string()))?;
    let text = a.text_content.to_string();
    if text.trim().is_empty() {
        return Err(Error::Reader("no article found on this page".into()));
    }
    let (words, minutes) = reading_time(&text);
    Ok(Article {
        title: truncate_chars(a.title.trim(), 300),
        byline: truncate_chars(a.byline.as_deref().unwrap_or("").trim(), 200),
        site_name: truncate_chars(a.site_name.as_deref().unwrap_or("").trim(), 100),
        excerpt: truncate_chars(a.excerpt.as_deref().unwrap_or("").trim(), 500),
        lang: a
            .lang
            .unwrap_or_default()
            .chars()
            .filter(|c| c.is_ascii_alphanumeric() || *c == '-')
            .take(20)
            .collect(),
        dir: if a.dir.as_deref() == Some("rtl") {
            "rtl".into()
        } else {
            "ltr".into()
        },
        published: a.published_time.unwrap_or_default(),
        content_html: a.content.to_string(),
        text,
        words,
        minutes,
    })
}

/// Reader appearance.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Theme {
    Light,
    Sepia,
    Dark,
}

impl Theme {
    pub fn parse(s: &str) -> Self {
        match s {
            "sepia" => Self::Sepia,
            "dark" => Self::Dark,
            _ => Self::Light,
        }
    }

    fn colours(self) -> (&'static str, &'static str, &'static str) {
        match self {
            Self::Light => ("#ffffff", "#1b1b1b", "#0b57d0"),
            Self::Sepia => ("#f4ecd8", "#3b2f22", "#7a4b12"),
            Self::Dark => ("#121417", "#e3e3e3", "#8ab4f8"),
        }
    }
}

/// The policy of reader pages: nothing runs, nothing is fetched but images.
pub const READER_CSP: &str =
    "default-src 'none'; img-src https: data:; style-src 'unsafe-inline'; \
     media-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'";

/// The reader page for `article` from `url`. `font_px` is the body text
/// size, `serif` the typeface family, and `minutes_label` the localised
/// "%1 min read" text from the UI.
pub fn render(
    article: &Article,
    url: &str,
    theme: Theme,
    font_px: u32,
    serif: bool,
    minutes_label: &str,
) -> String {
    let (bg, fg, link) = theme.colours();
    let font = if serif {
        "Georgia, 'Noto Serif', serif"
    } else {
        "'Sail Sans Pro', 'Noto Sans', sans-serif"
    };
    let host = crate::util::display_host(url);
    let mut meta = Vec::new();
    for part in [&article.byline, &article.site_name] {
        if !part.is_empty() {
            meta.push(html_escape(part));
        }
    }
    if host.is_empty() {
        meta.push(String::new());
    } else if article.site_name.is_empty() {
        meta.push(html_escape(&host));
    }
    if article.minutes > 0 {
        meta.push(html_escape(
            &minutes_label.replace("%1", &article.minutes.to_string()),
        ));
    }
    let meta: Vec<String> = meta.into_iter().filter(|m| !m.is_empty()).collect();
    let lang = if article.lang.is_empty() {
        "en".to_owned()
    } else {
        article.lang.clone()
    };
    format!(
        "<!DOCTYPE html>\n<html lang=\"{lang}\" dir=\"{dir}\"><head><meta charset=\"utf-8\">\
<meta http-equiv=\"Content-Security-Policy\" content=\"{csp}\">\
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\
<meta name=\"referrer\" content=\"no-referrer\">\
<title>{title}</title><style>\
html{{background:{bg};color:{fg};-webkit-text-size-adjust:100%}}\
body{{margin:0 auto;max-width:42em;padding:1.2em 1.1em 4em;font:{font_px}px/1.6 {font};word-wrap:break-word}}\
h1{{font-size:1.6em;line-height:1.25;margin:0.3em 0}}\
.meta{{opacity:0.7;font-size:0.85em;margin-bottom:1.6em}}\
a{{color:{link}}}img,video,figure{{max-width:100%;height:auto}}figure{{margin:1em 0}}\
pre,code{{white-space:pre-wrap;font-size:0.9em}}blockquote{{margin:1em 0;padding-left:1em;border-left:3px solid {link}}}\
table{{display:block;overflow-x:auto;border-collapse:collapse}}td,th{{padding:0.2em 0.5em}}\
</style></head><body><article><h1>{title}</h1><div class=\"meta\">{meta}</div>{content}</article></body></html>\n",
        lang = html_escape(&lang),
        dir = article.dir,
        csp = READER_CSP,
        title = html_escape(&article.title),
        meta = meta.join(" \u{b7} "),
        content = article.content_html,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(name: &str) -> String {
        std::fs::read_to_string(format!(
            "{}/tests/fixtures/{name}",
            env!("CARGO_MANIFEST_DIR")
        ))
        .unwrap()
    }

    #[test]
    fn extracts_a_news_article() {
        let html = fixture("article.html");
        let url = "https://news.example/2026/10/04/harbour";
        assert!(is_readable(&html, url));
        let a = extract(&html, url).unwrap();
        assert_eq!(a.title, "The harbour reopens after the storm");
        assert!(a.byline.contains("Aino Virtanen"), "{}", a.byline);
        assert!(a.text.contains("fishing boats returned"));
        // Navigation, ads, comments and scripts are gone.
        assert!(!a.content_html.contains("Subscribe now"));
        assert!(!a.content_html.contains("<script"));
        assert!(!a.text.contains("Cookie settings"));
        assert!(a.words > 300, "{}", a.words);
        assert_eq!(a.minutes, reading_time(&a.text).1);
        assert!(a.minutes >= 2);
        assert_eq!(a.lang, "en");
    }

    #[test]
    fn rejects_pages_without_an_article() {
        let html = fixture("app-shell.html");
        assert!(!is_readable(&html, "https://app.example/"));
    }

    #[test]
    fn reading_time_counts_words_and_cjk() {
        assert_eq!(reading_time(""), (0, 0));
        assert_eq!(reading_time("one two three"), (3, 1));
        let long = "word ".repeat(460);
        assert_eq!(reading_time(&long), (460, 2));
        let cjk = "漢".repeat(1000);
        assert_eq!(reading_time(&cjk), (1000, 2));
        assert_eq!(reading_time("— – ..."), (0, 0));
    }

    #[test]
    fn rendered_page_is_locked_down() {
        let a = Article {
            title: "<script>alert(1)</script>".into(),
            byline: "A & B".into(),
            site_name: String::new(),
            excerpt: String::new(),
            lang: "fi".into(),
            dir: "ltr".into(),
            published: String::new(),
            content_html: "<p>Hello</p>".into(),
            text: "Hello".into(),
            words: 1,
            minutes: 1,
        };
        let page = render(
            &a,
            "https://www.example.com/x",
            Theme::Dark,
            18,
            true,
            "%1 min read",
        );
        assert!(page.contains("script-src") || page.contains("default-src 'none'"));
        assert!(page.contains("&lt;script&gt;alert(1)&lt;/script&gt;"));
        assert!(page.contains("A &amp; B \u{b7} example.com \u{b7} 1 min read"));
        assert!(page.contains("lang=\"fi\""));
        assert!(page.contains("#121417"));
        assert!(page.contains("<p>Hello</p>"));
        assert_eq!(Theme::parse("sepia"), Theme::Sepia);
        assert_eq!(Theme::parse("?"), Theme::Light);
    }

    #[test]
    fn collapsed_sections_are_read() {
        let para = "Jolla designs phones and Sailfish OS in Finland, with offices in Tampere and Helsinki. ".repeat(40);
        let html = format!(
            "<html><head><title>Jolla</title></head><body><article><h1>Jolla</h1><p>{para}</p>\
             <section><h2>History</h2><div hidden=\"until-found\"><p>{para}</p><p>{para}</p></div></section>\
             </article></body></html>"
        );
        let a = extract(&html, "https://en.m.wikipedia.org/wiki/Jolla").unwrap();
        assert!(
            a.words > 1500,
            "collapsed sections are part of the article: {} words",
            a.words
        );
    }
}
