//! `Navigation`: the shell's Navigation1, opening apps and links.

use std::pin::Pin;

use cxx_qt::Threading;
use cxx_qt_lib::{QMap, QMapPair_QString_QVariant, QString, QVariant};

use crate::shell::{relay, Service};

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        type Navigation = super::NavigationRust;

        #[qsignal]
        #[cxx_name = "appLaunched"]
        fn app_launched(self: Pin<&mut Self>, app_id: &QString);
        #[qsignal]
        #[cxx_name = "navigationFailed"]
        fn navigation_failed(self: Pin<&mut Self>, uri: &QString, error: &QString);
        #[qsignal]
        #[cxx_name = "deepLinkRequested"]
        fn deep_link_requested(
            self: Pin<&mut Self>,
            app_id: &QString,
            route: &QString,
            params: &QMap_QString_QVariant,
        );

        #[qinvokable]
        #[cxx_name = "launchApp"]
        fn launch_app(self: &Navigation, app_id: &QString) -> bool;
        /// A `marathon://` link.
        #[qinvokable]
        fn navigate(self: &Navigation, uri: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "launchAppWithRoute"]
        fn launch_app_with_route(
            self: &Navigation,
            app_id: &QString,
            route: &QString,
            params_json: &QString,
        ) -> bool;
    }

    impl cxx_qt::Threading for Navigation {}
    impl cxx_qt::Initialize for Navigation {}
}

use qobject::Navigation;

const NAVIGATION: Service = Service::shell("Navigation");

#[derive(Default)]
pub struct NavigationRust;

impl cxx_qt::Initialize for Navigation {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        relay(
            qt.clone(),
            NAVIGATION,
            "AppLaunched",
            |obj, (a,): (String,)| obj.app_launched(&QString::from(&a)),
        );
        relay(
            qt.clone(),
            NAVIGATION,
            "NavigationFailed",
            |obj, (uri, error): (String, String)| {
                obj.navigation_failed(&QString::from(&uri), &QString::from(&error));
            },
        );
        relay(
            qt,
            NAVIGATION,
            "DeepLinkRequested",
            |obj, (app, route, json): (String, String, String)| {
                obj.deep_link_requested(
                    &QString::from(&app),
                    &QString::from(&route),
                    &params(&json),
                );
            },
        );
    }
}

/// A JSON object of a link's parameters, as strings, numbers and flags.
fn params(json: &str) -> QMap<QMapPair_QString_QVariant> {
    let mut map = QMap::<QMapPair_QString_QVariant>::default();
    let Ok(serde_json::Value::Object(object)) = serde_json::from_str(json) else {
        return map;
    };
    for (key, value) in object {
        let value = match value {
            serde_json::Value::String(s) => QVariant::from(&QString::from(&s)),
            serde_json::Value::Bool(b) => QVariant::from(&b),
            serde_json::Value::Number(n) => {
                n.as_i64().and_then(|n| i32::try_from(n).ok()).map_or_else(
                    || QVariant::from(&n.as_f64().unwrap_or_default()),
                    |n| QVariant::from(&n),
                )
            }
            other => QVariant::from(&QString::from(&other.to_string())),
        };
        map.insert(QString::from(&key), value);
    }
    map
}

impl Navigation {
    crate::shell::asks! { NAVIGATION;
        launch_app_with_route(app_id: &QString, route: &QString, params_json: &QString) -> bool => "LaunchAppWithRoute";
    }

    fn launch_app(&self, app_id: &QString) -> bool {
        !app_id.is_empty()
            && NAVIGATION
                .ask_now("LaunchApp", &(app_id.to_string(),))
                .unwrap_or(false)
    }

    fn navigate(&self, uri: &QString) -> bool {
        let uri = uri.to_string();
        uri.starts_with("marathon://") && NAVIGATION.ask_now("Navigate", &(uri,)).unwrap_or(false)
    }
}
