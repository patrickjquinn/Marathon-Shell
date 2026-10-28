// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! `#[keel::action]` and `#[keel::entity]`: registration, argument decoding,
//! sync and async dispatch, entities, and the C entry points the runtime
//! uses.

use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::sync::mpsc;

use serde::Serialize;
use serde_json::{json, Value};

#[keel::object]
#[derive(Serialize)]
pub struct NoteRef {
    note: keel::EntityRef<Note>,
    #[keel(max_length = 200)]
    title: String,
}

#[keel::entity(
    type = "note",
    title = "Note",
    description = "A note with a title and a body."
)]
#[derive(Serialize)]
pub struct Note {
    id: String,
    title: String,
    #[keel(summarisable, indexable, max_length = 32)]
    created: String,
    #[keel(max_length = 20000)]
    body: String,
}

fn notes() -> Vec<Note> {
    vec![
        Note {
            id: "n1".into(),
            title: "Shopping".into(),
            created: "2026-10-01".into(),
            body: "Milk".into(),
        },
        Note {
            id: "n2".into(),
            title: "Trattoria".into(),
            created: "2026-09-25".into(),
            body: "Friday".into(),
        },
    ]
}

impl keel::EntitySource for Note {
    fn get(id: &str) -> keel::Result<Option<Self>> {
        Ok(notes().into_iter().find(|n| n.id == id))
    }
    fn find(query: &str, limit: u32) -> keel::Result<Vec<Self>> {
        Ok(notes()
            .into_iter()
            .filter(|n| n.title.to_lowercase().contains(&query.to_lowercase()))
            .take(limit as usize)
            .collect())
    }
}

#[keel::action(
    name = "notes.search",
    description = "Search notes by text. Returns up to `limit` matches.",
    read_only = true
)]
async fn search(
    #[keel(max_length = 256)] query: String,
    limit: Option<u32>,
) -> keel::Result<Vec<NoteRef>> {
    // Something to await, as a real action would (I/O, a worker).
    std::future::ready(()).await;
    let found = <Note as keel::EntitySource>::find(&query, limit.unwrap_or(10))?;
    Ok(found
        .into_iter()
        .map(|n| NoteRef {
            note: keel::EntityRef::from_uri(format!("keel://org.example.notes/note/{}", n.id)),
            title: n.title,
        })
        .collect())
}

#[keel::action(
    name = "notes.delete",
    description = "Delete a note permanently; it cannot be restored.",
    destructive = true
)]
fn delete(note: keel::EntityRef<Note>) -> keel::Result<()> {
    if note.id() == "n1" {
        Ok(())
    } else {
        Err(keel::Error::failed(format!("no note {}", note.id())))
    }
}

#[keel::action(
    name = "notes.touch",
    description = "Marks the notes list as seen; has no result."
)]
fn touch() {}

#[keel::action(
    name = "notes.panic",
    description = "Test action that panics, to check the FFI guard."
)]
fn panics() -> keel::Result<u32> {
    panic!("boom")
}

// The manifest the generator writes for this file
// (keel/actions/codegen/tests/golden/rust-notes), and the test stubs it
// writes, which must compile and pass.
keel::manifest!("../../../codegen/tests/golden/rust-notes/actions.json");

// Kept as generated: not reformatted.
#[rustfmt::skip]
#[path = "../../../codegen/tests/golden/rust-notes/keel_actions_tests.rs"]
mod generated_stubs;

#[test]
fn registered_names() {
    assert_eq!(
        keel::action_names(),
        ["notes.delete", "notes.panic", "notes.search", "notes.touch"]
    );
    assert_eq!(keel::app_id().as_deref(), Some("org.example.rustnotes"));
}

#[test]
fn async_action_with_optional_argument() {
    let result = keel::invoke("notes.search", json!({ "query": "shop" }))
        .unwrap()
        .wait()
        .unwrap();
    assert_eq!(
        result,
        json!([{ "note": "keel://org.example.notes/note/n1", "title": "Shopping" }])
    );
}

#[test]
fn sync_action_and_errors() {
    let ok = keel::invoke(
        "notes.delete",
        json!({ "note": "keel://org.example.notes/note/n1" }),
    )
    .unwrap()
    .wait();
    // `()` serialises as null; the runtime answers {} for actions without a
    // result whatever the function returns.
    assert_eq!(ok, Ok(Value::Null));
    let failed = keel::invoke(
        "notes.delete",
        json!({ "note": "keel://org.example.notes/note/n9" }),
    )
    .unwrap()
    .wait()
    .unwrap_err();
    assert_eq!(failed.code, keel::ErrorCode::Failed);
    assert_eq!(
        keel::invoke("notes.touch", json!({})).unwrap().wait(),
        Ok(json!({}))
    );
}

