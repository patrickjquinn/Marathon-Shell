//! `SecurityManagerCpp`: the quick PIN, the system password through PAM,
//! the fingerprint reader, the lockout, the data partition's startup PIN and
//! remote connection over SSH. Hashing, PAM and the root helpers run on the
//! blocking pool and fprintd on the I/O thread; the GUI thread only keeps the
//! state QML binds to.

use crate::i18n::fl;
use std::fs;
use std::io::{Read, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use async_channel::Sender;
use async_io::Timer;
use async_lock::Mutex;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use futures_lite::io::AsyncBufReadExt;
use futures_lite::{future, StreamExt};
use sha2::{Digest, Sha256};
use zbus::fdo;
use zbus::message::Header;
use zbus::OwnedObjectPath;

use crate::audit::{self, Severity};
use crate::ipc::{self, value, State};
use crate::systemd::SystemdManagerProxy;
use crate::{gate, io, log, pam};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(i32, auth_mode, cxx_name = "authMode", READ = auth_mode, NOTIFY = auth_mode_changed)]
        #[qproperty(bool, has_quick_pin, cxx_name = "hasQuickPIN", READ, NOTIFY = quick_pin_changed)]
        #[qproperty(bool, fingerprint_available, cxx_name = "fingerprintAvailable", READ = fingerprint_available, NOTIFY = fingerprint_changed)]
        #[qproperty(bool, has_fingerprint_reader, cxx_name = "hasFingerprintReader", READ = has_fingerprint_reader, NOTIFY = fingerprint_changed)]
        /// "" while a finger can unlock; "restart" until the PIN or password
        /// is used once after the shell starts, "attempts" after too many
        /// misses, until the PIN or password is used.
        #[qproperty(QString, fingerprint_blocked, cxx_name = "fingerprintBlocked", READ = fingerprint_blocked, NOTIFY = fingerprint_changed)]
        #[qproperty(bool, is_locked_out, cxx_name = "isLockedOut", READ = is_locked_out, NOTIFY = lockout_state_changed)]
        #[qproperty(i32, lockout_seconds_remaining, cxx_name = "lockoutSecondsRemaining", READ = lockout_seconds_remaining, NOTIFY = lockout_state_changed)]
        #[qproperty(i32, failed_attempts, cxx_name = "failedAttempts", READ, NOTIFY = failed_attempts_changed)]
        /// "none", "off", "open" or "pin": see `data_encryption_state`.
        #[qproperty(QString, data_encryption, cxx_name = "dataEncryption", READ, NOTIFY = data_encryption_changed)]
        /// The PIN was typed at startup to unlock the data; the lock screen
        /// needn't ask again this boot.
        #[qproperty(bool, boot_unlocked, cxx_name = "bootUnlocked", READ, NOTIFY = boot_unlocked_changed)]
        /// A trackpad combination unlocks the lock screen as the PIN does.
        #[qproperty(bool, has_trackpad_combo, cxx_name = "hasTrackpadCombo", READ, NOTIFY = trackpad_combo_changed)]
        /// Settings is recording a new combination: strokes go to
        /// `recorded_combo`, not to the lock screen.
        #[qproperty(bool, recording_combo, cxx_name = "recordingCombo", READ, NOTIFY = trackpad_combo_changed)]
        #[qproperty(QString, recorded_combo, cxx_name = "recordedCombo", READ, NOTIFY = trackpad_combo_changed)]
        type Security = super::SecurityRust;

        #[cxx_name = "authMode"]
        fn auth_mode(self: &Security) -> i32;
        #[cxx_name = "fingerprintAvailable"]
        fn fingerprint_available(self: &Security) -> bool;
        #[cxx_name = "hasFingerprintReader"]
        fn has_fingerprint_reader(self: &Security) -> bool;
        #[cxx_name = "fingerprintBlocked"]
        fn fingerprint_blocked(self: &Security) -> QString;
        #[cxx_name = "isLockedOut"]
        fn is_locked_out(self: &Security) -> bool;
        #[cxx_name = "lockoutSecondsRemaining"]
        fn lockout_seconds_remaining(self: &Security) -> i32;

        #[qsignal]
        #[cxx_name = "authenticationSuccess"]
        fn authentication_success(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "authenticationFailed"]
        fn authentication_failed(self: Pin<&mut Self>, reason: &QString);
        #[qsignal]
        #[cxx_name = "authModeChanged"]
        fn auth_mode_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "quickPINChanged"]
        fn quick_pin_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "fingerprintChanged"]
        fn fingerprint_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "lockoutStateChanged"]
        fn lockout_state_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "failedAttemptsChanged"]
        fn failed_attempts_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "dataEncryptionChanged"]
        fn data_encryption_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "bootUnlockedChanged"]
        fn boot_unlocked_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "trackpadComboChanged"]
        fn trackpad_combo_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "biometricPrompt"]
        fn biometric_prompt(self: Pin<&mut Self>, message: &QString);
        /// A finger that is not enrolled; the sensor keeps listening.
        #[qsignal]
        #[cxx_name = "fingerprintMismatch"]
        fn fingerprint_mismatch(self: Pin<&mut Self>, message: &QString);

        #[qinvokable]
        #[cxx_name = "authenticatePassword"]
        fn authenticate_password(self: Pin<&mut Security>, password: &QString);
        #[qinvokable]
        #[cxx_name = "authenticateQuickPIN"]
        fn authenticate_quick_pin(self: Pin<&mut Security>, pin: &QString);
        /// `combo`: the strokes, one of U D L R each.
        #[qinvokable]
        #[cxx_name = "authenticateTrackpadCombo"]
        fn authenticate_trackpad_combo(self: Pin<&mut Security>, combo: &QString);
        /// A stroke on the trackpad while strokes are on (TrackpadInput).
        #[qinvokable]
        #[cxx_name = "recordStroke"]
        fn record_stroke(self: Pin<&mut Security>, stroke: &QString);
        /// `kind` 0 is the fingerprint, the only one there is. It listens
        /// until a finger matches, `cancelAuthentication`, or too many misses.
        #[qinvokable]
        #[cxx_name = "authenticateBiometric"]
        fn authenticate_biometric(self: Pin<&mut Security>, kind: i32);
        #[qinvokable]
        #[cxx_name = "cancelAuthentication"]
        fn cancel_authentication(self: Pin<&mut Security>);
        /// Changes the quick PIN after the system password.
        #[qinvokable]
        #[cxx_name = "setQuickPIN"]
        fn set_quick_pin(self: &Security, pin: &QString, system_password: &QString);
        /// The first-run PIN, set without a password while none is set yet.
        #[qinvokable]
        #[cxx_name = "setQuickPINFirstRun"]
        fn set_quick_pin_first_run(self: Pin<&mut Security>, pin: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "removeQuickPIN"]
        fn remove_quick_pin(self: &Security, system_password: &QString);
        #[qinvokable]
        #[cxx_name = "isBiometricEnrolled"]
        fn is_biometric_enrolled(self: &Security, kind: i32) -> bool;
        #[qinvokable]
        #[cxx_name = "resetLockout"]
        fn reset_lockout(self: Pin<&mut Security>);
        #[qinvokable]
        #[cxx_name = "getCurrentUsername"]
        fn get_current_username(self: &Security) -> QString;
    }

    impl cxx_qt::Threading for Security {}
    impl cxx_qt::Initialize for Security {}
}

use qobject::Security;

const MAX_ATTEMPTS: i32 = 5;
/// Misses before a finger can't unlock until the PIN is used.
const MAX_FINGERPRINT_MISSES: i32 = 5;
const FINGERPRINT_HELPER: &str = "/usr/libexec/marathon-fingerprint";
/// fprintd's finger names.
const FINGERS: [&str; 10] = [
    "left-thumb",
    "left-index-finger",
    "left-middle-finger",
    "left-ring-finger",
    "left-little-finger",
    "right-thumb",
    "right-index-finger",
    "right-middle-finger",
    "right-ring-finger",
    "right-little-finger",
];
const LOCKOUT: Duration = Duration::from_secs(300);
const DATA_KEY_HELPER: &str = "/usr/libexec/marathon-data-key";
const REMOTE_HELPER: &str = "/usr/libexec/marathon-remote-connection";
const BUG_REPORT_HELPER: &str = "/usr/libexec/marathon-bug-report";
/// The shortest remote connection password, here and in the helper.
const REMOTE_PASSWORD_MIN: usize = 8;
/// The root service that erases the device at the next boot, on images that can.
const FACTORY_RESET: &str = "/run/marathon/factory-reset.sock";

