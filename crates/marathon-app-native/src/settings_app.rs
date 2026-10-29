//! Settings app types (`MarathonOS.Settings`): `MmsSettings`, `StorageInfo`,
//! `TimeZoneList`, `KeyboardSettingsStore`, and `SettingsController`.

use std::collections::{HashMap, HashSet};
use std::ffi::CString;
use std::fs;
use std::path::PathBuf;
use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QStringList, QVariant};
use futures_lite::StreamExt;
use jiff::tz::TimeZone;
use jiff::Timestamp;
use zbus::{MatchRule, MessageStream};
use zbus::{OwnedVariant as OwnedValue, Variant as Value};

use crate::shell::{get, mirror, relay, Field, Service, State, Update};
use marathon_apps::apps;
use marathon_rt::io;

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
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, available, READ, NOTIFY = changed)]
        #[qproperty(bool, loaded, READ, NOTIFY = changed)]
        #[qproperty(QString, mmsc, READ, NOTIFY = changed)]
        #[qproperty(QString, apn, READ, NOTIFY = changed)]
        #[qproperty(QString, proxy, READ, NOTIFY = changed)]
        #[qproperty(bool, auto_download, cxx_name = "autoDownload", READ, NOTIFY = changed)]
        type MmsSettings = super::MmsSettingsRust;

        #[qsignal]
        fn changed(self: Pin<&mut Self>);
        #[qsignal]
        fn saved(self: Pin<&mut Self>);
        #[qsignal]
        fn failed(self: Pin<&mut Self>, error: &QString);

        #[qinvokable]
        fn refresh(self: &MmsSettings);
        #[qinvokable]
        fn save(self: &MmsSettings, mmsc: &QString, apn: &QString, proxy: &QString);
        #[qinvokable]
        #[cxx_name = "setAutoDownload"]
        fn set_auto_download(self: &MmsSettings, on: bool);
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(i64, total_space, cxx_name = "totalSpace", READ, NOTIFY = changed)]
        #[qproperty(i64, available_space, cxx_name = "availableSpace", READ, NOTIFY = changed)]
        #[qproperty(i64, used_space, cxx_name = "usedSpace", READ, NOTIFY = changed)]
        #[qproperty(f64, used_percentage, cxx_name = "usedPercentage", READ, NOTIFY = changed)]
        #[qproperty(QString, total_space_string, cxx_name = "totalSpaceString", READ, NOTIFY = changed)]
        #[qproperty(QString, available_space_string, cxx_name = "availableSpaceString", READ, NOTIFY = changed)]
        #[qproperty(QString, used_space_string, cxx_name = "usedSpaceString", READ, NOTIFY = changed)]
        type StorageInfo = super::StorageInfoRust;

        #[qsignal]
        fn changed(self: Pin<&mut Self>);

        #[qinvokable]
        fn refresh(self: Pin<&mut StorageInfo>);
    }

    extern "RustQt" {
        #[qobject]
        type TimeZoneList = super::TimeZoneListRust;

        #[qinvokable]
        fn search(self: &TimeZoneList, query: &QString) -> QList_QVariant;
        #[qinvokable]
        #[cxx_name = "displayName"]
        fn display_name(self: &TimeZoneList, zone_id: &QString) -> QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(QString, current_language, cxx_name = "currentLanguage", READ, WRITE = set_current_language, NOTIFY)]
        #[qproperty(bool, auto_correct_enabled, cxx_name = "autoCorrectEnabled", READ, WRITE = set_auto_correct_enabled, NOTIFY)]
        #[qproperty(bool, auto_capitalize_enabled, cxx_name = "autoCapitalizeEnabled", READ, WRITE = set_auto_capitalize_enabled, NOTIFY)]
        #[qproperty(bool, haptic_feedback_enabled, cxx_name = "hapticFeedbackEnabled", READ, WRITE = set_haptic_feedback_enabled, NOTIFY)]
        #[qproperty(bool, predictions_enabled, cxx_name = "predictionsEnabled", READ, WRITE = set_predictions_enabled, NOTIFY)]
        #[qproperty(
            QStringList,
            available_languages,
            cxx_name = "availableLanguages",
            READ,
            CONSTANT
        )]
        type KeyboardSettingsStore = super::KeyboardSettingsStoreRust;

        #[cxx_name = "setCurrentLanguage"]
        fn set_current_language(self: Pin<&mut KeyboardSettingsStore>, language_id: &QString);
        #[cxx_name = "setAutoCorrectEnabled"]
        fn set_auto_correct_enabled(self: Pin<&mut KeyboardSettingsStore>, enabled: bool);
        #[cxx_name = "setAutoCapitalizeEnabled"]
        fn set_auto_capitalize_enabled(self: Pin<&mut KeyboardSettingsStore>, enabled: bool);
        #[cxx_name = "setHapticFeedbackEnabled"]
        fn set_haptic_feedback_enabled(self: Pin<&mut KeyboardSettingsStore>, enabled: bool);
        #[cxx_name = "setPredictionsEnabled"]
        fn set_predictions_enabled(self: Pin<&mut KeyboardSettingsStore>, enabled: bool);

        #[qinvokable]
        #[cxx_name = "getLanguageName"]
        fn get_language_name(self: &KeyboardSettingsStore, language_id: &QString) -> QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(QList_QVariant, notification_apps, cxx_name = "notificationApps", READ, NOTIFY = notification_apps_changed)]
        #[qproperty(i32, notification_apps_revision, cxx_name = "notificationAppsRevision", READ, NOTIFY = notification_apps_changed)]
        #[qproperty(QString, os_version, cxx_name = "osVersion", READ, NOTIFY = system_info_changed)]
        #[qproperty(QString, kernel_version, cxx_name = "kernelVersion", READ, NOTIFY = system_info_changed)]
        #[qproperty(QString, device_model, cxx_name = "deviceModel", READ, NOTIFY = system_info_changed)]
        #[qproperty(QString, display_resolution, cxx_name = "displayResolution", READ, NOTIFY = system_info_changed)]
        #[qproperty(QString, display_refresh_rate, cxx_name = "displayRefreshRate", READ, NOTIFY = system_info_changed)]
        #[qproperty(QString, display_dpi, cxx_name = "displayDpi", READ, NOTIFY = system_info_changed)]
        #[qproperty(QString, display_scale, cxx_name = "displayScale", READ, NOTIFY = system_info_changed)]
        #[qproperty(
            QList_QVariant,
            open_source_licenses,
            cxx_name = "openSourceLicenses",
            READ,
            CONSTANT
        )]
        #[qproperty(bool, wifi_dialog_visible, cxx_name = "wifiDialogVisible", READ, NOTIFY = wifi_dialog_changed)]
        #[qproperty(QString, wifi_dialog_ssid, cxx_name = "wifiDialogSsid", READ, NOTIFY = wifi_dialog_changed)]
        #[qproperty(i32, wifi_dialog_strength, cxx_name = "wifiDialogStrength", READ, NOTIFY = wifi_dialog_changed)]
        #[qproperty(QString, wifi_dialog_security, cxx_name = "wifiDialogSecurity", READ, NOTIFY = wifi_dialog_changed)]
        #[qproperty(bool, wifi_dialog_secured, cxx_name = "wifiDialogSecured", READ, NOTIFY = wifi_dialog_changed)]
        #[qproperty(bool, wifi_dialog_connecting, cxx_name = "wifiDialogConnecting", READ, NOTIFY = wifi_dialog_changed)]
        #[qproperty(QString, wifi_dialog_error, cxx_name = "wifiDialogError", READ, NOTIFY = wifi_dialog_changed)]
        #[qproperty(QString, wifi_dialog_password, cxx_name = "wifiDialogPassword", READ, NOTIFY = wifi_dialog_changed)]
        #[qproperty(bool, wifi_dialog_hidden, cxx_name = "wifiDialogHidden", READ, NOTIFY = wifi_dialog_changed)]
        #[qproperty(bool, bluetooth_dialog_visible, cxx_name = "bluetoothDialogVisible", READ, NOTIFY = bluetooth_dialog_changed)]
        #[qproperty(QString, bluetooth_dialog_name, cxx_name = "bluetoothDialogName", READ, NOTIFY = bluetooth_dialog_changed)]
        #[qproperty(QString, bluetooth_dialog_address, cxx_name = "bluetoothDialogAddress", READ, NOTIFY = bluetooth_dialog_changed)]
        #[qproperty(QString, bluetooth_dialog_type, cxx_name = "bluetoothDialogType", READ, NOTIFY = bluetooth_dialog_changed)]
        #[qproperty(QString, bluetooth_dialog_mode, cxx_name = "bluetoothDialogMode", READ, NOTIFY = bluetooth_dialog_changed)]
        #[qproperty(QString, bluetooth_dialog_passkey, cxx_name = "bluetoothDialogPasskey", READ, NOTIFY = bluetooth_dialog_changed)]
        #[qproperty(bool, bluetooth_dialog_pairing, cxx_name = "bluetoothDialogPairing", READ, NOTIFY = bluetooth_dialog_changed)]
        #[qproperty(QString, bluetooth_dialog_error, cxx_name = "bluetoothDialogError", READ, NOTIFY = bluetooth_dialog_changed)]
        type SettingsController = super::SettingsControllerRust;

        #[qsignal]
        #[cxx_name = "wifiDialogChanged"]
        fn wifi_dialog_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "bluetoothDialogChanged"]
        fn bluetooth_dialog_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "notificationAppsChanged"]
        fn notification_apps_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "systemInfoChanged"]
        fn system_info_changed(self: Pin<&mut Self>);

        #[cxx_name = "initDisplay"]
        fn init_display(
            self: Pin<&mut SettingsController>,
            resolution: &QString,
            refresh_rate: &QString,
            dpi: &QString,
            scale: &QString,
        );

        #[qinvokable]
        #[cxx_name = "setNotificationEnabled"]
        fn set_notification_enabled(
            self: Pin<&mut SettingsController>,
            app_id: &QString,
            enabled: bool,
        );
        #[qinvokable]
        #[cxx_name = "showWifiDialog"]
        fn show_wifi_dialog(
            self: Pin<&mut SettingsController>,
            ssid: &QString,
            strength: i32,
            security: &QString,
            secured: bool,
        );
        #[qinvokable]
        #[cxx_name = "dismissWifiDialog"]
        fn dismiss_wifi_dialog(self: Pin<&mut SettingsController>);
        #[qinvokable]
        #[cxx_name = "submitWifiPassword"]
        fn submit_wifi_password(self: Pin<&mut SettingsController>, password: &QString);
        #[qinvokable]
        #[cxx_name = "connectSavedNetwork"]
        fn connect_saved_network(
            self: Pin<&mut SettingsController>,
            ssid: &QString,
            strength: i32,
            security: &QString,
            secured: bool,
        );
        #[qinvokable]
        #[cxx_name = "showHiddenNetworkDialog"]
        fn show_hidden_network_dialog(self: Pin<&mut SettingsController>);
        #[qinvokable]
        #[cxx_name = "connectHiddenNetwork"]
        fn connect_hidden_network(
            self: Pin<&mut SettingsController>,
            ssid: &QString,
            security: &QString,
            password: &QString,
        );
        #[qinvokable]
        #[cxx_name = "showBluetoothDialog"]
        fn show_bluetooth_dialog(
            self: Pin<&mut SettingsController>,
            name: &QString,
            address: &QString,
            device_type: &QString,
            mode: &QString,
        );
        #[qinvokable]
        #[cxx_name = "showBluetoothPasskeyConfirmation"]
        fn show_bluetooth_passkey_confirmation(
            self: Pin<&mut SettingsController>,
            name: &QString,
            address: &QString,
            device_type: &QString,
            passkey: u32,
        );
        #[qinvokable]
        #[cxx_name = "dismissBluetoothDialog"]
        fn dismiss_bluetooth_dialog(self: Pin<&mut SettingsController>);
        #[qinvokable]
        #[cxx_name = "submitBluetoothPin"]
        fn submit_bluetooth_pin(self: Pin<&mut SettingsController>, pin: &QString);
        #[qinvokable]
        #[cxx_name = "submitBluetoothPasskey"]
        fn submit_bluetooth_passkey(self: Pin<&mut SettingsController>, passkey: &QString);
        #[qinvokable]
        #[cxx_name = "confirmBluetoothPairing"]
        fn confirm_bluetooth_pairing(self: Pin<&mut SettingsController>, accepted: bool);
        #[qinvokable]
        #[cxx_name = "cancelBluetoothPairing"]
        fn cancel_bluetooth_pairing(self: Pin<&mut SettingsController>);
        #[qinvokable]
        #[cxx_name = "bluetoothPairingModeText"]
        fn bluetooth_pairing_mode_text(self: &SettingsController, mode: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "bluetoothHelpText"]
        fn bluetooth_help_text(self: &SettingsController, mode: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "bluetoothCanPair"]
        fn bluetooth_can_pair(
            self: &SettingsController,
            mode: &QString,
            pin: &QString,
            passkey: &QString,
        ) -> bool;
        #[qinvokable]
        #[cxx_name = "lockoutStatusText"]
        fn lockout_status_text(
            self: &SettingsController,
            locked_out: bool,
            seconds_remaining: i32,
        ) -> QString;
        #[qinvokable]
        #[cxx_name = "quickPinValidationError"]
        fn quick_pin_validation_error(
            self: &SettingsController,
            pin: &QString,
            password: &QString,
        ) -> QString;
    }

    impl cxx_qt::Threading for MmsSettings {}
    impl cxx_qt::Initialize for MmsSettings {}
    impl cxx_qt::Initialize for StorageInfo {}
    impl cxx_qt::Threading for KeyboardSettingsStore {}
    impl cxx_qt::Initialize for KeyboardSettingsStore {}
    impl cxx_qt::Threading for SettingsController {}
    impl cxx_qt::Initialize for SettingsController {}
}

