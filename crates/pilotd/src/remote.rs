// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The one way `pilotd` talks to the network: JSON POSTs that are logged in
//! the egress log, refused while offline, and in direct mode authenticated
//! with the owner's key for that upstream.

use std::sync::Arc;
use std::time::{Duration, Instant};

use reqwest::header::HeaderMap;
use serde_json::Value;

use crate::privacy::Offline;
use crate::store::{now_ms, EgressEntry, EgressSink};

#[derive(Debug, thiserror::Error)]
pub enum RemoteError {
    #[error("Pilot is offline")]
    Offline,
    #[error("{provider} returned HTTP {status}")]
    Status { provider: String, status: u16 },
    #[error("{provider} unreachable: {message}")]
    Transport { provider: String, message: String },
    #[error("{provider} did not answer in time")]
    Timeout { provider: String },
    #[error("{provider} sent an unusable reply: {message}")]
    Decode { provider: String, message: String },
    #[error("processing region not confirmed as allowed ({0}); request dropped")]
    Region(String),
}

/// A request that failed on its way, its timeout told apart.
fn transport(provider: &str, e: reqwest::Error) -> RemoteError {
    let provider = provider.to_owned();
    if e.is_timeout() {
        RemoteError::Timeout { provider }
    } else {
        RemoteError::Transport {
            provider,
            message: e.without_url().to_string(),
        }
    }
}

impl RemoteError {
    fn result_label(&self) -> String {
        match self {
            RemoteError::Offline => "offline".into(),
            RemoteError::Status { status, .. } => format!("http-{status}"),
            RemoteError::Transport { .. } => "transport".into(),
            RemoteError::Timeout { .. } => "timeout".into(),
            RemoteError::Decode { .. } => "decode".into(),
            RemoteError::Region(_) => "region-blocked".into(),
        }
    }
}

/// Each whole `data:` line in `pending` to `on_data`, but `[DONE]`.
fn drain_events(pending: &mut Vec<u8>, on_data: &mut impl FnMut(&str)) {
    while let Some(end) = pending.iter().position(|b| *b == b'\n') {
        let line: Vec<u8> = pending.drain(..=end).collect();
        let line = String::from_utf8_lossy(&line);
        if let Some(data) = line.trim().strip_prefix("data:") {
            let data = data.trim();
            if data != "[DONE]" {
                on_data(data);
            }
        }
    }
}

/// The longest a streamed reply may take, stalls apart.
const STREAM_MAX: Duration = Duration::from_mins(10);

/// Where the bearer token comes from.
#[derive(Debug, Clone)]
pub enum Credential {
    /// No `Authorization` header (a local test server).
    None,
    /// The owner's own keys, each sent only to its upstream (direct.rs).
    Direct(Arc<crate::direct::Direct>),
}

/// A JSON reply and its headers.
pub struct Reply {
    pub headers: HeaderMap,
    pub body: Value,
}

/// An HTTP client bound to one provider name for the egress log.
#[derive(Clone)]
pub struct Remote {
    client: reqwest::Client,
    credential: Credential,
    egress: Arc<dyn EgressSink>,
    offline: Offline,
    timeout: Duration,
}

impl Remote {
    pub fn new(
        client: reqwest::Client,
        credential: Credential,
        egress: Arc<dyn EgressSink>,
        offline: Offline,
        timeout: Duration,
    ) -> Remote {
        Remote {
            client,
            credential,
            egress,
            offline,
            timeout,
        }
    }

    /// The same client with another per-request timeout.
    #[must_use]
    pub fn with_timeout(&self, timeout: Duration) -> Remote {
        Remote {
            timeout,
            ..self.clone()
        }
    }

    /// Direct mode's shaped request and key for `url`.
    fn direct(
        &self,
        provider: &str,
        url: &str,
        body: &Value,
    ) -> Result<Option<(Arc<crate::direct::Direct>, crate::direct::Outgoing)>, RemoteError> {
        let Credential::Direct(d) = &self.credential else {
            return Ok(None);
        };
        let out = d
            .prepare(url, body)
            .map_err(|message| RemoteError::Decode {
                provider: provider.to_owned(),
                message,
            })?;
        Ok(Some((Arc::clone(d), out)))
    }

