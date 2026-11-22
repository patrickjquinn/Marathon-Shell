// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! [`keel_mcp::watch`]: the catalogue follows manifest files as they are
//! created, changed and removed, and running apps as they start and stop,
//! without polling. The bus test starts a private bus (skipped without
//! `dbus-daemon`).

#![allow(clippy::unwrap_used, clippy::expect_used, reason = "tests")]

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use futures_util::StreamExt;
use keel_mcp::backend::{Backend, BoxFuture, Bus, CallError, CallResult};
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

/// Running apps as a test sets them, with a count of how often keel-mcp
/// asked.
#[derive(Default)]
struct Apps {
    running: Mutex<Vec<Value>>,
    asked: AtomicUsize,
    changed: tokio::sync::Notify,
}

impl Apps {
    fn set(&self, running: Vec<Value>) {
        *self.running.lock().unwrap() = running;
        self.changed.notify_one();
    }
}

impl Backend for Apps {
    fn running_manifests(&self) -> BoxFuture<'_, Vec<Value>> {
        self.asked.fetch_add(1, Ordering::SeqCst);
        let running = self.running.lock().unwrap().clone();
        Box::pin(async move { running })
    }
    fn running_changed(&self) -> BoxFuture<'_, ()> {
        Box::pin(self.changed.notified())
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
    let apps = Arc::new(Apps::default());
    let server = KeelMcp::new(Arc::<Apps>::clone(&apps), false);
    tokio::spawn(keel_mcp::watch(
        server.clone(),
        apps,
        vec![dir.clone()],
        None,
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

#[tokio::test(start_paused = true)]
async fn running_apps_are_asked_only_when_they_change() {
    let apps = Arc::new(Apps::default());
    let server = KeelMcp::new(Arc::<Apps>::clone(&apps), false);
    tokio::spawn(keel_mcp::watch(
        server.clone(),
        Arc::<Apps>::clone(&apps),
        Vec::new(),
        None,
    ));

    tokio::time::sleep(Duration::from_secs(3600)).await;
    assert_eq!(
        apps.asked.load(Ordering::SeqCst),
        1,
        "asked at start, then not for an hour without a change"
    );

    apps.set(vec![manifest("org.example.r", "running")]);
    until(&server, |c| c.apps.contains_key("org.example.r")).await;
    apps.set(Vec::new());
    until(&server, |c| c.apps.is_empty()).await;
    assert_eq!(apps.asked.load(Ordering::SeqCst), 3);
}

#[tokio::test(start_paused = true)]
async fn the_safety_net_asks_on_its_interval() {
    let apps = Arc::new(Apps::default());
    let server = KeelMcp::new(Arc::<Apps>::clone(&apps), false);
    tokio::spawn(keel_mcp::watch(
        server.clone(),
        Arc::<Apps>::clone(&apps),
        Vec::new(),
        Some(Duration::from_secs(60)),
    ));
    tokio::time::sleep(Duration::from_secs(150)).await;
    assert_eq!(apps.asked.load(Ordering::SeqCst), 3);
}

const APP: &str = "org.example.watched";

/// An app on the real bus: it appears when it takes its name and goes when
/// it gives it up.
#[tokio::test]
async fn apps_on_the_bus_are_followed() {
    let Some(bus) = marathon_rt::testing::PrivateBus::start() else {
        return;
    };
    let backend: Arc<dyn Backend> = Arc::new(Bus::on(bus.connect().await.unwrap()).await.unwrap());
    let server = KeelMcp::new(Arc::clone(&backend), false);
    tokio::spawn(keel_mcp::watch(server.clone(), backend, Vec::new(), None));

    let app = bus.connect().await.unwrap();
    let mut calls = zbus::MessageStream::from(&app);
    let replies = app.clone();
    tokio::spawn(async move {
        let describe = manifest(APP, "on the bus").to_string();
        while let Some(Ok(message)) = calls.next().await {
            let header = message.header();
            if header.message_type() == zbus::message::Type::MethodCall
                && header.member().is_some_and(|m| m.as_str() == "Describe")
            {
                replies.reply(&header, &describe).await.unwrap();
            }
        }
    });

    app.request_name(APP).await.unwrap();
    until(&server, |c| c.apps.contains_key(APP)).await;
    app.release_name(APP).await.unwrap();
    until(&server, |c| !c.apps.contains_key(APP)).await;
}
