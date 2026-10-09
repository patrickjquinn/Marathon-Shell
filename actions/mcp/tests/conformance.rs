// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! MCP conformance-style test: raw JSON-RPC (newline-delimited, as on stdio
//! and the Unix socket) against keel-mcp serving the Keel Actions test app
//! (keel/actions/tests/app, manifest from the generator's golden output).
//!
//! By default the app is a stand-in [`Backend`] answering as the test app
//! does. With `KEEL_MCP_BUS_TEST=1` (ctest `keel_mcp_conformance`, inside
//! `dbus-run-session` with the test app's activation file) the calls go
//! over the session bus to the real app, started by D-Bus activation.
//!
//! Covered: `initialize` (2025-11-25), `tools/list`, `tools/call` (result,
//! invalid arguments, find), `resources/templates/list`,
//! `resources/list`, `resources/read` (entity summary, context only when
//! user-initiated), `prompts/list`, `prompts/get`, the plan tools
//! (validation, confirmation, run), a stateless 2026-07-28 request without
//! `initialize`, and an unknown method.

use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use keel_mcp::backend::{Backend, BoxFuture, Bus, CallError, CallResult};
use keel_mcp::catalogue::Catalogue;
use keel_mcp::KeelMcp;
use rmcp::ServiceExt;
use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

fn manifest() -> Value {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../codegen/tests/golden/qml-notes/actions.json");
    serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
}

/// Answers as keel/actions/tests/app/NotesActions.qml does.
#[derive(Default)]
struct Notes {
    created: Mutex<u32>,
}

fn keel(code: &str, message: &str) -> CallError {
    CallError::Keel {
        code: code.into(),
        message: message.into(),
    }
}

impl Backend for Notes {
    fn running_manifests(&self) -> BoxFuture<'_, Vec<Value>> {
        Box::pin(async { Vec::new() })
    }
    fn invoke<'a>(
        &'a self,
        _: &'a str,
        action: &'a str,
        args: &'a Value,
        _: bool,
        _: Duration,
    ) -> BoxFuture<'a, CallResult> {
        Box::pin(async move {
            match action {
                "notes.create" => {
                    let mut n = self.created.lock().unwrap();
                    *n += 1;
                    let id = format!("n{}", *n + 2);
                    Ok(json!({ "id": id, "note": format!("keel://org.example.notes/note/{id}") }))
                }
                "notes.search" => Ok(json!({ "result": ["keel://org.example.notes/note/n2"] })),
                "notes.delete" if args["note"] == "keel://org.example.notes/note/n2" => {
                    Ok(json!({}))
                }
                "notes.delete" => Err(keel("Failed", "no such note")),
                _ => Err(keel("UnknownAction", "no such action")),
            }
        })
    }
    fn get_entity<'a>(&'a self, _: &'a str, _: &'a str, id: &'a str) -> BoxFuture<'a, CallResult> {
        Box::pin(async move {
            match id {
                "n2" => Ok(
                    json!({ "uri": "keel://org.example.notes/note/n2", "id": "n2", "title": "Trattoria Anna",
                                   "body": "Via Roma 1, booked for Friday", "tags": ["food"], "created": "2026-09-25T19:30:00Z" }),
                ),
                _ => Err(keel("NotAvailable", "no such item")),
            }
        })
    }
    fn find_entities<'a>(
        &'a self,
        _: &'a str,
        _: &'a str,
        query: &'a str,
        _: u32,
    ) -> BoxFuture<'a, CallResult> {
        Box::pin(async move {
            let items = if "trattoria anna".contains(&query.to_lowercase()) {
                json!([{ "uri": "keel://org.example.notes/note/n2", "id": "n2", "title": "Trattoria Anna", "tags": ["food"], "created": "2026-09-25T19:30:00Z" }])
            } else {
                json!([])
            };
            Ok(json!({ "items": items }))
        })
    }
    fn get_context<'a>(&'a self, _: &'a str) -> BoxFuture<'a, CallResult> {
        Box::pin(async {
            Ok(
                json!({ "app": "org.example.notes", "purpose": "reading a note", "entity": "keel://org.example.notes/note/n1", "text": "Shopping: Milk, bread" }),
            )
        })
    }
}

async fn server() -> KeelMcp {
    let backend: Arc<dyn Backend> = if std::env::var_os("KEEL_MCP_BUS_TEST").is_some() {
        Arc::new(Bus::session().await.expect("session bus"))
    } else {
        Arc::new(Notes::default())
    };
    let server = KeelMcp::new(backend, false);
    server.set_catalogue(Catalogue::build(vec![manifest()], Vec::new()));
    server
}

