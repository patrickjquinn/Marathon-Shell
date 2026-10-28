// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! A static reader for the part of QML that declarations use: imports, the
//! object tree, and bindings whose values are literals (strings, numbers,
//! booleans, `null`, `qsTr("...")`, lists, JavaScript object literals and
//! nested objects). Anything else (expressions, handlers, functions,
//! property declarations) is kept as source text or skipped; the
//! declaration reader rejects it where it needs a literal.

use std::fmt;
use std::fmt::Write as _;

#[derive(Clone, Debug, PartialEq)]
pub enum QValue {
    Str(String),
    Num(f64),
    Bool(bool),
    Null,
    List(Vec<QValue>),
    /// A JavaScript object literal `{ key: value }`.
    JsObject(Vec<(String, QValue)>),
    /// A QML object `Type { ... }`.
    Object(QObject),
    /// Anything else, as its source text.
    Expr(String),
}

#[derive(Clone, Debug, PartialEq, Default)]
pub struct QObject {
    /// As written, possibly qualified (`KA.KeelAction`).
    pub type_name: String,
    pub line: usize,
    pub bindings: Vec<Binding>,
    pub children: Vec<QObject>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Binding {
    pub name: String,
    pub value: QValue,
    pub line: usize,
}

#[derive(Clone, Debug, PartialEq, Default)]
pub struct Import {
    pub uri: String,
    pub alias: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Default)]
pub struct Document {
    pub imports: Vec<Import>,
    pub root: QObject,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ParseError {
    pub line: usize,
    pub message: String,
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "line {}: {}", self.line, self.message)
    }
}

#[derive(Clone, Debug, PartialEq)]
enum Tok {
    Ident(String),
    Str(String),
    /// A template literal (always an expression).
    Template(String),
    Num(f64),
    Punct(char),
}

#[derive(Clone, Debug)]
struct Token {
    tok: Tok,
    line: usize,
    newline_before: bool,
}

#[allow(
    clippy::too_many_lines,
    clippy::many_single_char_names,
    reason = "one hand-written lexer loop"
)]
fn tokenize(src: &str) -> Result<Vec<Token>, ParseError> {
    let chars: Vec<char> = src.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    let mut line = 1;
    let mut newline = true;
    while i < chars.len() {
        let c = chars[i];
        if c == '\n' {
            line += 1;
            newline = true;
            i += 1;
            continue;
        }
        if c.is_whitespace() {
            i += 1;
            continue;
        }
        if c == '/' && chars.get(i + 1) == Some(&'/') {
            while i < chars.len() && chars[i] != '\n' {
                i += 1;
            }
            continue;
        }
        if c == '/' && chars.get(i + 1) == Some(&'*') {
            i += 2;
            while i < chars.len() && !(chars[i] == '*' && chars.get(i + 1) == Some(&'/')) {
                if chars[i] == '\n' {
                    line += 1;
                    newline = true;
                }
                i += 1;
            }
            i += 2;
            continue;
        }
        let start_line = line;
        let tok = if c == '"' || c == '\'' || c == '`' {
            let mut s = String::new();
            i += 1;
            loop {
                let Some(&d) = chars.get(i) else {
                    return Err(ParseError {
                        line: start_line,
                        message: "unterminated string".into(),
                    });
                };
                i += 1;
                if d == c {
                    break;
                }
                if d == '\n' {
                    line += 1;
                }
                if d == '\\' {
                    let e = chars.get(i).copied().unwrap_or('\\');
                    i += 1;
                    match e {
                        'n' => s.push('\n'),
                        't' => s.push('\t'),
                        'r' => s.push('\r'),
                        'u' => {
                            let hex: String = chars.iter().skip(i).take(4).collect();
                            i += 4;
                            s.push(
                                u32::from_str_radix(&hex, 16)
                                    .ok()
                                    .and_then(char::from_u32)
                                    .unwrap_or('\u{fffd}'),
                            );
                        }
                        '\n' => line += 1,
                        other => s.push(other),
                    }
                } else {
                    s.push(d);
                }
            }
            if c == '`' {
                Tok::Template(s)
            } else {
                Tok::Str(s)
            }
        } else if c.is_ascii_digit()
            || (c == '.' && chars.get(i + 1).is_some_and(char::is_ascii_digit))
        {
            let start = i;
            while i < chars.len()
                && (chars[i].is_ascii_alphanumeric() || chars[i] == '.' || chars[i] == '_')
            {
                i += 1;
            }
            let text: String = chars[start..i].iter().filter(|c| **c != '_').collect();
            let value = if let Some(hex) = text.strip_prefix("0x") {
                u32::from_str_radix(hex, 16).map_or(f64::NAN, f64::from)
            } else {
                text.parse::<f64>().unwrap_or(f64::NAN)
            };
            Tok::Num(value)
        } else if c.is_alphabetic() || c == '_' || c == '$' {
            let start = i;
            while i < chars.len()
                && (chars[i].is_alphanumeric() || chars[i] == '_' || chars[i] == '$')
            {
                i += 1;
            }
            Tok::Ident(chars[start..i].iter().collect())
        } else {
            i += 1;
            Tok::Punct(c)
        };
        out.push(Token {
            tok,
            line: start_line,
            newline_before: newline,
        });
        newline = false;
    }
    Ok(out)
}