use qobject::{KeyboardSettingsStore, MmsSettings, SettingsController, StorageInfo, TimeZoneList};

fn q(s: &str) -> QString {
    QString::from(s)
}

// ---------------------------------------------------------------------------
// MmsSettings
// ---------------------------------------------------------------------------

const MMS_SERVICE: &str = "org.ofono.mms";
const MMS_PATH: &str = "/org/ofono/mms";
const MMS_IFACE: &str = "org.ofono.mms.ModemManager";

pub struct MmsSettingsRust {
    available: bool,
    loaded: bool,
    mmsc: QString,
    apn: QString,
    proxy: QString,
    auto_download: bool,
}

impl Default for MmsSettingsRust {
    fn default() -> Self {
        Self {
            available: false,
            loaded: false,
            mmsc: QString::default(),
            apn: QString::default(),
            proxy: QString::default(),
            auto_download: true,
        }
    }
}

async fn mms_call<B: serde::Serialize + zbus::DynamicType>(
    method: &str,
    body: &B,
) -> zbus::Result<zbus::Message> {
    let bus = io::session_bus().await?;
    bus.call_method(Some(MMS_SERVICE), MMS_PATH, Some(MMS_IFACE), method, body)
        .await
}

impl cxx_qt::Initialize for MmsSettings {
    fn initialize(self: Pin<&mut Self>) {
        self.refresh();
        let qt = self.qt_thread();
        io::spawn(async move {
            let Ok(bus) = io::session_bus().await else {
                return;
            };
            let Ok(rule) = MatchRule::builder()
                .msg_type(zbus::message::Type::Signal)
                .sender(MMS_SERVICE)
                .path(MMS_PATH)
                .interface(MMS_IFACE)
                .member("SettingsChanged")
                .build()
            else {
                return;
            };
            let Ok(mut stream) = MessageStream::for_match_rule(rule, &bus, None).await else {
                return;
            };
            while stream.next().await.is_some() {
                qt.queue(|obj| obj.refresh()).ok();
            }
        });
    }
}

