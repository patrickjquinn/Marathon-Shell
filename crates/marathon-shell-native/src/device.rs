//! The device's traits the shell cannot probe (GPU stack, panel, policies),
//! from `/etc/marathon/device-profile.conf` (KEY=VALUE, `MARATHON_DEVICE_PROFILE`
//! names another), each overridden by its `MARATHON_*` variable. Missing keys
//! keep the Librem 5's values. Read before the GUI exists: the surface format
//! comes from it.

use std::collections::HashMap;
use std::os::fd::AsFd as _;
use std::sync::LazyLock;
use std::time::{Duration, Instant};

use cxx_qt_lib::QString;

#[cxx_qt::bridge]
mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[namespace = "marathon::device"]
    struct Profile {
        device_id: QString,
        gpu_stack: QString,
        gles_major: i32,
        gles_minor: i32,
        surface_has_alpha: bool,
        /// The hardware's FBO samples, 0 for none.
        hw_msaa_samples: i32,
        /// 18 bpp panels band on gradients without a noise overlay.
        panel_dither: bool,
        render_node: QString,
        brightness_floor: f64,
        /// Spawned runners' first surface size.
        runner_width: i32,
        runner_height: i32,
        /// The panel's true DPI, 0 to trust the screen.
        panel_dpi: f64,
        /// Native apps' Wayland scale, 0 for DPI / 160.
        native_scale: f64,
        /// Doze powers the CRTC down; false is the backlight only.
        doze_dpms: bool,
        wifi_power_save: bool,
        /// Idle screen-off, 0 for never.
        screen_timeout_ms: i32,
        /// Bits per channel the panel shows; below 8 the frame is dithered.
        panel_depth: i32,
        /// A physical key wakes a blanked screen.
        wake_on_key: bool,
        /// Warm spare runners: 0, 1, or 2 (one per sandbox shape).
        runner_pool: i32,
        /// Qt's evdevtouch Kalman filter: even steps, ~60 ms more lag.
        touch_filter: bool,
        /// Extra evdevtouch parameters, e.g. "rotate=90:invertx".
        touch_params: QString,
    }

    #[namespace = "marathon::device"]
    extern "Rust" {
        fn profile() -> Profile;
        /// A keyboard with letter keys is attached (MARATHON_FORCE_VKB: none).
        fn has_hardware_keyboard() -> bool;
        /// Waits up to `timeout_ms` until no other process is DRM master on
        /// the cards eglfs_kms may open; the ms waited, or -1.
        fn wait_for_drm_master(timeout_ms: i32) -> i32;
    }
}

use ffi::Profile;

/// The profile's values, for the shell's Rust.
pub struct Values {
    raw: HashMap<String, String>,
}

impl Values {
    fn get(&self, env: &str, key: &str) -> Option<String> {
        std::env::var(env).ok().filter(|v| !v.is_empty()).or_else(|| self.raw.get(key).cloned())
    }

    fn text(&self, env: &str, key: &str, default: &str) -> String {
        self.get(env, key).unwrap_or_else(|| default.to_owned())
    }

    fn number<T: std::str::FromStr>(&self, env: &str, key: &str, default: T, valid: impl Fn(&T) -> bool) -> T {
        self.get(env, key).and_then(|v| v.parse().ok()).filter(valid).unwrap_or(default)
    }

    fn flag(&self, env: &str, key: &str, default: bool) -> bool {
        match self.get(env, key).map(|v| v.to_lowercase()).as_deref() {
            Some("1" | "true" | "yes" | "on") => true,
            Some("0" | "false" | "no" | "off") => false,
            _ => default,
        }
    }

    pub fn render_node(&self) -> String {
        self.text("MARATHON_RENDER_NODE", "RENDER_NODE", "/dev/dri/renderD128")
    }

    pub fn gpu_stack(&self) -> String {
        self.text("MARATHON_GPU_STACK", "GPU_STACK", "mesa-etnaviv")
    }

    pub fn runner_pool(&self) -> i32 {
        self.number("MARATHON_RUNNER_POOL", "RUNNER_POOL", 1, |n| (0..=2).contains(n))
    }

    pub fn runner_size(&self) -> (i32, i32) {
        (
            self.number("MARATHON_APP_WIDTH", "RUNNER_WIDTH", 540, |n| *n > 0),
            self.number("MARATHON_APP_HEIGHT", "RUNNER_HEIGHT", 1140, |n| *n > 0),
        )
    }
}

pub static VALUES: LazyLock<Values> = LazyLock::new(|| {
    let path = std::env::var("MARATHON_DEVICE_PROFILE").unwrap_or_else(|_| "/etc/marathon/device-profile.conf".into());
    let raw = dotenvy::from_path_iter(path).map(|i| i.flatten().collect()).unwrap_or_default();
    Values { raw }
});

