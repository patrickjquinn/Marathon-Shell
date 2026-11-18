//! Logos for stations the directory has none for. From the station's own
//! site: the icon it gives phones (`apple-touch-icon`), else a large icon;
//! never a 16 px favicon, nor a share image (a banner or a stock picture:
//! RTÉ's is one grey placeholder for all its stations). Failing that, the
//! logo on Commons of Wikidata's radio station of that name in that
//! country (Wikipedia's own station logos are non-free: no API gives
//! them). Found once, in the background, and kept; a station with none is
//! asked about again after a week.

use std::collections::{HashMap, HashSet};
use std::io::Read;
use std::sync::mpsc::{channel, Sender};
use std::sync::{Mutex, OnceLock, PoisonError};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use ureq::ResponseExt as _;

const RETRY: u64 = 7 * 24 * 3600;
const PAGE_BYTES: u64 = 512 << 10;

#[derive(Default, Serialize, Deserialize)]
struct Found {
    /// The logo's address, empty when the site has none.
    logo: String,
    /// When it was looked for, seconds since 1970.
    at: u64,
}

#[derive(Default)]
struct Store {
    found: HashMap<String, Found>,
    pending: HashSet<String>,
    work: Option<Sender<String>>,
}

static STORE: OnceLock<Mutex<Store>> = OnceLock::new();

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs())
}

fn path() -> std::path::PathBuf {
    marathon_rt::dirs::cache().join("marathon/radio/logos.json")
}

fn store() -> &'static Mutex<Store> {
    STORE.get_or_init(|| {
        let found = std::fs::read(path())
            .ok()
            .and_then(|b| serde_json::from_slice(&b).ok())
            .unwrap_or_default();
        Mutex::new(Store {
            found,
            ..Store::default()
        })
    })
}

/// The logo found for a station; looks for one in the background when
/// there is none yet. `cc`: the station's country, ISO 3166 alpha-2.
pub fn get(name: &str, cc: &str, homepage: &str) -> Option<String> {
    if crate::catalogue::name_key(name).is_empty() {
        return None;
    }
    let key = format!("{name}\t{cc}\t{homepage}");
    let mut s = store().lock().unwrap_or_else(PoisonError::into_inner);
    if let Some(f) = s.found.get(&key) {
        if !f.logo.is_empty() {
            return Some(f.logo.clone());
        }
        if now().saturating_sub(f.at) < RETRY {
            return None;
        }
    }
    if s.pending.insert(key.clone()) {
        let work = s.work.get_or_insert_with(|| {
            let (tx, rx) = channel::<String>();
            std::thread::spawn(move || {
                for key in rx {
                    let mut parts = key.split('\t');
                    let (name, cc, page) = (
                        parts.next().unwrap_or(""),
                        parts.next().unwrap_or(""),
                        parts.next().unwrap_or(""),
                    );
                    let logo = Some(page)
                        .filter(|p| p.starts_with("http"))
                        .and_then(site)
                        .or_else(|| wikidata(name, cc))
                        .unwrap_or_default();
                    let mut s = store().lock().unwrap_or_else(PoisonError::into_inner);
                    s.pending.remove(&key);
                    s.found.insert(key, Found { logo, at: now() });
                    if let Ok(json) = serde_json::to_vec(&s.found) {
                        let file = path();
                        if let Some(dir) = file.parent() {
                            std::fs::create_dir_all(dir).ok();
                        }
                        std::fs::write(file, json).ok();
                    }
                }
            });
            tx
        });
        work.send(key).ok();
    }
    None
}

fn agent() -> ureq::Agent {
    ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(8)))
        .user_agent("MarathonRadio/1.0 (+https://github.com/patrickjquinn/Marathon-Shell)")
        .build()
        .new_agent()
}

fn json(url: &str) -> Option<serde_json::Value> {
    let mut body = String::new();
    agent()
        .get(url)
        .call()
        .ok()?
        .into_body()
        .into_reader()
        .take(1 << 20)
        .read_to_string(&mut body)
        .ok()?;
    serde_json::from_str(&body).ok()
}

fn query(pairs: &[(&str, &str)]) -> String {
    pairs
        .iter()
        .map(|(k, v)| {
            let v: String = v
                .bytes()
                .map(|b| match b {
                    b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' => {
                        (b as char).to_string()
                    }
                    _ => format!("%{b:02X}"),
                })
                .collect();
            format!("{k}={v}")
        })
        .collect::<Vec<_>>()
        .join("&")
}