struct Parser {
    toks: Vec<Token>,
    pos: usize,
}

const KEYWORDS: &[&str] = &[
    "property",
    "readonly",
    "required",
    "default",
    "signal",
    "function",
    "enum",
    "component",
    "final",
    "virtual",
    "override",
];

impl Parser {
    fn peek(&self, n: usize) -> Option<&Tok> {
        self.toks.get(self.pos + n).map(|t| &t.tok)
    }
    fn line(&self) -> usize {
        self.toks
            .get(self.pos)
            .or_else(|| self.toks.last())
            .map_or(0, |t| t.line)
    }
    fn err<T>(&self, message: impl Into<String>) -> Result<T, ParseError> {
        Err(ParseError {
            line: self.line(),
            message: message.into(),
        })
    }
    fn is_punct(&self, n: usize, c: char) -> bool {
        self.peek(n) == Some(&Tok::Punct(c))
    }
    fn expect_punct(&mut self, c: char) -> Result<(), ParseError> {
        if self.is_punct(0, c) {
            self.pos += 1;
            Ok(())
        } else {
            self.err(format!("expected `{c}`, found {:?}", self.peek(0)))
        }
    }
    fn ident(&self, n: usize) -> Option<&str> {
        match self.peek(n) {
            Some(Tok::Ident(s)) => Some(s),
            _ => None,
        }
    }

    /// Length (in tokens) of a dotted name `a.b.c` at `pos + n`.
    fn dotted_len(&self, n: usize) -> usize {
        let mut k = n;
        if self.ident(k).is_none() {
            return 0;
        }
        k += 1;
        while self.is_punct(k, '.') && self.ident(k + 1).is_some() {
            k += 2;
        }
        k - n
    }

    fn dotted(&mut self) -> String {
        let len = self.dotted_len(0);
        let mut s = String::new();
        for t in &self.toks[self.pos..self.pos + len] {
            match &t.tok {
                Tok::Ident(i) => s.push_str(i),
                Tok::Punct(c) => s.push(*c),
                _ => {}
            }
        }
        self.pos += len;
        s
    }

    /// An object declaration starts here: `Type {` or `Qualified.Type {`
    /// with an upper-case last segment.
    fn at_object(&self) -> bool {
        let len = self.dotted_len(0);
        if len == 0 || !self.is_punct(len, '{') {
            return false;
        }
        matches!(self.peek(len - 1), Some(Tok::Ident(s)) if s.starts_with(|c: char| c.is_uppercase()))
    }

    /// A member starts at `pos + n` (for ending an expression at a newline).
    fn member_starts(&self, n: usize) -> bool {
        match self.peek(n) {
            Some(Tok::Punct('}' | ';')) | None => true,
            Some(Tok::Ident(s)) if KEYWORDS.contains(&s.as_str()) => true,
            Some(Tok::Ident(_)) => {
                let len = self.dotted_len(n);
                self.is_punct(n + len, ':') || self.is_punct(n + len, '{')
            }
            _ => false,
        }
    }