fn profile() -> Profile {
    let v = &*VALUES;
    let q = |s: String| QString::from(&s);
    let (gles_major, gles_minor) = v
        .get("MARATHON_GLES_VERSION", "GLES_LEVEL")
        .and_then(|s| {
            let (major, minor) = s.split_once('.').unwrap_or((&s, "0"));
            Some((major.parse().ok().filter(|m| *m > 0)?, minor.parse().unwrap_or(0)))
        })
        .unwrap_or((2, 0));
    let (runner_width, runner_height) = v.runner_size();
    Profile {
        device_id: q(v.text("MARATHON_DEVICE_ID", "DEVICE_ID", "generic")),
        gpu_stack: q(v.gpu_stack()),
        gles_major,
        gles_minor,
        surface_has_alpha: v.flag("MARATHON_SURFACE_ALPHA", "SURFACE_ALPHA", false),
        hw_msaa_samples: v.number("MARATHON_LAYER_SAMPLES", "GPU_MSAA", 0, |_| true),
        panel_dither: v.flag("MARATHON_PANEL_DITHER", "PANEL_DITHER", true),
        render_node: q(v.render_node()),
        brightness_floor: v.number("MARATHON_BRIGHTNESS_FLOOR", "BRIGHTNESS_FLOOR", 0.28, |f| (0.0..=1.0).contains(f)),
        runner_width,
        runner_height,
        panel_dpi: v.number("MARATHON_PANEL_DPI", "PANEL_DPI", 0.0, |f| *f > 0.0),
        native_scale: v.number("MARATHON_NATIVE_SCALE", "NATIVE_SCALE", 0.0, |f| *f > 0.0),
        doze_dpms: v.flag("MARATHON_DOZE_DPMS", "DOZE_DPMS", true),
        wifi_power_save: v.flag("MARATHON_WIFI_POWERSAVE", "WIFI_POWERSAVE", true),
        screen_timeout_ms: v.number("MARATHON_SCREEN_TIMEOUT_MS", "SCREEN_TIMEOUT_MS", 300_000, |n| *n >= 0),
        panel_depth: v.number("MARATHON_PANEL_DEPTH", "PANEL_DEPTH", 8, |n| (4..=10).contains(n)),
        wake_on_key: v.flag("MARATHON_WAKE_ON_KEY", "WAKE_ON_KEY", false),
        runner_pool: v.runner_pool(),
        touch_filter: v.flag("MARATHON_TOUCH_FILTER", "TOUCH_FILTER", false),
        touch_params: q(v.text("MARATHON_TOUCH_PARAMS", "TOUCH_PARAMS", "")),
    }
}

/// /proc/bus/input/devices, which needs no access to the devices: a `kbd`
/// handler with key repeat and a full key map, not a power button.
fn has_hardware_keyboard() -> bool {
    const EV_REP: u64 = 1 << 20;
    if std::env::var_os("MARATHON_FORCE_VKB").is_some() {
        return false;
    }
    std::fs::read_to_string("/proc/bus/input/devices").unwrap_or_default().split("\n\n").any(|device| {
        let field = |prefix: &str| device.lines().find_map(|l| l.strip_prefix(prefix)).unwrap_or("").trim();
        let ev = u64::from_str_radix(field("B: EV="), 16).unwrap_or(0);
        field("H: Handlers=").split(' ').any(|h| h == "kbd") && ev & EV_REP != 0 && field("B: KEY=").len() > 40
    })
}

struct Card(std::fs::File);

impl std::os::fd::AsFd for Card {
    fn as_fd(&self) -> std::os::fd::BorrowedFd<'_> {
        self.0.as_fd()
    }
}

impl drm::Device for Card {}
impl drm::control::Device for Card {}

fn open(path: &std::path::Path) -> Option<Card> {
    std::fs::OpenOptions::new().read(true).write(true).open(path).ok().map(Card)
}

/// `QT_QPA_EGLFS_KMS_CONFIG`'s device, else every card with connectors.
fn eglfs_cards() -> Vec<std::path::PathBuf> {
    let configured = std::env::var("QT_QPA_EGLFS_KMS_CONFIG")
        .ok()
        .and_then(|p| std::fs::read(p).ok())
        .and_then(|b| serde_json::from_slice::<serde_json::Value>(&b).ok())
        .and_then(|j| j["device"].as_str().map(std::path::PathBuf::from));
    if let Some(card) = configured {
        return vec![card];
    }
    let mut cards: Vec<_> = std::fs::read_dir("/dev/dri")
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.file_name().is_some_and(|n| n.to_string_lossy().starts_with("card")))
        .filter(|p| open(p).is_some_and(|c| drm::control::Device::resource_handles(&c).is_ok_and(|r| !r.connectors().is_empty())))
        .collect();
    cards.sort();
    cards
}

/// The kernel makes the first opener master: an open that is not master
/// means another holds it (drmIsMaster's test).
fn held_by_other(card: &std::path::Path) -> bool {
    open(card).is_some_and(|c| drm_ffi::auth::auth_magic_token(c.0.as_fd(), 0).is_err_and(|e| e.raw_os_error() == Some(libc::EACCES)))
}

fn wait_for_drm_master(timeout_ms: i32) -> i32 {
    let cards = eglfs_cards();
    let started = Instant::now();
    let timeout = Duration::from_millis(u64::try_from(timeout_ms).unwrap_or(0));
    while cards.iter().any(|c| held_by_other(c)) {
        if started.elapsed() >= timeout {
            return -1;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    i32::try_from(started.elapsed().as_millis()).unwrap_or(i32::MAX)
}
