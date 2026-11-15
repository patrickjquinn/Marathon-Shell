// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Helpers for Pilot driving the browser (the Keel Actions in
//! `ui/qml/actions/PacificActions.qml`).
//!
//! **Snapshots.** Pilot never sees or sends CSS selectors. It asks for a
//! snapshot of the page's interactive elements, which the web view takes
//! in its isolated script world (`WebView.agentSnapshot`, webview/js/agent.js)
//! so the page cannot read, change or fake it, and gets short ids (`e12`).
//! Clicks and fills name those ids; the elements stay in the isolated
//! world, and an id of a detached element is refused there.
//! [`Snapshot::parse`] reads that snapshot, bounds it and decides which
//! fields are sensitive.
//!
//! **Untrusted content.** Everything read from a page (text, titles, link
//! names, field labels) is web content: possibly written to steer an
//! assistant. [`untrusted`] bounds it, strips control and bidirectional
//! override characters and collapses whitespace; the actions return it in
//! fields marked as untrusted page content, never as instructions, and
//! every result has a size bound.
//!
//! **Safety.** Pilot may not fill password, one-time-code or payment
//! fields ([`Snapshot::check_fill`]); logins stay user-initiated through
//! Shoal Keys. Clicking, filling and submitting are `confirm` actions, and
//! [`Snapshot::form_risk`] says what a form submission would do (log in,
//! pay, ...) for the confirmation card.

use std::fmt::Write as _;

use serde::{Deserialize, Serialize};

use crate::util::truncate_chars;
use crate::{Error, Result};

/// Bounds of what goes back to Pilot.
pub const MAX_ELEMENTS: usize = 200;
pub const MAX_NAME: usize = 120;
pub const MAX_PAGE_TEXT: usize = 20_000;
pub const MAX_SELECTION: usize = 4_000;

/// Cleans page text for an assistant: no control characters (except
/// newlines), no bidirectional overrides or zero-width characters (used to
/// hide text), runs of blank lines and spaces collapsed, at most `max`
/// characters.
pub fn untrusted(text: &str, max: usize) -> String {
    let mut out = String::with_capacity(text.len().min(max * 4));
    let mut blank_lines = 0;
    let mut last_space = false;
    for c in text.chars() {
        let hidden = matches!(c as u32, 0x200B..=0x200F | 0x202A..=0x202E | 0x2060..=0x2064 | 0x2066..=0x2069 | 0xFEFF);
        if hidden || (c.is_control() && c != '\n' && c != '\t') {
            continue;
        }
        if c == '\n' {
            blank_lines += 1;
            if blank_lines <= 2 {
                while out.ends_with(' ') {
                    out.pop();
                }
                out.push('\n');
            }
            last_space = false;
            continue;
        }
        if c.is_whitespace() {
            if !last_space && !out.is_empty() && !out.ends_with('\n') {
                out.push(' ');
            }
            last_space = true;
            continue;
        }
        blank_lines = 0;
        last_space = false;
        out.push(c);
    }
    truncate_chars(out.trim(), max)
}

/// One interactive element of a snapshot.
#[allow(
    clippy::struct_excessive_bools,
    reason = "independent facts about an element"
)]
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Element {
    pub id: String,
    #[serde(default)]
    pub tag: String,
    /// link, button, textbox, checkbox, radio, combobox, ...
    #[serde(default)]
    pub role: String,
    /// Its accessible name (untrusted).
    #[serde(default)]
    pub label: String,
    #[serde(default)]
    pub href: String,
    /// The input type for `<input>`.
    #[serde(default, rename = "type")]
    pub input_type: String,
    /// The field's `name` attribute.
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub autocomplete: String,
    /// The current value (password values are masked by the view).
    #[serde(default, deserialize_with = "lenient_string")]
    pub value: String,
    /// The id of its form, if any.
    #[serde(default)]
    pub form: String,
    #[serde(default)]
    pub disabled: bool,
    #[serde(default, rename = "readOnly")]
    pub read_only: bool,
    /// On screen now (not scrolled away).
    #[serde(default, rename = "inViewport")]
    pub in_view: bool,
    /// A password, one-time code or payment field (decided here, from
    /// type, autocomplete and name).
    #[serde(default, skip_deserializing)]
    pub sensitive: bool,
}

