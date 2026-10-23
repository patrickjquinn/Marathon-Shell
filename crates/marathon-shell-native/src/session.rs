//! `Session` (QML `SessionStore`): locked or not, and the lock screen's
//! transitions. Unlocking within `lockDelay` seconds of locking skips the PIN.

use std::pin::Pin;
use std::time::Duration;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

use crate::{io, log};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, is_locked, cxx_name = "isLocked", READ, WRITE = set_is_locked, NOTIFY)]
        #[qproperty(
            bool,
            is_on_lock_screen,
            cxx_name = "isOnLockScreen",
            READ,
            WRITE,
            NOTIFY
        )]
        #[qproperty(
            bool,
            show_lock_screen,
            cxx_name = "showLockScreen",
            READ,
            WRITE,
            NOTIFY
        )]
        #[qproperty(
            bool,
            is_animating_lock,
            cxx_name = "isAnimatingLock",
            READ,
            WRITE,
            NOTIFY
        )]
        #[qproperty(
            QString,
            lock_transition,
            cxx_name = "lockTransition",
            READ,
            WRITE,
            NOTIFY
        )]
        /// Seconds after locking during which unlocking skips the PIN.
        #[qproperty(i32, lock_delay, cxx_name = "lockDelay", READ, WRITE = set_lock_delay, NOTIFY)]
        type Session = super::SessionRust;

        #[cxx_name = "setIsLocked"]
        fn set_is_locked(self: Pin<&mut Session>, locked: bool);
        #[cxx_name = "setLockDelay"]
        fn set_lock_delay(self: Pin<&mut Session>, seconds: i32);

        #[qinvokable]
        fn lock(self: Pin<&mut Session>);
        #[qinvokable]
        fn unlock(self: Pin<&mut Session>);
        /// Within `lockDelay` of locking.
        #[qinvokable]
        #[cxx_name = "checkSession"]
        fn check_session(self: &Session) -> bool;
        #[qinvokable]
        #[cxx_name = "showLock"]
        fn show_lock(self: Pin<&mut Session>);
        #[qinvokable]
        fn reset(self: Pin<&mut Session>);

        #[qsignal]
        #[cxx_name = "lockStateChanging"]
        fn lock_state_changing(self: Pin<&mut Session>, to_locked: bool);
        #[qsignal]
        #[cxx_name = "lockStateChanged"]
        fn lock_state_changed(self: Pin<&mut Session>, is_locked: bool);
        #[qsignal]
        #[cxx_name = "triggerShakeAnimation"]
        fn trigger_shake_animation(self: Pin<&mut Session>);
        #[qsignal]
        #[cxx_name = "triggerUnlockAnimation"]
        fn trigger_unlock_animation(self: Pin<&mut Session>);
    }

    impl cxx_qt::Threading for Session {}
}

use qobject::Session;

/// The lock screen's animation.
const SETTLE: Duration = Duration::from_millis(300);

#[allow(clippy::struct_excessive_bools, reason = "the QML properties")]
pub struct SessionRust {
    is_locked: bool,
    is_on_lock_screen: bool,
    show_lock_screen: bool,
    is_animating_lock: bool,
    lock_transition: QString,
    lock_delay: i32,
    /// On the boot clock, which counts through suspend.
    valid_until_ms: i64,
    /// The pending transition: its target, and a turn a later one bumps.
    settling: Option<bool>,
    turn: u64,
}

impl Default for SessionRust {
    fn default() -> Self {
        Self {
            is_locked: true,
            is_on_lock_screen: false,
            show_lock_screen: true,
            is_animating_lock: false,
            lock_transition: QString::default(),
            lock_delay: 0,
            valid_until_ms: 0,
            settling: None,
            turn: 0,
        }
    }
}

