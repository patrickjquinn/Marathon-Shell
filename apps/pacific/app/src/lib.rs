// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! shipwright-pacific: the Pacific browser. Loads the QML UI (installed to
//! /usr/share/shipwright-pacific/qml) on Keel with `Shipwright.Pacific 1.0`
//! from [`bridge`], [`tabs`], [`suggestions`] and [`lists`]; pages render in
//! `Shipwright.Pacific.WebView 1.0` (shoal/pacific/webview).
//!
//! A shared object that is also executable, like the other Shipwright apps
//! (tools/keel-launcher/link_sailfishapp.rs), installed as
//! /usr/bin/shipwright-pacific. Sailjail only starts an ELF binary and
//! leaves no shell in the sandbox, so the engine's environment cannot come
//! from a wrapper script: [`main`] re-execs this binary through the
//! engine's `pacific-env` program first ([`engine_env`]).

pub mod bridge;
pub mod dbus;
pub mod launcher_entry;
pub mod lists;
pub mod models;
pub mod net;
pub mod suggestions;
pub mod tabs;
pub mod time;
pub mod worker;

// The generated Keel Actions manifest (build.rs).
keel::manifest!();

use std::ffi::{c_char, c_int};
use std::path::PathBuf;

use cxx_qt_lib::QString;

const DEFAULT_QML: &str = "/usr/share/shipwright-pacific/qml/shipwright-pacific.qml";

fn usage() -> ! {
    eprintln!(
        "usage: shipwright-pacific [--qml FILE] [--private] [URL...]\n\
         \n\
         --qml FILE   main QML file (default {DEFAULT_QML}, or $PACIFIC_QML)\n\
         URL          pages to open in new tabs\n\
         \n\
         Environment: PACIFIC_DATA, PACIFIC_CACHE, PACIFIC_DOWNLOADS, PACIFIC_SHARE\n\
         (directories), PACIFIC_LOG (error|warn|info|debug)."
    );
    std::process::exit(2)
}

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

/// The program's entry point for the C start code and booster-keel.
#[cfg_attr(not(test), no_mangle)]
pub extern "C" fn main(count: c_int, values: *const *const c_char) -> c_int {
    cache_env();
    engine_env(count, values);
    bridge::keel_main(run)
}

/// Qt's and the engine's caches go in the app's Sailjail cache directory.
/// They were under the application name (~/.cache/shipwright-pacific),
/// which the sandbox keeps in memory only, so every start compiled the QML,
/// the GL pipelines and the EGL shaders again (the shaders' first use
/// pauses scrolling) and, with the private profile's filter store there
/// too, every content filter (24 s of two cores on the Xperia 10 II). Set
/// before `pacific-env`, which keeps a `PACIFIC_EGL_SHADER_CACHE` already set.
fn cache_env() {
    let cache = worker::Dirs::from_env().cache;
    let qml = cache.join("qmlcache");
    let _ = std::fs::create_dir_all(&qml);
    let pipelines = cache.join("qtpipelinecache");
    let mut vars = vec![
        ("QML_DISK_CACHE_PATH", qml),
        ("QSG_RHI_PIPELINE_CACHE_SAVE", pipelines.clone()),
        ("PACIFIC_EGL_SHADER_CACHE", cache.join("egl-shader-cache")),
    ];
    // (Qt warns when the file to load is missing: not before the first save.)
    if pipelines.is_file() {
        vars.push(("QSG_RHI_PIPELINE_CACHE_LOAD", pipelines));
    }
    for (name, path) in vars {
        if std::env::var_os(name).is_none() {
            std::env::set_var(name, path);
        }
    }
}

