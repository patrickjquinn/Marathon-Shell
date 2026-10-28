// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! `org.shipwright.Pilot1` on a private session bus, and the privacy
//! switch followed through a stand-in `org.sailfishos.privacyswitch`
//! service on the same bus.

#![allow(clippy::unwrap_used, clippy::expect_used, reason = "tests")]

mod common;

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use common::{chat_text, jev_reply, FakeHttp, Log, Reply};
use futures_util::StreamExt as _;
use marathon_rt::testing::PrivateBus;
use pilotd::privacy::{SailfishSwitch, SWITCH_BUS_NAME, SWITCH_PATH};
use serde_json::Value;
use zbus::object_server::SignalEmitter;

/// Stand-in for the Sailfish OS privacy switch service.
struct Switch(Arc<AtomicBool>);

#[zbus::interface(name = "org.sailfishos.privacyswitch")]
impl Switch {
    #[zbus(name = "privacyModeActive")]
    fn privacy_mode_active(&self) -> bool {
        self.0.load(Ordering::SeqCst)
    }

    #[zbus(signal, name = "privacyModeActiveChanged")]
    async fn changed(emitter: &SignalEmitter<'_>, active: bool) -> zbus::Result<()>;
}

async fn pilot(conn: &zbus::Connection) -> zbus::Proxy<'static> {
    zbus::Proxy::new(
        conn,
        "org.shipwright.Pilot",
        "/org/shipwright/Pilot",
        "org.shipwright.Pilot1",
    )
    .await
    .unwrap()
}

#[tokio::test]
#[allow(clippy::too_many_lines, reason = "one end-to-end scenario")]
async fn service_round_trip_and_privacy_switch() {
    let Some(bus) = PrivateBus::start() else {
        return;
    };
    let srv = FakeHttp::start(|req: &common::Seen, _| match req.path.as_str() {
        "/v1/jev" => {
            if req.body["state"]["utterance"]
                .as_str()
                .unwrap_or("")
                .contains("timer")
            {
                Reply::ok(jev_reply(&[("timer", 0.97)], 0.0, 0.0))
            } else {
                Reply::ok(jev_reply(&[("open_ended", 0.9)], 0.9, 0.0))
            }
        }
        _ => Reply::us(chat_text("Helsinki.")),
    })
    .await;
    let dir = tempfile::tempdir().unwrap();
    let log = Arc::new(Log::default());
    let d = Arc::new(common::daemon(&srv.base, &log, Some(dir.path().to_owned())));
    let server = bus.connect().await.unwrap();
    pilotd::daemon::serve_on(&d, &server).await.unwrap();

    // The switch service, released to start with.
    let state = Arc::new(AtomicBool::new(false));
    let switch_conn = bus.connect().await.unwrap();
    switch_conn
        .object_server()
        .at(SWITCH_PATH, Switch(Arc::clone(&state)))
        .await
        .unwrap();
    switch_conn.request_name(SWITCH_BUS_NAME).await.unwrap();
    let sw = Arc::new(SailfishSwitch {
        conn: server.clone(),
    });
    tokio::spawn(Arc::clone(&d).follow_switch(sw, Some(server.clone())));

    let client = bus.connect().await.unwrap();
    let p = pilot(&client).await;
    let mut finished = p.receive_signal("TurnFinished").await.unwrap();
    // The first-run choice: nothing goes to the cloud before it.
    let () = p.call("SetConsent", &("text_qa", true)).await.unwrap();

    let json: String = p
        .call("Ask", &("set a timer for 3 minutes", false))
        .await
        .unwrap();
    let r: Value = serde_json::from_str(&json).unwrap();
    assert_eq!(r["route"], "handler");
    assert_eq!(r["cards"][0]["kind"], "timer");
    assert_eq!(r["cards"][0]["text"], "Timer set for 3 minutes.");
    assert_eq!(r["cards"][0]["seconds"], 180);
    assert_eq!(r["via"], "phone");
    let sig = tokio::time::timeout(Duration::from_secs(2), finished.next())
        .await
        .unwrap()
        .unwrap();
    let body: String = sig.body().deserialize().unwrap();
    assert_eq!(
        serde_json::from_str::<Value>(&body).unwrap()["turn"],
        r["turn"]
    );
    let last: String = p.get_property("LastResponse").await.unwrap();
    assert_eq!(last, "Timer set for 3 minutes.");

    // A transcribed question needs the spoken-questions consent.
    p.call::<_, _, ()>("SetConsent", &("voice_cloud", true))
        .await
        .unwrap();
    let json: String = p.call("Ask", &("capital of Finland?", true)).await.unwrap();
    let r: Value = serde_json::from_str(&json).unwrap();
    assert_eq!(r["cards"][0]["text"], "Helsinki.");
    assert_eq!(r["spoken"], true);

    // Settings: defaults, a change persisted to disk, bad names refused.
    let s: Value =
        serde_json::from_str(&p.call::<_, _, String>("Settings", &()).await.unwrap()).unwrap();
    assert_eq!(s["consent"]["text_qa"], true);
    assert_eq!(s["consent"]["vision"], false);
    assert_eq!(s["backends"], serde_json::json!(["lighthouse", "standard"]));
    p.call::<_, _, ()>("SetConsent", &("vision", true))
        .await
        .unwrap();
    assert!(p
        .call::<_, _, ()>("SetConsent", &("everything", true))
        .await
        .is_err());
    p.call::<_, _, ()>("SetBackend", &("lighthouse",))
        .await
        .unwrap();
    assert!(p
        .call::<_, _, ()>("SetBackend", &("nowhere",))
        .await
        .is_err());
    let saved: Value =
        serde_json::from_slice(&std::fs::read(dir.path().join("settings.json")).unwrap()).unwrap();
    assert_eq!(saved["consent"]["vision"], true);
    assert_eq!(saved["backend"], "lighthouse");
    p.call::<_, _, ()>("SetBackend", &("standard",))
        .await
        .unwrap();

    // Egress log and export.
    let eg: Value =
        serde_json::from_str(&p.call::<_, _, String>("EgressLog", &(0u32,)).await.unwrap())
            .unwrap();
    let providers: Vec<&str> = eg
        .as_array()
        .unwrap()
        .iter()
        .map(|e| e["provider"].as_str().unwrap())
        .collect();
    assert_eq!(providers, ["groq", "jev", "jev"]);
    let ex: Value =
        serde_json::from_str(&p.call::<_, _, String>("Export", &()).await.unwrap()).unwrap();
    assert_eq!(ex["format"], "shoal-pilot-export/1");
    assert_eq!(ex["decisions"].as_array().unwrap().len(), 2);
    assert!(
        !ex.to_string().contains("Finland"),
        "no utterances in the export"
    );

    // Privacy switch engaged through the Sailfish service: offline, voice
    // stopped, property signalled, nothing leaves the device.
    assert!(!p.get_property::<bool>("Offline").await.unwrap());
    let mut offline_changes = p.receive_property_changed::<bool>("Offline").await;
    state.store(true, Ordering::SeqCst);
    Switch::changed(
        &SignalEmitter::new(&switch_conn, SWITCH_PATH).unwrap(),
        true,
    )
    .await
    .unwrap();
    // The stream may first yield the cached value; wait for `true`.
    tokio::time::timeout(Duration::from_secs(2), async {
        while let Some(ch) = offline_changes.next().await {
            if ch.get().await.unwrap() {
                return;
            }
        }
    })
    .await
    .expect("Offline changed to true");
    assert!(log.all().contains(&"voice stopped".to_owned()));
    let before = srv.seen.lock().unwrap().len();
    let json: String = p.call("Ask", &("capital of Sweden?", false)).await.unwrap();
    assert_eq!(
        serde_json::from_str::<Value>(&json).unwrap()["cards"][0]["kind"],
        "offline"
    );
    assert_eq!(srv.seen.lock().unwrap().len(), before);

    // Wipe empties both logs and the cover text.
    p.call::<_, _, ()>("Wipe", &()).await.unwrap();
    let eg: String = p.call("EgressLog", &(0u32,)).await.unwrap();
    assert_eq!(eg, "[]");
    assert_eq!(p.get_property::<String>("LastResponse").await.unwrap(), "");
}

