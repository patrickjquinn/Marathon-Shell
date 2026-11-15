// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Pacific's Keel Actions declarations (ui/qml/actions/PacificActions.qml)
//! through Keel's own generator and Reef's review rules, plus Pacific's
//! safety promises: what must be confirmed, destructive, read-only, and
//! that page content is marked untrusted.

use std::path::PathBuf;

use serde_json::Value;

fn manifest() -> Value {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..");
    let out = keel_actions_codegen::Config {
        qml: vec![root.join("ui/qml")],
        desktop: Some(root.join("app/packaging/shipwright-pacific.desktop")),
        ..Default::default()
    }
    .generate()
    .unwrap_or_else(|e| panic!("{e}"));
    assert!(
        out.diagnostics.warnings.is_empty(),
        "{:?}",
        out.diagnostics.warnings
    );
    out.manifest
}

fn tool<'a>(m: &'a Value, name: &str) -> &'a Value {
    m["tools"]
        .as_array()
        .unwrap()
        .iter()
        .find(|t| t["name"] == format!("org.shipwright.pacific/{name}"))
        .unwrap_or_else(|| panic!("no tool {name}"))
}

#[test]
fn passes_reef_review() {
    let m = manifest();
    let findings = keel_actions_schema::review::review(&m, Some("org.shipwright.pacific"));
    assert!(
        findings.is_empty(),
        "{}",
        findings
            .iter()
            .map(ToString::to_string)
            .collect::<Vec<_>>()
            .join("\n")
    );
}

#[test]
fn declares_the_browser_surface() {
    let m = manifest();
    for name in [
        "browser.open",
        "browser.search",
        "tabs.list",
        "tabs.switch",
        "tabs.close",
        "page.read",
        "page.find",
        "page.links",
        "page.click",
        "page.fill",
        "page.submit",
        "page.scroll",
        "page.screenshot",
        "browse.open",
        "browse.show",
        "browse.close",
        "bookmarks.add",
        "bookmarks.find",
        "history.search",
        "downloads.list",
        // Entity finders.
        "tab.find",
        "bookmark.find",
        "history.find",
    ] {
        tool(&m, name);
    }
    assert_eq!(m["appId"], "org.shipwright.pacific");
    assert_eq!(m["context"]["uri"], "keel://org.shipwright.pacific/context");
}

#[test]
fn acting_on_pages_is_always_confirmed() {
    let m = manifest();
    for name in ["page.click", "page.fill", "page.submit"] {
        let t = tool(&m, name);
        assert_eq!(t["_meta"]["org.shipwright.keel/confirm"], true, "{name}");
        assert_eq!(t["annotations"]["readOnlyHint"], false, "{name}");
    }
    assert_eq!(
        tool(&m, "page.submit")["annotations"]["destructiveHint"],
        true
    );
    assert_eq!(
        tool(&m, "page.submit")["annotations"]["openWorldHint"],
        true
    );
    for name in [
        "page.read",
        "page.links",
        "page.find",
        "tabs.list",
        "history.search",
        "bookmarks.find",
        "downloads.list",
    ] {
        assert_eq!(
            tool(&m, name)["annotations"]["readOnlyHint"],
            true,
            "{name}"
        );
    }
}

#[test]
fn page_content_is_marked_untrusted_and_bounded() {
    let m = manifest();
    for name in [
        "page.read",
        "page.links",
        "browse.open",
        "tabs.list",
        "history.search",
        "page.click",
        "page.submit",
    ] {
        assert_eq!(
            tool(&m, name)["_meta"]["org.shipwright.keel/untrusted"],
            true,
            "{name}"
        );
    }
    for name in ["page.read", "page.links", "browse.open"] {
        let t = tool(&m, name);
        let props = &t["outputSchema"]["properties"];
        assert!(
            props.get("untrusted").is_some(),
            "{name}: no untrusted flag"
        );
        let desc = t["description"].as_str().unwrap().to_lowercase();
        assert!(
            desc.contains("untrusted"),
            "{name}: description does not say the content is untrusted"
        );
    }
    let text = &tool(&m, "page.read")["outputSchema"]["properties"]["pageText"];
    assert_eq!(text["maxLength"], 20000);
    // Element ids are snapshot ids, nothing else (no selectors or script).
    let id = &tool(&m, "page.click")["inputSchema"]["properties"]["id"];
    assert_eq!(id["pattern"], "^e[0-9]+$");
}
