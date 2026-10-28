// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! What Pilot remembers, as tools for the model. Kept on the phone
//! (`Store`); the person sees it on a card and in Settings, and can say
//! "forget …".
//!
//! - `memory.remember`: a lasting fact about the person. Asked for ("my
//!   baby naps from one to three, bear that in mind"), it is kept at once;
//!   mentioned in passing ("I'm vegetarian, so..."), it is offered on a card
//!   and kept only on the person's yes. A fact that changes an older one
//!   (`replaces`, its number in the list the model is shown) takes its
//!   place: "I moved to Cork" leaves no "I live in Galway" behind.
//! - `memory.search`: earlier conversations (the last 30 days, kept only
//!   while the "Conversation history" switch is on), for "what was that
//!   restaurant you suggested last week?".

use std::sync::Arc;

use async_trait::async_trait;
use serde_json::{json, Value};

use crate::schema::Validator;
use crate::store::Store;
use crate::tools::{Confirm, Registry, ToolError, ToolExecutor, ToolOutput, ToolSpec};

pub const TOOL: &str = "memory.remember";
pub const SEARCH: &str = "memory.search";

pub struct MemoryTool {
    pub store: Arc<Store>,
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
        title: "Remember".into(),
        description: "Keep a lasting fact about the person or their life (family, diet, routines, \
                      preferences, where they live), in the first person and their words (\"my baby \
                      naps from 1 to 3\"). asked: true when they asked you to remember it; false when \
                      they only mentioned it, and then the person is asked first. Nothing passing \
                      (today's plans, one question). replaces: the number of a remembered fact this \
                      one changes."
            .into(),
        input: Validator::new(json!({"type": "object", "properties": {
            "fact": {"type": "string", "minLength": 3, "maxLength": 300},
            "asked": {"type": "boolean"},
            "replaces": {"type": "integer", "minimum": 1}},
            "required": ["fact", "asked"], "additionalProperties": false}))
        .expect("static schema"),
        output: None,
        // Kept without asking only when the person asked for it.
        confirm: Confirm::When(|a| a.get("asked").and_then(Value::as_bool) != Some(true)),
        read_only: false,
        destructive: false,
        open_world: false,
        domain: "system".into(),
    }
}

/// `memory.search`'s declaration.
///
/// # Panics
///
/// Never: the schema is static and valid.
#[allow(clippy::expect_used, reason = "compiled-in schemas")]
pub fn search_spec() -> ToolSpec {
    ToolSpec {
        name: SEARCH.into(),
        title: "Search earlier conversations".into(),
        description: "Find what the person and you said in earlier conversations on this phone \
                      (up to 30 days back): \"what was that recipe you gave me\", \"the restaurant \
                      we talked about last week\". query: the distinctive words to look for."
            .into(),
        input: Validator::new(json!({"type": "object", "properties": {
            "query": {"type": "string", "minLength": 2, "maxLength": 200}},
            "required": ["query"], "additionalProperties": false}))
        .expect("static schema"),
        output: None,
        confirm: Confirm::Never,
        read_only: true,
        destructive: false,
        open_world: false,
        domain: "system".into(),
    }
}

/// Adds `memory.remember` and `memory.search`.
pub fn register(registry: &mut Registry, store: Arc<Store>) {
    registry.add(
        spec(),
        true,
        Arc::new(MemoryTool {
            store: Arc::clone(&store),
        }),
    );
    registry.add(search_spec(), true, Arc::new(MemoryTool { store }));
}

#[async_trait]
impl ToolExecutor for MemoryTool {
    async fn call(&self, tool: &str, args: &Value) -> Result<ToolOutput, ToolError> {
        if tool == SEARCH {
            let query = args.get("query").and_then(Value::as_str).unwrap_or("");
            let hits = self
                .store
                .search_conversation(query, 5)
                .map_err(|e| ToolError::Failed(e.to_string()))?;
            let found: Vec<Value> = hits
                .iter()
                .map(|h| {
                    json!({"when": crate::localtime::at(h.ts_ms / 1000).long_date(),
                           "person": h.question, "pilot": h.answer})
                })
                .collect();
            return Ok(ToolOutput {
                summary: if found.is_empty() {
                    "Nothing in earlier conversations matches.".into()
                } else {
                    format!("{} earlier exchange(s) found.", found.len())
                },
                data: json!({"exchanges": found}),
                private: false,
                untrusted: false,
            });
        }
        if tool != TOOL {
            return Err(ToolError::Unavailable(tool.to_owned()));
        }
        let fact = args
            .get("fact")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|f| !f.is_empty())
            .ok_or_else(|| ToolError::Invalid("fact is empty".into()))?;
        if let Some(old) = args.get("replaces").and_then(Value::as_i64) {
            self.store.forget(old).ok();
        }
        let id = self
            .store
            .remember(fact)
            .map_err(|e| ToolError::Failed(e.to_string()))?;
        Ok(ToolOutput {
            summary: format!("Remembered: {fact}."),
            data: json!({"id": id, "fact": fact}),
            private: false,
            untrusted: false,
        })
    }
}
