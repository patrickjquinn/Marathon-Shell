// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Content blocking on Brave's `adblock` crate (MPL-2.0, used unmodified):
//! network rules, cosmetic (element hiding) rules and scriptlets, from
//! EasyList-format filter lists.
//!
//! - [`lists`]: the catalogue of filter lists, their download state and
//!   the cached list text.
//! - [`Blocker`]: the compiled engine. It is built off the GUI thread from
//!   the enabled lists and cached as `engine.dat` (the crate's own
//!   FlatBuffers serialisation, unchanged, so the WebProcess extension can
//!   load the same file) with `engine.json` beside it (crate version and a
//!   hash of the lists) to know when it must be rebuilt.
//! - [`stats`]: what was blocked, per page and per day.
//! - [`webkit`]: the lists as WebKit content filters: network blocking and
//!   generic element hiding, natively in the engine.
//!
//! Per-site allow list: a site with blocking turned off (site settings,
//! key `blocking`) gets no network blocking and no cosmetic filtering. The
//! hosts are also written to `allowlist.json` beside the engine for the
//! WebProcess side.
//!
//! The network match itself runs where requests are seen: in the
//! WebProcess extension of the web view (engine package), which loads
//! `engine.dat`. [`Blocker::check`] is the same match for the UI process
//! (tests, the "why was this blocked" view and engines without the
//! extension).

pub mod lists;
pub mod record;
pub mod stats;
pub mod webkit;

use std::path::{Path, PathBuf};

use adblock::lists::{FilterSet, ParseOptions};
use adblock::request::Request;
use adblock::resources::{PermissionMask, Resource};
use adblock::Engine;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::util::write_atomic;
use crate::{Error, Result};

/// The `adblock` crate version the cache was written by; a different one
/// means rebuilding (the serialisation changes between minor versions).
pub const ADBLOCK_VERSION: &str = "0.13.3";

/// The resource types a request can have, as the filter syntax names them.
pub const RESOURCE_TYPES: &[&str] = &[
    "document",
    "subdocument",
    "script",
    "stylesheet",
    "image",
    "media",
    "font",
    "xmlhttprequest",
    "websocket",
    "ping",
    "object",
    "other",
];

/// What to do with a request.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct Verdict {
    pub block: bool,
    /// A replacement body (a `redirect=` surrogate), as a data URL.
    pub redirect: Option<String>,
    /// The URL with tracking parameters removed (`removeparam`), when the
    /// request is not blocked.
    pub rewritten_url: Option<String>,
    /// The matching filter, for the "what was blocked" view.
    pub filter: Option<String>,
}

/// Element hiding and scriptlets for one page.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct Cosmetic {
    /// A stylesheet: one `selector { display: none !important; }` rule per
    /// selector, so one invalid selector only drops its own rule.
    pub css: String,
    /// Scriptlets to run in the page's main world before its own scripts.
    pub script: String,
    /// Procedural filters (JSON, one per line) for the page's interpreter.
    pub procedural: Vec<String>,
    /// `$generichide` applies to the page (its generic hiding is off).
    pub generichide: bool,
    /// Class and id selectors exempt from generic hiding on this page.
    pub exceptions: Vec<String>,
}

/// Rule text in, `display: none` rules out.
pub fn hide_css(selectors: impl IntoIterator<Item = String>) -> String {
    let mut sel: Vec<String> = selectors
        .into_iter()
        .filter(|s| !s.is_empty() && !s.contains(['{', '}']) && !s.contains("</"))
        .collect();
    sel.sort();
    let mut css = String::new();
    for s in sel {
        css.push_str(&s);
        css.push_str("{display:none!important}\n");
    }
    css
}

/// A filter list's text with how far it is trusted.
#[derive(Debug, Clone)]
pub struct ListText<'a> {
    pub id: &'a str,
    pub text: &'a str,
    /// Lists from uBlock Origin's own project may use its trusted
    /// scriptlets (`trusted-click-element` for cookie notices and the like).
    pub trusted: bool,
}

/// The compiled filter engine.
pub struct Blocker {
    engine: Engine,
    lists_hash: String,
    resources: usize,
}

