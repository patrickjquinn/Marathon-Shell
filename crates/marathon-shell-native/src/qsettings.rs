//! `QSettings`' INI dialect, so an older image reads what this one writes:
//! `[group]` sections, `"a, b"` lists, quoted and escaped strings, and
//! `@Variant(...)`, a `QDataStream` at version 4.0, for maps.

use std::collections::BTreeMap;
use std::fmt::Write as _;

use marathon_qt as qvariant;
use zbus::zvariant;

#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Invalid,
    Text(String),
    List(Vec<String>),
    Bool(bool),
    Int(i64),
    Double(f64),
    Seq(Vec<Value>),
    Map(BTreeMap<String, Value>),
}

impl Value {
    /// As `QVariant::toBool`.
    pub fn as_bool(&self) -> Option<bool> {
        Some(match self {
            Self::Text(s) => !(s.is_empty() || s == "0" || s.eq_ignore_ascii_case("false")),
            Self::Bool(b) => *b,
            Self::Int(n) => *n != 0,
            Self::Double(d) => *d != 0.0,
            _ => return None,
        })
    }

    #[allow(clippy::cast_precision_loss, reason = "settings values")]
    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Self::Text(s) => s.trim().parse().ok(),
            Self::Int(n) => Some(*n as f64),
            Self::Double(d) => Some(*d),
            Self::Bool(b) => Some(f64::from(u8::from(*b))),
            _ => None,
        }
    }

    #[allow(clippy::cast_possible_truncation, reason = "rounded, as QVariant does")]
    pub fn as_i64(&self) -> Option<i64> {
        match self {
            Self::Text(s) => s.trim().parse().ok(),
            Self::Double(d) => Some(d.round() as i64),
            other => other.as_f64().map(|f| f as i64),
        }
    }

    pub fn as_text(&self) -> Option<String> {
        match self {
            Self::Text(s) => Some(s.clone()),
            Self::Bool(b) => Some(b.to_string()),
            Self::Int(n) => Some(n.to_string()),
            Self::Double(d) => Some(d.to_string()),
            _ => None,
        }
    }

    /// As `QVariant::toStringList`: one string is a list of one.
    pub fn as_list(&self) -> Vec<String> {
        match self {
            Self::List(l) => l.clone(),
            Self::Seq(s) => s.iter().filter_map(Self::as_text).collect(),
            Self::Invalid | Self::Map(_) => Vec::new(),
            other => other.as_text().into_iter().collect(),
        }
    }
}

impl Value {
    /// What a D-Bus caller (or QML, through `qvariant`) stores.
    pub fn from_dbus(value: &zvariant::Value<'_>) -> Self {
        use zvariant::Value as V;
        match value {
            V::Bool(b) => Self::Bool(*b),
            V::F64(f) => Self::Double(*f),
            V::Str(s) => Self::Text(s.as_str().to_owned()),
            V::ObjectPath(p) => Self::Text(p.as_str().to_owned()),
            V::Value(inner) => Self::from_dbus(inner),
            V::Array(items) if items.element_signature() == "s" => Self::List(
                items
                    .iter()
                    .filter_map(|v| <&str>::try_from(v).ok().map(str::to_owned))
                    .collect(),
            ),
            V::Array(items) => Self::Seq(items.iter().map(Self::from_dbus).collect()),
            V::Dict(dict) => Self::Map(
                dict.iter()
                    .map(|(k, v)| {
                        (
                            <&str>::try_from(k).map(str::to_owned).unwrap_or_default(),
                            Self::from_dbus(v),
                        )
                    })
                    .collect(),
            ),
            other => qvariant::number(other).map_or(Self::Invalid, Self::Int),
        }
    }

    /// What D-Bus carries back; an invalid value is an empty string.
    pub fn to_dbus(&self) -> zvariant::Value<'static> {
        use zvariant::Value as V;
        match self {
            Self::Invalid => V::from(String::new()),
            Self::Text(s) => V::from(s.clone()),
            Self::List(l) => V::from(l.clone()),
            Self::Bool(b) => V::from(*b),
            Self::Int(n) => i32::try_from(*n).map_or_else(|_| V::from(*n), V::from),
            Self::Double(d) => V::from(*d),
            Self::Seq(s) => V::from(
                s.iter()
                    .map(|v| V::Value(Box::new(v.to_dbus())))
                    .collect::<Vec<_>>(),
            ),
            Self::Map(m) => V::from(
                m.iter()
                    .map(|(k, v)| (k.clone(), V::Value(Box::new(v.to_dbus()))))
                    .collect::<std::collections::HashMap<_, _>>(),
            ),
        }
    }
}

