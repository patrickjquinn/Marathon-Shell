//! How a marathon-app-runner starts: its environment and the bubblewrap
//! sandbox around it, for an app or for a warm spare that becomes one.
//!
//! The sandbox sees `/usr`, `/etc` and the system apps read-only, the
//! app's own data, cache and config read-write, the session's runtime dir
//! with the app's own Wayland security-context socket over the shell's,
//! only the GPU's render node, and a tmpfs home. The network goes only to
//! apps with "network", the media folders only to apps with "storage".

use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{LazyLock, Mutex};

use cxx_qt_lib::{QMap, QMapPair_QString_QVariant, QString, QStringList, QVariant};

#[cxx_qt::bridge]
mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
    }

    #[namespace = "marathon::sandbox"]
    extern "Rust" {
        /// The media folders an app with "storage" sees.
        fn shared_folders() -> QStringList;
    }
}

/// One runner to start. A spare has no app id yet.
#[derive(Clone, Debug, Default)]
pub(crate) struct Runner {
    pub app_id: String,
    pub permissions: Vec<String>,
    pub requires_qt: Vec<String>,
    /// A spare that will become an app with "storage".
    pub storage_spare: bool,
    pub wayland_socket: String,
    pub render_node: String,
    /// The GPU stack runs WebGL (ANGLE over GLES).
    pub gpu_webgl: bool,
    pub thumbnails: String,
    pub dpi: f64,
    pub user_scale: f64,
    pub screen_width: i32,
    pub screen_height: i32,
    pub app_width: i32,
    pub app_height: i32,
}

// QtWebEngine's Chromium cannot drive etnaviv's GLES2: software raster, WebGL1 only.
const CHROMIUM_FLAGS: &str =
    "--use-gl=disabled --disable-gpu --ignore-gpu-blocklist --disable-dev-shm-usage \
     --disable-features=Vulkan,UseSkiaRenderer,WebGL2 --num-raster-threads=2 --enable-viewport \
     --main-frame-resizes-are-orientation-changes";
// Stacks whose GL Chromium can drive, so WebGL runs on the GPU.
const GPU_CHROMIUM_FLAGS: &str =
    "--use-gl=angle --use-angle=gles --ignore-gpu-blocklist --disable-dev-shm-usage \
     --num-raster-threads=2 --enable-viewport --main-frame-resizes-are-orientation-changes";

struct App<'a> {
    id: String,
    permissions: Vec<String>,
    runner: &'a Runner,
}

impl App<'_> {
    fn has(&self, permission: &str) -> bool {
        self.permissions.iter().any(|p| p == permission)
    }
}

fn app(runner: &Runner) -> Option<App<'_>> {
    (!runner.app_id.is_empty()).then(|| App {
        id: runner.app_id.clone(),
        permissions: runner.permissions.clone(),
        runner,
    })
}

fn var(name: &str) -> Option<String> {
    env::var(name).ok().filter(|v| !v.is_empty())
}

// An empty value would vanish in the command-line round trip and shift
// every later argument, so empty counts as unset.
fn var_or(name: &str, fallback: &str) -> String {
    var(name).unwrap_or_else(|| fallback.to_owned())
}

use marathon_rt::dirs::home;

use marathon_apps::paths::{system_apps, user_installs};

/// The user installed it; it is not one of Marathon's own apps.
pub(crate) fn is_user_installed(app_id: &str) -> bool {
    !marathon_apps::paths::system_app(app_id)
        .join("manifest.json")
        .exists()
        && marathon_apps::paths::receipt(app_id).exists()
}

/// bubblewrap, or none when apps run unsandboxed.
pub(crate) fn bwrap() -> Option<String> {
    if env::var_os("MARATHON_DISABLE_SANDBOX").is_some() {
        return None;
    }
    let found = env::var_os("PATH")
        .map(|p| {
            env::split_paths(&p)
                .map(|d| d.join("bwrap"))
                .find(|p| p.is_file())
        })
        .unwrap_or_default();
    found.map(|p| p.to_string_lossy().into_owned())
}

#[derive(Default, Clone)]
struct Manifest {
    requires_qt: Vec<String>,
    chromium_flags: String,
}