#[derive(Default)]
#[allow(
    clippy::struct_excessive_bools,
    reason = "independent lock states, each a Qt property"
)]
pub struct SecurityRust {
    has_quick_pin: bool,
    /// fprintd's default device, if there is one.
    reader: Option<OwnedObjectPath>,
    fingers: Vec<String>,
    /// Touches an enrolment takes, and "press" or "swipe".
    enroll_stages: i32,
    scan_type: String,
    /// The PIN or password checked out since the shell started.
    pin_entered: bool,
    fingerprint_misses: i32,
    stop_enroll: Option<Sender<()>>,
    failed_attempts: i32,
    locked_until: Option<Instant>,
    data_encryption: QString,
    boot_unlocked: bool,
    // An attempt is in flight; another is refused, not raced.
    checking: bool,
    stop_fingerprint: Option<Sender<()>>,
    // Ticks the lockout countdown while set.
    counting_down: Arc<AtomicBool>,
    user: String,
    /// "unavailable", "off" or "on": see `remote_connection_state`.
    remote_connection: &'static str,
    has_trackpad_combo: bool,
    recording_combo: bool,
    recorded_combo: QString,
}

/// What an attempt checked, for the messages and the audit log.
#[derive(Clone, Copy)]
enum Secret {
    Pin,
    Password,
    Fingerprint,
    Combo,
}

impl cxx_qt::Initialize for Security {
    fn initialize(mut self: Pin<&mut Self>) {
        // Read once at startup: the lock screen decides from these at once.
        let user = current_user();
        let home = std::env::var_os("HOME").map_or_default(PathBuf::from);
        let encryption = data_encryption_state(&home, &Probe::default());
        {
            let mut rust = self.as_mut().rust_mut();
            rust.has_quick_pin = !stored_pin().is_empty();
            rust.has_trackpad_combo = !stored(&combo_path()).is_empty();
            rust.data_encryption = QString::from(encryption);
            rust.user.clone_from(&user);
            rust.remote_connection = "unavailable";
        }
        let push = |obj: Pin<&mut Self>| ipc::signal("Security", "StateChanged", (state(&obj),));
        self.as_mut().on_auth_mode_changed(push).release();
        self.as_mut().on_fingerprint_changed(push).release();
        self.as_mut().on_lockout_state_changed(push).release();
        self.as_mut().on_failed_attempts_changed(push).release();
        self.as_mut().on_data_encryption_changed(push).release();
        self.as_mut().on_trackpad_combo_changed(push).release();
        self.as_mut()
            .on_quick_pin_changed(move |obj| {
                ipc::signal("Security", "QuickPINChanged", ());
                push(obj);
            })
            .release();
        self.as_mut()
            .on_authentication_failed(move |obj, reason| {
                ipc::signal("Security", "AuthenticationFailed", (reason.to_string(),));
                push(obj);
            })
            .release();
        self.as_mut()
            .on_authentication_success(move |obj| {
                ipc::signal("Security", "AuthenticationSuccess", ());
                push(obj);
            })
            .release();
        let qt = self.qt_thread();
        ipc::export("Security", Security1 { qt: qt.clone() });
        io::spawn(refresh_remote_connection(qt.clone()));
        io::spawn(refresh_fingerprints(qt.clone(), user));
        if encryption == "pin" {
            // The initramfs leaves a note when the PIN was typed there.
            io::spawn(async move {
                if run_data_key("consume-boot-unlock", "").await == Some(0) {
                    qt.queue(|mut obj| {
                        obj.as_mut().rust_mut().boot_unlocked = true;
                        obj.as_mut().boot_unlocked_changed();
                        obj.pin_checked();
                    })
                    .ok();
                }
            });
        }
    }
}

impl Security {
    fn auth_mode(&self) -> i32 {
        // SystemPassword 0, QuickPIN 1.
        i32::from(self.has_quick_pin)
    }

    fn fingerprint_available(&self) -> bool {
        self.reader.is_some() && !self.fingers.is_empty()
    }

    fn has_fingerprint_reader(&self) -> bool {
        self.reader.is_some()
    }

    fn fingerprint_blocked(&self) -> QString {
        QString::from(if !self.pin_entered {
            "restart"
        } else if self.fingerprint_misses >= MAX_FINGERPRINT_MISSES {
            "attempts"
        } else {
            ""
        })
    }

    fn is_locked_out(&self) -> bool {
        self.locked_until
            .is_some_and(|until| Instant::now() < until)
    }

    fn lockout_seconds_remaining(&self) -> i32 {
        self.locked_until
            .and_then(|until| until.checked_duration_since(Instant::now()))
            .map_or(0, |left| i32::try_from(left.as_secs()).unwrap_or(i32::MAX))
    }

    fn get_current_username(&self) -> QString {
        QString::from(self.user.as_str())
    }

    fn is_biometric_enrolled(&self, kind: i32) -> bool {
        kind == 0 && self.fingerprint_available()
    }

    fn fail(self: Pin<&mut Self>, reason: &str) {
        self.authentication_failed(&QString::from(reason));
    }

    // Why the attempt can't start, if it can't.
    fn refuse(&self, secret: &str) -> Option<String> {
        if self.is_locked_out() {
            Some(fl!(
                "security-account-locked",
                seconds = self.lockout_seconds_remaining()
            ))
        } else if secret.is_empty() {
            Some(fl!("security-pin-empty"))
        } else if self.checking {
            Some(fl!("security-busy"))
        } else {
            None
        }
    }

    fn authenticate_quick_pin(mut self: Pin<&mut Self>, pin: &QString) {
        let pin = pin.to_string();
        if let Some(refusal) = self.refuse(&pin) {
            return self.fail(&refusal);
        }
        self.as_mut().rust_mut().checking = true;
        let qt = self.qt_thread();
        io::spawn(async move {
            let ok = check_pin(pin).await;
            qt.queue(move |obj| obj.finish(ok, Secret::Pin)).ok();
        });
    }

    fn authenticate_trackpad_combo(mut self: Pin<&mut Self>, combo: &QString) {
        let combo = combo.to_string();
        if let Some(refusal) = self.refuse(&combo) {
            return self.fail(&refusal);
        }
        self.as_mut().rust_mut().checking = true;
        let qt = self.qt_thread();
        io::spawn(async move {
            let ok = check_combo(combo).await;
            qt.queue(move |obj| obj.finish(ok, Secret::Combo)).ok();
        });
    }

    fn record_stroke(mut self: Pin<&mut Self>, stroke: &QString) {
        if !self.recording_combo || self.recorded_combo.to_string().len() >= COMBO_MAX {
            return;
        }
        let combo = format!("{}{stroke}", self.recorded_combo);
        self.as_mut().rust_mut().recorded_combo = QString::from(&combo);
        self.trackpad_combo_changed();
    }

    /// Settings records a combination: strokes stop going to the lock screen.
    fn set_recording_combo(mut self: Pin<&mut Self>, on: bool) {
        let mut rust = self.as_mut().rust_mut();
        rust.recording_combo = on;
        rust.recorded_combo = QString::default();
        self.trackpad_combo_changed();
    }

    /// The combination after the PIN; an empty one removes it.
    fn set_trackpad_combo(&self, combo: String, pin: String) {
        let qt = self.qt_thread();
        io::spawn(async move {
            if !check_pin(pin).await {
                qt.queue(|obj| obj.fail(&fl!("security-combo-pin"))).ok();
                return;
            }
            let ok = store_combo(combo.clone()).await;
            qt.queue(move |mut obj| {
                if !ok {
                    return obj.fail(&fl!("security-combo-store-failed"));
                }
                obj.as_mut().rust_mut().has_trackpad_combo = !combo.is_empty();
                obj.as_mut().set_recording_combo(false);
                ipc::signal("Security", "TrackpadComboSaved", ());
            })
            .ok();
        });
    }

    fn authenticate_password(mut self: Pin<&mut Self>, password: &QString) {
        let password = password.to_string();
        if password.is_empty() {
            return self.fail(&fl!("security-password-empty"));
        }
        if let Some(refusal) = self.refuse(&password) {
            return self.fail(&refusal);
        }
        self.as_mut().rust_mut().checking = true;
        let (qt, user) = (self.qt_thread(), self.user.clone());
        io::spawn(async move {
            let ok = password_ok(user, password).await;
            qt.queue(move |obj| obj.finish(ok, Secret::Password)).ok();
        });
    }

    fn finish(mut self: Pin<&mut Self>, ok: bool, secret: Secret) {
        self.as_mut().rust_mut().checking = false;
        match self.as_mut().settle(ok, secret) {
            None => self.authentication_success(),
            Some(message) => self.fail(&message),
        }
    }