impl MmsSettings {
    fn refresh(&self) {
        let qt = self.qt_thread();
        io::spawn(async move {
            let reply = mms_call("ViewSettings", &())
                .await
                .and_then(|m| m.body().deserialize::<HashMap<String, OwnedValue>>());
            qt.queue(move |mut obj| {
                let mut rust = obj.as_mut().rust_mut();
                rust.loaded = true;
                if let Ok(map) = reply {
                    rust.available = true;
                    rust.mmsc = get(&map, "CarrierMMSC");
                    rust.apn = get(&map, "MMS_APN");
                    rust.proxy = get(&map, "CarrierMMSProxy");
                    rust.auto_download = map
                        .get("AutoProcessSMSWAP")
                        .and_then(bool::from_value)
                        .unwrap_or(true);
                } else {
                    rust.available = false;
                    rust.mmsc = QString::default();
                    rust.apn = QString::default();
                    rust.proxy = QString::default();
                    rust.auto_download = true;
                }
                obj.changed();
            })
            .ok();
        });
    }

    fn save(&self, mmsc: &QString, apn: &QString, proxy: &QString) {
        let (qt, mmsc, apn, proxy) = (
            self.qt_thread(),
            mmsc.to_string(),
            apn.to_string(),
            proxy.to_string(),
        );
        io::spawn(async move {
            let mut all = HashMap::<&str, Value<'_>>::new();
            all.insert("CarrierMMSC", Value::from(mmsc));
            all.insert("MMS_APN", Value::from(apn));
            all.insert(
                "CarrierMMSProxy",
                Value::from(if proxy.is_empty() {
                    "NULL".to_owned()
                } else {
                    proxy
                }),
            );
            let reply = mms_call("ChangeAllSettings", &(all,)).await;
            if reply.is_ok() {
                mms_call("ProcessMessageQueue", &()).await.ok();
            }
            qt.queue(move |obj| match reply {
                Ok(_) => {
                    obj.refresh();
                    obj.saved();
                }
                Err(e) => obj.failed(&q(&crate::shell::message(&e))),
            })
            .ok();
        });
    }

    fn set_auto_download(&self, on: bool) {
        let qt = self.qt_thread();
        io::spawn(async move {
            let reply = mms_call("ChangeSettings", &("AutoProcessSMSWAP", Value::from(on))).await;
            qt.queue(move |mut obj| {
                if let Err(e) = reply {
                    obj.as_mut().failed(&q(&crate::shell::message(&e)));
                }
                obj.refresh();
            })
            .ok();
        });
    }
}

// ---------------------------------------------------------------------------
// StorageInfo
// ---------------------------------------------------------------------------

#[derive(Default)]
pub struct StorageInfoRust {
    total_space: i64,
    available_space: i64,
    used_space: i64,
    used_percentage: f64,
    total_space_string: QString,
    available_space_string: QString,
    used_space_string: QString,
}