    fn document(&mut self) -> Result<Document, ParseError> {
        let mut imports = Vec::new();
        loop {
            match self.ident(0) {
                Some("import") => {
                    self.pos += 1;
                    let uri = match self.peek(0) {
                        Some(Tok::Str(s)) => {
                            let s = s.clone();
                            self.pos += 1;
                            s
                        }
                        _ => self.dotted(),
                    };
                    let mut alias = None;
                    while self.pos < self.toks.len() && !self.toks[self.pos].newline_before {
                        if self.ident(0) == Some("as") {
                            alias = self.ident(1).map(ToOwned::to_owned);
                        }
                        self.pos += 1;
                    }
                    imports.push(Import { uri, alias });
                }
                Some("pragma") => {
                    self.pos += 1;
                    while self.pos < self.toks.len() && !self.toks[self.pos].newline_before {
                        self.pos += 1;
                    }
                }
                _ => break,
            }
        }
        if !self.at_object() {
            return self.err("expected the root object");
        }
        let root = self.object()?;
        Ok(Document { imports, root })
    }

    fn object(&mut self) -> Result<QObject, ParseError> {
        let line = self.line();
        let type_name = self.dotted();
        self.expect_punct('{')?;
        let mut object = QObject {
            type_name,
            line,
            ..QObject::default()
        };
        loop {
            match self.peek(0) {
                None => return self.err("unexpected end of file in an object"),
                Some(Tok::Punct('}')) => {
                    self.pos += 1;
                    return Ok(object);
                }
                Some(Tok::Punct(';' | ',')) => self.pos += 1,
                Some(Tok::Ident(kw))
                    if KEYWORDS.contains(&kw.as_str()) && !self.is_punct(1, ':') =>
                {
                    self.declaration()?;
                }
                _ if self.at_object() => object.children.push(self.object()?),
                Some(Tok::Ident(_)) => {
                    // `Behavior on x { }`
                    if self.ident(1) == Some("on") && self.ident(2).is_some() {
                        self.pos += 2;
                        let len = self.dotted_len(0);
                        self.pos += len;
                        self.skip_balanced()?;
                        continue;
                    }
                    let line = self.line();
                    let name = self.dotted();
                    if !self.is_punct(0, ':') {
                        return self.err(format!("expected `:` after {name}"));
                    }
                    self.pos += 1;
                    let value = self.value()?;
                    object.bindings.push(Binding { name, value, line });
                }
                Some(other) => return self.err(format!("unexpected {other:?} in an object")),
            }
        }
    }

    /// `property ...`, `signal ...`, `function ...`, `enum ...`,
    /// `component X: Type { }`: skipped (a property's initial value too).
    fn declaration(&mut self) -> Result<(), ParseError> {
        while let Some(kw) = self.ident(0) {
            if matches!(
                kw,
                "readonly" | "required" | "default" | "final" | "virtual" | "override"
            ) {
                self.pos += 1;
            } else {
                break;
            }
        }
        match self.ident(0) {
            Some("property") => {
                self.pos += 1;
                // type (possibly list<T>) and name
                self.dotted();
                if self.is_punct(0, '<') {
                    while self.peek(0).is_some() && !self.is_punct(0, '>') {
                        self.pos += 1;
                    }
                    self.pos += 1;
                }
                self.dotted();
                if self.is_punct(0, ':') {
                    self.pos += 1;
                    self.value()?;
                }
            }
            Some("signal") => {
                self.pos += 1;
                self.dotted();
                if self.is_punct(0, '(') {
                    self.skip_balanced()?;
                }
            }
            Some("function") => {
                self.pos += 1;
                self.dotted();
                self.skip_balanced()?; // parameters
                if self.is_punct(0, ':') {
                    // return type annotation
                    self.pos += 1;
                    self.dotted();
                }
                self.skip_balanced()?; // body
            }
            Some("enum") => {
                self.pos += 2;
                self.skip_balanced()?;
            }
            Some("component") => {
                self.pos += 2;
                self.expect_punct(':')?;
                self.object()?;
            }
            _ => self.pos += 1,
        }
        Ok(())
    }

