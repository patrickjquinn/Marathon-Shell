//! `WebDAV` over HTTP: PROPFIND, REPORT and GET, and their multistatus
//! answers (RFC 4918, RFC 6578).

use std::time::Duration;

use base64::Engine;
use quick_xml::events::Event;
use quick_xml::Reader;

pub fn agent() -> ureq::Agent {
    ureq::Agent::config_builder()
        .user_agent("Marathon DAV")
        .timeout_global(Some(Duration::from_secs(30)))
        .http_status_as_error(false)
        .allow_non_standard_methods(true)
        .max_redirects(0)
        .build()
        .into()
}

pub fn authorization(kind: &str, username: &str, secret: &str) -> String {
    if kind == "bearer" {
        format!("Bearer {secret}")
    } else {
        format!(
            "Basic {}",
            base64::engine::general_purpose::STANDARD.encode(format!("{username}:{secret}"))
        )
    }
}

/// `href` against the URL it came from.
pub fn resolve(base: &str, href: &str) -> String {
    if href.starts_with("http://") || href.starts_with("https://") {
        return href.to_owned();
    }
    let origin = base.find("://").map_or(0, |i| {
        base[i + 3..].find('/').map_or(base.len(), |j| i + 3 + j)
    });
    if href.starts_with('/') {
        return format!("{}{href}", &base[..origin]);
    }
    let dir = base
        .rfind('/')
        .filter(|&i| i >= origin)
        .map_or_else(|| format!("{base}/"), |i| base[..=i].to_owned());
    format!("{dir}{href}")
}

/// The body of a 2xx answer, following redirects with the same method.
pub fn request(
    agent: &ureq::Agent,
    auth: &str,
    method: &str,
    url: &str,
    depth: Option<&str>,
    body: Option<&str>,
) -> Result<String, String> {
    let mut url = url.to_owned();
    for _ in 0..5 {
        let mut builder = ureq::http::Request::builder()
            .method(method)
            .uri(&url)
            .header("Authorization", auth);
        if let Some(depth) = depth {
            builder = builder.header("Depth", depth);
        }
        let sent = match body {
            Some(xml) => builder
                .header("Content-Type", "application/xml; charset=utf-8")
                .body(xml.to_owned())
                .map(|r| agent.run(r)),
            None => builder.body(()).map(|r| agent.run(r)),
        };
        let mut response = sent
            .map_err(|e| e.to_string())?
            .map_err(|e| e.to_string())?;
        let status = response.status().as_u16();
        if let (300..=399, Some(to)) = (
            status,
            response
                .headers()
                .get("location")
                .and_then(|l| l.to_str().ok()),
        ) {
            url = resolve(&url, to);
            continue;
        }
        let text = response
            .body_mut()
            .read_to_string()
            .map_err(|e| e.to_string())?;
        return if (200..300).contains(&status) {
            Ok(text)
        } else {
            Err(format!("{method} {url}: HTTP {status}"))
        };
    }
    Err(format!("{method} {url}: too many redirects"))
}

#[derive(Default, Debug)]
pub struct Response {
    pub href: String,
    pub gone: bool,
    pub resource_type: Vec<String>,
    pub body: String,
}

#[derive(Default, Debug)]
pub struct Multistatus {
    pub responses: Vec<Response>,
    pub sync_token: String,
    pub principal: String,
    pub addressbook_home: String,
    pub calendar_home: String,
}

fn reference(name: &str) -> Option<char> {
    match name {
        "amp" => Some('&'),
        "lt" => Some('<'),
        "gt" => Some('>'),
        "quot" => Some('"'),
        "apos" => Some('\''),
        _ => {
            let code = name.strip_prefix("#x").map_or_else(
                || name.strip_prefix('#')?.parse().ok(),
                |hex| u32::from_str_radix(hex, 16).ok(),
            )?;
            char::from_u32(code)
        }
    }
}

