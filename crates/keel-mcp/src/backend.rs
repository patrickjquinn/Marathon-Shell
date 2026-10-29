// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! How keel-mcp reaches apps: `org.shipwright.Keel.Actions` on the session
//! bus ([`Bus`]), or anything else implementing [`Backend`] (tests).

use std::fmt;
use std::future::Future;
use std::pin::Pin;
use std::time::Duration;

use serde_json::Value;

pub type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

pub const PATH: &str = "/org/shipwright/Keel/Actions";
pub const INTERFACE: &str = "org.shipwright.Keel.Actions";
const ERROR_PREFIX: &str = "org.shipwright.Keel.Actions.Error.";

/// A failed call.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CallError {
    /// The app answered with `org.shipwright.Keel.Actions.Error.<code>`.
    Keel { code: String, message: String },
    /// The app could not be reached (not installed, crashed, bus error).
    Unreachable(String),
    /// No answer in time.
    Timeout,
}

impl fmt::Display for CallError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Keel { code, message } => write!(f, "{code}: {message}"),
            Self::Unreachable(m) => write!(f, "NotAvailable: the app cannot be reached ({m})"),
            Self::Timeout => f.write_str("Timeout: the app did not answer in time"),
        }
    }
}

pub type CallResult = Result<Value, CallError>;

/// The calls keel-mcp makes on apps.
pub trait Backend: Send + Sync + 'static {
    /// Manifests of running apps that serve Keel Actions (for apps without
    /// an installed manifest, e.g. during development).
    fn running_manifests(&self) -> BoxFuture<'_, Vec<Value>>;
    fn invoke<'a>(
        &'a self,
        app: &'a str,
        action: &'a str,
        arguments: &'a Value,
        user_initiated: bool,
        timeout: Duration,
    ) -> BoxFuture<'a, CallResult>;
    fn get_entity<'a>(
        &'a self,
        app: &'a str,
        ty: &'a str,
        id: &'a str,
    ) -> BoxFuture<'a, CallResult>;
    fn find_entities<'a>(
        &'a self,
        app: &'a str,
        ty: &'a str,
        query: &'a str,
        limit: u32,
    ) -> BoxFuture<'a, CallResult>;
    fn get_context<'a>(&'a self, app: &'a str) -> BoxFuture<'a, CallResult>;
}

/// The session bus.
pub struct Bus {
    connection: zbus::Connection,
    /// What each well-known name answered to `Describe`, by the unique
    /// connection that owned it then: a name is asked again only when its
    /// owner changes (asking every name every probe sent ~170 calls each
    /// time, nearly all to processes that are not Keel apps and answer
    /// with an error, waking them every 10 s).
    described: std::sync::Mutex<std::collections::HashMap<String, (String, Option<Value>)>>,
}

impl Bus {
    pub async fn session() -> zbus::Result<Self> {
        Ok(Self {
            connection: zbus::Connection::session().await?,
            described: std::sync::Mutex::default(),
        })
    }

    /// Why bus activation of `app` would hang, if it would. A sandboxed
    /// app that has not been opened from the app grid yet has no Sailjail
    /// decision on its permissions: activation then waits for a prompt it
    /// has no window to show, until the call times out (60 s and more for
    /// Migrate on the Jolla Phone). Asked only when the app is not running.
    async fn activation_blocked(&self, app: &str) -> Option<CallError> {
        let dbus = zbus::fdo::DBusProxy::new(&self.connection).await.ok()?;
        let name = zbus::names::BusName::try_from(app).ok()?;
        if dbus.name_has_owner(name).await.unwrap_or(true) {
            return None;
        }
        let service =
            std::fs::read_to_string(format!("/usr/share/dbus-1/services/{app}.service")).ok()?;
        let profile = sailjail_profile(&service)?;
        let uid = std::fs::read_to_string("/proc/self/status")
            .ok()
            .and_then(|s| own_uid(&s))?;
        let system = zbus::Connection::system().await.ok()?;
        let reply = system
            .call_method(
                Some("org.sailfishos.sailjaild1"),
                "/org/sailfishos/sailjaild1",
                Some("org.sailfishos.sailjaild1"),
                "GetLaunchAllowed",
                &(uid, profile.as_str()),
            )
            .await
            .ok()?;
        let allowed: i32 = reply.body().deserialize().ok()?;
        launch_refusal(allowed)
    }

