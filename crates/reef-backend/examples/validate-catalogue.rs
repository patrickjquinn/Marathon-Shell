// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

//! Parses a catalogue exactly as the store client does and prints what a
//! phone on `release` would see. Used by tools/build/reef/e2e-test.sh to
//! prove the publish scripts and the client agree on the format.
//!
//! usage: validate-catalogue <catalogue.json> <arch> <release>

use std::process::ExitCode;

use reef_backend::catalogue::Catalogue;
use reef_backend::release::SailfishRelease;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let [path, arch, release] = args.as_slice() else {
        eprintln!("usage: validate-catalogue <catalogue.json> <arch> <release>");
        return ExitCode::from(2);
    };
    let Some(release) = SailfishRelease::parse(release) else {
        eprintln!("not a four-part Sailfish release: {release}");
        return ExitCode::from(2);
    };
    let bytes = match std::fs::read(path) {
        Ok(b) => b,
        Err(e) => {
            eprintln!("{path}: {e}");
            return ExitCode::FAILURE;
        }
    };
    let cat = match Catalogue::parse(&bytes, arch) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{path}: {e}");
            return ExitCode::FAILURE;
        }
    };
    let visible = cat.visible(&release);
    println!(
        "{path}: {} packages, {} visible on {release}",
        cat.packages.len(),
        visible.len()
    );
    for p in visible {
        match &p.keel_tier {
            Some(tier) => println!("  {} {} ({}), keel tier {tier}", p.name, p.version, p.title),
            None => println!("  {} {} ({})", p.name, p.version, p.title),
        }
    }
    ExitCode::SUCCESS
}
