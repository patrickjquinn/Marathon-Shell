// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Local PII redaction (spec section 4, step 3).
//!
//! Before anything leaves the device, phone numbers, email addresses,
//! postal addresses, contact names and account numbers are replaced with
//! typed placeholders such as `<CONTACT_1>`. The [`PlaceholderMap`] that
//! undoes it stays in `pilotd`'s memory for the turn and is never sent
//! anywhere; [`PlaceholderMap::restore`] re-applies it to the response.
//!
//! Detection is pattern based and deliberately greedy: a false positive
//! costs the model a little context, a false negative leaks personal data.

use std::collections::HashMap;
use std::fmt;
use std::sync::OnceLock;

use regex::Regex;

/// The kinds of personal data the redactor replaces.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PiiKind {
    Phone,
    Email,
    Address,
    Contact,
    Account,
}

impl PiiKind {
    pub fn tag(self) -> &'static str {
        match self {
            PiiKind::Phone => "PHONE",
            PiiKind::Email => "EMAIL",
            PiiKind::Address => "ADDRESS",
            PiiKind::Contact => "CONTACT",
            PiiKind::Account => "ACCOUNT",
        }
    }

    fn from_tag(tag: &str) -> Option<PiiKind> {
        Some(match tag {
            "PHONE" => PiiKind::Phone,
            "EMAIL" => PiiKind::Email,
            "ADDRESS" => PiiKind::Address,
            "CONTACT" => PiiKind::Contact,
            "ACCOUNT" => PiiKind::Account,
            _ => return None,
        })
    }
}

impl fmt::Display for PiiKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.tag())
    }
}

/// Source of the names the redactor must hide: the phone's address book.
/// Behind a trait so tests and the Lite build (no contacts access) can
/// supply their own.
pub trait ContactNames: Send + Sync {
    /// Display names of every contact ("Anna Virtanen"). Called once per
    /// turn; implementations should cache.
    fn names(&self) -> Vec<String>;
}

/// No address book (Pilot Lite, or contacts consent withheld).
pub struct NoContacts;

impl ContactNames for NoContacts {
    fn names(&self) -> Vec<String> {
        Vec::new()
    }
}

impl ContactNames for Vec<String> {
    fn names(&self) -> Vec<String> {
        self.clone()
    }
}

/// Placeholder to original value, for one turn. Never serialised, never
/// logged, never sent.
#[derive(Default, Clone)]
pub struct PlaceholderMap {
    by_placeholder: HashMap<String, String>,
    by_value: HashMap<(PiiKind, String), String>,
    counters: HashMap<PiiKind, u32>,
}

impl fmt::Debug for PlaceholderMap {
    // Values are personal data: keep them out of debug output and logs.
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("PlaceholderMap")
            .field("entries", &self.by_placeholder.len())
            .finish_non_exhaustive()
    }
}

impl PlaceholderMap {
    /// The placeholder for `value`, minting `<KIND_n>` on first sight. The
    /// same value always gets the same placeholder within one map.
    pub fn placeholder(&mut self, kind: PiiKind, value: &str) -> String {
        let key = (kind, normalise(kind, value));
        if let Some(p) = self.by_value.get(&key) {
            return p.clone();
        }
        let n = self.counters.entry(kind).or_insert(0);
        *n += 1;
        let p = format!("<{}_{}>", kind.tag(), n);
        self.by_value.insert(key, p.clone());
        self.by_placeholder.insert(p.clone(), value.to_owned());
        p
    }

    /// The original value behind a placeholder.
    pub fn original(&self, placeholder: &str) -> Option<&str> {
        self.by_placeholder.get(placeholder).map(String::as_str)
    }

    /// The values the placeholders stand for: what the person (or the
    /// conversation) actually said.
    pub fn originals(&self) -> impl Iterator<Item = &str> {
        self.by_placeholder.values().map(String::as_str)
    }

    pub fn len(&self) -> usize {
        self.by_placeholder.len()
    }

    pub fn is_empty(&self) -> bool {
        self.by_placeholder.is_empty()
    }

    /// Puts the original values back into model output. Unknown
    /// placeholders (the model invented `<CONTACT_9>`) are left as they are.
    pub fn restore(&self, text: &str) -> String {
        if self.by_placeholder.is_empty() {
            return text.to_owned();
        }
        // The model writes them back as it likes: `<CONTACT_1>`, but also
        // `CONTACT_1` or `[CONTACT_1]` (an e-mail went to "EMAIL_1").
        loose_placeholder_re()
            .replace_all(text, |caps: &regex::Captures<'_>| {
                let whole = caps.get(0).map_or("", |m| m.as_str());
                let canonical = format!("<{}>", &caps[1]);
                self.original(&canonical).unwrap_or(whole).to_owned()
            })
            .into_owned()
    }

    /// [`restore`](Self::restore) applied to every string inside a JSON
    /// value: tool-call arguments from the model.
    pub fn restore_json(&self, value: &serde_json::Value) -> serde_json::Value {
        use serde_json::Value;
        match value {
            Value::String(s) => Value::String(self.restore(s)),
            Value::Array(a) => Value::Array(a.iter().map(|v| self.restore_json(v)).collect()),
            Value::Object(o) => Value::Object(
                o.iter()
                    .map(|(k, v)| (k.clone(), self.restore_json(v)))
                    .collect(),
            ),
            other => other.clone(),
        }
    }

    /// Kinds present, for tests and the egress log's "what was hidden".
    pub fn kinds(&self) -> Vec<PiiKind> {
        let mut k: Vec<PiiKind> = self.counters.keys().copied().collect();
        k.sort_by_key(|k| k.tag());
        k
    }
}

