//! `Links` (QML `NavigationRouter`): deep links into apps, which the shell's
//! QML opens.

use std::pin::Pin;
use std::sync::OnceLock;

use cxx_qt::Threading;
use cxx_qt_lib::{QMap, QMapPair_QString_QVariant, QString};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        type Links = super::LinksRust;

        #[qinvokable]
        #[cxx_name = "navigateToDeepLink"]
        fn navigate_to_deep_link(self: Pin<&mut Links>, app_id: &QString, route: &QString, params: &QMap_QString_QVariant) -> bool;

        #[qsignal]
        #[cxx_name = "deepLinkRequested"]
        fn deep_link_requested(self: Pin<&mut Links>, app_id: &QString, route: &QString, params: &QMap_QString_QVariant);
    }

    impl cxx_qt::Threading for Links {}
    impl cxx_qt::Initialize for Links {}
}

use qobject::Links;

type Map = QMap<QMapPair_QString_QVariant>;

static QT: OnceLock<cxx_qt::CxxQtThread<Links>> = OnceLock::new();

/// Opens `app` at `route` with `params`, from any thread.
pub(crate) fn deep_link(app: String, route: String, params: Map) {
    if let Some(qt) = QT.get() {
        qt.queue(move |obj| {
            obj.navigate_to_deep_link(&QString::from(&app), &QString::from(&route), &params);
        })
        .ok();
    }
}

#[derive(Default)]
pub struct LinksRust;

impl cxx_qt::Initialize for Links {
    fn initialize(self: Pin<&mut Self>) {
        QT.set(self.qt_thread()).ok();
    }
}

impl Links {
    fn navigate_to_deep_link(self: Pin<&mut Self>, app_id: &QString, route: &QString, params: &Map) -> bool {
        if app_id.is_empty() {
            return false;
        }
        self.deep_link_requested(app_id, route, params);
        true
    }
}
