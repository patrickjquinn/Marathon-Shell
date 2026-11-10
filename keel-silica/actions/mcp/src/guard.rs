// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! A line filter in front of rmcp for the JSON-RPC it misreads. A batch
//! (removed from MCP in 2025-06-18) gets an error without the `id: null`
//! JSON-RPC asks for, and a request whose id is null (MCP: "MUST NOT be
//! null") is taken for a notification, which before initialisation ends
//! the session. Both are answered here with -32600 and never reach rmcp.

use std::sync::Arc;

use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncRead, AsyncWrite, AsyncWriteExt, BufReader, DuplexStream};

/// The error for a message rmcp should not see, if `line` is one.
pub fn refusal(line: &str) -> Option<Value> {
    let why = match serde_json::from_str::<Value>(line).ok()? {
        Value::Array(_) => "Invalid Request: batches are not part of MCP",
        Value::Object(m) if m.contains_key("method") && m.get("id") == Some(&Value::Null) => {
            "Invalid Request: a request id must not be null"
        }
        _ => return None,
    };
    Some(json!({ "jsonrpc": "2.0", "id": null, "error": { "code": -32600, "message": why } }))
}

/// Wraps a client's newline-delimited stream: rmcp serves the returned
/// pair, and refused messages are answered on `write` between its own.
pub fn guard<R, W>(read: R, write: W) -> (DuplexStream, DuplexStream)
where
    R: AsyncRead + Unpin + Send + 'static,
    W: AsyncWrite + Unpin + Send + 'static,
{
    let (server_in, mut to_server) = tokio::io::duplex(1 << 16);
    let (server_out, from_server) = tokio::io::duplex(1 << 16);
    let out = Arc::new(tokio::sync::Mutex::new(write));
    let send = |out: Arc<tokio::sync::Mutex<W>>, line: String| async move {
        let mut w = out.lock().await;
        w.write_all(line.as_bytes()).await?;
        w.write_all(b"\n").await?;
        w.flush().await
    };
    let replies = Arc::clone(&out);
    tokio::spawn(async move {
        let mut lines = BufReader::new(from_server).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            if send(Arc::clone(&replies), line).await.is_err() {
                break;
            }
        }
    });
    tokio::spawn(async move {
        let mut lines = BufReader::new(read).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            if let Some(error) = refusal(&line) {
                if send(Arc::clone(&out), error.to_string()).await.is_err() {
                    break;
                }
                continue;
            }
            if to_server.write_all(line.as_bytes()).await.is_err()
                || to_server.write_all(b"\n").await.is_err()
            {
                break;
            }
        }
        // Dropping `to_server` ends rmcp's input.
    });
    (server_in, server_out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn batches_and_null_ids_are_refused() {
        let batch = refusal(r#"[{"jsonrpc":"2.0","id":1,"method":"ping"}]"#).unwrap();
        assert_eq!(batch["error"]["code"], -32600);
        assert_eq!(batch["id"], Value::Null);
        assert!(refusal(r#"{"jsonrpc":"2.0","id":null,"method":"tools/list"}"#).is_some());
        assert!(refusal(r#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#).is_none());
        assert!(refusal(r#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#).is_none());
        assert!(refusal(r#"{"jsonrpc":"2.0","id":null,"result":{}}"#).is_none());
        assert!(refusal("not json").is_none());
    }
}