/// A settings file's entries, by `group/key` (`key` alone in `[General]`).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Ini(pub BTreeMap<String, Value>);

impl Ini {
    pub fn parse(text: &str) -> Self {
        let mut entries = BTreeMap::new();
        let mut group = String::new();
        let mut lines = text.lines();
        while let Some(line) = lines.next() {
            let line = line.trim_start();
            if line.is_empty() || line.starts_with([';', '#']) {
                continue;
            }
            if let Some(name) = line
                .strip_prefix('[')
                .and_then(|l| l.trim_end().strip_suffix(']'))
            {
                group = match name {
                    "General" => String::new(),
                    "%General" => "General".to_owned(),
                    name => unescape_key(name),
                };
                continue;
            }
            let Some((key, value)) = line.split_once('=') else {
                continue;
            };
            let mut value = value.to_owned();
            while value.ends_with('\\') && !value.ends_with("\\\\") {
                value.pop();
                value.push_str(lines.next().unwrap_or_default());
            }
            let key = unescape_key(key.trim());
            let full = if group.is_empty() {
                key
            } else {
                format!("{group}/{key}")
            };
            entries.insert(full, parse_value(&value));
        }
        Self(entries)
    }

    pub fn render(&self) -> String {
        let mut sections: BTreeMap<&str, Vec<(&str, &Value)>> = BTreeMap::new();
        for (key, value) in &self.0 {
            let (group, key) = key.split_once('/').unwrap_or(("", key));
            sections.entry(group).or_default().push((key, value));
        }
        let mut out = String::new();
        for (group, entries) in sections {
            if !out.is_empty() {
                out.push('\n');
            }
            let name = match group {
                "" => "General".to_owned(),
                "General" => "%General".to_owned(),
                g => escape_key(g),
            };
            writeln!(out, "[{name}]").ok();
            for (key, value) in entries {
                writeln!(out, "{}={}", escape_key(key), render_value(value)).ok();
            }
        }
        out
    }

    /// Removes `prefix` and every key under it.
    pub fn remove_tree(&mut self, prefix: &str) {
        let under = format!("{prefix}/");
        self.0.retain(|k, _| k != prefix && !k.starts_with(&under));
    }
}

fn escape_key(key: &str) -> String {
    let mut out = String::new();
    for c in key.chars() {
        match c {
            '/' => out.push('\\'),
            'a'..='z' | 'A'..='Z' | '0'..='9' | '_' | '-' | '.' => out.push(c),
            c if u32::from(c) <= 0xFF => {
                write!(out, "%{:02X}", u32::from(c)).ok();
            }
            c => {
                write!(out, "%U{:04X}", u32::from(c)).ok();
            }
        }
    }
    out
}

fn unescape_key(key: &str) -> String {
    let mut out = String::new();
    let mut chars = key.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '\\' => out.push('/'),
            '%' => {
                let wide = chars.peek() == Some(&'U');
                if wide {
                    chars.next();
                }
                let hex: String = chars.by_ref().take(if wide { 4 } else { 2 }).collect();
                if let Some(c) = u32::from_str_radix(&hex, 16).ok().and_then(char::from_u32) {
                    out.push(c);
                } else {
                    out.push('%');
                    out.push_str(&hex);
                }
            }
            c => out.push(c),
        }
    }
    out
}

/// One string as `QSettings` escapes it; `raw` for a `@Variant`'s bytes,
/// which escape everything outside ASCII.
fn escape(s: &str, raw: bool, out: &mut String) {
    let start = out.len();
    let mut quote = false;
    let mut after_number = false;
    for c in s.chars() {
        quote |= matches!(c, ';' | ',' | '=');
        if after_number && c.is_ascii_hexdigit() {
            write!(out, "\\x{:x}", u32::from(c)).ok();
            continue;
        }
        after_number = false;
        match c {
            '\0' => {
                out.push_str("\\0");
                after_number = true;
            }
            '\x07' => out.push_str("\\a"),
            '\x08' => out.push_str("\\b"),
            '\x0c' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\x0b' => out.push_str("\\v"),
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            c if u32::from(c) <= 0x1F || (raw && u32::from(c) >= 0x7F) => {
                write!(out, "\\x{:x}", u32::from(c)).ok();
                after_number = true;
            }
            c => out.push(c),
        }
    }
    let body = &out[start..];
    if quote || body.starts_with(char::is_whitespace) || body.ends_with(char::is_whitespace) {
        out.insert(start, '"');
        out.push('"');
    }
}

