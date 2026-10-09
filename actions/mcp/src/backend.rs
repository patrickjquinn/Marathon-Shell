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
}

impl Bus {
    pub async fn session() -> zbus::Result<Self> {
        Ok(Self {
            connection: zbus::Connection::session().await?,
        })
    }

    async fn call<B>(&self, app: &str, method: &str, body: &B, timeout: Duration) -> CallResult
    where
        B: serde::Serialize + zbus::zvariant::DynamicType + Sync,
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
            for name in names {
                let name = name.as_str();
                // Well-known names only; apps are reverse-DNS.
                if name.starts_with(':')
                    || name.starts_with("org.freedesktop.")
                    || !name.contains('.')
                {
                    continue;
                }
                if let Ok(manifest) = self
                    .call(name, "Describe", &(), Duration::from_millis(500))
                    .await
                {
                    if manifest.get("appId").and_then(Value::as_str) == Some(name) {
                        out.push(manifest);
                    }
                }
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
            let mut options = std::collections::HashMap::new();
            options.insert("userInitiated", zbus::zvariant::Value::from(user_initiated));
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
