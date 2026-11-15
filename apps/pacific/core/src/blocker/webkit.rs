// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Filter lists as WebKit content-blocker JSON.
//!
//! The web view applies network blocking and generic element hiding
//! through WebKit's own content filters (`WebProfile.compileContentFilter`):
//! compiled once into a byte-code automaton shared by every WebProcess, so
//! blocking costs no memory per tab. The network conversion is the
//! `adblock` crate's (`FilterSet::into_content_blocking`, the code Brave
//! uses for iOS). Site-specific hiding, procedural filters and scriptlets
//! stay with [`super::Blocker`]'s cosmetic pass.
//!
//! Each list becomes one or more filters of at most [`MAX_RULES`] rules
//! (`pacific-<list>-<n>`), each ending with an `ignore-previous-rules`
//! rule for the sites where the person turned blocking off.
//!
//! Generic element hiding (`##.ad`, no domain) is gathered from all the
//! lists into filters of its own (`pacific-generic-<n>`, [`generic`]), as
//! Safari content blockers do: the selectors joined into groups of
//! [`SELECTORS_PER_RULE`], one `css-display-none` rule per group, which
//! WebKit compiles into one user stylesheet. Exceptions are kept:
//! `site#@#.ad` takes the selector out of its group into a rule with
//! `unless-domain`, `#@#.ad` drops it, `@@||site^$generichide` and the
//! person's allow list end the filter with `ignore-previous-rules`. The
//! crate's own hiding rules are dropped from the lists' filters: they come
//! before its closing `ignore-previous-rules` for first-party documents,
//! which voids every one of them in WebKit; it also gives one rule per
//! selector and turns `site#@#.ad` (and rules for `site.*`) into "hide
//! everywhere but on this site".

use std::collections::{BTreeMap, BTreeSet};

use adblock::filters::cosmetic::{CosmeticFilter, CosmeticFilterMask};
use adblock::lists::{FilterSet, ParseOptions};
use adblock::resources::PermissionMask;
use serde_json::{json, Value};

use super::ListText;
use crate::{Error, Result};

/// Rules per compiled filter (WebKit compiles larger ones, but slowly and
/// with a big peak of memory on a phone).
pub const MAX_RULES: usize = 50_000;

/// Selectors joined into one generic hiding rule. WebKit drops a rule
/// whose selector it cannot parse, so a bad selector costs its group;
/// [`usable_selector`] keeps out what WebKit is known to refuse.
pub const SELECTORS_PER_RULE: usize = 250;

/// Changes whenever the conversion gives different JSON for the same
/// lists, so filters recorded by an older version are converted again.
pub const FORMAT: &str = "2";

/// One content filter to compile.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ContentFilter {
    pub identifier: String,
    pub json: String,
    pub rules: usize,
}

/// The allow-list rule for `hosts` (none when empty).
fn allow_rule(hosts: &[String]) -> Option<Value> {
    if hosts.is_empty() {
        return None;
    }
    let domains: Vec<String> = hosts
        .iter()
        .map(|h| format!("*{}", h.to_ascii_lowercase()))
        .collect();
    Some(json!({
        "trigger": { "url-filter": ".*", "if-domain": domains },
        "action": { "type": "ignore-previous-rules" }
    }))
}

/// Converts one list into content filters.
pub fn convert(
    list: &ListText<'_>,
    allowlist: &[String],
    max_rules: usize,
) -> Result<Vec<ContentFilter>> {
    let mut set = FilterSet::new(true);
    let opts = ParseOptions {
        permissions: if list.trusted {
            PermissionMask::from_bits(1)
        } else {
            PermissionMask::default()
        },
        ..ParseOptions::default()
    };
    set.add_filter_list(list.text.to_owned(), opts);
    let (rules, _) = set.into_content_blocking().map_err(|()| {
        Error::Blocker(format!(
            "{}: cannot convert to content-blocker rules",
            list.id
        ))
    })?;
    // No hiding rules: the crate puts them before its closing rule
    // (`ignore-previous-rules` for first-party documents), which voids
    // them all, and the page's own hiding comes from [`super::Blocker`]
    // (site rules) and [`generic`].
    let rules: Vec<Value> = rules
        .into_iter()
        .filter_map(|r| serde_json::to_value(r).ok())
        .filter(|r| r["action"]["type"] != "css-display-none")
        .collect();
    let max = max_rules.max(1);
    let allow = allow_rule(allowlist);
    let mut out = Vec::new();
    for (n, chunk) in rules.chunks(max).enumerate() {
        let mut v: Vec<Value> = chunk.to_vec();
        let count = v.len();
        if let Some(a) = &allow {
            v.push(a.clone());
        }
        out.push(ContentFilter {
            identifier: format!("pacific-{}-{}", list.id, n + 1),
            json: serde_json::to_string(&v)?,
            rules: count,
        });
    }
    Ok(out)
}

