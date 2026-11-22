// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! [`keel_mcp::watch`]: the catalogue follows manifest files as they are
//! created, changed and removed.

#![allow(clippy::unwrap_used, clippy::expect_used, reason = "tests")]

use std::sync::Arc;
use std::time::Duration;

use keel_mcp::backend::{Backend, BoxFuture, CallError, CallResult};
use keel_mcp::catalogue::Catalogue;
use keel_mcp::KeelMcp;
use serde_json::{json, Value};

fn manifest(app: &str, description: &str) -> Value {
    json!({ "version": 1, "appId": app,
            "tools": [ { "name": format!("{app}/thing.do"), "description": description } ] })
}

/// Waits (up to 5 s) until the catalogue satisfies `what`.
async fn until(server: &KeelMcp, what: impl Fn(&Catalogue) -> bool) {
    let mut changes = server.changes();
    tokio::time::timeout(Duration::from_secs(5), async {
        while !what(&server.catalogue()) {
            changes.recv().await.unwrap();
        }
    })
    .await
    .expect("the catalogue did not change");
}

/// No apps run.
struct Apps;

impl Backend for Apps {
    fn running_manifests(&self) -> BoxFuture<'_, Vec<Value>> {
        Box::pin(async { Vec::new() })
    }
    fn invoke<'a>(
        &'a self,
        _: &'a str,
        _: &'a str,
        _: &'a Value,
        _: bool,
        _: Duration,
    ) -> BoxFuture<'a, CallResult> {
        Box::pin(async { Err(CallError::Unreachable("no apps".into())) })
    }
    fn get_entity<'a>(&'a self, _: &'a str, _: &'a str, _: &'a str) -> BoxFuture<'a, CallResult> {
        Box::pin(async { Err(CallError::Unreachable("no apps".into())) })
    }
    fn find_entities<'a>(
        &'a self,
        _: &'a str,
        _: &'a str,
        _: &'a str,
        _: u32,
    ) -> BoxFuture<'a, CallResult> {
        Box::pin(async { Err(CallError::Unreachable("no apps".into())) })
    }
    fn get_context<'a>(&'a self, _: &'a str) -> BoxFuture<'a, CallResult> {
        Box::pin(async { Err(CallError::Unreachable("no apps".into())) })
    }
}

fn description(c: &Catalogue, app: &str) -> Option<String> {
    c.tool(&format!("{app}/thing.do"))
        .and_then(|t| t.tool["description"].as_str().map(ToOwned::to_owned))
}

#[tokio::test]
async fn manifest_files_are_followed() {
    let root = tempfile::tempdir().unwrap();
    // Neither directory exists yet: watched through the temporary one.
    let dir = root.path().join("keel/actions");
    let server = KeelMcp::new(Arc::new(Apps), false);
    tokio::spawn(keel_mcp::watch(
        server.clone(),
        Arc::new(Apps),
        vec![dir.clone()],
        Duration::from_secs(3600),
    ));

    std::fs::create_dir_all(&dir).unwrap();
    let file = dir.join("org.example.a.json");
    std::fs::write(&file, manifest("org.example.a", "one").to_string()).unwrap();
    until(&server, |c| {
        description(c, "org.example.a").as_deref() == Some("one")
    })
    .await;

    std::fs::write(&file, manifest("org.example.a", "two").to_string()).unwrap();
    until(&server, |c| {
        description(c, "org.example.a").as_deref() == Some("two")
    })
    .await;

    // Written beside and moved into place, as a package manager does.
    let partial = dir.join("org.example.b.json.new");
    std::fs::write(&partial, manifest("org.example.b", "b").to_string()).unwrap();
    std::fs::rename(&partial, dir.join("org.example.b.json")).unwrap();
    until(&server, |c| c.apps.contains_key("org.example.b")).await;

    std::fs::remove_file(&file).unwrap();
    until(&server, |c| {
        !c.apps.contains_key("org.example.a") && c.apps.contains_key("org.example.b")
    })
    .await;

    // The directory goes and comes back.
    std::fs::remove_dir_all(&dir).unwrap();
    until(&server, |c| c.apps.is_empty()).await;
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(&file, manifest("org.example.a", "three").to_string()).unwrap();
    until(&server, |c| {
        description(c, "org.example.a").as_deref() == Some("three")
    })
    .await;
}
