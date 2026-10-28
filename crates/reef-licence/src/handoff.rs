// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Licence hand-off: how a sandboxed app gets its token from Reef.
//!
//! The Reef client keeps tokens in `~/.local/share/shipwright-reef/licences`,
//! which a Sailjail-sandboxed app cannot read. Instead of the user pasting
//! the token, Reef runs a small session-bus service:
//!
//! | | |
//! | --- | --- |
//! | Bus name | [`BUS_NAME`] `org.shipwright.Reef.Licences` (D-Bus activated: `shipwright-reef-licenced`) |
//! | Object | [`OBJECT_PATH`] `/org/shipwright/Reef/Licences` |
//! | Interface | [`INTERFACE`] `org.shipwright.Reef.Licences1` |
//! | Method | `GetLicence(s app_id) -> (s token)` |
//! | Errors | `org.shipwright.Reef.Licences1.Error.NotFound` (no token stored, or it was revoked), `...Error.InvalidAppId` |
//!
//! Sandboxed apps reach it through the Sailjail permission
//! `ShipwrightLicences` (`dbus-user.talk org.shipwright.Reef.Licences`),
//! which the Reef client package installs.
//!
//! # Why the caller is not authenticated
//!
//! Sailjail filters D-Bus per bus name, not per method argument, so any app
//! granted `ShipwrightLicences` can ask for any app id. That is accepted
//! (decision (a) in reef/licence/README.md, "Licence hand-off"): a token is not a
//! secret that protects the user. It is a signed, device-independent bearer
//! credential that unlocks exactly one app, the same string the user could
//! paste, and handing it to another app gains that app nothing (it verifies
//! only its own app id). The residual risk is a sandboxed app that asks for
//! another app's token and uploads it so others can use it unpaid; the
//! licence id in every token lets the service see the sharing and revoke
//! it. Authenticating the caller (`GetConnectionUnixProcessID`, then
//! `/proc/<pid>` or Sailjail's app id) would not remove that risk for
//! unsandboxed processes, which can read the licence directory directly,
//! and depends on Sailjail internals that are not a stable interface.
//!
//! The client below is behind the `handoff-client` feature. Apps call
//! [`fetch`] at start-up when they hold no valid token, verify what comes
//! back exactly as a pasted token, and keep paste-in as the fallback.

/// Well-known bus name of the hand-off service.
pub const BUS_NAME: &str = "org.shipwright.Reef.Licences";
/// Object path of the hand-off service.
pub const OBJECT_PATH: &str = "/org/shipwright/Reef/Licences";
/// Interface name, versioned.
pub const INTERFACE: &str = "org.shipwright.Reef.Licences1";
/// Error name prefix.
pub const ERROR_PREFIX: &str = "org.shipwright.Reef.Licences1.Error";
/// The Sailjail permission (file `ShipwrightLicences.permission`) apps list
/// in their desktop file.
pub const SAILJAIL_PERMISSION: &str = "ShipwrightLicences";

/// Whether `app_id` is a well-formed app id: what tokens allow
/// (`[A-Za-z0-9._-]`, 1 to [`crate::claims::MAX_ID_LEN`] characters, the
/// claims rule) and not starting with a dot, so it is also a safe file name.
pub fn valid_app_id(app_id: &str) -> bool {
    crate::claims::check_id("app", app_id).is_ok() && !app_id.starts_with('.')
}

#[cfg(feature = "handoff-client")]
pub use client::{fetch, fetch_on, HandoffError};

#[cfg(feature = "handoff-client")]
mod client {
    use super::{valid_app_id, BUS_NAME, ERROR_PREFIX, INTERFACE, OBJECT_PATH};
    use std::time::Duration;

    /// How long a start-up fetch may wait, D-Bus activation included.
    pub const TIMEOUT: Duration = Duration::from_secs(5);