/// A multistatus answer, by local names: namespaces are not checked.
pub fn multistatus(xml: &str) -> Multistatus {
    let mut out = Multistatus::default();
    let mut reader = Reader::from_str(xml);
    let mut path: Vec<String> = Vec::new();
    let mut text = String::new();
    let mut current = Response::default();
    loop {
        let event = match reader.read_event() {
            Ok(Event::Eof) | Err(_) => break,
            Ok(event) => event,
        };
        let opens = matches!(event, Event::Start(_));
        match event {
            Event::Start(e) | Event::Empty(e)
                if path.last().is_some_and(|p| p == "resourcetype") =>
            {
                current
                    .resource_type
                    .push(e.local_name().as_ref().to_owned());
                if opens {
                    path.push(String::new());
                }
            }
            Event::Start(e) => {
                path.push(e.local_name().as_ref().to_owned());
                text.clear();
            }
            Event::Text(t) => text.push_str(&t),
            Event::CData(t) => text.push_str(&t),
            Event::GeneralRef(r) => text.extend(reference(&r)),
            Event::End(_) => {
                let name = path.pop().unwrap_or_default();
                let parent = path.last().map_or("", String::as_str);
                let value = text.trim().to_owned();
                match (name.as_str(), parent) {
                    ("href", "current-user-principal") => out.principal = value,
                    ("href", "addressbook-home-set") => out.addressbook_home = value,
                    ("href", "calendar-home-set") => out.calendar_home = value,
                    ("href", "response") => current.href = value,
                    ("status", "response") => current.gone = value.contains(" 404"),
                    ("sync-token", _) => out.sync_token = value,
                    ("address-data" | "calendar-data", _) => current.body = value,
                    ("response", _) => out.responses.push(std::mem::take(&mut current)),
                    _ => {}
                }
                text.clear();
            }
            _ => {}
        }
    }
    out
}

pub const PRINCIPAL: &str = r#"<?xml version="1.0" encoding="utf-8" ?><d:propfind xmlns:d="DAV:"><d:prop><d:current-user-principal/></d:prop></d:propfind>"#;
pub const HOMES: &str = r#"<?xml version="1.0" encoding="utf-8" ?><d:propfind xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav" xmlns:cal="urn:ietf:params:xml:ns:caldav"><d:prop><card:addressbook-home-set/><cal:calendar-home-set/></d:prop></d:propfind>"#;
pub const COLLECTIONS: &str = r#"<?xml version="1.0" encoding="utf-8" ?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:displayname/><d:sync-token/></d:prop></d:propfind>"#;

pub fn sync_collection(token: &str) -> String {
    let token = if token.is_empty() {
        "<d:sync-token/>".to_owned()
    } else {
        format!("<d:sync-token>{token}</d:sync-token>")
    };
    format!(
        r#"<?xml version="1.0" encoding="utf-8" ?><d:sync-collection xmlns:d="DAV:">{token}<d:sync-level>1</d:sync-level><d:prop><d:getetag/></d:prop></d:sync-collection>"#
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn relative_hrefs_resolve_against_their_url() {
        assert_eq!(
            resolve("https://dav.example.com/remote.php/dav/", "/principals/me/"),
            "https://dav.example.com/principals/me/"
        );
        assert_eq!(
            resolve("https://dav.example.com/books/", "work/"),
            "https://dav.example.com/books/work/"
        );
        assert_eq!(
            resolve("https://dav.example.com", "books/"),
            "https://dav.example.com/books/"
        );
        assert_eq!(
            resolve("https://a.example/x", "https://b.example/y"),
            "https://b.example/y"
        );
    }

    #[test]
    fn a_multistatus_answer_is_read() {
        let xml = r#"<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
  <d:response><d:href>/books/me/</d:href><d:propstat><d:prop>
    <d:resourcetype><d:collection/><card:addressbook/></d:resourcetype>
    <d:current-user-principal><d:href>/principals/me/</d:href></d:current-user-principal>
  </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
  <d:response><d:href>/books/me/a&amp;b.vcf</d:href><d:status>HTTP/1.1 404 Not Found</d:status></d:response>
  <d:response><d:href>/books/me/c.vcf</d:href><d:propstat><d:prop><card:address-data><![CDATA[BEGIN:VCARD]]></card:address-data></d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat></d:response>
  <d:sync-token>http://example.com/sync/7</d:sync-token>
</d:multistatus>"#;
        let m = multistatus(xml);
        assert_eq!(m.principal, "/principals/me/");
        assert_eq!(m.sync_token, "http://example.com/sync/7");
        assert_eq!(m.responses.len(), 3);
        assert_eq!(m.responses[0].resource_type, ["collection", "addressbook"]);
        assert_eq!(
            (m.responses[1].href.as_str(), m.responses[1].gone),
            ("/books/me/a&b.vcf", true)
        );
        assert_eq!(
            (m.responses[2].body.as_str(), m.responses[2].gone),
            ("BEGIN:VCARD", false)
        );
    }
}
