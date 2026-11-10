// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! Rust actions served by the Keel.Actions runtime (ctest
//! `keel_actions_dbus_native`): a synchronous and an `async` action, a
//! failing one and an entity type.

use serde::Serialize;

keel::manifest!();

#[keel::entity(
    type = "note",
    title = "Note",
    description = "A note kept by the Rust test app."
)]
#[derive(Serialize)]
pub struct Note {
    id: String,
    title: String,
    #[keel(summarisable, max_length = 32)]
    created: String,
    #[keel(max_length = 1000)]
    body: String,
}

fn notes() -> Vec<Note> {
    [
        ("r1", "Rust note", "2026-10-02", "Body one"),
        ("r2", "Second", "2026-10-01", "Body two"),
    ]
    .into_iter()
    .map(|(id, title, created, body)| Note {
        id: id.into(),
        title: title.into(),
        created: created.into(),
        body: body.into(),
    })
    .collect()
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
    name = "math.add",
    description = "Add two whole numbers and return their sum.",
    read_only = true,
    idempotent = true
)]
fn add(#[keel(minimum = 0, maximum = 1000)] a: u32, b: Option<u32>) -> keel::Result<u32> {
    Ok(a + b.unwrap_or(0))
}

#[keel::action(
    name = "notes.titles",
    description = "List the titles of all notes, asynchronously on a worker thread.",
    read_only = true
)]
async fn titles() -> keel::Result<Vec<String>> {
    std::future::ready(()).await;
    Ok(notes().into_iter().map(|n| n.title).collect())
}

#[keel::action(
    name = "notes.fail",
    description = "Always fails with NotAvailable, to test error replies."
)]
fn fail() -> keel::Result<()> {
    Err(keel::Error::not_available("the vault is locked"))
}
