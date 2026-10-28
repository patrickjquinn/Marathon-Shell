// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! The keel-mcp binary on its two transports, stdio and a Unix socket,
//! reading manifests from a directory. Needs a session bus (it connects at
//! start-up), so it runs inside ctest `keel_mcp_conformance`
//! (`KEEL_MCP_BUS_TEST=1`) and is skipped elsewhere.

#![allow(clippy::unwrap_used, clippy::let_underscore_must_use, reason = "tests")]

use std::io::{BufRead, BufReader, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use serde_json::{json, Value};

fn golden_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/qml-notes")
}

fn on_bus() -> bool {
    std::env::var_os("KEEL_MCP_BUS_TEST").is_some()
}

fn exchange(write: &mut impl Write, read: &mut impl BufRead, request: &Value) -> Value {
    writeln!(write, "{request}").unwrap();
    write.flush().unwrap();
    let mut line = String::new();
    read.read_line(&mut line).unwrap();
    serde_json::from_str(&line).unwrap()
}

fn tools_list() -> Value {
    json!({ "jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": { "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientInfo": { "name": "t", "version": "1" },
        "io.modelcontextprotocol/clientCapabilities": {} } } })
}

/// keel-mcp under test, killed however the test ends: a failed assertion
/// would otherwise leave it running, holding the test's output open (ctest
/// then waits for it).
struct Server(std::process::Child);

impl Drop for Server {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

/// The notes app's six actions, its note.find and the built-in app.show,
/// and the two plan tools.
const TOOLS: usize = 10;

#[test]
fn stdio() {
    if !on_bus() {
        return;
    }
    let mut server = Server(
        Command::new(env!("CARGO_BIN_EXE_keel-mcp"))
            .args(["--stdio", "--probe-seconds", "0", "--actions-dir"])
            .arg(golden_dir())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .unwrap(),
    );
    let mut stdin = server.0.stdin.take().unwrap();
    let mut stdout = BufReader::new(server.0.stdout.take().unwrap());
    let init = exchange(
        &mut stdin,
        &mut stdout,
        &json!({ "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": { "name": "t", "version": "1" } } }),
    );
    assert_eq!(init["result"]["protocolVersion"], "2025-06-18");
    writeln!(
        stdin,
        "{}",
        json!({ "jsonrpc": "2.0", "method": "notifications/initialized" })
    )
    .unwrap();
    let list = exchange(
        &mut stdin,
        &mut stdout,
        &json!({ "jsonrpc": "2.0", "id": 2, "method": "tools/list" }),
    );
    assert_eq!(list["result"]["tools"].as_array().unwrap().len(), TOOLS);
    drop(stdin);
    server.0.wait().unwrap();
}

#[test]
fn unix_socket() {
    if !on_bus() {
        return;
    }
    let socket = std::env::temp_dir().join(format!("keel-mcp-test-{}.sock", std::process::id()));
    let _server = Server(
        Command::new(env!("CARGO_BIN_EXE_keel-mcp"))
            .arg("--socket")
            .arg(&socket)
            .args(["--probe-seconds", "0", "--actions-dir"])
            .arg(golden_dir())
            .spawn()
            .unwrap(),
    );
    let start = Instant::now();
    let stream = loop {
        if let Ok(s) = UnixStream::connect(&socket) {
            break s;
        }
        assert!(start.elapsed() < Duration::from_secs(20), "no socket");
        std::thread::sleep(Duration::from_millis(50));
    };
    assert_eq!(
        std::fs::metadata(&socket).unwrap().permissions().mode() & 0o777,
        0o600
    );
    let mut write = stream.try_clone().unwrap();
    let mut read = BufReader::new(stream);
    let list = exchange(&mut write, &mut read, &tools_list());
    assert_eq!(
        list["result"]["tools"].as_array().unwrap().len(),
        TOOLS,
        "{list}"
    );
    let _ = std::fs::remove_file(&socket);
}
