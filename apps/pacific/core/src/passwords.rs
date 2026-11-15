// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Logins from Shoal Keys: Pacific never stores passwords itself.
//!
//! Shoal Keys serves `org.shipwright.Keys.Autofill1` on the bus name
//! `org.shipwright.shoal-keys.Autofill` (shoal/keys/app/src/autofill.rs,
//! where the interface is documented): `Logins(origin)` gives titles and
//! user names only, while the vault is open; `Fill(origin, id)` brings Keys
//! up, where the person unlocks and picks the login to send (an empty id:
//! choose in Keys); `Save(origin, username, password)` asks the person in
//! Keys before storing anything.
//!
//! Every call is started by the person in Pacific (the login bar, the page
//! menu, the save prompt). Pilot never fills passwords: the Keel Actions
//! refuse password and payment fields. Pacific needs the
//! `ShoalKeysAutofill` Sailjail permission, which Keys ships.

use serde::{Deserialize, Serialize};

use crate::util::{js_string, site_of};
use crate::{Error, Result};

pub const BUS_NAME: &str = "org.shipwright.shoal-keys.Autofill";
pub const OBJECT_PATH: &str = "/org/shipwright/Keys/Autofill";
pub const INTERFACE: &str = "org.shipwright.Keys.Autofill1";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Login {
    pub id: String,
    pub title: String,
    pub username: String,
}

#[derive(Clone, PartialEq, Eq, Deserialize)]
pub struct Credentials {
    pub username: String,
    pub password: String,
}

impl std::fmt::Debug for Credentials {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Credentials")
            .field("username", &self.username)
            .field("password", &"<redacted>")
            .finish()
    }
}

/// The origin (`scheme://host[:port]`) of a page URL, for the requests.
pub fn origin_of(url: &str) -> Option<String> {
    let u = url::Url::parse(url).ok()?;
    if !matches!(u.scheme(), "http" | "https") {
        return None;
    }
    Some(u.origin().ascii_serialization())
}

/// The matching rule Keys applies (shoal/keys/app/src/autofill.rs): an
/// entry URL matches a page origin if both are HTTPS with the same
/// registrable domain, or both have the same scheme and host.
pub fn entry_matches(entry_url: &str, origin: &str) -> bool {
    let (Ok(e), Ok(o)) = (url::Url::parse(entry_url), url::Url::parse(origin)) else {
        // Keys stores bare hosts too ("github.com").
        return url::Url::parse(&format!("https://{entry_url}"))
            .is_ok_and(|e| entry_matches(e.as_str(), origin));
    };
    let (Some(eh), Some(oh)) = (e.host_str(), o.host_str()) else {
        return false;
    };
    if e.scheme() == o.scheme() && eh.eq_ignore_ascii_case(oh) {
        return true;
    }
    e.scheme() == "https" && o.scheme() == "https" && site_of(eh) == site_of(oh)
}

/// The Shoal Keys autofill client (session bus).
pub struct KeysClient {
    conn: zbus::blocking::Connection,
}

impl std::fmt::Debug for KeysClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("KeysClient").finish_non_exhaustive()
    }
}

fn map_err(e: &zbus::Error) -> Error {
    let text = e.to_string();
    if text.contains("ServiceUnknown")
        || text.contains("NameHasNoOwner")
        || text.contains("UnknownObject")
        || text.contains("UnknownInterface")
        || text.contains("UnknownMethod")
    {
        Error::Keys("Shoal Keys autofill is not available (install or update Shoal Keys)".into())
    } else if text.contains("Locked") {
        Error::Keys("Shoal Keys is locked".into())
    } else if text.contains("Denied") {
        Error::Keys("declined".into())
    } else {
        Error::Keys(text)
    }
}

impl KeysClient {
    pub fn session() -> Result<Self> {
        Ok(Self {
            conn: zbus::blocking::Connection::session().map_err(|e| map_err(&e))?,
        })
    }

    pub fn with_connection(conn: zbus::blocking::Connection) -> Self {
        Self { conn }
    }

    fn running(&self) -> Result<bool> {
        let dbus = zbus::blocking::fdo::DBusProxy::new(&self.conn).map_err(|e| map_err(&e))?;
        let name =
            zbus::names::BusName::try_from(BUS_NAME).map_err(|e| Error::Keys(e.to_string()))?;
        dbus.name_has_owner(name)
            .map_err(|e| Error::Keys(e.to_string()))
    }

    fn call(
        &self,
        method: &str,
        body: &(impl serde::Serialize + zbus::zvariant::DynamicType),
    ) -> Result<String> {
        let reply = self
            .conn
            .call_method(Some(BUS_NAME), OBJECT_PATH, Some(INTERFACE), method, body)
            .map_err(|e| map_err(&e))?;
        reply
            .body()
            .deserialize::<String>()
            .map_err(|e| Error::Keys(e.to_string()))
    }

    /// Logins for the page at `url` (no secrets), while Keys is running.
    /// Pacific asks on its own whenever a page with a login form loads, so
    /// this must not start Keys: D-Bus activation brought its window up
    /// over the browser (its "New vault" page, on Facebook's front page).
    /// Not running is no logins.
    pub fn logins(&self, url: &str) -> Result<Vec<Login>> {
        let origin = origin_of(url).ok_or_else(|| Error::BadUrl(url.to_owned()))?;
        if !self.running()? {
            return Ok(Vec::new());
        }
        let json = self.call("Logins", &(origin.as_str(),))?;
        let mut v: Vec<Login> = serde_json::from_str(&json)?;
        v.truncate(20);
        Ok(v)
    }

