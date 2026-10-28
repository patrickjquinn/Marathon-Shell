// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! Golden tests: the generator's output for the QML test app
//! (keel/actions/tests/app) and for the Rust declarations of the `keel`
//! crate's tests. `UPDATE_GOLDEN=1 cargo test -p keel-actions-codegen`
//! rewrites the expected files; review the diff.

use std::fs;
use std::path::{Path, PathBuf};

use keel_actions_codegen::{stubs, Config};

fn repo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../..")
}

fn check(name: &str, config: &Config) {
    let golden = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/golden")
        .join(name);
    let output = config.generate().unwrap_or_else(|e| panic!("{e}"));
    assert!(
        output.diagnostics.warnings.is_empty(),
        "{}",
        output.diagnostics
    );
    let mut files: Vec<_> = output.artefacts.clone();
    files.extend(output.stubs.iter().map(|s| stubs::place(s, &golden)));
    if std::env::var_os("UPDATE_GOLDEN").is_some() {
        fs::create_dir_all(&golden).unwrap();
        for f in &files {
            fs::write(golden.join(&f.name), &f.contents).unwrap();
        }
    }
    let mut expected: Vec<String> = fs::read_dir(&golden)
        .unwrap()
        .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
        .collect();
    expected.sort();
    let mut actual: Vec<String> = files.iter().map(|f| f.name.clone()).collect();
    actual.sort();
    assert_eq!(actual, expected, "generated file set");
    for f in &files {
        let want = fs::read_to_string(golden.join(&f.name)).unwrap();
        assert!(
            want == f.contents,
            "{name}/{} differs from the golden file:\n{}",
            f.name,
            f.contents
        );
    }
}

// Paths relative to the repository root, so that messages and stubs do not
// depend on where the checkout is.
fn in_repo() {
    std::env::set_current_dir(repo()).unwrap();
}

#[test]
fn qml_notes() {
    in_repo();
    check(
        "qml-notes",
        &Config {
            qml: vec!["keel/actions/tests/app".into()],
            desktop: Some("keel/actions/tests/app/org.example.notes.desktop".into()),
            ..Config::default()
        },
    );
}

#[test]
fn rust_notes() {
    in_repo();
    check(
        "rust-notes",
        &Config {
            rust: vec!["keel/actions/rust/keel/tests".into()],
            app_id: Some("org.example.rustnotes".into()),
            executable: Some("/usr/bin/rustnotes".into()),
            ..Config::default()
        },
    );
}