    /// Counts an attempt towards the lockout and audits it; the failure
    /// message, if it failed.
    fn settle(mut self: Pin<&mut Self>, ok: bool, secret: Secret) -> Option<String> {
        let (method, what, source) = match secret {
            Secret::Pin => ("quick_pin", "PIN", "QuickPIN"),
            Secret::Password => ("password", "password", "PAM"),
            Secret::Fingerprint => ("fingerprint", "fingerprint", "fprintd"),
            Secret::Combo => ("trackpad_combo", "trackpad combination", "QuickPIN"),
        };
        if ok {
            self.as_mut().reset_lockout();
            if matches!(secret, Secret::Fingerprint) {
                self.as_mut().rust_mut().fingerprint_misses = 0;
            } else {
                self.as_mut().pin_checked();
            }
            audit::log(
                Severity::Info,
                &format!("Authentication success: user={} method={method}", self.user),
            );
            return None;
        }
        self.as_mut().record_failure();
        audit::log(
            Severity::Warning,
            &format!(
                "Authentication failure: user={} reason=Invalid {what} source={source}",
                self.user
            ),
        );
        Some(if self.is_locked_out() {
            let seconds = self.lockout_seconds_remaining();
            audit::log(
                Severity::Alert,
                &format!("Account locked out: user={} duration={seconds}s", self.user),
            );
            fl!("security-locked-for", seconds = seconds)
        } else {
            let remaining = MAX_ATTEMPTS - self.failed_attempts;
            if matches!(secret, Secret::Pin) {
                fl!("security-wrong-pin-left", remaining = remaining)
            } else {
                fl!("security-wrong-password-left", remaining = remaining)
            }
        })
    }

    /// The PIN or password checked out: a finger can unlock again.
    fn pin_checked(mut self: Pin<&mut Self>) {
        if self.pin_entered && self.fingerprint_misses == 0 {
            return;
        }
        let mut rust = self.as_mut().rust_mut();
        rust.pin_entered = true;
        rust.fingerprint_misses = 0;
        self.fingerprint_changed();
    }

    /// A finger that is not enrolled. Misses don't count towards the
    /// lockout, which would also stop the PIN, but enough of them stop the
    /// fingerprint until the PIN is used.
    fn fingerprint_missed(mut self: Pin<&mut Self>) {
        let misses = self.fingerprint_misses + 1;
        self.as_mut().rust_mut().fingerprint_misses = misses;
        audit::log(
            Severity::Warning,
            &format!(
                "Authentication failure: user={} reason=Invalid fingerprint source=fprintd",
                self.user
            ),
        );
        if misses < MAX_FINGERPRINT_MISSES {
            return self.fingerprint_mismatch(&QString::from(fl!("fingerprint-not-recognised")));
        }
        self.as_mut().cancel_authentication();
        self.as_mut().fingerprint_changed();
        self.fail(&fl!("fingerprint-too-many"));
    }

    fn record_failure(mut self: Pin<&mut Self>) {
        let attempts = self.failed_attempts + 1;
        self.as_mut().rust_mut().failed_attempts = attempts;
        self.as_mut().failed_attempts_changed();
        if attempts >= MAX_ATTEMPTS && !self.is_locked_out() {
            self.as_mut().rust_mut().locked_until = Some(Instant::now() + LOCKOUT);
            log::warn("security", "locked out for 5 minutes");
            self.as_mut().count_down();
            self.lockout_state_changed();
        }
    }

    // The countdown QML shows, once a second until the lockout ends.
    fn count_down(self: Pin<&mut Self>) {
        let running = Arc::clone(&self.counting_down);
        if running.swap(true, Ordering::Relaxed) {
            return;
        }
        let qt = self.qt_thread();
        io::spawn(async move {
            while running.load(Ordering::Relaxed) {
                Timer::after(Duration::from_secs(1)).await;
                let ticked = qt.queue(|mut obj| {
                    if !obj.is_locked_out() {
                        obj.as_mut().rust_mut().locked_until = None;
                        obj.counting_down.store(false, Ordering::Relaxed);
                    }
                    obj.lockout_state_changed();
                });
                if ticked.is_err() {
                    break;
                }
            }
        });
    }

    fn reset_lockout(mut self: Pin<&mut Self>) {
        if self.failed_attempts > 0 {
            self.as_mut().rust_mut().failed_attempts = 0;
            self.as_mut().failed_attempts_changed();
        }
        if self.locked_until.is_some() {
            self.as_mut().rust_mut().locked_until = None;
            self.counting_down.store(false, Ordering::Relaxed);
            self.lockout_state_changed();
        }
    }

    fn set_quick_pin(&self, pin: &QString, system_password: &QString) {
        let (pin, password, user, qt) = (
            pin.to_string(),
            system_password.to_string(),
            self.user.clone(),
            self.qt_thread(),
        );
        io::spawn(async move {
            if !password_ok(user, password).await {
                qt.queue(|obj| obj.fail(&fl!("security-set-pin-password")))
                    .ok();
                return;
            }
            // The startup PIN changes first, so a failure leaves both on the old PIN.
            let helper = run_data_key("set", &pin).await;
            queue_encryption(&qt);
            if !helper_ok(helper) {
                qt.queue(|obj| {
                    obj.fail(&fl!("security-startup-pin-change-failed"));
                })
                .ok();
                return;
            }
            let stored = store_pin(pin).await;
            qt.queue(move |obj| obj.pin_stored(stored)).ok();
        });
    }

    fn set_quick_pin_first_run(self: Pin<&mut Self>, pin: &QString) -> bool {
        // Only while no PIN is set: later changes need the password.
        if self.has_quick_pin {
            log::warn("security", "first-run PIN refused: a PIN is set");
            return false;
        }
        let pin = pin.to_string();
        if pin.chars().count() < 4 {
            return false;
        }
        let qt = self.qt_thread();
        io::spawn(async move {
            let stored = store_pin(pin.clone()).await;
            qt.queue(move |obj| obj.pin_stored(stored)).ok();
            if !stored {
                return;
            }
            // If this fails the data still opens at startup without a PIN,
            // and Settings says so.
            run_data_key("set", &pin).await;
            queue_encryption(&qt);
        });
        true
    }

    fn pin_stored(mut self: Pin<&mut Self>, stored: bool) {
        if !stored {
            return self.fail("Failed to store Quick PIN");
        }
        if !self.has_quick_pin {
            self.as_mut().rust_mut().has_quick_pin = true;
            self.as_mut().quick_pin_changed();
            self.auth_mode_changed();
        }
    }

    fn remove_quick_pin(&self, system_password: &QString) {
        let (password, user, qt, fingers) = (
            system_password.to_string(),
            self.user.clone(),
            self.qt_thread(),
            !self.fingers.is_empty(),
        );
        io::spawn(async move {
            if !password_ok(user.clone(), password).await {
                qt.queue(|obj| obj.fail(&fl!("security-remove-pin-password")))
                    .ok();
                return;
            }
            let helper = run_data_key("clear", "").await;
            queue_encryption(&qt);
            if !helper_ok(helper) {
                qt.queue(|obj| {
                    obj.fail(&fl!("security-startup-pin-off-failed"));
                })
                .ok();
                return;
            }
            let _guard = PIN_FILE.lock().await;
            if let Err(e) = fs::remove_file(pin_path()) {
                log::warn("security", format_args!("removing the PIN: {e}"));
            }
            // A combination stands in for the PIN, and a finger needs the PIN
            // behind it: they go with it.
            fs::remove_file(combo_path()).ok();
            if fingers {
                run("pkexec".to_owned(), fingerprint_helper("delete", ""), "").await;
                refresh_fingerprints(qt.clone(), user).await;
            }
            qt.queue(|mut obj| {
                obj.as_mut().rust_mut().has_trackpad_combo = false;
                obj.as_mut().trackpad_combo_changed();
                obj.as_mut().rust_mut().has_quick_pin = false;
                obj.as_mut().quick_pin_changed();
                obj.auth_mode_changed();
            })
            .ok();
        });
    }

