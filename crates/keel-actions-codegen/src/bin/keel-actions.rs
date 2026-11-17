// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! An app's Keel actions manifest (`keel-actions.json`) from the actions
//! its QML or Rust declares, so Pilot and other assistants can use them.
//!
//! ```text
//! cargo run -q -p keel-actions-codegen --bin keel-actions -- \
//!     --qml apps/radio/RadioActions.qml --app-id org.marathonos.radio \
//!     --out apps/radio/keel-actions.json
//! ```
//!
//! `--check` compares instead of writing, and fails when the file is stale.

#![allow(
    clippy::print_stdout,
    clippy::print_stderr,
    reason = "a command-line tool"
)]

use std::path::PathBuf;
use std::process::ExitCode;

use keel_actions_codegen::Config;

const USAGE: &str = "usage: keel-actions (--qml PATH | --rust PATH)... --app-id ID \
[--exec PATH] [--out FILE [--check]]
  --qml PATH    QML file or directory declaring KeelAction items
  --rust PATH   Rust file or directory declaring #[keel::action] functions
  --app-id ID   the app's D-Bus name, e.g. org.marathonos.radio
  --exec PATH   what the service file starts (default /usr/bin/marathon-app-runner)
  --out FILE    write the manifest there (default: print it)
  --check       compare with --out instead of writing; fail when it differs";

fn main() -> ExitCode {
    let mut config = Config {
        executable: Some("/usr/bin/marathon-app-runner".into()),
        ..Config::default()
    };
    let mut out: Option<PathBuf> = None;
    let mut check = false;
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        let mut value = || args.next().ok_or(format!("{arg} needs a value"));
        let r = match arg.as_str() {
            "--qml" => value().map(|v| config.qml.push(v.into())),
            "--rust" => value().map(|v| config.rust.push(v.into())),
            "--app-id" => value().map(|v| config.app_id = Some(v)),
            "--exec" => value().map(|v| config.executable = Some(v)),
            "--out" => value().map(|v| out = Some(v.into())),
            "--check" => {
                check = true;
                Ok(())
            }
            "-h" | "--help" => {
                println!("{USAGE}");
                return ExitCode::SUCCESS;
            }
            other => Err(format!("unknown argument {other}")),
        };
        if let Err(e) = r {
            eprintln!("keel-actions: {e}\n{USAGE}");
            return ExitCode::FAILURE;
        }
    }
    if config.qml.is_empty() && config.rust.is_empty() {
        eprintln!("keel-actions: give --qml or --rust\n{USAGE}");
        return ExitCode::FAILURE;
    }
    let output = match config.generate() {
        Ok(o) => o,
        Err(e) => {
            eprintln!("keel-actions: {e}");
            return ExitCode::FAILURE;
        }
    };
    if !output.diagnostics.warnings.is_empty() {
        eprintln!("{}", output.diagnostics);
    }
    let Some(manifest) = output.artefact("actions.json") else {
        eprintln!("keel-actions: no manifest was generated");
        return ExitCode::FAILURE;
    };
    match (out, check) {
        (None, _) => {
            print!("{manifest}");
            ExitCode::SUCCESS
        }
        (Some(path), true) => {
            if std::fs::read_to_string(&path).is_ok_and(|have| have == manifest) {
                ExitCode::SUCCESS
            } else {
                eprintln!(
                    "keel-actions: {} is stale; run without --check to regenerate it",
                    path.display()
                );
                ExitCode::FAILURE
            }
        }
        (Some(path), false) => match std::fs::write(&path, manifest) {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => {
                eprintln!("keel-actions: {}: {e}", path.display());
                ExitCode::FAILURE
            }
        },
    }
}
