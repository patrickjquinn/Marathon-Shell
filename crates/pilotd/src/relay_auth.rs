// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! The relay's device token (services/pilot-relay): obtained by sending the
//! Pilot licence from Reef (`org.shipwright.Reef.Licences`, the hand-off
//! every Shipwright app uses) and a random device id to `POST /v1/token`.
//! The token is stored 0600 in the data directory, reused until five
//! minutes before its expiry, and dropped when the relay answers 401.

use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};

use base64::Engine as _;
use serde_json::{json, Value};

use crate::privacy::Offline;
use crate::remote::RemoteError;
use crate::settings::write_private;
use crate::store::{now_ms, EgressEntry, EgressSink};

/// The licence app id for Pilot in Reef.
pub const APP_ID: &str = "shipwright-shoal-pilot";
/// Renew this long before the token expires.
const MARGIN_SECS: i64 = 300;

/// Where the licence token comes from.
pub trait LicenceSource: Send + Sync {
    /// Blocking; `Ok(None)` when there is no licence.
    fn licence(&self) -> Result<Option<String>, String>;
}

/// Reef's session-bus hand-off.
pub struct ReefHandoff;

impl LicenceSource for ReefHandoff {
    fn licence(&self) -> Result<Option<String>, String> {
        reef_licence::handoff::fetch(APP_ID).map_err(|e| e.to_string())
    }
}

/// A fixed licence (tests).
impl LicenceSource for String {
    fn licence(&self) -> Result<Option<String>, String> {
        Ok(Some(self.clone()))
    }
}

pub struct RelayAuth {
    pub token_file: PathBuf,
    pub device_file: PathBuf,
    pub exchange_url: String,
    pub licence: Arc<dyn LicenceSource>,
    pub client: reqwest::Client,
    pub egress: Arc<dyn EgressSink>,
    pub offline: Offline,
    pub timeout: Duration,
    lock: tokio::sync::Mutex<()>,
}

/// The `exp` claim of a `pr1.` token, read without verifying (the device
/// cannot; the relay does).
pub fn token_exp(token: &str) -> Option<i64> {
    let mut parts = token.split('.');
    if parts.next()? != "pr1" {
        return None;
    }
    let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(parts.next()?)
        .ok()?;
    serde_json::from_slice::<Value>(&bytes)
        .ok()?
        .get("exp")?
        .as_i64()
}

fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write as _;
    bytes.iter().fold(String::new(), |mut s, b| {
        let _ = write!(s, "{b:02x}");
        s
    })
}

impl RelayAuth {
    #[allow(clippy::too_many_arguments, reason = "plain wiring")]
    pub fn new(
        token_file: PathBuf,
        device_file: PathBuf,
        exchange_url: String,
        licence: Arc<dyn LicenceSource>,
        client: reqwest::Client,
        egress: Arc<dyn EgressSink>,
        offline: Offline,
        timeout: Duration,
    ) -> RelayAuth {
        RelayAuth {
            token_file,
            device_file,
            exchange_url,
            licence,
            client,
            egress,
            offline,
            timeout,
            lock: tokio::sync::Mutex::new(()),
        }
    }

    fn stored(&self) -> Option<String> {
        let t = std::fs::read_to_string(&self.token_file).ok()?;
        let t = t.trim().to_owned();
        if t.is_empty() {
            return None;
        }
        match token_exp(&t) {
            Some(exp) if exp - MARGIN_SECS <= now_ms() / 1000 => None,
            _ => Some(t),
        }
    }

    /// A random id for this installation, created on first use.
    fn device_id(&self) -> Result<String, RemoteError> {
        if let Ok(id) = std::fs::read_to_string(&self.device_file) {
            let id = id.trim().to_owned();
            if id.len() >= 8 {
                return Ok(id);
            }
        }
        let mut bytes = [0u8; 16];
        std::fs::File::open("/dev/urandom")
            .and_then(|mut f| std::io::Read::read_exact(&mut f, &mut bytes))
            .map_err(|e| RemoteError::Token(format!("random device id: {e}")))?;
        let id = hex(&bytes);
        write_private(&self.device_file, id.as_bytes())
            .map_err(|e| RemoteError::Token(format!("{}: {e}", self.device_file.display())))?;
        Ok(id)
    }

    /// Forgets the stored token after the relay refused it.
    pub fn invalidate(&self) {
        let _ = std::fs::remove_file(&self.token_file);
    }

    /// The current device token, exchanging the licence when needed.
    pub async fn token(&self) -> Result<String, RemoteError> {
        if let Some(t) = self.stored() {
            return Ok(t);
        }
        let _guard = self.lock.lock().await;
        if let Some(t) = self.stored() {
            return Ok(t);
        }
        if self.offline.is_offline() {
            return Err(RemoteError::Offline);
        }
        // The hand-off is a blocking D-Bus call of a few seconds at most.
        let src = self.licence.clone();
        let licence = tokio::task::spawn_blocking(move || src.licence())
            .await
            .map_err(|e| RemoteError::Token(e.to_string()))?
            .map_err(RemoteError::Token)?
            .ok_or_else(|| RemoteError::Token("no Pilot licence in Reef".into()))?;
        let body = json!({"licence": licence, "device": self.device_id()?});
        let bytes = serde_json::to_vec(&body).unwrap_or_default();
        let started = Instant::now();
        let sent = self
            .client
            .post(&self.exchange_url)
            .timeout(self.timeout)
            .header(reqwest::header::CONTENT_TYPE, "application/json")
            .body(bytes.clone())
            .send()
            .await;
        let (result, reply) = match sent {
            Ok(r) if r.status().is_success() => match r.bytes().await {
                Ok(b) => ("ok".to_owned(), Some(b)),
                Err(_) => ("transport".to_owned(), None),
            },
            Ok(r) => (format!("http-{}", r.status().as_u16()), None),
            Err(_) => ("transport".to_owned(), None),
        };
        self.egress.record(EgressEntry {
            ts_ms: now_ms(),
            provider: "relay".into(),
            purpose: "token".into(),
            bytes_out: bytes.len() as u64,
            bytes_in: reply.as_ref().map_or(0, |b| b.len() as u64),
            latency_ms: u64::try_from(started.elapsed().as_millis()).unwrap_or(u64::MAX),
            result: result.clone(),
        });
        let reply = reply.ok_or_else(|| RemoteError::Token(format!("token exchange: {result}")))?;
        let token = serde_json::from_slice::<Value>(&reply)
            .ok()
            .and_then(|v| v.get("token").and_then(Value::as_str).map(str::to_owned))
            .ok_or_else(|| RemoteError::Token("token exchange: no token in the reply".into()))?;
        write_private(&self.token_file, token.as_bytes())
            .map_err(|e| RemoteError::Token(format!("{}: {e}", self.token_file.display())))?;
        Ok(token)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_exp_without_verifying() {
        let payload =
            base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(br#"{"exp":1234,"lid":"x"}"#);
        assert_eq!(token_exp(&format!("pr1.{payload}.sig")), Some(1234));
        assert_eq!(token_exp("dev-token-123"), None);
        assert_eq!(token_exp("pr1.!!.x"), None);
    }
}
