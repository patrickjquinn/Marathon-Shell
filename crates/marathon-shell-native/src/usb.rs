//! `Usb`: whether a computer is on the USB port, and what the port offers
//! it: charging only, file transfer (MTP) or the developer network. The
//! charger's BC1.2 detection tells a computer (SDP, CDP) from a wall
//! charger. A computer gets charging only, or the developer network while
//! remote connection is on; file transfer is picked per connection, ends
//! with it, and hides the files while the phone is locked. The root helper
//! switches the gadget.

use std::fs;
use std::path::Path;
use std::pin::Pin;
use std::sync::OnceLock;
use std::time::Duration;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

use crate::{io, log, security};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        /// A computer, not a charger, is on the port.
        #[qproperty(bool, host, READ, NOTIFY)]
        /// "charging", "files" or "developer".
        #[qproperty(QString, mode, READ, NOTIFY)]
        #[qproperty(bool, files_available, cxx_name = "filesAvailable", READ, NOTIFY)]
        /// Remote connection is on.
        #[qproperty(
            bool,
            developer_available,
            cxx_name = "developerAvailable",
            READ,
            NOTIFY
        )]
        type Usb = super::UsbRust;

        /// Looks again at what is plugged in, after the power supply changes.
        #[qinvokable]
        fn refresh(self: Pin<&mut Usb>);
        #[qinvokable]
        #[cxx_name = "setMode"]
        fn set_mode(self: Pin<&mut Usb>, mode: &QString);
        #[qinvokable]
        #[cxx_name = "setLocked"]
        fn set_locked(self: Pin<&mut Usb>, locked: bool);
    }

    impl cxx_qt::Threading for Usb {}
    impl cxx_qt::Initialize for Usb {}
}

use qobject::Usb;

const HELPER: &str = "/usr/libexec/marathon-usb-mode";
const GADGET: &str = "/sys/kernel/config/usb_gadget/g1";

#[derive(Default)]
pub struct UsbRust {
    host: bool,
    mode: QString,
    files_available: bool,
    developer_available: bool,
    /// The connection the default mode was last set for; none before start.
    applied: Option<bool>,
}

/// The connected port's BC1.2 type ("SDP", "DCP", ...), once detected.
fn port_type() -> Option<String> {
    let supplies = fs::read_dir("/sys/class/power_supply").ok()?;
    supplies.flatten().find_map(|s| {
        let online = fs::read_to_string(s.path().join("online")).ok()?;
        let types = fs::read_to_string(s.path().join("usb_type")).ok()?;
        if online.trim() != "1" {
            return None;
        }
        let chosen = types.split_whitespace().find(|t| t.starts_with('['))?;
        let chosen = chosen.trim_matches(['[', ']']);
        (chosen != "Unknown").then(|| chosen.to_owned())
    })
}

/// The gadget's mode now: unbound, MTP or the network.
fn gadget_mode() -> &'static str {
    let bound =
        fs::read_to_string(Path::new(GADGET).join("UDC")).is_ok_and(|udc| !udc.trim().is_empty());
    let mtp = fs::read_dir(Path::new(GADGET).join("configs/c.1"))
        .into_iter()
        .flatten()
        .flatten()
        .any(|e| e.file_name().to_string_lossy().starts_with("ffs."));
    match (bound, mtp) {
        (false, _) => "charging",
        (true, true) => "files",
        (true, false) => "developer",
    }
}

static USB: OnceLock<cxx_qt::CxxQtThread<Usb>> = OnceLock::new();

/// A mode picked from the USB notification.
pub fn choose(mode: &str) {
    let mode = QString::from(mode);
    if let Some(qt) = USB.get() {
        qt.queue(move |obj| obj.set_mode(&mode)).ok();
    }
}

fn helper(qt: cxx_qt::CxxQtThread<Usb>, command: &'static str) {
    io::spawn(async move {
        if security::run_helper(HELPER, command, "").await != Some(0) {
            log::warn("usb", format_args!("{command} failed"));
        }
        if matches!(command, "charging" | "files" | "developer") {
            let mode = QString::from(gadget_mode());
            qt.queue(move |mut obj| set!(obj, mode, mode_changed, mode))
                .ok();
        }
    });
}

impl Usb {
    fn refresh(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        io::spawn(async move {
            // Detection ends a moment after the supply comes online.
            let mut kind = port_type();
            for wait in [300, 700, 1500] {
                if kind.is_some() {
                    break;
                }
                async_io::Timer::after(Duration::from_millis(wait)).await;
                kind = port_type();
            }
            let host = matches!(kind.as_deref(), Some("SDP" | "CDP"));
            let developer = security::remote_connection_state().await == "on";
            qt.queue(move |obj| obj.apply(host, developer)).ok();
        });
    }

    /// The default mode at start and at each connection or disconnection;
    /// file transfer lasts only while the computer stays connected.
    fn apply(mut self: Pin<&mut Self>, host: bool, developer: bool) {
        set!(
            self,
            developer_available,
            developer_available_changed,
            developer
        );
        let changed = self.applied != Some(host);
        self.as_mut().rust_mut().applied = Some(host);
        set!(self, host, host_changed, host);
        let wanted = if developer { "developer" } else { "charging" };
        if changed && self.mode.to_string() != wanted && Path::new(GADGET).exists() {
            helper(self.qt_thread(), wanted);
        }
    }

    fn set_mode(self: Pin<&mut Self>, mode: &QString) {
        let command = match mode.to_string().as_str() {
            "charging" => "charging",
            "files" if self.files_available => "files",
            "developer" => "developer",
            _ => return,
        };
        helper(self.qt_thread(), command);
    }

    fn set_locked(self: Pin<&mut Self>, locked: bool) {
        if self.mode.to_string() == "files" {
            helper(self.qt_thread(), if locked { "lock" } else { "unlock" });
        }
    }
}

impl cxx_qt::Initialize for Usb {
    fn initialize(mut self: Pin<&mut Self>) {
        let files = Path::new(HELPER).exists() && Path::new("/usr/bin/umtprd").exists();
        let mut rust = self.as_mut().rust_mut();
        rust.files_available = files;
        rust.mode = QString::from(gadget_mode());
        USB.set(self.qt_thread()).ok();
        self.refresh();
    }
}
