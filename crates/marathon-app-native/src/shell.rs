//! The shell's services as an app reaches them on the session bus: calls,
//! signals, and the state a client mirrors once the shell lets the app read
//! it.

use std::collections::HashMap;
use std::pin::Pin;
use std::sync::OnceLock;
use std::time::Duration;

use async_io::Timer;
use cxx_qt::{CxxQtThread, CxxQtType, Threading};
use futures_lite::{Stream, StreamExt};
use serde::de::DeserializeOwned;
use serde::Serialize;
use zbus::zvariant::{DynamicType, OwnedValue, Type};
use zbus::{MatchRule, MessageStream};

use marathon_rt::{io, log};

#[cxx_qt::bridge]
mod ffi {
    #[namespace = "marathon::platform"]
    extern "Rust" {
        /// The app this runner hosts, which the shell's permissions name.
        fn set_app_id(id: &str);
    }
}

static APP_ID: OnceLock<String> = OnceLock::new();

fn set_app_id(id: &str) {
    APP_ID.set(id.to_owned()).ok();
}

pub fn app_id() -> &'static str {
    APP_ID.get().map_or("", String::as_str)
}

/// A service's `GetState` and `StateChanged` map.
pub type State = HashMap<String, OwnedValue>;

const SHELL: &str = "org.marathonos.Shell";

