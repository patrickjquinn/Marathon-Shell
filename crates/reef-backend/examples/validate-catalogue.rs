// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Parses a catalogue exactly as the store client does and prints what
//! this machine would see, to prove a publisher and the client agree on
//! the format.
//!
//! usage: validate-catalogue <catalogue.json> <arch>

use std::process::ExitCode;

use reef_backend::catalogue::Catalogue;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let [path, arch] = args.as_slice() else {
        eprintln!("usage: validate-catalogue <catalogue.json> <arch>");
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
    let visible = cat.visible();
    println!(
        "{path}: {} packages, {} visible here",
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