impl std::fmt::Debug for Blocker {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Blocker")
            .field("lists_hash", &self.lists_hash)
            .field("resources", &self.resources)
            .finish_non_exhaustive()
    }
}

/// `engine.json`, beside `engine.dat`.
#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
struct CacheInfo {
    adblock: String,
    lists_hash: String,
}

/// A hash identifying a set of list texts (order-independent).
pub fn lists_hash(lists: &[ListText<'_>]) -> String {
    let mut parts: Vec<(String, String)> = lists
        .iter()
        .map(|l| {
            let mut h = Sha256::new();
            h.update(l.text.as_bytes());
            (format!("{}:{}", l.id, l.trusted), hex(&h.finalize()))
        })
        .collect();
    parts.sort();
    let mut h = Sha256::new();
    for (id, text) in parts {
        h.update(id.as_bytes());
        h.update([0]);
        h.update(text.as_bytes());
        h.update([0]);
    }
    hex(&h.finalize())
}

pub(crate) fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write;
    bytes
        .iter()
        .fold(String::with_capacity(bytes.len() * 2), |mut s, b| {
            let _ = write!(s, "{b:02x}");
            s
        })
}

impl Blocker {
    /// Compiles the lists (seconds for the full default set; never on the
    /// GUI thread).
    pub fn build(lists: &[ListText<'_>]) -> Self {
        let mut set = FilterSet::new(false);
        for l in lists {
            let opts = ParseOptions {
                permissions: if l.trusted {
                    PermissionMask::from_bits(1)
                } else {
                    PermissionMask::default()
                },
                ..ParseOptions::default()
            };
            set.add_filter_list(l.text.to_owned(), opts);
        }
        Self {
            engine: Engine::new_with_filter_set(set),
            lists_hash: lists_hash(lists),
            resources: 0,
        }
    }

    /// An engine that blocks nothing (before the lists are ready).
    pub fn empty() -> Self {
        Self::build(&[])
    }

    pub fn lists_hash(&self) -> &str {
        &self.lists_hash
    }

    /// Writes `engine.dat` and `engine.json` into `dir`.
    pub fn save(&self, dir: &Path) -> Result<()> {
        write_atomic(&dir.join("engine.dat"), &self.engine.serialize())?;
        let info = CacheInfo {
            adblock: ADBLOCK_VERSION.into(),
            lists_hash: self.lists_hash.clone(),
        };
        write_atomic(&dir.join("engine.json"), &serde_json::to_vec(&info)?)
    }

    /// Loads the cached engine if it was built by this crate version from
    /// lists with hash `expected_hash` (`None`: any lists).
    pub fn load(dir: &Path, expected_hash: Option<&str>) -> Result<Self> {
        let info_path = dir.join("engine.json");
        let info: CacheInfo = serde_json::from_slice(
            &std::fs::read(&info_path).map_err(|e| Error::io(&info_path, e))?,
        )?;
        if info.adblock != ADBLOCK_VERSION {
            return Err(Error::Blocker(format!(
                "cache from adblock {}",
                info.adblock
            )));
        }
        if expected_hash.is_some_and(|h| h != info.lists_hash) {
            return Err(Error::Blocker("the lists changed".into()));
        }
        let dat = dir.join("engine.dat");
        let bytes = std::fs::read(&dat).map_err(|e| Error::io(&dat, e))?;
        // A damaged file can make the deserialiser panic; never take the
        // browser down for it.
        let engine = std::panic::catch_unwind(|| {
            let mut engine = Engine::default();
            engine.deserialize(&bytes).map(|()| engine)
        })
        .map_err(|_| Error::Blocker("damaged cache".into()))?
        .map_err(|e| Error::Blocker(e.to_string()))?;
        Ok(Self {
            engine,
            lists_hash: info.lists_hash,
            resources: 0,
        })
    }

    /// Loads redirect and scriptlet resources: Brave's `adblock-resources`
    /// `resources.json` (an array of resources, content base64). Returns
    /// how many were loaded.
    pub fn use_resources_json(&mut self, json: &[u8]) -> Result<usize> {
        let resources: Vec<Resource> = serde_json::from_slice(json)?;
        let n = resources.len();
        self.engine.use_resources(resources);
        self.resources = n;
        Ok(n)
    }

    pub fn resource_count(&self) -> usize {
        self.resources
    }

    /// Matches a request made by the page `source_url`. `resource_type`
    /// is one of [`RESOURCE_TYPES`]; `allowlisted` is the page's site
    /// setting (blocking off).
    pub fn check(
        &self,
        url: &str,
        source_url: &str,
        resource_type: &str,
        method: &str,
        allowlisted: bool,
    ) -> Verdict {
        if allowlisted
            || !(url.starts_with("http:") || url.starts_with("https:") || url.starts_with("ws"))
        {
            return Verdict::default();
        }
        let Ok(req) = Request::new(url, source_url, resource_type, method) else {
            return Verdict::default();
        };
        let r = self.engine.check_network_request(&req);
        let block = r.should_block();
        Verdict {
            block,
            redirect: if block { r.redirect } else { None },
            rewritten_url: if block { None } else { r.rewritten_url },
            filter: r.filter.and_then(|f| f.raw_line),
        }
    }

    /// Element hiding and scriptlets for `page_url` (nothing when the site
    /// is allowlisted).
    pub fn cosmetic(&self, page_url: &str, allowlisted: bool) -> Cosmetic {
        if allowlisted {
            return Cosmetic {
                generichide: true,
                ..Cosmetic::default()
            };
        }
        let r = self.engine.url_cosmetic_resources(page_url);
        let mut procedural: Vec<String> = r.procedural_actions.into_iter().collect();
        procedural.sort();
        let mut exceptions: Vec<String> = r.exceptions.into_iter().collect();
        exceptions.sort();
        Cosmetic {
            css: hide_css(r.hide_selectors),
            script: r.injected_script,
            procedural,
            generichide: r.generichide,
            exceptions,
        }
    }
}

/// The directory layout of the blocker cache.
#[derive(Debug, Clone)]
pub struct BlockerDir {
    pub dir: PathBuf,
}

impl BlockerDir {
    pub fn new(dir: &Path) -> Self {
        Self {
            dir: dir.to_owned(),
        }
    }

