// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! Keel Actions for Rust apps (ADR-0018, `docs/specs/pilot.md` section 9).
//!
//! ```ignore
//! #[keel::action(
//!     name = "notes.search",
//!     description = "Search notes by text. Returns up to `limit` matches.",
//!     read_only = true
//! )]
//! async fn search(#[keel(max_length = 256)] query: String, limit: Option<u32>) -> keel::Result<Vec<NoteRef>> {
//!     ...
//! }
//!
//! #[keel::entity(type = "note", title = "Note")]
//! #[derive(serde::Serialize)]
//! struct Note { id: String, title: String, #[keel(summarisable)] created: String }
//!
//! impl keel::EntitySource for Note {
//!     fn get(id: &str) -> keel::Result<Option<Self>> { ... }
//!     fn find(query: &str, limit: u32) -> keel::Result<Vec<Self>> { ... }
//! }
//!
//! keel::manifest!(); // the generated actions.json, from build.rs
//! ```
//!
//! `#[keel::action]` keys: `name` and `description` (required), `title`,
//! `read_only`, `destructive`, `idempotent`, `open_world`, `confirm`,
//! `sensitive`, `timeout_ms`, `not_destructive_because`. `#[keel(...)]` on a
//! parameter or field: `max_length`, `min_length`, `max_items`, `minimum`,
//! `maximum`, `pattern`, `format`, `description`, `title`, `entity`,
//! `values`, `summarisable`, `indexable`.
//!
//! The macros register each function in a link-time table; the
//! `Keel.Actions` runtime (C++, in the app's process) finds the table
//! through the C functions in [`ffi`] and calls it after validating the
//! arguments against the generated schema. Synchronous actions run on the
//! calling (GUI) thread; `async` ones on a worker thread, so their futures
//! must be `Send`.

use std::fmt;
use std::future::Future;
use std::marker::PhantomData;
use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Poll, Wake, Waker};

use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::Value;

pub use keel_macros::{action, entity, object};

pub mod ffi;

#[doc(hidden)]
pub mod __private {
    pub use inventory;
    pub use serde;
    pub use serde::Deserialize;
    pub use serde_json::{from_value, to_value, Value};
}

/// The error codes of `org.shipwright.Keel.Actions.Error.*`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum ErrorCode {
    UnknownAction,
    InvalidArguments,
    Failed,
    Timeout,
    NotAvailable,
    Cancelled,
}

impl ErrorCode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::UnknownAction => "UnknownAction",
            Self::InvalidArguments => "InvalidArguments",
            Self::Failed => "Failed",
            Self::Timeout => "Timeout",
            Self::NotAvailable => "NotAvailable",
            Self::Cancelled => "Cancelled",
        }
    }
}

/// An action's failure, as the caller sees it.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Error {
    pub code: ErrorCode,
    pub message: String,
}

impl Error {
    pub fn new(code: ErrorCode, message: impl fmt::Display) -> Self {
        Self {
            code,
            message: message.to_string(),
        }
    }
    pub fn failed(message: impl fmt::Display) -> Self {
        Self::new(ErrorCode::Failed, message)
    }
    pub fn invalid_arguments(message: impl fmt::Display) -> Self {
        Self::new(ErrorCode::InvalidArguments, message)
    }
    pub fn not_available(message: impl fmt::Display) -> Self {
        Self::new(ErrorCode::NotAvailable, message)
    }
    pub fn cancelled(message: impl fmt::Display) -> Self {
        Self::new(ErrorCode::Cancelled, message)
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}: {}", self.code.as_str(), self.message)
    }
}

impl std::error::Error for Error {}

pub type Result<T> = std::result::Result<T, Error>;

/// What an action function may return: `keel::Result<T>` with a
/// serialisable `T`, or nothing.
pub trait IntoReply {
    fn into_reply(self) -> Result<Value>;
}

impl<T: Serialize> IntoReply for Result<T> {
    fn into_reply(self) -> Result<Value> {
        self.and_then(|v| serde_json::to_value(v).map_err(Error::failed))
    }
}

impl IntoReply for () {
    fn into_reply(self) -> Result<Value> {
        Ok(Value::Object(serde_json::Map::new()))
    }
}

type BoxFuture = Pin<Box<dyn Future<Output = Result<Value>> + Send>>;

/// A started call: answered already, or a future to drive to its answer.
pub enum Invocation {
    Ready(Result<Value>),
    Future(BoxFuture),
}

impl Invocation {
    pub fn ready(result: Result<Value>) -> Self {
        Self::Ready(result)
    }
    pub fn future(future: impl Future<Output = Result<Value>> + Send + 'static) -> Self {
        Self::Future(Box::pin(future))
    }
    /// Waits for the answer on this thread. A panic in the action is a
    /// `Failed` answer.
    pub fn wait(self) -> Result<Value> {
        match self {
            Self::Ready(result) => result,
            Self::Future(future) => {
                std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| block_on(future)))
                    .unwrap_or_else(|_| Err(Error::failed("the action panicked")))
            }
        }
    }
}

/// A function registered by `#[keel::action]`.
pub struct NativeAction {
    pub name: &'static str,
    pub invoke: fn(Value) -> Invocation,
}

/// An entity type registered by `#[keel::entity]`.
pub struct NativeEntity {
    pub type_name: &'static str,
    pub get: fn(&str) -> Result<Option<Value>>,
    pub find: fn(&str, u32) -> Result<Vec<Value>>,
}

