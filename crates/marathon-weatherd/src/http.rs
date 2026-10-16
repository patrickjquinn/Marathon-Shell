//! HTTP to MET Norway and Nominatim, both of which require an identifying
//! User-Agent. MET's terms also require honouring `Expires` and revalidating
//! with `If-Modified-Since`.

use std::time::{Duration, UNIX_EPOCH};

use crate::store::CacheMeta;

pub const USER_AGENT: &str = concat!(
    "marathon-weatherd/",
    env!("CARGO_PKG_VERSION"),
    " https://github.com/MarathonOS/Marathon-Image"
);

const MET_URL: &str = "https://api.met.no/weatherapi/locationforecast/2.0/complete";

/// Used when a response carries no usable `Expires`.
const DEFAULT_LIFETIME: i64 = 3600;

pub fn agent() -> ureq::Agent {
    ureq::Agent::config_builder()
        .user_agent(USER_AGENT)
        .timeout_global(Some(Duration::from_secs(30)))
        .build()
        .into()
}

#[derive(Debug, PartialEq)]
pub enum Failure {
    /// No route to the server: DNS, connect, TLS or timeout.
    Offline,
    Status(u16),
    Other(String),
}

impl From<ureq::Error> for Failure {
    fn from(e: ureq::Error) -> Self {
        match e {
            ureq::Error::StatusCode(code) => Failure::Status(code),
            ureq::Error::Io(_)
            | ureq::Error::Timeout(_)
            | ureq::Error::HostNotFound
            | ureq::Error::ConnectionFailed
            | ureq::Error::Tls(_)
            | ureq::Error::Rustls(_) => Failure::Offline,
            other => Failure::Other(other.to_string()),
        }
    }
}

pub enum Fetched {
    New { body: String, meta: CacheMeta },
    NotModified { meta: CacheMeta },
}

pub fn met_url(latitude: f64, longitude: f64) -> String {
    format!("{MET_URL}?lat={latitude:.4}&lon={longitude:.4}")
}

/// Whether the cache can still be served for this point without asking MET.
pub fn is_fresh(meta: &CacheMeta, latitude: f64, longitude: f64, now: i64) -> bool {
    same_point(meta, latitude, longitude) && now < meta.expires
}

pub fn same_point(meta: &CacheMeta, latitude: f64, longitude: f64) -> bool {
    met_url(meta.latitude, meta.longitude) == met_url(latitude, longitude)
}

/// `If-Modified-Since` only revalidates the same point's data.
pub fn if_modified_since(
    cached: Option<&CacheMeta>,
    latitude: f64,
    longitude: f64,
) -> Option<&str> {
    cached
        .filter(|m| same_point(m, latitude, longitude))
        .and_then(|m| m.last_modified.as_deref())
}

pub fn expires_at(header: Option<&str>, now: i64) -> i64 {
    header
        .and_then(|h| httpdate::parse_http_date(h).ok())
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .and_then(|d| i64::try_from(d.as_secs()).ok())
        .unwrap_or(now + DEFAULT_LIFETIME)
}

pub fn fetch_met(
    agent: &ureq::Agent,
    cached: Option<&CacheMeta>,
    latitude: f64,
    longitude: f64,
    now: i64,
) -> Result<Fetched, Failure> {
    let mut request = agent.get(met_url(latitude, longitude));
    let validator = if_modified_since(cached, latitude, longitude);
    if let Some(since) = validator {
        request = request.header("If-Modified-Since", since);
    }
    let mut response = request.call()?;
    let header = |name: &str| {
        response
            .headers()
            .get(name)
            .and_then(|v| v.to_str().ok())
            .map(str::to_owned)
    };
    let expires = expires_at(header("expires").as_deref(), now);
    let last_modified = header("last-modified");
    if response.status() == 304 {
        return Ok(Fetched::NotModified {
            meta: CacheMeta {
                latitude,
                longitude,
                last_modified: last_modified.or_else(|| validator.map(str::to_owned)),
                expires,
            },
        });
    }
    let body = response.body_mut().read_to_string()?;
    Ok(Fetched::New {
        body,
        meta: CacheMeta {
            latitude,
            longitude,
            last_modified,
            expires,
        },
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn meta(expires: i64) -> CacheMeta {
        CacheMeta {
            latitude: 53.349_81,
            longitude: -6.260_31,
            last_modified: Some("Fri, 16 Oct 2026 22:03:14 GMT".into()),
            expires,
        }
    }

    #[test]
    fn url_rounds_to_four_decimals() {
        assert_eq!(
            met_url(53.349_812, -6.260_349),
            "https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=53.3498&lon=-6.2603"
        );
    }

    #[test]
    fn expires_header_is_parsed_and_defaults_when_missing() {
        // Fri, 16 Oct 2026 22:34:33 GMT
        assert_eq!(
            expires_at(Some("Fri, 16 Oct 2026 22:34:33 GMT"), 0),
            1_792_190_073
        );
        assert_eq!(expires_at(None, 100), 100 + DEFAULT_LIFETIME);
        assert_eq!(expires_at(Some("garbage"), 100), 100 + DEFAULT_LIFETIME);
    }

    #[test]
    fn cache_is_fresh_only_before_expires_at_the_same_point() {
        let m = meta(1000);
        assert!(is_fresh(&m, 53.3498, -6.2603, 999));
        assert!(!is_fresh(&m, 53.3498, -6.2603, 1000));
        assert!(!is_fresh(&m, 61.4981, 23.7608, 999));
    }

    #[test]
    fn revalidates_with_last_modified_only_for_the_same_point() {
        let m = meta(0);
        assert_eq!(
            if_modified_since(Some(&m), 53.3498, -6.2603),
            Some("Fri, 16 Oct 2026 22:03:14 GMT")
        );
        assert_eq!(if_modified_since(Some(&m), 61.4981, 23.7608), None);
        assert_eq!(if_modified_since(None, 53.3498, -6.2603), None);
    }
}