    /// Skips a balanced `(...)`, `[...]` or `{...}` group starting here.
    fn skip_balanced(&mut self) -> Result<(), ParseError> {
        let mut depth = 0usize;
        loop {
            match self.peek(0) {
                None => return self.err("unbalanced brackets"),
                Some(Tok::Punct('(' | '[' | '{')) => depth += 1,
                Some(Tok::Punct(')' | ']' | '}')) => {
                    depth = depth.saturating_sub(1);
                    if depth == 0 {
                        self.pos += 1;
                        return Ok(());
                    }
                }
                _ => {}
            }
            self.pos += 1;
        }
    }

    /// Skips an expression from here, returning its source text.
    fn skip_expression(&mut self, in_list: bool) -> String {
        let mut text = String::new();
        let mut depth = 0usize;
        let start = self.pos;
        while let Some(tok) = self.peek(0) {
            if depth == 0 && self.pos > start {
                if self.toks[self.pos].newline_before && self.member_starts(0) {
                    break;
                }
                if matches!(tok, Tok::Punct(';' | '}'))
                    || (in_list && matches!(tok, Tok::Punct(',' | ']')))
                {
                    break;
                }
            }
            match tok {
                Tok::Punct('(' | '[' | '{') => depth += 1,
                Tok::Punct(')' | ']' | '}') => {
                    if depth == 0 {
                        break;
                    }
                    depth -= 1;
                }
                _ => {}
            }
            if text.len() < 200 {
                match tok {
                    Tok::Ident(s) => {
                        text.push_str(s);
                        text.push(' ');
                    }
                    Tok::Str(s) | Tok::Template(s) => {
                        let _ = write!(text, "{s:?} ");
                    }
                    Tok::Num(n) => {
                        let _ = write!(text, "{n} ");
                    }
                    Tok::Punct(c) => text.push(*c),
                }
            }
            self.pos += 1;
        }
        if self.is_punct(0, ';') && !in_list {
            self.pos += 1;
        }
        text.trim().to_owned()
    }

    /// Does the value just parsed end here (so it was a whole literal)?
    fn value_ends(&self, in_list: bool) -> bool {
        match self.peek(0) {
            None | Some(Tok::Punct(';' | '}')) => true,
            Some(Tok::Punct(',' | ']')) if in_list => true,
            _ => self.toks[self.pos].newline_before && self.member_starts(0),
        }
    }

    fn value(&mut self) -> Result<QValue, ParseError> {
        self.value_in(false)
    }

    fn value_in(&mut self, in_list: bool) -> Result<QValue, ParseError> {
        if self.at_object() {
            return Ok(QValue::Object(self.object()?));
        }
        let start = self.pos;
        if let Some(v) = self.literal()? {
            if self.value_ends(in_list) {
                if self.is_punct(0, ';') && !in_list {
                    self.pos += 1;
                }
                return Ok(v);
            }
        }
        self.pos = start;
        Ok(QValue::Expr(self.skip_expression(in_list)))
    }

