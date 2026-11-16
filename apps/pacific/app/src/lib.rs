// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! shipwright-pacific: the Pacific browser's QML module `Shipwright.Pacific
//! 1.0` (the `Pacific` singleton from [`bridge`], the models from [`tabs`],
//! [`suggestions`] and [`lists`]), a plugin that marathon-app-runner loads
//! with the UI in `/usr/share/marathon-apps/shipwright-pacific`. Pages render
//! in `Shipwright.Pacific.WebView 1.0` (apps/pacific/webview).

pub mod bridge;
pub mod dbus;
pub mod launcher_entry;
pub mod lists;
pub mod models;
pub mod net;
pub mod plugin_entry;
pub mod suggestions;
pub mod tabs;
pub mod time;
pub mod worker;

struct Logger;

static LOGGER: Logger = Logger;

impl log::Log for Logger {
    fn enabled(&self, m: &log::Metadata<'_>) -> bool {
        m.level() <= log::max_level()
            && !m.target().starts_with("zbus")
            && !m.target().starts_with("rustls")
            // The HTML parser's notes on pages' markup (reader mode reads
            // any page) are not Pacific's warnings.
            && !m.target().starts_with("html5ever")
            && !m.target().starts_with("markup5ever")
    }
    fn log(&self, r: &log::Record<'_>) {
        if self.enabled(r.metadata()) {
            eprintln!("pacific [{}] {}", r.level(), r.args());
        }
    }
    fn flush(&self) {}
}

// When the QML engine loads the plugin for the UI's first import: before
// any web view exists, so WebKit and the web processes it starts read the
// environment set here.
#[used]
#[link_section = ".init_array"]
static LOADED: extern "C" fn() = loaded;

extern "C" fn loaded() {
    let level = match std::env::var("PACIFIC_LOG").as_deref() {
        Ok("error") => log::LevelFilter::Error,
        Ok("info") => log::LevelFilter::Info,
        Ok("debug") => log::LevelFilter::Debug,
        _ => log::LevelFilter::Warn,
    };
    if log::set_logger(&LOGGER).is_ok() {
        log::set_max_level(level);
    }
    let dirs = worker::Dirs::from_env();
    std::env::set_var("PACIFIC_WEB_DATA", dirs.data.join("web"));
    std::env::set_var("PACIFIC_WEB_CACHE", dirs.cache.join("web"));
    let driver = std::fs::read_link("/sys/class/drm/renderD128/device/driver").ok();
    let mem_kib = std::fs::read_to_string("/proc/meminfo")
        .ok()
        .and_then(|m| mem_total_kib(&m));
    for (name, value) in engine_tuning(
        driver.as_ref().and_then(|d| d.file_name()?.to_str()),
        mem_kib,
    ) {
        std::env::set_var(name, value);
    }
}

fn mem_total_kib(meminfo: &str) -> Option<u64> {
    meminfo
        .lines()
        .find_map(|l| l.strip_prefix("MemTotal:"))?
        .split_whitespace()
        .next()?
        .parse()
        .ok()
}

/// The engine settings that depend on the phone (the rest are the
/// manifest's `environment`). GLES2-class GPUs (the Librem 5's etnaviv, the
/// Pinephone's lima) paint pages faster with Skia on the CPU, with no low-resolution
/// tiles and 512 px tiles; phones with 7 GiB or more keep more in memory
/// and prewarm a web process.
fn engine_tuning(driver: Option<&str>, mem_kib: Option<u64>) -> Vec<(&'static str, &'static str)> {
    let mut v = Vec::new();
    if matches!(driver, Some("etnaviv" | "lima")) {
        v.extend([
            ("WEBKIT_SKIA_ENABLE_CPU_RENDERING", "1"),
            ("WEBKIT_LOWRES_TILE_SCALE", "1.0"),
            ("WEBKIT_LAYERS_TILE_SIZE", "512"),
        ]);
    }
    if mem_kib.unwrap_or(0) >= 7 * 1024 * 1024 {
        v.extend([
            ("WEBKIT_MEMORY_BASE_THRESHOLD_MB", "4000"),
            ("WEBKIT_PROCESS_PREWARM", "1"),
        ]);
    } else {
        v.push(("WEBKIT_MEMORY_BASE_THRESHOLD_MB", "700"));
    }
    v
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tunes_for_the_phone() {
        assert_eq!(
            mem_total_kib("MemTotal:  7912344 kB\nMemFree: 1 kB\n"),
            Some(7_912_344)
        );
        let etnaviv = engine_tuning(Some("etnaviv"), Some(3_000_000));
        assert!(etnaviv.contains(&("WEBKIT_SKIA_ENABLE_CPU_RENDERING", "1")));
        assert!(etnaviv.contains(&("WEBKIT_MEMORY_BASE_THRESHOLD_MB", "700")));
        let big = engine_tuning(Some("panfrost"), Some(11_000_000));
        assert_eq!(
            big,
            [
                ("WEBKIT_MEMORY_BASE_THRESHOLD_MB", "4000"),
                ("WEBKIT_PROCESS_PREWARM", "1")
            ]
        );
    }
}