#[allow(
    clippy::cast_precision_loss,
    reason = "human-readable storage formatting"
)]
fn format_bytes(bytes: i64) -> QString {
    const KB: i64 = 1024;
    const MB: i64 = KB * 1024;
    const GB: i64 = MB * 1024;
    const TB: i64 = GB * 1024;
    let s = if bytes >= TB {
        format!("{:.1} TB", bytes as f64 / TB as f64)
    } else if bytes >= GB {
        format!("{:.1} GB", bytes as f64 / GB as f64)
    } else if bytes >= MB {
        format!("{:.1} MB", bytes as f64 / MB as f64)
    } else if bytes >= KB {
        format!("{:.1} KB", bytes as f64 / KB as f64)
    } else {
        format!("{bytes} bytes")
    };
    q(&s)
}

fn stat_disk() -> (i64, i64) {
    const TMPFS_MAGIC: u64 = 0x0102_1994;
    let mut candidates = Vec::new();
    if let Some(dir) = dirs::data_local_dir() {
        // In the sandbox the data folder is on a tmpfs home; the app's own
        // folder under it is on the user's data disk.
        candidates.push(dir.join("marathon-apps").join(crate::shell::app_id()));
        candidates.push(dir);
    }
    candidates.push(PathBuf::from("/usr"));
    candidates.push(PathBuf::from("/"));
    for path in &candidates {
        let Ok(cpath) = CString::new(path.to_string_lossy().as_bytes()) else {
            continue;
        };
        // SAFETY: zeroed statfs struct filled by libc::statfs with valid C string.
        let (rc, s) = unsafe {
            let mut s: libc::statfs = std::mem::zeroed();
            (libc::statfs(cpath.as_ptr(), &raw mut s), s)
        };
        #[allow(clippy::useless_conversion, reason = "f_type is signed on some libcs")]
        let fs_type = u64::try_from(s.f_type).unwrap_or(u64::MAX);
        if rc == 0 && fs_type != TMPFS_MAGIC && s.f_blocks > 0 {
            #[allow(clippy::useless_conversion, reason = "f_frsize is unsigned on musl")]
            let bsize = i64::try_from(s.f_frsize).unwrap_or(0);
            let total = i64::try_from(s.f_blocks).unwrap_or(0).saturating_mul(bsize);
            let avail = i64::try_from(s.f_bavail).unwrap_or(0).saturating_mul(bsize);
            return (total, avail);
        }
    }
    (0, 0)
}

impl cxx_qt::Initialize for StorageInfo {
    fn initialize(self: Pin<&mut Self>) {
        self.refresh();
    }
}

impl StorageInfo {
    #[allow(clippy::cast_precision_loss, reason = "percentage ratio")]
    fn refresh(mut self: Pin<&mut Self>) {
        let (total, avail) = stat_disk();
        let used = (total - avail).max(0);
        let pct = if total > 0 {
            used as f64 / total as f64
        } else {
            0.0
        };
        let mut rust = self.as_mut().rust_mut();
        rust.total_space = total;
        rust.available_space = avail;
        rust.used_space = used;
        rust.used_percentage = pct;
        rust.total_space_string = format_bytes(total);
        rust.available_space_string = format_bytes(avail);
        rust.used_space_string = format_bytes(used);
        self.changed();
    }
}

// ---------------------------------------------------------------------------
// TimeZoneList
// ---------------------------------------------------------------------------

struct ZoneEntry {
    id: String,
    city: String,
    region: String,
    map: QVariant,
}

pub struct TimeZoneListRust {
    zones: Vec<ZoneEntry>,
}

fn offset_label(seconds: i32) -> String {
    if seconds == 0 {
        return "GMT".to_owned();
    }
    let minutes = seconds.unsigned_abs() / 60;
    let sign = if seconds < 0 { '-' } else { '+' };
    let hours = minutes / 60;
    let rem = minutes % 60;
    if rem == 0 {
        format!("GMT{sign}{hours}")
    } else {
        format!("GMT{sign}{hours}:{rem:02}")
    }
}

fn canonical_zones() -> HashSet<String> {
    let Ok(text) = fs::read_to_string("/usr/share/zoneinfo/zone.tab") else {
        return HashSet::new();
    };
    text.lines()
        .filter(|l| !l.starts_with('#'))
        .filter_map(|l| l.trim().split('\t').nth(2).map(ToOwned::to_owned))
        .collect()
}

impl Default for TimeZoneListRust {
    fn default() -> Self {
        const REGIONS: [&str; 9] = [
            "Africa",
            "America",
            "Antarctica",
            "Asia",
            "Atlantic",
            "Australia",
            "Europe",
            "Indian",
            "Pacific",
        ];
        let now = Timestamp::now();
        let canonical = canonical_zones();
        let mut entries = Vec::new();
        for raw_id in jiff::tz::db().available() {
            let id = raw_id.as_str();
            let Some((region, _)) = id.split_once('/') else {
                continue;
            };
            if !REGIONS.contains(&region) || (!canonical.is_empty() && !canonical.contains(id)) {
                continue;
            }
            let Ok(tz) = TimeZone::get(id) else { continue };
            let city = id.rsplit('/').next().unwrap_or(id).replace('_', " ");
            let offset = offset_label(tz.to_offset(now).seconds());
            let mut m = QMap::<QMapPair_QString_QVariant>::default();
            m.insert(q("id"), QVariant::from(&q(id)));
            m.insert(q("city"), QVariant::from(&q(&city)));
            m.insert(q("region"), QVariant::from(&q(region)));
            m.insert(q("offset"), QVariant::from(&q(&offset)));
            entries.push(ZoneEntry {
                id: id.to_owned(),
                city,
                region: region.to_owned(),
                map: QVariant::from(&m),
            });
        }
        entries.sort_by_key(|a| a.city.to_lowercase());
        Self { zones: entries }
    }
}

impl TimeZoneList {
    fn search(&self, query: &QString) -> QList<QVariant> {
        let q_lower = query.to_string().trim().to_lowercase();
        let mut out = QList::<QVariant>::default();
        for z in &self.zones {
            if q_lower.is_empty()
                || z.city.to_lowercase().contains(&q_lower)
                || z.region.to_lowercase().contains(&q_lower)
                || z.id.to_lowercase().contains(&q_lower)
            {
                out.append(z.map.clone());
            }
        }
        out
    }

