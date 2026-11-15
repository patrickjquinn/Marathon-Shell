// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! `org.shipwright.pacific.ui`: how other apps and the shell open links in
//! Pacific, the way sailfish-browser serves `org.sailfishos.browser.ui`.
//!
//! ```text
//! bus name   org.shipwright.pacific.ui
//! object     /ui
//! interface  org.shipwright.pacific.ui
//!   openUrl(as urls)      opens each URL in a new tab and brings Pacific up;
//!                         with none, only brings it up
//! ```
//!
//! `/usr/bin/shipwright-pacific`, the desktop file's command, calls it, so a
//! link tapped elsewhere reaches the running browser, and D-Bus activation
//! has the shell start or thaw it otherwise. While the runner freezes the
//! app the name is let go ([`release`]), so a call activates instead of
//! waiting on a process that cannot answer. Only http(s), file and about
//! URLs are accepted (at most 10 per call).

use std::sync::OnceLock;

use cxx_qt::CxxQtThread;
use cxx_qt_lib::QString;

use crate::bridge::qobject::Pacific;

pub const BUS_NAME: &str = "org.shipwright.pacific.ui";
pub const OBJECT_PATH: &str = "/ui";

/// The URLs from an openUrl call that Pacific will open.
pub fn accepted(urls: &[String]) -> Vec<String> {
    urls.iter()
        .filter_map(|u| {
            let u = u.trim();
            let parsed = url::Url::parse(u).ok()?;
            matches!(parsed.scheme(), "http" | "https" | "file" | "about")
                .then(|| parsed.to_string())
        })
        .take(10)
        .collect()
}

struct Ui {
    thread: CxxQtThread<Pacific>,
}

#[zbus::interface(name = "org.shipwright.pacific.ui")]
impl Ui {
    #[zbus(name = "openUrl")]
    #[allow(
        clippy::needless_pass_by_value,
        reason = "zbus hands the arguments over owned"
    )]
    fn open_url(&self, urls: Vec<String>) {
        let urls = accepted(&urls);
        // Opening the app itself while it runs (Reef's Open, the app grid)
        // is this call with no URL (the desktop file's X-Maemo-Method): it
        // brings the browser up. It did nothing, and Pacific stayed hidden.
        if urls.is_empty() {
            let _ = self.thread.queue(Pacific::raise_requested);
            return;
        }
        for u in urls {
            let _ = self
                .thread
                .queue(move |q| q.open_url_requested(QString::from(u.as_str())));
        }
    }
}

static CONNECTION: OnceLock<zbus::blocking::Connection> = OnceLock::new();

/// Lets go of the bus name (the interface stays served on the connection).
pub fn release() {
    if let Some(c) = CONNECTION.get() {
        if let Err(e) = c.release_name(BUS_NAME) {
            log::warn!("cannot release {BUS_NAME}: {e}");
        }
    }
}

/// Takes the bus name back after [`release`].
pub fn reclaim() {
    if let Some(c) = CONNECTION.get() {
        if let Err(e) = c.request_name(BUS_NAME) {
            log::warn!("cannot take {BUS_NAME} back: {e}");
        }
    }
}

/// Serves the interface on the session bus from a background thread. A
/// second instance (or no bus) only logs.
pub fn serve(thread: CxxQtThread<Pacific>) {
    let spawned = std::thread::Builder::new()
        .name("pacific-dbus".into())
        .spawn(move || {
            let conn = zbus::blocking::connection::Builder::session()
                .and_then(|b| b.name(BUS_NAME))
                .and_then(|b| b.serve_at(OBJECT_PATH, Ui { thread }))
                .and_then(zbus::blocking::connection::Builder::build);
            match conn {
                Ok(c) => {
                    let _ = CONNECTION.set(c);
                }
                Err(e) => log::info!("{BUS_NAME} is not served: {e}"),
            }
        });
    if let Err(e) = spawned {
        log::warn!("cannot start the D-Bus thread: {e}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_safe_urls() {
        let urls = vec![
            "https://example.com/a".to_string(),
            " http://x.example ".into(),
            "javascript:alert(1)".into(),
            "data:text/html,x".into(),
            "file:///home/u/page.html".into(),
            "not a url".into(),
        ];
        assert_eq!(
            accepted(&urls),
            [
                "https://example.com/a",
                "http://x.example/",
                "file:///home/u/page.html"
            ]
        );
        let many: Vec<String> = (0..20).map(|i| format!("https://e/{i}")).collect();
        assert_eq!(accepted(&many).len(), 10);
    }
}