    pub fn fill(&self, url: &str, id: &str) -> Result<Credentials> {
        let origin = origin_of(url).ok_or_else(|| Error::BadUrl(url.to_owned()))?;
        let json = self.call("Fill", &(origin.as_str(), id))?;
        Ok(serde_json::from_str(&json)?)
    }

    pub fn save(&self, url: &str, username: &str, password: &str) -> Result<String> {
        let origin = origin_of(url).ok_or_else(|| Error::BadUrl(url.to_owned()))?;
        self.call("Save", &(origin.as_str(), username, password))
    }
}

/// Script (isolated world, at document end) that reports a submitted
/// login form to the `shipLogin` message handler: `{username, password}`
/// of the form that holds a non-empty password field. Pacific then offers
/// to save it in Shoal Keys; it keeps nothing itself.
pub const WATCH_SUBMIT_JS: &str = r"(function () {
  function user(form, pw) {
    var u = form.querySelector('input[autocomplete=username],input[type=email],input[type=text],input:not([type])');
    return u && u !== pw ? u.value : '';
  }
  document.addEventListener('submit', function (e) {
    var form = e.target;
    if (!form || !form.querySelector) return;
    var pw = form.querySelector('input[type=password]');
    if (!pw || !pw.value) return;
    var ac = (pw.getAttribute('autocomplete') || '').toLowerCase();
    if (ac === 'one-time-code') return;
    window.webkit.messageHandlers.shipLogin.postMessage({ username: user(form, pw), password: pw.value });
  }, true);
})()";

/// Script (isolated world) that reports whether the page has a login
/// form: `{"login": bool, "username": bool}`.
pub const DETECT_LOGIN_JS: &str = r"(function () {
  var pw = document.querySelector('input[type=password]:not([disabled])');
  if (!pw) return JSON.stringify({ login: false, username: false });
  var form = pw.form || document;
  var user = form.querySelector('input[autocomplete=username],input[type=email],input[type=text],input:not([type])');
  return JSON.stringify({ login: true, username: !!user });
})()";

/// Script (isolated world) that fills the first login form with
/// `creds`, firing the input events frameworks listen for. Returns the
/// number of fields filled.
pub fn fill_js(creds: &Credentials) -> String {
    format!(
        r"(function (u, p) {{
  function set(el, v) {{
    var proto = Object.getPrototypeOf(el), d = Object.getOwnPropertyDescriptor(proto, 'value');
    if (d && d.set) d.set.call(el, v); else el.value = v;
    el.dispatchEvent(new Event('input', {{ bubbles: true }}));
    el.dispatchEvent(new Event('change', {{ bubbles: true }}));
  }}
  var pw = document.querySelector('input[type=password]:not([disabled])');
  if (!pw) return 0;
  var form = pw.form || document, n = 0;
  var user = form.querySelector('input[autocomplete=username],input[type=email],input[type=text],input:not([type])');
  if (user && u) {{ set(user, u); n++; }}
  set(pw, p); n++;
  return n;
}})({}, {})",
        js_string(&creds.username),
        js_string(&creds.password)
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn origins_and_matching() {
        assert_eq!(
            origin_of("https://Login.Example.com:8443/a?b").as_deref(),
            Some("https://login.example.com:8443")
        );
        assert_eq!(origin_of("about:blank"), None);
        assert!(entry_matches(
            "https://example.com/login",
            "https://accounts.example.com"
        ));
        assert!(entry_matches("github.com", "https://github.com"));
        assert!(entry_matches("http://router.lan/", "http://router.lan"));
        assert!(!entry_matches(
            "https://example.com/",
            "https://example.org"
        ));
        // No cross-scheme matching for different hosts.
        assert!(!entry_matches(
            "http://example.com/",
            "https://a.example.com"
        ));
        // Public suffixes are not a shared site.
        assert!(!entry_matches(
            "https://alice.github.io/",
            "https://mallory.github.io"
        ));
    }

    #[test]
    fn fill_script_escapes_values() {
        let js = fill_js(&Credentials {
            username: "a\"b".into(),
            password: "p'</script>\u{2028}".into(),
        });
        assert!(js.contains("\"a\\\"b\""));
        assert!(js.contains("\\u2028"));
        assert!(!js.contains('\u{2028}'));
        let dbg = format!(
            "{:?}",
            Credentials {
                username: "u".into(),
                password: "secret".into()
            }
        );
        assert!(!dbg.contains("secret"));
    }

    /// Without Keys running, the automatic lookup finds nothing (and does
    /// not start Keys); a fill, which the person asked for, says plainly
    /// that Keys is missing.
    #[test]
    fn unavailable_keys() {
        if let Ok(c) = KeysClient::session() {
            assert_eq!(c.logins("https://example.com/").unwrap(), Vec::new());
            match c.fill("https://example.com/", "") {
                Err(Error::Keys(m)) => assert!(!m.is_empty()),
                other => panic!("{other:?}"),
            }
        }
        assert!(
            matches!(map_err(&zbus::Error::Failure("org.freedesktop.DBus.Error.ServiceUnknown".into())), Error::Keys(m) if m.contains("not available"))
        );
    }
}