fn lenient_string<'de, D: serde::Deserializer<'de>>(d: D) -> std::result::Result<String, D::Error> {
    let v = serde_json::Value::deserialize(d)?;
    Ok(match v {
        serde_json::Value::String(s) => s,
        serde_json::Value::Null => String::new(),
        other => other.to_string(),
    })
}

impl Element {
    fn is_sensitive(&self) -> bool {
        let ty = self.input_type.to_ascii_lowercase();
        let ac = self.autocomplete.to_ascii_lowercase();
        let nm = self.name.to_ascii_lowercase();
        let label = self.label.to_ascii_lowercase();
        ty == "password"
            || ac.contains("password")
            || ac.contains("one-time-code")
            || ac.split_whitespace().any(|t| t.starts_with("cc-"))
            || [
                "cardnumber",
                "card-number",
                "card_number",
                "ccnum",
                "cvc",
                "cvv",
                "iban",
                "securitycode",
                "security-code",
                "passcode",
                "otp",
            ]
            .iter()
            .any(|k| nm.contains(k))
            || nm == "pin"
            || ((ty.is_empty() || ty == "text" || ty == "tel" || ty == "number")
                && ["card number", "cvc", "cvv", "security code"]
                    .iter()
                    .any(|k| label.contains(k)))
    }

