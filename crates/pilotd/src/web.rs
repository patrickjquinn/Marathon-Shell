// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! `web.search`: the relay's `POST /v1/search` (Cloudflare's Web Search,
//! a provider that keeps no data). Read-only and asked for by the model
//! within a typed question's consent, so no card; what comes back is
//! third-party text and reaches the model only as untrusted content.
//!
//! The query is the model's own wording, written from the redacted
//! question: it is sent as written, never with the turn's placeholders
//! restored (`<CONTACT_1>` and the like are dropped instead), so a search
//! carries no more about the person than the question already sent.

use std::sync::{Arc, OnceLock};

use async_trait::async_trait;
use regex::Regex;
use serde_json::{json, Value};

use crate::remote::Remote;
use crate::schema::Validator;
use crate::tools::{Confirm, Registry, ToolError, ToolExecutor, ToolOutput, ToolSpec};

pub const TOOL: &str = "web.search";

pub struct WebSearch {
    pub remote: Remote,
    /// The relay's `/v1/search`; empty: the tool is not offered.
    pub url: String,
}

/// The tool's declaration.
///
/// # Panics
///
/// Never: the schema is static and valid.
#[allow(clippy::expect_used, reason = "compiled-in schemas")]
pub fn spec() -> ToolSpec {
    ToolSpec {
        name: TOOL.into(),
        title: "Search the web".into(),
        description: "Search the web for current or specific facts: news, prices, opening hours, \
                      sports results, recent events, anything after your training or that you \
                      are not sure of. Write the query as keywords a search engine matches, \
                      not a sentence (\"Carrauntoohil height metres\", not \"how tall is the \
                      tallest mountain in Ireland?\"). Set fresh for anything that changes: \
                      news, results, scores, prices, versions, weather, opening hours; add the \
                      year when it matters (\"All-Ireland hurling final 2026\"). Returns titles, \
                      URLs and page extracts; answer from them and name the site you used."
            .into(),
        input: Validator::new(json!({"type": "object", "properties": {
            "query": {"type": "string", "minLength": 2, "maxLength": 300},
            "limit": {"type": "integer", "minimum": 1, "maximum": 8},
            "fresh": {"type": "boolean"}},
            "required": ["query"], "additionalProperties": false}))
        .expect("static schema"),
        output: None,
        confirm: Confirm::Never,
        read_only: true,
        destructive: false,
        open_world: false,
        domain: "web".into(),
    }
}

/// Adds `web.search`, offered when `url` is set.
pub fn register(registry: &mut Registry, remote: Remote, url: &str) {
    let exec = Arc::new(WebSearch {
        remote,
        url: url.to_owned(),
    });
    registry.add(spec(), !url.is_empty(), exec);
}

/// `query` without redaction placeholders, spaces collapsed.
///
/// # Panics
///
/// Never: the pattern is static and valid.
#[allow(clippy::expect_used, reason = "compiled-in patterns")]
pub fn clean_query(query: &str) -> String {
    static RE: OnceLock<Regex> = OnceLock::new();
    let re = RE.get_or_init(|| Regex::new(r"<[A-Z]+_\d+>").expect("static regex"));
    re.replace_all(query, " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

/// The items of a relay reply, for the model: title, URL, extract.
pub fn results(reply: &Value) -> Vec<Value> {
    reply
        .get("items")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|i| {
                    let url = i.get("url")?.as_str()?;
                    Some(json!({
                        "title": i.get("title").and_then(Value::as_str).unwrap_or(""),
                        "url": url,
                        "extract": i.get("description").and_then(Value::as_str).unwrap_or(""),
                    }))
                })
                .collect()
        })
        .unwrap_or_default()
}

#[async_trait]
impl ToolExecutor for WebSearch {
    async fn call(&self, tool: &str, args: &Value) -> Result<ToolOutput, ToolError> {
        if tool != TOOL {
            return Err(ToolError::Unavailable(tool.to_owned()));
        }
        let query = clean_query(args.get("query").and_then(Value::as_str).unwrap_or(""));
        if query.chars().count() < 2 {
            return Err(ToolError::Invalid(
                "the query is empty without personal details; search for the topic itself".into(),
            ));
        }
        let limit = args.get("limit").and_then(Value::as_u64).unwrap_or(5);
        let fresh = args.get("fresh").and_then(Value::as_bool).unwrap_or(false);
        let reply = self
            .remote
            .post_json(
                "relay",
                "search",
                &self.url,
                &json!({"query": query, "limit": limit, "fresh": fresh}),
            )
            .await
            .map_err(|e| ToolError::Failed(format!("web search failed: {e}")))?;
        let items = results(&reply.body);
        Ok(ToolOutput {
            summary: if items.is_empty() {
                format!("No web results for \"{query}\".")
            } else {
                format!("{} web results for \"{query}\".", items.len())
            },
            data: json!({"query": query, "results": items}),
            private: false,
            untrusted: true,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn placeholders_never_reach_a_search() {
        assert_eq!(
            clean_query("restaurants near <ADDRESS_1> for <CONTACT_1> birthday"),
            "restaurants near for birthday"
        );
        assert_eq!(clean_query("<PHONE_1>"), "");
        assert_eq!(clean_query("  weather   Cork  "), "weather Cork");
    }

    #[test]
    fn results_keep_title_url_extract() {
        let r = results(&json!({"items": [
            {"url": "https://a.example", "title": "A", "description": "x"},
            {"title": "no url"}]}));
        assert_eq!(
            r,
            vec![json!({"title": "A", "url": "https://a.example", "extract": "x"})]
        );
        assert!(results(&json!({})).is_empty());
    }

    #[test]
    fn read_only_without_a_card() {
        let s = spec();
        assert!(s.read_only && !s.needs_confirmation(&json!({"query": "x"})));
        assert!(s.input.is_valid(&json!({"query": "Cork weather"})));
        assert!(!s.input.is_valid(&json!({"query": "x", "extra": 1})));
    }
}