/// All enabled lists, converted, then their generic hiding.
pub fn convert_all(lists: &[ListText<'_>], allowlist: &[String]) -> Vec<ContentFilter> {
    let mut out = Vec::new();
    for l in lists {
        match convert(l, allowlist, MAX_RULES) {
            Ok(f) => out.extend(f),
            Err(e) => log::warn!("{e}"),
        }
    }
    match generic(
        &GenericHiding::gather(lists),
        allowlist,
        SELECTORS_PER_RULE,
        MAX_RULES,
    ) {
        Ok(f) => out.extend(f),
        Err(e) => log::warn!("generic hiding: {e}"),
    }
    out
}

/// The generic element hiding of a set of lists.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct GenericHiding {
    /// `##sel`: hidden on every site.
    pub everywhere: BTreeSet<String>,
    /// `~site##sel`: hidden on every site but these.
    pub except_on: BTreeMap<String, BTreeSet<String>>,
    /// `site#@#sel`: not hidden on these sites.
    pub exceptions: BTreeMap<String, BTreeSet<String>>,
    /// `#@#sel`: not hidden anywhere.
    pub unhidden: BTreeSet<String>,
    /// `@@||site^$generichide`: no generic hiding on these sites.
    pub generichide: BTreeSet<String>,
}

/// Whether WebKit can take `selector` in a content-blocker rule: ASCII
/// (the crate's rule too), no braces or comments (one rule's text cannot
/// end another's), no procedural operators.
pub fn usable_selector(selector: &str) -> bool {
    !selector.is_empty()
        && selector.len() <= 1000
        && selector.is_ascii()
        && !selector.contains(['{', '}'])
        && !selector.contains("/*")
        && !PROCEDURAL.iter().any(|p| selector.contains(p))
}

/// uBlock Origin's and Adblock Plus's operators that are not CSS (the
/// crate, without its CSS validation, can take them for plain selectors).
const PROCEDURAL: &[&str] = &[
    ":-abp-",
    ":contains(",
    ":has-text(",
    ":if(",
    ":if-not(",
    ":matches-attr(",
    ":matches-css",
    ":matches-media(",
    ":matches-path(",
    ":matches-prop(",
    ":min-text-length(",
    ":nth-ancestor(",
    ":others(",
    ":remove",
    ":shadow(",
    ":spath(",
    ":style(",
    ":upward(",
    ":watch-attr(",
    ":xpath(",
];

/// The sites before `#` in a rule (`a.com,~b.com##x`): (sites, negated
/// sites), lower case. `None` when one is an entity (`site.*`), which
/// WebKit's `if-domain` cannot express.
fn rule_sites(prefix: &str) -> Option<(Vec<String>, Vec<String>)> {
    let (mut on, mut off) = (Vec::new(), Vec::new());
    for part in prefix.split(',').map(str::trim).filter(|p| !p.is_empty()) {
        let (list, site) = match part.strip_prefix('~') {
            Some(s) => (&mut off, s),
            None => (&mut on, part),
        };
        if site.ends_with(".*") || site.contains(['*', '/', ' ']) {
            return None;
        }
        list.push(site.to_ascii_lowercase());
    }
    Some((on, off))
}

