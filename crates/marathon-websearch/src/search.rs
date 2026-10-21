//! A search and the text of each result: fetched as is, or rendered when
//! the page builds itself in JavaScript.

use std::io::Read as _;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use dom_query::Document;
use marathon_rt::log;
use serde::Serialize;

pub const MAX_RESULTS: usize = 10;
const MAX_DESCRIPTION: usize = 4000;
const MAX_PAGE: u64 = 2 * 1024 * 1024;
/// Less readable text than this, the page needs its JavaScript.
const THIN: usize = 300;
const FETCH_TIMEOUT: Duration = Duration::from_secs(4);
/// The whole answer's: a page still rendering by then keeps its snippet.
const BUDGET: Duration = Duration::from_secs(6);
// Pacific's own: a page gets the markup it gives a phone's browser.
const USER_AGENT: &str = "Mozilla/5.0 (Linux; aarch64) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile Safari/605.1.15";

#[derive(Serialize)]
pub struct Item {
    url: String,
    title: String,
    description: String,
}

fn agent() -> ureq::Agent {
    ureq::Agent::config_builder().user_agent(USER_AGENT).timeout_global(Some(FETCH_TIMEOUT)).build().into()
}

/// The results, each with its page's text where it could be read in time,
/// else the engine's snippet.
pub fn search(query: &str, limit: usize, fresh: bool) -> Vec<Item> {
    let started = Instant::now();
    let results = match results(query, fresh) {
        Ok(r) => r,
        Err(e) => {
            log::warn("websearch", format_args!("search: {e}"));
            return Vec::new();
        }
    };
    let items: Vec<Item> = std::thread::scope(|s| {
        let deadline = started + BUDGET;
        // All started before any is waited on.
        #[allow(clippy::needless_collect, reason = "the pages load in parallel")]
        let pages: Vec<_> = results.into_iter().take(limit).map(|r| s.spawn(move || with_text(r, deadline))).collect();
        pages.into_iter().filter_map(|p| p.join().ok()).collect()
    });
    log::warn("websearch", format_args!("{} results in {} ms", items.len(), started.elapsed().as_millis()));
    items
}

/// `DuckDuckGo`'s HTML endpoint, else its lite one, which it sometimes
/// answers when the other comes back empty: no account, no key, no
/// JavaScript. `fresh` keeps to the past week (news, results, prices).
fn results(query: &str, fresh: bool) -> Result<Vec<Item>, ureq::Error> {
    let mut form = vec![("q", query)];
    if fresh {
        form.push(("df", "w"));
    }
    let page = |url| agent().post(url).send_form(form.clone())?.body_mut().read_to_string();
    let html = Document::from(page("https://html.duckduckgo.com/html/")?.as_str());
    let items: Vec<Item> = html
        .select(".result")
        .iter()
        .filter(|r| !r.has_class("result--ad"))
        .filter_map(|r| item(&r.select("a.result__a"), &r.select(".result__snippet")))
        .collect();
    if !items.is_empty() {
        return Ok(items);
    }
    let lite = Document::from(page("https://lite.duckduckgo.com/lite/")?.as_str());
    let snippets = lite.select("td.result-snippet");
    Ok(lite.select("a.result-link").iter().zip(snippets.iter()).filter_map(|(link, snippet)| item(&link, &snippet)).collect())
}

fn item(link: &dom_query::Selection<'_>, snippet: &dom_query::Selection<'_>) -> Option<Item> {
    let url = link.attr("href")?.to_string();
    (url.starts_with("https://") || url.starts_with("http://")).then(|| Item {
        url,
        title: cap(link.text().trim(), 300),
        description: cap(snippet.text().trim(), MAX_DESCRIPTION),
    })
}

fn with_text(mut item: Item, deadline: Instant) -> Item {
    let fetched = fetch(&item.url).map(|html| readable(&html, &item.url));
    let text = match fetched {
        Some(t) if t.chars().count() >= THIN => Some(t),
        _ => rendered(&item.url, deadline),
    };
    if let Some(t) = text.filter(|t| t.chars().count() > item.description.chars().count()) {
        item.description = cap(&t, MAX_DESCRIPTION);
    }
    item
}

fn fetch(url: &str) -> Option<String> {
    let mut reply = agent().get(url).call().ok()?;
    let html = reply.headers().get("content-type").and_then(|v| v.to_str().ok()).is_some_and(|t| t.contains("html"));
    if !html {
        return None;
    }
    let mut body = String::new();
    reply.body_mut().as_reader().take(MAX_PAGE).read_to_string(&mut body).ok()?;
    Some(body)
}

/// The page's main text, as Pacific's reader view would show it.
fn readable(html: &str, url: &str) -> String {
    let article = dom_smoothie::Readability::new(html, Some(url), None).and_then(|mut r| r.parse());
    article.map(|a| tidy(&a.text_content)).unwrap_or_default()
}

/// The page rendered by WPE in a process of its own (`render`), which a
/// crash or a hung page cannot take the service down with.
fn rendered(url: &str, deadline: Instant) -> Option<String> {
    if deadline.saturating_duration_since(Instant::now()) < Duration::from_secs(2) {
        return None;
    }
    let exe = std::env::current_exe().ok()?;
    let mut child = Command::new(exe).args(["render", url]).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().ok()?;
    while child.try_wait().ok()?.is_none() {
        if Instant::now() >= deadline {
            child.kill().ok();
            child.wait().ok();
            return None;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    let mut out = String::new();
    child.stdout.take()?.read_to_string(&mut out).ok()?;
    let html = out.trim();
    (!html.is_empty()).then(|| readable(html, url))
}

fn tidy(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn cap(text: &str, max: usize) -> String {
    text.chars().take(max).collect()
}