fn normalise(kind: PiiKind, value: &str) -> String {
    match kind {
        PiiKind::Phone | PiiKind::Account => value
            .chars()
            .filter(char::is_ascii_alphanumeric)
            .collect::<String>()
            .to_ascii_uppercase(),
        _ => value.to_lowercase(),
    }
}

fn placeholder_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"<(PHONE|EMAIL|ADDRESS|CONTACT|ACCOUNT)_[0-9]{1,4}>").expect("static regex")
    })
}

/// A placeholder with or without its brackets.
fn loose_placeholder_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"[<\[{]?\b((?:PHONE|EMAIL|ADDRESS|CONTACT|ACCOUNT)_[0-9]{1,4})\b[>\]}]?")
            .expect("static regex")
    })
}

/// Whether `text` is a placeholder this module could have produced.
pub fn is_placeholder(text: &str) -> bool {
    placeholder_re()
        .find(text)
        .is_some_and(|m| m.start() == 0 && m.end() == text.len())
        && PiiKind::from_tag(text[1..].split('_').next().unwrap_or("")).is_some()
}

struct Patterns {
    email: Regex,
    iban: Regex,
    card: Regex,
    account_ctx: Regex,
    phone: Regex,
    address: Regex,
    postcode: Regex,
    postcode_ctx: Regex,
    date_like: Regex,
}

