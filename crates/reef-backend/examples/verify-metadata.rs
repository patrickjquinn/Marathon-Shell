// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Runs Reef's repository metadata check on a phone, as the app does
//! before an install: `verify-metadata [alias]`.

fn main() {
    let alias = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "shipwright-reef".into());
    let Some(check) = reef_backend::metadata::MetadataCheck::device(&alias) else {
        eprintln!("no home directory");
        std::process::exit(2);
    };
    match check.verify() {
        Ok(rev) => println!("ok: revision {rev}"),
        Err(e) => {
            println!("refused: {e}");
            std::process::exit(1);
        }
    }
}
