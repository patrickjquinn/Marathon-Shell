//! `SecurityManagerCpp`: the quick PIN, the system password through PAM,
//! the fingerprint reader, the lockout and the data partition's startup PIN.
//! Hashing, PAM and the data-key helper run on the blocking pool and fprintd
//! on the I/O thread; the GUI thread only keeps the state QML binds to.

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
use futures_lite::{future, StreamExt};
use sha2::{Digest, Sha256};
use zbus::fdo;
use zbus::message::Header;
use zbus::zvariant::OwnedObjectPath;

use crate::audit::{self, Severity};
use crate::ipc::{self, value, State};
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
        #[qproperty(bool, fingerprint_available, cxx_name = "fingerprintAvailable", READ = fingerprint_available, NOTIFY = fingerprint_available_changed)]
        #[qproperty(bool, is_locked_out, cxx_name = "isLockedOut", READ = is_locked_out, NOTIFY = lockout_state_changed)]
        #[qproperty(i32, lockout_seconds_remaining, cxx_name = "lockoutSecondsRemaining", READ = lockout_seconds_remaining, NOTIFY = lockout_state_changed)]
        #[qproperty(i32, failed_attempts, cxx_name = "failedAttempts", READ, NOTIFY = failed_attempts_changed)]
        /// "none", "off", "open" or "pin": see `data_encryption_state`.
        #[qproperty(QString, data_encryption, cxx_name = "dataEncryption", READ, NOTIFY = data_encryption_changed)]
        /// The PIN was typed at startup to unlock the data; the lock screen
        /// needn't ask again this boot.
        #[qproperty(bool, boot_unlocked, cxx_name = "bootUnlocked", READ, NOTIFY = boot_unlocked_changed)]
        type Security = super::SecurityRust;

        #[cxx_name = "authMode"]
        fn auth_mode(self: &Security) -> i32;
        #[cxx_name = "fingerprintAvailable"]
        fn fingerprint_available(self: &Security) -> bool;
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
        #[cxx_name = "fingerprintAvailableChanged"]
        fn fingerprint_available_changed(self: Pin<&mut Self>);
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
        #[cxx_name = "biometricPrompt"]
        fn biometric_prompt(self: Pin<&mut Self>, message: &QString);

        #[qinvokable]
        #[cxx_name = "authenticatePassword"]
        fn authenticate_password(self: Pin<&mut Security>, password: &QString);
        #[qinvokable]
        #[cxx_name = "authenticateQuickPIN"]
        fn authenticate_quick_pin(self: Pin<&mut Security>, pin: &QString);
        /// `kind` 0 is the fingerprint, the only one there is.
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
const LOCKOUT: Duration = Duration::from_secs(300);
const DATA_KEY_HELPER: &str = "/usr/libexec/marathon-data-key";
/// The root service that erases the device at the next boot, on images that can.
const FACTORY_RESET: &str = "/run/marathon/factory-reset.sock";

#[derive(Default)]
pub struct SecurityRust {
    has_quick_pin: bool,
    fingerprint: Option<OwnedObjectPath>,
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
}

/// What an attempt checked, for the messages and the audit log.
#[derive(Clone, Copy)]
enum Secret {
    Pin,
    Password,
    Fingerprint,
}