fn scalar_text(value: &Value) -> String {
    match value {
        Value::Text(s) if s.starts_with('@') => format!("@{s}"),
        Value::Invalid => "@Invalid()".to_owned(),
        Value::Map(_) | Value::Seq(_) => {
            let bytes = stream(value);
            format!(
                "@Variant({})",
                bytes.iter().map(|&b| char::from(b)).collect::<String>()
            )
        }
        other => other.as_text().unwrap_or_default(),
    }
}

fn render_value(value: &Value) -> String {
    let mut out = String::new();
    let items: Vec<String> = match value {
        Value::List(l) if l.len() != 1 => l
            .iter()
            .map(|s| scalar_text(&Value::Text(s.clone())))
            .collect(),
        Value::List(l) => vec![scalar_text(&Value::Text(l[0].clone()))],
        Value::Seq(s) if s.len() != 1 => s.iter().map(scalar_text).collect(),
        other => vec![scalar_text(other)],
    };
    if items.is_empty() {
        return "@Invalid()".to_owned();
    }
    for (i, item) in items.iter().enumerate() {
        if i > 0 {
            out.push_str(", ");
        }
        escape(item, item.starts_with("@Variant("), &mut out);
    }
    out
}

fn parse_value(text: &str) -> Value {
    let mut pieces = Vec::new();
    let (mut cur, mut gap) = (String::new(), String::new());
    let (mut quoted, mut started) = (false, false);
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '"' => {
                cur.push_str(&std::mem::take(&mut gap));
                quoted = !quoted;
                started = true;
            }
            ',' if !quoted => {
                pieces.push(std::mem::take(&mut cur));
                gap.clear();
                started = false;
            }
            c if c.is_whitespace() && !quoted => {
                if started {
                    gap.push(c);
                }
            }
            '\\' => {
                cur.push_str(&std::mem::take(&mut gap));
                started = true;
                let Some(e) = chars.next() else { break };
                let radix = match e {
                    'x' => 16,
                    '0'..='7' => 8,
                    _ => 0,
                };
                if radix == 0 {
                    cur.push(match e {
                        'a' => '\x07',
                        'b' => '\x08',
                        'f' => '\x0c',
                        'n' => '\n',
                        'r' => '\r',
                        't' => '\t',
                        'v' => '\x0b',
                        e => e,
                    });
                    continue;
                }
                let mut n = if radix == 8 {
                    e.to_digit(8).unwrap_or(0)
                } else {
                    0
                };
                while let Some(d) = chars.peek().and_then(|d| d.to_digit(radix)) {
                    n = n.wrapping_mul(radix).wrapping_add(d);
                    chars.next();
                }
                cur.push(char::from_u32(n).unwrap_or('\u{fffd}'));
            }
            c => {
                cur.push_str(&std::mem::take(&mut gap));
                cur.push(c);
                started = true;
            }
        }
    }
    pieces.push(cur);
    if pieces.len() > 1 {
        return Value::List(
            pieces
                .into_iter()
                .map(|p| {
                    p.strip_prefix('@')
                        .filter(|p| p.starts_with('@'))
                        .map_or_else(|| p.clone(), str::to_owned)
                })
                .collect(),
        );
    }
    let s = pieces.pop().unwrap_or_default();
    if let Some(rest) = s.strip_prefix("@@") {
        return Value::Text(format!("@{rest}"));
    }
    if s == "@Invalid()" {
        return Value::Invalid;
    }
    // What a version 4.0 stream has no word for (a `QDBusArgument` some
    // devices stored) reads as no value.
    if let Some(inner) = s
        .strip_prefix("@Variant(")
        .and_then(|r| r.strip_suffix(')'))
    {
        let bytes: Vec<u8> = inner
            .chars()
            .map(|c| u8::try_from(u32::from(c)).unwrap_or(0))
            .collect();
        return unstream(&mut bytes.as_slice()).unwrap_or(Value::Invalid);
    }
    if let Some(inner) = s
        .strip_prefix("@ByteArray(")
        .and_then(|r| r.strip_suffix(')'))
    {
        return Value::Text(inner.to_owned());
    }
    Value::Text(s)
}

// QMetaType ids, as a version 4.0 stream writes them.
const BOOL: u32 = 1;
const INT: u32 = 2;
const UINT: u32 = 3;
const LONG: u32 = 4;
const ULONG: u32 = 5;
const DOUBLE: u32 = 6;
const MAP: u32 = 8;
const LIST: u32 = 9;
const STRING: u32 = 10;
const STRINGS: u32 = 11;
const BYTES: u32 = 12;