    /// `answer` gets "" or why the secret was refused.
    fn check_owner(
        mut self: Pin<&mut Self>,
        secret: String,
        answer: impl FnOnce(Pin<&mut Self>, String) + Send + 'static,
    ) {
        if self.is_locked_out() {
            let refusal = fl!(
                "security-try-again-in",
                seconds = self.lockout_seconds_remaining()
            );
            return answer(self, refusal);
        }
        let (pin, user, qt) = (self.has_quick_pin, self.user.clone(), self.qt_thread());
        self.as_mut().rust_mut().checking = true;
        io::spawn(async move {
            let ok = if pin {
                check_pin(secret).await
            } else {
                password_ok(user, secret).await
            };
            qt.queue(move |mut obj| {
                obj.as_mut().rust_mut().checking = false;
                let secret = if pin { Secret::Pin } else { Secret::Password };
                let refusal = match obj.as_mut().settle(ok, secret) {
                    None => String::new(),
                    Some(_) if obj.is_locked_out() => {
                        fl!(
                            "security-try-again-in",
                            seconds = obj.lockout_seconds_remaining()
                        )
                    }
                    Some(_) if pin => fl!("security-wrong-pin"),
                    Some(_) => fl!("security-wrong-password"),
                };
                answer(obj, refusal);
            })
            .ok();
        });
    }

    fn authenticate_biometric(mut self: Pin<&mut Self>, kind: i32) {
        if kind != 0 {
            return self.fail(&fl!("security-biometric-unsupported"));
        }
        if self.is_locked_out() {
            let refusal = fl!(
                "security-account-locked",
                seconds = self.lockout_seconds_remaining()
            );
            return self.fail(&refusal);
        }
        let Some(reader) = self.reader.clone().filter(|_| !self.fingers.is_empty()) else {
            return self.fail(&fl!("fingerprint-unavailable"));
        };
        match self.fingerprint_blocked().to_string().as_str() {
            "restart" => return self.fail(&fl!("fingerprint-pin-after-restart")),
            "attempts" => return self.fail(&fl!("fingerprint-too-many")),
            _ => {}
        }
        if self.stop_fingerprint.is_some() {
            return;
        }
        let (stop, stopped) = async_channel::bounded(1);
        self.as_mut().rust_mut().stop_fingerprint = Some(stop);
        let (qt, user) = (self.qt_thread(), self.user.clone());
        io::spawn(async move {
            let result = listen_for_fingerprint(&qt, reader, &user, stopped).await;
            qt.queue(move |mut obj| {
                obj.as_mut().rust_mut().stop_fingerprint = None;
                match result {
                    Ok(true) => obj.finish(true, Secret::Fingerprint),
                    Ok(false) => {}
                    Err(message) => obj.fail(&message),
                }
            })
            .ok();
        });
    }

    fn cancel_authentication(mut self: Pin<&mut Self>) {
        if let Some(stop) = self.as_mut().rust_mut().stop_fingerprint.take() {
            stop.try_send(()).ok();
        }
    }
}

fn state(security: &Security) -> State {
    State::from([
        ("authMode".to_owned(), value(security.auth_mode())),
        ("hasQuickPIN".to_owned(), value(security.has_quick_pin)),
        (
            "hasTrackpadCombo".to_owned(),
            value(security.has_trackpad_combo),
        ),
        ("recordingCombo".to_owned(), value(security.recording_combo)),
        (
            "recordedCombo".to_owned(),
            value(security.recorded_combo.to_string()),
        ),
        (
            "fingerprintAvailable".to_owned(),
            value(security.fingerprint_available()),
        ),
        (
            "hasFingerprintReader".to_owned(),
            value(security.has_fingerprint_reader()),
        ),
        (
            "enrolledFingers".to_owned(),
            value(security.fingers.clone()),
        ),
        (
            "fingerprintStages".to_owned(),
            value(security.enroll_stages),
        ),
        (
            "fingerprintScanType".to_owned(),
            value(security.scan_type.clone()),
        ),
        (
            "fingerprintBlocked".to_owned(),
            value(security.fingerprint_blocked().to_string()),
        ),
        ("isLockedOut".to_owned(), value(security.is_locked_out())),
        (
            "lockoutSecondsRemaining".to_owned(),
            value(security.lockout_seconds_remaining()),
        ),
        ("failedAttempts".to_owned(), value(security.failed_attempts)),
        (
            "canEraseAllContent".to_owned(),
            value(Path::new(FACTORY_RESET).exists()),
        ),
        (
            "dataEncryption".to_owned(),
            value(security.data_encryption.to_string()),
        ),
        (
            "remoteConnection".to_owned(),
            value(security.remote_connection),
        ),
    ])
}

/// Ok once `secret` is the owner's quick PIN, or system password without
/// one; Err says why not.
async fn confirm_owner(qt: &cxx_qt::CxxQtThread<Security>, secret: String) -> Result<(), String> {
    let (tx, rx) = async_channel::bounded(1);
    ipc::on_gui(qt, move |obj| {
        obj.check_owner(secret, move |_, refusal| {
            tx.try_send(refusal).ok();
        });
    })
    .await
    .map_err(|e| e.to_string())?;
    let refusal = rx.recv().await.map_err(|e| e.to_string())?;
    if refusal.is_empty() {
        Ok(())
    } else {
        Err(refusal)
    }
}

/// Once the owner's secret checks out, asks the service for an erase; it
/// restarts the device. Err says why not.
async fn erase(qt: &cxx_qt::CxxQtThread<Security>, secret: String) -> Result<(), String> {
    if !Path::new(FACTORY_RESET).exists() {
        return Err(fl!("security-cannot-erase"));
    }
    confirm_owner(qt, secret).await?;
    let reply = blocking::unblock(|| {
        let mut socket = UnixStream::connect(FACTORY_RESET)?;
        socket.write_all(b"erase\n")?;
        let mut reply = String::new();
        socket.read_to_string(&mut reply)?;
        Ok::<_, std::io::Error>(reply)
    })
    .await
    .map_err(|e| fl!("security-erase-unreachable", error = e.to_string()))?;
    match reply.trim() {
        "ok" => Ok(()),
        "" => Err(fl!("security-erase-closed")),
        why => Err(why.to_owned()),
    }
}

struct Security1 {
    qt: cxx_qt::CxxQtThread<Security>,
}

