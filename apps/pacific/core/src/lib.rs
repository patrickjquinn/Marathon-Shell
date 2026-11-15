// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! pacific-core: the Pacific browser without Qt and without the web
//! engine. See `shoal/pacific/README.md` for the whole picture.
//!
//! | Module | What |
//! | --- | --- |
//! | [`db`] | the profile database (SQLite, WAL), or an in-memory one for private tabs |
//! | [`history`], [`frecency`] | visits and the exponential-decay frecency |
//! | [`bookmarks`] | folders, Netscape import and export |
//! | [`suggest`], [`omnibox`], [`search`] | the address bar: ranking, input classification, engines |
//! | [`session`] | tabs, back/forward lists, scroll positions, crash detection |
//! | [`lifecycle`] | which background tabs keep a live web process |
//! | [`blocker`] | ad and tracker blocking on Brave's `adblock` crate |
//! | [`autoconsent`] | cookie-banner rejection (DuckDuckGo autoconsent) |
//! | [`https`] | HTTPS-first with fallback |
//! | [`reader`] | reader mode and reading time |
//! | [`downloads`] | download records, safe names, resumption |
//! | [`site_settings`], [`settings`] | per-site and global settings |
//! | [`privacy`] | clearing data by time range |
//! | [`passwords`] | the Shoal Keys autofill client |
//! | [`agent`] | Pilot's page snapshots and safety rules |

pub mod agent;
pub mod autoconsent;
pub mod blocker;
pub mod bookmarks;
pub mod db;
pub mod downloads;
mod error;
pub mod favicons;
pub mod frecency;
pub mod history;
pub mod https;
pub mod lifecycle;
pub mod omnibox;
pub mod passwords;
pub mod privacy;
pub mod reader;
pub mod search;
pub mod searches;
pub mod session;
pub mod settings;
pub mod site_settings;
pub mod suggest;
pub mod util;

pub use db::Profile;
pub use error::{Error, Result};