    fn is_payment(&self) -> bool {
        let ac = self.autocomplete.to_ascii_lowercase();
        let nm = self.name.to_ascii_lowercase();
        ac.split_whitespace().any(|t| t.starts_with("cc-"))
            || [
                "cardnumber",
                "card-number",
                "card_number",
                "ccnum",
                "cvc",
                "cvv",
                "iban",
            ]
            .iter()
            .any(|k| nm.contains(k))
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Form {
    pub id: String,
    #[serde(default)]
    pub action: String,
    #[serde(default)]
    pub method: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub label: String,
    /// Decided here from the form's fields.
    #[serde(default, skip_deserializing)]
    pub has_password: bool,
    #[serde(default, skip_deserializing)]
    pub has_payment: bool,
    #[serde(default, skip_deserializing)]
    pub is_search: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Snapshot {
    #[serde(default)]
    pub url: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub elements: Vec<Element>,
    #[serde(default)]
    pub forms: Vec<Form>,
    /// More elements existed than the snapshot holds.
    #[serde(default)]
    pub truncated: bool,
}

/// What submitting a form would do, for the confirmation card.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Risk {
    Search,
    Login,
    Payment,
    Other,
}

impl Snapshot {
    /// Parses the web view's snapshot (`agentSnapshot`), bounds and
    /// cleans it, and marks sensitive fields and risky forms.
    pub fn parse(json: &str) -> Result<Self> {
        if json.len() > 4 * 1024 * 1024 {
            return Err(Error::Invalid("the page snapshot is too large".into()));
        }
        let mut s: Self = serde_json::from_str(json)?;
        s.title = untrusted(&s.title, 300);
        s.url = truncate_chars(&s.url, 2048);
        if s.elements.len() > MAX_ELEMENTS {
            s.elements.truncate(MAX_ELEMENTS);
            s.truncated = true;
        }
        for e in &mut s.elements {
            e.label = untrusted(&e.label, MAX_NAME);
            e.href = truncate_chars(&e.href, 2048);
            e.role = truncate_chars(&e.role, 20);
            e.input_type = truncate_chars(&e.input_type, 20);
            e.name = truncate_chars(&e.name, 100);
            e.sensitive = e.is_sensitive();
            e.value = if e.sensitive {
                String::new()
            } else {
                untrusted(&e.value, 200)
            };
        }
        s.forms.truncate(50);
        for f in &mut s.forms {
            f.action = truncate_chars(&f.action, 2048);
            f.method = f.method.to_ascii_lowercase().chars().take(10).collect();
            f.label = untrusted(&f.label, MAX_NAME);
            let fields: Vec<&Element> = s.elements.iter().filter(|e| e.form == f.id).collect();
            f.has_password = fields.iter().any(|e| e.input_type == "password");
            f.has_payment = fields.iter().any(|e| e.is_payment());
            let action = f.action.to_ascii_lowercase();
            f.is_search = !f.has_password
                && (fields
                    .iter()
                    .any(|e| e.input_type == "search" || e.role == "searchbox")
                    || action.contains("search")
                    || action.contains("?q=")
                    || f.label.to_ascii_lowercase().contains("search"));
        }
        Ok(s)
    }

    pub fn element(&self, id: &str) -> Result<&Element> {
        self.elements.iter().find(|e| e.id == id).ok_or_else(|| {
            Error::NotFound(format!(
                "no element {id} in the current page snapshot (take a new one)"
            ))
        })
    }

    /// Refuses filling a sensitive or disabled field, or anything that is
    /// not a text field.
    pub fn check_fill(&self, id: &str) -> Result<&Element> {
        let e = self.element(id)?;
        if e.sensitive {
            return Err(Error::Invalid(
                "Pilot does not fill passwords, one-time codes or payment details; the person fills those".into(),
            ));
        }
        if e.disabled {
            return Err(Error::Invalid("the field is disabled".into()));
        }
        if !matches!(
            e.role.as_str(),
            "textbox" | "textarea" | "searchbox" | "select" | "combobox" | "checkbox" | "radio"
        ) {
            return Err(Error::Invalid(format!("{id} is a {}, not a field", e.role)));
        }
        Ok(e)
    }

    pub fn form(&self, id: &str) -> Result<&Form> {
        self.forms
            .iter()
            .find(|f| f.id == id)
            .ok_or_else(|| Error::NotFound(format!("no form {id} in the snapshot")))
    }

    pub fn form_risk(&self, id: &str) -> Result<Risk> {
        let f = self.form(id)?;
        Ok(if f.has_payment {
            Risk::Payment
        } else if f.has_password {
            Risk::Login
        } else if f.is_search {
            Risk::Search
        } else {
            Risk::Other
        })
    }

    /// A compact outline for the model: one line per element,
    /// `[id] role "name" -> href`, at most `max` characters.
    pub fn outline(&self, max: usize) -> String {
        let mut out = String::new();
        for e in &self.elements {
            let mut line = format!("[{}] {}", e.id, e.role);
            if !e.input_type.is_empty() && e.input_type != e.role {
                let _ = write!(line, "({})", e.input_type);
            }
            if !e.label.is_empty() {
                let _ = write!(line, " \"{}\"", e.label.replace('"', "'"));
            }
            if !e.value.is_empty() {
                let _ = write!(line, " value=\"{}\"", e.value.replace('"', "'"));
            }
            if !e.href.is_empty() {
                let _ = write!(line, " -> {}", e.href);
            }
            if e.sensitive {
                line.push_str(" (sensitive: Pilot cannot fill)");
            }
            if !e.form.is_empty() {
                let _ = write!(line, " in {}", e.form);
            }
            line.push('\n');
            if out.len() + line.len() > max {
                out.push_str("...\n");
                break;
            }
            out.push_str(&line);
        }
        out
    }
}

/// Where Pilot's own tab may go: web pages only.
pub fn may_navigate(url: &str) -> Result<String> {
    let u = url::Url::parse(url)
        .or_else(|_| url::Url::parse(&format!("https://{url}")))
        .map_err(|_| Error::BadUrl(url.to_owned()))?;
    if !matches!(u.scheme(), "http" | "https") || u.host_str().is_none() {
        return Err(Error::Invalid(
            "Pilot can only open web pages (http and https)".into(),
        ));
    }
    Ok(u.to_string())
}

/// The state of Pilot's background browsing ("Pilot is browsing").
#[derive(Debug, Clone, Default, Serialize)]
pub struct AgentSession {
    pub active: bool,
    pub tab_id: i64,
    pub started: i64,
    /// The pages it visited, newest last (at most 50), shown to the person.
    pub visited: Vec<String>,
}

impl AgentSession {
    pub fn start(&mut self, tab_id: i64, now: i64) {
        *self = Self {
            active: true,
            tab_id,
            started: now,
            visited: Vec::new(),
        };
    }

    pub fn visited(&mut self, url: &str) {
        if self.visited.last().map(String::as_str) != Some(url) {
            self.visited.push(truncate_chars(url, 2048));
            if self.visited.len() > 50 {
                self.visited.remove(0);
            }
        }
    }

    pub fn stop(&mut self) {
        self.active = false;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The shape webview/js/agent.js returns.
    const SNAP: &str = r#"{"url":"https://shop.example/checkout","title":"Checkout\u202e evil","lang":"en",
      "viewport":{"width":360,"height":640,"scrollX":0,"scrollY":0,"scrollHeight":2000},
      "elements":[
      {"id":"e1","tag":"a","role":"link","label":"  Home \n\n page ","visible":true,"inViewport":true,"box":[0,0,10,10],"href":"https://shop.example/"},
      {"id":"e2","tag":"input","role":"textbox","label":"Email","visible":true,"inViewport":true,"name":"email","type":"email","value":"me@example.com","form":"e9"},
      {"id":"e3","tag":"input","role":"textbox","label":"Card number","visible":true,"inViewport":true,"name":"cardnumber","type":"text","autocomplete":"cc-number","value":"4111","form":"e9"},
      {"id":"e4","tag":"button","role":"button","label":"Pay now","visible":true,"inViewport":false,"form":"e9"},
      {"id":"e5","tag":"input","role":"textbox","label":"Coupon","visible":true,"inViewport":true,"type":"text","disabled":true},
      {"id":"e6","tag":"input","role":"textbox","label":"Password","visible":true,"inViewport":true,"type":"password","value":"•••","form":"e10"},
      {"id":"e7","tag":"input","role":"searchbox","label":"Search","visible":true,"inViewport":true,"type":"search","form":"e11"},
      {"id":"e8","tag":"select","role":"combobox","label":"Size","visible":true,"inViewport":true,"value":7}
    ],"forms":[{"id":"e9","action":"https://shop.example/pay","method":"POST","name":"","label":""},
               {"id":"e10","action":"https://shop.example/login","method":"post","name":"","label":""},
               {"id":"e11","action":"https://shop.example/find","method":"get","name":"","label":""}],
      "frames":[],"total":8,"truncated":false}"#;

    #[test]
    fn untrusted_text_is_cleaned_and_bounded() {
        assert_eq!(untrusted("a\u{202e}b\u{200b}c\u{0}d", 100), "abcd");
        assert_eq!(untrusted("  x \t  y\n\n\n\n z ", 100), "x y\n\nz");
        assert_eq!(untrusted(&"w ".repeat(100), 10).chars().count(), 10);
    }

    #[test]
    fn snapshot_parsing_and_rules() {
        let s = Snapshot::parse(SNAP).unwrap();
        assert_eq!(s.title, "Checkout evil");
        assert_eq!(s.elements[0].label, "Home\n\npage");
        assert!(s.check_fill("e2").is_ok());
        let card = s.element("e3").unwrap();
        assert!(card.sensitive);
        assert!(card.value.is_empty());
        assert!(s
            .check_fill("e3")
            .unwrap_err()
            .to_string()
            .contains("payment"));
        assert!(s.check_fill("e6").is_err());
        assert!(s.check_fill("e1").is_err());
        assert!(s.check_fill("e4").is_err());
        assert!(s.check_fill("e5").is_err());
        assert!(s.check_fill("e8").is_ok());
        assert_eq!(s.element("e8").unwrap().value, "7");
        assert!(s.check_fill("e99").is_err());
        assert_eq!(s.form_risk("e9").unwrap(), Risk::Payment);
        assert_eq!(s.form_risk("e10").unwrap(), Risk::Login);
        assert_eq!(s.form_risk("e11").unwrap(), Risk::Search);
        assert_eq!(s.forms[0].method, "post");
        let o = s.outline(10_000);
        assert!(o.contains("[e1] link \"Home"));
        assert!(o.contains("[e2] textbox(email) \"Email\" value=\"me@example.com\" in e9"));
        assert!(o.contains("(sensitive: Pilot cannot fill)"));
        assert!(s.outline(40).ends_with("...\n"));
    }

    #[test]
    fn snapshot_bounds() {
        let mut v: serde_json::Value = serde_json::from_str(SNAP).unwrap();
        let el = v["elements"][0].clone();
        v["elements"] = serde_json::Value::Array(vec![el; 300]);
        let s = Snapshot::parse(&v.to_string()).unwrap();
        assert_eq!(s.elements.len(), MAX_ELEMENTS);
        assert!(s.truncated);
        assert!(Snapshot::parse("{").is_err());
    }

    #[test]
    fn pilot_navigation_and_session() {
        assert_eq!(may_navigate("example.com").unwrap(), "https://example.com/");
        assert!(may_navigate("file:///etc/passwd").is_err());
        assert!(may_navigate("javascript:alert(1)").is_err());
        let mut a = AgentSession::default();
        a.start(9, 100);
        a.visited("https://a/");
        a.visited("https://a/");
        for i in 0..60 {
            a.visited(&format!("https://p/{i}"));
        }
        assert_eq!(a.visited.len(), 50);
        assert!(a.active);
        a.stop();
        assert!(!a.active);
    }
}