fn patterns() -> &'static Patterns {
    static P: OnceLock<Patterns> = OnceLock::new();
    P.get_or_init(|| Patterns {
        email: Regex::new(r"(?i)\b[a-z0-9._%+\-]+@[a-z0-9\-]+(?:\.[a-z0-9\-]+)*\.[a-z]{2,}\b")
            .expect("static regex"),
        // IBAN: country, check digits, 11 to 30 alphanumerics, optionally
        // grouped in fours.
        iban: Regex::new(r"\b[A-Z]{2}[0-9]{2}(?:[ ]?[A-Z0-9]){11,30}\b").expect("static regex"),
        // Payment cards: 13 to 19 digits, grouped or not; Luhn-checked below.
        card: Regex::new(r"\b[0-9](?:[ \-]?[0-9]){12,18}\b").expect("static regex"),
        // A run of digits right after a word that says it is an account, a
        // card or a customer number, in English, Italian, Portuguese,
        // Spanish, Polish, Czech, Dutch, Swedish, Finnish, German, French,
        // Norwegian and Danish ("Kontonummer: 1234 5678", "numer konta
        // 12 3456 7890", "tilinumero on 123456-785").
        account_ctx: Regex::new(
            r"(?xi)
            \b(?:account|acct|a/c|sort\ code|iban|bic|card|policy|customer|member|reference|ref
               |numero\ di\ conto|conto|carta
               |número\ de\ conta|conta|cartão|nib
               |número\ de\ cuenta|cuenta|tarjeta
               |numer\ konta|numer\ rachunku|konto|rachunek|karta
               |číslo\ účtu|účet|účtu
               |rekeningnummer|rekening|kaart|pas
               |kontonummer|clearingnummer|bankgiro|plusgiro|kort
               |tilinumero|tili|kortti|asiakasnumero|viitenumero|viite
               |kundennummer|kontonr\.?|bankleitzahl|blz|karte
               |numéro\ de\ compte|compte|carte|rib
               |reg\.?\ ?nr\.?)
            (?:\s+(?:number|no\.?|nr\.?|\#|code|numero|número|numéro|numer|číslo|nummer))?
            \s*(?:is|:|on|är|er|ist|est|es|é|è|jest|je|to)?\s*:?\s*
            ([0-9][0-9\ \-]{4,30}[0-9])",
        )
        .expect("static regex"),
        // Phone numbers, 7 to 15 digits with the usual separators:
        //  - international (+CC... or 00CC...);
        //  - national with a trunk 0 (most of Europe: 040-123 4567,
        //    06 12 34 56 78, 030 1234567);
        //  - North American (555) 123-4567, 555-123-4567, 555.123.4567,
        //    555 123 4567;
        //  - nine digits in threes without a trunk prefix (Spain, Portugal,
        //    Poland, the Czech Republic: 612 345 678);
        //  - eight digits in pairs or 3-2-3 (Denmark, Norway: 12 34 56 78,
        //    412 34 567).
        // Bare digit runs without any of these shapes are not phones: they
        // are times, counts and amounts. Dates and amounts that take a
        // phone's shape are dropped in `phone_ok`.
        phone: Regex::new(
            r"(?x)
            (?:\+|\b00)[1-9][0-9]{0,2}(?:[\ \-.]?\(?[0-9]{1,4}\)?){2,6}\b
            | \(?\b0[0-9]{1,4}\)?(?:[\ \-.]?[0-9]{2,4}){2,4}\b
            | (?:\(\b[2-9][0-9]{2}\)\ ?|\b[2-9][0-9]{2}[\ \-.])[0-9]{3}[\ \-.][0-9]{4}\b
            | \b[2-9][0-9]{2}[\ \-][0-9]{3}[\ \-][0-9]{3}\b
            | \b[2-9][0-9](?:\ [0-9]{2}){3}\b
            | \b[2-9][0-9]{2}\ [0-9]{2}\ [0-9]{3}\b",
        )
        .expect("static regex"),
        // Street addresses:
        //  - English: a house number, up to three capitalised words and a
        //    street type (221B Baker Street);
        //  - a compound word ending in a street type, then a number
        //    (Finnish, Swedish, German, Dutch, Danish, Norwegian:
        //    Mannerheimintie 12, Drottninggatan 5, Hauptstraße 5,
        //    Keizersgracht 123, Vesterbrogade 20, Storgata 1);
        //  - the street type as its own word after the name, then a
        //    number (Karl Johans gate 22, Berliner Str. 5, Václavské
        //    náměstí 1);
        //  - the street type first and a capitalised name (French,
        //    Spanish, Portuguese, Italian, Polish, Czech: rue de la Paix,
        //    Calle Mayor 5, Avenida da Liberdade 110, Piazza Navona,
        //    ul. Marszałkowska 10), with a house number before or after;
        //  - the same with words that are also ordinary words (via, corso,
        //    place, route, al.) only with a house number (Via Roma 12).
        address: Regex::new(
            r"(?x)
            \b[0-9]{1,5}[A-Za-z]?,?\s+(?:[A-Z][\p{L}'\-]+\s+){0,3}
              (?:Street|St|Road|Rd|Avenue|Ave|Lane|Ln|Drive|Dr|Boulevard|Blvd|Way|Court|Ct|Place|Pl|
                 Square|Sq|Terrace|Close|Crescent|Parade|Row|Quay|Park|Gardens|Hill|Green|Walk|Mews)\b\.?
            |
            \b(?:\p{Lu}\p{L}+\s+){0,2}\p{Lu}\p{L}+
              (?:katu|tie|kuja|polku|väylä|raitti|tori|aukio|rinne|kaari
                |gatan|vägen|gata|väg|gränd|torget|torg|backen|stigen
                |straße|strasse|str\.|gasse|allee|platz|damm|ufer
                |laan|straat|weg|plein|gracht|kade|singel|dijk|steeg
                |gade|vej|vænget|stræde|plads
                |gaten|veien|vegen|plassen)
              \s+[0-9]{1,5}[A-Za-z]?(?:\s*[A-Z]\s*[0-9]{1,3})?\b
            |
            \b(?:\p{Lu}[\p{L}'\-]+\s+){1,3}
              (?:gate|gata|vei|veg|gade|vej|allé|plass|plads|straat|laan|Straße|Strasse|Str\.
                |gatan|vägen|náměstí|nábřeží|třída)
              \s+[0-9]{1,5}[A-Za-z]?\b
            |
            (?:\b[0-9]{1,5}[A-Za-z]?,?\s+)?
            (?:\b(?i:rue|chemin|impasse|allée|quai|calle|avenida|avda\.|paseo|carretera|camino|rambla
                    |rua|travessa|praça|viale|piazza|piazzale|vicolo|ulica|ul\.|aleja|plac|náměstí|nám\.)
               |\bavenue|\bboulevard|\bplaza|\bC/)
            \s+(?:(?i:d[eu']|de\s+la|de\s+los|de\s+las|del|da|do|dos|das|di|della|delle|dei|des)\s*)?
            \p{Lu}[\p{L}'\-]+(?:\s+\p{Lu}[\p{L}'\-]+){0,3}(?:,?\s+[0-9]{1,5}[A-Za-z]?\b)?
            |
            (?:\b[0-9]{1,5}[A-Za-z]?,?\s+)?
            \b(?i:via|corso|largo|place|route|cours|ronda|estrada|al\.)
            \s+(?:(?i:d[eu']|de\s+la|del|da|do|dos|das|di|della|des)\s*)?
            \p{Lu}[\p{L}'\-]+(?:\s+\p{Lu}[\p{L}'\-]+){0,3},?\s+[0-9]{1,5}[A-Za-z]?\b
            ",
        )
        .expect("static regex"),
        // Postcodes: UK and Irish Eircodes, Canadian (K1A 0B1), US ZIP+4
        // and a state with its ZIP (CA 94103); and, only next to a
        // capitalised town, five digits (00100 Helsinki, 10115 Berlin),
        // Dutch (1234 AB Amsterdam), Polish (00-950 Warszawa), Portuguese
        // (1000-001 Lisboa), Swedish and Czech (114 55 Stockholm, 110 00
        // Praha).
        postcode: Regex::new(
            r"(?x)
            \b(?:[A-Z]{1,2}[0-9][A-Z0-9]?\s?[0-9][A-Z]{2}
               |[AC-FHKNPRTV-Y][0-9]{2}[0-9W]?\s?[0-9AC-FHKNPRTV-Y]{4}
               |[ABCEGHJ-NPRSTVXY][0-9][ABCEGHJ-NPRSTV-Z]\s?[0-9][ABCEGHJ-NPRSTV-Z][0-9]
               |[0-9]{5}-[0-9]{4}
               |(?:AL|AK|AZ|AR|CA|CO|CT|DE|DC|FL|GA|HI|ID|IL|IN|IA|KS|KY|LA|ME|MD|MA|MI|MN|MS|MO|MT|NE|NV
                  |NH|NJ|NM|NY|NC|ND|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VT|VA|WA|WV|WI|WY)\s+[0-9]{5}(?:-[0-9]{4})?
               |(?:[0-9]{5}|[1-9][0-9]{3}\s?[A-Z]{2}|[0-9]{2}-[0-9]{3}|[1-9][0-9]{3}-[0-9]{3}|[1-9][0-9]{2}\s[0-9]{2})
                \s+\p{Lu}\p{Ll}+)\b",
        )
        .expect("static regex"),
        // A code right after a word for postcode, in the same languages.
        postcode_ctx: Regex::new(
            r"(?x)
            \b(?i:postcode|post\ code|postal\ code|zip\ code|zip|postinumero|postnummer|plz|postleitzahl
                |code\ postal|cap|código\ postal|codigo\ postal|kod\ pocztowy|psč|postcode)
            \s*(?i:is|on|är|er|ist|est|es|é|è|jest|je)?\s*:?\s*
            ([0-9A-Z]{2,5}(?:[\ \-][0-9A-Z]{2,4})?)\b",
        )
        .expect("static regex"),
        // A date in a phone's shape (08.10.2026, 2026-10-08).
        date_like: Regex::new(
            r"^(?:[0-9]{1,2}[./\-][0-9]{1,2}[./\-](?:[0-9]{2}|[0-9]{4})|[0-9]{4}-[0-9]{1,2}-[0-9]{1,2})$",
        )
        .expect("static regex"),
    })
}

/// Whether a phone-shaped match at `[start, end)` of `text` is a phone:
/// 7 to 15 digits, not a date, and not an amount (a currency next to it, or
/// decimals after it: "612 345 678,50 €", "kr 12 34 56 78").
fn phone_ok(text: &str, start: usize, end: usize) -> bool {
    const CURRENCY: [&str; 18] = [
        "€", "$", "£", "kr", "zł", "zl", "kč", "kc", "eur", "usd", "gbp", "sek", "nok", "dkk",
        "pln", "czk", "chf", "euro",
    ];
    let s = &text[start..end];
    let n = s.chars().filter(char::is_ascii_digit).count();
    if !(7..=15).contains(&n) || patterns().date_like.is_match(s.trim()) {
        return false;
    }
    let after = text[end..].trim_start();
    let before = text[..start].trim_end();
    let mut decimals = after.chars();
    if matches!(decimals.next(), Some('.' | ','))
        && decimals.next().is_some_and(|c| c.is_ascii_digit())
    {
        return false;
    }
    let after_l = after.to_lowercase();
    let before_l = before.to_lowercase();
    !CURRENCY.iter().any(|c| {
        let word_after = after_l.strip_prefix(c).is_some_and(|rest| {
            rest.chars().next().is_none_or(|ch| !ch.is_alphanumeric())
                || c.chars().all(|ch| !ch.is_alphanumeric())
        });
        let word_before = before_l.strip_suffix(c).is_some_and(|rest| {
            rest.chars().last().is_none_or(|ch| !ch.is_alphanumeric())
                || c.chars().all(|ch| !ch.is_alphanumeric())
        });
        word_after || word_before
    })
}

fn luhn(digits: &str) -> bool {
    let ds: Vec<u32> = digits.chars().filter_map(|c| c.to_digit(10)).collect();
    if ds.len() < 13 {
        return false;
    }
    let sum: u32 = ds
        .iter()
        .rev()
        .enumerate()
        .map(|(i, &d)| {
            if i % 2 == 1 {
                let x = d * 2;
                if x > 9 {
                    x - 9
                } else {
                    x
                }
            } else {
                d
            }
        })
        .sum();
    sum.is_multiple_of(10)
}

/// Result of redacting one input.
#[derive(Debug, Clone)]
pub struct Redacted {
    pub text: String,
    pub map: PlaceholderMap,
}

/// The redactor. Holds the contact-name source; patterns are static.
pub struct Redactor {
    contacts: Box<dyn ContactNames>,
}

impl Redactor {
    pub fn new(contacts: Box<dyn ContactNames>) -> Redactor {
        Redactor { contacts }
    }

    /// Redacts `text` into a fresh map.
    pub fn redact(&self, text: &str) -> Redacted {
        let mut map = PlaceholderMap::default();
        let text = self.redact_with(text, &mut map);
        Redacted { text, map }
    }

    /// Redacts `text` reusing `map`, so a value seen earlier in the turn
    /// (the utterance) keeps its placeholder in later text (a tool result).
    pub fn redact_with(&self, text: &str, map: &mut PlaceholderMap) -> String {
        let p = patterns();
        let mut out = text.to_owned();
        out = replace(&out, &p.email, PiiKind::Email, map, |_| true);
        out = replace(&out, &p.iban, PiiKind::Account, map, |s| {
            s.chars().filter(char::is_ascii_digit).count() >= 6
        });
        out = replace(&out, &p.card, PiiKind::Account, map, luhn);
        out = replace_group(&out, &p.account_ctx, PiiKind::Account, map);
        out = replace(&out, &p.address, PiiKind::Address, map, |_| true);
        out = replace(&out, &p.postcode, PiiKind::Address, map, |_| true);
        out = replace_group(&out, &p.postcode_ctx, PiiKind::Address, map);
        out = replace_at(&out, &p.phone, PiiKind::Phone, map, phone_ok);
        self.replace_names(&out, map)
    }

    fn replace_names(&self, text: &str, map: &mut PlaceholderMap) -> String {
        let mut names: Vec<String> = Vec::new();
        let contacts = self.contacts.names();
        // A first name only one contact has stands for that contact: it
        // gets the full name's placeholder, so "ring Anna" and the address
        // book's "Anna Virtanen" are visibly the same person to the model
        // (with two placeholders it decided Anna was not in the contacts).
        let mut firsts: HashMap<String, (usize, String)> = HashMap::new();
        for full in &contacts {
            if let Some(first) = full.split_whitespace().next() {
                let e = firsts
                    .entry(first.to_lowercase())
                    .or_insert((0, full.trim().to_owned()));
                e.0 += 1;
            }
        }
        for full in contacts {
            let full = full.trim().to_owned();
            if full.chars().count() < 2 {
                continue;
            }
            // The first name alone also identifies the contact ("ring
            // Anna"), unless it is too short to be distinctive.
            if let Some(first) = full.split_whitespace().next() {
                if first != full && first.chars().count() >= 3 {
                    names.push(first.to_owned());
                }
            }
            names.push(full);
        }
        // Longest first, so "Anna Virtanen" wins over "Anna".
        names.sort_by_key(|n| std::cmp::Reverse(n.chars().count()));
        names.dedup();
        let mut out = text.to_owned();
        for name in names {
            let Ok(re) = Regex::new(&format!(r"(?i)\b{}\b", regex::escape(&name))) else {
                continue;
            };
            // Each occurrence maps to the full name's placeholder when the
            // first name belongs to exactly that contact; otherwise to its
            // own. Either way the original text is what gets restored.
            let stands_for = firsts
                .get(&name.to_lowercase())
                .filter(|(n, full)| *n == 1 && !full.eq_ignore_ascii_case(&name))
                .map(|(_, full)| full.clone());
            out = match stands_for {
                Some(full) => replace_as(&out, &re, PiiKind::Contact, map, &full),
                None => replace(&out, &re, PiiKind::Contact, map, |_| true),
            };
        }
        out
    }
}

/// [`replace`], every match standing for `value` (its placeholder, and
/// what is restored).
fn replace_as(
    text: &str,
    re: &Regex,
    kind: PiiKind,
    map: &mut PlaceholderMap,
    value: &str,
) -> String {
    let mut out = String::with_capacity(text.len());
    let mut last = 0;
    for m in re.find_iter(text) {
        if inside_placeholder(text, m.start(), m.end()) {
            continue;
        }
        let (_, trail) = split_trailing_punct(m.as_str());
        out.push_str(&text[last..m.start()]);
        out.push_str(&map.placeholder(kind, value));
        out.push_str(trail);
        last = m.end();
    }
    out.push_str(&text[last..]);
    out
}

fn replace(
    text: &str,
    re: &Regex,
    kind: PiiKind,
    map: &mut PlaceholderMap,
    accept: impl Fn(&str) -> bool,
) -> String {
    replace_at(text, re, kind, map, |t, start, end| accept(&t[start..end]))
}

/// [`replace`] with `accept` given the whole text and the match's range,
/// for checks that look at what is around it.
fn replace_at(
    text: &str,
    re: &Regex,
    kind: PiiKind,
    map: &mut PlaceholderMap,
    accept: impl Fn(&str, usize, usize) -> bool,
) -> String {
    let mut out = String::with_capacity(text.len());
    let mut last = 0;
    for m in re.find_iter(text) {
        let s = m.as_str();
        if inside_placeholder(text, m.start(), m.end()) || !accept(text, m.start(), m.end()) {
            continue;
        }
        let (core, trail) = split_trailing_punct(s);
        out.push_str(&text[last..m.start()]);
        out.push_str(&map.placeholder(kind, core));
        out.push_str(trail);
        last = m.end();
    }
    out.push_str(&text[last..]);
    out
}

fn replace_group(text: &str, re: &Regex, kind: PiiKind, map: &mut PlaceholderMap) -> String {
    let mut out = String::with_capacity(text.len());
    let mut last = 0;
    for caps in re.captures_iter(text) {
        let Some(g) = caps.get(1) else { continue };
        if inside_placeholder(text, g.start(), g.end()) {
            continue;
        }
        out.push_str(&text[last..g.start()]);
        out.push_str(&map.placeholder(kind, g.as_str().trim()));
        last = g.end();
    }
    out.push_str(&text[last..]);
    out
}

fn split_trailing_punct(s: &str) -> (&str, &str) {
    let core = s.trim_end_matches(['.', ',']);
    // "Dr." and "St." keep their dot.
    if core.len() < s.len() && (core.ends_with("Dr") || core.ends_with("St")) {
        return (s, "");
    }
    (core, &s[core.len()..])
}

/// Whether `[start, end)` overlaps a placeholder already in `text`.
/// The longest text Jev is sent, in characters: routing needs the request,
/// not a whole message.
pub const JEV_MAX_CHARS: usize = 400;

/// Text bound for Jev, which only classifies it (what was asked, whether a
/// notification is worth an interruption), on top of [`Redactor::redact`]:
/// the user's own name, any other capitalised word after the first of a
/// sentence (a name the address book does not know), links and long
/// numbers are replaced, and the text is cut short. With no account,
/// device or network identifier on the request (the relay forwards only
/// the body), what reaches Jev cannot be linked to a person.
///
/// # Panics
///
/// Never: its regular expressions are fixed and valid.
pub fn for_jev(text: &str, own_name: &str) -> String {
    static RES: OnceLock<(Regex, Regex, Regex)> = OnceLock::new();
    let (link, number, word) = RES.get_or_init(|| {
        (
            Regex::new(r"(?i)\b(?:https?://|www\.)\S+").expect("static regex"),
            Regex::new(r"\d(?:[\d\s./-]*\d){4,}").expect("static regex"),
            Regex::new(r"[\p{L}\p{M}][\p{L}\p{M}'’-]*").expect("static regex"),
        )
    });
    let mut out = link.replace_all(text, "<LINK>").into_owned();
    out = number.replace_all(&out, "<NUMBER>").into_owned();
    for part in own_name
        .split_whitespace()
        .filter(|p| p.chars().count() >= 2)
    {
        if let Ok(re) = Regex::new(&format!(r"(?i)\b{}\b", regex::escape(part))) {
            out = re.replace_all(&out, "<NAME>").into_owned();
        }
    }
    let mut cleaned = String::with_capacity(out.len());
    let mut last = 0;
    for m in word.find_iter(&out) {
        let w = m.as_str();
        let capitalised = w.chars().next().is_some_and(char::is_uppercase);
        let acronym = w.chars().count() <= 4 && w.chars().all(|c| !c.is_lowercase());
        let sentence_start = out[..m.start()]
            .trim_end()
            .chars()
            .last()
            .is_none_or(|c| matches!(c, '.' | '!' | '?' | ':' | '\n' | '"' | '“'));
        let keep = !capitalised
            || acronym
            || w == "I"
            || sentence_start
            || inside_placeholder(&out, m.start(), m.end())
            || out[..m.start()].ends_with('<');
        if !keep {
            cleaned.push_str(&out[last..m.start()]);
            cleaned.push_str("<NAME>");
            last = m.end();
        }
    }
    cleaned.push_str(&out[last..]);
    let mut cut: String = cleaned.chars().take(JEV_MAX_CHARS).collect();
    if cut.chars().count() < cleaned.chars().count() {
        cut.push('…');
    }
    cut
}

fn inside_placeholder(text: &str, start: usize, end: usize) -> bool {
    placeholder_re()
        .find_iter(text)
        .any(|p| start < p.end() && p.start() < end)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn redactor() -> Redactor {
        Redactor::new(Box::new(vec![
            "Anna Virtanen".to_owned(),
            "Seán Ó Briain".to_owned(),
            "Bo".to_owned(),
        ]))
    }

    fn red(text: &str) -> Redacted {
        redactor().redact(text)
    }

    #[test]
    fn phones_international_and_national() {
        for t in [
            "call +358 40 123 4567 now",
            "call +44 (0)20 7946 0958 now",
            "call 0044 20 7946 0958 now",
            "call 040-123 4567 now",
            "call (01) 234 5678 now",
            "call 087 123 4567 now",
        ] {
            let r = red(t);
            assert_eq!(r.text, "call <PHONE_1> now", "{t}");
            assert_eq!(r.map.restore(&r.text), t);
        }
    }

    #[test]
    fn times_counts_and_years_are_not_phones() {
        for t in [
            "set a timer for 25 minutes",
            "alarm at 07:30",
            "what happened in 1999",
            "I walked 12000 steps",
            "turn volume to 40",
        ] {
            assert_eq!(red(t).text, t, "{t}");
        }
    }

    #[test]
    fn emails() {
        let r = red("mail anna.v+work@example.co.uk and ANNA.V+WORK@example.co.uk");
        assert_eq!(r.text, "mail <EMAIL_1> and <EMAIL_1>");
        assert_eq!(r.map.len(), 1);
    }

    #[test]
    fn addresses_english_nordic_and_postcodes() {
        let r = red("meet at 221B Baker Street, London NW1 6XE");
        assert_eq!(r.text, "meet at <ADDRESS_1>, London <ADDRESS_2>");
        let r = red("deliver to Mannerheimintie 12 B 7, 00100 Helsinki");
        assert_eq!(r.text, "deliver to <ADDRESS_1>, <ADDRESS_2>");
        let r = red("my Eircode is D02 X285");
        assert_eq!(r.text, "my Eircode is <ADDRESS_1>");
        let r = red("the café on rue de la Paix");
        assert_eq!(r.text, "the café on <ADDRESS_1>");
    }

    #[test]
    fn contact_names_full_and_first() {
        let r = red("remind me to ring Anna when I get home, and tell anna virtanen too");
        assert_eq!(
            r.text, "remind me to ring <CONTACT_1> when I get home, and tell <CONTACT_1> too",
            "a first name only one contact has is that contact"
        );
        assert_eq!(r.map.original("<CONTACT_1>"), Some("anna virtanen"));
        assert_eq!(r.map.len(), 1);
        // Non-ASCII names and word boundaries.
        let r = red("text Seán Ó Briain; Annabel is someone else");
        assert_eq!(r.text, "text <CONTACT_1>; Annabel is someone else");
        // Two-letter names are not redacted as a bare first name, but the
        // full display name still is.
        assert_eq!(red("Bo").text, "<CONTACT_1>");
        assert_eq!(red("a boat").text, "a boat");
    }

    #[test]
    fn account_numbers() {
        let r = red("pay to IBAN FI21 1234 5600 0007 85 today");
        assert_eq!(r.text, "pay to IBAN <ACCOUNT_1> today");
        let r = red("card 4111 1111 1111 1111 expires");
        assert_eq!(r.text, "card <ACCOUNT_1> expires");
        let r = red("my account number is 12345678 and sort code 12-34-56");
        assert_eq!(
            r.text,
            "my account number is <ACCOUNT_1> and sort code <ACCOUNT_2>"
        );
        // Not Luhn-valid, no account keyword: a long number, but not a card.
        assert_eq!(red("order 4111111111111112").text, "order 4111111111111112");
    }

    #[test]
    fn restore_round_trip_and_unknown_placeholders() {
        let r = red("email anna@example.org or call +358401234567 about Anna");
        assert!(!r.text.contains("anna@"));
        assert!(!r.text.contains("358"));
        let reply = format!("I'll email {} and mention <CONTACT_9>.", "<EMAIL_1>");
        assert_eq!(
            r.map.restore(&reply),
            "I'll email anna@example.org and mention <CONTACT_9>."
        );
        assert_eq!(
            r.map.restore(&r.text),
            "email anna@example.org or call +358401234567 about Anna Virtanen"
        );
        // However the model writes a placeholder back.
        assert_eq!(
            r.map
                .restore("to EMAIL_1, [PHONE_1] and {CONTACT_1}; not EMAIL_12"),
            "to anna@example.org, +358401234567 and Anna Virtanen; not EMAIL_12"
        );
    }

    #[test]
    fn restore_json_and_reuse_across_texts() {
        let rd = redactor();
        let mut map = PlaceholderMap::default();
        let a = rd.redact_with("text Anna", &mut map);
        let b = rd.redact_with("Anna replied from +358 40 123 4567", &mut map);
        assert_eq!(a, "text <CONTACT_1>");
        assert_eq!(b, "<CONTACT_1> replied from <PHONE_1>");
        let args = serde_json::json!({"to": "<CONTACT_1>", "body": ["call <PHONE_1>"], "n": 3});
        assert_eq!(
            map.restore_json(&args),
            serde_json::json!({"to": "Anna Virtanen", "body": ["call +358 40 123 4567"], "n": 3})
        );
    }

    #[test]
    fn debug_output_hides_values() {
        let r = red("anna@example.org");
        let dbg = format!("{r:?}");
        assert!(!dbg.contains("anna@example.org"), "{dbg}");
    }

    /// The cases Pilot Lite's JavaScript redactor also runs
    /// (`../redaction-cases.json`), so the two stay the same.
    #[test]
    fn shared_cases() {
        let all: serde_json::Value =
            serde_json::from_str(include_str!("../../redaction-cases.json")).unwrap();
        for c in all["cases"].as_array().unwrap() {
            let names: Vec<String> = c["contacts"]
                .as_array()
                .map(|a| a.iter().map(|n| n.as_str().unwrap().to_owned()).collect())
                .unwrap_or_default();
            let input = c["input"].as_str().unwrap();
            let r = Redactor::new(Box::new(names)).redact(input);
            assert_eq!(r.text, c["output"].as_str().unwrap(), "{input}");
        }
    }

    /// Each input, redacted, is `want`, and restores to itself.
    fn check(cases: &[(&str, &str)]) {
        for (input, want) in cases {
            let r = red(input);
            assert_eq!(r.text, *want, "{input}");
            assert_eq!(r.map.restore(&r.text), *input, "{input}");
        }
    }

    #[test]
    fn phones_north_america() {
        check(&[
            ("call (555) 123-4567 now", "call <PHONE_1> now"),
            ("call 555-123-4567 now", "call <PHONE_1> now"),
            ("call 555.123.4567 now", "call <PHONE_1> now"),
            ("call 555 123 4567 now", "call <PHONE_1> now"),
            ("call +1 (555) 123-4567 now", "call <PHONE_1> now"),
        ]);
    }

    #[test]
    fn phones_european_national_groupings() {
        check(&[
            // Spain, Portugal, Poland, Czech Republic: nine digits in threes.
            ("llama al 612 345 678", "llama al <PHONE_1>"),
            ("ligue 912 345 678", "ligue <PHONE_1>"),
            ("zadzwoń 512-345-678", "zadzwoń <PHONE_1>"),
            ("volejte 601 123 456", "volejte <PHONE_1>"),
            // Denmark, Norway: eight digits.
            ("ring 22 34 56 78", "ring <PHONE_1>"),
            ("ring 412 34 567", "ring <PHONE_1>"),
            // Trunk-0 forms: France, Germany, Netherlands, Sweden, Italy.
            ("appelle 06 12 34 56 78", "appelle <PHONE_1>"),
            ("ruf 0171 1234567 an", "ruf <PHONE_1> an"),
            ("bel 06-12345678", "bel <PHONE_1>"),
            ("ring 070-123 45 67", "ring <PHONE_1>"),
            ("chiama 06 1234 5678", "chiama <PHONE_1>"),
        ]);
    }

    #[test]
    fn addresses_by_language() {
        check(&[
            (
                "vieni in Via Roma 12, grazie",
                "vieni in <ADDRESS_1>, grazie",
            ),
            ("in Piazza Navona", "in <ADDRESS_1>"),
            ("na Rua Augusta 100", "na <ADDRESS_1>"),
            ("Avenida da Liberdade 110", "<ADDRESS_1>"),
            ("en la Calle Mayor 5", "en la <ADDRESS_1>"),
            ("C/ Mayor 5", "<ADDRESS_1>"),
            ("ul. Marszałkowska 10", "<ADDRESS_1>"),
            ("Václavské náměstí 1", "<ADDRESS_1>"),
            ("Keizersgracht 123", "<ADDRESS_1>"),
            ("Drottninggatan 5", "<ADDRESS_1>"),
            ("Mannerheimintie 12", "<ADDRESS_1>"),
            ("Hauptstraße 5", "<ADDRESS_1>"),
            ("Berliner Str. 5", "<ADDRESS_1>"),
            ("12 rue de la Paix", "<ADDRESS_1>"),
            ("Karl Johans gate 22", "<ADDRESS_1>"),
            ("Storgata 1", "<ADDRESS_1>"),
            ("Vesterbrogade 20", "<ADDRESS_1>"),
        ]);
    }

    #[test]
    fn postcodes_by_region() {
        check(&[
            ("1234 AB Amsterdam", "<ADDRESS_1>"),
            ("Ottawa ON K1A 0B1", "Ottawa ON <ADDRESS_1>"),
            ("00-950 Warszawa", "<ADDRESS_1>"),
            ("1000-001 Lisboa", "<ADDRESS_1>"),
            ("114 55 Stockholm", "<ADDRESS_1>"),
            ("110 00 Praha", "<ADDRESS_1>"),
            ("Washington, DC 20500-0003", "Washington, <ADDRESS_1>"),
            ("San Francisco, CA 94103", "San Francisco, <ADDRESS_1>"),
            ("10115 Berlin", "<ADDRESS_1>"),
            ("my zip is 94103", "my zip is <ADDRESS_1>"),
            ("PLZ: 10115", "PLZ: <ADDRESS_1>"),
            ("postinumero 00100", "postinumero <ADDRESS_1>"),
        ]);
    }

    #[test]
    fn account_keywords_by_language() {
        check(&[
            ("Kontonummer: 1234 5678 90", "Kontonummer: <ACCOUNT_1>"),
            ("numer konta 12 3456 7890", "numer konta <ACCOUNT_1>"),
            ("tilinumero on 123456-785", "tilinumero on <ACCOUNT_1>"),
            (
                "numéro de compte 12345678901",
                "numéro de compte <ACCOUNT_1>",
            ),
            (
                "número de cuenta 1234-5678-90",
                "número de cuenta <ACCOUNT_1>",
            ),
            ("rekeningnummer 123456789", "rekeningnummer <ACCOUNT_1>"),
            ("číslo účtu 123456789", "číslo účtu <ACCOUNT_1>"),
            ("conto 123456789", "conto <ACCOUNT_1>"),
            ("asiakasnumero 1234567", "asiakasnumero <ACCOUNT_1>"),
            ("Kundennummer 12345678", "Kundennummer <ACCOUNT_1>"),
            ("konto nr. 1234 1234567890", "konto nr. <ACCOUNT_1>"),
        ]);
    }

    /// Dates, times, prices, versions and counts in many languages stay
    /// as they are.
    #[test]
    fn ordinary_text_is_left_alone() {
        for t in [
            "am 08.10.2026 um 18:30",
            "le 08/10/2026 à 18h30",
            "2026-10-12",
            "klo 18.30 tiistaina 13.10.2026",
            "at 6:30 PM on 10/12/2026",
            "kostar 1 299,00 kr",
            "kostet 1.299,00 €",
            "costs $1,299.99",
            "€ 612 345 678",
            "612 345 678 EUR",
            "1 234 567,89 zł",
            "Sailfish OS 5.0.0.67",
            "version 4.6.0.15 and v1.2.3",
            "Qt 6.11.2",
            "IP 192.168.1.1",
            "set a timer for 25 minutes",
            "I walked 12000 steps",
            "in 2026 the EU",
            "Platform 9",
            "via email 2 days ago",
            "sent via Signal",
        ] {
            assert_eq!(red(t).text, t, "{t}");
        }
    }

    #[test]
    fn placeholder_syntax() {
        assert!(is_placeholder("<CONTACT_1>"));
        assert!(!is_placeholder("<CONTACT_1> x"));
        assert!(!is_placeholder("<NAME_1>"));
    }

    #[test]
    fn jev_text_has_no_names_links_or_long_numbers() {
        assert_eq!(
            for_jev(
                "Remind me to call Siobhan about the Dublin trip",
                "Patrick Quinn"
            ),
            "Remind me to call <NAME> about the <NAME> trip"
        );
        assert_eq!(
            for_jev("Patrick, dinner at 7?", "Patrick Quinn"),
            "<NAME>, dinner at 7?"
        );
        assert_eq!(
            for_jev("Your code is 482913. See https://x.example/t?id=9 now", ""),
            "Your code is <NUMBER>. See <LINK> now"
        );
        // Sentence starts, acronyms, "I" and placeholders stay: routing needs them.
        assert_eq!(
            for_jev(
                "Set a timer for 10 minutes. Turn on the TV, I said <CONTACT_1>",
                ""
            ),
            "Set a timer for 10 minutes. Turn on the TV, I said <CONTACT_1>"
        );
        let long = "word ".repeat(200);
        assert_eq!(for_jev(&long, "").chars().count(), JEV_MAX_CHARS + 1);
    }
}