/// The generated manifest, registered by [`manifest!`].
pub struct Manifest(pub &'static str);

inventory::collect!(NativeAction);
inventory::collect!(NativeEntity);
inventory::collect!(Manifest);

/// Implemented by `#[keel::entity]`.
pub trait Entity {
    const TYPE: &'static str;
}

/// How the runtime reads entities of a type (implement it for each
/// `#[keel::entity]` struct). `get` answers `None` for an unknown id; `find`
/// returns at most `limit` entities, best matches first.
pub trait EntitySource: Sized + Serialize {
    fn get(id: &str) -> Result<Option<Self>>;
    fn find(query: &str, limit: u32) -> Result<Vec<Self>>;
}

/// Any entity type: for parameters whose type is given with
/// `#[keel(entity = "<app-id>/<type>")]`.
pub enum Any {}

impl Entity for Any {
    const TYPE: &'static str = "";
}

/// A reference to an entity, `keel://<app-id>/<type>/<id>`, as actions take
/// and return them. The runtime has validated the pattern before a function
/// sees one.
pub struct EntityRef<T: Entity = Any> {
    uri: String,
    marker: PhantomData<fn() -> T>,
}

impl<T: Entity> EntityRef<T> {
    /// A reference to `id` of this app (its ID from the manifest).
    pub fn new(id: &str) -> Self {
        Self::from_uri(format!(
            "keel://{}/{}/{}",
            app_id().unwrap_or_default(),
            T::TYPE,
            id
        ))
    }
    pub fn from_uri(uri: String) -> Self {
        Self {
            uri,
            marker: PhantomData,
        }
    }
    pub fn uri(&self) -> &str {
        &self.uri
    }
    /// The last path segment.
    pub fn id(&self) -> &str {
        self.uri.rsplit('/').next().unwrap_or_default()
    }
    /// `<app-id>/<type>`.
    pub fn entity_type(&self) -> Option<&str> {
        let rest = self.uri.strip_prefix("keel://")?;
        Some(&rest[..rest.rfind('/')?])
    }
}

impl<T: Entity> Clone for EntityRef<T> {
    fn clone(&self) -> Self {
        Self::from_uri(self.uri.clone())
    }
}

impl<T: Entity> fmt::Debug for EntityRef<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_tuple("EntityRef").field(&self.uri).finish()
    }
}

impl<T: Entity> PartialEq for EntityRef<T> {
    fn eq(&self, other: &Self) -> bool {
        self.uri == other.uri
    }
}

impl<T: Entity> Serialize for EntityRef<T> {
    fn serialize<S: Serializer>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error> {
        serializer.serialize_str(&self.uri)
    }
}

impl<'de, T: Entity> Deserialize<'de> for EntityRef<T> {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> std::result::Result<Self, D::Error> {
        let uri = String::deserialize(deserializer)?;
        if !uri.starts_with("keel://") {
            return Err(serde::de::Error::custom(
                "an entity reference is a keel:// URI",
            ));
        }
        Ok(Self::from_uri(uri))
    }
}

/// Registers the generated manifest (`$OUT_DIR/actions.json`, written by
/// `keel_actions_codegen` in build.rs), or the file given, so that the
/// runtime enforces the schemas the build generated.
#[macro_export]
macro_rules! manifest {
    () => {
        $crate::manifest!(concat!(env!("OUT_DIR"), "/actions.json"));
    };
    ($path:expr) => {
        $crate::__private::inventory::submit! {
            $crate::Manifest(concat!(include_str!($path), "\0"))
        }
    };
}

/// The registered manifest's text (without the terminating NUL).
pub fn manifest_json() -> Option<&'static str> {
    inventory::iter::<Manifest>
        .into_iter()
        .next()
        .map(|m| m.0.trim_end_matches('\0'))
}

/// The app ID from the registered manifest.
pub fn app_id() -> Option<String> {
    let manifest: Value = serde_json::from_str(manifest_json()?).ok()?;
    manifest.get("appId")?.as_str().map(ToOwned::to_owned)
}

/// The registered action names, sorted.
pub fn action_names() -> Vec<&'static str> {
    let mut names: Vec<_> = inventory::iter::<NativeAction>
        .into_iter()
        .map(|a| a.name)
        .collect();
    names.sort_unstable();
    names
}

/// Starts the action `name` with `args` (already validated by the runtime).
/// A panic in a synchronous action is a `Failed` answer.
pub fn invoke(name: &str, args: Value) -> Option<Invocation> {
    inventory::iter::<NativeAction>
        .into_iter()
        .find(|a| a.name == name)
        .map(|a| {
            std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| (a.invoke)(args)))
                .unwrap_or_else(|_| Invocation::Ready(Err(Error::failed("the action panicked"))))
        })
}

/// The entity type registered as `type_name`.
pub fn entity_source(type_name: &str) -> Option<&'static NativeEntity> {
    inventory::iter::<NativeEntity>
        .into_iter()
        .find(|e| e.type_name == type_name)
}

struct ThreadWaker(std::thread::Thread);

impl Wake for ThreadWaker {
    fn wake(self: Arc<Self>) {
        self.0.unpark();
    }
    fn wake_by_ref(self: &Arc<Self>) {
        self.0.unpark();
    }
}

/// Runs a future to completion on this thread.
pub fn block_on<F: Future>(future: F) -> F::Output {
    let mut future = std::pin::pin!(future);
    let waker = Waker::from(Arc::new(ThreadWaker(std::thread::current())));
    let mut context = Context::from_waker(&waker);
    loop {
        if let Poll::Ready(output) = future.as_mut().poll(&mut context) {
            return output;
        }
        std::thread::park();
    }
}
