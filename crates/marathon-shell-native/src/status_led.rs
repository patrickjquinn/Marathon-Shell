//! The notification light: the `*:status` LED under `/sys/class/leds`
//! (green on an RGB one) is on while the screen is off and notifications
//! are unread. It stays lit rather than blinking: a blink would wake the
//! phone to write it, and the timer trigger's delays are root's files.
//! udev/70-marathon-shell.rules lets the session write its brightness.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::sync::OnceLock;

use crate::{io, log};

static LED: OnceLock<Option<PathBuf>> = OnceLock::new();
static UNREAD: AtomicI32 = AtomicI32::new(0);
static SCREEN_ON: AtomicBool = AtomicBool::new(true);
static LIT: AtomicBool = AtomicBool::new(false);

/// The notification LED: a green status LED before any other status LED.
fn find(root: &Path) -> Option<PathBuf> {
    let mut names: Vec<String> = std::fs::read_dir(root)
        .ok()?
        .flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .filter(|n| n.ends_with(":status"))
        .collect();
    names.sort_by_key(|n| (!n.starts_with("green:"), n.clone()));
    let dir = root.join(names.first()?);
    dir.join("brightness").exists().then_some(dir)
}

fn led() -> Option<&'static PathBuf> {
    LED.get_or_init(|| find(Path::new("/sys/class/leds")))
        .as_ref()
}

fn write(dir: PathBuf, lit: bool) {
    io::spawn(async move {
        let r = blocking::unblock(move || -> std::io::Result<()> {
            let level = if lit {
                std::fs::read_to_string(dir.join("max_brightness"))?
            } else {
                "0".to_owned()
            };
            std::fs::write(dir.join("brightness"), level.trim())
        })
        .await;
        if let Err(e) = r {
            log::warn("status_led", e);
        }
    });
}

fn apply() {
    let want = UNREAD.load(Ordering::Relaxed) > 0 && !SCREEN_ON.load(Ordering::Relaxed);
    if LIT.swap(want, Ordering::Relaxed) == want {
        return;
    }
    if let Some(dir) = led() {
        write(dir.clone(), want);
    }
}

/// The number of unread notifications changed.
pub fn unread(count: i32) {
    UNREAD.store(count, Ordering::Relaxed);
    apply();
}

/// The screen went on or off.
pub fn screen(on: bool) {
    SCREEN_ON.store(on, Ordering::Relaxed);
    apply();
}

#[cfg(test)]
mod tests {
    #[allow(clippy::unwrap_used, reason = "tests")]
    #[test]
    fn the_green_status_led_is_the_notification_light() {
        let root = tempfile::tempdir().unwrap();
        for name in ["blue:status", "green:status", "red:status", "white:flash"] {
            let dir = root.path().join(name);
            std::fs::create_dir(&dir).unwrap();
            std::fs::write(dir.join("brightness"), "0").unwrap();
        }
        assert_eq!(
            super::find(root.path()),
            Some(root.path().join("green:status"))
        );
        std::fs::remove_dir_all(root.path().join("green:status")).unwrap();
        assert_eq!(
            super::find(root.path()),
            Some(root.path().join("blue:status"))
        );
        for name in ["blue:status", "red:status"] {
            std::fs::remove_dir_all(root.path().join(name)).unwrap();
        }
        assert_eq!(super::find(root.path()), None);
    }
}
