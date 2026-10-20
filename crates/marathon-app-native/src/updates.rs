//! `Updates`: the shell's Updates1, system updates.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

use crate::shell::{get, mirror, Service, Update};

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(QString, state, READ, NOTIFY = state_changed)]
        #[qproperty(QString, current_version, cxx_name = "currentVersion", READ, NOTIFY = state_changed)]
        #[qproperty(QString, os_version, cxx_name = "osVersion", READ, NOTIFY = state_changed)]
        #[qproperty(QString, available_version, cxx_name = "availableVersion", READ, NOTIFY = state_changed)]
        #[qproperty(i64, download_size, cxx_name = "downloadSize", READ, NOTIFY = state_changed)]
        #[qproperty(QString, release_notes, cxx_name = "releaseNotes", READ, NOTIFY = state_changed)]
        #[qproperty(i32, progress, READ, NOTIFY = state_changed)]
        #[qproperty(QString, blocked_reason, cxx_name = "blockedReason", READ, NOTIFY = state_changed)]
        #[qproperty(QString, rolled_back_version, cxx_name = "rolledBackVersion", READ, NOTIFY = state_changed)]
        #[qproperty(bool, update_available, cxx_name = "updateAvailable", READ, NOTIFY = state_changed)]
        #[qproperty(QString, last_error, cxx_name = "lastError", READ, NOTIFY = state_changed)]
        #[qproperty(i64, last_checked_ms, cxx_name = "lastCheckedMs", READ, NOTIFY = state_changed)]
        #[qproperty(bool, auto_update, cxx_name = "autoUpdate", READ, WRITE = set_auto_update, NOTIFY = state_changed)]
        #[qproperty(bool, restart_scheduled, cxx_name = "restartScheduled", READ, NOTIFY = state_changed)]
        #[qproperty(QString, current_release_notes, cxx_name = "currentReleaseNotes", READ, NOTIFY = state_changed)]
        type Updates = super::UpdatesRust;

        #[qsignal]
        #[cxx_name = "stateChanged"]
        fn state_changed(self: Pin<&mut Self>);

        #[cxx_name = "setAutoUpdate"]
        fn set_auto_update(self: Pin<&mut Updates>, on: bool);
        #[qinvokable]
        #[cxx_name = "checkNow"]
        fn check_now(self: &Updates);
        #[qinvokable]
        fn install(self: &Updates);
        #[qinvokable]
        fn cancel(self: &Updates);
        #[qinvokable]
        fn reboot(self: &Updates);
        #[qinvokable]
        #[cxx_name = "scheduleRestart"]
        fn schedule_restart(self: &Updates);
    }

    impl cxx_qt::Threading for Updates {}
    impl cxx_qt::Initialize for Updates {}
}

use qobject::Updates;

const UPDATES: Service = Service::shell("Updates");

#[derive(Default)]
#[allow(clippy::struct_excessive_bools, reason = "the QML properties")]
pub struct UpdatesRust {
    state: QString,
    current_version: QString,
    os_version: QString,
    available_version: QString,
    download_size: i64,
    release_notes: QString,
    progress: i32,
    blocked_reason: QString,
    rolled_back_version: QString,
    update_available: bool,
    last_error: QString,
    last_checked_ms: i64,
    auto_update: bool,
    restart_scheduled: bool,
    current_release_notes: QString,
}

impl cxx_qt::Initialize for Updates {
    fn initialize(mut self: Pin<&mut Self>) {
        let mut u = self.as_mut().rust_mut();
        u.download_size = -1;
        u.auto_update = true;
        mirror(self.qt_thread(), UPDATES, "system", |mut obj, update| {
            let Update::State(s) = update else { return };
            let mut u = obj.as_mut().rust_mut();
            u.state = get(&s, "state");
            u.current_version = get(&s, "currentVersion");
            u.os_version = get(&s, "osVersion");
            u.available_version = get(&s, "availableVersion");
            u.download_size = if s.contains_key("downloadSize") { get(&s, "downloadSize") } else { -1 };
            u.release_notes = get(&s, "releaseNotes");
            u.progress = get(&s, "progress");
            u.blocked_reason = get(&s, "blockedReason");
            u.rolled_back_version = get(&s, "rolledBackVersion");
            u.update_available = u.state == QString::from("available");
            u.last_error = get(&s, "lastError");
            u.last_checked_ms = get(&s, "lastCheckedMs");
            u.auto_update = !s.contains_key("autoUpdate") || get(&s, "autoUpdate");
            u.restart_scheduled = get(&s, "restartScheduled");
            u.current_release_notes = get(&s, "currentReleaseNotes");
            obj.state_changed();
        });
    }
}

impl Updates {
    crate::shell::calls! { UPDATES; mut
        set_auto_update(on: bool) => "SetAutoUpdate";
    }
    crate::shell::calls! { UPDATES;
        check_now() => "CheckNow";
        install() => "Install";
        cancel() => "Cancel";
        reboot() => "Reboot";
        schedule_restart() => "ScheduleRestart";
    }
}
