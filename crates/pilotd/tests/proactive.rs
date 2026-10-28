// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Proactive triage (spec section 5.3) and camera turns (phase 4), against
//! fake Jev and LLM servers; the notification monitor on a private bus
//! with a stand-in notification server.

mod common;

use std::sync::Arc;
use std::time::Duration;

use common::{chat_text, chat_tool, jev_reply, FakeHttp, Log, Reply};
use futures_util::StreamExt as _;
use pilotd::pipeline::Card;
use pilotd::triage::{Incoming, Skipped};
use serde_json::{json, Value};
use shoal_push_client::testbus::TestBus;

fn triage_reply(interrupt: f64, bucket: &str, urgency: f64) -> Reply {
    Reply::ok(json!({"answers": {
        "worth_interrupting": {"noul": interrupt},
        "bucket": {"probabilities": {bucket: 0.8, "ignore": 0.1}},
        "urgency": {"score": urgency, "confidence": 0.8}
    }}))
}

fn sms(title: &str, body: &str) -> Incoming {
    Incoming {
        source: "sms".into(),
        app: "Messages".into(),
        title: title.into(),
        body: body.into(),
    }
}

#[tokio::test]
async fn triage_is_opt_in_redacted_stored_and_nudges_only_when_asked() {
    let srv = FakeHttp::start(|req: &common::Seen, _| {
        let urgent = req.body["state"]["event"]["body"]
            .as_str()
            .unwrap_or("")
            .contains("now");
        if urgent {
            triage_reply(0.95, "act_now", 2.0)
        } else {
            triage_reply(0.1, "later", 0.0)
        }
    })
    .await;
    let log = Arc::new(Log::default());
    let d = common::daemon(&srv.base, &log, None);
    let ev = sms(
        "Anna Virtanen",
        "Call me now on +358 40 123 4567, door code 4411",
    );

    // Off at first run: nothing leaves the phone.
    assert_eq!(d.triage.handle(&ev).await, Err(Skipped::NoConsent));
    assert!(srv.seen("/v1/jev").is_empty());

    d.live.lock().unwrap().consent.triage = true;
    let item = d.triage.handle(&ev).await.unwrap();
    assert_eq!((item.bucket.as_str(), item.urgency), ("act_now", 2.0));
    let sent = &srv.seen("/v1/jev")[0].body;
    assert_eq!(sent["state"]["event"]["source"], "sms");
    let s = sent.to_string();
    assert!(!s.contains("Anna") && !s.contains("123 4567"), "{s}");
    assert!(s.contains("<CONTACT_1>") && s.contains("<PHONE_1>"), "{s}");
    for q in ["worth_interrupting", "bucket", "urgency"] {
        assert!(sent["questions"].get(q).is_some(), "{q}");
    }
    // Kept on the device with the real text, for the Events view.
    let list = d.store.triage(0).unwrap();
    assert_eq!(list[0].title, "Anna Virtanen");
    // Worth interrupting, but spoken nudges are off.
    assert!(!log.all().iter().any(|l| l.starts_with("say")));

    // The same message again within ten minutes: triaged once.
    assert_eq!(d.triage.handle(&ev).await, Err(Skipped::Repeat));

    d.live.lock().unwrap().consent.spoken_nudges = true;
    d.triage
        .handle(&sms("Anna Virtanen", "now: the second one"))
        .await
        .unwrap();
    assert!(
        log.all().contains(&"say Message: Anna Virtanen".to_owned()),
        "{:?}",
        log.all()
    );
    // Below the threshold: listed, not spoken.
    d.triage
        .handle(&sms("Shop", "your parcel ships"))
        .await
        .unwrap();
    assert_eq!(log.all().iter().filter(|l| l.starts_with("say")).count(), 1);
    assert_eq!(d.store.triage(0).unwrap().len(), 3);

    // The privacy switch stops triage.
    d.offline_ctl.set(true);
    assert_eq!(
        d.triage.handle(&sms("Bank", "statement ready")).await,
        Err(Skipped::Offline)
    );
    assert_eq!(srv.seen("/v1/jev").len(), 3);
}