#[zbus::interface(name = "org.marathonos.Shell.Security1")]
impl Security1 {
    async fn get_state(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<State> {
        ipc::admit(&h, "Security", &["system"]).await?;
        ipc::on_gui(&self.qt, |obj| state(&obj)).await
    }

    #[zbus(name = "SetQuickPIN")]
    async fn set_quick_pin(
        &self,
        pin: String,
        system_password: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        ipc::admit(&h, "Security", &["system"]).await?;
        ipc::on_gui(&self.qt, move |obj| {
            obj.set_quick_pin(&QString::from(&pin), &QString::from(&system_password));
        })
        .await
    }

    /// Sets the trackpad combination after the PIN; an empty one removes it.
    #[zbus(name = "SetTrackpadCombo")]
    async fn set_trackpad_combo(
        &self,
        combo: String,
        pin: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        ipc::admit(&h, "Security", &["system"]).await?;
        ipc::on_gui(&self.qt, move |obj| obj.set_trackpad_combo(combo, pin)).await
    }

    /// While on, trackpad strokes build `recordedCombo` for Settings.
    #[zbus(name = "RecordTrackpadCombo")]
    async fn record_trackpad_combo(
        &self,
        on: bool,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        ipc::admit(&h, "Security", &["system"]).await?;
        ipc::on_gui(&self.qt, move |obj| obj.set_recording_combo(on)).await
    }

    #[zbus(name = "RemoveQuickPIN")]
    async fn remove_quick_pin(
        &self,
        system_password: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        ipc::admit(&h, "Security", &["system"]).await?;
        ipc::on_gui(&self.qt, move |obj| {
            obj.remove_quick_pin(&QString::from(&system_password));
        })
        .await
    }

    async fn authenticate_password(
        &self,
        password: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        ipc::admit(&h, "Security", &["system"]).await?;
        ipc::on_gui(&self.qt, move |obj| {
            obj.authenticate_password(&QString::from(&password));
        })
        .await
    }

    /// The PIN is the authentication: only the rate limit stands before it.
    #[zbus(name = "AuthenticateQuickPIN")]
    async fn authenticate_quick_pin(
        &self,
        pin: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        if !gate::in_window(
            h.sender().map_or_default(zbus::names::UniqueName::as_str),
            "Security",
        ) {
            return Err(fdo::Error::LimitsExceeded("Rate limit exceeded".into()));
        }
        ipc::on_gui(&self.qt, move |obj| {
            obj.authenticate_quick_pin(&QString::from(&pin));
        })
        .await
    }

    async fn authenticate_biometric(
        &self,
        kind: i32,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        ipc::admit(&h, "Security", &["system"]).await?;
        ipc::on_gui(&self.qt, move |obj| obj.authenticate_biometric(kind)).await
    }

    /// Enrols `finger`, one of fprintd's names, once `pin` is the owner's
    /// quick PIN. Answers with `FingerprintEnrollStatus` for each touch, then
    /// `FingerprintEnrolled`, or `FingerprintFailed` saying why not.
    async fn enroll_fingerprint(
        &self,
        finger: String,
        pin: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        ipc::admit(&h, "Security", &["system"]).await?;
        if !FINGERS.contains(&finger.as_str()) {
            return Err(fdo::Error::InvalidArgs("Unknown finger".into()));
        }
        let (stop, stopped) = async_channel::bounded(1);
        let started = ipc::on_gui(&self.qt, move |mut obj| {
            let idle = obj.stop_enroll.is_none();
            if idle {
                obj.as_mut().rust_mut().stop_enroll = Some(stop);
            }
            idle
        })
        .await?;
        if !started {
            return Err(fdo::Error::LimitsExceeded("An enrolment is running".into()));
        }
        let qt = self.qt.clone();
        io::spawn(async move {
            let outcome = enroll_fingerprint(&qt, &finger, pin, stopped).await;
            let user = ipc::on_gui(&qt, |mut obj| {
                obj.as_mut().rust_mut().stop_enroll = None;
                obj.user.clone()
            })
            .await
            .unwrap_or_default();
            refresh_fingerprints(qt, user).await;
            match outcome {
                Ok(()) => ipc::signal("Security", "FingerprintEnrolled", (finger,)),
                Err(reason) if reason.is_empty() => {}
                Err(reason) => ipc::signal("Security", "FingerprintFailed", (reason,)),
            }
        });
        Ok(())
    }

    async fn cancel_fingerprint_enroll(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        ipc::admit(&h, "Security", &["system"]).await?;
        ipc::on_gui(&self.qt, |mut obj| {
            if let Some(stop) = obj.as_mut().rust_mut().stop_enroll.take() {
                stop.try_send(()).ok();
            }
        })
        .await
    }

    /// Deletes `finger`, or every finger when it is empty, once `pin` is the
    /// owner's quick PIN. Answers `FingerprintDeleted` or `FingerprintFailed`.
    async fn delete_fingerprint(
        &self,
        finger: String,
        pin: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        ipc::admit(&h, "Security", &["system"]).await?;
        if !finger.is_empty() && !FINGERS.contains(&finger.as_str()) {
            return Err(fdo::Error::InvalidArgs("Unknown finger".into()));
        }
        let qt = self.qt.clone();
        io::spawn(async move {
            let outcome = delete_fingerprints(&qt, &finger, pin).await;
            let user = ipc::on_gui(&qt, |obj| obj.user.clone())
                .await
                .unwrap_or_default();
            refresh_fingerprints(qt, user).await;
            match outcome {
                Ok(()) => ipc::signal("Security", "FingerprintDeleted", (finger,)),
                Err(reason) => ipc::signal("Security", "FingerprintFailed", (reason,)),
            }
        });
        Ok(())
    }

    async fn cancel_authentication(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        ipc::admit(&h, "Security", &["system"]).await?;
        ipc::on_gui(&self.qt, Security::cancel_authentication).await
    }

    async fn reset_lockout(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        ipc::admit(&h, "Security", &["system"]).await?;
        ipc::on_gui(&self.qt, Security::reset_lockout).await
    }

    async fn is_biometric_enrolled(
        &self,
        kind: i32,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<bool> {
        ipc::admit(&h, "Security", &["system"]).await?;
        ipc::on_gui(&self.qt, move |obj| obj.is_biometric_enrolled(kind)).await
    }

    async fn current_username(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<String> {
        ipc::admit(&h, "Security", &["system"]).await?;
        ipc::on_gui(&self.qt, |obj| obj.user.clone()).await
    }

    /// Erases the device at the next boot if `secret` is the owner's quick
    /// PIN, or system password without one; `EraseFailed` says why not.
    async fn erase_all_content(
        &self,
        secret: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        ipc::admit(&h, "Security", &["system"]).await?;
        let qt = self.qt.clone();
        io::spawn(async move {
            if let Err(reason) = erase(&qt, secret).await {
                ipc::signal("Security", "EraseFailed", (reason,));
            }
        });
        Ok(())
    }

    /// SSH logins by `password` on, or a new password while on, once `pin`
    /// is the owner's quick PIN (none without one); or off. Answers with
    /// `RemoteConnectionApplied`, or `RemoteConnectionFailed` saying why not.
    async fn set_remote_connection(
        &self,
        on: bool,
        password: String,
        pin: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        ipc::admit(&h, "Security", &["system"]).await?;
        // The helper reads one line.
        if on
            && (password.chars().count() < REMOTE_PASSWORD_MIN
                || password.chars().any(char::is_control))
        {
            return Err(fdo::Error::InvalidArgs("Unusable password".into()));
        }
        let qt = self.qt.clone();
        io::spawn(async move {
            let outcome = set_remote_connection(&qt, on, password, pin).await;
            refresh_remote_connection(qt).await;
            match outcome {
                Ok(()) => ipc::signal("Security", "RemoteConnectionApplied", ()),
                Err(reason) => ipc::signal("Security", "RemoteConnectionFailed", (reason,)),
            }
        });
        Ok(())
    }

    /// A saved Wi-Fi network's password, once `secret` is the owner's quick
    /// PIN (the system password without one).
    async fn wifi_password(
        &self,
        ssid: String,
        secret: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<String> {
        ipc::admit(&h, "Security", &["system"]).await?;
        confirm_owner(&self.qt, secret)
            .await
            .map_err(fdo::Error::AccessDenied)?;
        crate::wifi_details::password(&io::system_bus().await?, &ssid)
            .await
            .map_err(fdo::Error::Failed)
    }

    /// Gathers the system's logs into a file in Documents. Answers with
    /// `BugReportCreated` and its path, or `BugReportFailed` saying why not.
    async fn create_bug_report(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        ipc::admit(&h, "Security", &["system"]).await?;
        io::spawn(async move {
            let args = vec![BUG_REPORT_HELPER.to_owned(), "create".to_owned()];
            match run_output("pkexec".to_owned(), args, "", true).await {
                Some((Some(0), path, _)) if !path.trim().is_empty() => {
                    ipc::signal("Security", "BugReportCreated", (path.trim().to_owned(),));
                }
                // The helper's last word, so a screenshot of the notice says why.
                other => {
                    let reason = other
                        .and_then(|(_, _, err)| {
                            err.lines()
                                .rev()
                                .find(|l| !l.trim().is_empty())
                                .map(str::to_owned)
                        })
                        .unwrap_or_default();
                    let message = if reason.is_empty() {
                        fl!("security-bug-report-failed")
                    } else {
                        let reason: String = reason.trim().chars().take(160).collect();
                        fl!("security-bug-report-failed-because", reason = reason)
                    };
                    ipc::signal("Security", "BugReportFailed", (message,));
                }
            }
        });
        Ok(())
    }
}

async fn set_remote_connection(
    qt: &cxx_qt::CxxQtThread<Security>,
    on: bool,
    password: String,
    pin: String,
) -> Result<(), String> {
    if on {
        let has_pin = ipc::on_gui(qt, |obj| obj.has_quick_pin)
            .await
            .map_err(|e| e.to_string())?;
        if has_pin {
            confirm_owner(qt, pin).await?;
        }
    }
    let (command, password) = if on {
        ("on", password)
    } else {
        ("off", String::new())
    };
    if run_helper(REMOTE_HELPER, command, &password).await == Some(0) {
        Ok(())
    } else if on {
        Err(fl!("remote-connection-on-failed"))
    } else {
        Err(fl!("remote-connection-off-failed"))
    }
}

/// "on" while sshd starts at boot, "off" while it doesn't, "unavailable"
/// on an image without sshd or the helper.
pub(crate) async fn remote_connection_state() -> &'static str {
    if !Path::new(REMOTE_HELPER).exists() {
        return "unavailable";
    }
    let state = async {
        SystemdManagerProxy::new(&io::system_bus().await?)
            .await?
            .get_unit_file_state("sshd.service")
            .await
    };
    match state.await {
        Ok(state) if state.starts_with("enabled") => "on",
        Ok(_) => "off",
        Err(_) => "unavailable",
    }
}

async fn refresh_remote_connection(qt: cxx_qt::CxxQtThread<Security>) {
    let state = remote_connection_state().await;
    ipc::on_gui(&qt, move |mut obj| {
        if obj.remote_connection != state {
            obj.as_mut().rust_mut().remote_connection = state;
            ipc::signal("Security", "StateChanged", (self::state(&obj),));
        }
    })
    .await
    .ok();
}

fn helper_ok(code: Option<i32>) -> bool {
    // 3: the data partition is not encrypted; the quick PIN stands alone.
    matches!(code, Some(0 | 3))
}

fn queue_encryption(qt: &cxx_qt::CxxQtThread<Security>) {
    let home = std::env::var_os("HOME").map_or_default(PathBuf::from);
    let state = data_encryption_state(&home, &Probe::default());
    qt.queue(move |mut obj| {
        if obj.data_encryption.to_string() != state {
            obj.as_mut().rust_mut().data_encryption = QString::from(state);
            obj.data_encryption_changed();
        }
    })
    .ok();
}

// The PIN file is read and written one at a time: a PIN set during setup
// is on disk before the first unlock checks it.
static PIN_FILE: Mutex<()> = Mutex::new(());

async fn password_ok(user: String, password: String) -> bool {
    match blocking::unblock(move || pam::authenticate(&user, &password)).await {
        Ok(()) => true,
        Err(e) => {
            log::warn(
                "security",
                format_args!("PAM rejected authentication: {e:?}"),
            );
            false
        }
    }
}

async fn check_pin(pin: String) -> bool {
    let _guard = PIN_FILE.lock().await;
    blocking::unblock(move || {
        let stored = stored_pin();
        let ok = verify_pin(&pin, &stored);
        // A PIN still under the old hash moves to Argon2id once it is known.
        if ok && !stored.starts_with("argon2id:") {
            if let Err(e) = write_pin(&pin) {
                log::warn("security", format_args!("upgrading the PIN hash: {e}"));
            }
        }
        ok
    })
    .await
}

async fn store_pin(pin: String) -> bool {
    let _guard = PIN_FILE.lock().await;
    blocking::unblock(move || match write_pin(&pin) {
        Ok(()) => true,
        Err(e) => {
            log::warn("security", format_args!("storing the PIN: {e}"));
            false
        }
    })
    .await
}

fn pin_path() -> PathBuf {
    marathon_rt::dirs::config().join("marathon/quickpin.conf")
}

fn combo_path() -> PathBuf {
    marathon_rt::dirs::config().join("marathon/trackpadcombo.conf")
}

/// The longest trackpad combination, and the shortest one Settings keeps.
const COMBO_MAX: usize = 16;
pub const COMBO_MIN: usize = 4;

fn stored(path: &Path) -> String {
    io::read(path).unwrap_or_default()
}

fn stored_pin() -> String {
    stored(&pin_path())
}

async fn check_combo(combo: String) -> bool {
    let _guard = PIN_FILE.lock().await;
    blocking::unblock(move || {
        let stored = stored(&combo_path());
        stored.starts_with("argon2id:") && verify_pin(&combo, &stored)
    })
    .await
}

/// Stores `combo` as the PIN is stored; empty removes it.
async fn store_combo(combo: String) -> bool {
    let _guard = PIN_FILE.lock().await;
    blocking::unblock(move || {
        let result = if combo.is_empty() {
            fs::remove_file(combo_path()).or_else(|e| {
                if e.kind() == std::io::ErrorKind::NotFound {
                    Ok(())
                } else {
                    Err(e)
                }
            })
        } else if combo.len() < COMBO_MIN
            || combo.len() > COMBO_MAX
            || !combo.chars().all(|c| "UDLR".contains(c))
        {
            Err(std::io::Error::other("not a combination"))
        } else {
            write_secret(&combo_path(), &combo)
        };
        result
            .inspect_err(|e| log::warn("security", format_args!("storing the combination: {e}")))
            .is_ok()
    })
    .await
}

// Argon2id at 8 MiB and two passes: tens of milliseconds on a phone's core,
// on the blocking pool, against offline guessing of a short PIN.
fn argon2() -> Option<argon2::Argon2<'static>> {
    let params = argon2::Params::new(8 * 1024, 2, 1, Some(32)).ok()?;
    Some(argon2::Argon2::new(
        argon2::Algorithm::Argon2id,
        argon2::Version::V0x13,
        params,
    ))
}

fn argon2_hash(pin: &str, salt: &[u8]) -> Option<[u8; 32]> {
    let mut out = [0u8; 32];
    argon2()?
        .hash_password_into(pin.as_bytes(), salt, &mut out)
        .ok()?;
    Some(out)
}

fn write_pin(pin: &str) -> std::io::Result<()> {
    write_secret(&pin_path(), pin)
}

/// "argon2id:<salt>:<hash>", written owner-only and renamed into place.
fn write_secret(path: &Path, pin: &str) -> std::io::Result<()> {
    let mut salt = [0u8; 16];
    fs::File::open("/dev/urandom")?.read_exact(&mut salt)?;
    let hash = argon2_hash(pin, &salt).ok_or_else(|| std::io::Error::other("argon2"))?;
    let path = path.to_path_buf();
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir)?;
    }
    let tmp = path.with_extension("tmp");
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&tmp)?;
    file.write_all(format!("argon2id:{}:{}", hex(&salt), hex(&hash)).as_bytes())?;
    file.sync_all()?;
    fs::rename(tmp, path)
}