    /// POSTs `body` as JSON and returns the JSON reply. Logged whatever the
    /// outcome; dropped without a request while offline; abandoned
    /// mid-flight if the privacy switch engages.
    pub async fn post_json(
        &self,
        provider: &str,
        purpose: &str,
        url: &str,
        body: &Value,
    ) -> Result<Reply, RemoteError> {
        if self.offline.is_offline() {
            return Err(RemoteError::Offline);
        }
        let direct = self.direct(provider, url, body)?;
        let body = direct.as_ref().map_or(body, |(_, out)| &out.body);
        let bytes = serde_json::to_vec(body).map_err(|e| RemoteError::Decode {
            provider: provider.to_owned(),
            message: e.to_string(),
        })?;
        let bytes_out = bytes.len() as u64;
        let started = Instant::now();
        let log = |result: String, bytes_in: u64| {
            self.egress.record(EgressEntry {
                ts_ms: now_ms(),
                provider: provider.to_owned(),
                purpose: purpose.to_owned(),
                bytes_out,
                bytes_in,
                latency_ms: u64::try_from(started.elapsed().as_millis()).unwrap_or(u64::MAX),
                result,
            });
        };
        let mut req = self
            .client
            .post(url)
            .timeout(self.timeout)
            .header(reqwest::header::CONTENT_TYPE, "application/json")
            .body(bytes);
        if let Some(k) = direct.as_ref().and_then(|(_, out)| out.key.as_ref()) {
            req = req.bearer_auth(k);
        }
        let llm = direct.as_ref().filter(|(_, out)| out.llm).map(|(d, _)| d);
        let sent = async {
            let resp = req.send().await.map_err(|e| transport(provider, e))?;
            let status = resp.status();
            let mut headers = resp.headers().clone();
            if let Some(d) = llm {
                d.stamp(&mut headers);
            }
            let raw = resp.bytes().await.map_err(|e| transport(provider, e))?;
            Ok::<_, RemoteError>((status, headers, raw))
        };
        let outcome = tokio::select! {
            r = sent => r,
            () = self.offline.engaged() => Err(RemoteError::Offline),
        };
        let (status, headers, raw) = match outcome {
            Ok(x) => x,
            Err(e) => {
                log(e.result_label(), 0);
                return Err(e);
            }
        };
        let bytes_in = raw.len() as u64;
        let status = llm.map_or(status, |_| crate::direct::llm_status(status, &raw));
        if !status.is_success() {
            let e = RemoteError::Status {
                provider: provider.to_owned(),
                status: status.as_u16(),
            };
            log(e.result_label(), bytes_in);
            return Err(e);
        }
        match serde_json::from_slice(&raw) {
            Ok(body) => {
                log("ok".into(), bytes_in);
                Ok(Reply { headers, body })
            }
            Err(e) => {
                let e = RemoteError::Decode {
                    provider: provider.to_owned(),
                    message: e.to_string(),
                };
                log(e.result_label(), bytes_in);
                Err(e)
            }
        }
    }

    /// As [`Remote::post_json`], for a reply streamed as server-sent events
    /// (a model on this phone writing): `on_data` gets each event's data as
    /// it arrives, and the reply's headers come back. A server that answers
    /// with plain JSON instead has it returned whole.
    pub async fn post_stream(
        &self,
        provider: &str,
        purpose: &str,
        url: &str,
        body: &Value,
        mut on_data: impl FnMut(&str) + Send,
    ) -> Result<(HeaderMap, Option<Value>), RemoteError> {
        if self.offline.is_offline() {
            return Err(RemoteError::Offline);
        }
        let direct = self.direct(provider, url, body)?;
        let body = direct.as_ref().map_or(body, |(_, out)| &out.body);
        let bytes = serde_json::to_vec(body).map_err(|e| RemoteError::Decode {
            provider: provider.to_owned(),
            message: e.to_string(),
        })?;
        let bytes_out = bytes.len() as u64;
        let started = Instant::now();
        let log = |result: String, bytes_in: u64| {
            self.egress.record(EgressEntry {
                ts_ms: now_ms(),
                provider: provider.to_owned(),
                purpose: purpose.to_owned(),
                bytes_out,
                bytes_in,
                latency_ms: u64::try_from(started.elapsed().as_millis()).unwrap_or(u64::MAX),
                result,
            });
        };
        // A stream is limited by its stalls, not its length: a long answer
        // still arriving is not cut off. The timeout is the longest wait
        // for the reply's start (the model reading the prompt) and between
        // its pieces.
        let mut req = self
            .client
            .post(url)
            .timeout(STREAM_MAX)
            .header(reqwest::header::CONTENT_TYPE, "application/json")
            .body(bytes);
        if let Some(k) = direct.as_ref().and_then(|(_, out)| out.key.as_ref()) {
            req = req.bearer_auth(k);
        }
        let llm = direct.as_ref().filter(|(_, out)| out.llm).map(|(d, _)| d);
        let stall = self.timeout;
        let stalled = || RemoteError::Timeout {
            provider: provider.to_owned(),
        };
        let sent = async {
            let mut resp = tokio::time::timeout(stall, req.send())
                .await
                .map_err(|_elapsed| stalled())?
                .map_err(|e| transport(provider, e))?;
            let status = resp.status();
            let mut headers = resp.headers().clone();
            if let Some(d) = llm {
                d.stamp(&mut headers);
            }
            let mut bytes_in = 0u64;
            let events = headers
                .get(reqwest::header::CONTENT_TYPE)
                .and_then(|v| v.to_str().ok())
                .is_some_and(|v| v.starts_with("text/event-stream"));
            let mut whole = None;
            if status.is_success() && !events {
                let raw = resp.bytes().await.map_err(|e| transport(provider, e))?;
                bytes_in = raw.len() as u64;
                whole = Some(serde_json::from_slice::<Value>(&raw).map_err(|e| {
                    RemoteError::Decode {
                        provider: provider.to_owned(),
                        message: e.to_string(),
                    }
                })?);
            } else if status.is_success() {
                let mut pending: Vec<u8> = Vec::new();
                while let Some(chunk) = tokio::time::timeout(stall, resp.chunk())
                    .await
                    .map_err(|_elapsed| stalled())?
                    .map_err(|e| transport(provider, e))?
                {
                    bytes_in += chunk.len() as u64;
                    pending.extend_from_slice(&chunk);
                    drain_events(&mut pending, &mut on_data);
                }
            }
            Ok::<_, RemoteError>((status, headers, bytes_in, whole))
        };
        let outcome = tokio::select! {
            r = sent => r,
            () = self.offline.engaged() => Err(RemoteError::Offline),
        };
        let (status, headers, bytes_in, whole) = match outcome {
            Ok(x) => x,
            Err(e) => {
                log(e.result_label(), 0);
                return Err(e);
            }
        };
        if !status.is_success() {
            let e = RemoteError::Status {
                provider: provider.to_owned(),
                status: status.as_u16(),
            };
            log(e.result_label(), bytes_in);
            return Err(e);
        }
        log("ok".into(), bytes_in);
        Ok((headers, whole))
    }

