//! `Lifecycle`: the shell's `AppLifecycle1`, background work an app declares.

use cxx_qt_lib::{QString, QStringList, QVariant};

use crate::shell::Service;

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
        include!("cxx-qt-lib/qvariant.h");
        type QVariant = cxx_qt_lib::QVariant;
    }

    extern "RustQt" {
        #[qobject]
        type Lifecycle = super::LifecycleRust;

        /// A handle, 0 when the manifest does not allow `category`.
        #[qinvokable]
        #[cxx_name = "beginBackgroundTask"]
        fn begin_background_task(self: &Lifecycle, category: &QString, reason: &QString) -> u32;
        #[qinvokable]
        #[cxx_name = "endBackgroundTask"]
        fn end_background_task(self: &Lifecycle, handle: u32) -> bool;
        #[qinvokable]
        #[cxx_name = "currentCapabilities"]
        fn current_capabilities(self: &Lifecycle) -> QStringList;
        /// For the shell's own windows; in an app's runner the shell tracks
        /// the app's surface itself.
        #[qinvokable]
        #[cxx_name = "registerApp"]
        fn register_app(self: &Lifecycle, app_id: &QString, root: &QVariant);
        #[qinvokable]
        #[cxx_name = "unregisterApp"]
        fn unregister_app(self: &Lifecycle, app_id: &QString);
    }
}

#[derive(Default)]
pub struct LifecycleRust;

const LIFECYCLE: Service = Service::session("AppLifecycle");

impl qobject::Lifecycle {
    crate::shell::asks! { LIFECYCLE;
        begin_background_task(category: &QString, reason: &QString) -> u32 => "BeginBackgroundTask";
        end_background_task(handle: u32) -> bool => "EndBackgroundTask";
        current_capabilities() -> QStringList => "GetMyCapabilities";
    }

    fn register_app(&self, _app_id: &QString, _root: &QVariant) {}

    fn unregister_app(&self, _app_id: &QString) {}
}
