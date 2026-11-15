// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The app's own HTTPS requests: search suggestions and filter-list
//! updates. reqwest over rustls (ring) with the platform's certificates,
//! HTTPS only, no cookies, a plain user agent, a size limit.

use std::sync::{Arc, OnceLock};
use std::time::Duration;

use tokio::runtime::Runtime;

pub struct Response {
    pub status: u16,
    pub etag: String,
    pub last_modified: String,
    pub body: Vec<u8>,
}

/// `PACIFIC_OFFLINE=1` (tests, screenshots): the app makes no request of
/// its own.
pub fn offline() -> bool {
    std::env::var("PACIFIC_OFFLINE").is_ok_and(|v| v == "1")
}

static RUNTIME: OnceLock<Option<Runtime>> = OnceLock::new();
static CLIENT: OnceLock<Option<reqwest::Client>> = OnceLock::new();

/// The runtime for network work (two threads).
pub fn runtime() -> Option<&'static Runtime> {
    RUNTIME
        .get_or_init(|| {
            tokio::runtime::Builder::new_multi_thread()
                .worker_threads(2)
                .thread_name("pacific-net")
                .enable_all()
                .build()
                .map_err(|e| log::error!("cannot start the network runtime: {e}"))
                .ok()
        })
        .as_ref()
}

fn tls() -> Result<rustls::ClientConfig, String> {
    use rustls_platform_verifier::BuilderVerifierExt;
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    Ok(rustls::ClientConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()
        .map_err(|e| e.to_string())?
        .with_platform_verifier()
        .map_err(|e| e.to_string())?
        .with_no_client_auth())
}

fn client() -> Option<&'static reqwest::Client> {
    CLIENT
        .get_or_init(|| {
            let config = tls().map_err(|e| log::error!("TLS: {e}")).ok()?;
            reqwest::Client::builder()
                .tls_backend_preconfigured(config)
                .https_only(true)
                .connect_timeout(Duration::from_secs(10))
                .timeout(Duration::from_secs(60))
                .user_agent(concat!("Pacific/", env!("CARGO_PKG_VERSION")))
                .build()
                .map_err(|e| log::error!("HTTP client: {e}"))
                .ok()
        })
        .as_ref()
}

/// GET `url` with extra headers, refusing bodies over `max` bytes, within
/// `timeout`.
pub async fn get(
    url: &str,
    headers: &[(&str, &str)],
    max: usize,
    timeout: Duration,
) -> Result<Response, String> {
    let c = client().ok_or("no HTTP client")?;
    let mut req = c.get(url).timeout(timeout);
    for (k, v) in headers {
        if !v.is_empty() {
            req = req.header(*k, *v);
        }
    }
    let mut resp = req.send().await.map_err(|e| e.without_url().to_string())?;
    let status = resp.status().as_u16();
    let header = |name: &str| {
        resp.headers()
            .get(name)
            .and_then(|v| v.to_str().ok())
            .unwrap_or("")
            .to_owned()
    };
    let etag = header("etag");
    let last_modified = header("last-modified");
    if resp.content_length().is_some_and(|l| l > max as u64) {
        return Err("response too large".into());
    }
    let mut body = Vec::new();
    while let Some(chunk) = resp
        .chunk()
        .await
        .map_err(|e| e.without_url().to_string())?
    {
        if body.len() + chunk.len() > max {
            return Err("response too large".into());
        }
        body.extend_from_slice(&chunk);
    }
    Ok(Response {
        status,
        etag,
        last_modified,
        body,
    })
}