fn boot_ms() -> i64 {
    let mut ts = libc::timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    // SAFETY: `ts` is valid writable storage for the duration of the call.
    let rc = unsafe { libc::clock_gettime(libc::CLOCK_BOOTTIME, &raw mut ts) };
    if rc != 0 {
        log::warn(
            "session",
            format_args!(
                "reading CLOCK_BOOTTIME: {}",
                std::io::Error::last_os_error()
            ),
        );
        return 0;
    }
    ts.tv_sec * 1000 + ts.tv_nsec / 1_000_000
}

impl Session {
    fn set_is_locked(mut self: Pin<&mut Self>, locked: bool) {
        if self.is_locked == locked {
            return;
        }
        let delay = i64::from(self.lock_delay);
        let mut rust = self.as_mut().rust_mut();
        rust.is_locked = locked;
        rust.valid_until_ms = if locked && delay > 0 {
            boot_ms() + delay * 1000
        } else {
            0
        };
        self.is_locked_changed();
    }

    fn set_lock_delay(mut self: Pin<&mut Self>, seconds: i32) {
        set!(self, lock_delay, lock_delay_changed, seconds.max(0));
    }

    fn transition(mut self: Pin<&mut Self>, to_locked: bool) {
        self.as_mut()
            .set_lock_transition(QString::from(if to_locked {
                "locking"
            } else {
                "unlocking"
            }));
        self.as_mut().set_is_animating_lock(true);
        self.as_mut().lock_state_changing(to_locked);
        let turn = {
            let mut rust = self.as_mut().rust_mut();
            rust.turn += 1;
            rust.settling = Some(to_locked);
            rust.turn
        };
        let qt = self.qt_thread();
        io::spawn(async move {
            async_io::Timer::after(SETTLE).await;
            qt.queue(move |mut obj| {
                if obj.turn == turn {
                    obj.as_mut().settle();
                }
            })
            .ok();
        });
    }

    fn settle(mut self: Pin<&mut Self>) {
        let Some(locked) = self.as_mut().rust_mut().settling.take() else {
            return;
        };
        self.as_mut().set_is_locked(locked);
        self.as_mut().set_is_animating_lock(false);
        self.as_mut().set_lock_transition(QString::default());
        self.lock_state_changed(locked);
    }

    fn cancel(mut self: Pin<&mut Self>) {
        let mut rust = self.as_mut().rust_mut();
        rust.settling = None;
        rust.turn += 1;
    }

    fn lock(mut self: Pin<&mut Self>) {
        if self.is_locked {
            return;
        }
        self.as_mut().set_show_lock_screen(true);
        self.transition(true);
    }

    /// A lock still settling (auto-lock, the power key) is cancelled first:
    /// left running it would lock the session again under the home screen.
    fn unlock(mut self: Pin<&mut Self>) {
        if self.settling == Some(true) {
            self.as_mut().cancel();
            self.as_mut().set_is_animating_lock(false);
            self.as_mut().set_lock_transition(QString::default());
        }
        self.as_mut().set_show_lock_screen(false);
        if self.settling == Some(false) || !self.is_locked {
            self.set_is_on_lock_screen(false);
            return;
        }
        self.transition(false);
    }

    fn check_session(&self) -> bool {
        self.valid_until_ms > boot_ms()
    }

    fn show_lock(self: Pin<&mut Self>) {
        self.set_show_lock_screen(true);
    }

    /// `MARATHON_NO_INITIAL_LOCK` starts unlocked (headless and VM runs).
    fn reset(mut self: Pin<&mut Self>) {
        self.as_mut().cancel();
        self.as_mut().set_is_animating_lock(false);
        self.as_mut().set_lock_transition(QString::default());
        let lock = std::env::var_os("MARATHON_NO_INITIAL_LOCK").is_none_or(|v| v.is_empty());
        self.as_mut().set_show_lock_screen(lock);
        self.as_mut().set_is_locked(lock);
        self.as_mut().rust_mut().valid_until_ms = 0;
        self.set_is_on_lock_screen(false);
    }
}
