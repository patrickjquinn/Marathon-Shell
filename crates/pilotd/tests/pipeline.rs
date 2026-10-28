// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The whole pipeline against fake Jev and LLM servers: routing by the
//! section 5.2 thresholds, redaction on the wire, placeholder restore,
//! region fail-closed, tool validation with one retry, confirmation cards,
//! the privacy switch, the Lighthouse scorer and the egress log.

mod common;

use std::sync::Arc;
use std::time::Duration;

use common::{chat_text, chat_tool, daemon, jev_reply, FakeHttp, Log, Reply};
use pilotd::pipeline::Card;
use serde_json::{json, Value};

fn route_server(
    jev: Value,
    llm: impl Fn(usize) -> Reply + Send + Sync + 'static,
) -> impl Fn(&common::Seen, usize) -> Reply + Send + Sync + 'static {
    move |req, i| match req.path.as_str() {
        "/v1/jev" => Reply::ok(jev.clone()),
        "/v1/llm/chat/completions" => llm(i),
        _ => Reply {
            status: 404,
            headers: vec![],
            body: json!({}),
            delay: Duration::ZERO,
        },
    }
}

fn text_of(card: &Card) -> String {
    match card {
        Card::Response { text, .. }
        | Card::Clarify { text, .. }
        | Card::Offline { text }
        | Card::Camera { text, .. }
        | Card::Error { text }
        | Card::Timer { text, .. }
        | Card::Alarm { text, .. }
        | Card::Reminder { text, .. }
        | Card::Agenda { text, .. }
        | Card::Answer { text, .. }
        | Card::Memory { text, .. } => text.clone(),
        Card::Confirm { detail, .. } => detail.clone(),
    }
}

#[tokio::test]
async fn confident_intent_runs_the_handler_without_an_llm() {
    let srv = FakeHttp::start(route_server(
        jev_reply(&[("reminder", 0.93), ("alarm", 0.05)], 0.05, 0.1),
        |_| panic!("no LLM call on the deterministic path"),
    ))
    .await;
    let log = Arc::new(Log::default());
    let d = daemon(&srv.base, &log, None);
    let r = d.pipeline.ask("Remind me to ring Anna at 7pm", false).await;
    assert_eq!(r.route, "handler");
    assert_eq!(
        text_of(&r.cards[0]),
        "I'll remind you to ring Anna at 19:00."
    );
    // Original text, on the device, for the reminder itself.
    let midnight = 1_790_966_550 - (18 * 3600 + 42 * 60 + 30);
    assert_eq!(
        log.all(),
        [format!("reminder ring Anna @{}", midnight + 19 * 3600)]
    );
    // Redacted text on the wire, in the section 5.1 shape.
    let sent = &srv.seen("/v1/jev")[0].body;
    assert_eq!(sent["model"], "jev-latest");
    assert_eq!(
        sent["state"]["utterance"],
        "Remind me to ring <CONTACT_1> at 7pm"
    );
    assert!(sent["state"]["local_time"]
        .as_str()
        .unwrap()
        .starts_with("18:42, "));
    assert!(sent["state"].get("context").is_none(), "no unknown fields");
    // Jev's guidance: options described, literal yes/no questions.
    assert!(sent["questions"]["intent"]["criteria"]["timer"].is_string());
    assert!(sent["questions"]["needs_web"]["criteria"]["true"].is_string());
    assert_eq!(sent["questions"]["intent"]["type"], "choice");
    assert_eq!(
        sent["questions"]["intent"]["criteria"]
            .as_object()
            .unwrap()
            .len(),
        17
    );
    assert!(sent["questions"]["ambiguity"]["criteria"][2]
        .as_str()
        .unwrap()
        .starts_with("A detail the request cannot do without"));
    // Egress: one Jev call, logged without payload; decision recorded.
    let eg = d.store.egress(0).unwrap();
    assert_eq!(eg.len(), 1);
    assert_eq!(
        (
            eg[0].provider.as_str(),
            eg[0].purpose.as_str(),
            eg[0].result.as_str()
        ),
        ("jev", "decide", "ok")
    );
    assert!(eg[0].bytes_out > 0);
    let dec = d.store.decisions(0).unwrap();
    assert_eq!(
        (dec[0].route.as_str(), dec[0].outcome.as_str()),
        ("handler", "done")
    );
}

