// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Direct mode: the phone's owner holds the Groq and Jev keys, in a 0600
//! file, and pilotd calls the relay's upstreams itself (`[direct]` in
//! pilotd.toml, off by default). What the relay does on the way is done
//! here instead: each key goes only to its own upstream, requests are
//! shaped as services/pilot-relay/src/policy.rs shapes them, and LLM
//! replies are stamped with the upstream's processing region, so the
//! fail-closed region check in llm.rs still applies.

use std::os::unix::fs::PermissionsExt as _;
use std::path::Path;

use serde_json::Value;

/// The relay's caps (policy.rs).
const MAX_BODY: usize = 4 * 1024 * 1024;
const MAX_STATE_TEXT: usize = 401;

#[derive(Debug, thiserror::Error)]
pub enum KeyFileError {
    #[error("{0}: {1}")]
    Read(String, std::io::Error),
    #[error("{0} is readable by other users; run chmod 600 on it")]
    Exposed(String),
    #[error("{0} has no {1}")]
    Missing(String, &'static str),
}

/// One upstream: where, its key, and the region stamped on its replies.
#[derive(Clone)]
pub struct Upstream {
    pub url: String,
    pub key: String,
    pub region: Option<String>,
}

impl std::fmt::Debug for Upstream {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Upstream")
            .field("url", &self.url)
            .field("region", &self.region)
            .finish_non_exhaustive()
    }
}

#[derive(Debug, Clone)]
pub struct Direct {
    pub jev: Upstream,
    pub llm: Upstream,
    pub region_header: String,
    pub max_completion_tokens: u64,
}

/// A request as direct mode sends it.
pub struct Outgoing {
    pub body: Value,
    pub key: Option<String>,
    /// To the LLM upstream: its reply gets the region stamp.
    pub llm: bool,
}

impl Direct {
    /// `body` for `url`, shaped as the relay would forward it, with the
    /// key of that upstream (none for any other URL).
    pub fn prepare(&self, url: &str, body: &Value) -> Result<Outgoing, String> {
        let target = self.target(url);
        let body = shape(&target, body, self.max_completion_tokens)?;
        if serde_json::to_vec(&body).map_or(0, |b| b.len()) > MAX_BODY {
            return Err("request too large".into());
        }
        let (key, llm) = match target {
            Target::Jev(u) => (Some(u.key.clone()), false),
            Target::Llm(u) => (Some(u.key.clone()), true),
            Target::Other => (None, false),
        };
        Ok(Outgoing { body, key, llm })
    }

    /// No relay to stamp the processing region: the LLM upstream's known
    /// one replaces whatever the reply says.
    pub fn stamp(&self, headers: &mut reqwest::header::HeaderMap) {
        headers.remove(self.region_header.as_str());
        let name = reqwest::header::HeaderName::from_bytes(self.region_header.as_bytes());
        let value = self
            .llm
            .region
            .as_deref()
            .map(reqwest::header::HeaderValue::from_str);
        if let (Ok(name), Some(Ok(value))) = (name, value) {
            headers.insert(name, value);
        }
    }
}

/// What a request to `url` gets in direct mode.
pub enum Target<'a> {
    Jev(&'a Upstream),
    Llm(&'a Upstream),
    /// Anything else: no key.
    Other,
}

impl Direct {
    pub fn target(&self, url: &str) -> Target<'_> {
        if url == self.jev.url {
            Target::Jev(&self.jev)
        } else if url == self.llm.url {
            Target::Llm(&self.llm)
        } else {
            Target::Other
        }
    }
}

/// `PILOT_RELAY_GROQ_KEY` and `PILOT_RELAY_JEV_KEY` from an env file
/// (`NAME=value` lines, `#` comments, optional quotes and `export`). The
/// file must be readable by its owner only.
pub fn read_keys(path: &Path) -> Result<(String, String), KeyFileError> {
    let name = path.display().to_string();
    let meta = std::fs::metadata(path).map_err(|e| KeyFileError::Read(name.clone(), e))?;
    if meta.permissions().mode() & 0o077 != 0 {
        return Err(KeyFileError::Exposed(name));
    }
    let text = std::fs::read_to_string(path).map_err(|e| KeyFileError::Read(name.clone(), e))?;
    let get = |want: &'static str| {
        text.lines()
            .map(str::trim)
            .filter(|l| !l.starts_with('#'))
            .filter_map(|l| l.strip_prefix("export ").unwrap_or(l).split_once('='))
            .filter(|(k, _)| k.trim() == want)
            .map(|(_, v)| v.trim().trim_matches(|c| c == '"' || c == '\'').to_owned())
            .rfind(|v| !v.is_empty())
            .ok_or_else(|| KeyFileError::Missing(name.clone(), want))
    };
    Ok((get("PILOT_RELAY_GROQ_KEY")?, get("PILOT_RELAY_JEV_KEY")?))
}

/// Jev's `state` as the relay forwards it: the redacted request and the
/// local time, or a notification being sorted, each text capped.
fn jev_state(state: &Value) -> Value {
    fn text(v: Option<&Value>) -> Option<Value> {
        v.and_then(Value::as_str)
            .map(|s| Value::String(s.chars().take(MAX_STATE_TEXT).collect()))
    }
    fn pick(v: Option<&Value>, keys: &[&str]) -> serde_json::Map<String, Value> {
        keys.iter()
            .filter_map(|k| Some(((*k).to_owned(), text(v.and_then(|o| o.get(*k)))?)))
            .collect()
    }
    let mut out = pick(Some(state), &["utterance", "local_time"]);
    for (key, fields) in [
        ("event", &["source", "app", "title", "body"][..]),
        ("context", &["time", "weekday"][..]),
    ] {
        let o = pick(state.get(key), fields);
        if !o.is_empty() {
            out.insert(key.to_owned(), Value::Object(o));
        }
    }
    Value::Object(out)
}