#[tokio::test]
async fn triage_has_an_hourly_ceiling() {
    let srv = FakeHttp::start(|_: &common::Seen, _| triage_reply(0.2, "today", 1.0)).await;
    let mut cfg = common::config(&srv.base);
    cfg.triage.per_hour = 2;
    let d = pilotd::daemon::build(pilotd::daemon::Options {
        config: cfg,
        data_dir: None,
        session: None,
        system: None,
        adapters: Some(common::fake_adapters(&Arc::new(Log::default()))),
        credential: Some(pilotd::remote::Credential::None),
        licence: None,
        now: || pilotd::localtime::LocalNow::fixed_utc(1_790_966_550),
    })
    .unwrap();
    d.live.lock().unwrap().consent.triage = true;
    for i in 0..2 {
        d.triage
            .handle(&sms("Shop", &format!("offer {i}")))
            .await
            .unwrap();
    }
    assert_eq!(
        d.triage.handle(&sms("Shop", "offer 3")).await,
        Err(Skipped::OverQuota)
    );
    assert_eq!(srv.seen("/v1/jev").len(), 2);
}

/// Stand-in for Lipstick's notification server: records what it shows.
struct Notifications(Arc<std::sync::Mutex<Vec<String>>>);

#[zbus::interface(name = "org.freedesktop.Notifications")]
#[allow(
    clippy::needless_pass_by_value,
    reason = "zbus deserializes each D-Bus argument into an owned value"
)]
impl Notifications {
    #[allow(clippy::too_many_arguments, reason = "the Notify signature")]
    fn notify(
        &self,
        app: String,
        replaces: u32,
        icon: String,
        summary: String,
        body: String,
        actions: Vec<String>,
        hints: std::collections::HashMap<String, zbus::zvariant::OwnedValue>,
        timeout: i32,
    ) -> u32 {
        let mut shown = self.0.lock().unwrap();
        shown.push(format!(
            "{app}|{replaces}|{icon}|{summary}|{body}|{}|{}|{timeout}",
            actions.len(),
            hints.len()
        ));
        u32::try_from(shown.len()).unwrap()
    }
}

#[tokio::test]
async fn notifications_on_the_bus_reach_the_events_list() {
    let bus = TestBus::start();
    let srv = FakeHttp::start(|_: &common::Seen, _| triage_reply(0.4, "today", 1.0)).await;
    let d = Arc::new(common::daemon(&srv.base, &Arc::new(Log::default()), None));
    d.live.lock().unwrap().consent.triage = true;
    let server = bus.connect().await;
    pilotd::daemon::serve_on(&d, &server).await.unwrap();
    let shown = Arc::new(std::sync::Mutex::new(Vec::new()));
    let notif = bus.connect().await;
    notif
        .object_server()
        .at(
            "/org/freedesktop/Notifications",
            Notifications(shown.clone()),
        )
        .await
        .unwrap();
    notif
        .request_name("org.freedesktop.Notifications")
        .await
        .unwrap();
    d.start_triage(Some(bus.connect().await), Some(server.clone()));

    let client = bus.connect().await;
    let pilot = zbus::Proxy::new(
        &client,
        "org.shipwright.Pilot",
        "/org/shipwright/Pilot",
        "org.shipwright.Pilot1",
    )
    .await
    .unwrap();
    let mut added = pilot.receive_signal("TriageAdded").await.unwrap();
    let n = zbus::Proxy::new(
        &client,
        "org.freedesktop.Notifications",
        "/org/freedesktop/Notifications",
        "org.freedesktop.Notifications",
    )
    .await
    .unwrap();
    let hints = |cat: &'static str, extra: Option<(&'static str, &'static str)>| {
        let mut h: std::collections::HashMap<&'static str, zbus::zvariant::Value<'static>> =
            std::collections::HashMap::new();
        h.insert("category", cat.to_owned().into());
        if let Some((k, v)) = extra {
            h.insert(k, v.to_owned().into());
        }
        h
    };
    // A battery warning is not triaged; an SMS with its text only in
    // Sailfish's preview hints is.
    let _: u32 = n
        .call(
            "Notify",
            &(
                "System",
                0u32,
                "",
                "Battery low",
                "10%",
                Vec::<String>::new(),
                hints("x-nemo.battery.lowbattery", None),
                -1i32,
            ),
        )
        .await
        .unwrap();
    let _: u32 = n
        .call(
            "Notify",
            &(
                "Messages",
                0u32,
                "",
                "",
                "",
                Vec::<String>::new(),
                hints(
                    "x-nemo.messaging.sms",
                    Some(("x-nemo-preview-summary", "Anna Virtanen")),
                ),
                -1i32,
            ),
        )
        .await
        .unwrap();
    let sig = tokio::time::timeout(Duration::from_secs(5), added.next())
        .await
        .expect("TriageAdded within 5 s")
        .unwrap();
    let item: Value = serde_json::from_str(&sig.body().deserialize::<String>().unwrap()).unwrap();
    assert_eq!(item["source"], "sms");
    assert_eq!(item["title"], "Anna Virtanen");
    assert_eq!(item["bucket"], "today");
    let list: String = pilot.call("Triage", &(0u32,)).await.unwrap();
    let list: Value = serde_json::from_str(&list).unwrap();
    assert_eq!(list.as_array().unwrap().len(), 1, "{list}");
    assert_eq!(srv.seen("/v1/jev").len(), 1);
    // The monitor only watches: both notifications were still shown.
    assert_eq!(shown.lock().unwrap().len(), 2);
}