#[tokio::test]
async fn ambiguity_asks_one_templated_question_then_completes_locally() {
    let srv = FakeHttp::start(route_server(
        jev_reply(&[("timer", 0.9)], 0.05, 1.6),
        |_| panic!("no LLM call when clarifying"),
    ))
    .await;
    let log = Arc::new(Log::default());
    let d = daemon(&srv.base, &log, None);
    let r = d.pipeline.ask("set a timer", false).await;
    assert_eq!(r.route, "clarify");
    assert_eq!(
        r.cards[0],
        Card::Clarify {
            text: "How long should the timer be?".into(),
            intent: "timer".into()
        }
    );
    let r = d.pipeline.ask("ten minutes", false).await;
    assert_eq!(r.route, "clarified");
    assert_eq!(text_of(&r.cards[0]), "Timer set for 10 minutes.");
    assert_eq!(
        srv.seen("/v1/jev").len(),
        1,
        "the answer needs no second Jev call"
    );
    assert_eq!(log.all(), ["timer 600 None"]);
}

#[tokio::test]
async fn an_answer_that_does_not_complete_the_request_continues_it() {
    let srv = FakeHttp::start(route_server(
        jev_reply(&[("timer", 0.9)], 0.05, 1.6),
        |_| panic!("no LLM call when clarifying"),
    ))
    .await;
    let log = Arc::new(Log::default());
    let d = daemon(&srv.base, &log, None);
    assert_eq!(d.pipeline.ask("set a timer", false).await.route, "clarify");
    // Not a length on its own: the whole request goes on, not "a long one"
    // as a new conversation.
    let r = d.pipeline.ask("a long one", false).await;
    assert_eq!(r.route, "clarify");
    assert_eq!(
        srv.seen("/v1/jev")[1].body["state"]["utterance"],
        "set a timer a long one"
    );
    assert!(log.all().is_empty());
}

#[tokio::test]
async fn handler_intent_with_missing_slot_clarifies() {
    let srv = FakeHttp::start(route_server(
        jev_reply(&[("alarm", 0.95)], 0.0, 0.2),
        |_| panic!(),
    ))
    .await;
    let d = daemon(&srv.base, &Arc::new(Log::default()), None);
    let r = d.pipeline.ask("wake me up", false).await;
    assert_eq!(
        text_of(&r.cards[0]),
        "What time should I set the alarm for?"
    );
}

#[tokio::test]
async fn a_timer_is_corrected_and_cancelled() {
    let srv = FakeHttp::start(route_server(
        jev_reply(&[("timer", 0.95)], 0.0, 0.2),
        |_| panic!(),
    ))
    .await;
    let log = Arc::new(Log::default());
    let d = daemon(&srv.base, &log, None);
    d.pipeline.ask("Set a timer for 5 minutes", false).await;
    let r = d.pipeline.ask("Make it 10 minutes instead", false).await;
    assert_eq!(text_of(&r.cards[0]), "Timer set for 10 minutes.");
    // The 5-minute timer (the first one set) gave way to the new one.
    let all = log.all();
    assert_eq!(all[0], "timer 300 None");
    assert_eq!(all[1], "timer 600 None");
    assert_eq!(all[2], "cancel 11", "{all:?}");
    let r = d.pipeline.ask("Cancel the timer", false).await;
    assert_eq!(text_of(&r.cards[0]), "Timer cancelled.");
    assert_eq!(log.all()[3], "cancel 12");
    // Nothing of that kind left to cancel: said so, nothing cancelled.
    let r = d.pipeline.ask("cancel my alarm", false).await;
    assert!(
        text_of(&r.cards[0]).starts_with("I haven't set an alarm"),
        "{:?}",
        r.cards
    );
    assert_eq!(log.all().len(), 4);
}

#[tokio::test]
async fn a_follow_up_is_asked_in_the_conversation_so_far() {
    let srv = FakeHttp::start(route_server(
        jev_reply(&[("open_ended", 0.8)], 0.9, 0.2),
        |i| {
            Reply::us(chat_text(match i {
                0 => "Sami Pienimäki runs Jolla.",
                _ => "He was born in 1978.",
            }))
        },
    ))
    .await;
    let d = daemon(&srv.base, &Arc::new(Log::default()), None);
    d.pipeline
        .ask("Who is the CEO of Jolla? Mail anna@example.org", false)
        .await;
    let r = d.pipeline.ask("How old is he?", false).await;
    assert_eq!(text_of(&r.cards[0]), "He was born in 1978.");
    let calls = srv.seen("/v1/llm/chat/completions");
    let msgs = calls[1].body["messages"].as_array().unwrap();
    let said: Vec<(&str, &str)> = msgs
        .iter()
        .map(|m| {
            (
                m["role"].as_str().unwrap(),
                m["content"].as_str().unwrap_or(""),
            )
        })
        .collect();
    // System, the first exchange (redacted as any question is), the follow-up.
    assert_eq!(said.len(), 4, "{said:?}");
    assert_eq!(said[1].0, "user");
    assert!(
        said[1].1.starts_with("Who is the CEO of Jolla?"),
        "{said:?}"
    );
    assert!(!said[1].1.contains("example.org"), "{said:?}");
    assert_eq!(said[2], ("assistant", "Sami Pienimäki runs Jolla."));
    assert_eq!(said[3], ("user", "How old is he?"));

    // A new conversation forgets it.
    d.pipeline.clear_history();
    d.pipeline.ask("How old is he?", false).await;
    let calls = srv.seen("/v1/llm/chat/completions");
    assert_eq!(calls[2].body["messages"].as_array().unwrap().len(), 2);
}