/// A confirmation card is answered only by the connection whose turn made
/// it: another process of the person's, watching `TurnFinished` for card
/// ids, cannot say yes to a call on their behalf.
#[tokio::test]
async fn only_the_asking_app_can_answer_its_card() {
    let Some(bus) = PrivateBus::start() else {
        return;
    };
    let srv = FakeHttp::start(|req: &common::Seen, _| match req.path.as_str() {
        "/v1/jev" => Reply::ok(jev_reply(&[("call", 0.95)], 0.1, 0.1)),
        _ => Reply::us(common::chat_tool("call_dial", r#"{"number": "112"}"#)),
    })
    .await;
    let log = Arc::new(Log::default());
    let d = Arc::new(common::daemon(&srv.base, &log, None));
    let server = bus.connect().await.unwrap();
    pilotd::daemon::serve_on(&d, &server).await.unwrap();
    let app = bus.connect().await.unwrap();
    let other = bus.connect().await.unwrap();
    let p = pilot(&app).await;
    let () = p.call("SetConsent", &("text_qa", true)).await.unwrap();
    let json: String = p.call("Ask", &("call 112", false)).await.unwrap();
    let r: Value = serde_json::from_str(&json).unwrap();
    let id = r["cards"][0]["id"]
        .as_str()
        .expect("a confirmation card")
        .to_owned();
    // Another connection, with the id from the broadcast: refused.
    let refused: zbus::Result<String> = pilot(&other)
        .await
        .call("Confirm", &(id.as_str(), true))
        .await;
    assert!(
        matches!(&refused, Err(zbus::Error::MethodError(name, _, _)) if name.as_str() == "org.freedesktop.DBus.Error.AccessDenied"),
        "{refused:?}"
    );
    assert!(
        !log.all().iter().any(|l| l.starts_with("dial")),
        "nothing was called"
    );
    // The app that asked: done.
    let _: String = p.call("Confirm", &(id.as_str(), true)).await.unwrap();
    assert!(log.all().iter().any(|l| l.starts_with("dial 112")));
}
