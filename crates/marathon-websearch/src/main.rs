//! Pilot's web search on the phone: `POST /v1/search` on 127.0.0.1:8089,
//! `{"query", "limit"?, "fresh"?}` in, `{"items": [{"url", "title",
//! "description"}]}` out, as Shipwright's Pilot relay answers it. Results
//! come from `DuckDuckGo`'s HTML search, each page's text from the page
//! itself, rendered headless in WPE (Pacific's engine) when it needs
//! JavaScript.

mod render;
mod search;

use std::io::Read as _;

use marathon_rt::log;
use serde::Deserialize;

const ADDRESS: &str = "127.0.0.1:8089";
const MAX_BODY: usize = 16 * 1024;
const MAX_QUERY: usize = 1024;

#[derive(Deserialize)]
struct Request {
    query: String,
    #[serde(default = "default_limit")]
    limit: usize,
    #[serde(default)]
    fresh: bool,
}

const fn default_limit() -> usize {
    5
}

fn main() {
    let mut args = std::env::args().skip(1);
    if args.next().as_deref() == Some("render") {
        std::process::exit(render::main(&args.next().unwrap_or_default()));
    }
    let server = match listener()
        .and_then(|l| tiny_http::Server::from_listener(l, None).map_err(std::io::Error::other))
    {
        Ok(s) => s,
        Err(e) => {
            log::warn("websearch", format_args!("cannot listen on {ADDRESS}: {e}"));
            std::process::exit(1);
        }
    };
    for request in server.incoming_requests() {
        std::thread::spawn(move || answer(request));
    }
}

/// systemd's socket (marathon-websearch.socket), else our own.
fn listener() -> std::io::Result<std::net::TcpListener> {
    if std::env::var("LISTEN_PID").ok() == Some(std::process::id().to_string())
        && std::env::var("LISTEN_FDS").ok().as_deref() == Some("1")
    {
        use std::os::fd::FromRawFd as _;
        // SAFETY: systemd passed exactly one socket, as fd 3, to this process.
        return Ok(unsafe { std::net::TcpListener::from_raw_fd(3) });
    }
    std::net::TcpListener::bind(ADDRESS)
}

fn answer(mut request: tiny_http::Request) {
    let (status, body) =
        if request.method() != &tiny_http::Method::Post || request.url() != "/v1/search" {
            (404, error("not found"))
        } else {
            let mut raw = Vec::new();
            let read = request
                .as_reader()
                .take(MAX_BODY as u64 + 1)
                .read_to_end(&mut raw);
            match read
                .ok()
                .filter(|n| *n <= MAX_BODY)
                .and_then(|_| serde_json::from_slice::<Request>(&raw).ok())
            {
                Some(r) if !r.query.trim().is_empty() && r.query.chars().count() <= MAX_QUERY => {
                    let items = search::search(
                        r.query.trim(),
                        r.limit.clamp(1, search::MAX_RESULTS),
                        r.fresh,
                    );
                    (200, serde_json::json!({ "items": items }).to_string())
                }
                _ => (
                    400,
                    error("a JSON body with a query of at most 1024 characters"),
                ),
            }
        };
    let json = tiny_http::Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..]);
    let mut response = tiny_http::Response::from_string(body).with_status_code(status);
    if let Ok(h) = json {
        response.add_header(h);
    }
    if let Err(e) = request.respond(response) {
        log::warn("websearch", format_args!("reply: {e}"));
    }
}

fn error(message: &str) -> String {
    serde_json::json!({ "error": message }).to_string()
}
