//! `Haptics`: the shell's Haptic1, the vibration motor.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QVariant};

use crate::shell::Service;
use crate::variant;
use marathon_rt::io;

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, available, READ, NOTIFY)]
        type Haptics = super::HapticsRust;

        #[qinvokable]
        fn light(self: &Haptics);
        #[qinvokable]
        fn medium(self: &Haptics);
        #[qinvokable]
        fn heavy(self: &Haptics);
        #[qinvokable]
        fn vibrate(self: &Haptics, duration: i32);
        /// Durations in ms, alternately on and off; `repeat` is not used.
        #[qinvokable]
        #[cxx_name = "vibratePattern"]
        fn vibrate_pattern(self: &Haptics, pattern: &QList_QVariant, repeat: i32);
        #[qinvokable]
        #[cxx_name = "stopVibration"]
        fn stop_vibration(self: &Haptics);
    }

    impl cxx_qt::Threading for Haptics {}
    impl cxx_qt::Initialize for Haptics {}
}

use qobject::Haptics;

const HAPTIC: Service = Service("Haptic");

#[derive(Default)]
pub struct HapticsRust {
    available: bool,
}

impl cxx_qt::Initialize for Haptics {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        io::spawn(async move {
            if let Ok(available) = HAPTIC.ask::<_, bool>("IsAvailable", &()).await {
                qt.queue(move |mut obj| set!(obj, available, available_changed, available)).ok();
            }
        });
    }
}

impl Haptics {
    crate::shell::calls! { HAPTIC;
        light() => "Light";
        medium() => "Medium";
        heavy() => "Heavy";
        vibrate(duration: i32) => "Vibrate";
        stop_vibration() => "Stop";
    }

    fn vibrate_pattern(&self, pattern: &QList<QVariant>, _repeat: i32) {
        HAPTIC.call("VibratePattern", (variant::list(pattern),));
    }
}