#[tokio::test]
async fn open_ended_goes_to_qwen_redacted_and_restored() {
    let srv = FakeHttp::start(route_server(
        jev_reply(&[("open_ended", 0.8), ("message", 0.1)], 0.9, 0.2),
        |_| {
            Reply::us(chat_text(
                "You could write to <CONTACT_1> at <EMAIL_1> and say thanks.",
            ))
        },
    ))
    .await;
    let d = daemon(&srv.base, &Arc::new(Log::default()), None);
    let r = d
        .pipeline
        .ask("How should I thank Anna Virtanen, anna@example.org?", false)
        .await;
    assert_eq!(r.route, "qwen");
    assert_eq!(
        text_of(&r.cards[0]),
        "You could write to Anna Virtanen at anna@example.org and say thanks."
    );
    let sent = &srv.seen("/v1/llm/chat/completions")[0].body;
    let wire = sent.to_string();
    assert!(
        !wire.contains("Anna") && !wire.contains("example.org"),
        "{wire}"
    );
    assert_eq!(sent["model"], "qwen/qwen3.8-27b");
    assert_eq!(
        sent["reasoning_effort"], "none",
        "thinking off for conversation"
    );
    assert!(sent["tools"]
        .as_array()
        .unwrap()
        .iter()
        .any(|t| t["function"]["name"] == "timer_set"));
    assert!(
        !sent["tools"].to_string().contains("messages_send"),
        "unavailable tools are not offered"
    );
    let eg = d.store.egress(0).unwrap();
    assert_eq!(eg[0].provider, "groq");
    assert_eq!(eg[0].result, "ok");
}

#[tokio::test]
async fn hinted_route_passes_top_two_and_uses_low_effort() {
    let srv = FakeHttp::start(route_server(
        jev_reply(&[("calendar_add", 0.6), ("reminder", 0.3)], 0.4, 0.3),
        |_| Reply::us(chat_text("Sure.")),
    ))
    .await;
    let d = daemon(&srv.base, &Arc::new(Log::default()), None);
    let r = d.pipeline.ask("dentist thursday", false).await;
    assert_eq!(r.route, "qwen_hints");
    let sent = &srv.seen("/v1/llm/chat/completions")[0].body;
    let system = sent["messages"][0]["content"].as_str().unwrap();
    assert!(
        system.contains("calendar_add (0.60), reminder (0.30)"),
        "{system}"
    );
    assert_eq!(sent["reasoning_effort"], "low");
}

#[tokio::test]
async fn reply_outside_the_allowed_regions_is_dropped() {
    // The default allowed regions are eu and us: both answer.
    for region in ["us", "EU"] {
        let srv = FakeHttp::start(route_server(
            jev_reply(&[("open_ended", 0.9)], 0.9, 0.0),
            move |_| Reply::stamped(chat_text("Once upon a time."), region),
        ))
        .await;
        let d = daemon(&srv.base, &Arc::new(Log::default()), None);
        let r = d.pipeline.ask("tell me a story", false).await;
        assert_eq!(text_of(&r.cards[0]), "Once upon a time.", "{region}");
    }

    let srv = FakeHttp::start(route_server(
        jev_reply(&[("open_ended", 0.9)], 0.9, 0.0),
        |_| Reply::stamped(chat_text("secret answer"), "ap-south"),
    ))
    .await;
    let d = daemon(&srv.base, &Arc::new(Log::default()), None);
    let r = d.pipeline.ask("tell me a story", false).await;
    let t = text_of(&r.cards[0]);
    assert!(t.contains("couldn't confirm where it was processed"), "{t}");
    assert!(!t.contains("secret"));
    let eg = d.store.egress(0).unwrap();
    assert_eq!(eg[0].result, "region-blocked");

    let srv = FakeHttp::start(route_server(
        jev_reply(&[("open_ended", 0.9)], 0.9, 0.0),
        |_| Reply::ok(chat_text("no header at all")),
    ))
    .await;
    let d = daemon(&srv.base, &Arc::new(Log::default()), None);
    let r = d.pipeline.ask("tell me a story", false).await;
    assert!(matches!(r.cards[0], Card::Error { .. }));
}