    fn display_name(&self, zone_id: &QString) -> QString {
        let id = zone_id.to_string();
        let Ok(tz) = TimeZone::get(&id) else {
            return zone_id.clone();
        };
        let city = id.rsplit('/').next().unwrap_or(&id).replace('_', " ");
        let offset = offset_label(tz.to_offset(Timestamp::now()).seconds());
        q(&format!("{city} ({offset})"))
    }
}

// ---------------------------------------------------------------------------
// KeyboardSettingsStore
// ---------------------------------------------------------------------------

const SETTINGS: Service = Service::shell("Settings");

const LANGUAGES: [(&str, &str); 10] = [
    ("en_US", "English (US)"),
    ("fr_FR", "Français"),
    ("de_DE", "Deutsch"),
    ("es_ES", "Español"),
    ("pt_BR", "Português"),
    ("it_IT", "Italiano"),
    ("ru_RU", "Русский"),
    ("ar_SA", "العربية"),
    ("zh_CN", "中文"),
    ("ja_JP", "日本語"),
];

#[allow(clippy::struct_excessive_bools, reason = "keyboard setting toggles")]
pub struct KeyboardSettingsStoreRust {
    current_language: QString,
    auto_correct_enabled: bool,
    auto_capitalize_enabled: bool,
    haptic_feedback_enabled: bool,
    predictions_enabled: bool,
    available_languages: QStringList,
}

impl Default for KeyboardSettingsStoreRust {
    fn default() -> Self {
        let mut list = QList::<QString>::default();
        for (code, _) in LANGUAGES {
            list.append(q(code));
        }
        Self {
            current_language: q("en_US"),
            auto_correct_enabled: true,
            auto_capitalize_enabled: true,
            haptic_feedback_enabled: true,
            predictions_enabled: true,
            available_languages: QStringList::from(&list),
        }
    }
}

impl cxx_qt::Initialize for KeyboardSettingsStore {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        relay(
            qt.clone(),
            SETTINGS,
            "PropertyChanged",
            |mut obj, (name, val): (String, OwnedValue)| {
                obj.as_mut().apply_prop(&name, &val);
            },
        );
        io::spawn(async move {
            if let Ok(state) = SETTINGS.ask::<_, State>("GetState", &()).await {
                qt.queue(move |mut obj| {
                    for (k, v) in &state {
                        obj.as_mut().apply_prop(k, v);
                    }
                })
                .ok();
            }
        });
    }
}

impl KeyboardSettingsStore {
    fn apply_prop(mut self: Pin<&mut Self>, name: &str, val: &OwnedValue) {
        match name {
            "keyboardLanguage" => {
                if let Some(v) = QString::from_value(val) {
                    if self.current_language != v {
                        self.as_mut().rust_mut().current_language = v;
                        self.current_language_changed();
                    }
                }
            }
            "keyboardAutoCorrection" => {
                if let Some(v) = bool::from_value(val) {
                    if self.auto_correct_enabled != v {
                        self.as_mut().rust_mut().auto_correct_enabled = v;
                        self.auto_correct_enabled_changed();
                    }
                }
            }
            "keyboardAutoCapitalize" => {
                if let Some(v) = bool::from_value(val) {
                    if self.auto_capitalize_enabled != v {
                        self.as_mut().rust_mut().auto_capitalize_enabled = v;
                        self.auto_capitalize_enabled_changed();
                    }
                }
            }
            "keyboardPredictiveText" => {
                if let Some(v) = bool::from_value(val) {
                    if self.predictions_enabled != v {
                        self.as_mut().rust_mut().predictions_enabled = v;
                        self.predictions_enabled_changed();
                    }
                }
            }
            "keyboardHapticStrength" => {
                if let Ok(s) = <&str>::try_from(val) {
                    let on = s != "off";
                    if self.haptic_feedback_enabled != on {
                        self.as_mut().rust_mut().haptic_feedback_enabled = on;
                        self.haptic_feedback_enabled_changed();
                    }
                }
            }
            _ => {}
        }
    }

    fn set_current_language(mut self: Pin<&mut Self>, language_id: &QString) {
        if &self.current_language == language_id {
            return;
        }
        self.as_mut().rust_mut().current_language = language_id.clone();
        self.current_language_changed();
        SETTINGS.call(
            "SetProperty",
            ("keyboardLanguage", Value::from(language_id.to_string())),
        );
    }

    fn set_auto_correct_enabled(mut self: Pin<&mut Self>, enabled: bool) {
        if self.auto_correct_enabled == enabled {
            return;
        }
        self.as_mut().rust_mut().auto_correct_enabled = enabled;
        self.auto_correct_enabled_changed();
        SETTINGS.call(
            "SetProperty",
            ("keyboardAutoCorrection", Value::from(enabled)),
        );
    }

    fn set_auto_capitalize_enabled(mut self: Pin<&mut Self>, enabled: bool) {
        if self.auto_capitalize_enabled == enabled {
            return;
        }
        self.as_mut().rust_mut().auto_capitalize_enabled = enabled;
        self.auto_capitalize_enabled_changed();
        SETTINGS.call(
            "SetProperty",
            ("keyboardAutoCapitalize", Value::from(enabled)),
        );
    }

    fn set_haptic_feedback_enabled(mut self: Pin<&mut Self>, enabled: bool) {
        if self.haptic_feedback_enabled == enabled {
            return;
        }
        self.as_mut().rust_mut().haptic_feedback_enabled = enabled;
        self.haptic_feedback_enabled_changed();
        let strength = if enabled { "medium" } else { "off" };
        SETTINGS.call(
            "SetProperty",
            ("keyboardHapticStrength", Value::from(strength)),
        );
    }

    fn set_predictions_enabled(mut self: Pin<&mut Self>, enabled: bool) {
        if self.predictions_enabled == enabled {
            return;
        }
        self.as_mut().rust_mut().predictions_enabled = enabled;
        self.predictions_enabled_changed();
        SETTINGS.call(
            "SetProperty",
            ("keyboardPredictiveText", Value::from(enabled)),
        );
    }

    fn get_language_name(&self, language_id: &QString) -> QString {
        let id = language_id.to_string();
        LANGUAGES
            .iter()
            .find(|(k, _)| *k == id)
            .map_or_else(|| language_id.clone(), |(_, v)| q(v))
    }
}

