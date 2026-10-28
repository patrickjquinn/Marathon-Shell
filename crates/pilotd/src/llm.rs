// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The generation layer (spec section 6): an OpenAI-compatible chat
//! completions client with tools, JSON mode and `reasoning_effort`.
//!
//! Default path: the Pilot relay, which holds the Groq key and forwards to
//! Groq's public endpoint, processed in the United States. Lighthouse
//! (section 10.1) is the same interface on a different URL.
//!
//! **Processing region, fail closed (section 6.1).** Every reply must carry
//! the processing region in a header (default `x-pilot-processing-region`,
//! stamped by the relay from the upstream it actually used: `us` for Groq),
//! and the value must be in `allowed_regions` (default `eu`, `us`). A
//! missing or other value drops the reply before anything reads it, and the
//! turn fails.

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::remote::{Remote, RemoteError};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Role {
    System,
    User,
    Assistant,
    Tool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ToolCall {
    pub id: String,
    pub name: String,
    /// Raw JSON text, as the model produced it.
    pub arguments: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Message {
    pub role: Role,
    pub content: Option<String>,
    pub tool_calls: Vec<ToolCall>,
    pub tool_call_id: Option<String>,
    /// `data:` URLs of images (vision turns), already downscaled and
    /// stripped of metadata.
    pub images: Vec<String>,
}

impl Message {
    pub fn text(role: Role, content: impl Into<String>) -> Message {
        Message {
            role,
            content: Some(content.into()),
            tool_calls: Vec::new(),
            tool_call_id: None,
            images: Vec::new(),
        }
    }

    pub fn tool_result(id: &str, content: impl Into<String>) -> Message {
        Message {
            role: Role::Tool,
            content: Some(content.into()),
            tool_calls: Vec::new(),
            tool_call_id: Some(id.to_owned()),
            images: Vec::new(),
        }
    }

    fn to_json(&self) -> Value {
        let mut m = json!({ "role": self.role });
        if self.images.is_empty() {
            m["content"] = self.content.clone().map_or(Value::Null, Value::String);
        } else {
            let mut parts =
                vec![json!({"type": "text", "text": self.content.clone().unwrap_or_default()})];
            parts.extend(
                self.images
                    .iter()
                    .map(|u| json!({"type": "image_url", "image_url": {"url": u}})),
            );
            m["content"] = Value::Array(parts);
        }
        if !self.tool_calls.is_empty() {
            m["tool_calls"] = self
                .tool_calls
                .iter()
                .map(|c| {
                    json!({"id": c.id, "type": "function",
                           "function": {"name": c.name, "arguments": c.arguments}})
                })
                .collect();
        }
        if let Some(id) = &self.tool_call_id {
            m["tool_call_id"] = Value::String(id.clone());
        }
        m
    }
}

/// A tool as the model sees it.
#[derive(Debug, Clone, PartialEq)]
pub struct ToolDef {
    /// Model-safe name (`^[a-zA-Z0-9_-]{1,64}$`); the registry maps it back.
    pub name: String,
    pub description: String,
    pub parameters: Value,
}

/// How hard the model should think (section 6.1).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Effort {
    /// Conversational turns: thinking off.
    Off,
    /// Tool loops.
    Low,
    /// Explicit "work this out" requests.
    Medium,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ChatRequest {
    pub messages: Vec<Message>,
    pub tools: Vec<ToolDef>,
    pub json_mode: bool,
    pub effort: Effort,
    pub purpose: String,
    /// A tool the model must call this round (its name in `tools`): a
    /// question only a tool can answer truthfully (the weather).
    pub require: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ChatResponse {
    pub content: Option<String>,
    pub tool_calls: Vec<ToolCall>,
    pub finish_reason: String,
    /// The processing region the reply was verified against.
    pub region: String,
}

#[async_trait]
pub trait LlmClient: Send + Sync {
    async fn chat(&self, req: &ChatRequest) -> Result<ChatResponse, RemoteError>;
    fn provider(&self) -> &str;
    fn model(&self) -> &str;
}

/// Effort-to-parameter mapping; config, because preview models change
/// what they accept.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct EffortValues {
    /// `None` leaves `reasoning_effort` out of the request.
    pub off: Option<String>,
    pub low: Option<String>,
    pub medium: Option<String>,
}

impl Default for EffortValues {
    fn default() -> Self {
        EffortValues {
            off: Some("none".into()),
            low: Some("low".into()),
            medium: Some("medium".into()),
        }
    }
}

pub struct OpenAiClient {
    pub remote: Remote,
    /// Full URL of the chat completions endpoint.
    pub url: String,
    pub model: String,
    pub provider: String,
    pub region_header: String,
    pub allowed_regions: Vec<String>,
    pub effort: EffortValues,
    pub max_completion_tokens: u32,
}

impl OpenAiClient {
    fn body(&self, req: &ChatRequest) -> Value {
        let mut body = json!({
            "model": self.model,
            "messages": req.messages.iter().map(Message::to_json).collect::<Vec<_>>(),
            "max_completion_tokens": self.max_completion_tokens,
        });
        let effort = match req.effort {
            Effort::Off => &self.effort.off,
            Effort::Low => &self.effort.low,
            Effort::Medium => &self.effort.medium,
        };
        if let Some(e) = effort {
            body["reasoning_effort"] = Value::String(e.clone());
        }
        // Without reasoning, Qwen3.8's model card: 0.7 / 0.8 and a presence
        // penalty against repetition. With it, 0.6 and 0.95, not the card's
        // 1.0: measured on Pilot's evaluation (3 runs of 72 tasks), 1.0
        // passed 203 of 216 against 212 for 0.6, worst on short tool turns.
        // The reasoning stays out of the reply text.
        let thinking = !matches!(req.effort, Effort::Off);
        if thinking {
            body["temperature"] = json!(0.6);
            body["top_p"] = json!(0.95);
            // Groq's field; vLLM (Lighthouse) separates reasoning itself.
            if self.provider == "groq" {
                body["reasoning_format"] = json!("hidden");
            }
        } else {
            body["temperature"] = json!(0.7);
            body["top_p"] = json!(0.8);
            body["presence_penalty"] = json!(1.5);
        }
        if !req.tools.is_empty() {
            body["tools"] = req
                .tools
                .iter()
                .map(|t| {
                    json!({"type": "function", "function": {
                        "name": t.name, "description": t.description, "parameters": t.parameters}})
                })
                .collect();
            body["tool_choice"] = match &req.require {
                Some(name) if req.tools.iter().any(|t| &t.name == name) => {
                    json!({"type": "function", "function": {"name": name}})
                }
                _ => Value::String("auto".into()),
            };
        }
        if req.json_mode {
            body["response_format"] = json!({"type": "json_object"});
        }
        body
    }

    /// The region the reply says it was processed in, if allowed.
    fn check_region(&self, headers: &reqwest::header::HeaderMap) -> Result<String, RemoteError> {
        let Some(v) = headers.get(self.region_header.as_str()) else {
            return Err(RemoteError::Region(format!(
                "no {} header",
                self.region_header
            )));
        };
        let region = v
            .to_str()
            .map_err(|_| RemoteError::Region("unreadable region header".into()))?
            .trim()
            .to_ascii_lowercase();
        if self
            .allowed_regions
            .iter()
            .any(|a| a.eq_ignore_ascii_case(&region))
        {
            Ok(region)
        } else {
            Err(RemoteError::Region(format!("processed in {region:?}")))
        }
    }
}

fn decode(provider: &str, message: impl Into<String>) -> RemoteError {
    RemoteError::Decode {
        provider: provider.to_owned(),
        message: message.into(),
    }
}

/// Reads `choices[0]` of an OpenAI-style reply.
pub fn parse_choice(
    provider: &str,
    body: &Value,
) -> Result<(Option<String>, Vec<ToolCall>, String), RemoteError> {
    let choice = body
        .get("choices")
        .and_then(|c| c.get(0))
        .ok_or_else(|| decode(provider, "no choices"))?;
    let msg = choice
        .get("message")
        .ok_or_else(|| decode(provider, "no message"))?;
    let content = msg
        .get("content")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned);
    let mut calls = Vec::new();
    if let Some(Value::Array(tcs)) = msg.get("tool_calls") {
        for tc in tcs {
            let f = tc
                .get("function")
                .ok_or_else(|| decode(provider, "tool call without function"))?;
            let name = f
                .get("name")
                .and_then(Value::as_str)
                .ok_or_else(|| decode(provider, "tool call without name"))?;
            // Some servers send arguments as an object instead of a string.
            let arguments = match f.get("arguments") {
                Some(Value::String(s)) => s.clone(),
                Some(other) => other.to_string(),
                None => "{}".to_owned(),
            };
            calls.push(ToolCall {
                id: tc
                    .get("id")
                    .and_then(Value::as_str)
                    .unwrap_or("call")
                    .to_owned(),
                name: name.to_owned(),
                arguments,
            });
        }
    }
    let finish = choice
        .get("finish_reason")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_owned();
    Ok((content, calls, finish))
}

#[async_trait]
impl LlmClient for OpenAiClient {
    async fn chat(&self, req: &ChatRequest) -> Result<ChatResponse, RemoteError> {
        let body = self.body(req);
        let reply = self
            .remote
            .post_json(&self.provider, &req.purpose, &self.url, &body)
            .await?;
        let region = match self.check_region(&reply.headers) {
            Ok(r) => r,
            Err(e) => {
                self.remote
                    .record_refusal(&self.provider, &req.purpose, "region-blocked");
                return Err(e);
            }
        };
        let (content, tool_calls, finish_reason) = parse_choice(&self.provider, &reply.body)?;
        Ok(ChatResponse {
            content,
            tool_calls,
            finish_reason,
            region,
        })
    }

    fn provider(&self) -> &str {
        &self.provider
    }

    fn model(&self) -> &str {
        &self.model
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_tool_calls_with_string_or_object_arguments() {
        let body = json!({"choices": [{"finish_reason": "tool_calls", "message": {
        "content": null,
        "tool_calls": [
            {"id": "a", "type": "function", "function": {"name": "timer_set", "arguments": "{\"seconds\":60}"}},
            {"id": "b", "type": "function", "function": {"name": "media_control", "arguments": {"action": "pause"}}}
        ]}}]});
        let (content, calls, finish) = parse_choice("groq", &body).unwrap();
        assert_eq!(content, None);
        assert_eq!(finish, "tool_calls");
        assert_eq!(calls[0].arguments, "{\"seconds\":60}");
        assert_eq!(
            serde_json::from_str::<Value>(&calls[1].arguments).unwrap()["action"],
            "pause"
        );
        assert!(parse_choice("groq", &json!({"choices": []})).is_err());
    }

    #[test]
    fn message_json_shapes() {
        let mut m = Message::text(Role::User, "what is this");
        m.images.push("data:image/jpeg;base64,AAAA".into());
        let j = m.to_json();
        assert_eq!(j["content"][1]["type"], "image_url");
        let t = Message::tool_result("x", "{}").to_json();
        assert_eq!(t["role"], "tool");
        assert_eq!(t["tool_call_id"], "x");
    }
}