/// Checks a PIN against any format the shell has stored: Argon2id, the
/// earlier 10 000 rounds of salted SHA-256, or the first unsalted SHA-256.
fn verify_pin(pin: &str, stored: &str) -> bool {
    let parts: Vec<&str> = stored.split(':').collect();
    let (expected, computed) = match parts.as_slice() {
        ["argon2id", salt, hash] => (
            unhex(hash),
            unhex(salt)
                .and_then(|s| argon2_hash(pin, &s))
                .map(Vec::from),
        ),
        [salt, hash] => {
            let computed = unhex(salt).map(|salt| {
                let mut digest =
                    Sha256::digest([salt.as_slice(), pin.as_bytes()].concat()).to_vec();
                for _ in 1..10_000 {
                    digest = Sha256::digest(&digest).to_vec();
                }
                digest
            });
            (unhex(hash), computed)
        }
        [hash] if !hash.is_empty() => (unhex(hash), Some(Sha256::digest(pin.as_bytes()).to_vec())),
        _ => (None, None),
    };
    match (expected, computed) {
        (Some(a), Some(b)) => {
            a.len() == b.len() && a.iter().zip(&b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
        }
        _ => false,
    }
}

fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    bytes
        .iter()
        .flat_map(|b| [DIGITS[usize::from(b >> 4)], DIGITS[usize::from(b & 0xf)]])
        .map(char::from)
        .collect()
}

fn unhex(text: &str) -> Option<Vec<u8>> {
    if !text.len().is_multiple_of(2) {
        return None;
    }
    (0..text.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(text.get(i..i + 2)?, 16).ok())
        .collect()
}

/// The user the shell runs as, from its real uid and /etc/passwd.
fn current_user() -> String {
    let uid = fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|status| {
            status
                .lines()
                .find_map(|l| l.strip_prefix("Uid:"))
                .and_then(|ids| ids.split_whitespace().next().map(str::to_owned))
        });
    let passwd = fs::read_to_string("/etc/passwd").unwrap_or_default();
    uid.and_then(|uid| {
        passwd.lines().find_map(|line| {
            let mut fields = line.split(':');
            let name = fields.next()?;
            (fields.nth(1)? == uid).then(|| name.to_owned())
        })
    })
    .or_else(|| std::env::var("USER").ok())
    .unwrap_or_default()
}

/// Runs marathon-data-key (docs/ENCRYPTION.md) with `secret` on stdin; its
/// exit code, or `None` when it could not run. Without the helper (a desktop
/// session) there is no data partition to keep in step: `Some(0)`.
async fn run_data_key(command: &str, secret: &str) -> Option<i32> {
    match std::env::var("MARATHON_DATA_KEY_HELPER") {
        Ok(helper) if !helper.is_empty() => run(helper, vec![command.to_owned()], secret).await,
        _ if !Path::new(DATA_KEY_HELPER).exists() => Some(0),
        _ => run_helper(DATA_KEY_HELPER, command, secret).await,
    }
}

/// Runs `helper command` as root through pkexec with `secret` on stdin; its
/// exit code, or `None` when it could not run.
pub(crate) async fn run_helper(helper: &str, command: &str, secret: &str) -> Option<i32> {
    let args = vec![helper.to_owned(), command.to_owned()];
    run("pkexec".to_owned(), args, secret).await
}

async fn run(program: String, args: Vec<String>, secret: &str) -> Option<i32> {
    run_output(program, args, secret, false).await?.0
}