fn put_string(s: &str, out: &mut Vec<u8>) {
    let units: Vec<u16> = s.encode_utf16().collect();
    out.extend(
        u32::try_from(units.len() * 2)
            .unwrap_or(u32::MAX)
            .to_be_bytes(),
    );
    out.extend(units.iter().flat_map(|u| u.to_be_bytes()));
}

fn put(value: &Value, out: &mut Vec<u8>) {
    let len = |n: usize| u32::try_from(n).unwrap_or(u32::MAX).to_be_bytes();
    match value {
        Value::Invalid => {
            out.extend(0u32.to_be_bytes());
            out.extend(u32::MAX.to_be_bytes());
        }
        Value::Bool(b) => {
            out.extend(BOOL.to_be_bytes());
            out.push(u8::from(*b));
        }
        Value::Int(n) => {
            if let Ok(small) = i32::try_from(*n) {
                out.extend(INT.to_be_bytes());
                out.extend(small.to_be_bytes());
            } else {
                out.extend(LONG.to_be_bytes());
                out.extend(n.to_be_bytes());
            }
        }
        Value::Double(d) => {
            out.extend(DOUBLE.to_be_bytes());
            out.extend(d.to_be_bytes());
        }
        Value::Text(s) => {
            out.extend(STRING.to_be_bytes());
            put_string(s, out);
        }
        Value::List(l) => {
            out.extend(STRINGS.to_be_bytes());
            out.extend(len(l.len()));
            for s in l {
                put_string(s, out);
            }
        }
        Value::Seq(s) => {
            out.extend(LIST.to_be_bytes());
            out.extend(len(s.len()));
            for v in s {
                put(v, out);
            }
        }
        // Qt streams a map from its last key to its first.
        Value::Map(m) => {
            out.extend(MAP.to_be_bytes());
            out.extend(len(m.len()));
            for (k, v) in m.iter().rev() {
                put_string(k, out);
                put(v, out);
            }
        }
    }
}

fn stream(value: &Value) -> Vec<u8> {
    let mut out = Vec::new();
    put(value, &mut out);
    out
}

fn take<const N: usize>(input: &mut &[u8]) -> Option<[u8; N]> {
    let (head, rest) = input.split_first_chunk::<N>()?;
    *input = rest;
    Some(*head)
}

fn take_u32(input: &mut &[u8]) -> Option<u32> {
    take::<4>(input).map(u32::from_be_bytes)
}

fn take_string(input: &mut &[u8]) -> Option<String> {
    let len = take_u32(input)?;
    if len == u32::MAX {
        return Some(String::new());
    }
    let len = usize::try_from(len).ok()?;
    let (bytes, rest) = input.split_at_checked(len)?;
    *input = rest;
    let units: Vec<u16> = bytes
        .as_chunks::<2>()
        .0
        .iter()
        .map(|c| u16::from_be_bytes(*c))
        .collect();
    Some(String::from_utf16_lossy(&units))
}