/// The engine's runtime environment (library path, preloaded shims, WebKit,
/// `GStreamer` and GPU settings) must be in place when the process starts, so
/// that the dynamic loader and the engine's processes see it. Unless
/// `PACIFIC_ENV` says it is applied, exec the engine's `pacific-env`
/// (shoal/pacific/engine/launcher/pacific-env.c) with this binary and its
/// arguments; it sets the environment and execs this binary again. Without
/// the engine installed (host runs under tools/host-run.sh) this returns.
fn engine_env(count: c_int, values: *const *const c_char) {
    use std::ffi::CString;
    const PACIFIC_ENV: &str = "/usr/libexec/pacific/pacific-env";
    if std::env::var_os("PACIFIC_ENV").is_some_and(|v| v == "1")
        || !std::path::Path::new(PACIFIC_ENV).exists()
    {
        return;
    }
    let Ok(exe) = std::env::current_exe() else {
        return;
    };
    let Ok(exe) = CString::new(exe.into_os_string().into_encoded_bytes()) else {
        return;
    };
    let env = CString::new(PACIFIC_ENV).expect("no NUL");
    let mut exec_args: Vec<*const c_char> = vec![env.as_ptr(), exe.as_ptr()];
    for i in 1..usize::try_from(count).unwrap_or(0) {
        // SAFETY: `values` holds `count` valid C strings from the C start code.
        let a = unsafe { *values.add(i) };
        if a.is_null() {
            break;
        }
        exec_args.push(a);
    }
    exec_args.push(std::ptr::null());
    // SAFETY: a NUL-terminated array of valid C strings; execv only returns
    // on failure, when Pacific carries on without the environment.
    unsafe { libc_execv(env.as_ptr(), exec_args.as_ptr()) };
    eprintln!(
        "shipwright-pacific: cannot run {PACIFIC_ENV}: {}",
        std::io::Error::last_os_error()
    );
}

extern "C" {
    #[link_name = "execv"]
    fn libc_execv(path: *const c_char, argv: *const *const c_char) -> c_int;
}

fn run() {
    let level = match std::env::var("PACIFIC_LOG").as_deref() {
        Ok("error") => log::LevelFilter::Error,
        Ok("info") => log::LevelFilter::Info,
        Ok("debug") => log::LevelFilter::Debug,
        _ => log::LevelFilter::Warn,
    };
    if log::set_logger(&LOGGER).is_ok() {
        log::set_max_level(level);
    }
    let mut qml = std::env::var_os("PACIFIC_QML")
        .filter(|v| !v.is_empty())
        .map_or_else(|| PathBuf::from(DEFAULT_QML), PathBuf::from);
    let mut urls = Vec::new();
    let launch_args = bridge::launch_args();
    let mut args = launch_args.iter().skip(1).cloned();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--qml" => qml = args.next().map_or_else(|| usage(), PathBuf::from),
            "--version" => {
                println!("shipwright-pacific {}", env!("CARGO_PKG_VERSION"));
                return;
            }
            "-h" | "--help" => usage(),
            a if a.starts_with('-') => {}
            a => urls.push(a.to_owned()),
        }
    }
    let _ = bridge::STARTUP_URLS.set(dbus::accepted(&urls));
    let qml = std::fs::canonicalize(&qml).unwrap_or_else(|e| {
        eprintln!("shipwright-pacific: cannot open {}: {e}", qml.display());
        std::process::exit(1)
    });
    let dirs = worker::Dirs::from_env();
    // WebKit's own data (cookies, site storage, service workers) and cache
    // go in the app's Sailjail directories, with its profile. The web view
    // put them under the application name (~/.local/share/shipwright-pacific),
    // which the sandbox keeps in memory only: every site's login and stored
    // state went when Pacific closed. Set before Qt starts any thread.
    std::env::set_var("PACIFIC_WEB_DATA", dirs.data.join("web"));
    std::env::set_var("PACIFIC_WEB_CACHE", dirs.cache.join("web"));
    // Qt Quick holds each touch move for the next frame and asks for one to
    // deliver it, so every finger movement redrew the whole window, nothing
    // in it changed or not: on the Xperia 10 II, whose GPU a fling keeps
    // busy, that was 15 window frames a second and ~10% of the GPU. The page
    // takes its touches straight to WebKit anyway.
    if std::env::var_os("QML_NO_TOUCH_COMPRESSION").is_none() {
        std::env::set_var("QML_NO_TOUCH_COMPRESSION", "1");
    }
    let Some(mut app) = bridge::keel_application() else {
        eprintln!("shipwright-pacific: cannot create the Qt application");
        std::process::exit(1)
    };
    app.as_mut()
        .set_application_name(&QString::from("shipwright-pacific"));
    app.as_mut()
        .set_application_version(&QString::from(env!("CARGO_PKG_VERSION")));
    worker::init(dirs);
    if !bridge::qobject::keel_show_main_view(&QString::from(qml.to_string_lossy().as_ref())) {
        eprintln!("shipwright-pacific: could not load {}", qml.display());
        std::process::exit(1);
    }
    let code = app.exec();
    bridge::qobject::keel_destroy_main_view();
    std::process::exit(code);
}
