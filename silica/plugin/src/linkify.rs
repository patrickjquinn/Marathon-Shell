// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! Turns plain text into Qt `StyledText` with links, for `LinkParser`
//! (Sailfish.Silica.private, used by Silica's BSD LinkedLabel.qml).
//! Clean-room; the rules are Keel's own and match Keel 0.1's `LinkedLabel`:
//! at the leftmost position where one matches, in this order,
//!
//! - a URL: `http://`, `https://`, `ftp://` (any case) or `www.`, up to
//!   white space or one of `<>"`; `www.` links get `http://`;
//! - an email address: `local@domain.tld` (`mailto:`);
//! - a phone number: an optional `+`, a digit, at least five of
//!   `0-9 ()-`, and a final digit (`tel:` with only digits and `+`);
//!
//! with trailing `.,;:!?)` left out of the link. A date written with dashes
//! (`2026-10-01`, `01-10-2026`) is not a phone number. Everything else is
//! escaped.
//! With `shorten`, a URL is shown without its scheme and `www.`, and cut to
//! 27 characters and an ellipsis when longer than 30.

#![warn(clippy::indexing_slicing, clippy::string_slice)]

fn escape(s: &str, out: &mut String) {
    for c in s.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            _ => out.push(c),
        }
    }
}

fn at(chars: &[char], i: usize) -> Option<char> {
    chars.get(i).copied()
}

fn collect(chars: &[char], from: usize, to: usize) -> String {
    chars
        .get(from..to)
        .map(|s| s.iter().collect())
        .unwrap_or_default()
}

fn starts_with_ci(chars: &[char], at_index: usize, prefix: &str) -> bool {
    prefix
        .chars()
        .enumerate()
        .all(|(k, p)| at(chars, at_index + k).is_some_and(|c| c.to_ascii_lowercase() == p))
}

/// End (exclusive) of a URL starting at `start`, before trimming.
fn url_at(chars: &[char], start: usize) -> Option<usize> {
    let schemes = ["http://", "https://", "ftp://", "www."];
    let prefix = schemes.iter().find(|s| starts_with_ci(chars, start, s))?;
    let body = start + prefix.chars().count();
    let mut end = body;
    while at(chars, end).is_some_and(|c| !c.is_whitespace() && !matches!(c, '<' | '>' | '"')) {
        end += 1;
    }
    (end > body).then_some(end)
}

fn is_local(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '%' | '+' | '-')
}

fn is_domain(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '.' | '-')
}

fn email_at(chars: &[char], start: usize) -> Option<usize> {
    let mut i = start;
    while at(chars, i).is_some_and(is_local) {
        i += 1;
    }
    if i == start || at(chars, i) != Some('@') {
        return None;
    }
    let domain_start = i + 1;
    let mut domain_end = domain_start;
    while at(chars, domain_end).is_some_and(is_domain) {
        domain_end += 1;
    }
    // The last '.' inside the domain run (not first) followed by 2+ letters.
    let mut best = None;
    for dot in domain_start + 1..domain_end {
        if at(chars, dot) != Some('.') {
            continue;
        }
        let mut j = dot + 1;
        while j < domain_end && at(chars, j).is_some_and(|c| c.is_ascii_alphabetic()) {
            j += 1;
        }
        if j - (dot + 1) >= 2 {
            best = Some(j);
        }
    }
    best
}

fn phone_at(chars: &[char], start: usize) -> Option<usize> {
    let mut i = start;
    if at(chars, i) == Some('+') {
        i += 1;
    }
    if !at(chars, i).is_some_and(|c| c.is_ascii_digit()) {
        return None;
    }
    let first = i;
    let mut end = first + 1;
    while at(chars, end).is_some_and(|c| c.is_ascii_digit() || matches!(c, ' ' | '(' | ')' | '-')) {
        end += 1;
    }
    // Last digit at least six characters after the first digit.
    (first + 6..end)
        .rev()
        .find(|&j| at(chars, j).is_some_and(|c| c.is_ascii_digit()))
        .map(|j| j + 1)
}

/// End (exclusive) of a date written with dashes at `start`: digit groups of
/// 4-2-2, 2-2-4 or 2-2-2 (one- or two-digit day and month), not followed by a
/// digit.
fn dashed_date_at(chars: &[char], start: usize) -> Option<usize> {
    if start > 0 && at(chars, start - 1).is_some_and(|c| c.is_ascii_digit()) {
        return None;
    }
    let mut groups = Vec::new();
    let mut i = start;
    loop {
        let from = i;
        while at(chars, i).is_some_and(|c| c.is_ascii_digit()) {
            i += 1;
        }
        groups.push(i - from);
        if groups.len() == 3 || at(chars, i) != Some('-') {
            break;
        }
        i += 1;
    }
    let shape = match groups.as_slice() {
        [4, m, d] | [d, m, 4 | 2] => (1..=2).contains(m) && (1..=2).contains(d),
        _ => false,
    };
    (shape && !at(chars, i).is_some_and(|c| c.is_ascii_digit())).then_some(i)
}