/// `org.marathonos.Shell.<name>1` at `/org/marathonos/Shell/<name>`.
#[derive(Clone, Copy)]
pub struct Service(pub &'static str);

pub const PERMISSIONS: Service = Service("Permissions");

impl Service {
    fn path(self) -> String {
        format!("/org/marathonos/Shell/{}", self.0)
    }

    fn interface(self) -> String {
        format!("org.marathonos.Shell.{}1", self.0)
    }

    async fn reply<B>(self, method: &str, body: &B) -> zbus::Result<zbus::Message>
    where
        B: Serialize + DynamicType,
    {
        let bus = io::session_bus().await?;
        bus.call_method(Some(SHELL), self.path().as_str(), Some(self.interface().as_str()), method, body).await
    }

    pub async fn ask<B, R>(self, method: &str, body: &B) -> zbus::Result<R>
    where
        B: Serialize + DynamicType,
        R: DeserializeOwned + Type,
    {
        self.reply(method, body).await?.body().deserialize()
    }

    /// For the invokables QML reads an answer from at once, as the C++
    /// clients did: the GUI thread waits for the shell.
    pub fn ask_now<B, R>(self, method: &str, body: &B) -> Option<R>
    where
        B: Serialize + DynamicType,
        R: DeserializeOwned + Type,
    {
        async_io::block_on(self.ask(method, body))
            .map_err(|e| log::warn(self.0, format_args!("{method}: {e}")))
            .ok()
    }

    /// Calls `method` and logs a refusal; for calls whose answer, if any,
    /// the app does not need.
    pub fn call<B>(self, method: &'static str, body: B)
    where
        B: Serialize + DynamicType + Send + Sync + 'static,
    {
        io::spawn(async move {
            if let Err(e) = self.reply(method, &body).await {
                log::warn(self.0, format_args!("{method}: {e}"));
            }
        });
    }

    /// The bodies of the service's `member` signal.
    pub async fn signals<T>(self, member: &'static str) -> zbus::Result<impl Stream<Item = T>>
    where
        T: DeserializeOwned + Type,
    {
        let rule = MatchRule::builder()
            .msg_type(zbus::message::Type::Signal)
            .sender(SHELL)?
            .path(self.path())?
            .interface(self.interface())?
            .member(member)?
            .build();
        let stream = MessageStream::for_match_rule(rule, &io::session_bus().await?, None).await?;
        Ok(stream.filter_map(|m| m.ok()?.body().deserialize().ok()))
    }
}

/// The shell's `member` (`PermissionGranted` or `PermissionDenied`) for
/// this app's `permission`.
pub async fn answers(member: &'static str, permission: &'static str) -> zbus::Result<impl Stream<Item = ()>> {
    let answers = PERMISSIONS.signals::<(String, String)>(member).await?;
    Ok(answers.filter_map(move |(app, name)| (app == app_id() && name == permission).then_some(())))
}

fn is_access_denied(e: &zbus::Error) -> bool {
    matches!(e, zbus::Error::MethodError(name, _, _) if name.as_str() == "org.freedesktop.DBus.Error.AccessDenied")
}

/// What a client shows: the shell's state, or that it refused the app.
pub enum Update {
    State(State),
    Refused,
}

/// Mirrors `service`'s state into `apply`: `GetState` once the shell lets
/// the app read it, asking for `permission` when refused, then every
/// `StateChanged`, and a refusal when the permission is revoked.
pub fn mirror<T>(qt: CxxQtThread<T>, service: Service, permission: &'static str, apply: fn(Pin<&mut T>, Update))
where
    T: Threading + CxxQtType + 'static,
{
    io::spawn(async move {
        enum Event {
            State(State),
            Granted,
            Denied,
        }
        let (Ok(changes), Ok(grants), Ok(denials)) = (
            service.signals::<State>("StateChanged").await,
            answers("PermissionGranted", permission).await,
            answers("PermissionDenied", permission).await,
        ) else {
            return log::warn(service.0, "no session bus");
        };
        let events = changes.map(Event::State).or(grants.map(|()| Event::Granted)).or(denials.map(|()| Event::Denied));
        let mut events = std::pin::pin!(events);
        let queue = |update: Update| {
            qt.queue(move |obj| apply(obj, update)).ok();
        };
        let mut asked = false;
        refresh(service, permission, &mut asked, &queue).await;
        while let Some(event) = events.next().await {
            match event {
                Event::State(state) => queue(Update::State(state)),
                Event::Granted => refresh(service, permission, &mut asked, &queue).await,
                Event::Denied => queue(Update::Refused),
            }
        }
    });
}

/// `GetState` once the app holds `permission`; retried while the shell starts.
async fn refresh(service: Service, permission: &'static str, asked: &mut bool, queue: &impl Fn(Update)) {
    for attempt in 0..40u32 {
        let read = match allowed(permission, asked).await {
            Ok(false) => return,
            Ok(true) => service.ask::<_, State>("GetState", &()).await,
            Err(e) => Err(e),
        };
        match read {
            Ok(state) => return queue(Update::State(state)),
            Err(e) if is_access_denied(&e) => return,
            Err(e) if attempt == 39 => return log::warn(service.0, format_args!("GetState: {e}")),
            Err(_) => {
                Timer::after(Duration::from_millis(250 << (attempt / 8).min(3))).await;
            }
        }
    }
}

/// Whether the app holds `permission`; the first time a client finds it
/// does not, it asks the shell, which answers with `PermissionGranted` or
/// `PermissionDenied`.
pub async fn allowed(permission: &'static str, asked: &mut bool) -> zbus::Result<bool> {
    let held = PERMISSIONS.ask::<_, bool>("HasPermission", &(app_id(), permission)).await?;
    if !held && !std::mem::replace(asked, true) {
        PERMISSIONS.call("RequestPermission", (app_id().to_owned(), permission.to_owned()));
    }
    Ok(held)
}

/// Forwards each `member` signal of `service` to `emit` on the GUI thread.
pub fn relay<T, A>(qt: CxxQtThread<T>, service: Service, member: &'static str, emit: fn(Pin<&mut T>, A))
where
    T: Threading + CxxQtType + 'static,
    A: DeserializeOwned + Type + Send + 'static,
{
    io::spawn(async move {
        let Ok(signals) = service.signals::<A>(member).await else {
            return log::warn(service.0, format_args!("no {member}"));
        };
        let mut signals = std::pin::pin!(signals);
        while let Some(args) = signals.next().await {
            qt.queue(move |obj| emit(obj, args)).ok();
        }
    });
}

/// A state entry as the property's type; absent or of another type, the
/// type's default, as `QVariant::to*` gave.
pub fn get<T: Field>(state: &State, key: &str) -> T {
    state.get(key).and_then(T::from_value).unwrap_or_default()
}

pub trait Field: Default + Sized {
    fn from_value(value: &OwnedValue) -> Option<Self>;
}

macro_rules! numeric {
    ($($t:ty),*) => {$(
        impl Field for $t {
            fn from_value(value: &OwnedValue) -> Option<Self> {
                crate::variant::number(value).and_then(|n| <$t>::try_from(n).ok())
            }
        }
    )*};
}
numeric!(i32, u32, i64);

impl Field for f64 {
    #[allow(clippy::cast_precision_loss, reason = "QVariant::toDouble does the same")]
    fn from_value(value: &OwnedValue) -> Option<Self> {
        f64::try_from(value).ok().or_else(|| crate::variant::number(value).map(|n| n as f64))
    }
}

impl Field for bool {
    fn from_value(value: &OwnedValue) -> Option<Self> {
        bool::try_from(value).ok()
    }
}

impl Field for cxx_qt_lib::QString {
    fn from_value(value: &OwnedValue) -> Option<Self> {
        <&str>::try_from(value).ok().map(Self::from)
    }
}

impl Field for cxx_qt_lib::QVariant {
    fn from_value(value: &OwnedValue) -> Option<Self> {
        Some(crate::variant::to_qt(value))
    }
}

impl Field for cxx_qt_lib::QStringList {
    fn from_value(value: &OwnedValue) -> Option<Self> {
        crate::variant::to_qt(value).value::<cxx_qt_lib::QList<cxx_qt_lib::QVariant>>().map(|list| {
            let strings: cxx_qt_lib::QList<cxx_qt_lib::QString> =
                list.iter().filter_map(cxx_qt_lib::QVariant::value::<cxx_qt_lib::QString>).collect();
            Self::from(&strings)
        })
    }
}

impl Field for cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant> {
    fn from_value(value: &OwnedValue) -> Option<Self> {
        crate::variant::to_qt(value).value()
    }
}

impl Field for cxx_qt_lib::QList<cxx_qt_lib::QVariant> {
    fn from_value(value: &OwnedValue) -> Option<Self> {
        crate::variant::to_qt(value).value()
    }
}

/// A QML argument as D-Bus sends it.
pub trait Arg {
    type Wire: Serialize + DynamicType + Into<zbus::zvariant::Value<'static>> + Send + Sync + 'static;
    fn wire(self) -> Self::Wire;
}

impl Arg for &cxx_qt_lib::QStringList {
    type Wire = Vec<String>;
    fn wire(self) -> Vec<String> {
        cxx_qt_lib::QList::<cxx_qt_lib::QString>::from(self).iter().map(ToString::to_string).collect()
    }
}

impl Arg for &cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant> {
    type Wire = HashMap<String, zbus::zvariant::Value<'static>>;
    fn wire(self) -> Self::Wire {
        crate::variant::map(self)
    }
}

impl Arg for &cxx_qt_lib::QString {
    type Wire = String;
    fn wire(self) -> String {
        self.to_string()
    }
}

macro_rules! plain {
    ($($t:ty),*) => {$(
        impl Arg for $t {
            type Wire = $t;
            fn wire(self) -> $t {
                self
            }
        }
    )*};
}
plain!(bool, i32, u32, f64);

/// Invokables that only call the shell: `name(args) => "Method";`, and
/// with `mut` the property setters, which cxx-qt gives a pinned `self`.
macro_rules! calls {
    ($service:expr; mut $($name:ident($($arg:ident: $ty:ty),*) => $method:literal;)*) => {$(
        fn $name(self: std::pin::Pin<&mut Self>, $($arg: $ty),*) {
            $service.call($method, ($(crate::shell::Arg::wire($arg),)*));
        }
    )*};
    ($service:expr; $($name:ident($($arg:ident: $ty:ty),*) => $method:literal;)*) => {$(
        fn $name(&self, $($arg: $ty),*) {
            $service.call($method, ($(crate::shell::Arg::wire($arg),)*));
        }
    )*};
}
pub(crate) use calls;

/// Invokables QML reads an answer from at once: `name(args) -> T => "Method";`,
/// the type's default when the shell does not answer.
macro_rules! asks {
    ($service:expr; $($name:ident($($arg:ident: $ty:ty),*) -> $ret:ty => $method:literal;)*) => {$(
        fn $name(&self, $($arg: $ty),*) -> $ret {
            $service.ask_now::<_, $ret>($method, &($(crate::shell::Arg::wire($arg),)*)).unwrap_or_default()
        }
    )*};
}
pub(crate) use asks;
