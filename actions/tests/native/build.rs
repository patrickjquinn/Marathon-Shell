// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

// The Keel Actions build step from build.rs: actions.json into $OUT_DIR,
// registered in src/lib.rs with keel::manifest!().

fn main() {
    keel_actions_codegen::Config {
        rust: vec!["src".into()],
        app_id: Some("org.example.rustnotes".into()),
        executable: Some("/usr/bin/keel-actions-test-native".into()),
        ..Default::default()
    }
    .build_script();
}
