// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Minimal stderr logger. Under systemd, stderr goes to the journal, which
//! adds its own timestamps; the level prefix follows sd-daemon(3) so
//! journald records the priority too.

use log::{Level, LevelFilter, Log, Metadata, Record};

struct Stderr;

impl Log for Stderr {
    fn enabled(&self, metadata: &Metadata<'_>) -> bool {
        metadata.level() <= log::max_level()
    }

    #[allow(clippy::print_stderr, reason = "journald collects stderr")]
    fn log(&self, record: &Record<'_>) {
        if !self.enabled(record.metadata()) {
            return;
        }
        // Only our own crate: dependencies' debug output is noise here.
        if !record.target().starts_with(env!("CARGO_CRATE_NAME")) && record.level() > Level::Warn {
            return;
        }
        eprintln!("{}{}", sd_prefix(record.level()), record.args());
    }

    fn flush(&self) {}
}

fn sd_prefix(level: Level) -> &'static str {
    match level {
        Level::Error => "<3>",
        Level::Warn => "<4>",
        Level::Info => "<6>",
        Level::Debug | Level::Trace => "<7>",
    }
}

fn parse_level(value: Option<&str>) -> LevelFilter {
    match value.map(str::to_ascii_lowercase).as_deref() {
        Some("error") => LevelFilter::Error,
        Some("warn") => LevelFilter::Warn,
        Some("debug") => LevelFilter::Debug,
        Some("trace") => LevelFilter::Trace,
        Some("off") => LevelFilter::Off,
        _ => LevelFilter::Info,
    }
}

pub fn init() {
    let level = parse_level(std::env::var("SHOAL_PILOT_LOG").ok().as_deref());
    if log::set_logger(&Stderr).is_ok() {
        log::set_max_level(level);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn levels() {
        assert_eq!(parse_level(None), LevelFilter::Info);
        assert_eq!(parse_level(Some("DEBUG")), LevelFilter::Debug);
        assert_eq!(parse_level(Some("nonsense")), LevelFilter::Info);
        assert_eq!(sd_prefix(Level::Error), "<3>");
    }
}
