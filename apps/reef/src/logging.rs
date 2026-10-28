// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

//! A minimal `log` backend: one line per record on stderr, which the
//! journal (or the terminal) collects. `REEF_LOG` sets
//! the level (error, warn, info, debug; default info). Secrets (tokens)
//! are never passed to the log macros. The same small logger lives in
//! reef/devportal and services/licence-service (separate crates).

use log::{Level, LevelFilter, Log, Metadata, Record};

struct StderrLogger {
    level: LevelFilter,
}

impl Log for StderrLogger {
    fn enabled(&self, metadata: &Metadata<'_>) -> bool {
        metadata.level() <= self.level
    }

    fn log(&self, record: &Record<'_>) {
        if self.enabled(record.metadata()) {
            let level = match record.level() {
                Level::Error => "error",
                Level::Warn => "warning",
                Level::Info => "info",
                Level::Debug => "debug",
                Level::Trace => "trace",
            };
            eprintln!("shipwright-reef: {level}: {}", record.args());
        }
    }

    fn flush(&self) {}
}

/// Parses a level name; `None` for anything else.
pub fn parse_level(s: &str) -> Option<LevelFilter> {
    match s.trim().to_ascii_lowercase().as_str() {
        "off" => Some(LevelFilter::Off),
        "error" => Some(LevelFilter::Error),
        "warn" | "warning" => Some(LevelFilter::Warn),
        "info" => Some(LevelFilter::Info),
        "debug" => Some(LevelFilter::Debug),
        "trace" => Some(LevelFilter::Trace),
        _ => None,
    }
}

/// Installs the logger once; later calls are ignored.
pub fn init(level: LevelFilter) {
    // Leaked once per process: the logger lives as long as the program.
    let logger: &'static StderrLogger = Box::leak(Box::new(StderrLogger { level }));
    if log::set_logger(logger).is_ok() {
        log::set_max_level(level);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn levels() {
        assert_eq!(parse_level("Warning"), Some(LevelFilter::Warn));
        assert_eq!(parse_level("debug"), Some(LevelFilter::Debug));
        assert_eq!(parse_level("loud"), None);
    }
}