    /// A literal value, or None (position unspecified) if there is none.
    fn literal(&mut self) -> Result<Option<QValue>, ParseError> {
        let Some(tok) = self.peek(0).cloned() else {
            return Ok(None);
        };
        Ok(match tok {
            Tok::Str(s) => {
                self.pos += 1;
                Some(QValue::Str(s))
            }
            Tok::Num(n) => {
                self.pos += 1;
                Some(QValue::Num(n))
            }
            Tok::Punct('-') => match self.peek(1) {
                Some(Tok::Num(n)) => {
                    let n = *n;
                    self.pos += 2;
                    Some(QValue::Num(-n))
                }
                _ => None,
            },
            Tok::Ident(ref i) if i == "true" || i == "false" => {
                self.pos += 1;
                Some(QValue::Bool(i == "true"))
            }
            Tok::Ident(ref i) if i == "null" => {
                self.pos += 1;
                Some(QValue::Null)
            }
            Tok::Ident(ref i) if (i == "qsTr" || i == "QT_TR_NOOP") && self.is_punct(1, '(') => {
                match self.peek(2) {
                    Some(Tok::Str(s)) if self.is_punct(3, ')') => {
                        let s = s.clone();
                        self.pos += 4;
                        Some(QValue::Str(s))
                    }
                    _ => None,
                }
            }
            Tok::Punct('[') => {
                self.pos += 1;
                let mut items = Vec::new();
                loop {
                    if self.is_punct(0, ']') {
                        self.pos += 1;
                        break;
                    }
                    let item = if self.at_object() {
                        QValue::Object(self.object()?)
                    } else {
                        match self.literal()? {
                            Some(v) => v,
                            None => return Ok(None),
                        }
                    };
                    items.push(item);
                    if self.is_punct(0, ',') {
                        self.pos += 1;
                    } else if !self.is_punct(0, ']') {
                        return Ok(None);
                    }
                }
                Some(QValue::List(items))
            }
            Tok::Punct('{') => {
                self.pos += 1;
                let mut entries = Vec::new();
                loop {
                    if self.is_punct(0, '}') {
                        self.pos += 1;
                        break;
                    }
                    let key = match self.peek(0) {
                        Some(Tok::Ident(k) | Tok::Str(k)) => k.clone(),
                        _ => return Ok(None),
                    };
                    self.pos += 1;
                    if !self.is_punct(0, ':') {
                        return Ok(None);
                    }
                    self.pos += 1;
                    let Some(v) = self.literal()? else {
                        return Ok(None);
                    };
                    entries.push((key, v));
                    if self.is_punct(0, ',') {
                        self.pos += 1;
                    } else if !self.is_punct(0, '}') {
                        return Ok(None);
                    }
                }
                Some(QValue::JsObject(entries))
            }
            _ => None,
        })
    }
}

/// Parses a QML document.
pub fn parse(src: &str) -> Result<Document, ParseError> {
    let toks = tokenize(src)?;
    Parser { toks, pos: 0 }.document()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_declarations_and_skips_code() {
        let doc = parse(
            r#"
import QtQuick 2.15
import Keel.Actions 1.0 as KA
// comment
Item {
    id: root
    property var notes: [ { id: "n1" } ]
    property int n: 3; signal done(string x)
    function f(a, b) { if (a) { return b } return { x: 1 } }
    KA.KeelAction {
        name: "notes.create"
        title: qsTr("Create note")
        timeout: -5
        enabled: root.n > 2 &&
            root.n < 9
        parameters: [
            KA.KeelParam { name: "title"; type: "string"; maxLength: 200 },
            KA.KeelParam { name: "body"; required: true }
        ]
        returns: KA.KeelResult { type: "object"; fields: ["id"] }
        onInvoked: (args, call) => {
            call.reply({ id: 1 })
        }
        anchors.fill: parent
    }
    KeelShortcut { steps: [ { action: "a.b", arguments: { title: "x", n: 2 } } ] }
    Behavior on opacity { NumberAnimation {} }
}
"#,
        )
        .unwrap();
        assert_eq!(doc.imports[1].uri, "Keel.Actions");
        assert_eq!(doc.imports[1].alias.as_deref(), Some("KA"));
        let action = &doc.root.children[0];
        assert_eq!(action.type_name, "KA.KeelAction");
        let get = |n: &str| &action.bindings.iter().find(|b| b.name == n).unwrap().value;
        assert_eq!(get("name"), &QValue::Str("notes.create".into()));
        assert_eq!(get("title"), &QValue::Str("Create note".into()));
        assert_eq!(get("timeout"), &QValue::Num(-5.0));
        assert!(matches!(get("enabled"), QValue::Expr(_)));
        assert!(matches!(get("onInvoked"), QValue::Expr(_)));
        assert!(matches!(get("anchors.fill"), QValue::Expr(_)));
        let QValue::List(params) = get("parameters") else {
            panic!()
        };
        assert_eq!(params.len(), 2);
        let QValue::Object(ret) = get("returns") else {
            panic!()
        };
        assert_eq!(ret.type_name, "KA.KeelResult");
        let shortcut = &doc.root.children[1];
        let QValue::List(steps) = &shortcut.bindings[0].value else {
            panic!()
        };
        assert!(matches!(&steps[0], QValue::JsObject(e) if e.len() == 2));
    }
}