/// `run`, with what the program printed (when `capture`) and its errors.
async fn run_output(
    program: String,
    args: Vec<String>,
    secret: &str,
    capture: bool,
) -> Option<(Option<i32>, String, String)> {
    let secret = secret.to_owned();
    blocking::unblock(move || {
        let mut child = Command::new(&program)
            .args(&args)
            .stdin(Stdio::piped())
            .stdout(if capture {
                Stdio::piped()
            } else {
                Stdio::inherit()
            })
            .stderr(Stdio::piped())
            .spawn()
            .ok()?;
        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(secret.as_bytes()).ok();
        }
        let out = child.wait_with_output().ok()?;
        if !out.status.success() && !out.stderr.is_empty() {
            log::warn(
                "security",
                format_args!(
                    "{} {}: {}",
                    program,
                    args.join(" "),
                    String::from_utf8_lossy(&out.stderr).trim()
                ),
            );
        }
        Some((
            out.status.code(),
            String::from_utf8_lossy(&out.stdout).into_owned(),
            String::from_utf8_lossy(&out.stderr).into_owned(),
        ))
    })
    .await
}

/// Where the data partition's state is read from; tests point it elsewhere.
struct Probe {
    mount_info: PathBuf,
    sys_dev_block: PathBuf,
    state_file: PathBuf,
    data_partition: PathBuf,
}

impl Default for Probe {
    fn default() -> Self {
        Self {
            mount_info: "/proc/self/mountinfo".into(),
            sys_dev_block: "/sys/dev/block".into(),
            state_file: "/var/lib/marathon-data-key/state".into(),
            data_partition: "/dev/disk/by-partlabel/marathon_data".into(),
        }
    }
}

/// The encrypted data partition (docs/ENCRYPTION.md), as an unprivileged
/// process can tell. With the home directory on dm-crypt LUKS: "pin" when
/// marathon-data-key last made the quick PIN its startup passphrase, "open"
/// otherwise. Without: "off" when the image has a data partition that
/// erasing would encrypt, "none" when not.
fn data_encryption_state(home: &Path, probe: &Probe) -> &'static str {
    let read = |p: &Path| io::read::<String>(p).unwrap_or_default();
    let luks = device_of(home, &read(&probe.mount_info)).is_some_and(|device| {
        read(&probe.sys_dev_block.join(device).join("dm/uuid")).starts_with("CRYPT-LUKS")
    });
    if !luks {
        return if probe.data_partition.exists() {
            "off"
        } else {
            "none"
        };
    }
    if read(&probe.state_file) == "pin" {
        "pin"
    } else {
        "open"
    }
}

/// The major:minor of the mount that holds `path`; later lines are mounted
/// on top of earlier ones.
fn device_of<'a>(path: &Path, mount_info: &'a str) -> Option<&'a str> {
    let mut best: Option<(usize, &str)> = None;
    for line in mount_info.lines() {
        let fields: Vec<&str> = line.split(' ').collect();
        let (Some(device), Some(mount_point)) = (fields.get(2), fields.get(4)) else {
            continue;
        };
        let mount_point = unescape_mount_point(mount_point);
        if path.starts_with(&mount_point) && best.is_none_or(|(len, _)| mount_point.len() >= len) {
            best = Some((mount_point.len(), device));
        }
    }
    best.map(|(_, device)| device)
}

/// mountinfo writes space, tab, newline and backslash as \ooo.
fn unescape_mount_point(field: &str) -> String {
    let mut out = String::with_capacity(field.len());
    let mut rest = field;
    while let Some(i) = rest.find('\\') {
        out.push_str(&rest[..i]);
        let code = rest
            .get(i + 1..i + 4)
            .and_then(|o| u8::from_str_radix(o, 8).ok());
        if let Some(c) = code {
            out.push(char::from(c));
            rest = &rest[i + 4..];
        } else {
            out.push('\\');
            rest = &rest[i + 1..];
        }
    }
    out.push_str(rest);
    out
}

#[zbus::proxy(
    interface = "net.reactivated.Fprint.Manager",
    default_service = "net.reactivated.Fprint",
    default_path = "/net/reactivated/Fprint/Manager"
)]
trait FprintManager {
    fn get_default_device(&self) -> zbus::Result<OwnedObjectPath>;
}

#[zbus::proxy(
    interface = "net.reactivated.Fprint.Device",
    default_service = "net.reactivated.Fprint"
)]
trait FprintDevice {
    fn list_enrolled_fingers(&self, user: &str) -> zbus::Result<Vec<String>>;
    fn claim(&self, user: &str) -> zbus::Result<()>;
    fn release(&self) -> zbus::Result<()>;
    fn verify_start(&self, finger: &str) -> zbus::Result<()>;
    fn verify_stop(&self) -> zbus::Result<()>;
    #[zbus(signal)]
    fn verify_status(&self, result: &str, done: bool) -> zbus::Result<()>;
    #[zbus(property, name = "num-enroll-stages")]
    fn num_enroll_stages(&self) -> zbus::Result<i32>;
    #[zbus(property, name = "scan-type")]
    fn scan_type(&self) -> zbus::Result<String>;
}

async fn fprint_device(path: OwnedObjectPath) -> zbus::Result<FprintDeviceProxy<'static>> {
    FprintDeviceProxy::builder(&io::system_bus().await?)
        .path(path)
        .build()
        .await
}

/// What fprintd knows: its default device, the user's fingers on it, the
/// touches an enrolment takes and how a finger goes on the sensor.
#[derive(Default)]
struct Reader {
    path: Option<OwnedObjectPath>,
    fingers: Vec<String>,
    stages: i32,
    scan_type: String,
}

async fn read_reader(user: &str) -> Reader {
    let Ok(bus) = io::system_bus().await else {
        return Reader::default();
    };
    let path = async {
        FprintManagerProxy::new(&bus)
            .await?
            .get_default_device()
            .await
    };
    let Ok(path) = path.await else {
        return Reader::default();
    };
    let Ok(device) = fprint_device(path.clone()).await else {
        return Reader::default();
    };
    Reader {
        // fprintd answers NoEnrolledPrints rather than an empty list.
        fingers: device.list_enrolled_fingers(user).await.unwrap_or_default(),
        stages: device.num_enroll_stages().await.unwrap_or(0),
        scan_type: device.scan_type().await.unwrap_or_default(),
        path: Some(path),
    }
}

async fn refresh_fingerprints(qt: cxx_qt::CxxQtThread<Security>, user: String) {
    let reader = read_reader(&user).await;
    qt.queue(move |mut obj| {
        let mut rust = obj.as_mut().rust_mut();
        rust.reader = reader.path;
        rust.fingers = reader.fingers;
        rust.enroll_stages = reader.stages;
        rust.scan_type = reader.scan_type;
        obj.fingerprint_changed();
    })
    .ok();
}

// One claim on fprintd's device at a time: a new listener waits for the
// last one to release it.
static FPRINT_CLAIM: Mutex<()> = Mutex::new(());

/// Listens until an enrolled finger matches (`Ok(true)`) or `stop`
/// (`Ok(false)`); each miss goes to `fingerprint_missed`.
async fn listen_for_fingerprint(
    qt: &cxx_qt::CxxQtThread<Security>,
    path: OwnedObjectPath,
    user: &str,
    stop: async_channel::Receiver<()>,
) -> Result<bool, String> {
    let Some(_claim) = future::or(async { Some(FPRINT_CLAIM.lock().await) }, async {
        stop.recv().await.ok();
        None
    })
    .await
    else {
        return Ok(false);
    };
    let device = fprint_device(path).await.map_err(|e| e.to_string())?;
    if let Err(e) = device.claim(user).await {
        log::warn("security", format_args!("fingerprint claim: {e}"));
        return Err(fl!("fingerprint-busy"));
    }
    let matched = future::or(verify_until_match(qt, &device), async {
        stop.recv().await.ok();
        Ok(false)
    })
    .await;
    // Also when stopped mid-scan: fprintd keeps a claim until it is released.
    device.verify_stop().await.ok();
    device.release().await.ok();
    matched
}

