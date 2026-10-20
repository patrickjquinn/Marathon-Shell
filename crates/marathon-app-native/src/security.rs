//! `Security`: the shell's Security1, the PIN, authentication and erasing
//! the device, for system apps.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

use crate::shell::{get, mirror, relay, Service, Update};
use marathon_rt::io;

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(i32, auth_mode, cxx_name = "authMode", READ, NOTIFY = state_changed)]
        #[qproperty(bool, has_quick_pin, cxx_name = "hasQuickPIN", READ, NOTIFY = state_changed)]
        #[qproperty(bool, fingerprint_available, cxx_name = "fingerprintAvailable", READ, NOTIFY = state_changed)]
        #[qproperty(bool, is_locked_out, cxx_name = "isLockedOut", READ, NOTIFY = state_changed)]
        #[qproperty(i32, lockout_seconds_remaining, cxx_name = "lockoutSecondsRemaining", READ, NOTIFY = state_changed)]
        #[qproperty(i32, failed_attempts, cxx_name = "failedAttempts", READ, NOTIFY = state_changed)]
        #[qproperty(bool, can_erase_all_content, cxx_name = "canEraseAllContent", READ, NOTIFY = state_changed)]
        #[qproperty(QString, data_encryption, cxx_name = "dataEncryption", READ, NOTIFY = state_changed)]
        type Security = super::SecurityRust;

        #[qsignal]
        #[cxx_name = "stateChanged"]
        fn state_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "authenticationFailed"]
        fn authentication_failed(self: Pin<&mut Self>, reason: &QString);
        #[qsignal]
        #[cxx_name = "authenticationSuccess"]
        fn authentication_success(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "quickPINChanged"]
        fn quick_pin_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "eraseFailed"]
        fn erase_failed(self: Pin<&mut Self>, reason: &QString);

        #[qinvokable]
        #[cxx_name = "setQuickPIN"]
        fn set_quick_pin(self: &Security, pin: &QString, system_password: &QString);
        #[qinvokable]
        #[cxx_name = "removeQuickPIN"]
        fn remove_quick_pin(self: &Security, system_password: &QString);
        #[qinvokable]
        #[cxx_name = "authenticatePassword"]
        fn authenticate_password(self: &Security, password: &QString);
        #[qinvokable]
        #[cxx_name = "authenticateQuickPIN"]
        fn authenticate_quick_pin(self: &Security, pin: &QString);
        #[qinvokable]
        #[cxx_name = "authenticateBiometric"]
        fn authenticate_biometric(self: &Security, kind: i32);
        #[qinvokable]
        #[cxx_name = "cancelAuthentication"]
        fn cancel_authentication(self: &Security);
        #[qinvokable]
        #[cxx_name = "resetLockout"]
        fn reset_lockout(self: &Security);
        #[qinvokable]
        #[cxx_name = "isBiometricEnrolled"]
        fn is_biometric_enrolled(self: &Security, kind: i32) -> bool;
        #[qinvokable]
        #[cxx_name = "currentUsername"]
        fn current_username(self: &Security) -> QString;
        /// Answers only by `eraseFailed`: on success the device restarts.
        #[qinvokable]
        #[cxx_name = "eraseAllContent"]
        fn erase_all_content(self: &Security, secret: &QString);
    }

    impl cxx_qt::Threading for Security {}
    impl cxx_qt::Initialize for Security {}
}

use qobject::Security;

const SECURITY: Service = Service("Security");

#[derive(Default)]
#[allow(clippy::struct_excessive_bools, reason = "the QML properties")]
pub struct SecurityRust {
    auth_mode: i32,
    has_quick_pin: bool,
    fingerprint_available: bool,
    is_locked_out: bool,
    lockout_seconds_remaining: i32,
    failed_attempts: i32,
    can_erase_all_content: bool,
    data_encryption: QString,
}

impl cxx_qt::Initialize for Security {
    fn initialize(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().data_encryption = QString::from("none");
        let qt = self.qt_thread();
        relay(qt.clone(), SECURITY, "AuthenticationFailed", |obj, (r,): (String,)| {
            obj.authentication_failed(&QString::from(&r));
        });
        relay(qt.clone(), SECURITY, "AuthenticationSuccess", |obj, ()| obj.authentication_success());
        relay(qt.clone(), SECURITY, "QuickPINChanged", |obj, ()| obj.quick_pin_changed());
        relay(qt.clone(), SECURITY, "EraseFailed", |obj, (r,): (String,)| obj.erase_failed(&QString::from(&r)));
        mirror(qt, SECURITY, "system", |mut obj, update| {
            let Update::State(s) = update else { return };
            let mut x = obj.as_mut().rust_mut();
            x.auth_mode = get(&s, "authMode");
            x.has_quick_pin = get(&s, "hasQuickPIN");
            x.fingerprint_available = get(&s, "fingerprintAvailable");
            x.is_locked_out = get(&s, "isLockedOut");
            x.lockout_seconds_remaining = get(&s, "lockoutSecondsRemaining");
            x.failed_attempts = get(&s, "failedAttempts");
            x.can_erase_all_content = get(&s, "canEraseAllContent");
            x.data_encryption = s.get("dataEncryption").map_or_else(|| QString::from("none"), |_| get(&s, "dataEncryption"));
            obj.state_changed();
        });
    }
}

impl Security {
    crate::shell::calls! { SECURITY;
        set_quick_pin(pin: &QString, system_password: &QString) => "SetQuickPIN";
        remove_quick_pin(system_password: &QString) => "RemoveQuickPIN";
        authenticate_password(password: &QString) => "AuthenticatePassword";
        authenticate_quick_pin(pin: &QString) => "AuthenticateQuickPIN";
        authenticate_biometric(kind: i32) => "AuthenticateBiometric";
        cancel_authentication() => "CancelAuthentication";
        reset_lockout() => "ResetLockout";
    }
    crate::shell::asks! { SECURITY;
        is_biometric_enrolled(kind: i32) -> bool => "IsBiometricEnrolled";
        current_username() -> QString => "CurrentUsername";
    }

    fn erase_all_content(&self, secret: &QString) {
        let (qt, secret) = (self.qt_thread(), secret.to_string());
        io::spawn(async move {
            if let Err(e) = SECURITY.reply("EraseAllContent", &(secret,)).await {
                let reason = QString::from(&crate::shell::message(&e));
                qt.queue(move |obj| obj.erase_failed(&reason)).ok();
            }
        });
    }
}
