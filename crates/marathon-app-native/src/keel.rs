//! `KeelHost`: the Keel host (`marathon_keel::Host`) for the app this runner
//! runs. Started before the app's QML, which reads its environment when
//! Keel's plugin first loads; in a pool spare that is during the warm-up.

use std::pin::Pin;
use std::sync::{Arc, OnceLock};

use cxx_qt::Threading;
use marathon_keel::Host;
use marathon_rt::log;

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    extern "RustQt" {
        #[qobject]
        type KeelHost = super::KeelHostRust;

        /// SIGTERM: the app is told to close and given its grace.
        #[qsignal]
        #[cxx_name = "closeRequested"]
        fn close_requested(self: Pin<&mut Self>);

        /// Listens in `$XDG_RUNTIME_DIR` and exports the Keel environment;
        /// false when it cannot. SIGTERM becomes `closeRequested`.
        fn start(self: Pin<&mut KeelHost>, dpi: i32) -> bool;
        #[cxx_name = "setActive"]
        fn set_active(self: &KeelHost, active: bool);
        #[cxx_name = "requestClose"]
        fn request_close(self: &KeelHost);
    }

    impl cxx_qt::Threading for KeelHost {}
}

use qobject::KeelHost;

#[derive(Default)]
pub struct KeelHostRust;

impl Drop for KeelHostRust {
    fn drop(&mut self) {
        if let Some(host) = host() {
            host.close();
        }
    }
}

static HOST: OnceLock<Host> = OnceLock::new();

/// The running host, for the shell's calls (cover status).
pub fn host() -> Option<&'static Host> {
    HOST.get()
}

fn export(host: &Host) {
    for (key, value) in host.environment() {
        std::env::set_var(key, value);
    }
}

impl KeelHost {
    fn start(self: Pin<&mut Self>, dpi: i32) -> bool {
        let qt = self.qt_thread();
        let runtime = std::env::var("XDG_RUNTIME_DIR").unwrap_or_default();
        // A spare learns its app later: the id is read when the app asks.
        let activate = Arc::new(|| marathon_keel::launch(crate::shell::app_id().to_owned()));
        // Exported on the GUI thread, which reads the environment.
        let changed = qt.clone();
        let on_ambience = Arc::new(move || {
            changed
                .queue(|_| {
                    if let Some(host) = HOST.get() {
                        export(host);
                    }
                })
                .ok();
        });
        let host = match Host::start(runtime.as_ref(), dpi, activate, on_ambience) {
            Ok(host) => host,
            Err(e) => {
                log::warn("keel", format_args!("the Keel host did not start: {e}"));
                return false;
            }
        };
        export(&host);
        HOST.set(host).ok();
        if let Ok(mut signals) = signal_hook::iterator::Signals::new([signal_hook::consts::SIGTERM]) {
            std::thread::spawn(move || {
                for _ in signals.forever() {
                    qt.queue(qobject::KeelHost::close_requested).ok();
                }
            });
        }
        true
    }

    fn set_active(&self, active: bool) {
        if let Some(host) = host() {
            host.set_active(active);
        }
    }

    fn request_close(&self) {
        if let Some(host) = host() {
            host.request_close();
        }
    }
}