    async fn call<B>(&self, app: &str, method: &str, body: &B, timeout: Duration) -> CallResult
    where
        B: serde::Serialize + zbus::DynamicType + Sync,
    {
        let call = self
            .connection
            .call_method(Some(app), PATH, Some(INTERFACE), method, body);
        let reply = match tokio::time::timeout(timeout, call).await {
            Err(_) => return Err(CallError::Timeout),
            Ok(Err(zbus::Error::MethodError(name, message, _))) => {
                let name = name.as_str();
                return Err(match name.strip_prefix(ERROR_PREFIX) {
                    Some(code) => CallError::Keel {
                        code: code.to_owned(),
                        message: message.unwrap_or_default(),
                    },
                    None if name == "org.freedesktop.DBus.Error.NoReply" => CallError::Timeout,
                    None => {
                        CallError::Unreachable(format!("{name}: {}", message.unwrap_or_default()))
                    }
                });
            }
            Ok(Err(zbus::Error::FDO(error))) if matches!(*error, zbus::fdo::Error::NoReply(_)) => {
                return Err(CallError::Timeout);
            }
            Ok(Err(e)) => return Err(CallError::Unreachable(e.to_string())),
            Ok(Ok(reply)) => reply,
        };
        let text: String = reply
            .body()
            .deserialize()
            .map_err(|e| CallError::Unreachable(format!("unexpected reply: {e}")))?;
        serde_json::from_str(&text)
            .map_err(|e| CallError::Unreachable(format!("reply is not JSON: {e}")))
    }
}

/// The Sailjail application a D-Bus service file starts the app under
/// (`Exec=/usr/bin/sailjail -p <name>.desktop ...`), if it is sandboxed.
fn sailjail_profile(service: &str) -> Option<String> {
    let exec = service
        .lines()
        .find_map(|l| l.trim().strip_prefix("Exec="))?;
    let mut words = exec.split_whitespace();
    words.next().filter(|w| w.ends_with("/sailjail"))?;
    while let Some(w) = words.next() {
        if w == "-p" || w == "--profile" {
            let p = words.next()?;
            return Some(p.strip_suffix(".desktop").unwrap_or(p).to_owned());
        }
    }
    None
}

/// The real uid from /proc/self/status.
fn own_uid(status: &str) -> Option<u32> {
    status
        .lines()
        .find_map(|l| l.strip_prefix("Uid:"))?
        .split_whitespace()
        .next()?
        .parse()
        .ok()
}

/// sailjaild's `GetLaunchAllowed`: 1 allowed; 0 not decided yet (never
/// opened); anything else refused.
fn launch_refusal(allowed: i32) -> Option<CallError> {
    match allowed {
        1 => None,
        0 => Some(CallError::Keel {
            code: "NotAvailable".into(),
            message: "the app has not been opened yet: open it once from the app grid and allow \
                      what it asks for, then try again"
                .into(),
        }),
        _ => Some(CallError::Keel {
            code: "NotAvailable".into(),
            message: "the app's permissions were declined: allow them in Settings > Apps".into(),
        }),
    }
}

/// D-Bus calls wait at most this long beyond the action's own timeout
/// (activation starts the app first).
const ACTIVATION_SLACK: Duration = Duration::from_secs(15);
const SHORT: Duration = Duration::from_secs(30);