fn shorten_url(url: &str) -> String {
    let chars: Vec<char> = url.chars().collect();
    let mut from = 0;
    if let Some(p) = url.find("://") {
        let scheme_len = url.get(..p).map_or(0, |s| s.chars().count());
        if scheme_len > 0 && chars.iter().take(scheme_len).all(char::is_ascii_alphabetic) {
            from = scheme_len + 3;
        }
    }
    if starts_with_ci(&chars, from, "www.") {
        from += 4;
    }
    let rest = chars.get(from..).unwrap_or_default();
    if rest.len() > 30 {
        let mut out: String = rest.iter().take(27).collect();
        out.push('…');
        out
    } else {
        rest.iter().collect()
    }
}

#[must_use]
pub fn linkify(text: &str, shorten: bool) -> String {
    let chars: Vec<char> = text.chars().collect();
    let mut out = String::new();
    let mut plain_start = 0;
    let mut pos = 0;
    while pos < chars.len() {
        if let Some(end) = dashed_date_at(&chars, pos) {
            pos = end;
            continue;
        }
        let found = url_at(&chars, pos)
            .map(|e| (e, 0))
            .or_else(|| email_at(&chars, pos).map(|e| (e, 1)))
            .or_else(|| phone_at(&chars, pos).map(|e| (e, 2)));
        let Some((mut end, kind)) = found else {
            pos += 1;
            continue;
        };
        while end > pos
            && at(&chars, end - 1)
                .is_some_and(|c| matches!(c, '.' | ',' | ';' | ':' | '!' | '?' | ')'))
        {
            end -= 1;
        }
        if end == pos {
            pos += 1;
            continue;
        }
        escape(&collect(&chars, plain_start, pos), &mut out);
        let link = collect(&chars, pos, end);
        let href = match kind {
            0 if starts_with_ci(&chars, pos, "www.") => format!("http://{link}"),
            0 => link.clone(),
            1 => format!("mailto:{link}"),
            _ => format!(
                "tel:{}",
                link.chars()
                    .filter(|c| c.is_ascii_digit() || *c == '+')
                    .collect::<String>()
            ),
        };
        let shown = if kind == 0 && shorten {
            shorten_url(&link)
        } else {
            link
        };
        out.push_str("<a href=\"");
        escape(&href, &mut out);
        out.push_str("\">");
        escape(&shown, &mut out);
        out.push_str("</a>");
        pos = end;
        plain_start = end;
    }
    escape(&collect(&chars, plain_start, chars.len()), &mut out);
    out
}

#[cfg(test)]
mod tests {
    use super::linkify;

    #[test]
    fn plain_text_is_escaped() {
        assert_eq!(
            linkify("a < b & \"c\"", false),
            "a &lt; b &amp; &quot;c&quot;"
        );
    }

    #[test]
    fn urls() {
        assert_eq!(
            linkify("see https://example.com/x.", false),
            "see <a href=\"https://example.com/x\">https://example.com/x</a>."
        );
        assert_eq!(
            linkify("www.jolla.com", false),
            "<a href=\"http://www.jolla.com\">www.jolla.com</a>"
        );
    }

    #[test]
    fn shortened_url() {
        // Shown without scheme and "www.": "example.com/a/very/long/path/to/something"
        // is 41 characters, so it is cut to its first 27, "example.com/a/very/long/pat",
        // plus an ellipsis.
        assert_eq!(
            linkify("http://www.example.com/a/very/long/path/to/something", true),
            "<a href=\"http://www.example.com/a/very/long/path/to/something\">example.com/a/very/long/pat…</a>"
        );
        // Short enough: shown whole.
        assert_eq!(
            linkify("https://jolla.com/x", true),
            "<a href=\"https://jolla.com/x\">jolla.com/x</a>"
        );
    }

    #[test]
    fn non_ascii_urls_do_not_panic() {
        // A multi-byte character within the first four bytes after the
        // scheme (byte slicing there used to panic).
        assert_eq!(
            linkify("go http://é€x now", true),
            "go <a href=\"http://é€x\">é€x</a> now"
        );
        assert_eq!(linkify("http://ä", true), "<a href=\"http://ä\">ä</a>");
        let long = "€".repeat(40);
        let shown = "€".repeat(27) + "…";
        assert_eq!(
            linkify(&format!("https://{long}"), true),
            format!("<a href=\"https://{long}\">{shown}</a>")
        );
    }

    #[test]
    fn email_and_phone() {
        assert_eq!(
            linkify("mail ada@example.org, call +358 40 123 4567!", false),
            "mail <a href=\"mailto:ada@example.org\">ada@example.org</a>, call \
             <a href=\"tel:+358401234567\">+358 40 123 4567</a>!"
        );
    }

    #[test]
    fn dates_are_not_phones() {
        assert_eq!(linkify("due 2026-10-01", false), "due 2026-10-01");
        assert_eq!(linkify("due 01-10-2026, ok", false), "due 01-10-2026, ok");
        assert_eq!(linkify("on 1-10-26", false), "on 1-10-26");
        assert_eq!(linkify("2026-10-01 12:30", false), "2026-10-01 12:30");
        // A real number next to a date still links.
        assert_eq!(
            linkify("2026-10-01 call 040 123 4567", false),
            "2026-10-01 call <a href=\"tel:0401234567\">040 123 4567</a>"
        );
    }

    #[test]
    fn short_numbers_are_not_phones() {
        assert_eq!(linkify("room 1234", false), "room 1234");
    }
}