    /// Why no token came back.
    #[derive(Debug, Clone, PartialEq, Eq)]
    pub enum HandoffError {
        /// No session bus, Reef not installed, or the sandbox does not allow
        /// the call (the app lacks the `ShipwrightLicences` permission).
        Unavailable(String),
        /// The service refused or failed.
        Failed(String),
    }

    impl std::fmt::Display for HandoffError {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            match self {
                HandoffError::Unavailable(m) => write!(f, "Reef licence service unavailable: {m}"),
                HandoffError::Failed(m) => write!(f, "Reef licence service: {m}"),
            }
        }
    }

    impl std::error::Error for HandoffError {}

    /// Asks Reef on the session bus for `app_id`'s token. `Ok(None)` means
    /// Reef holds none. The token is **not** verified here: verify it as a
    /// pasted one before using or storing it.
    pub fn fetch(app_id: &str) -> Result<Option<String>, HandoffError> {
        let conn = zbus::blocking::connection::Builder::session()
            .map(|b| b.method_timeout(TIMEOUT))
            .and_then(zbus::blocking::connection::Builder::build)
            .map_err(|e| HandoffError::Unavailable(e.to_string()))?;
        fetch_on(&conn, app_id)
    }

    /// [`fetch`] over an existing bus connection (tests, or an app that
    /// already has one).
    pub fn fetch_on(
        conn: &zbus::blocking::Connection,
        app_id: &str,
    ) -> Result<Option<String>, HandoffError> {
        if !valid_app_id(app_id) {
            return Err(HandoffError::Failed(format!("invalid app id {app_id:?}")));
        }
        let reply = conn.call_method(
            Some(BUS_NAME),
            OBJECT_PATH,
            Some(INTERFACE),
            "GetLicence",
            &(app_id,),
        );
        match reply {
            Ok(m) => {
                let token: String = m
                    .body()
                    .deserialize()
                    .map_err(|e| HandoffError::Failed(e.to_string()))?;
                let token = token.trim().to_string();
                Ok((!token.is_empty()).then_some(token))
            }
            Err(zbus::Error::MethodError(name, msg, _)) => {
                let name = name.as_str();
                if name == format!("{ERROR_PREFIX}.NotFound") {
                    Ok(None)
                } else if is_unavailable_error(name) {
                    Err(HandoffError::Unavailable(format!(
                        "{name}: {}",
                        msg.unwrap_or_default()
                    )))
                } else {
                    Err(HandoffError::Failed(format!(
                        "{name}: {}",
                        msg.unwrap_or_default()
                    )))
                }
            }
            Err(e) => Err(HandoffError::Unavailable(e.to_string())),
        }
    }

    /// Errors meaning "nobody to ask": not installed, cannot start, or the
    /// sandbox's D-Bus filter refused the call.
    fn is_unavailable_error(name: &str) -> bool {
        matches!(
            name,
            "org.freedesktop.DBus.Error.ServiceUnknown"
                | "org.freedesktop.DBus.Error.NameHasNoOwner"
                | "org.freedesktop.DBus.Error.Spawn.ChildExited"
                | "org.freedesktop.DBus.Error.Spawn.ExecFailed"
                | "org.freedesktop.DBus.Error.Spawn.ServiceNotFound"
                | "org.freedesktop.DBus.Error.AccessDenied"
                | "org.freedesktop.DBus.Error.NoReply"
                | "org.freedesktop.DBus.Error.Timeout"
                | "org.freedesktop.DBus.Error.TimedOut"
                | "org.freedesktop.DBus.Error.UnknownObject"
                | "org.freedesktop.DBus.Error.UnknownMethod"
                | "org.freedesktop.DBus.Error.UnknownInterface"
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn app_ids() {
        assert!(valid_app_id("shipwright-shoal-mail"));
        assert!(valid_app_id("a.b_c-9"));
        assert!(!valid_app_id(""));
        assert!(!valid_app_id(".hidden"));
        assert!(!valid_app_id("../x"));
        assert!(!valid_app_id("a b"));
        assert!(!valid_app_id(&"a".repeat(129)));
    }
}