/// The sites of `@@||site^$generichide` (or `$ghide`, and their
/// `domain=` option): whole sites only, no entities.
fn generichide_sites(line: &str) -> Vec<String> {
    let Some(rest) = line.strip_prefix("@@") else {
        return Vec::new();
    };
    let Some((pattern, options)) = rest.rsplit_once('$') else {
        return Vec::new();
    };
    let options: Vec<&str> = options.split(',').collect();
    if !options.iter().any(|o| *o == "generichide" || *o == "ghide") {
        return Vec::new();
    }
    let mut sites = Vec::new();
    if let Some(host) = pattern
        .strip_prefix("||")
        .and_then(|p| p.strip_suffix('^').or(Some(p)))
    {
        if !host.is_empty()
            && host
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-')
        {
            sites.push(host.to_ascii_lowercase());
        }
    }
    let whole = pattern.is_empty() || pattern == "*";
    for o in options {
        if let (true, Some(domains)) = (whole, o.strip_prefix("domain=")) {
            sites.extend(
                domains
                    .split('|')
                    .filter(|d| !d.starts_with('~') && !d.ends_with(".*") && !d.is_empty())
                    .map(str::to_ascii_lowercase),
            );
        }
    }
    sites
}

impl GenericHiding {
    /// Reads the generic hiding rules and their exceptions from `lists`.
    pub fn gather(lists: &[ListText<'_>]) -> Self {
        let mut g = Self::default();
        for l in lists {
            for line in l.text.lines().map(str::trim) {
                if line.starts_with('!') || line.starts_with('[') {
                    continue;
                }
                if line.starts_with("@@") {
                    g.generichide.extend(generichide_sites(line));
                    continue;
                }
                if let Some(sel) = line.strip_prefix("#@#") {
                    g.unhidden.insert(sel.trim().to_owned());
                    continue;
                }
                let Some(sharp) = line.find('#') else {
                    continue;
                };
                let rest = &line[sharp..];
                if !(rest.starts_with("##") || rest.starts_with("#@#")) {
                    continue;
                }
                let Ok(f) = CosmeticFilter::parse(line, false, PermissionMask::default()) else {
                    continue;
                };
                if f.action.is_some() || f.mask.contains(CosmeticFilterMask::SCRIPT_INJECT) {
                    continue;
                }
                let Some(sel) = f.plain_css_selector() else {
                    continue;
                };
                let Some((on, off)) = rule_sites(&line[..sharp]) else {
                    continue;
                };
                if f.mask.contains(CosmeticFilterMask::UNHIDE) {
                    if !on.is_empty() {
                        g.exceptions.entry(sel.to_owned()).or_default().extend(on);
                    }
                } else if on.is_empty() && off.is_empty() {
                    g.everywhere.insert(sel.to_owned());
                } else if on.is_empty() {
                    g.except_on.entry(sel.to_owned()).or_default().extend(off);
                }
            }
        }
        g
    }

    /// The rules: groups of selectors hidden everywhere, then one rule per
    /// selector with sites excepted.
    pub fn rules(&self, per_rule: usize) -> Vec<Value> {
        let unless = |sites: &BTreeSet<String>| -> Vec<String> {
            sites.iter().map(|s| format!("*{s}")).collect()
        };
        let mut plain = Vec::new();
        let mut excepted: BTreeMap<&str, BTreeSet<String>> = BTreeMap::new();
        for sel in &self.everywhere {
            if self.unhidden.contains(sel) || !usable_selector(sel) {
                continue;
            }
            match self.exceptions.get(sel) {
                Some(sites) => {
                    excepted.insert(sel, sites.clone());
                }
                None => plain.push(sel.as_str()),
            }
        }
        for (sel, off) in &self.except_on {
            if self.everywhere.contains(sel) || self.unhidden.contains(sel) || !usable_selector(sel)
            {
                continue;
            }
            let mut sites = off.clone();
            if let Some(more) = self.exceptions.get(sel) {
                sites.extend(more.iter().cloned());
            }
            excepted.insert(sel, sites);
        }
        let mut out: Vec<Value> = plain
            .chunks(per_rule.max(1))
            .map(|group| {
                json!({
                    "trigger": { "url-filter": ".*" },
                    "action": { "type": "css-display-none", "selector": group.join(", ") }
                })
            })
            .collect();
        out.extend(excepted.into_iter().map(|(sel, sites)| {
            json!({
                "trigger": { "url-filter": ".*", "unless-domain": unless(&sites) },
                "action": { "type": "css-display-none", "selector": sel }
            })
        }));
        out
    }
}

/// The generic hiding filters (`pacific-generic-<n>`), each ending with
/// `ignore-previous-rules` for the `$generichide` sites and the allow list.
pub fn generic(
    g: &GenericHiding,
    allowlist: &[String],
    per_rule: usize,
    max_rules: usize,
) -> Result<Vec<ContentFilter>> {
    let rules = g.rules(per_rule);
    let mut off: Vec<String> = g.generichide.iter().cloned().collect();
    off.extend(allowlist.iter().map(|h| h.to_ascii_lowercase()));
    off.sort();
    off.dedup();
    let allow = allow_rule(&off);
    let mut out = Vec::new();
    for (n, chunk) in rules.chunks(max_rules.max(1)).enumerate() {
        let mut v: Vec<Value> = chunk.to_vec();
        let count = v.len();
        if let Some(a) = &allow {
            v.push(a.clone());
        }
        out.push(ContentFilter {
            identifier: format!("pacific-generic-{}", n + 1),
            json: serde_json::to_string(&v)?,
            rules: count,
        });
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    const LIST: &str = "||ads.example.com^\n||tracker.example.net^$third-party,script\nexample.com##.ad-slot\n##.sponsored\n@@||ads.example.com/ok.js\n";

    #[test]
    fn converts_network_and_hiding_rules() {
        let l = ListText {
            id: "sample",
            text: LIST,
            trusted: false,
        };
        let f = convert(&l, &[], MAX_RULES).unwrap();
        assert_eq!(f.len(), 1);
        assert_eq!(f[0].identifier, "pacific-sample-1");
        let v: Vec<Value> = serde_json::from_str(&f[0].json).unwrap();
        let text = f[0].json.as_str();
        assert!(
            text.contains("ads\\\\.example\\\\.com") || text.contains("ads\\.example\\.com"),
            "{text}"
        );
        assert!(v.iter().any(|r| r["action"]["type"] == "block"));
        // Hiding is not in the list's filter (the crate's closing rule
        // would void it): site rules are injected per page, generic ones
        // are in the generic filter.
        assert!(!v.iter().any(|r| r["action"]["type"] == "css-display-none"));
        assert!(v
            .iter()
            .any(|r| r["action"]["type"] == "ignore-previous-rules"));
        assert_eq!(f[0].rules, v.len());
    }

    /// A real EasyList, when one is around (`PACIFIC_EASYLIST`): converts,
    /// and every filter is valid JSON with an action and a trigger.
    #[test]
    fn real_list_when_available() {
        let Ok(path) = std::env::var("PACIFIC_EASYLIST") else {
            return;
        };
        let text = std::fs::read_to_string(path).unwrap();
        let t = std::time::Instant::now();
        let f = convert(
            &ListText {
                id: "easylist",
                text: &text,
                trusted: false,
            },
            &[],
            MAX_RULES,
        )
        .unwrap();
        let rules: usize = f.iter().map(|c| c.rules).sum();
        eprintln!(
            "easylist: {rules} rules in {} filters, {:?}",
            f.len(),
            t.elapsed()
        );
        assert!(rules > 10_000);
        for c in &f {
            let v: Vec<Value> = serde_json::from_str(&c.json).unwrap();
            assert!(
                v.iter()
                    .all(|r| r["action"]["type"].is_string()
                        && r["trigger"]["url-filter"].is_string())
            );
        }
        let lists = [ListText {
            id: "easylist",
            text: &text,
            trusted: false,
        }];
        let g = generic(
            &GenericHiding::gather(&lists),
            &[],
            SELECTORS_PER_RULE,
            MAX_RULES,
        )
        .unwrap();
        let hiding: usize = g.iter().map(|c| c.rules).sum();
        eprintln!(
            "easylist: {} generic selectors in {hiding} rules",
            GenericHiding::gather(&lists).everywhere.len()
        );
        assert!(hiding > 10 && hiding < 2_000);
        let t = std::time::Instant::now();
        let b = super::super::Blocker::build(&[ListText {
            id: "easylist",
            text: &text,
            trusted: false,
        }]);
        eprintln!("engine build {:?}", t.elapsed());
        assert!(
            b.check(
                "https://securepubads.g.doubleclick.net/gpt/pubads_impl.js",
                "https://news.example/",
                "script",
                "GET",
                false
            )
            .block
        );
    }

    const GENERIC: &str = "##.ad-a\n##.ad-b\n###top-ad\n##div[data-ad] > .x\nnews.example#@#.ad-b\nother.example,third.example#@#.ad-b\n#@#.ad-gone\n##.ad-gone\n~shop.example##.promo\nshop.example##.site-only\nsite.*##.entity-only\n~site.*##.entity-neg\n##.ad-x:has-text(Sponsored)\n##.ad-styled:style(color: red)\n##.caf\u{e9}\n@@||quiet.example^$generichide\n@@*$ghide,domain=one.example|two.*|~three.example\n@@||partial.example/path^$generichide\n";

    fn generic_rules(text: &str, per_rule: usize, allow: &[String]) -> Vec<Value> {
        let l = ListText {
            id: "g",
            text,
            trusted: false,
        };
        let f = generic(&GenericHiding::gather(&[l]), allow, per_rule, MAX_RULES).unwrap();
        assert_eq!(f.len(), 1);
        assert_eq!(f[0].identifier, "pacific-generic-1");
        serde_json::from_str(&f[0].json).unwrap()
    }

    #[test]
    fn generic_hiding_in_groups() {
        let v = generic_rules(GENERIC, 2, &["Mine.example".to_string()]);
        let groups: Vec<&str> = v
            .iter()
            .filter(|r| {
                r["trigger"].get("unless-domain").is_none()
                    && r["action"]["type"] == "css-display-none"
            })
            .map(|r| {
                assert_eq!(r["trigger"]["url-filter"], ".*");
                r["action"]["selector"].as_str().unwrap()
            })
            .collect();
        // Sorted, two per rule; the excepted, unhidden, procedural,
        // styled, site-only, entity and non-ASCII rules are not grouped.
        assert_eq!(groups, ["#top-ad, .ad-a", "div[data-ad] > .x"]);
        let excepted: Vec<(&str, Vec<&str>)> = v
            .iter()
            .filter_map(|r| {
                let sites = r["trigger"].get("unless-domain")?.as_array()?;
                Some((
                    r["action"]["selector"].as_str()?,
                    sites.iter().filter_map(Value::as_str).collect(),
                ))
            })
            .collect();
        assert_eq!(
            excepted,
            [
                (
                    ".ad-b",
                    vec!["*news.example", "*other.example", "*third.example"]
                ),
                (".promo", vec!["*shop.example"]),
            ]
        );
        // Last: no generic hiding on $generichide sites and the allow list.
        let last = v.last().unwrap();
        assert_eq!(last["action"]["type"], "ignore-previous-rules");
        assert_eq!(
            last["trigger"]["if-domain"],
            json!(["*mine.example", "*one.example", "*quiet.example"])
        );
        assert!(!v.iter().any(|r| r.to_string().contains("entity")
            || r.to_string().contains("site-only")
            || r.to_string().contains("ad-gone")
            || r.to_string().contains("has-text")
            || r.to_string().contains("styled")));
    }

    #[test]
    fn generic_hiding_without_exceptions_or_rules() {
        let v = generic_rules("##.a\n##.b\n##.c\n", 250, &[]);
        assert_eq!(v.len(), 1);
        assert_eq!(v[0]["action"]["selector"], ".a, .b, .c");
        assert!(generic(&GenericHiding::default(), &[], 250, MAX_RULES)
            .unwrap()
            .is_empty());
    }

    #[test]
    fn selectors_webkit_cannot_take() {
        assert!(usable_selector("div[class^=\"ad-\"] > a"));
        assert!(usable_selector(".a\\:b"));
        for bad in [
            "",
            "a{}",
            "a}b{",
            "x/*",
            ".caf\u{e9}",
            "a:-abp-has(b)",
            "a:style(x)",
            "a:remove()",
        ] {
            assert!(!usable_selector(bad), "{bad}");
        }
    }

    #[test]
    fn chunks_and_allowlist() {
        let many = (0..25)
            .map(|i| format!("||ads{i}.example^"))
            .collect::<Vec<_>>()
            .join("\n");
        let l = ListText {
            id: "big",
            text: &many,
            trusted: false,
        };
        let f = convert(&l, &["News.example".to_string()], 10).unwrap();
        assert_eq!(f.len(), 3);
        assert!(f.iter().map(|c| c.rules).sum::<usize>() >= 25);
        for c in &f {
            let v: Vec<Value> = serde_json::from_str(&c.json).unwrap();
            let last = v.last().unwrap();
            assert_eq!(last["action"]["type"], "ignore-previous-rules");
            assert_eq!(last["trigger"]["if-domain"][0], "*news.example");
        }
        // The list's filter only: it has no generic hiding.
        assert_eq!(convert_all(&[l], &[]).len(), 1);
    }
}