const WIKIDATA: &str = "https://www.wikidata.org/w/api.php?";
/// Radio station, and radio network (a national broadcaster's channel).
const RADIO: &[&str] = &["Q14350", "Q184973"];

fn ids(claims: &serde_json::Value, property: &str) -> Vec<String> {
    claims[property].as_array().map_or_else(Vec::new, |a| {
        a.iter()
            .filter_map(|c| c["mainsnak"]["datavalue"]["value"]["id"].as_str())
            .map(str::to_owned)
            .collect()
    })
}

/// The logo on Commons of Wikidata's radio station `name` in country `cc`.
fn wikidata(name: &str, cc: &str) -> Option<String> {
    if cc.len() != 2 {
        return None;
    }
    let found = json(&format!(
        "{WIKIDATA}{}",
        query(&[
            ("action", "wbsearchentities"),
            ("search", name),
            ("language", "en"),
            ("type", "item"),
            ("limit", "7"),
            ("format", "json")
        ])
    ))?;
    let candidates: Vec<&str> = found["search"]
        .as_array()?
        .iter()
        .filter_map(|r| r["id"].as_str())
        .collect();
    if candidates.is_empty() {
        return None;
    }
    let entities = json(&format!(
        "{WIKIDATA}{}",
        query(&[
            ("action", "wbgetentities"),
            ("ids", &candidates.join("|")),
            ("props", "claims|labels"),
            ("languages", "en"),
            ("format", "json")
        ])
    ))?;
    let entities = &entities["entities"];
    let countries: Vec<String> = candidates
        .iter()
        .flat_map(|id| ids(&entities[*id]["claims"], "P17"))
        .collect();
    let codes = json(&format!(
        "{WIKIDATA}{}",
        query(&[
            ("action", "wbgetentities"),
            ("ids", &countries.join("|")),
            ("props", "claims"),
            ("format", "json")
        ])
    ))?;
    let ours = crate::catalogue::name_key(name);
    let ours: Vec<&str> = ours.split(' ').collect();
    let station = candidates.iter().map(|id| &entities[*id]).find(|e| {
        let label = crate::catalogue::name_key(e["labels"]["en"]["value"].as_str().unwrap_or(""));
        let label: Vec<&str> = label.split(' ').collect();
        let named = label == ours
            || (ours.len() >= 2 && label.windows(ours.len()).any(|w| w == ours.as_slice()));
        let radio = ids(&e["claims"], "P31")
            .iter()
            .any(|t| RADIO.contains(&t.as_str()));
        let here = ids(&e["claims"], "P17").iter().any(|c| {
            codes["entities"][c.as_str()]["claims"]["P297"][0]["mainsnak"]["datavalue"]["value"]
                .as_str()
                .is_some_and(|code| code.eq_ignore_ascii_case(cc))
        });
        named && radio && here
    })?;
    let file = station["claims"]["P154"][0]["mainsnak"]["datavalue"]["value"].as_str()?;
    Some(format!(
        "https://commons.wikimedia.org/wiki/Special:FilePath/{}?width=256",
        query(&[("", &file.replace(' ', "_"))]).trim_start_matches('=')
    ))
}

/// The station's site's own logo.
fn site(homepage: &str) -> Option<String> {
    let resp = agent().get(homepage).call().ok()?;
    let base = resp.get_uri().to_string();
    let mut html = String::new();
    resp.into_body()
        .into_reader()
        .take(PAGE_BYTES)
        .read_to_string(&mut html)
        .ok()?;
    best_logo(&html).map(|href| absolute(&base, &href))
}

/// A tag's attributes, names lowercase: `<link rel="icon" href=...>`.
fn attributes(tag: &str) -> HashMap<String, String> {
    let mut out = HashMap::new();
    let mut rest = tag;
    while let Some(eq) = rest.find('=') {
        let name = rest[..eq]
            .rsplit(|c: char| c.is_whitespace())
            .next()
            .unwrap_or("")
            .to_ascii_lowercase();
        let after = rest[eq + 1..].trim_start();
        let (value, tail) = if let Some(q @ ('"' | '\'')) = after.chars().next() {
            match after[1..].find(q) {
                Some(end) => (&after[1..=end], &after[end + 2..]),
                None => (&after[1..], ""),
            }
        } else {
            let end = after
                .find(|c: char| c.is_whitespace() || c == '>')
                .unwrap_or(after.len());
            (&after[..end], &after[end..])
        };
        out.insert(name, value.to_owned());
        rest = tail;
    }
    out
}