    /// Writes the hosts with blocking turned off, for the WebProcess side.
    pub fn write_allowlist(&self, hosts: &[String]) -> Result<()> {
        write_atomic(
            &self.dir.join("allowlist.json"),
            &serde_json::to_vec(hosts)?,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const LIST: &str = r"[Adblock Plus 2.0]
! Sample list for the tests
||ads.example.com^
||tracker.example.net^$third-party
/banner/*$image
@@||ads.example.com/allowed.js$script
||cdn.example.org/lib.js$script,redirect=noop.js
example.com##.ad-slot
example.com##+js(pacific-test, hello)
##.sponsored-box
example.com#@#.sponsored-box
news.example##div[data-ad]
";

    fn blocker() -> Blocker {
        let mut b = Blocker::build(&[ListText {
            id: "sample",
            text: LIST,
            trusted: false,
        }]);
        // Brave adblock-resources format.
        let resources = br#"[
          {"name":"pacific-test.js","aliases":[],"kind":{"mime":"application/javascript"},"content":"d2luZG93LnBhY2lmaWNUZXN0ID0gJ3t7MX19Jzs="},
          {"name":"noop.js","aliases":["noopjs"],"kind":{"mime":"application/javascript"},"content":"KGZ1bmN0aW9uKCl7fSkoKTs="}
        ]"#;
        assert_eq!(b.use_resources_json(resources).unwrap(), 2);
        b
    }

    #[test]
    fn network_rules() {
        let b = blocker();
        let page = "https://example.com/article";
        assert!(
            b.check("https://ads.example.com/x.js", page, "script", "GET", false)
                .block
        );
        assert!(
            !b.check(
                "https://ads.example.com/allowed.js",
                page,
                "script",
                "GET",
                false
            )
            .block
        );
        // $third-party: blocked from another site, not from itself.
        assert!(
            b.check(
                "https://tracker.example.net/p.gif",
                page,
                "image",
                "GET",
                false
            )
            .block
        );
        assert!(
            !b.check(
                "https://tracker.example.net/p.gif",
                "https://tracker.example.net/",
                "image",
                "GET",
                false
            )
            .block
        );
        // $image only.
        assert!(
            b.check(
                "https://img.example.org/banner/1.png",
                page,
                "image",
                "GET",
                false
            )
            .block
        );
        assert!(
            !b.check(
                "https://img.example.org/banner/1.js",
                page,
                "script",
                "GET",
                false
            )
            .block
        );
        // The allow list wins.
        assert!(
            !b.check("https://ads.example.com/x.js", page, "script", "GET", true)
                .block
        );
        // Non-web schemes are never matched.
        assert!(
            !b.check("data:image/png;base64,AAAA", page, "image", "GET", false)
                .block
        );
    }

    #[test]
    fn redirect_resources() {
        let b = blocker();
        let v = b.check(
            "https://cdn.example.org/lib.js",
            "https://example.com/",
            "script",
            "GET",
            false,
        );
        assert!(v.block);
        assert!(v
            .redirect
            .as_deref()
            .is_some_and(|r| r.starts_with("data:application/javascript")));
    }

    #[test]
    fn cosmetic_rules_and_scriptlets() {
        let b = blocker();
        let c = b.cosmetic("https://example.com/page", false);
        assert!(
            c.css.contains(".ad-slot{display:none!important}"),
            "{}",
            c.css
        );
        assert!(
            c.script.contains("window.pacificTest = 'hello'"),
            "{}",
            c.script
        );
        assert!(c.exceptions.contains(&".sponsored-box".to_string()));
        let other = b.cosmetic("https://news.example/", false);
        assert!(other.css.contains("div[data-ad]"));
        assert!(!other.css.contains(".ad-slot"));
        // Generic rules are the engine's own (webkit::generic), not here.
        assert!(!other.css.contains(".sponsored-box"));
        let none = b.cosmetic("https://example.com/page", true);
        assert!(none.css.is_empty() && none.script.is_empty() && none.generichide);
    }

    #[test]
    fn cache_round_trip_and_invalidation() {
        let d = tempfile::tempdir().unwrap();
        let b = blocker();
        b.save(d.path()).unwrap();
        let hash = b.lists_hash().to_owned();
        let loaded = Blocker::load(d.path(), Some(&hash)).unwrap();
        assert!(
            loaded
                .check(
                    "https://ads.example.com/x.js",
                    "https://example.com/",
                    "script",
                    "GET",
                    false
                )
                .block
        );
        assert!(Blocker::load(d.path(), Some("other")).is_err());
        std::fs::write(d.path().join("engine.dat"), b"rubbish").unwrap();
        assert!(Blocker::load(d.path(), None).is_err());
        std::fs::write(
            d.path().join("engine.json"),
            br#"{"adblock":"0.1.0","lists_hash":"x"}"#,
        )
        .unwrap();
        assert!(Blocker::load(d.path(), None).is_err());
    }

    #[test]
    fn hashes_ignore_order() {
        let a = ListText {
            id: "a",
            text: "x",
            trusted: false,
        };
        let b = ListText {
            id: "b",
            text: "y",
            trusted: false,
        };
        assert_eq!(
            lists_hash(&[a.clone(), b.clone()]),
            lists_hash(&[b, a.clone()])
        );
        assert_ne!(
            lists_hash(std::slice::from_ref(&a)),
            lists_hash(&[ListText { trusted: true, ..a }])
        );
    }

    #[test]
    fn css_is_sane() {
        let css = hide_css(vec![
            ".a".into(),
            "#b".into(),
            "x{}".into(),
            "</style>".into(),
            String::new(),
        ]);
        assert_eq!(
            css,
            "#b{display:none!important}\n.a{display:none!important}\n"
        );
    }

    /// Brave's real resources file, when fetch-data.sh fetched it
    /// (`PACIFIC_RESOURCES_JSON`).
    #[test]
    fn real_resources_when_available() {
        let Ok(path) = std::env::var("PACIFIC_RESOURCES_JSON") else {
            return;
        };
        let mut b = Blocker::empty();
        let n = b.use_resources_json(&std::fs::read(path).unwrap()).unwrap();
        assert!(n > 10, "{n}");
    }

    #[test]
    fn empty_engine_blocks_nothing() {
        let b = Blocker::empty();
        assert!(
            !b.check(
                "https://ads.example.com/x.js",
                "https://example.com/",
                "script",
                "GET",
                false
            )
            .block
        );
    }
}