fn seg(marker: u8, payload: &[u8]) -> Vec<u8> {
    let len = u16::try_from(payload.len() + 2).unwrap().to_be_bytes();
    let mut v = vec![0xFF, marker, len[0], len[1]];
    v.extend_from_slice(payload);
    v
}

/// A small JPEG carrying EXIF with a location.
fn photo_with_exif() -> Vec<u8> {
    let mut v = vec![0xFF, 0xD8];
    v.extend(seg(0xE1, b"Exif\0\0GPS 60.1699N 24.9384E"));
    v.extend(seg(0xDB, &[0; 65]));
    v.extend(seg(0xC0, &[8, 0, 120, 0, 160, 1, 1, 0x11, 0]));
    v.extend(seg(0xC4, &[0; 20]));
    v.extend(seg(0xDA, &[1, 1, 0, 0, 63, 0]));
    v.extend_from_slice(&[0x12, 0x34, 0xFF, 0xD9]);
    v
}

fn b64decode(s: &str) -> Vec<u8> {
    const A: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = Vec::new();
    let (mut acc, mut bits) = (0u32, 0);
    for c in s.bytes().filter(|&c| c != b'=') {
        acc = (acc << 6) | u32::try_from(A.iter().position(|&a| a == c).unwrap()).unwrap();
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push(u8::try_from((acc >> bits) & 0xFF).unwrap());
        }
    }
    out
}

#[tokio::test]
async fn a_camera_turn_sends_the_photo_without_metadata() {
    let srv = FakeHttp::start(|req: &common::Seen, _| match req.path.as_str() {
        "/v1/jev" => Reply::ok(jev_reply(&[("camera_vision", 0.95)], 0.2, 0.0)),
        _ => Reply::us(chat_text("A ripe avocado.")),
    })
    .await;
    let d = common::daemon(&srv.base, &Arc::new(Log::default()), None);

    // Off at first run: no camera card, and Look sends nothing.
    let r = d.pipeline.ask("what am I looking at", false).await;
    assert!(
        matches!(&r.cards[0], Card::Offline { text } if text.contains("camera")),
        "{r:?}"
    );
    let r = d.pipeline.look("is it ripe?", &photo_with_exif()).await;
    assert_eq!(r.route, "no-consent");
    assert!(srv.seen("/v1/llm/chat/completions").is_empty());

    d.live.lock().unwrap().consent.vision = true;
    let r = d.pipeline.ask("is this avocado ripe", false).await;
    assert_eq!(
        r.cards[0],
        Card::Camera {
            text: "Take a photo and Pilot will look at it.".into(),
            question: "is this avocado ripe".into()
        }
    );
    let r = d
        .pipeline
        .look("Is it ripe? Ask Anna Virtanen", &photo_with_exif())
        .await;
    assert_eq!(r.route, "vision");
    assert_eq!(
        r.cards[0],
        Card::Response {
            text: "A ripe avocado.".into(),
            source: "qwen".into()
        }
    );
    let req = &srv.seen("/v1/llm/chat/completions")[0].body;
    let parts = req["messages"][1]["content"].as_array().unwrap();
    assert_eq!(parts[0]["text"], "Is it ripe? Ask <CONTACT_1>");
    let url = parts[1]["image_url"]["url"].as_str().unwrap();
    let jpeg = b64decode(url.strip_prefix("data:image/jpeg;base64,").unwrap());
    assert_eq!(&jpeg[..2], &[0xFF, 0xD8]);
    assert!(!String::from_utf8_lossy(&jpeg).contains("GPS"));
    let exif_segment = 4 + b"Exif\0\0GPS 60.1699N 24.9384E".len();
    assert_eq!(jpeg.len(), photo_with_exif().len() - exif_segment);
    assert!(req["tools"].as_array().is_none_or(Vec::is_empty));

    // Not a photo: refused on the device.
    let r = d.pipeline.look("what is it", b"GIF89a").await;
    assert!(
        matches!(&r.cards[0], Card::Error { text } if text.contains("not a JPEG")),
        "{r:?}"
    );
    assert_eq!(srv.seen("/v1/llm/chat/completions").len(), 1);
}