// Manifests don't change while the shell runs.
fn manifest(app_id: &str) -> Manifest {
    static CACHE: LazyLock<Mutex<HashMap<String, Manifest>>> = LazyLock::new(Mutex::default);
    let mut cache = CACHE.lock().unwrap_or_else(|_| std::process::abort());
    cache
        .entry(app_id.to_owned())
        .or_insert_with(|| {
            let json: serde_json::Value =
                fs::read(system_apps().join(app_id).join("manifest.json"))
                    .ok()
                    .and_then(|b| serde_json::from_slice(&b).ok())
                    .unwrap_or_default();
            Manifest {
                requires_qt: json["requiresQtModules"]
                    .as_array()
                    .map(|a| {
                        a.iter()
                            .filter_map(|v| v.as_str().map(str::to_owned))
                            .collect()
                    })
                    .unwrap_or_default(),
                chromium_flags: json["chromiumFlags"]
                    .as_str()
                    .unwrap_or_default()
                    .trim()
                    .to_owned(),
            }
        })
        .clone()
}

pub(crate) fn uses_webengine(runner: &Runner) -> bool {
    let Some(app) = app(runner) else { return false };
    let mut modules = runner.requires_qt.clone();
    if modules.is_empty() {
        modules = manifest(&app.id).requires_qt;
    }
    modules.iter().any(|m| m == "webengine")
}

fn chromium_flags(app: &App<'_>) -> String {
    var("QTWEBENGINE_CHROMIUM_FLAGS").unwrap_or_else(|| {
        let flags = manifest(&app.id).chromium_flags;
        if !flags.is_empty() {
            flags
        } else if app.runner.gpu_webgl {
            GPU_CHROMIUM_FLAGS.to_owned()
        } else {
            CHROMIUM_FLAGS.to_owned()
        }
    })
}

fn variables(runner: &Runner) -> Vec<(&'static str, String)> {
    let mut vars = vec![
        ("QT_NO_XDG_DESKTOP_PORTAL", "1".to_owned()),
        ("MARATHON_SHELL_PID", std::process::id().to_string()),
        ("MARATHON_DPI", format!("{:.1}", runner.dpi)),
        ("MARATHON_APP_WIDTH", runner.app_width.to_string()),
        ("MARATHON_APP_HEIGHT", runner.app_height.to_string()),
        ("QT_QPA_PLATFORM", "wayland".to_owned()),
        (
            "WAYLAND_DISPLAY",
            var_or("MARATHON_WL_SOCKET_NAME", "marathon-wayland-0"),
        ),
        ("QT_IM_MODULE", "wayland".to_owned()),
        (
            "QSG_ANTIALIASING_METHOD",
            var_or("QSG_ANTIALIASING_METHOD", "vertex"),
        ),
        (
            "MARATHON_LAYER_SAMPLES",
            var_or("MARATHON_LAYER_SAMPLES", "0"),
        ),
        ("MARATHON_GPU_HDR", var_or("MARATHON_GPU_HDR", "0")),
        ("LANG", var_or("LANG", "en_US.UTF-8")),
    ];
    if runner.screen_width > 0 {
        vars.push(("MARATHON_SCREEN_WIDTH", runner.screen_width.to_string()));
        vars.push(("MARATHON_SCREEN_HEIGHT", runner.screen_height.to_string()));
    }
    for flag in ["MARATHON_STARTUP_TIMING", "QSG_RENDER_TIMING"] {
        if var(flag).is_some_and(|v| v.parse::<i32>().is_ok_and(|n| n != 0)) {
            vars.push((flag, "1".to_owned()));
        }
    }
    if let Some(driver) = var("MARATHON_APP_MESA_DRIVER") {
        vars.push(("MESA_LOADER_DRIVER_OVERRIDE", driver));
    }
    let Some(app) = app(runner) else { return vars };
    // A spare learns the scale when it is adopted.
    vars.push(("MARATHON_USER_SCALE", format!("{:.3}", runner.user_scale)));
    for (permission, name) in [
        ("network", "MARATHON_PERM_NETWORK"),
        ("storage", "MARATHON_PERM_STORAGE"),
        ("secret-service", "MARATHON_PERM_SECRET_SERVICE"),
    ] {
        if app.has(permission) {
            vars.push((name, "1".to_owned()));
        }
    }
    if uses_webengine(runner) {
        vars.push(("QT_OPENGL", var_or("QT_OPENGL", "es2")));
        vars.push(("EGL_PLATFORM", "wayland".to_owned()));
        vars.push(("QTWEBENGINE_CHROMIUM_FLAGS", chromium_flags(&app)));
        vars.push((
            "WLR_RENDER_DRM_DEVICE",
            var("WLR_RENDER_DRM_DEVICE").unwrap_or_else(|| runner.render_node.clone()),
        ));
        if let Some(gles) = var("MARATHON_MESA_GLES_OVERRIDE") {
            vars.push(("MESA_GLES_VERSION_OVERRIDE", gles));
        }
    }
    vars
}