impl Backend for Bus {
    fn running_manifests(&self) -> BoxFuture<'_, Vec<Value>> {
        Box::pin(async move {
            let Ok(dbus) = zbus::fdo::DBusProxy::new(&self.connection).await else {
                return Vec::new();
            };
            let names = dbus.list_names().await.unwrap_or_default();
            let mut out = Vec::new();
            let mut seen = std::collections::HashMap::new();
            for name in names {
                let name = name.as_str();
                // Well-known names only; apps are reverse-DNS.
                if name.starts_with(':')
                    || name.starts_with("org.freedesktop.")
                    || !name.contains('.')
                {
                    continue;
                }
                // The bus daemon answers this itself: no app is woken.
                let Ok(bus_name) = zbus::names::BusName::try_from(name) else {
                    continue;
                };
                let Ok(owner) = dbus.get_name_owner(bus_name).await else {
                    continue;
                };
                let owner = owner.to_string();
                let known = self
                    .described
                    .lock()
                    .ok()
                    .and_then(|d| d.get(name).cloned())
                    .filter(|(o, _)| *o == owner)
                    .map(|(_, m)| m);
                let manifest = match known {
                    Some(m) => m,
                    None => self
                        .call(name, "Describe", &(), Duration::from_millis(500))
                        .await
                        .ok()
                        .filter(|m| m.get("appId").and_then(Value::as_str) == Some(name)),
                };
                if let Some(m) = &manifest {
                    out.push(m.clone());
                }
                seen.insert(name.to_owned(), (owner, manifest));
            }
            // Names that went away are forgotten.
            if let Ok(mut d) = self.described.lock() {
                *d = seen;
            }
            out
        })
    }

    fn invoke<'a>(
        &'a self,
        app: &'a str,
        action: &'a str,
        arguments: &'a Value,
        user_initiated: bool,
        timeout: Duration,
    ) -> BoxFuture<'a, CallResult> {
        Box::pin(async move {
            if let Some(e) = self.activation_blocked(app).await {
                return Err(e);
            }
            let mut options = std::collections::HashMap::new();
            options.insert("userInitiated", zbus::Variant::from(user_initiated));
            self.call(
                app,
                "Invoke",
                &(action, arguments.to_string(), options),
                timeout + ACTIVATION_SLACK,
            )
            .await
        })
    }

    fn get_entity<'a>(
        &'a self,
        app: &'a str,
        ty: &'a str,
        id: &'a str,
    ) -> BoxFuture<'a, CallResult> {
        Box::pin(async move {
            if let Some(e) = self.activation_blocked(app).await {
                return Err(e);
            }
            self.call(app, "GetEntity", &(ty, id), SHORT + ACTIVATION_SLACK)
                .await
        })
    }

    fn find_entities<'a>(
        &'a self,
        app: &'a str,
        ty: &'a str,
        query: &'a str,
        limit: u32,
    ) -> BoxFuture<'a, CallResult> {
        Box::pin(async move {
            if let Some(e) = self.activation_blocked(app).await {
                return Err(e);
            }
            self.call(
                app,
                "FindEntities",
                &(ty, query, limit),
                SHORT + ACTIVATION_SLACK,
            )
            .await
        })
    }

    fn get_context<'a>(&'a self, app: &'a str) -> BoxFuture<'a, CallResult> {
        // Never activates an app for its context: it must be running (and
        // in the foreground, which the app checks).
        Box::pin(async move {
            let dbus = zbus::fdo::DBusProxy::new(&self.connection)
                .await
                .map_err(|e| CallError::Unreachable(e.to_string()))?;
            let name = zbus::names::BusName::try_from(app)
                .map_err(|e| CallError::Unreachable(e.to_string()))?;
            if !dbus.name_has_owner(name).await.unwrap_or(false) {
                return Err(CallError::Keel {
                    code: "NotAvailable".into(),
                    message: "the app is not running".into(),
                });
            }
            self.call(app, "GetContext", &(), SHORT).await
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sandboxed_service_names_its_profile() {
        let svc = "[D-BUS Service]\nName=org.shipwright.shoal-migrate\n\
                   Exec=/usr/bin/sailjail -p shipwright-shoal-migrate.desktop /usr/bin/shipwright-shoal-migrate --keel-actions\n";
        assert_eq!(
            sailjail_profile(svc).as_deref(),
            Some("shipwright-shoal-migrate")
        );
        assert_eq!(
            sailjail_profile("Exec=/usr/bin/shipwright-reef --keel-actions\n"),
            None
        );
    }

    #[test]
    fn uid_from_status() {
        assert_eq!(
            own_uid("Name:\tx\nUid:\t100000\t100000\t100000\t100000\n"),
            Some(100_000)
        );
    }

    #[test]
    fn only_an_allowed_launch_passes() {
        assert_eq!(launch_refusal(1), None);
        assert!(
            matches!(launch_refusal(0), Some(CallError::Keel { code, .. }) if code == "NotAvailable")
        );
        assert!(launch_refusal(2).is_some());
    }
}