/// A request as the relay would forward it, or why it would refuse it.
pub fn shape(target: &Target<'_>, body: &Value, cap: u64) -> Result<Value, String> {
    let mut v = body.clone();
    match target {
        Target::Jev(_) => {
            if let Some(state) = v.get("state") {
                v["state"] = jev_state(state);
            }
        }
        Target::Llm(_) => {
            let obj = v.as_object_mut().ok_or("not a JSON object")?;
            if obj.get("stream").and_then(Value::as_bool) == Some(true) {
                return Err("streaming is not supported".into());
            }
            let asked = obj
                .get("max_completion_tokens")
                .or_else(|| obj.get("max_tokens"))
                .and_then(Value::as_u64)
                .unwrap_or(cap);
            obj.remove("max_tokens");
            obj.insert("max_completion_tokens".into(), Value::from(asked.min(cap)));
            for k in ["store", "metadata", "user"] {
                obj.remove(k);
            }
        }
        Target::Other => {}
    }
    Ok(v)
}

/// The relay's 422 for a tool call the provider could not parse (pipeline
/// retries once on it).
pub fn llm_status(status: reqwest::StatusCode, body: &[u8]) -> reqwest::StatusCode {
    let v: Value = serde_json::from_slice(body).unwrap_or_default();
    let code = v
        .pointer("/error/code")
        .and_then(Value::as_str)
        .unwrap_or("");
    if status == reqwest::StatusCode::BAD_REQUEST && code.ends_with("tool_use_failed") {
        reqwest::StatusCode::UNPROCESSABLE_ENTITY
    } else {
        status
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::io::Write as _;

    fn up(url: &str) -> Upstream {
        Upstream {
            url: url.into(),
            key: "k".into(),
            region: None,
        }
    }

    #[test]
    fn key_file() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("keys.env");
        let mut f = std::fs::File::create(&p).unwrap();
        writeln!(
            f,
            "# owner's keys\nexport PILOT_RELAY_GROQ_KEY=\"gk\"\nPILOT_RELAY_JEV_KEY = jk\nOTHER=x"
        )
        .unwrap();
        std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o640)).unwrap();
        assert!(matches!(read_keys(&p), Err(KeyFileError::Exposed(_))));
        std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o600)).unwrap();
        assert_eq!(read_keys(&p).unwrap(), ("gk".into(), "jk".into()));
        std::fs::write(&p, "PILOT_RELAY_GROQ_KEY=gk\n").unwrap();
        assert!(matches!(
            read_keys(&p),
            Err(KeyFileError::Missing(_, "PILOT_RELAY_JEV_KEY"))
        ));
        assert!(read_keys(&dir.path().join("none")).is_err());
        // The key never shows in debug output.
        let d = format!("{:?}", up("https://x"));
        assert!(!d.contains("\"k\""));
    }

    #[test]
    fn shaped_as_the_relay_does() {
        let jev = up("https://jev");
        let req = json!({"state": {"utterance": "a".repeat(500), "contact": "Anna",
                         "context": {"time": "18:42", "location": "Dublin"}},
                         "questions": {"q": {"type": "noul"}}});
        let out = shape(&Target::Jev(&jev), &req, 4096).unwrap();
        assert_eq!(
            out["state"],
            json!({"utterance": "a".repeat(MAX_STATE_TEXT), "context": {"time": "18:42"}})
        );
        assert_eq!(out["questions"], req["questions"]);

        let llm = up("https://llm");
        let req =
            json!({"model": "m", "messages": [], "max_tokens": 99_999, "store": true, "user": "u"});
        let out = shape(&Target::Llm(&llm), &req, 4096).unwrap();
        assert_eq!(out["max_completion_tokens"], 4096);
        assert!(
            out.get("max_tokens").is_none()
                && out.get("store").is_none()
                && out.get("user").is_none()
        );
        assert!(shape(&Target::Llm(&llm), &json!({"stream": true}), 1).is_err());
        assert_eq!(shape(&Target::Other, &req, 1).unwrap(), req);
    }

    #[test]
    fn targets_and_statuses() {
        let d = Direct {
            jev: up("https://api.typesafe.ai/v1/systemone"),
            llm: up("https://api.groq.com/openai/v1/chat/completions"),
            region_header: "x-pilot-processing-region".into(),
            max_completion_tokens: 4096,
        };
        assert!(matches!(
            d.target("https://api.typesafe.ai/v1/systemone"),
            Target::Jev(_)
        ));
        assert!(matches!(
            d.target("https://api.groq.com/openai/v1/chat/completions"),
            Target::Llm(_)
        ));
        assert!(matches!(
            d.target("https://pilot.reefstore.app/v1/search"),
            Target::Other
        ));
        let tool = br#"{"error": {"type": "invalid_request_error", "code": "tool_use_failed"}}"#;
        let code = |n| reqwest::StatusCode::from_u16(n).unwrap();
        assert_eq!(llm_status(code(400), tool), code(422));
        assert_eq!(llm_status(code(400), b"{}"), code(400));
        assert_eq!(llm_status(code(429), tool), code(429));
        let mut h = reqwest::header::HeaderMap::new();
        h.insert("x-pilot-processing-region", "ap-south".parse().unwrap());
        d.stamp(&mut h);
        assert!(
            h.get("x-pilot-processing-region").is_none(),
            "no region configured"
        );
    }
}