pub(crate) fn environment(runner: &Runner) -> QMap<QMapPair_QString_QVariant> {
    let mut map = QMap::<QMapPair_QString_QVariant>::default();
    let sandboxed = bwrap().is_some();
    for (name, value) in variables(runner)
        .into_iter()
        .chain(sandboxed.then(|| ("MARATHON_SANDBOXED", "1".to_owned())))
    {
        map.insert(QString::from(name), QVariant::from(&QString::from(&value)));
    }
    map
}

fn shared_folders() -> QStringList {
    media_folders()
        .iter()
        .map(|p| QString::from(p.to_string_lossy().as_ref()))
        .collect()
}

/// The media folders an app with "storage" sees, at the same paths.
pub(crate) fn shared_paths() -> Vec<PathBuf> {
    media_folders()
}

fn media_folders() -> Vec<PathBuf> {
    let home = home();
    let user = [
        (dirs::picture_dir(), "Pictures"),
        (dirs::audio_dir(), "Music"),
        (dirs::video_dir(), "Videos"),
        (dirs::document_dir(), "Documents"),
        (dirs::download_dir(), "Downloads"),
    ];
    user.into_iter()
        .map(|(dir, fallback)| dir.unwrap_or_else(|| home.join(fallback)))
        .filter(|d| *d != home)
        .chain([home.join("DCIM")])
        .collect()
}

/// The program and its arguments.
pub(crate) fn argv(runner: &Runner, runner_path: &str) -> Vec<String> {
    let app = app(runner);
    let tail = match &app {
        Some(app) => vec![
            runner_path.to_owned(),
            "--app-id".to_owned(),
            app.id.clone(),
        ],
        None => vec![runner_path.to_owned(), "--pool".to_owned()],
    };
    match bwrap() {
        Some(bwrap) => [vec![bwrap], sandbox(runner, app.as_ref()), tail].concat(),
        None => tail,
    }
}

