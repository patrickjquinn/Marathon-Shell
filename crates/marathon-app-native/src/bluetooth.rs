//! `Bluetooth`: the shell's Bluetooth1, the adapter, devices and pairing.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QString, QVariant};

use crate::shell::{get, mirror, relay, Service, Update};

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
        #[qproperty(bool, enabled, READ, WRITE = set_enabled, NOTIFY = state_changed)]
        #[qproperty(bool, scanning, READ, NOTIFY = state_changed)]
        #[qproperty(QString, adapter_name, cxx_name = "adapterName", READ, NOTIFY = state_changed)]
        #[qproperty(QList_QVariant, devices, READ, NOTIFY = state_changed)]
        #[qproperty(QList_QVariant, paired_devices, cxx_name = "pairedDevices", READ, NOTIFY = state_changed)]
        type Bluetooth = super::BluetoothRust;

        #[qsignal]
        #[cxx_name = "stateChanged"]
        fn state_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "pairingFailed"]
        fn pairing_failed(self: Pin<&mut Self>, address: &QString, error: &QString);
        #[qsignal]
        #[cxx_name = "pairingSucceeded"]
        fn pairing_succeeded(self: Pin<&mut Self>, address: &QString);
        #[qsignal]
        #[cxx_name = "pinRequested"]
        fn pin_requested(self: Pin<&mut Self>, address: &QString, device_name: &QString);
        #[qsignal]
        #[cxx_name = "passkeyRequested"]
        fn passkey_requested(self: Pin<&mut Self>, address: &QString, device_name: &QString);
        #[qsignal]
        #[cxx_name = "passkeyConfirmation"]
        fn passkey_confirmation(
            self: Pin<&mut Self>,
            address: &QString,
            device_name: &QString,
            passkey: u32,
        );

        #[cxx_name = "setEnabled"]
        fn set_enabled(self: Pin<&mut Bluetooth>, enabled: bool);
        #[qinvokable]
        #[cxx_name = "startScan"]
        fn start_scan(self: &Bluetooth);
        #[qinvokable]
        #[cxx_name = "stopScan"]
        fn stop_scan(self: &Bluetooth);
        #[qinvokable]
        #[cxx_name = "pairDevice"]
        fn pair_device(self: &Bluetooth, address: &QString, pin: &QString);
        #[qinvokable]
        #[cxx_name = "unpairDevice"]
        fn unpair_device(self: &Bluetooth, address: &QString);
        #[qinvokable]
        #[cxx_name = "connectDevice"]
        fn connect_device(self: &Bluetooth, address: &QString);
        #[qinvokable]
        #[cxx_name = "disconnectDevice"]
        fn disconnect_device(self: &Bluetooth, address: &QString);
        #[qinvokable]
        #[cxx_name = "confirmPairing"]
        fn confirm_pairing(self: &Bluetooth, address: &QString, confirmed: bool);
        #[qinvokable]
        #[cxx_name = "cancelPairing"]
        fn cancel_pairing(self: &Bluetooth, address: &QString);
    }

    impl cxx_qt::Threading for Bluetooth {}
    impl cxx_qt::Initialize for Bluetooth {}
}

use qobject::Bluetooth;

const BLUETOOTH: Service = Service::shell("Bluetooth");

#[derive(Default)]
pub struct BluetoothRust {
    available: bool,
    enabled: bool,
    scanning: bool,
    adapter_name: QString,
    devices: QList<QVariant>,
    paired_devices: QList<QVariant>,
}

type Device = (String, String);

fn qt((address, name): &Device) -> (QString, QString) {
    (QString::from(address), QString::from(name))
}

impl cxx_qt::Initialize for Bluetooth {
    fn initialize(self: Pin<&mut Self>) {
        let t = self.qt_thread();
        relay(t.clone(), BLUETOOTH, "PairingFailed", |obj, d: Device| {
            let (address, error) = qt(&d);
            obj.pairing_failed(&address, &error);
        });
        relay(
            t.clone(),
            BLUETOOTH,
            "PairingSucceeded",
            |obj, (a,): (String,)| obj.pairing_succeeded(&QString::from(&a)),
        );
        relay(t.clone(), BLUETOOTH, "PinRequested", |obj, d: Device| {
            let (address, name) = qt(&d);
            obj.pin_requested(&address, &name);
        });
        relay(
            t.clone(),
            BLUETOOTH,
            "PasskeyRequested",
            |obj, d: Device| {
                let (address, name) = qt(&d);
                obj.passkey_requested(&address, &name);
            },
        );
        relay(
            t.clone(),
            BLUETOOTH,
            "PasskeyConfirmation",
            |obj, (a, n, key): (String, String, u32)| {
                obj.passkey_confirmation(&QString::from(&a), &QString::from(&n), key);
            },
        );
        mirror(t, BLUETOOTH, "system", |mut obj, update| {
            let Update::State(s) = update else { return };
            let mut b = obj.as_mut().rust_mut();
            b.available = get(&s, "available");
            b.enabled = get(&s, "enabled");
            b.scanning = get(&s, "scanning");
            b.adapter_name = get(&s, "adapterName");
            b.devices = get(&s, "devices");
            b.paired_devices = get(&s, "pairedDevices");
            obj.state_changed();
        });
    }
}

impl Bluetooth {
    crate::shell::calls! { BLUETOOTH; mut
        set_enabled(enabled: bool) => "SetEnabled";
    }
    crate::shell::calls! { BLUETOOTH;
        start_scan() => "StartScan";
        stop_scan() => "StopScan";
        pair_device(address: &QString, pin: &QString) => "PairDevice";
        unpair_device(address: &QString) => "UnpairDevice";
        connect_device(address: &QString) => "ConnectDevice";
        disconnect_device(address: &QString) => "DisconnectDevice";
        confirm_pairing(address: &QString, confirmed: bool) => "ConfirmPairing";
        cancel_pairing(address: &QString) => "CancelPairing";
    }
}
