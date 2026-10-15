// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! `pilotd`, the Pilot assistant daemon (docs/specs/pilot.md). The binary
//! in `main.rs` is a thin shell over [`daemon`]; everything else is a
//! library so the integration tests drive the real pipeline.

pub mod adapters;
pub mod calibrate;
pub mod config;
pub mod daemon;
pub mod dbus;
pub mod direct;
pub mod events;
pub mod intents;
pub mod jev;
pub mod lang;
pub mod llm;
pub mod localtime;
pub mod logger;
pub mod mcp;
pub mod memory;
pub mod now;
pub mod onscreen;
pub mod photo;
pub mod pipeline;
pub mod privacy;
pub mod privilege;
pub mod redact;
pub mod relay_auth;
pub mod remote;
pub mod route;
pub mod schema;
pub mod settings;
pub mod store;
pub mod system_tools;
pub mod tools;
pub mod triage;
pub mod voice_models;
pub mod weather;
pub mod web;
