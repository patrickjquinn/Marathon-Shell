// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! The C functions the `Keel.Actions` runtime looks up in the app's process
//! (`dl_iterate_phdr` + `dlsym`: booster-keel loads apps `RTLD_LOCAL`).
//!
//! ```c
//! typedef void (*keel_native_done)(void *ctx, int status, const char *json);
//! const char *keel_actions_manifest(void);   // NULL without keel::manifest!()
//! const char *keel_actions_native_list(void); // JSON: {"actions":[..],"entities":[..]}
//! int keel_actions_native_invoke(const char *name, const char *args_json,
//!                                keel_native_done done, void *ctx);
//! int keel_actions_native_entity_get(const char *type, const char *id,
//!                                    keel_native_done done, void *ctx);
//! int keel_actions_native_entity_find(const char *type, const char *query,
//!                                     unsigned limit, keel_native_done done, void *ctx);
//! ```
//!
//! The three calls return 0 when the call was started, -1 when there is no
//! such action or entity type, -2 for unreadable arguments. `done` is then
//! called exactly once: on the calling thread before the function returns
//! (synchronous actions, entity reads) or on a worker thread (`async`
//! actions); the runtime marshals it to the GUI thread. `status` is 0 with
//! the result as `json`, or 1 with `{"code": "...", "message": "..."}`. The
//! strings are valid only during the callback.

use std::ffi::{c_char, c_int, c_uint, c_void, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::OnceLock;

use serde_json::{json, Value};

use crate::{Error, Invocation};

/// The completion callback.
pub type Done = extern "C" fn(ctx: *mut c_void, status: c_int, json: *const c_char);

/// The context pointer, handed to a worker thread. The runtime keeps the
/// object it points to alive until `done` has been called.
struct SendPtr(*mut c_void);
// SAFETY: the pointer is only passed back to `done`, which the runtime
// documents as callable from any thread.
unsafe impl Send for SendPtr {}

fn complete(done: Done, ctx: *mut c_void, result: crate::Result<Value>) {
    let (status, value) = match result {
        Ok(value) => (0, value),
        Err(error) => (
            1,
            json!({ "code": error.code.as_str(), "message": error.message }),
        ),
    };
    // serde_json never writes a NUL byte (it escapes control characters).
    let text = CString::new(value.to_string()).unwrap_or_default();
    done(ctx, status, text.as_ptr());
}

fn guarded<T>(f: impl FnOnce() -> crate::Result<T>) -> crate::Result<T> {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or_else(|_| Err(Error::failed("the action panicked")))
}

/// # Safety
/// `ptr` is NULL or a NUL-terminated string.
unsafe fn text<'a>(ptr: *const c_char) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }
    // SAFETY: the caller guarantees a NUL-terminated string.
    unsafe { CStr::from_ptr(ptr) }.to_str().ok()
}

#[no_mangle]
pub extern "C" fn keel_actions_manifest() -> *const c_char {
    inventory::iter::<crate::Manifest>
        .into_iter()
        .next()
        .map_or(std::ptr::null(), |m| m.0.as_ptr().cast())
}

#[no_mangle]
pub extern "C" fn keel_actions_native_list() -> *const c_char {
    static LIST: OnceLock<CString> = OnceLock::new();
    LIST.get_or_init(|| {
        let mut entities: Vec<_> = inventory::iter::<crate::NativeEntity>
            .into_iter()
            .map(|e| e.type_name)
            .collect();
        entities.sort_unstable();
        let list = json!({ "actions": crate::action_names(), "entities": entities });
        CString::new(list.to_string()).unwrap_or_default()
    })
    .as_ptr()
}

/// # Safety
/// `name` and `args_json` are NUL-terminated strings; `ctx` stays valid
/// until `done` has been called.
#[no_mangle]
pub unsafe extern "C" fn keel_actions_native_invoke(
    name: *const c_char,
    args_json: *const c_char,
    done: Done,
    ctx: *mut c_void,
) -> c_int {
    // SAFETY: forwarded from the caller.
    let (Some(name), Some(args)) = (unsafe { text(name) }, unsafe { text(args_json) }) else {
        return -2;
    };
    let Ok(args) = serde_json::from_str::<Value>(args) else {
        return -2;
    };
    let Some(action) = inventory::iter::<crate::NativeAction>
        .into_iter()
        .find(|a| a.name == name)
    else {
        return -1;
    };
    match guarded(|| Ok((action.invoke)(args))) {
        Ok(Invocation::Ready(result)) => complete(done, ctx, result),
        Ok(Invocation::Future(future)) => {
            let send = SendPtr(ctx);
            let spawned = std::thread::Builder::new()
                .name("keel-action".into())
                .spawn(move || {
                    let send = send;
                    let result = guarded(|| crate::block_on(future));
                    complete(done, send.0, result);
                });
            if let Err(error) = spawned {
                // The closure (and with it the future) was dropped unrun.
                complete(done, ctx, Err(Error::failed(error)));
            }
        }
        Err(error) => complete(done, ctx, Err(error)),
    }
    0
}

/// # Safety
/// As [`keel_actions_native_invoke`].
#[no_mangle]
pub unsafe extern "C" fn keel_actions_native_entity_get(
    type_name: *const c_char,
    id: *const c_char,
    done: Done,
    ctx: *mut c_void,
) -> c_int {
    // SAFETY: forwarded from the caller.
    let (Some(type_name), Some(id)) = (unsafe { text(type_name) }, unsafe { text(id) }) else {
        return -2;
    };
    let Some(source) = crate::entity_source(type_name) else {
        return -1;
    };
    let result = guarded(|| (source.get)(id)).map(|v| v.unwrap_or(Value::Null));
    complete(done, ctx, result);
    0
}

/// # Safety
/// As [`keel_actions_native_invoke`].
#[no_mangle]
pub unsafe extern "C" fn keel_actions_native_entity_find(
    type_name: *const c_char,
    query: *const c_char,
    limit: c_uint,
    done: Done,
    ctx: *mut c_void,
) -> c_int {
    // SAFETY: forwarded from the caller.
    let (Some(type_name), Some(query)) = (unsafe { text(type_name) }, unsafe { text(query) })
    else {
        return -2;
    };
    let Some(source) = crate::entity_source(type_name) else {
        return -1;
    };
    let result = guarded(|| (source.find)(query, limit)).map(Value::Array);
    complete(done, ctx, result);
    0
}
