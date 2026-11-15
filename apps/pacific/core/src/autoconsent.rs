// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Cookie-banner rejection with DuckDuckGo's autoconsent (MPL-2.0).
//!
//! The package bundles the library's self-initialising standalone build
//! (`autoconsent.standalone.js`, pinned by version and SHA-256 in
//! `data/versions.env`, as Atlantic's `versions.env` does) at
//! `/usr/share/shipwright-pacific/autoconsent/autoconsent.js`. The file is
//! checked against the pin before it is used: unknown code is never
//! injected into every page. It runs in each page's main world from
//! document start (as DuckDuckGo's browsers inject it, so its hiding of the
//! consent managers it knows is in place before one draws), finds the
//! consent dialog (hundreds of known CMPs plus heuristics)
//! and answers it with "reject all" (`autoAction: optOut`, the library's
//! default).
//!
//! The standalone build reports through `console.log`. Forwarding every
//! page's console to the app only to find those lines costs every page a
//! wrapped console and a message per call, so [`prepare`] also makes it
//! post its reports to the script message handler [`HANDLER`] (registered
//! in the page's world, every frame); [`parse_report`] turns them into
//! events for the per-page protection summary. Its verbose lifecycle
//! logging is switched off when the script is loaded.

use sha2::{Digest, Sha256};

use crate::{Error, Result};

const VERSIONS: &str = include_str!("../data/versions.env");

/// A value from `data/versions.env`.
pub fn pin(key: &str) -> &'static str {
    VERSIONS
        .lines()
        .find_map(|l| l.strip_prefix(key)?.strip_prefix('='))
        .unwrap_or("")
}

pub fn version() -> &'static str {
    pin("AUTOCONSENT_VERSION")
}

/// Where the package installs the script.
pub const INSTALLED_PATH: &str = "/usr/share/shipwright-pacific/autoconsent/autoconsent.js";

/// The script message handler autoconsent reports to (in the page's own
/// world): `{type, cmp, result}`.
pub const HANDLER: &str = "shipConsent";

/// Where the standalone build hands each of its messages to its logger.
const SEND_HOOK: &str = "messages.push(message);\n      logMessage(message);";

/// Reads and checks the bundled script and returns the text to inject.
pub fn load(path: &std::path::Path) -> Result<String> {
    let bytes = std::fs::read(path).map_err(|e| Error::io(path, e))?;
    prepare(&bytes)
}

/// Checks `bytes` against the pinned hash and quiets the logging.
pub fn prepare(bytes: &[u8]) -> Result<String> {
    let sha = crate::blocker::hex(&Sha256::digest(bytes));
    if sha != pin("AUTOCONSENT_JS_SHA256") {
        return Err(Error::Invalid(format!(
            "autoconsent.js does not match the pinned {} build",
            version()
        )));
    }
    let text = String::from_utf8(bytes.to_vec())
        .map_err(|_| Error::Invalid("autoconsent.js is not UTF-8".into()))?;
    let mut out = report_to_handler(&lighten(&quiet(&text)))?;
    out.push('\n');
    out.push_str(EXTRA_RULES_JS);
    Ok(out)
}

/// Pacific's own answers to consent screens autoconsent's rules miss (seen
/// on the Jolla Phone): Google's and `YouTube`'s in-page "Before you continue"
/// dialog, and the BBC's banner. Each says "reject" and reports to
/// [`HANDLER`] as autoconsent does, so the page counts it.
pub const EXTRA_RULES_JS: &str = r#"(function () {
  if (window !== window.top || window.__pacificConsentExtra) return;
  window.__pacificConsentExtra = true;
  var host = location.hostname;
  function report(cmp) {
    try { window.webkit.messageHandlers.shipConsent.postMessage({ type: 'autoconsentDone', cmp: cmp, result: true }); } catch (e) {}
  }
  // BBC: its banner reads ckns_explicit and ckns_policy (functional,
  // performance, advertising). Explicit, all off: the banner never shows.
  if (/(^|\.)bbc\.(co\.uk|com)$/.test(host)) {
    if (!/(^|; )ckns_explicit=/.test(document.cookie)) {
      var domain = host.indexOf('bbc.com') >= 0 ? '.bbc.com' : '.bbc.co.uk';
      var age = '; max-age=31536000; path=/; domain=' + domain + '; samesite=lax';
      document.cookie = 'ckns_policy=000' + age;
      document.cookie = 'ckns_explicit=2' + age;
      report('bbc');
    }
    return;
  }
  // Google and YouTube: the consent dialog's "Reject all" button.
  if (!/(^|\.)(google\.[a-z.]+|youtube\.com)$/.test(host)) return;
  var done = false;
  function tryReject() {
    if (done) return true;
    var buttons = document.querySelectorAll('button, [role="button"], input[type="submit"]');
    for (var i = 0; i < buttons.length; i++) {
      var b = buttons[i];
      var label = ((b.getAttribute('aria-label') || '') + ' ' + (b.textContent || b.value || '')).trim();
      if (/^(Reject all|Alle ablehnen|Tout refuser|Rechazar todo|Rifiuta tutto|Alles afwijzen|Hylkää kaikki|Odrzuć wszystko|Rejeitar tudo|Avvisa alla|Afvis alle|Avvis alle)/i.test(label)
          && b.offsetParent !== null) {
        done = true;
        b.click();
        report(host.indexOf('youtube') >= 0 ? 'youtube' : 'google');
        return true;
      }
    }
    return false;
  }
  if (tryReject()) return;
  var observer = new MutationObserver(function () { if (tryReject()) observer.disconnect(); });
  observer.observe(document.documentElement, { childList: true, subtree: true });
  setTimeout(function () { observer.disconnect(); }, 15000);
})();"#;