#[tokio::test]
async fn invalid_tool_call_is_returned_once_then_the_turn_fails() {
    let srv = FakeHttp::start(route_server(
        jev_reply(&[("timer", 0.6), ("alarm", 0.3)], 0.2, 0.2),
        |_| Reply::us(chat_tool("timer_set", r#"{"seconds": "ten"}"#)),
    ))
    .await;
    let log = Arc::new(Log::default());
    let d = daemon(&srv.base, &log, None);
    let r = d.pipeline.ask("timer please, about ten", false).await;
    assert_eq!(
        text_of(&r.cards[0]),
        "Pilot couldn't do that. Try asking another way."
    );
    let calls = srv.seen("/v1/llm/chat/completions");
    assert_eq!(calls.len(), 2, "rejected once, back to the model once");
    let msgs = calls[1].body["messages"].as_array().unwrap();
    let tool_msg = msgs.iter().find(|m| m["role"] == "tool").unwrap();
    assert!(tool_msg["content"]
        .as_str()
        .unwrap()
        .contains("/seconds: expected integer"));
    assert!(log.all().is_empty(), "nothing executed");
    assert_eq!(d.store.decisions(0).unwrap()[0].outcome, "failed");
}

#[tokio::test]
async fn corrected_tool_call_runs_and_the_model_summarises() {
    let srv = FakeHttp::start(route_server(
        jev_reply(&[("timer", 0.6), ("alarm", 0.3)], 0.2, 0.2),
        |i| match i {
            0 => Reply::us(chat_tool("timer_set", r#"{"seconds": "ten"}"#)),
            1 => Reply::us(chat_tool(
                "timer_set",
                r#"{"seconds": 600, "label": "tea"}"#,
            )),
            _ => Reply::us(chat_text("Your tea timer is running.")),
        },
    ))
    .await;
    let log = Arc::new(Log::default());
    let d = daemon(&srv.base, &log, None);
    let r = d.pipeline.ask("tea timer, ten minutes-ish", false).await;
    // The timer's own card first, then the model's words.
    assert!(matches!(&r.cards[0], Card::Timer { seconds: 600, label: Some(l), .. } if l == "tea"));
    assert_eq!(text_of(&r.cards[1]), "Your tea timer is running.");
    assert_eq!(log.all(), ["timer 600 Some(\"tea\")"]);
    let third = &srv.seen("/v1/llm/chat/completions")[2].body;
    assert_eq!(third["reasoning_effort"], "low");
    let last = third["messages"]
        .as_array()
        .unwrap()
        .last()
        .unwrap()
        .clone();
    assert!(last["content"]
        .as_str()
        .unwrap()
        .contains("Timer set for 10 minutes"));
}

#[tokio::test]
async fn outbound_call_waits_for_a_confirmation_card() {
    let srv = FakeHttp::start(route_server(jev_reply(&[("call", 0.95)], 0.1, 0.1), |_| {
        Reply::us(chat_tool("call_dial", r#"{"number": "<PHONE_1>"}"#))
    }))
    .await;
    let log = Arc::new(Log::default());
    let d = daemon(&srv.base, &log, None);
    let r = d.pipeline.ask("call +358 40 123 4567", false).await;
    let Card::Confirm {
        id,
        title,
        detail,
        tool,
        outbound,
        ..
    } = &r.cards[0]
    else {
        panic!("{r:?}")
    };
    assert_eq!(
        (title.as_str(), detail.as_str(), tool.as_str()),
        ("Call", "Call +358 40 123 4567", "call.dial")
    );
    assert!(*outbound);
    assert!(log.all().is_empty(), "nothing dialled before the yes");
    assert!(!srv.seen("/v1/llm/chat/completions")[0]
        .body
        .to_string()
        .contains("358"));

    let done = d.pipeline.confirm(id, true).await;
    assert_eq!(text_of(&done.cards[0]), "Calling +358 40 123 4567.");
    assert_eq!(log.all(), ["dial +358 40 123 4567"]);
    assert_eq!(d.store.decisions(0).unwrap()[0].outcome, "confirmed");
    // A card is good for one answer.
    let again = d.pipeline.confirm(id, true).await;
    assert!(matches!(again.cards[0], Card::Error { .. }));

    let r = d.pipeline.ask("call +358 40 123 4567", false).await;
    let Card::Confirm { id, .. } = &r.cards[0] else {
        panic!()
    };
    let no = d.pipeline.confirm(id, false).await;
    assert_eq!(text_of(&no.cards[0]), "Cancelled.");
    assert_eq!(log.all().len(), 1);
}

#[tokio::test]
async fn flight_mode_needs_a_card_wifi_does_not() {
    let srv = FakeHttp::start(route_server(
        jev_reply(&[("device_toggle", 0.9)], 0.1, 0.1),
        |i| match i {
            0 => Reply::us(chat_tool(
                "device_toggle",
                r#"{"target": "wifi", "on": false}"#,
            )),
            1 => Reply::us(chat_tool(
                "device_toggle",
                r#"{"target": "flight_mode", "on": true}"#,
            )),
            _ => Reply::us(chat_text("ok")),
        },
    ))
    .await;
    let log = Arc::new(Log::default());
    let d = daemon(&srv.base, &log, None);
    let r = d.pipeline.ask("wifi off then flight mode", false).await;
    assert_eq!(log.all(), ["toggle Wifi false"]);
    assert!(matches!(&r.cards[0], Card::Confirm { tool, .. } if tool == "device.toggle"));
}

#[tokio::test]
async fn privacy_switch_offline_keeps_local_intents_and_sends_nothing() {
    let srv =
        FakeHttp::start(|_: &common::Seen, _| panic!("no network while the switch is engaged"))
            .await;
    let log = Arc::new(Log::default());
    let d = daemon(&srv.base, &log, None);
    d.apply_privacy(true, None).await;
    assert!(d.offline.is_offline());
    assert_eq!(log.all(), ["speech stopped", "voice stopped"]);
    let r = d.pipeline.ask("set a timer for 5 minutes", false).await;
    assert_eq!(r.route, "offline");
    assert_eq!(text_of(&r.cards[0]), "Timer set for 5 minutes.");
    let r = d.pipeline.ask("pause", false).await;
    assert_eq!(text_of(&r.cards[0]), "Paused.");
    let r = d.pipeline.ask("why is the sky blue", false).await;
    assert!(matches!(r.cards[0], Card::Offline { .. }));
    assert!(d.store.egress(0).unwrap().is_empty());
    assert!(srv.seen.lock().unwrap().is_empty());
}

#[tokio::test]
async fn engaging_the_switch_abandons_a_request_in_flight() {
    let srv = FakeHttp::start(|_: &common::Seen, _| {
        let mut r = Reply::ok(jev_reply(&[("open_ended", 0.9)], 0.9, 0.0));
        r.delay = Duration::from_secs(3);
        r
    })
    .await;
    let log = Arc::new(Log::default());
    let d = Arc::new(daemon(&srv.base, &log, None));
    let d2 = d.clone();
    let turn = tokio::spawn(async move {
        d2.pipeline
            .ask("what's the capital of Finland", false)
            .await
    });
    tokio::time::sleep(Duration::from_millis(300)).await;
    d.apply_privacy(true, None).await;
    let r = tokio::time::timeout(Duration::from_secs(1), turn)
        .await
        .expect("dropped at once, not after the reply")
        .unwrap();
    assert!(matches!(r.cards[0], Card::Offline { .. }), "{r:?}");
    assert_eq!(d.store.egress(0).unwrap()[0].result, "offline");
}

#[tokio::test]
async fn privacy_drops_pending_confirmations() {
    let srv = FakeHttp::start(route_server(jev_reply(&[("call", 0.95)], 0.1, 0.1), |_| {
        Reply::us(chat_tool("call_dial", r#"{"number": "112"}"#))
    }))
    .await;
    let log = Arc::new(Log::default());
    let d = daemon(&srv.base, &log, None);
    let r = d.pipeline.ask("call 112", false).await;
    let Card::Confirm { id, .. } = &r.cards[0] else {
        panic!()
    };
    d.apply_privacy(true, None).await;
    assert_eq!(d.pipeline.pending_count(), 0);
    let r = d.pipeline.confirm(id, true).await;
    assert!(matches!(r.cards[0], Card::Error { .. }));
    assert!(!log.all().iter().any(|l| l.starts_with("dial")));
}

#[tokio::test]
async fn jev_down_still_sets_a_timer() {
    let srv = FakeHttp::start(|_: &common::Seen, _| Reply {
        status: 503,
        headers: vec![],
        body: json!({}),
        delay: Duration::ZERO,
    })
    .await;
    let log = Arc::new(Log::default());
    let d = daemon(&srv.base, &log, None);
    let r = d.pipeline.ask("timer for 90 seconds", false).await;
    assert_eq!(r.route, "local");
    assert_eq!(text_of(&r.cards[0]), "Timer set for 1 minute 30 seconds.");
    assert_eq!(d.store.egress(0).unwrap()[0].result, "http-503");
    let r = d.pipeline.ask("tell me a joke", false).await;
    assert!(text_of(&r.cards[0]).contains("can't reach its cloud service"));
}

#[tokio::test]
async fn consent_withdrawn_means_local_only() {
    let srv = FakeHttp::start(|_: &common::Seen, _| panic!("no network without consent")).await;
    let d = daemon(&srv.base, &Arc::new(Log::default()), None);
    d.live.lock().unwrap().consent.text_qa = false;
    let r = d.pipeline.ask("what's on my calendar today", false).await;
    assert_eq!(r.route, "no-consent");
    let t = text_of(&r.cards[0]);
    assert!(
        t.starts_with("1 event today: ") && t.ends_with(" Standup."),
        "{t}"
    );
    let r = d.pipeline.ask("write me a poem", false).await;
    assert!(text_of(&r.cards[0]).starts_with("Cloud answers are off"));
}

#[tokio::test]
async fn lighthouse_scorer_drives_the_same_routing() {
    // Scorer: intent puts 0.9 on the second label (timer), the noul says
    // no, the score sits on "clear".
    let srv = FakeHttp::start(|req: &common::Seen, _| match req.path.as_str() {
        "/v1/score" => {
            let n = req.body["label_token_ids"].as_array().unwrap().len();
            let probs: Vec<f64> = if n == 17 {
                (0..17)
                    .map(|i| if i == 1 { 0.9 } else { 0.1 / 16.0 })
                    .collect()
            } else if req.body["label_token_ids"] == json!([100, 101]) {
                vec![0.05, 0.95]
            } else {
                vec![0.9, 0.08, 0.02]
            };
            Reply::ok(json!({"scores": [probs]}))
        }
        _ => panic!("unexpected {}", req.path),
    })
    .await;
    let log = Arc::new(Log::default());
    let d = daemon(&srv.base, &log, None);
    d.pipeline.set_backends((d.factory)("lighthouse").unwrap());
    let r = d.pipeline.ask("15 minute timer", false).await;
    assert_eq!(r.route, "handler");
    assert_eq!(log.all(), ["timer 900 None"]);
    let calls = srv.seen("/v1/score");
    assert_eq!(calls.len(), 4, "one score request per question");
    assert!(calls.iter().all(|c| c.body["apply_softmax"] == true));
    let eg = d.store.egress(0).unwrap();
    assert!(eg.iter().all(|e| e.provider == "lighthouse-score"));
}

#[tokio::test]
async fn cancel_marks_the_previous_turn_corrected() {
    let srv = FakeHttp::start(|req: &common::Seen, i| {
        assert_eq!(req.path, "/v1/jev");
        Reply::ok(if i == 0 {
            jev_reply(&[("alarm", 0.95)], 0.0, 0.1)
        } else {
            jev_reply(&[("cancel", 0.97)], 0.0, 0.0)
        })
    })
    .await;
    let d = daemon(&srv.base, &Arc::new(Log::default()), None);
    let first = d.pipeline.ask("alarm at 6", false).await;
    let r = d.pipeline.ask("no, cancel that", false).await;
    assert_eq!(text_of(&r.cards[0]), "Cancelled.");
    let decisions = d.store.decisions(0).unwrap();
    let prev = decisions.iter().find(|x| x.turn == first.turn).unwrap();
    assert_eq!(prev.outcome, "corrected");
}

#[tokio::test]
async fn device_token_goes_in_the_authorization_header() {
    let srv = FakeHttp::start(route_server(
        jev_reply(&[("media", 0.95)], 0.0, 0.0),
        |_| panic!(),
    ))
    .await;
    let dir = tempfile::tempdir().unwrap();
    let token = dir.path().join("device-token");
    std::fs::write(&token, "dev-token-123\n").unwrap();
    // A user who made the first-run choice: nothing goes out before it.
    std::fs::write(dir.path().join("settings.json"), r#"{"onboarded": true}"#).unwrap();
    let mut cfg = common::config(&srv.base);
    cfg.token_file = Some(token);
    let log = Arc::new(Log::default());
    let d = pilotd::daemon::build(pilotd::daemon::Options {
        config: cfg,
        data_dir: Some(dir.path().to_owned()),
        session: None,
        system: None,
        adapters: Some(common::fake_adapters(&log)),
        credential: None,
        licence: None,
        now: || pilotd::localtime::LocalNow::fixed_utc(1_790_966_550),
    })
    .unwrap();
    let r = d.pipeline.ask("next track", false).await;
    assert_eq!(text_of(&r.cards[0]), "Next track.");
    assert_eq!(
        srv.seen("/v1/jev")[0].auth.as_deref(),
        Some("Bearer dev-token-123")
    );
    assert!(dir.path().join("pilot.db").exists());
}

#[tokio::test]
async fn device_token_is_exchanged_for_the_licence_and_renewed_after_401() {
    use base64::Engine as _;
    let payload = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .encode(br#"{"lid":"lic_1","dev":"d","plan":"one_off","iat":0,"exp":4000000000}"#);
    let relay_token = format!("pr1.{payload}.sig");
    let token = relay_token.clone();
    let srv = FakeHttp::start(move |req: &common::Seen, i| match req.path.as_str() {
        "/v1/token" => {
            assert_eq!(req.body["licence"], "reef-licence-token");
            assert!(req.body["device"].as_str().unwrap().len() >= 8);
            Reply::ok(json!({"token": token, "expires_at": 4_000_000_000_i64}))
        }
        "/v1/jev" if i == 1 => Reply {
            status: 401,
            headers: vec![],
            body: json!({}),
            delay: Duration::ZERO,
        },
        _ => Reply::ok(jev_reply(&[("media", 0.95)], 0.0, 0.0)),
    })
    .await;
    let dir = tempfile::tempdir().unwrap();
    std::fs::write(dir.path().join("settings.json"), r#"{"onboarded": true}"#).unwrap();
    let log = Arc::new(Log::default());
    let d = pilotd::daemon::build(pilotd::daemon::Options {
        config: common::config(&srv.base),
        data_dir: Some(dir.path().to_owned()),
        session: None,
        system: None,
        adapters: Some(common::fake_adapters(&log)),
        credential: None,
        licence: Some(Arc::new("reef-licence-token".to_owned())),
        now: || pilotd::localtime::LocalNow::fixed_utc(1_790_966_550),
    })
    .unwrap();
    d.pipeline.ask("pause", false).await;
    assert_eq!(
        srv.seen("/v1/jev")[0].auth.as_deref(),
        Some(format!("Bearer {relay_token}").as_str())
    );
    assert_eq!(
        std::fs::read_to_string(dir.path().join("device-token")).unwrap(),
        relay_token
    );
    let device = std::fs::read_to_string(dir.path().join("device-id")).unwrap();
    // The relay refuses the token: it is dropped, and the next turn
    // exchanges the licence again with the same device id.
    let r = d.pipeline.ask("pause", false).await;
    assert_eq!(
        r.route, "local",
        "a timer-class intent still works while Jev refuses"
    );
    assert!(!dir.path().join("device-token").exists());
    d.pipeline.ask("pause", false).await;
    let ex = srv.seen("/v1/token");
    assert_eq!(ex.len(), 2);
    assert_eq!(ex[1].body["device"].as_str().unwrap(), device);
    let eg = d.store.egress(0).unwrap();
    assert!(eg
        .iter()
        .any(|e| e.provider == "relay" && e.purpose == "token" && e.result == "ok"));
}

#[tokio::test]
async fn spoken_turns_use_voice_consent_and_are_spoken_back() {
    let srv = FakeHttp::start(route_server(
        jev_reply(&[("open_ended", 0.9)], 0.9, 0.0),
        |_| Reply::us(chat_text("Helsinki.")),
    ))
    .await;
    let log = Arc::new(Log::default());
    let heard = Arc::new(std::sync::Mutex::new(vec![
        "set a timer for 2 minutes".to_owned(),
        "what is the capital of Finland".to_owned(),
        "what is the capital of Finland".to_owned(),
        String::new(),
        "!NoModel: getting speech recognition ready".to_owned(),
    ]));
    let d = pilotd::daemon::build(pilotd::daemon::Options {
        config: common::config(&srv.base),
        data_dir: None,
        session: None,
        system: None,
        adapters: Some(common::fake_adapters_hearing(&log, heard)),
        credential: Some(pilotd::remote::Credential::None),
        licence: None,
        now: || pilotd::localtime::LocalNow::fixed_utc(1_790_966_550),
    })
    .unwrap();
    let listen = || pilotd::daemon::listen_turn(&d.pipeline, &d.adapters, &d.offline);

    // Voice cloud consent is off by default: a timer still works locally.
    let r = listen().await;
    assert_eq!(r.route, "no-voice-consent");
    assert_eq!(r.transcript.as_deref(), Some("set a timer for 2 minutes"));
    assert!(r.spoken);
    assert_eq!(text_of(&r.cards[0]), "Timer set for 2 minutes.");
    let r = listen().await;
    assert!(
        matches!(r.cards[0], Card::Offline { .. }),
        "no cloud without voice consent"
    );
    assert!(srv.seen.lock().unwrap().is_empty());

    d.live.lock().unwrap().consent.voice_cloud = true;
    let r = listen().await;
    assert_eq!(text_of(&r.cards[0]), "Helsinki.");
    let r = listen().await;
    assert_eq!(r.route, "no-speech");
    assert_eq!(
        d.pipeline.last().unwrap().route,
        "no-speech",
        "recorded as the last turn"
    );
    let chat = srv.seen("/v1/llm/chat/completions");
    let system = chat.last().unwrap().body["messages"][0]["content"].to_string();
    assert!(system.contains("speech recognition heard"), "{system}");
    // The first press with no speech model: it is being fetched.
    let r = listen().await;
    assert_eq!(r.route, "voice-model");
    assert!(text_of(&r.cards[0]).contains("one-time download"));

    // The privacy switch closes the microphone: pilot-voice is not asked.
    d.apply_privacy(true, None).await;
    let before = log.all().iter().filter(|l| *l == "voice listened").count();
    let r = listen().await;
    assert_eq!(r.route, "offline");
    assert_eq!(
        log.all().iter().filter(|l| *l == "voice listened").count(),
        before
    );
    let said: Vec<String> = log
        .all()
        .into_iter()
        .filter(|l| l.starts_with("say "))
        .collect();
    assert_eq!(
        said,
        [
            "say Timer set for 2 minutes.",
            "say Spoken questions stay on this phone. To ask anything else by voice, turn on spoken questions in Settings.",
            "say Helsinki.",
            "say I didn't hear anything.",
            "say Getting speech recognition ready: a one-time download of about 78 MB. Try the microphone again in a minute."
        ]
    );
    assert!(log.all().contains(&"speech stopped".to_owned()));
}

#[tokio::test]
async fn memory_is_kept_on_the_phone_and_used_as_context() {
    let srv = FakeHttp::start(route_server(
        jev_reply(&[("open_ended", 0.95)], 0.9, 0.1),
        |_| Reply::us(chat_text("Anna would love that.")),
    ))
    .await;
    let log = Arc::new(Log::default());
    let d = daemon(&srv.base, &log, None);
    // Remembered with no model and no network.
    let r = d
        .pipeline
        .ask("Remember that my partner loves orchids", false)
        .await;
    assert_eq!(r.route, "memory");
    assert!(matches!(&r.cards[0], Card::Memory { action, facts, .. }
        if action == "remembered" && facts[0].fact == "my partner loves orchids"));
    assert!(srv.seen("/v1/jev").is_empty() && srv.seen("/v1/llm/chat/completions").is_empty());
    // Then part of what the model knows.
    d.pipeline.ask("what flowers should I buy?", false).await;
    let sent = &srv.seen("/v1/llm/chat/completions")[0].body;
    let system = sent["messages"][0]["content"].as_str().unwrap();
    assert!(system.contains("] my partner loves orchids"), "{system}");
    // Listed, then forgotten by a word in it.
    let r = d
        .pipeline
        .ask("what do you remember about me?", false)
        .await;
    assert!(
        matches!(&r.cards[0], Card::Memory { action, facts, .. } if action == "list" && facts.len() == 1)
    );
    let r = d.pipeline.ask("forget about the orchids", false).await;
    assert!(matches!(&r.cards[0], Card::Memory { action, .. } if action == "forgotten"));
    assert!(d.store.memories().unwrap().is_empty());
}

#[test]
fn answers_carry_no_em_dashes() {
    use pilotd::pipeline::plain_punctuation;
    assert_eq!(
        plain_punctuation("Lighthouses \u{2014} towers with lights \u{2014} guide ships."),
        "Lighthouses, towers with lights, guide ships."
    );
    assert_eq!(plain_punctuation("Done\u{2014}fast"), "Done, fast");
    assert_eq!(
        plain_punctuation("A spaced \u{2013} aside"),
        "A spaced, aside"
    );
    assert_eq!(
        plain_punctuation("From 2019\u{2013}2024"),
        "From 2019\u{2013}2024"
    );
}
