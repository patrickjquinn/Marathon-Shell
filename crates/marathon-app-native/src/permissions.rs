//! `Permissions`: the shell's Permissions1, and what each permission means.

use std::pin::Pin;

use cxx_qt::Threading;
use cxx_qt_lib::{QMap, QMapPair_QString_QVariant, QString, QVariant};

use crate::shell::{relay, PERMISSIONS};

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
        type Permissions = super::PermissionsRust;

        #[qsignal]
        #[cxx_name = "permissionGranted"]
        fn permission_granted(self: Pin<&mut Self>, app_id: &QString, permission: &QString);
        #[qsignal]
        #[cxx_name = "permissionDenied"]
        fn permission_denied(self: Pin<&mut Self>, app_id: &QString, permission: &QString);
        #[qsignal]
        #[cxx_name = "permissionRequested"]
        fn permission_requested(self: Pin<&mut Self>, app_id: &QString, permission: &QString);

        #[qinvokable]
        #[cxx_name = "hasPermission"]
        fn has_permission(self: &Permissions, app_id: &QString, permission: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "requestPermission"]
        fn request_permission(self: &Permissions, app_id: &QString, permission: &QString);
        #[qinvokable]
        #[cxx_name = "setPermission"]
        fn set_permission(self: &Permissions, app_id: &QString, permission: &QString, granted: bool, remember: bool) -> bool;
        /// Its label, description and whether only Marathon's own apps hold it.
        #[qinvokable]
        fn describe(self: &Permissions, permission: &QString) -> QMap_QString_QVariant;
    }

    impl cxx_qt::Threading for Permissions {}
    impl cxx_qt::Initialize for Permissions {}
}

use qobject::Permissions;

#[derive(Default)]
pub struct PermissionsRust;

type Pair = (String, String);

fn qt_pair((app, permission): &Pair) -> (QString, QString) {
    (QString::from(app), QString::from(permission))
}

impl cxx_qt::Initialize for Permissions {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        relay(qt.clone(), PERMISSIONS, "PermissionGranted", |obj, p: Pair| {
            let (app, permission) = qt_pair(&p);
            obj.permission_granted(&app, &permission);
        });
        relay(qt.clone(), PERMISSIONS, "PermissionDenied", |obj, p: Pair| {
            let (app, permission) = qt_pair(&p);
            obj.permission_denied(&app, &permission);
        });
        relay(qt, PERMISSIONS, "PermissionRequested", |obj, p: Pair| {
            let (app, permission) = qt_pair(&p);
            obj.permission_requested(&app, &permission);
        });
    }
}

impl Permissions {
    crate::shell::calls! { PERMISSIONS;
        request_permission(app_id: &QString, permission: &QString) => "RequestPermission";
    }
    crate::shell::asks! { PERMISSIONS;
        has_permission(app_id: &QString, permission: &QString) -> bool => "HasPermission";
    }

    fn set_permission(&self, app_id: &QString, permission: &QString, granted: bool, remember: bool) -> bool {
        let body = (app_id.to_string(), permission.to_string(), granted, remember);
        PERMISSIONS.ask_now::<_, ()>("SetPermission", &body).is_some()
    }

    fn describe(&self, permission: &QString) -> QMap<QMapPair_QString_QVariant> {
        let mut map = QMap::<QMapPair_QString_QVariant>::default();
        let name = permission.to_string();
        if let Some(p) = marathon_permissions::describe(&name) {
            map.insert(QString::from("label"), QVariant::from(&QString::from(&p.label)));
            map.insert(QString::from("description"), QVariant::from(&QString::from(&p.description)));
            map.insert(QString::from("restricted"), QVariant::from(&p.restricted));
        } else {
            map.insert(QString::from("label"), QVariant::from(permission));
            map.insert(QString::from("description"), QVariant::from(&QString::default()));
        }
        map
    }
}