/// Makes the standalone build post its results to [`HANDLER`] as well as
/// logging them.
pub fn report_to_handler(text: &str) -> Result<String> {
    if !text.contains(SEND_HOOK) {
        return Err(Error::Invalid(
            "autoconsent.js has no message hook to report through".into(),
        ));
    }
    let post = format!(
        "{SEND_HOOK}\n      if (/^(cmpDetected|optOutResult|autoconsentDone)$/.test(message.type)) {{ try {{ window.webkit.messageHandlers.{HANDLER}.postMessage({{ type: message.type, cmp: String(message.cmp || ''), result: message.result === true }}); }} catch (e) {{}} }}"
    );
    Ok(text.replacen(SEND_HOOK, &post, 1))
}

/// Turns the standalone build's lifecycle, rule-step and wait logging off
/// (its own configuration block, after `standalone/content.ts`). The
/// result lines ([`parse_console`]) stay.
pub fn quiet(text: &str) -> String {
    let Some(start) = text.find("// standalone/content.ts") else {
        return text.to_owned();
    };
    let (head, tail) = text.split_at(start);
    let tail = tail
        .replacen("lifecycle: true", "lifecycle: false", 1)
        .replacen("rulesteps: true", "rulesteps: false", 1)
        .replacen("waits: true", "waits: false", 1);
    format!("{head}{tail}")
}

/// Makes the standalone build cheaper on every page (its configuration
/// block, as [`quiet`]). Measured on the Jolla Phone, it cost the page's main
/// thread 0.5-1 s of each load, even with no banner on the page:
/// - `enableHeuristicDetection` read `document.documentElement.innerText`
///   (a layout and the whole page's text) on every attempt, only to record
///   wording patterns for reports; the heuristic that finds and answers
///   banners (`heuristicMode`) does not use it, so it is off.
/// - Up to 20 attempts, every 500 ms or at each change to the page, ran
///   every rule's checks for ten seconds and more on pages that keep
///   changing; banners appear within a few seconds of loading, so 10.
/// - Its visibility test read `offsetParent`, a layout of the page each time
///   the page had changed; the heuristic asks it of every element on the
///   page, every other attempt, and that was most of the cost.
///   `checkVisibility()` gives the same answer from styles alone: false
///   with no box, true for a fixed element (`offsetParent` is null for one,
///   and the test then took `position: fixed` as visible). Only `<body>` and
///   `<html>` differ, now visible; the heuristic skips both (it asks of
///   `<body>` only in a frame, and runs only in the top one).
/// - Its hiding rules read and wrote the `innerText` of its `<style>`
///   elements; reading it lays out the page. `textContent` is the same text.
/// - It hides the consent managers it knows while it looks for them, and
///   shows them again after `prehideTimeout` (2 s) if it has not started
///   answering: on a phone that is too short for a heavy page, so The
///   Verge's dialog was hidden, came back, and went again as it was
///   rejected. 8 s, longer than its ten attempts.
pub fn lighten(text: &str) -> String {
    let text = text.replace("styleEl.innerText", "styleEl.textContent");
    let text = text.replacen(
        "if (elem.offsetParent !== null) {",
        "if (elem.checkVisibility ? elem.checkVisibility() : elem.offsetParent !== null) {",
        1,
    );
    let Some(start) = text.find("// standalone/content.ts") else {
        return text;
    };
    let (head, tail) = text.split_at(start);
    let tail = tail.replacen(
        "enableHeuristicDetection: true,",
        "enableHeuristicDetection: false,\n      detectRetries: 10,\n      prehideTimeout: 8e3,",
        1,
    );
    format!("{head}{tail}")
}

/// What autoconsent reported.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    /// A consent manager was found on the page.
    Detected { cmp: String },
    /// The dialog was answered ("reject all").
    Done { cmp: String },
    /// Answering failed.
    Failed { cmp: String },
}