#[tokio::test]
async fn the_model_asking_for_the_camera_gets_a_card_not_a_photo() {
    let srv = FakeHttp::start(|req: &common::Seen, _| match req.path.as_str() {
        "/v1/jev" => Reply::ok(jev_reply(
            &[("open_ended", 0.7), ("camera_vision", 0.2)],
            0.7,
            0.0,
        )),
        _ => Reply::us(chat_tool("camera_capture", "{}")),
    })
    .await;
    let d = common::daemon(&srv.base, &Arc::new(Log::default()), None);
    d.live.lock().unwrap().consent.vision = true;
    let r = d.pipeline.ask("which plant is this", false).await;
    assert!(
        matches!(&r.cards[0], Card::Camera { question, .. } if question == "which plant is this"),
        "{r:?}"
    );
    assert_eq!(srv.seen("/v1/llm/chat/completions").len(), 1);
}

/// Pilot's entry in the Events view (`events.rs`): one notification in
/// its own category, updated in place, gone once opened.
#[tokio::test]
#[allow(clippy::too_many_lines, reason = "one end-to-end scenario")]
async fn triage_results_keep_one_events_view_entry() {
    let srv = FakeHttp::start(|req: &common::Seen, _| {
        let body = req.body["state"]["event"]["body"]
            .as_str()
            .unwrap_or("")
            .to_owned();
        if body.contains("now") {
            triage_reply(0.5, "act_now", 2.0)
        } else if body.contains("today") {
            triage_reply(0.3, "today", 1.0)
        } else {
            triage_reply(0.1, "later", 0.0)
        }
    })
    .await;
    let bus = TestBus::start();
    let dir = tempfile::tempdir().unwrap();
    let opened = dir.path().join("opened");
    let mut cfg = common::config(&srv.base);
    cfg.events.open_command = vec![
        "sh".into(),
        "-c".into(),
        format!("echo opened > {}", opened.display()),
    ];
    cfg.events.notification = true;
    let sheet = dir.path().join("sheet");
    cfg.sheet.open_command = vec![
        "sh".into(),
        "-c".into(),
        format!("echo sheet > {}", sheet.display()),
    ];
    let log = Arc::new(Log::default());
    let d = Arc::new(
        pilotd::daemon::build(pilotd::daemon::Options {
            config: cfg,
            data_dir: Some(dir.path().to_owned()),
            session: None,
            system: None,
            adapters: Some(common::fake_adapters(&log)),
            credential: Some(pilotd::remote::Credential::None),
            licence: None,
            now: || pilotd::localtime::LocalNow::fixed_utc(1_790_966_550),
        })
        .unwrap(),
    );
    let entries = || -> Vec<String> {
        log.all()
            .into_iter()
            .filter(|l| l.starts_with("notify") || l.starts_with("close"))
            .collect()
    };
    d.live.lock().unwrap().consent.triage = true;

    // Not news: no entry.
    d.triage.handle(&sms("Shop", "newsletter")).await.unwrap();
    d.events.refresh().await;
    assert!(entries().is_empty(), "{:?}", entries());

    d.triage
        .handle(&sms("Anna Virtanen", "call me now"))
        .await
        .unwrap();
    d.events.refresh().await;
    d.triage
        .handle(&sms("Dentist", "appointment today"))
        .await
        .unwrap();
    d.events.refresh().await;
    let e = entries();
    assert_eq!(e.len(), 2, "{e:?}");
    assert!(
        e[0].starts_with("notify 1 1 to act on now | Anna Virtanen | "),
        "{}",
        e[0]
    );
    assert!(
        e[1].starts_with("notify 1 1 to act on now, 1 for today | Anna Virtanen · Dentist | "),
        "{}",
        e[1]
    );
    for hint in [
        "category=x-shipwright.pilot.triage",
        "urgency=0",
        "x-nemo-remote-action-default=org.shipwright.Pilot /org/shipwright/Pilot org.shipwright.Pilot1 OpenEvents",
    ] {
        assert!(e[1].contains(hint), "{hint} in {}", e[1]);
    }
    assert!(
        !e[1].contains("preview") && !e[1].contains("call me now"),
        "no popup, no message text: {}",
        e[1]
    );

    // Tapped: Lipstick calls OpenEvents on the bus.
    let server = bus.connect().await;
    pilotd::daemon::serve_on(&d, &server).await.unwrap();
    let client = bus.connect().await;
    // Uncached: the property is read back right after the call, before the
    // PropertiesChanged signal would refresh a cache.
    let p: zbus::Proxy<'_> = zbus::proxy::Builder::new(&client)
        .destination("org.shipwright.Pilot")
        .unwrap()
        .path("/org/shipwright/Pilot")
        .unwrap()
        .interface("org.shipwright.Pilot1")
        .unwrap()
        .cache_properties(zbus::proxy::CacheProperties::No)
        .build()
        .await
        .unwrap();
    let before: u32 = p.get_property("EventsRequested").await.unwrap();
    p.call::<_, _, ()>("OpenEvents", &()).await.unwrap();
    let after: u32 = p.get_property("EventsRequested").await.unwrap();
    assert_eq!(after, before + 1);
    assert_eq!(entries().last().unwrap(), "close 1");
    for _ in 0..50 {
        if opened.exists() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    assert!(opened.exists(), "open_command ran");

    // The widget's view of the same: nothing new once opened.
    let s: String = p.call("EventsSummary", &()).await.unwrap();
    assert_eq!(s, "{}");

    // The system-wide gesture (shoal-pilot-gesture-patch) calls ShowSheet.
    let before: u32 = p.get_property("SheetRequested").await.unwrap();
    p.call::<_, _, ()>("ShowSheet", &()).await.unwrap();
    let after: u32 = p.get_property("SheetRequested").await.unwrap();
    assert_eq!(after, before + 1);
    for _ in 0..50 {
        if sheet.exists() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    assert!(sheet.exists(), "[sheet] open_command ran");
    // Seen: nothing new, no entry.
    d.events.refresh().await;
    assert_eq!(entries().last().unwrap(), "close 1");

    // A new result brings it back; withdrawing consent or the privacy
    // switch removes it.
    tokio::time::sleep(Duration::from_millis(5)).await;
    d.triage
        .handle(&sms("Bank", "act now please"))
        .await
        .unwrap();
    d.events.refresh().await;
    let s: String = p.call("EventsSummary", &()).await.unwrap();
    assert_eq!(
        serde_json::from_str::<Value>(&s).unwrap(),
        json!({"summary": "1 to act on now", "titles": "Bank"})
    );
    assert!(
        entries()
            .last()
            .unwrap()
            .starts_with("notify 3 1 to act on now | Bank"),
        "{:?}",
        entries()
    );
    p.call::<_, _, ()>("SetConsent", &("triage", false))
        .await
        .unwrap();
    assert_eq!(entries().last().unwrap(), "close 3");
    p.call::<_, _, ()>("SetConsent", &("triage", true))
        .await
        .unwrap();
    assert!(
        entries().last().unwrap().starts_with("notify 4 "),
        "{:?}",
        entries()
    );
    d.apply_privacy(true, Some(&server)).await;
    assert_eq!(entries().last().unwrap(), "close 4");
}

#[tokio::test]
async fn the_calendar_is_not_read_while_triage_is_off() {
    use pilotd::triage::{CalendarPoll, CalendarPoller};
    let srv = FakeHttp::start(|_: &common::Seen, _| triage_reply(0.1, "later", 0.0)).await;
    let log = Arc::new(Log::default());
    let d = common::daemon(&srv.base, &log, None);
    let (tx, mut rx) = tokio::sync::mpsc::channel(8);
    let reads = || {
        log.all()
            .iter()
            .filter(|l| l.starts_with("calendar"))
            .count()
    };
    let mut poller = CalendarPoller::default();

    // Off (the first-run default): mkcal is never touched.
    for _ in 0..3 {
        assert_eq!(
            poller.poll(&d.adapters, &d.triage, &tx).await,
            Ok(CalendarPoll::Inactive)
        );
    }
    assert_eq!(reads(), 0);

    // On: the first read is the baseline and reports nothing.
    d.live.lock().unwrap().consent.triage = true;
    assert_eq!(
        poller.poll(&d.adapters, &d.triage, &tx).await,
        Ok(CalendarPoll::Read)
    );
    assert_eq!(reads(), 1);
    assert!(rx.try_recv().is_err());

    // The privacy switch stops reads too.
    d.offline_ctl.set(true);
    assert_eq!(
        poller.poll(&d.adapters, &d.triage, &tx).await,
        Ok(CalendarPoll::Inactive)
    );
    assert_eq!(reads(), 1);
}