// ---------------------------------------------------------------------------
// SettingsController
// ---------------------------------------------------------------------------

const NETWORK: Service = Service::shell("Network");
const BLUETOOTH: Service = Service::shell("Bluetooth");

#[allow(clippy::struct_excessive_bools, reason = "dialog state properties")]
pub struct SettingsControllerRust {
    notification_apps: QList<QVariant>,
    notification_apps_revision: i32,
    app_notif_map: HashMap<String, bool>,
    os_version: QString,
    kernel_version: QString,
    device_model: QString,
    display_resolution: QString,
    display_refresh_rate: QString,
    display_dpi: QString,
    display_scale: QString,
    open_source_licenses: QList<QVariant>,
    wifi_dialog_visible: bool,
    wifi_dialog_ssid: QString,
    wifi_dialog_strength: i32,
    wifi_dialog_security: QString,
    wifi_dialog_secured: bool,
    wifi_dialog_connecting: bool,
    wifi_dialog_error: QString,
    wifi_dialog_password: QString,
    wifi_dialog_hidden: bool,
    bluetooth_dialog_visible: bool,
    bluetooth_dialog_name: QString,
    bluetooth_dialog_address: QString,
    bluetooth_dialog_type: QString,
    bluetooth_dialog_mode: QString,
    bluetooth_dialog_passkey: QString,
    bluetooth_dialog_pairing: bool,
    bluetooth_dialog_error: QString,
}

fn read_trimmed(path: &str) -> Option<String> {
    fs::read_to_string(path)
        .ok()
        .map(|s| {
            s.trim_matches(|c: char| c == '\0' || c.is_whitespace())
                .to_owned()
        })
        .filter(|s| !s.is_empty())
}

fn os_pretty_name() -> String {
    if let Ok(text) = fs::read_to_string("/etc/os-release") {
        for line in text.lines() {
            if let Some(val) = line.strip_prefix("PRETTY_NAME=") {
                return val.trim_matches('"').to_owned();
            }
        }
    }
    "Linux".to_owned()
}

fn licenses_list() -> QList<QVariant> {
    let item = |title: &str, subtitle: &str, value: &str| -> QVariant {
        let mut m = QMap::<QMapPair_QString_QVariant>::default();
        m.insert(q("title"), QVariant::from(&q(title)));
        m.insert(q("subtitle"), QVariant::from(&q(subtitle)));
        m.insert(q("value"), QVariant::from(&q(value)));
        QVariant::from(&m)
    };
    let section = |title: &str, entries: &[(&str, &str, &str)]| -> QVariant {
        let mut list = QList::<QVariant>::default();
        for (t, s, v) in entries {
            list.append(item(t, s, v));
        }
        let mut m = QMap::<QMapPair_QString_QVariant>::default();
        m.insert(q("title"), QVariant::from(&q(title)));
        m.insert(q("items"), QVariant::from(&list));
        QVariant::from(&m)
    };
    let mut out = QList::<QVariant>::default();
    out.append(section(
        "Marathon OS",
        &[("Marathon Shell", "Core shell and system apps", "Apache-2.0")],
    ));
    out.append(section(
        "Third-party components",
        &[
            (
                "Qt 6",
                "Qt Core, QML, Quick, Wayland, WebEngine",
                "LGPL-3.0 / GPL-3.0",
            ),
            ("LunaSVG", "SVG rendering backend", "MIT"),
            ("PlutoVG", "Vector graphics rasterizer (via LunaSVG)", "MIT"),
            (
                "Hunspell",
                "Spell checking and predictions",
                "MPL-1.1 / LGPL-2.1 / GPL-2.0",
            ),
            ("Wayland Protocols", "Wayland compositor + protocols", "MIT"),
            ("GStreamer", "Media playback backend", "LGPL-2.1"),
            ("PulseAudio", "Audio routing backend", "LGPL-2.1"),
            ("Linux-PAM", "Authentication framework", "BSD-3-Clause"),
        ],
    ));
    out
}

fn build_notification_apps(map: &HashMap<String, bool>) -> QList<QVariant> {
    let mut list = QList::<QVariant>::default();
    for app in apps::scan() {
        let enabled = map.get(&app.id).copied().unwrap_or(true);
        let mut entry = QMap::<QMapPair_QString_QVariant>::default();
        entry.insert(q("id"), QVariant::from(&q(&app.id)));
        entry.insert(q("name"), QVariant::from(&q(&app.name)));
        entry.insert(q("enabled"), QVariant::from(&enabled));
        list.append(QVariant::from(&entry));
    }
    list
}

impl Default for SettingsControllerRust {
    fn default() -> Self {
        let ostype = read_trimmed("/proc/sys/kernel/ostype").unwrap_or_else(|| "Linux".to_owned());
        let osrel = read_trimmed("/proc/sys/kernel/osrelease").unwrap_or_default();
        let model = read_trimmed("/sys/devices/virtual/dmi/id/product_name")
            .or_else(|| read_trimmed("/sys/firmware/devicetree/base/model"))
            .or_else(|| read_trimmed("/proc/sys/kernel/hostname"))
            .unwrap_or_else(|| std::env::consts::ARCH.to_owned());
        let app_notif_map = HashMap::new();
        Self {
            notification_apps: build_notification_apps(&app_notif_map),
            notification_apps_revision: 0,
            app_notif_map,
            os_version: q(&os_pretty_name()),
            kernel_version: q(format!("{ostype} {osrel}").trim()),
            device_model: q(&model),
            display_resolution: QString::default(),
            display_refresh_rate: QString::default(),
            display_dpi: QString::default(),
            display_scale: QString::default(),
            open_source_licenses: licenses_list(),
            wifi_dialog_visible: false,
            wifi_dialog_ssid: QString::default(),
            wifi_dialog_strength: 0,
            wifi_dialog_security: QString::default(),
            wifi_dialog_secured: true,
            wifi_dialog_connecting: false,
            wifi_dialog_error: QString::default(),
            wifi_dialog_password: QString::default(),
            wifi_dialog_hidden: false,
            bluetooth_dialog_visible: false,
            bluetooth_dialog_name: QString::default(),
            bluetooth_dialog_address: QString::default(),
            bluetooth_dialog_type: QString::default(),
            bluetooth_dialog_mode: QString::default(),
            bluetooth_dialog_passkey: QString::default(),
            bluetooth_dialog_pairing: false,
            bluetooth_dialog_error: QString::default(),
        }
    }
}

