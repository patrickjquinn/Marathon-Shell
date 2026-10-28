// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Direct mode against fake upstreams: each key to its own upstream, no
//! token exchange, the region stamped from configuration (whatever the
//! upstream says), requests shaped as the relay shapes them.

mod common;

use std::os::unix::fs::PermissionsExt as _;
use std::sync::Arc;

use common::{chat_text, fake_adapters, jev_reply, FakeHttp, Log, Reply};
use pilotd::pipeline::Card;

fn config(base: &str, keys: &std::path::Path) -> pilotd::config::Config {
    pilotd::config::Config::parse(&format!(
        r#"
        timeout_secs = 5
        token_exchange_url = "{base}/v1/token"
        web_search_url = "{base}/v1/search"
        [privacy]
        source = "none"
        [direct]
        enabled = true
        key_file = "{keys}"
        jev_url = "{base}/direct/jev"
        llm_url = "{base}/direct/llm"
        [backends.standard.jev]
        kind = "jev"
        url = "{base}/v1/jev"
        [backends.standard.llm]
        url = "{base}/v1/llm/chat/completions"
        "#,
        keys = keys.display()
    ))
    .unwrap()
}

fn build(
    cfg: pilotd::config::Config,
) -> Result<pilotd::daemon::Daemon, pilotd::daemon::StartError> {
    pilotd::daemon::build(pilotd::daemon::Options {
        config: cfg,
        data_dir: None,
        session: None,
        system: None,
        adapters: Some(fake_adapters(&Arc::new(Log::default()))),
        credential: None,
        licence: None,
        now: || pilotd::localtime::LocalNow::fixed_utc(1_790_966_550),
    })
}

fn key_file(dir: &std::path::Path, mode: u32) -> std::path::PathBuf {
    let p = dir.join("keys.env");
    std::fs::write(
        &p,
        "PILOT_RELAY_GROQ_KEY=groq-test\nPILOT_RELAY_JEV_KEY=jev-test\n",
    )
    .unwrap();
    std::fs::set_permissions(&p, std::fs::Permissions::from_mode(mode)).unwrap();
    p
}

#[tokio::test]
async fn keys_go_straight_to_their_upstreams() {
    let srv = FakeHttp::start(|req, _| match req.path.as_str() {
        "/direct/jev" => Reply::ok(jev_reply(&[("open_ended", 0.9)], 0.9, 0.0)),
        // A region the upstream claims is not trusted: the configured one is.
        "/direct/llm" => Reply::stamped(chat_text("Once upon a time."), "ap-south"),
        _ => Reply::ok(serde_json::json!({})),
    })
    .await;
    let dir = tempfile::tempdir().unwrap();
    let keys = key_file(dir.path(), 0o600);
    let d = build(config(&srv.base, &keys)).unwrap();
    let r = d.pipeline.ask("tell me a story", false).await;
    match &r.cards[0] {
        Card::Response { text, .. } | Card::Answer { text, .. } => {
            assert_eq!(text, "Once upon a time.");
        }
        other => panic!("{other:?}"),
    }
    let jev = srv.seen("/direct/jev");
    let llm = srv.seen("/direct/llm");
    assert_eq!(jev[0].auth.as_deref(), Some("Bearer jev-test"));
    assert_eq!(llm[0].auth.as_deref(), Some("Bearer groq-test"));
    assert!(llm[0].body["max_completion_tokens"].as_u64().unwrap() <= 4096);
    assert!(srv.seen("/v1/token").is_empty() && srv.seen("/v1/jev").is_empty());
    let providers: Vec<String> = d
        .store
        .egress(0)
        .unwrap()
        .into_iter()
        .map(|e| e.provider)
        .collect();
    assert!(
        providers.contains(&"groq".to_owned()) && providers.contains(&"jev".to_owned()),
        "{providers:?}"
    );
}

#[tokio::test]
async fn a_key_file_others_can_read_is_refused() {
    let dir = tempfile::tempdir().unwrap();
    let keys = key_file(dir.path(), 0o644);
    let err = build(config("http://127.0.0.1:9", &keys)).err().unwrap();
    assert!(err.to_string().contains("chmod 600"), "{err}");
}

#[test]
fn without_the_key_file_the_relay_is_used() {
    let dir = tempfile::tempdir().unwrap();
    let mut cfg = config("http://127.0.0.1:9", &dir.path().join("keys.env"));
    let before = cfg.clone();
    assert!(pilotd::daemon::direct_mode(&mut cfg).unwrap().is_none());
    assert_eq!(cfg, before);
    // Off unless asked for, even with the file there.
    key_file(dir.path(), 0o600);
    cfg.direct.enabled = false;
    assert!(pilotd::daemon::direct_mode(&mut cfg).unwrap().is_none());
}