/// The address of the page's best logo, as written in it.
fn best_logo(html: &str) -> Option<String> {
    let lower = html.to_ascii_lowercase();
    let mut best: Option<(u32, String)> = None;
    let mut at = 0;
    while let Some(i) = lower[at..].find('<').map(|i| at + i) {
        let end = lower[i..].find('>').map_or(lower.len(), |e| i + e);
        let tag = &html[i..end];
        at = end.max(i + 1);
        let kind = &lower[i..end.min(i + 6)];
        if !kind.starts_with("<link") && !kind.starts_with("<meta") {
            continue;
        }
        let a = attributes(tag);
        let get = |k: &str| a.get(k).map_or("", String::as_str);
        let rel = get("rel").to_ascii_lowercase();
        let (score, href) = if rel.contains("apple-touch-icon") {
            (2, get("href"))
        } else if rel.split_whitespace().any(|r| r == "icon") {
            let size = get("sizes")
                .split(['x', 'X'])
                .next()
                .and_then(|n| n.trim().parse::<u32>().ok())
                .unwrap_or(0);
            let href = get("href");
            let vector = std::path::Path::new(href.split('?').next().unwrap_or(href))
                .extension()
                .is_some_and(|e| e.eq_ignore_ascii_case("svg"));
            if size < 96 && !vector {
                continue;
            }
            (1, href)
        } else {
            continue;
        };
        let href = href.trim();
        if href.is_empty() || href.starts_with("data:") {
            continue;
        }
        if best.as_ref().is_none_or(|(s, _)| score > *s) {
            best = Some((score, href.replace("&amp;", "&")));
        }
    }
    best.map(|(_, href)| href)
}

/// `href` as an absolute address, read against the page at `base`.
fn absolute(base: &str, href: &str) -> String {
    if href.starts_with("http://") || href.starts_with("https://") {
        return href.to_owned();
    }
    let scheme = base.split("://").next().unwrap_or("https");
    if let Some(rest) = href.strip_prefix("//") {
        return format!("{scheme}://{rest}");
    }
    let after = base.split_once("://").map_or(base, |(_, r)| r);
    let origin = after.split('/').next().unwrap_or(after);
    if href.starts_with('/') {
        return format!("{scheme}://{origin}{href}");
    }
    let path = base.split(['?', '#']).next().unwrap_or(base);
    let dir = path.rsplit_once('/').map_or(path, |(d, _)| d);
    if dir.ends_with(origin) || dir.len() <= scheme.len() + 3 {
        format!("{scheme}://{origin}/{href}")
    } else {
        format!("{dir}/{href}")
    }
}

#[cfg(test)]
mod tests {
    use super::{absolute, best_logo};

    #[test]
    fn a_site_s_phone_icon_beats_its_icons() {
        let html = r#"<head><link rel="icon" href="/favicon.ico">
            <meta property="og:image" content="https://cdn.example/share.jpg">
            <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png?v=2&amp;x=1">
            </head>"#;
        assert_eq!(
            best_logo(html).as_deref(),
            Some("/apple-touch-icon.png?v=2&x=1")
        );
    }

    #[test]
    fn a_small_favicon_or_a_share_image_is_no_logo_but_a_large_icon_is() {
        assert_eq!(
            best_logo(r#"<link rel="shortcut icon" href="/favicon.ico">"#),
            None
        );
        assert_eq!(
            best_logo(r"<LINK REL=icon sizes=192x192 HREF=/i/192.png><meta property='og:image' content='/s.jpg'>")
                .as_deref(),
            Some("/i/192.png")
        );
        assert_eq!(
            best_logo(r#"<meta property="og:image" content="/s.jpg">"#),
            None
        );
    }

    #[test]
    fn addresses_are_read_against_the_page() {
        let base = "https://www.rte.ie/2fm/listen?x=1";
        assert_eq!(absolute(base, "/logo.png"), "https://www.rte.ie/logo.png");
        assert_eq!(
            absolute(base, "//cdn.rte.ie/l.png"),
            "https://cdn.rte.ie/l.png"
        );
        assert_eq!(absolute(base, "l.png"), "https://www.rte.ie/2fm/l.png");
        assert_eq!(
            absolute("https://www.spirit.ie", "l.png"),
            "https://www.spirit.ie/l.png"
        );
        assert_eq!(absolute(base, "https://x.ie/a.png"), "https://x.ie/a.png");
    }
}