impl cxx_qt::Initialize for SettingsController {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        relay(qt.clone(), NETWORK, "ConnectionSuccess", |mut obj, ()| {
            let mut r = obj.as_mut().rust_mut();
            r.wifi_dialog_connecting = false;
            r.wifi_dialog_error = QString::default();
            r.wifi_dialog_password = QString::default();
            r.wifi_dialog_hidden = false;
            r.wifi_dialog_visible = false;
            obj.wifi_dialog_changed();
        });
        relay(
            qt.clone(),
            NETWORK,
            "ConnectionFailed",
            |mut obj, (msg,): (String,)| {
                let mut r = obj.as_mut().rust_mut();
                r.wifi_dialog_connecting = false;
                r.wifi_dialog_error = q(&msg);
                obj.wifi_dialog_changed();
            },
        );
        relay(
            qt.clone(),
            BLUETOOTH,
            "PairingSucceeded",
            |mut obj, (_addr,): (String,)| {
                let mut r = obj.as_mut().rust_mut();
                r.bluetooth_dialog_pairing = false;
                r.bluetooth_dialog_error = QString::default();
                r.bluetooth_dialog_visible = false;
                obj.bluetooth_dialog_changed();
            },
        );
        relay(
            qt.clone(),
            BLUETOOTH,
            "PairingFailed",
            |mut obj, (_addr, err): (String, String)| {
                let mut r = obj.as_mut().rust_mut();
                r.bluetooth_dialog_pairing = false;
                r.bluetooth_dialog_error = q(&err);
                obj.bluetooth_dialog_changed();
            },
        );
        relay(
            qt.clone(),
            BLUETOOTH,
            "PinRequested",
            |obj, (addr, name): (String, String)| {
                obj.show_bluetooth_dialog(&q(&name), &q(&addr), &q("device"), &q("pin"));
            },
        );
        relay(
            qt.clone(),
            BLUETOOTH,
            "PasskeyRequested",
            |obj, (addr, name): (String, String)| {
                obj.show_bluetooth_dialog(&q(&name), &q(&addr), &q("device"), &q("passkey"));
            },
        );
        relay(
            qt.clone(),
            BLUETOOTH,
            "PasskeyConfirmation",
            |obj, (addr, name, passkey): (String, String, u32)| {
                obj.show_bluetooth_passkey_confirmation(
                    &q(&name),
                    &q(&addr),
                    &q("device"),
                    passkey,
                );
            },
        );
        relay(
            qt.clone(),
            SETTINGS,
            "PropertyChanged",
            |obj, (name, value): (String, OwnedValue)| {
                if name == "appNotificationSettings" {
                    apply_notification_settings(obj, Some(&value));
                }
            },
        );
        mirror(qt, SETTINGS, "system", |obj, update| {
            if let Update::State(s) = &update {
                apply_notification_settings(obj, s.get("appNotificationSettings"));
            }
        });
    }
}

fn apply_notification_settings(mut obj: Pin<&mut SettingsController>, v: Option<&OwnedValue>) {
    let mut map = HashMap::new();
    if let Some(qmap) = v.and_then(QMap::<QMapPair_QString_QVariant>::from_value) {
        for (k, val) in &qmap {
            map.insert(k.to_string(), val.value::<bool>().unwrap_or(true));
        }
    }
    let mut r = obj.as_mut().rust_mut();
    r.notification_apps = build_notification_apps(&map);
    r.app_notif_map = map;
    r.notification_apps_revision += 1;
    obj.notification_apps_changed();
}

impl SettingsController {
    fn init_display(
        mut self: Pin<&mut Self>,
        resolution: &QString,
        refresh_rate: &QString,
        dpi: &QString,
        scale: &QString,
    ) {
        let mut r = self.as_mut().rust_mut();
        r.display_resolution = resolution.clone();
        r.display_refresh_rate = refresh_rate.clone();
        r.display_dpi = dpi.clone();
        r.display_scale = scale.clone();
        self.system_info_changed();
    }

    fn set_notification_enabled(mut self: Pin<&mut Self>, app_id: &QString, enabled: bool) {
        let mut r = self.as_mut().rust_mut();
        r.app_notif_map.insert(app_id.to_string(), enabled);
        r.notification_apps = build_notification_apps(&r.app_notif_map);
        r.notification_apps_revision += 1;
        let mut wire = HashMap::<String, Value<'static>>::new();
        for (k, v) in &r.app_notif_map {
            wire.insert(k.clone(), Value::from(*v));
        }
        self.notification_apps_changed();
        SETTINGS.call(
            "SetProperty",
            ("appNotificationSettings", Value::from(wire)),
        );
    }

    fn show_wifi_dialog(
        mut self: Pin<&mut Self>,
        ssid: &QString,
        strength: i32,
        security: &QString,
        secured: bool,
    ) {
        let mut r = self.as_mut().rust_mut();
        if &r.wifi_dialog_ssid != ssid || r.wifi_dialog_hidden {
            r.wifi_dialog_password = QString::default();
        }
        r.wifi_dialog_hidden = false;
        r.wifi_dialog_ssid = ssid.clone();
        r.wifi_dialog_strength = strength;
        r.wifi_dialog_security = if security.is_empty() {
            q("WPA2")
        } else {
            security.clone()
        };
        r.wifi_dialog_secured = secured;
        r.wifi_dialog_connecting = false;
        r.wifi_dialog_error = QString::default();
        r.wifi_dialog_visible = true;
        self.wifi_dialog_changed();
    }

    fn dismiss_wifi_dialog(mut self: Pin<&mut Self>) {
        if self.wifi_dialog_visible {
            self.as_mut().rust_mut().wifi_dialog_visible = false;
            self.wifi_dialog_changed();
        }
    }

    fn submit_wifi_password(mut self: Pin<&mut Self>, password: &QString) {
        let ssid = self.wifi_dialog_ssid.to_string();
        let pw = password.to_string();
        let mut r = self.as_mut().rust_mut();
        r.wifi_dialog_connecting = true;
        r.wifi_dialog_password = password.clone();
        r.wifi_dialog_error = QString::default();
        self.wifi_dialog_changed();
        NETWORK.call("ConnectToNetwork", (ssid, pw));
    }

