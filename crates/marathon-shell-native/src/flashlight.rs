//! `Flashlight`: the torch LED under `/sys/class/leds`, written on the I/O
//! thread: a flash driver can sit behind I2C.

use std::path::{Path, PathBuf};
use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};

use crate::{io, log};

#[cxx_qt::bridge]
pub mod qobject {
    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, available, READ, CONSTANT)]
        #[qproperty(bool, enabled, READ, NOTIFY)]
        type Flashlight = super::FlashlightRust;

        /// Whether the torch is on now.
        #[qinvokable]
        fn toggle(self: Pin<&mut Flashlight>) -> bool;
    }

    impl cxx_qt::Threading for Flashlight {}
    impl cxx_qt::Initialize for Flashlight {}
}

use qobject::Flashlight;

#[derive(Default)]
pub struct FlashlightRust {
    available: bool,
    enabled: bool,
    led: Option<(PathBuf, i32)>,
}

impl cxx_qt::Initialize for Flashlight {
    fn initialize(mut self: Pin<&mut Self>) {
        let led = find_led(Path::new("/sys/class/leds"));
        let mut rust = self.as_mut().rust_mut();
        rust.available = led.is_some();
        rust.led = led;
    }
}

impl Flashlight {
    fn toggle(mut self: Pin<&mut Self>) -> bool {
        let Some((dir, max)) = self.led.clone() else { return false };
        let on = !self.enabled;
        let qt = self.qt_thread();
        io::spawn(async move {
            let level = if on { max.min(255) } else { 0 };
            if let Err(e) = blocking::unblock(move || std::fs::write(dir.join("brightness"), level.to_string())).await {
                log::warn("flashlight", e);
                qt.queue(move |mut obj| set!(obj, enabled, enabled_changed, !on)).ok();
            }
        });
        set!(self, enabled, enabled_changed, on);
        on
    }
}

/// The torch's directory and `max_brightness`.
fn find_led(root: &Path) -> Option<(PathBuf, i32)> {
    let mut names: Vec<String> = std::fs::read_dir(root).ok()?.flatten().map(|e| e.file_name().to_string_lossy().into_owned()).collect();
    names.sort();
    let name = names.into_iter().find(|n| {
        let n = n.to_lowercase();
        n.contains("torch") || n.contains("flash") || (n.contains("camera") && n.contains("led"))
    })?;
    let dir = root.join(name);
    if !dir.join("brightness").exists() {
        return None;
    }
    let max = io::read(dir.join("max_brightness")).filter(|m| *m > 0).unwrap_or(255);
    Some((dir, max))
}

#[cfg(test)]
mod tests {
    #[allow(clippy::unwrap_used, reason = "tests")]
    #[test]
    fn the_torch_is_the_flash_led_not_the_first() {
        let root = tempfile::tempdir().unwrap();
        for (name, max) in [("green:status", "1"), ("white:flash", "15")] {
            let dir = root.path().join(name);
            std::fs::create_dir(&dir).unwrap();
            std::fs::write(dir.join("brightness"), "0").unwrap();
            std::fs::write(dir.join("max_brightness"), max).unwrap();
        }
        assert_eq!(super::find_led(root.path()), Some((root.path().join("white:flash"), 15)));
        std::fs::remove_dir_all(root.path().join("white:flash")).unwrap();
        assert_eq!(super::find_led(root.path()), None);
    }
}
