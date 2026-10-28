// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Installs, updates or removes a package exactly the way the Reef app does
//! (`Store` with the signed-metadata check and the install ledger), for the
//! phone lifecycle test (tools/testing/lifecycle): `reef-test install|update|remove <rpm name>`.
//! Run as the device owner, like Reef. It prints the plan the app would show
//! (every package the transaction touches) and then runs it: typing the
//! command is the go-ahead.

use reef_backend::metadata::MetadataCheck;
use reef_backend::packagekit::dbus::PackageKitClient;
use reef_backend::packagekit::Error;
use reef_backend::store::{InstallLedger, Store};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let [cmd, name] = args.as_slice() else {
        eprintln!("usage: reef-test install|update|remove <rpm name>");
        std::process::exit(2);
    };
    let result = futures_lite::future::block_on(async {
        let pm = PackageKitClient::system().await?;
        let alias = "shipwright-reef";
        let store = Store::new(pm, alias)
            .with_metadata_check(MetadataCheck::device(alias))
            .with_ledger(InstallLedger::default_path().map(InstallLedger::new));
        let mut progress = |p: reef_backend::packagekit::Progress| {
            eprintln!("{:?} {:?}", p.status, p.percentage);
        };
        let plan = match cmd.as_str() {
            "install" => store.preview_install(name, None).await?,
            "update" => store
                .preview_update(name, None)
                .await?
                .ok_or_else(|| Error::NotFound(name.clone()))?,
            "remove" => store.preview_remove(name, None).await?,
            _ => {
                eprintln!("unknown command {cmd}");
                std::process::exit(2);
            }
        };
        for item in &plan.items {
            println!(
                "plan: {:?} {} {} ({:?}, from {})",
                item.change, item.name, item.version, item.kind, item.repo
            );
        }
        match cmd.as_str() {
            "install" => store.install(name, &plan, &mut progress).await,
            "update" => store.update(name, &plan, &mut progress).await.map(drop),
            _ => store.remove(name, &plan, &mut progress).await,
        }
    });
    match result {
        Ok(()) => println!("{cmd} {name}: ok"),
        Err(e) => {
            println!("{cmd} {name}: failed: {e}");
            std::process::exit(1);
        }
    }
}