#[test]
fn bad_arguments_are_rejected() {
    for args in [
        json!({}),
        json!({ "query": 5 }),
        json!({ "query": "x", "colour": "red" }),
    ] {
        let error = keel::invoke("notes.search", args)
            .unwrap()
            .wait()
            .unwrap_err();
        assert_eq!(error.code, keel::ErrorCode::InvalidArguments, "{error}");
    }
    let error = keel::invoke("notes.delete", json!({ "note": "n1" }))
        .unwrap()
        .wait()
        .unwrap_err();
    assert_eq!(error.code, keel::ErrorCode::InvalidArguments);
    assert!(keel::invoke("notes.fly", json!({})).is_none());
}

#[test]
fn entity_ref() {
    let r: keel::EntityRef<Note> = keel::EntityRef::new("n2");
    assert_eq!(r.uri(), "keel://org.example.rustnotes/note/n2");
    assert_eq!(r.id(), "n2");
    assert_eq!(r.entity_type(), Some("org.example.rustnotes/note"));
    assert_eq!(<Note as keel::Entity>::TYPE, "note");
}

extern "C" fn record(ctx: *mut c_void, status: c_int, json: *const c_char) {
    // SAFETY: ctx is the boxed Sender call_ffi leaked for this one call, and
    // `done` is called exactly once, so the callback owns it now: dropping
    // it here (not on the test thread) keeps it alive until send returns.
    let sender = unsafe { Box::from_raw(ctx.cast::<mpsc::Sender<(c_int, Value)>>()) };
    // SAFETY: json is NUL-terminated.
    let text = unsafe { CStr::from_ptr(json) }.to_str().unwrap();
    sender
        .send((status, serde_json::from_str(text).unwrap()))
        .unwrap();
}

fn call_ffi(
    start: impl FnOnce(keel::ffi::Done, *mut c_void) -> c_int,
) -> (c_int, Option<(c_int, Value)>) {
    let (sender, receiver) = mpsc::channel();
    let ctx = Box::into_raw(Box::new(sender)).cast::<c_void>();
    let started = start(record, ctx);
    if started != 0 {
        // Not started, so `done` will never run: take the Sender back.
        // SAFETY: ctx came from Box::into_raw above and was not consumed.
        drop(unsafe { Box::from_raw(ctx.cast::<mpsc::Sender<(c_int, Value)>>()) });
    }
    let answer = (started == 0).then(|| receiver.recv().unwrap());
    (started, answer)
}

#[test]
fn ffi_entry_points() {
    let name = CString::new("notes.search").unwrap();
    let args = CString::new(r#"{"query":"tratt"}"#).unwrap();
    let (started, answer) = call_ffi(|done, ctx| unsafe {
        keel::ffi::keel_actions_native_invoke(name.as_ptr(), args.as_ptr(), done, ctx)
    });
    assert_eq!(started, 0);
    assert_eq!(
        answer.unwrap(),
        (
            0,
            json!([{ "note": "keel://org.example.notes/note/n2", "title": "Trattoria" }])
        )
    );

    let name = CString::new("notes.panic").unwrap();
    let args = CString::new("{}").unwrap();
    let (_, answer) = call_ffi(|done, ctx| unsafe {
        keel::ffi::keel_actions_native_invoke(name.as_ptr(), args.as_ptr(), done, ctx)
    });
    assert_eq!(
        answer.unwrap(),
        (
            1,
            json!({ "code": "Failed", "message": "the action panicked" })
        )
    );

    let unknown = CString::new("notes.fly").unwrap();
    let (started, _) = call_ffi(|done, ctx| unsafe {
        keel::ffi::keel_actions_native_invoke(unknown.as_ptr(), args.as_ptr(), done, ctx)
    });
    assert_eq!(started, -1);

    let note = CString::new("note").unwrap();
    let id = CString::new("n1").unwrap();
    let (_, answer) = call_ffi(|done, ctx| unsafe {
        keel::ffi::keel_actions_native_entity_get(note.as_ptr(), id.as_ptr(), done, ctx)
    });
    assert_eq!(answer.unwrap().1["created"], "2026-10-01");

    let query = CString::new("").unwrap();
    let (_, answer) = call_ffi(|done, ctx| unsafe {
        keel::ffi::keel_actions_native_entity_find(note.as_ptr(), query.as_ptr(), 1, done, ctx)
    });
    assert_eq!(answer.unwrap().1.as_array().unwrap().len(), 1);

    let list = unsafe { CStr::from_ptr(keel::ffi::keel_actions_native_list()) };
    let list: Value = serde_json::from_str(list.to_str().unwrap()).unwrap();
    assert_eq!(list["entities"], json!(["note"]));
    let manifest = unsafe { CStr::from_ptr(keel::ffi::keel_actions_manifest()) };
    assert!(manifest.to_str().unwrap().contains("org.example.rustnotes"));
}
