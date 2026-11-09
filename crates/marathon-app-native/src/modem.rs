//! `Modem`: the shell's Modem1, the cellular modem and mobile data.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QVariant};
use marathon_rt::io;

use crate::shell::{get, mirror, Service, Update};

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, available, READ, NOTIFY = state_changed)]
        #[qproperty(bool, enabled, READ, NOTIFY = state_changed)]
        #[qproperty(bool, sim_present, cxx_name = "simPresent", READ, NOTIFY = state_changed)]
        #[qproperty(bool, registered, READ, NOTIFY = state_changed)]
        #[qproperty(QString, operator_name, cxx_name = "operatorName", READ, NOTIFY = state_changed)]
        #[qproperty(i32, signal_strength, cxx_name = "signalStrength", READ, NOTIFY = state_changed)]
        #[qproperty(QString, network_type, cxx_name = "networkType", READ, NOTIFY = state_changed)]
        #[qproperty(bool, roaming, READ, NOTIFY = state_changed)]
        #[qproperty(bool, data_enabled, cxx_name = "dataEnabled", READ, NOTIFY = state_changed)]
        #[qproperty(bool, data_roaming_allowed, cxx_name = "dataRoamingAllowed", READ, NOTIFY = state_changed)]
        #[qproperty(QList_QVariant, supported_modes, cxx_name = "supportedModes", READ, NOTIFY = state_changed)]
        #[qproperty(u32, mode_mask, cxx_name = "allowedModes", READ, NOTIFY = state_changed)]
        /// The APN data uses now, after loadApn().
        #[qproperty(QString, apn, READ, NOTIFY = apn_changed)]
        /// The APN set by hand, "" for automatic.
        #[qproperty(QString, custom_apn, cxx_name = "customApn", READ, NOTIFY = apn_changed)]
        /// The carrier's APNs for the SIM: maps of name, apn, user, password.
        #[qproperty(QList_QVariant, carrier_apns, cxx_name = "carrierApns", READ, NOTIFY = apn_changed)]
        type Modem = super::ModemRust;

        #[qsignal]
        #[cxx_name = "apnChanged"]
        fn apn_changed(self: Pin<&mut Self>);
        #[qinvokable]
        #[cxx_name = "loadApn"]
        fn load_apn(self: &Modem);
        /// "" for automatic; reloads once it is applied.
        #[qinvokable]
        #[cxx_name = "setApn"]
        fn set_apn(self: &Modem, apn: &QString, user: &QString, password: &QString);

        #[qsignal]
        #[cxx_name = "stateChanged"]
        fn state_changed(self: Pin<&mut Self>);

        #[qinvokable]
        #[cxx_name = "enableData"]
        fn enable_data(self: &Modem);
        #[qinvokable]
        #[cxx_name = "disableData"]
        fn disable_data(self: &Modem);
        #[qinvokable]
        #[cxx_name = "setDataRoamingAllowed"]
        fn set_data_roaming_allowed(self: &Modem, allowed: bool);
        /// One of `supportedModes`, a ModemManager `MMModemMode` mask.
        #[qinvokable]
        #[cxx_name = "setAllowedModes"]
        fn set_allowed_modes(self: &Modem, allowed: u32);
    }

    impl cxx_qt::Threading for Modem {}
    impl cxx_qt::Initialize for Modem {}
}

use qobject::Modem;

const MODEM: Service = Service::shell("Modem");

#[derive(Default)]
#[allow(clippy::struct_excessive_bools, reason = "the QML properties")]
pub struct ModemRust {
    available: bool,
    enabled: bool,
    sim_present: bool,
    registered: bool,
    operator_name: QString,
    signal_strength: i32,
    network_type: QString,
    roaming: bool,
    data_enabled: bool,
    data_roaming_allowed: bool,
    supported_modes: QList<QVariant>,
    mode_mask: u32,
    apn: QString,
    custom_apn: QString,
    carrier_apns: QList<QVariant>,
}

impl cxx_qt::Initialize for Modem {
    fn initialize(self: Pin<&mut Self>) {
        mirror(self.qt_thread(), MODEM, "network", |mut obj, update| {
            let Update::State(s) = update else { return };
            let mut m = obj.as_mut().rust_mut();
            m.available = get(&s, "available");
            m.enabled = get(&s, "enabled");
            m.sim_present = get(&s, "simPresent");
            m.registered = get(&s, "registered");
            m.operator_name = get(&s, "operatorName");
            m.signal_strength = get(&s, "signalStrength");
            m.network_type = get(&s, "networkType");
            m.roaming = get(&s, "roaming");
            m.data_enabled = get(&s, "dataEnabled");
            m.data_roaming_allowed = get(&s, "dataRoamingAllowed");
            m.supported_modes = get(&s, "supportedModes");
            m.mode_mask = get(&s, "allowedModes");
            obj.state_changed();
        });
    }
}

impl Modem {
    crate::shell::calls! { MODEM;
        enable_data() => "EnableData";
        disable_data() => "DisableData";
        set_data_roaming_allowed(allowed: bool) => "SetDataRoamingAllowed";
        set_allowed_modes(allowed: u32) => "SetAllowedModes";
    }

    fn load_apn(&self) {
        let qt = self.qt_thread();
        io::spawn(async move {
            let Ok((live, custom, carrier)) = MODEM
                .ask::<_, (String, String, Vec<(String, String, String, String)>)>("GetApn", &())
                .await
            else {
                return;
            };
            qt.queue(move |mut obj| {
                let mut list = QList::<QVariant>::default();
                for (name, apn, user, password) in &carrier {
                    let mut map = QMap::<QMapPair_QString_QVariant>::default();
                    for (k, v) in [
                        ("name", name),
                        ("apn", apn),
                        ("user", user),
                        ("password", password),
                    ] {
                        map.insert(QString::from(k), QVariant::from(&QString::from(v.as_str())));
                    }
                    list.append(QVariant::from(&map));
                }
                let mut m = obj.as_mut().rust_mut();
                m.apn = QString::from(&live);
                m.custom_apn = QString::from(&custom);
                m.carrier_apns = list;
                obj.apn_changed();
            })
            .ok();
        });
    }

    fn set_apn(&self, apn: &QString, user: &QString, password: &QString) {
        let qt = self.qt_thread();
        let body = (apn.to_string(), user.to_string(), password.to_string());
        io::spawn(async move {
            if let Err(e) = MODEM.reply("SetApn", &body).await {
                marathon_rt::log::warn("modem", format_args!("SetApn: {e}"));
            }
            qt.queue(|obj| obj.load_apn()).ok();
        });
    }
}