/// Parses one report posted to [`HANDLER`] (as JSON). The page can post
/// to the handler too, so nothing in it is trusted beyond a count.
pub fn parse_report(json: &str) -> Option<Event> {
    #[derive(serde::Deserialize)]
    struct Report {
        #[serde(rename = "type")]
        kind: String,
        #[serde(default)]
        cmp: String,
        #[serde(default)]
        result: bool,
    }
    let r: Report = serde_json::from_str(json).ok()?;
    let cmp: String = r.cmp.chars().take(80).collect();
    match r.kind.as_str() {
        "autoconsentDone" => Some(Event::Done { cmp }),
        "cmpDetected" => Some(Event::Detected { cmp }),
        "optOutResult" if !r.result => Some(Event::Failed { cmp }),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pins_are_present() {
        assert_eq!(version(), "16.45.0");
        assert_eq!(pin("AUTOCONSENT_JS_SHA256").len(), 64);
        assert!(pin("AUTOCONSENT_URL").ends_with("autoconsent-16.45.0.tgz"));
        assert_eq!(pin("NOPE"), "");
    }

    #[test]
    fn refuses_unpinned_code() {
        assert!(prepare(b"alert('not autoconsent')").is_err());
        let d = tempfile::tempdir().unwrap();
        assert!(load(&d.path().join("missing.js")).is_err());
    }

    #[test]
    fn quiets_only_the_standalone_block() {
        let js = "logs: { lifecycle: true }\n// standalone/content.ts\nlogs: { lifecycle: true, rulesteps: true, waits: true }";
        let q = quiet(js);
        assert!(q.starts_with("logs: { lifecycle: true }"));
        assert!(q.ends_with("logs: { lifecycle: false, rulesteps: false, waits: false }"));
        assert_eq!(quiet("no marker"), "no marker");
    }

    #[test]
    fn lightens_only_the_standalone_block() {
        let js = "enableHeuristicDetection: true,\n// standalone/content.ts\n    const config = {\n      enableHeuristicDetection: true,\n";
        let l = lighten(js);
        assert!(l.starts_with("enableHeuristicDetection: true,"));
        assert!(l.contains("enableHeuristicDetection: false,\n      detectRetries: 10,\n      prehideTimeout: 8e3,"));
        assert_eq!(lighten("no marker"), "no marker");
    }

    #[test]
    fn reports() {
        assert_eq!(
            parse_report(r#"{"type":"autoconsentDone","cmp":"Sourcepoint-frame","result":false}"#),
            Some(Event::Done {
                cmp: "Sourcepoint-frame".into()
            })
        );
        assert_eq!(
            parse_report(r#"{"type":"cmpDetected","cmp":"onetrust"}"#),
            Some(Event::Detected {
                cmp: "onetrust".into()
            })
        );
        assert_eq!(
            parse_report(r#"{"type":"optOutResult","cmp":"onetrust","result":false}"#),
            Some(Event::Failed {
                cmp: "onetrust".into()
            })
        );
        assert_eq!(
            parse_report(r#"{"type":"optOutResult","cmp":"onetrust","result":true}"#),
            None
        );
        assert_eq!(parse_report(r#"{"type":"popupFound"}"#), None);
        assert_eq!(parse_report("autoconsent done: x"), None);
        assert_eq!(parse_report("null"), None);
    }

    #[test]
    fn reports_go_to_the_handler() {
        let js = "const sendMessage = async (message) => {\n      messages.push(message);\n      logMessage(message);\n    };";
        let out = report_to_handler(js).unwrap();
        assert!(out.contains("logMessage(message);"));
        assert!(out.contains("window.webkit.messageHandlers.shipConsent.postMessage"));
        assert_eq!(out.matches("postMessage").count(), 1);
        assert!(report_to_handler("no hook here").is_err());
    }

    /// The real pinned build, when the scratch copy prebuild.sh fetched is
    /// around (`PACIFIC_AUTOCONSENT_JS`).
    #[test]
    fn real_build_when_available() {
        let Ok(path) = std::env::var("PACIFIC_AUTOCONSENT_JS") else {
            return;
        };
        let js = load(std::path::Path::new(&path)).unwrap();
        assert!(js.contains("autoconsentReceiveMessage"));
        assert!(js.contains("lifecycle: false"));
        assert!(js.contains("enableHeuristicDetection: false,\n      detectRetries: 10,"));
        assert!(js.contains("elem.checkVisibility ? elem.checkVisibility()"));
        assert!(!js.contains("if (elem.offsetParent !== null) {"));
        assert!(js.contains("styleEl.textContent += rule;"));
        assert!(!js.contains("styleEl.innerText"));
        assert!(js.contains("messageHandlers.shipConsent.postMessage"));
    }
}
