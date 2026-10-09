// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! Declarations the generator must reject, with useful messages.

use std::fs;
use std::path::PathBuf;

use keel_actions_codegen::Config;

fn errors(name: &str, qml: &str) -> Vec<String> {
    let dir =
        std::env::temp_dir().join(format!("keel-actions-errors-{}-{name}", std::process::id()));
    fs::create_dir_all(&dir).unwrap();
    let file = dir.join("Main.qml");
    fs::write(&file, qml).unwrap();
    let result = Config {
        qml: vec![PathBuf::from(&file)],
        app_id: Some("org.example.bad".into()),
        executable: Some("/usr/bin/bad".into()),
        ..Config::default()
    }
    .generate();
    fs::remove_dir_all(&dir).unwrap();
    let failed = result.expect_err("must fail");
    failed.0.errors.into_iter().map(|(_, m)| m).collect()
}

fn wrap(body: &str) -> String {
    format!("import QtQuick 2.15\nimport Keel.Actions 1.0\nItem {{\n{body}\n}}\n")
}

#[test]
fn non_literal_and_unknown_properties() {
    let e = errors(
        "literal",
        &wrap(
            r#"KeelAction { name: root.prefix + ".x"; description: "A description that is long enough."; colour: "red" }"#,
        ),
    );
    assert!(
        e[0].starts_with("KeelAction.name must be a literal"),
        "{e:?}"
    );
    assert!(
        e[1].starts_with("KeelAction has no property `colour`"),
        "{e:?}"
    );
}

#[test]
fn contract_checks() {
    let e = errors(
        "contract",
        &wrap(
            r#"
    KeelAction {
        name: "Bad"
        description: "Removes all the things from the device."
        parameters: [ KeelParam { name: "p"; type: "entity" }, KeelParam { name: "q"; type: "map" } ]
    }
    KeelShortcut { name: "s"; description: "A shortcut with an unknown step in it."; steps: [ { action: "x.y", arguments: { a: "{{nope}}" } } ] }
"#,
        ),
    );
    let joined = e.join("\n");
    for needle in [
        "an entity reference needs `entity`",
        "unknown type \"map\"",
        "action name \"Bad\" is not domain.verb",
        "step action \"x.y\" is not declared",
        "{{nope}}",
        "[destructive]",
    ] {
        assert!(joined.contains(needle), "missing {needle:?} in:\n{joined}");
    }
}

#[test]
fn untrusted_results_are_marked() {
    let dir = std::env::temp_dir().join(format!("keel-actions-untrusted-{}", std::process::id()));
    fs::create_dir_all(&dir).unwrap();
    let file = dir.join("Main.qml");
    fs::write(
        &file,
        wrap(
            r#"KeelAction { name: "page.read"; description: "Read the text of the page in front."; readOnly: true; untrusted: true
                 returns: KeelResult { type: "object"; KeelParam { name: "text"; type: "string"; maxLength: 100; required: true } } }
               KeelAction { name: "page.reload"; description: "Reload the page in front, nothing else." }"#,
        ),
    )
    .unwrap();
    let out = Config {
        qml: vec![PathBuf::from(&file)],
        app_id: Some("org.example.web".into()),
        executable: Some("/usr/bin/web".into()),
        ..Config::default()
    }
    .generate()
    .unwrap_or_else(|e| panic!("{e}"));
    fs::remove_dir_all(&dir).unwrap();
    let tools = out.manifest["tools"].as_array().unwrap();
    let read = tools
        .iter()
        .find(|t| t["name"] == "org.example.web/page.read")
        .unwrap();
    assert_eq!(read["_meta"]["org.shipwright.keel/untrusted"], true);
    let reload = tools
        .iter()
        .find(|t| t["name"] == "org.example.web/page.reload")
        .unwrap();
    assert!(reload["_meta"]
        .get("org.shipwright.keel/untrusted")
        .is_none());
    assert!(out
        .artefact("org.example.web.actions.xml")
        .unwrap()
        .contains("untrusted"));
}