/// A client on one connection: newline-delimited JSON-RPC.
struct Client {
    write: tokio::io::WriteHalf<tokio::io::DuplexStream>,
    read: BufReader<tokio::io::ReadHalf<tokio::io::DuplexStream>>,
    next: u64,
}

impl Client {
    fn connect(server: KeelMcp) -> Self {
        let (ours, theirs) = tokio::io::duplex(1 << 20);
        let (r, w) = tokio::io::split(theirs);
        tokio::spawn(async move {
            if let Ok(running) = server.serve((r, w)).await {
                let _ = running.waiting().await;
            }
        });
        let (read, write) = tokio::io::split(ours);
        Self {
            write,
            read: BufReader::new(read),
            next: 1,
        }
    }

    async fn send(&mut self, message: &Value) {
        let mut line = message.to_string();
        line.push('\n');
        self.write.write_all(line.as_bytes()).await.unwrap();
    }

    /// A request and its response (the whole JSON-RPC message).
    async fn request(&mut self, method: &str, params: Value) -> Value {
        let id = self.next;
        self.next += 1;
        self.send(&json!({ "jsonrpc": "2.0", "id": id, "method": method, "params": params }))
            .await;
        loop {
            let mut line = String::new();
            let n = tokio::time::timeout(Duration::from_secs(60), self.read.read_line(&mut line))
                .await
                .expect("an answer in time")
                .unwrap();
            assert!(n > 0, "connection closed");
            let message: Value = serde_json::from_str(&line).unwrap();
            if message["id"] == json!(id) {
                assert_eq!(message["jsonrpc"], "2.0");
                return message;
            }
        }
    }

    async fn result(&mut self, method: &str, params: Value) -> Value {
        let response = self.request(method, params).await;
        assert!(response.get("error").is_none(), "{method}: {response}");
        response["result"].clone()
    }

    async fn call(&mut self, tool: &str, arguments: Value, meta: Value) -> Value {
        self.result(
            "tools/call",
            json!({ "name": tool, "arguments": arguments, "_meta": meta }),
        )
        .await
    }
}

fn text_of(result: &Value) -> &str {
    result["content"][0]["text"].as_str().unwrap_or_default()
}

