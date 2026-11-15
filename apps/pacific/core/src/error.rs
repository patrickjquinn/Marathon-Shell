// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The one error type of the core.

use std::path::PathBuf;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("database: {0}")]
    Sql(#[from] rusqlite::Error),
    #[error("{}: {source}", path.display())]
    Io {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("JSON: {0}")]
    Json(#[from] serde_json::Error),
    #[error("not a valid address: {0}")]
    BadUrl(String),
    #[error("{0}")]
    Invalid(String),
    #[error("not found: {0}")]
    NotFound(String),
    #[error("filter engine: {0}")]
    Blocker(String),
    #[error("session file: {0}")]
    Session(String),
    #[error("reader mode: {0}")]
    Reader(String),
    #[error("Shoal Keys: {0}")]
    Keys(String),
}

impl Error {
    pub fn io(path: impl Into<PathBuf>, source: std::io::Error) -> Self {
        Self::Io {
            path: path.into(),
            source,
        }
    }
}

pub type Result<T, E = Error> = std::result::Result<T, E>;