fn unstream(input: &mut &[u8]) -> Option<Value> {
    let count = |input: &mut &[u8]| take_u32(input).and_then(|n| usize::try_from(n).ok());
    Some(match take_u32(input)? {
        0 => {
            take_string(input)?;
            Value::Invalid
        }
        BOOL => Value::Bool(take::<1>(input)?[0] != 0),
        INT => Value::Int(i64::from(i32::from_be_bytes(take(input)?))),
        UINT => Value::Int(i64::from(u32::from_be_bytes(take(input)?))),
        LONG => Value::Int(i64::from_be_bytes(take(input)?)),
        ULONG => Value::Int(i64::try_from(u64::from_be_bytes(take(input)?)).ok()?),
        DOUBLE => Value::Double(f64::from_be_bytes(take(input)?)),
        STRING => Value::Text(take_string(input)?),
        BYTES => {
            let len = take_u32(input)?;
            let len = if len == u32::MAX {
                0
            } else {
                usize::try_from(len).ok()?
            };
            let (bytes, rest) = input.split_at_checked(len)?;
            *input = rest;
            Value::Text(String::from_utf8_lossy(bytes).into_owned())
        }
        STRINGS => Value::List(
            (0..count(input)?)
                .map(|_| take_string(input))
                .collect::<Option<_>>()?,
        ),
        LIST => Value::Seq(
            (0..count(input)?)
                .map(|_| unstream(input))
                .collect::<Option<_>>()?,
        ),
        MAP => Value::Map(
            (0..count(input)?)
                .map(|_| Some((take_string(input)?, unstream(input)?)))
                .collect::<Option<_>>()?,
        ),
        _ => return None,
    })
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use std::collections::BTreeMap;

    use super::{Ini, Value};

    // From the HackberryPi's file, as Qt 6.11 wrote it.
    const DEVICE: &str = r#"[alarms]
data=[]

[apps]
defaultFiles=
hiddenApps=test
gridColumns=0

[audio]
alarmVolume=0.9
dndEnabled=true

[clock]
timer="{\"endsAt\":-1,\"total\":20,\"remaining\":0}"

[notifications]
appSettings=@Variant(\0\0\0\b\0\0\0\0)

[quicksettings]
tiles=wifi, cellular, bluetooth

[ui]
wallpaperPath=file:///usr/share/marathon-shell/wallpapers/slate-aurora.svg
"#;

    #[test]
    fn qts_file_reads_back_as_qt_wrote_it() {
        let ini = Ini::parse(DEVICE);
        let get = |k: &str| ini.0.get(k).cloned().unwrap();
        assert_eq!(
            get("clock/timer"),
            Value::Text(r#"{"endsAt":-1,"total":20,"remaining":0}"#.into())
        );
        assert_eq!(
            get("notifications/appSettings"),
            Value::Map(BTreeMap::default())
        );
        assert_eq!(
            get("quicksettings/tiles").as_list(),
            ["wifi", "cellular", "bluetooth"]
        );
        assert_eq!(get("apps/hiddenApps").as_list(), ["test"]);
        assert_eq!(get("apps/defaultFiles"), Value::Text(String::new()));
        assert_eq!(get("audio/alarmVolume").as_f64(), Some(0.9));
        assert_eq!(get("audio/dndEnabled").as_bool(), Some(true));
        assert_eq!(Ini::parse(&ini.render()), ini);
    }

    #[test]
    fn writes_are_byte_for_byte_qts() {
        let mut ini = Ini::default();
        ini.0.insert(
            "notifications/appSettings".into(),
            Value::Map(BTreeMap::default()),
        );
        ini.0
            .insert("clock/timer".into(), Value::Text(r#"{"a":1,"b":2}"#.into()));
        ini.0
            .insert("apps/hiddenApps".into(), Value::List(vec!["test".into()]));
        ini.0.insert("apps/none".into(), Value::List(Vec::new()));
        ini.0
            .insert("ui/userScaleFactor".into(), Value::Double(1.0));
        ini.0.insert("firstKey".into(), Value::Bool(true));
        assert_eq!(
            ini.render(),
            "[General]\nfirstKey=true\n\n[apps]\nhiddenApps=test\nnone=@Invalid()\n\n[clock]\ntimer=\"{\\\"a\\\":1,\\\"b\\\":2}\"\n\n\
             [notifications]\nappSettings=@Variant(\\0\\0\\0\\b\\0\\0\\0\\0)\n\n[ui]\nuserScaleFactor=1\n"
        );
    }

    #[test]
    fn maps_strings_and_escapes_round_trip() {
        let mut map = BTreeMap::new();
        map.insert("org.example.App".to_owned(), Value::Bool(false));
        map.insert("Mývatn".to_owned(), Value::Text("a, \"b\"\n".into()));
        map.insert("n".to_owned(), Value::Int(-7));
        let mut ini = Ini::default();
        ini.0
            .insert("notifications/appSettings".into(), Value::Map(map));
        ini.0
            .insert("x/@lead".into(), Value::Text("@at, \tspaced ".into()));
        ini.0
            .insert("x/deep/key with space".into(), Value::Text("Mývatn".into()));
        assert_eq!(Ini::parse(&ini.render()), ini);
    }

    #[test]
    fn a_value_qt_cannot_stream_is_no_value() {
        let ini = Ini::parse("[calendar]\nevents=@Variant(\\0\\0\\x4\\x1\\0)\n");
        assert_eq!(ini.0.get("calendar/events"), Some(&Value::Invalid));
    }

    #[test]
    fn removing_an_apps_keys_keeps_the_rest() {
        let mut ini = Ini::parse("[notes]\na=1\nb\\c=2\n\n[notesx]\na=3\n");
        ini.remove_tree("notes");
        assert_eq!(ini.0.keys().collect::<Vec<_>>(), ["notesx/a"]);
    }
}