    /// GETs a public JSON API (no relay credential): logged whatever the
    /// outcome, dropped while offline, abandoned if the privacy switch
    /// engages, as [`Remote::post_json`].
    pub async fn get_json(
        &self,
        provider: &str,
        purpose: &str,
        url: &str,
    ) -> Result<Reply, RemoteError> {
        if self.offline.is_offline() {
            return Err(RemoteError::Offline);
        }
        let started = Instant::now();
        let log = |result: String, bytes_in: u64| {
            self.egress.record(EgressEntry {
                ts_ms: now_ms(),
                provider: provider.to_owned(),
                purpose: purpose.to_owned(),
                bytes_out: url.len() as u64,
                bytes_in,
                latency_ms: u64::try_from(started.elapsed().as_millis()).unwrap_or(u64::MAX),
                result,
            });
        };
        let req = self.client.get(url).timeout(self.timeout);
        let sent = async {
            let resp = req.send().await.map_err(|e| transport(provider, e))?;
            let status = resp.status();
            let headers = resp.headers().clone();
            let raw = resp.bytes().await.map_err(|e| transport(provider, e))?;
            Ok::<_, RemoteError>((status, headers, raw))
        };
        let outcome = tokio::select! {
            r = sent => r,
            () = self.offline.engaged() => Err(RemoteError::Offline),
        };
        let (status, headers, raw) = match outcome {
            Ok(x) => x,
            Err(e) => {
                log(e.result_label(), 0);
                return Err(e);
            }
        };
        let bytes_in = raw.len() as u64;
        if !status.is_success() {
            let e = RemoteError::Status {
                provider: provider.to_owned(),
                status: status.as_u16(),
            };
            log(e.result_label(), bytes_in);
            return Err(e);
        }
        match serde_json::from_slice(&raw) {
            Ok(body) => {
                log("ok".into(), bytes_in);
                Ok(Reply { headers, body })
            }
            Err(e) => {
                let e = RemoteError::Decode {
                    provider: provider.to_owned(),
                    message: e.to_string(),
                };
                log(e.result_label(), bytes_in);
                Err(e)
            }
        }
    }

    /// Records a refusal that happened after the reply arrived (the region
    /// check), so the log shows the call was made and then discarded.
    pub fn record_refusal(&self, provider: &str, purpose: &str, result: &str) {
        self.egress.record(EgressEntry {
            ts_ms: now_ms(),
            provider: provider.to_owned(),
            purpose: purpose.to_owned(),
            bytes_out: 0,
            bytes_in: 0,
            latency_ms: 0,
            result: result.to_owned(),
        });
    }
}

/// Builds the shared HTTP client (rustls with ring, as Shoal Push).
pub fn http_client() -> Result<reqwest::Client, reqwest::Error> {
    rustls::crypto::ring::default_provider()
        .install_default()
        .ok();
    reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(10))
        .user_agent(concat!("shoal-pilotd/", env!("CARGO_PKG_VERSION")))
        .build()
}