async fn verify_until_match(
    qt: &cxx_qt::CxxQtThread<Security>,
    device: &FprintDeviceProxy<'static>,
) -> Result<bool, String> {
    let mut statuses = device
        .receive_verify_status()
        .await
        .map_err(|e| e.to_string())?;
    loop {
        if device.verify_start("any").await.is_err() {
            return Err(fl!("fingerprint-start-failed"));
        }
        loop {
            let Some(status) = statuses.next().await else {
                return Err(fl!("fingerprint-start-failed"));
            };
            let Ok(args) = status.args() else { continue };
            let prompt = match args.result {
                "verify-match" => return Ok(true),
                "verify-no-match" => break,
                "verify-disconnected" | "verify-unknown-error" => {
                    return Err(fl!("fingerprint-start-failed"));
                }
                "verify-retry-scan" => fl!("fingerprint-retry-scan"),
                "verify-swipe-too-short" => fl!("fingerprint-too-short"),
                "verify-finger-not-centered" => fl!("fingerprint-centre"),
                "verify-remove-and-retry" => fl!("fingerprint-remove"),
                _ => continue,
            };
            qt.queue(move |obj| obj.biometric_prompt(&QString::from(prompt)))
                .ok();
        }
        device.verify_stop().await.ok();
        qt.queue(Security::fingerprint_missed).ok();
    }
}

/// The helper's command line for `pkexec`.
fn fingerprint_helper(command: &str, finger: &str) -> Vec<String> {
    let mut args = vec![FINGERPRINT_HELPER.to_owned(), command.to_owned()];
    if !finger.is_empty() {
        args.push(finger.to_owned());
    }
    args
}

/// Enrols `finger` for the owner once `pin` is their quick PIN, telling
/// Settings each result as fprintd gives it. Err says why it didn't finish,
/// or is empty when it was stopped.
async fn enroll_fingerprint(
    qt: &cxx_qt::CxxQtThread<Security>,
    finger: &str,
    pin: String,
    stop: async_channel::Receiver<()>,
) -> Result<(), String> {
    let (has_pin, stages) = ipc::on_gui(qt, |obj| (obj.has_quick_pin, obj.enroll_stages))
        .await
        .map_err(|e| e.to_string())?;
    if !has_pin {
        return Err(fl!("fingerprint-needs-pin"));
    }
    confirm_owner(qt, pin).await?;
    let mut child = Command::new("pkexec")
        .args(fingerprint_helper("enroll", finger))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| fl!("fingerprint-enroll-failed", error = e.to_string()))?;
    // The helper stops the enrolment when its stdin closes.
    let mut stdin = child.stdin.take();
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| fl!("fingerprint-enroll-failed", error = "no output"))?;
    let mut lines = futures_lite::io::BufReader::new(blocking::Unblock::new(stdout)).lines();
    let (mut passed, mut last, mut cancelled) = (0, String::new(), false);
    loop {
        let line = future::or(async { Some(lines.next().await) }, async {
            stop.recv().await.ok();
            None
        })
        .await;
        let Some(Some(Ok(result))) = line else {
            cancelled = line.is_none();
            break;
        };
        if result == "enroll-stage-passed" {
            passed += 1;
        }
        ipc::signal(
            "Security",
            "FingerprintEnrollStatus",
            (result.clone(), passed, stages),
        );
        last = result;
    }
    drop(stdin.take());
    while lines.next().await.is_some() {}
    let out = blocking::unblock(move || child.wait_with_output())
        .await
        .map_err(|e| fl!("fingerprint-enroll-failed", error = e.to_string()))?;
    match last.as_str() {
        "enroll-completed" => Ok(()),
        _ if cancelled => Err(String::new()),
        "enroll-duplicate" => Err(fl!("fingerprint-duplicate")),
        "enroll-data-full" => Err(fl!("fingerprint-full")),
        "enroll-disconnected" => Err(fl!("fingerprint-disconnected")),
        "" => {
            let error = String::from_utf8_lossy(&out.stderr).trim().to_owned();
            log::warn("security", format_args!("fingerprint enrol: {error}"));
            Err(fl!("fingerprint-enroll-failed", error = error))
        }
        _ => Err(fl!("fingerprint-enroll-failed", error = last)),
    }
}

/// Deletes `finger`, or every finger when it is empty, after the PIN.
async fn delete_fingerprints(
    qt: &cxx_qt::CxxQtThread<Security>,
    finger: &str,
    pin: String,
) -> Result<(), String> {
    confirm_owner(qt, pin).await?;
    match run(
        "pkexec".to_owned(),
        fingerprint_helper("delete", finger),
        "",
    )
    .await
    {
        Some(0) => Ok(()),
        _ => Err(fl!("fingerprint-delete-failed")),
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::{data_encryption_state, hex, verify_pin, Probe};
    use sha2::{Digest, Sha256};
    use std::fs;
    use std::path::Path;

    #[test]
    fn every_stored_pin_format_verifies() {
        let salt = [7u8; 16];
        let argon = format!(
            "argon2id:{}:{}",
            hex(&salt),
            hex(&super::argon2_hash("135724", &salt).unwrap())
        );
        assert!(verify_pin("135724", &argon));
        assert!(!verify_pin("135725", &argon));

        let mut digest = Sha256::digest([salt.as_slice(), b"2468"].concat()).to_vec();
        for _ in 1..10_000 {
            digest = Sha256::digest(&digest).to_vec();
        }
        let salted = format!("{}:{}", hex(&salt), hex(&digest));
        assert!(verify_pin("2468", &salted));
        assert!(!verify_pin("2469", &salted));

        let plain = hex(&Sha256::digest(b"1111"));
        assert!(verify_pin("1111", &plain));
        assert!(!verify_pin("1112", &plain));
        assert!(!verify_pin("1111", ""));
        assert!(!verify_pin("1111", "argon2id:zz:00"));
    }

    struct Sandbox(tempfile::TempDir);

    impl Sandbox {
        fn new() -> Self {
            let s = Self(tempfile::tempdir().unwrap());
            s.write("marathon_data", "");
            // A/B Pi: / is the slot, /var the LUKS data partition, /home bound from it.
            s.write(
                "mountinfo",
                "22 1 179:4 / / rw,relatime - ext4 /dev/mmcblk0p4 rw\n\
                 30 22 253:0 / /var rw,noatime - ext4 /dev/mapper/marathon_data rw\n\
                 31 22 253:0 /home /home rw,noatime - ext4 /dev/mapper/marathon_data rw\n\
                 32 22 0:30 / /home/user/mnt\\040x rw - tmpfs tmpfs rw\n",
            );
            s.write("sys/253:0/dm/uuid", "CRYPT-LUKS2-0a1b2c3d-marathon_data\n");
            s.write("sys/179:4/dev", "179:4\n");
            s
        }

        fn write(&self, name: &str, contents: &str) {
            let path = self.0.path().join(name);
            fs::create_dir_all(path.parent().unwrap()).unwrap();
            fs::write(path, contents).unwrap();
        }

        fn remove(&self, name: &str) {
            let path = self.0.path().join(name);
            fs::remove_dir_all(&path)
                .or_else(|_| fs::remove_file(&path))
                .ok();
        }

        fn state(&self, home: &str) -> &'static str {
            let dir = self.0.path();
            let probe = Probe {
                mount_info: dir.join("mountinfo"),
                sys_dev_block: dir.join("sys"),
                state_file: dir.join("state"),
                data_partition: dir.join("marathon_data"),
            };
            data_encryption_state(Path::new(home), &probe)
        }
    }

    #[test]
    fn open_until_a_pin_is_set() {
        let s = Sandbox::new();
        assert_eq!(s.state("/home/user"), "open");
        s.write("state", "open\n");
        assert_eq!(s.state("/home/user"), "open");
        s.write("state", "pin\n");
        assert_eq!(s.state("/home/user"), "pin");
    }

    #[test]
    fn home_on_a_plain_partition_is_off() {
        let s = Sandbox::new();
        s.write("sys/253:0/dm/uuid", "LVM-abc\n");
        s.write("state", "pin\n");
        assert_eq!(s.state("/home/user"), "off");
        s.remove("sys/253:0");
        assert_eq!(s.state("/home/user"), "off");
    }

    #[test]
    fn the_longest_mount_point_wins() {
        let s = Sandbox::new();
        s.write("sys/0:30/dm/uuid", "");
        assert_eq!(s.state("/home/user/mnt x/file"), "off");
        assert_eq!(s.state("/home/user/mntx"), "open");
        assert_eq!(s.state("/root"), "off");
    }

    #[test]
    fn no_mount_info_is_off() {
        let s = Sandbox::new();
        s.remove("mountinfo");
        assert_eq!(s.state("/home/user"), "off");
    }

    #[test]
    fn no_data_partition_is_none() {
        let s = Sandbox::new();
        s.remove("marathon_data");
        s.remove("sys/253:0");
        assert_eq!(s.state("/home/user"), "none");
        s.write("sys/253:0/dm/uuid", "CRYPT-LUKS2-0a1b2c3d-root\n");
        assert_eq!(s.state("/home/user"), "open");
    }
}