    fn connect_saved_network(
        mut self: Pin<&mut Self>,
        ssid: &QString,
        strength: i32,
        security: &QString,
        secured: bool,
    ) {
        self.as_mut()
            .show_wifi_dialog(ssid, strength, security, secured);
        self.submit_wifi_password(&QString::default());
    }

    fn show_hidden_network_dialog(mut self: Pin<&mut Self>) {
        let mut r = self.as_mut().rust_mut();
        if !r.wifi_dialog_hidden {
            r.wifi_dialog_ssid = QString::default();
            r.wifi_dialog_security = q("wpa-psk");
            r.wifi_dialog_password = QString::default();
        }
        r.wifi_dialog_hidden = true;
        r.wifi_dialog_connecting = false;
        r.wifi_dialog_error = QString::default();
        r.wifi_dialog_visible = true;
        self.wifi_dialog_changed();
    }

    fn connect_hidden_network(
        mut self: Pin<&mut Self>,
        ssid: &QString,
        security: &QString,
        password: &QString,
    ) {
        let mut r = self.as_mut().rust_mut();
        r.wifi_dialog_hidden = true;
        r.wifi_dialog_visible = true;
        r.wifi_dialog_ssid = ssid.clone();
        r.wifi_dialog_security = security.clone();
        r.wifi_dialog_password = password.clone();
        r.wifi_dialog_connecting = true;
        r.wifi_dialog_error = QString::default();
        self.wifi_dialog_changed();
        NETWORK.call(
            "ConnectToHiddenNetwork",
            (ssid.to_string(), security.to_string(), password.to_string()),
        );
    }

    fn show_bluetooth_dialog(
        mut self: Pin<&mut Self>,
        name: &QString,
        address: &QString,
        device_type: &QString,
        mode: &QString,
    ) {
        let mut r = self.as_mut().rust_mut();
        r.bluetooth_dialog_name = name.clone();
        r.bluetooth_dialog_address = address.clone();
        r.bluetooth_dialog_type = if device_type.is_empty() {
            q("device")
        } else {
            device_type.clone()
        };
        r.bluetooth_dialog_mode = if mode.is_empty() {
            q("justworks")
        } else {
            mode.clone()
        };
        r.bluetooth_dialog_passkey = QString::default();
        r.bluetooth_dialog_pairing = false;
        r.bluetooth_dialog_error = QString::default();
        r.bluetooth_dialog_visible = true;
        self.bluetooth_dialog_changed();
    }

    fn show_bluetooth_passkey_confirmation(
        mut self: Pin<&mut Self>,
        name: &QString,
        address: &QString,
        device_type: &QString,
        passkey: u32,
    ) {
        let mut r = self.as_mut().rust_mut();
        r.bluetooth_dialog_name = name.clone();
        r.bluetooth_dialog_address = address.clone();
        r.bluetooth_dialog_type = if device_type.is_empty() {
            q("device")
        } else {
            device_type.clone()
        };
        r.bluetooth_dialog_mode = q("confirm");
        r.bluetooth_dialog_passkey = q(&passkey.to_string());
        r.bluetooth_dialog_pairing = false;
        r.bluetooth_dialog_error = QString::default();
        r.bluetooth_dialog_visible = true;
        self.bluetooth_dialog_changed();
    }

    fn dismiss_bluetooth_dialog(mut self: Pin<&mut Self>) {
        if self.bluetooth_dialog_visible {
            self.as_mut().rust_mut().bluetooth_dialog_visible = false;
            self.bluetooth_dialog_changed();
        }
    }

    fn submit_bluetooth_pin(mut self: Pin<&mut Self>, pin: &QString) {
        let addr = self.bluetooth_dialog_address.to_string();
        let mut r = self.as_mut().rust_mut();
        r.bluetooth_dialog_pairing = true;
        r.bluetooth_dialog_error = QString::default();
        self.bluetooth_dialog_changed();
        BLUETOOTH.call("PairDevice", (addr, pin.to_string()));
    }

    fn submit_bluetooth_passkey(self: Pin<&mut Self>, passkey: &QString) {
        self.submit_bluetooth_pin(passkey);
    }

    fn confirm_bluetooth_pairing(mut self: Pin<&mut Self>, accepted: bool) {
        let addr = self.bluetooth_dialog_address.to_string();
        BLUETOOTH.call("ConfirmPairing", (addr, accepted));
        if accepted {
            self.as_mut().rust_mut().bluetooth_dialog_pairing = true;
            self.bluetooth_dialog_changed();
        } else {
            self.dismiss_bluetooth_dialog();
        }
    }

    fn cancel_bluetooth_pairing(self: Pin<&mut Self>) {
        let addr = self.bluetooth_dialog_address.to_string();
        BLUETOOTH.call("CancelPairing", (addr,));
        self.dismiss_bluetooth_dialog();
    }

    fn bluetooth_pairing_mode_text(&self, mode: &QString) -> QString {
        match mode.to_string().as_str() {
            "pin" => q("Enter PIN to pair"),
            "passkey" => q("Enter passkey displayed on device"),
            "confirm" => q("Confirm pairing code"),
            _ => q("Ready to pair"),
        }
    }

    fn bluetooth_help_text(&self, mode: &QString) -> QString {
        match mode.to_string().as_str() {
            "pin" => q("Enter the PIN shown on your device (usually 0000 or 1234)"),
            "passkey" => q("Type the 6-digit passkey displayed on the device"),
            "confirm" => q("Make sure the code above matches what's shown on your device"),
            _ => q("No PIN required for this device"),
        }
    }

    fn bluetooth_can_pair(&self, mode: &QString, pin: &QString, passkey: &QString) -> bool {
        match mode.to_string().as_str() {
            "confirm" | "justworks" => true,
            "pin" => pin.len() >= 4,
            "passkey" => passkey.len() == 6,
            _ => false,
        }
    }

    fn lockout_status_text(&self, locked_out: bool, seconds_remaining: i32) -> QString {
        if locked_out {
            q(&format!("Locked ({}s remaining)", seconds_remaining.max(0)))
        } else {
            q("Active")
        }
    }

    fn quick_pin_validation_error(&self, pin: &QString, password: &QString) -> QString {
        if pin.len() < 4 {
            q("PIN must be 4-6 digits")
        } else if password.to_string().trim().is_empty() {
            q("System password required")
        } else {
            QString::default()
        }
    }
}