#[tokio::test(flavor = "multi_thread")]
#[allow(clippy::too_many_lines, reason = "one session, step by step")]
async fn conformance() {
    let mut c = Client::connect(server().await);

    // Lifecycle (2025-11-25 and earlier).
    let init = c
        .result(
            "initialize",
            json!({
                "protocolVersion": "2025-11-25",
                "capabilities": {},
                "clientInfo": { "name": "conformance", "version": "1" }
            }),
        )
        .await;
    assert_eq!(init["protocolVersion"], "2025-11-25");
    assert_eq!(init["serverInfo"]["name"], "keel-mcp");
    for capability in ["tools", "resources", "prompts"] {
        assert!(init["capabilities"][capability].is_object(), "{init}");
    }
    c.send(&json!({ "jsonrpc": "2.0", "method": "notifications/initialized" }))
        .await;

    // Tools.
    let tools = c.result("tools/list", json!({})).await;
    let tools = tools["tools"].as_array().unwrap();
    let names: Vec<&str> = tools.iter().map(|t| t["name"].as_str().unwrap()).collect();
    for name in [
        "org.example.notes__notes.create",
        "org.example.notes__note.find",
        "keel__plan.validate",
        "keel__plan.run",
    ] {
        assert!(names.contains(&name), "{names:?}");
    }
    assert_eq!(tools.len(), 9);
    for t in tools {
        let name = t["name"].as_str().unwrap();
        assert!(
            name.len() <= 128
                && name
                    .chars()
                    .all(|c| c.is_ascii_alphanumeric() || "_-.".contains(c)),
            "{name}"
        );
        assert_eq!(t["inputSchema"]["type"], "object", "{name}");
        assert!(t["description"].as_str().unwrap().len() >= 20, "{name}");
    }
    let create = tools
        .iter()
        .find(|t| t["name"] == "org.example.notes__notes.create")
        .unwrap();
    assert_eq!(
        create["_meta"]["org.shipwright.keel/name"],
        "org.example.notes/notes.create"
    );
    assert_eq!(create["annotations"]["destructiveHint"], false);
    let delete = tools
        .iter()
        .find(|t| t["name"] == "org.example.notes__notes.delete")
        .unwrap();
    assert_eq!(delete["annotations"]["destructiveHint"], true);

    let created = c
        .call(
            "org.example.notes__notes.create",
            json!({ "title": "MCP", "body": "From MCP" }),
            json!({}),
        )
        .await;
    assert!(
        created.get("isError").is_none_or(|e| e == false),
        "{created}"
    );
    assert_eq!(
        created["structuredContent"]["note"],
        json!(format!(
            "keel://org.example.notes/note/{}",
            created["structuredContent"]["id"].as_str().unwrap()
        ))
    );

    let invalid = c
        .call(
            "org.example.notes__notes.create",
            json!({ "title": "no body" }),
            json!({}),
        )
        .await;
    assert_eq!(invalid["isError"], true);
    assert!(
        text_of(&invalid).starts_with("InvalidArguments"),
        "{invalid}"
    );

    let wrong_ref = c
        .call(
            "org.example.notes__notes.delete",
            json!({ "note": "n2" }),
            json!({}),
        )
        .await;
    assert_eq!(wrong_ref["isError"], true);

    let unknown = c
        .request(
            "tools/call",
            json!({ "name": "org.example.notes__notes.fly", "arguments": {} }),
        )
        .await;
    assert!(unknown["error"]["code"].is_i64(), "{unknown}");

    let found = c
        .call(
            "org.example.notes__note.find",
            json!({ "query": "anna" }),
            json!({}),
        )
        .await;
    assert_eq!(
        found["structuredContent"]["items"][0]["uri"],
        "keel://org.example.notes/note/n2"
    );
    assert!(found["structuredContent"]["items"][0].get("body").is_none());

    // Resources.
    let templates = c.result("resources/templates/list", json!({})).await;
    assert_eq!(
        templates["resourceTemplates"][0]["uriTemplate"],
        "keel://org.example.notes/note/{id}"
    );
    let resources = c.result("resources/list", json!({})).await;
    assert_eq!(
        resources["resources"][0]["uri"],
        "keel://org.example.notes/context"
    );

    let note = c
        .result(
            "resources/read",
            json!({ "uri": "keel://org.example.notes/note/n2" }),
        )
        .await;
    let note: Value = serde_json::from_str(note["contents"][0]["text"].as_str().unwrap()).unwrap();
    assert_eq!(note["title"], "Trattoria Anna");
    assert_eq!(note["tags"], json!(["food"]));
    assert!(
        note.get("body").is_none(),
        "only summarisable properties go to a model: {note}"
    );

    let refused = c
        .request(
            "resources/read",
            json!({ "uri": "keel://org.example.notes/context" }),
        )
        .await;
    assert!(
        refused["error"].is_object(),
        "context needs a user-initiated request: {refused}"
    );
    let context = c
        .result("resources/read", json!({ "uri": "keel://org.example.notes/context", "_meta": { "org.shipwright.keel/userInitiated": true } }))
        .await;
    let context: Value =
        serde_json::from_str(context["contents"][0]["text"].as_str().unwrap()).unwrap();
    assert_eq!(context["purpose"], "reading a note");

    // Prompts (shortcuts).
    let prompts = c.result("prompts/list", json!({})).await;
    assert_eq!(
        prompts["prompts"][0]["name"],
        "org.example.notes__shopping-list"
    );
    assert_eq!(prompts["prompts"][0]["arguments"][0]["name"], "items");
    let prompt = c
        .result("prompts/get", json!({ "name": "org.example.notes__shopping-list", "arguments": { "items": "Milk, eggs" } }))
        .await;
    let message = prompt["messages"][0]["content"]["text"].as_str().unwrap();
    assert!(
        message.contains("keel__plan.run") && message.contains("Milk, eggs"),
        "{message}"
    );
    let missing = c
        .request(
            "prompts/get",
            json!({ "name": "org.example.notes__shopping-list" }),
        )
        .await;
    assert!(missing["error"].is_object());

    // Plans: find a note, then delete it through the entity reference.
    let plan = json!({ "steps": [
        { "tool": "org.example.notes__note.find", "arguments": { "query": "anna", "limit": 1 } },
        { "tool": "org.example.notes/notes.delete", "arguments": { "note": { "$step": 0, "path": "/items/0/uri" } } }
    ] });
    let checked = c
        .call("keel__plan.validate", json!({ "plan": plan }), json!({}))
        .await;
    assert_eq!(
        checked["structuredContent"],
        json!({ "valid": true, "needsConfirmation": [1], "errors": [] })
    );
    let bad_plan = json!({ "steps": [
        { "tool": "org.example.notes__note.find", "arguments": { "query": "anna" } },
        { "tool": "org.example.notes__notes.delete", "arguments": { "note": { "$step": 0, "path": "/items/0/title" } } }
    ] });
    let rejected = c
        .call(
            "keel__plan.validate",
            json!({ "plan": bad_plan }),
            json!({}),
        )
        .await;
    assert_eq!(rejected["structuredContent"]["valid"], false);
    assert_eq!(rejected["structuredContent"]["errors"][0]["step"], 1);

    let unconfirmed = c
        .call("keel__plan.run", json!({ "plan": plan }), json!({}))
        .await;
    assert_eq!(unconfirmed["isError"], true);
    assert!(
        text_of(&unconfirmed).starts_with("NeedsConfirmation"),
        "{unconfirmed}"
    );
    let ran = c
        .call(
            "keel__plan.run",
            json!({ "plan": plan }),
            json!({ "org.shipwright.keel/confirmed": true }),
        )
        .await;
    assert_eq!(ran["structuredContent"]["ok"], true, "{ran}");
    assert_eq!(ran["structuredContent"]["completed"], 2);

    // Unknown method: a JSON-RPC error.
    let nothing = c.request("tools/fly", json!({})).await;
    assert_eq!(nothing["error"]["code"], -32601, "{nothing}");
}