impl cxx_qt::Initialize for Security {
    fn initialize(mut self: Pin<&mut Self>) {
        // Read once at startup: the lock screen decides from these at once.
        let user = current_user();
        let home = std::env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_default();
        let encryption = data_encryption_state(&home, &Probe::default());
        {
            let mut rust = self.as_mut().rust_mut();
            rust.has_quick_pin = !stored_pin().is_empty();
            rust.data_encryption = QString::from(encryption);
            rust.user.clone_from(&user);
        }
        let push = |obj: Pin<&mut Self>| ipc::signal("Security", "StateChanged", (state(&obj),));
        self.as_mut().on_auth_mode_changed(push).release();
        self.as_mut()
            .on_fingerprint_available_changed(push)
            .release();
        self.as_mut().on_lockout_state_changed(push).release();
        self.as_mut().on_failed_attempts_changed(push).release();
        self.as_mut().on_data_encryption_changed(push).release();
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
        io::spawn(find_fingerprint_reader(qt.clone(), user));
        if encryption == "pin" {
            // The initramfs leaves a note when the PIN was typed there.
            io::spawn(async move {
                if run_data_key("consume-boot-unlock", "").await == Some(0) {
                    qt.queue(|mut obj| {
                        obj.as_mut().rust_mut().boot_unlocked = true;
                        obj.boot_unlocked_changed();
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
        self.fingerprint.is_some()
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
        kind == 0 && self.fingerprint.is_some()
    }

    fn fail(self: Pin<&mut Self>, reason: &str) {
        self.authentication_failed(&QString::from(reason));
    }

    // Why the attempt can't start, if it can't.
    fn refuse(&self, secret: &str) -> Option<String> {
        if self.is_locked_out() {
            Some(format!(
                "Account locked. Try again in {} seconds.",
                self.lockout_seconds_remaining()
            ))
        } else if secret.is_empty() {
            Some("PIN cannot be empty".to_owned())
        } else if self.checking {
            Some("Authentication already in progress".to_owned())
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

    fn authenticate_password(mut self: Pin<&mut Self>, password: &QString) {
        let password = password.to_string();
        if password.is_empty() {
            return self.fail("Password cannot be empty");
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
        };
        if ok {
            self.as_mut().reset_lockout();
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
            format!("Too many failed attempts. Locked for {seconds} seconds.")
        } else if matches!(secret, Secret::Fingerprint) {
            "Fingerprint not recognized".to_owned()
        } else {
            let incorrect = if matches!(secret, Secret::Pin) {
                "Incorrect PIN"
            } else {
                "Incorrect password"
            };
            format!(
                "{incorrect} ({} attempts remaining)",
                MAX_ATTEMPTS - self.failed_attempts
            )
        })
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
                qt.queue(|obj| obj.fail("System password incorrect. Cannot set Quick PIN."))
                    .ok();
                return;
            }
            // The startup PIN changes first, so a failure leaves both on the old PIN.
            let helper = run_data_key("set", &pin).await;
            queue_encryption(&qt);
            if !helper_ok(helper) {
                qt.queue(|obj| {
                    obj.fail("Couldn't change the PIN that unlocks your data at startup");
                })
                .ok();
                return;
            }
            let stored = store_pin(pin).await;
            qt.queue(move |obj| obj.pin_stored(stored)).ok();
        });
    }

    fn set_quick_pin_first_run(mut self: Pin<&mut Self>, pin: &QString) -> bool {
        // Only while no PIN is set: later changes need the password.
        if self.has_quick_pin {
            log::warn("security", "first-run PIN refused: a PIN is set");
            return false;
        }
        let pin = pin.to_string();
        if pin.chars().count() < 4 {
            return false;
        }
        self.as_mut().pin_stored(true);
        let qt = self.qt_thread();
        io::spawn(async move {
            if !store_pin(pin.clone()).await {
                qt.queue(|obj| obj.pin_stored(false)).ok();
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
        let (password, user, qt) = (
            system_password.to_string(),
            self.user.clone(),
            self.qt_thread(),
        );
        io::spawn(async move {
            if !password_ok(user, password).await {
                qt.queue(|obj| obj.fail("System password incorrect. Cannot remove Quick PIN."))
                    .ok();
                return;
            }
            let helper = run_data_key("clear", "").await;
            queue_encryption(&qt);
            if !helper_ok(helper) {
                qt.queue(|obj| {
                    obj.fail("Couldn't turn off the PIN that unlocks your data at startup");
                })
                .ok();
                return;
            }
            let _guard = PIN_FILE.lock().await;
            if let Err(e) = fs::remove_file(pin_path()) {
                log::warn("security", format_args!("removing the PIN: {e}"));
            }
            qt.queue(|mut obj| {
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
            let refusal = format!(
                "Too many failed attempts. Try again in {} seconds.",
                self.lockout_seconds_remaining()
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
                        format!(
                            "Too many failed attempts. Try again in {} seconds.",
                            obj.lockout_seconds_remaining()
                        )
                    }
                    Some(_) if pin => "Incorrect PIN".to_owned(),
                    Some(_) => "Incorrect password".to_owned(),
                };
                answer(obj, refusal);
            })
            .ok();
        });
    }

    fn authenticate_biometric(mut self: Pin<&mut Self>, kind: i32) {
        if kind != 0 {
            return self.fail("Biometric type not supported");
        }
        if self.is_locked_out() {
            let refusal = format!(
                "Account locked. Try again in {} seconds.",
                self.lockout_seconds_remaining()
            );
            return self.fail(&refusal);
        }
        let Some(device) = self.fingerprint.clone() else {
            return self.fail("Fingerprint not available");
        };
        if self.stop_fingerprint.is_some() {
            return;
        }
        let (stop, stopped) = async_channel::bounded(1);
        self.as_mut().rust_mut().stop_fingerprint = Some(stop);
        let (qt, user) = (self.qt_thread(), self.user.clone());
        io::spawn(async move {
            let result = future::or(verify_fingerprint(&qt, device, &user), async {
                stopped.recv().await.ok();
                Ok(None)
            })
            .await;
            qt.queue(move |mut obj| {
                obj.as_mut().rust_mut().stop_fingerprint = None;
                match result {
                    Ok(Some(ok)) => obj.finish(ok, Secret::Fingerprint),
                    Ok(None) => {}
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
            "fingerprintAvailable".to_owned(),
            value(security.fingerprint_available()),
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
    ])
}

/// Once the owner's secret checks out, asks the service for an erase; it
/// restarts the device. Err says why not.
async fn erase(qt: &cxx_qt::CxxQtThread<Security>, secret: String) -> Result<(), String> {
    if !Path::new(FACTORY_RESET).exists() {
        return Err("This device can't erase itself".into());
    }
    let (tx, rx) = async_channel::bounded(1);
    ipc::on_gui(qt, move |obj| {
        obj.check_owner(secret, move |_, refusal| {
            tx.try_send(refusal).ok();
        });
    })
    .await
    .map_err(|e| e.to_string())?;
    let refusal = rx.recv().await.map_err(|e| e.to_string())?;
    if !refusal.is_empty() {
        return Err(refusal);
    }
    let reply = blocking::unblock(|| {
        let mut socket = UnixStream::connect(FACTORY_RESET)?;
        socket.write_all(b"erase\n")?;
        let mut reply = String::new();
        socket.read_to_string(&mut reply)?;
        Ok::<_, std::io::Error>(reply)
    })
    .await
    .map_err(|e| format!("Couldn't reach the erase service: {e}"))?;
    match reply.trim() {
        "ok" => Ok(()),
        "" => Err("Couldn't reach the erase service: it closed the connection".into()),
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
            h.sender()
                .map(zbus::names::UniqueName::as_str)
                .unwrap_or_default(),
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
}

fn helper_ok(code: Option<i32>) -> bool {
    // 3: the data partition is not encrypted; the quick PIN stands alone.
    matches!(code, Some(0 | 3))
}

fn queue_encryption(qt: &cxx_qt::CxxQtThread<Security>) {
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_default();
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

fn stored_pin() -> String {
    io::read(pin_path()).unwrap_or_default()
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

/// "argon2id:<salt>:<hash>", written owner-only and renamed into place.
fn write_pin(pin: &str) -> std::io::Result<()> {
    let mut salt = [0u8; 16];
    fs::File::open("/dev/urandom")?.read_exact(&mut salt)?;
    let hash = argon2_hash(pin, &salt).ok_or_else(|| std::io::Error::other("argon2"))?;
    let path = pin_path();
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
    let (program, args) = match std::env::var("MARATHON_DATA_KEY_HELPER") {
        Ok(helper) if !helper.is_empty() => (helper, vec![command.to_owned()]),
        _ if !Path::new(DATA_KEY_HELPER).exists() => return Some(0),
        _ => (
            "pkexec".to_owned(),
            vec![DATA_KEY_HELPER.to_owned(), command.to_owned()],
        ),
    };
    let secret = secret.to_owned();
    blocking::unblock(move || {
        let mut child = Command::new(&program)
            .args(&args)
            .stdin(Stdio::piped())
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
                    "marathon-data-key {}: {}",
                    args.join(" "),
                    String::from_utf8_lossy(&out.stderr).trim()
                ),
            );
        }
        out.status.code()
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
}

async fn fprint_device(path: OwnedObjectPath) -> zbus::Result<FprintDeviceProxy<'static>> {
    FprintDeviceProxy::builder(&io::system_bus().await?)
        .path(path)?
        .build()
        .await
}

// A reader with an enrolled finger; none on most devices.
async fn find_fingerprint_reader(qt: cxx_qt::CxxQtThread<Security>, user: String) {
    let found = async {
        let bus = io::system_bus().await.ok()?;
        let path = FprintManagerProxy::new(&bus)
            .await
            .ok()?
            .get_default_device()
            .await
            .ok()?;
        let fingers = fprint_device(path.clone())
            .await
            .ok()?
            .list_enrolled_fingers(&user)
            .await
            .ok()?;
        (!fingers.is_empty()).then_some(path)
    }
    .await;
    if found.is_some() {
        qt.queue(move |mut obj| {
            obj.as_mut().rust_mut().fingerprint = found;
            obj.fingerprint_available_changed();
        })
        .ok();
    }
}

/// One verification: `Some(matched)`, or why it could not start.
async fn verify_fingerprint(
    qt: &cxx_qt::CxxQtThread<Security>,
    path: OwnedObjectPath,
    user: &str,
) -> Result<Option<bool>, String> {
    let device = fprint_device(path).await.map_err(|e| e.to_string())?;
    let mut statuses = device
        .receive_verify_status()
        .await
        .map_err(|e| e.to_string())?;
    if let Err(e) = device.claim(user).await {
        log::warn("security", format_args!("fingerprint claim: {e}"));
        return Err("Fingerprint device busy".to_owned());
    }
    if device.verify_start("any").await.is_err() {
        device.release().await.ok();
        return Err("Fingerprint verification failed to start".to_owned());
    }
    qt.queue(|obj| obj.biometric_prompt(&QString::from("Place your finger on the sensor")))
        .ok();
    let mut matched = None;
    while let Some(status) = statuses.next().await {
        let Ok(args) = status.args() else { continue };
        let prompt = match args.result {
            "verify-match" => {
                matched = Some(true);
                break;
            }
            "verify-no-match" => {
                matched = Some(false);
                break;
            }
            "verify-retry-scan" => "Scan quality poor, try again",
            "verify-swipe-too-short" => "Swipe too short, try again",
            "verify-finger-not-centered" => "Center your finger and try again",
            "verify-remove-and-retry" => "Remove finger and try again",
            _ => continue,
        };
        qt.queue(move |obj| obj.biometric_prompt(&QString::from(prompt)))
            .ok();
    }
    device.verify_stop().await.ok();
    device.release().await.ok();
    Ok(matched)
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