#[allow(
    clippy::too_many_lines,
    reason = "the ordered bubblewrap argument list is easier to audit as one policy definition"
)]
fn sandbox(runner: &Runner, app: Option<&App<'_>>) -> Vec<String> {
    let home = home();
    let runtime = var_or("XDG_RUNTIME_DIR", "/run/user/1000");
    let (data_home, cache_home, config_home) = (
        marathon_rt::dirs::data(),
        marathon_rt::dirs::cache(),
        marathon_rt::dirs::config(),
    );
    let own = |base: &Path| {
        app.map_or_else(
            || base.join("marathon-apps"),
            |a| base.join("marathon-apps").join(&a.id),
        )
    };
    let (data, cache, config) = (own(&data_home), own(&cache_home), own(&config_home));
    // Spares only ever become Marathon's own apps, so they share one cache.
    let cache_env = if app.is_some() {
        cache.clone()
    } else {
        cache.join(".spare")
    };
    for dir in [&data, &cache_env, &config] {
        fs::create_dir_all(dir).ok();
    }
    let render = runner.render_node.clone();
    let mut args = Args::default();
    args.flags(&["--die-with-parent", "--new-session"]);
    // The shell's own driver pin sends Mesa to software rendering on a render node.
    args.flags(&[
        "--unsetenv",
        "MESA_LOADER_DRIVER_OVERRIDE",
        "--unsetenv",
        "ETNA_MESA_DEBUG",
    ]);
    // Chromium's own namespace sandbox nests inside these.
    args.flags(&[
        "--unshare-pid",
        "--unshare-uts",
        "--unshare-ipc",
        "--unshare-cgroup-try",
        "--unshare-user-try",
    ]);
    if app.is_some_and(|a| !a.has("network")) {
        args.flags(&["--unshare-net"]);
    }
    for dir in ["/usr", "/etc"] {
        args.bind("--ro-bind", dir);
    }
    for dir in ["/lib", "/lib64", "/bin", "/sbin", "/var/empty"] {
        args.bind("--ro-bind-try", dir);
    }
    args.flags(&["--proc", "/proc", "--dev", "/dev"]);
    // The render node only: card nodes belong to the shell, which is DRM master.
    args.bind("--dev-bind-try", &render);
    // Mesa finds its driver through these sysfs links; resolv.conf links into
    // systemd-resolved's state.
    for dir in [
        "/sys",
        "/sys/dev/char",
        "/sys/class/drm",
        "/sys/devices",
        "/run/systemd/resolve",
        "/run/dbus",
        "/var/run/dbus",
    ] {
        args.bind("--ro-bind-try", dir);
    }
    for dir in ["/tmp", "/dev/shm"] {
        args.flags(&["--tmpfs", dir]);
    }
    args.flags(&["--tmpfs", &home.to_string_lossy()]);
    args.bind("--ro-bind", "/usr/share/marathon-apps");
    args.bind("--ro-bind-try", &config.to_string_lossy());
    args.bind("--bind", &data.to_string_lossy());
    args.bind("--bind", &cache.to_string_lossy());
    args.bind("--bind", &runtime);
    // Nemo.Configuration reads dconf's database; writes go over D-Bus.
    args.bind(
        "--ro-bind-try",
        &config_home.join("dconf").to_string_lossy(),
    );
    // The app's own security-context socket where WAYLAND_DISPLAY points,
    // every sandbox's socket hidden.
    let socket = runner.wayland_socket.clone();
    let display = var_or("MARATHON_WL_SOCKET_NAME", "marathon-wayland-0");
    args.flags(&["--ro-bind", &socket, &format!("{runtime}/{display}")]);
    args.flags(&[
        "--tmpfs",
        &Path::new(&socket)
            .parent()
            .unwrap_or_else(|| Path::new("/"))
            .to_string_lossy(),
    ]);
    match app {
        Some(app) if is_user_installed(&app.id) => {
            args.bind(
                "--ro-bind",
                &user_installs().join(&app.id).to_string_lossy(),
            );
        }
        Some(app) if !app.has("system") => {}
        _ => args.bind("--ro-bind-try", &user_installs().to_string_lossy()),
    }
    if app.map_or(runner.storage_spare, |a| a.has("storage")) {
        for dir in media_folders() {
            if dir == home.join("DCIM") {
                args.bind("--bind-try", &dir.to_string_lossy());
            } else {
                fs::create_dir_all(&dir).ok();
                args.bind("--bind", &dir.to_string_lossy());
            }
        }
        let thumbnails = runner.thumbnails.clone();
        fs::create_dir_all(&thumbnails).ok();
        args.bind("--ro-bind", &thumbnails);
    }
    let sandbox_vars = [
        ("HOME", home.to_string_lossy().into_owned()),
        ("XDG_DATA_HOME", data_home.to_string_lossy().into_owned()),
        ("XDG_CACHE_HOME", cache_env.to_string_lossy().into_owned()),
        (
            "QML_DISK_CACHE_PATH",
            cache_env.join("qmlcache").to_string_lossy().into_owned(),
        ),
        (
            "XDG_CONFIG_HOME",
            config_home.to_string_lossy().into_owned(),
        ),
        ("MARATHON_SANDBOXED", "1".to_owned()),
    ];
    for (name, value) in variables(runner).into_iter().chain(sandbox_vars) {
        args.flags(&["--setenv", name, &value]);
    }
    args.0
}

#[derive(Default)]
struct Args(Vec<String>);

impl Args {
    fn flags(&mut self, flags: &[&str]) {
        self.0.extend(flags.iter().map(|f| (*f).to_owned()));
    }

    fn bind(&mut self, kind: &str, dir: &str) {
        self.flags(&[kind, dir, dir]);
    }
}

// splitCommand honours double quotes only, and drops an empty argument.
/// `argv` as one line that `QProcess::splitCommand` gives back whole.
pub(crate) fn command_line(argv: &[String]) -> String {
    let quoted: Vec<String> = argv
        .iter()
        .cloned()
        .map(|a| {
            if a.is_empty() {
                "\"\"".to_owned()
            } else if a.contains([' ', '"']) {
                format!("\"{}\"", a.replace('"', "\\\""))
            } else {
                a
            }
        })
        .collect();
    quoted.join(" ")
}