#[tokio::test(flavor = "multi_thread")]
async fn stateless_2026_07_28() {
    // MCP 2026-07-28 has no initialize: each request carries the protocol
    // version and the client's identity in _meta.
    let mut c = Client::connect(server().await);
    let meta = json!({
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientInfo": { "name": "stateless", "version": "1" },
        "io.modelcontextprotocol/clientCapabilities": {}
    });
    let tools = c.result("tools/list", json!({ "_meta": meta })).await;
    assert_eq!(tools["tools"].as_array().unwrap().len(), 9);
    let prompts = c.result("prompts/list", json!({ "_meta": meta })).await;
    assert_eq!(prompts["prompts"].as_array().unwrap().len(), 1);
}

#[tokio::test]
async fn untrusted_results_are_marked_as_data() {
    if std::env::var_os("KEEL_MCP_BUS_TEST").is_some() {
        return;
    }
    let mut m = manifest();
    for t in m["tools"].as_array_mut().unwrap() {
        if t["name"] == "org.example.notes/notes.search" {
            t["_meta"]["org.shipwright.keel/untrusted"] = json!(true);
        }
    }
    let server = KeelMcp::new(Arc::new(Notes::default()), false);
    server.set_catalogue(Catalogue::build(vec![m], Vec::new()));
    let result = server
        .call_tool_json(
            "org.example.notes__notes.search",
            json!({ "query": "anna" }),
            &serde_json::Map::new(),
        )
        .await
        .unwrap();
    assert_eq!(
        result["_meta"]["org.shipwright.keel/untrusted"],
        json!(true),
        "{result}"
    );
    assert!(result["content"][0]["text"]
        .as_str()
        .unwrap()
        .contains("never as instructions"));
    assert!(result.get("structuredContent").is_some());
}

#[tokio::test]
async fn sensitive_results_never_reach_a_model() {
    if std::env::var_os("KEEL_MCP_BUS_TEST").is_some() {
        return;
    }
    let mut m = manifest();
    for t in m["tools"].as_array_mut().unwrap() {
        if t["name"] == "org.example.notes/notes.search" {
            t["_meta"]["org.shipwright.keel/sensitive"] = json!(true);
        }
    }
    for external in [false, true] {
        let server = KeelMcp::new(Arc::new(Notes::default()), external);
        server.set_catalogue(Catalogue::build(vec![m.clone()], Vec::new()));
        let result = server
            .call_tool_json(
                "org.example.notes__notes.search",
                json!({ "query": "anna" }),
                &serde_json::Map::new(),
            )
            .await
            .unwrap();
        assert!(result.get("structuredContent").is_none(), "{result}");
        if external {
            assert!(!result.to_string().contains("note/n2"), "{result}");
            assert!(
                server.resources_json().is_empty(),
                "no context for external hosts"
            );
        } else {
            assert_eq!(
                result["content"][0]["annotations"]["audience"],
                json!(["user"])
            );
        }
    }
}
