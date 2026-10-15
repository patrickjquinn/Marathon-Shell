// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! The one way `pilotd` talks to the network: JSON POSTs that are logged in
//! the egress log, refused while offline, and authenticated with the
//! device token the Pilot relay issued (spec section 10: API keys live in
//! the relay, never on the device).

use std::path::PathBuf;
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
    #[error("{provider} sent an unusable reply: {message}")]
    Decode { provider: String, message: String },
    #[error("processing region not confirmed as allowed ({0}); request dropped")]
    Region(String),
    #[error("no device token: {0}")]
    Token(String),
}

impl RemoteError {
    fn result_label(&self) -> String {
        match self {
            RemoteError::Offline => "offline".into(),
            RemoteError::Status { status, .. } => format!("http-{status}"),
            RemoteError::Transport { .. } => "transport".into(),
            RemoteError::Decode { .. } => "decode".into(),
            RemoteError::Region(_) => "region-blocked".into(),
            RemoteError::Token(_) => "no-token".into(),
        }
    }
}

/// Where the bearer token comes from.
#[derive(Debug, Clone)]
pub enum Credential {
    /// No `Authorization` header (a local test server).
    None,
    /// The relay's device token, read from this file on every request so a
    /// renewed token takes effect without a restart.
    TokenFile(PathBuf),
    /// The relay's device token, exchanged for the Reef licence on demand.
    Relay(Arc<crate::relay_auth::RelayAuth>),
    /// The owner's own keys, each sent only to its upstream (direct.rs).
    Direct(Arc<crate::direct::Direct>),
}

impl std::fmt::Debug for crate::relay_auth::RelayAuth {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("RelayAuth")
            .field("exchange_url", &self.exchange_url)
            .finish_non_exhaustive()
    }
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

    async fn token(&self) -> Result<Option<String>, RemoteError> {
        match &self.credential {
            Credential::None | Credential::Direct(_) => Ok(None),
            Credential::Relay(auth) => auth.token().await.map(Some),
            Credential::TokenFile(path) => {
                let t = std::fs::read_to_string(path)
                    .map_err(|e| RemoteError::Token(format!("{}: {e}", path.display())))?;
                let t = t.trim();
                if t.is_empty() {
                    return Err(RemoteError::Token(format!("{} is empty", path.display())));
                }
                Ok(Some(t.to_owned()))
            }
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
        Ok(Some((d.clone(), out)))
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
        let token = match self.token().await {
            Ok(t) => t,
            Err(e) => {
                log(e.result_label(), 0);
                return Err(e);
            }
        };
        let mut req = self
            .client
            .post(url)
            .timeout(self.timeout)
            .header(reqwest::header::CONTENT_TYPE, "application/json")
            .body(bytes);
        if let Some(t) = token {
            req = req.bearer_auth(t);
        }
        if let Some(k) = direct.as_ref().and_then(|(_, out)| out.key.as_ref()) {
            req = req.bearer_auth(k);
        }
        let llm = direct.as_ref().filter(|(_, out)| out.llm).map(|(d, _)| d);
        let sent = async {
            let resp = req.send().await.map_err(|e| RemoteError::Transport {
                provider: provider.to_owned(),
                message: e.without_url().to_string(),
            })?;
            let status = resp.status();
            let mut headers = resp.headers().clone();
            if let Some(d) = llm {
                d.stamp(&mut headers);
            }
            let raw = resp.bytes().await.map_err(|e| RemoteError::Transport {
                provider: provider.to_owned(),
                message: e.without_url().to_string(),
            })?;
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
            if status.as_u16() == 401 {
                if let Credential::Relay(auth) = &self.credential {
                    // Expired or revoked: exchange the licence again next time.
                    auth.invalidate();
                }
            }
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
            let resp = req.send().await.map_err(|e| RemoteError::Transport {
                provider: provider.to_owned(),
                message: e.without_url().to_string(),
            })?;
            let status = resp.status();
            let headers = resp.headers().clone();
            let raw = resp.bytes().await.map_err(|e| RemoteError::Transport {
                provider: provider.to_owned(),
                message: e.without_url().to_string(),
            })?;
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
    let _ = rustls::crypto::ring::default_provider().install_default();
    reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(10))
        .user_agent(concat!("shoal-pilotd/", env!("CARGO_PKG_VERSION")))
        .build()
}
