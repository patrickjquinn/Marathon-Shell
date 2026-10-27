//! `marathon::Settings`: the shell's settings, which QML binds and the
//! shell's services read, kept in `QSettings`' file (`marathon-os/Marathon
//! Shell.conf`) so an older image still reads them, and served as
//! `Settings1` to the Settings app and every app's own keys.

use std::collections::BTreeMap;
use std::fs;
use std::io::Write as _;
use std::os::unix::fs::OpenOptionsExt as _;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::OnceLock;
use std::time::Duration;

use async_channel::Sender;
use async_io::Timer;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QStringList, QUrl, QVariant};
use futures_lite::StreamExt;
use marathon_qt as qvariant;
use marathon_rt::dirs;
use zbus::fdo;
use zbus::message::Header;
use zbus::zvariant::OwnedValue;

use crate::ipc::{self, State};
use crate::qsettings::{Ini, Value};
use crate::{app_ids, gate, io, log, permissions};

#[cxx_qt::bridge(namespace = "marathon")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
        include!("cxx-qt-lib/qvariant.h");
        type QVariant = cxx_qt_lib::QVariant;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(f64, user_scale_factor, cxx_name = "userScaleFactor", READ, WRITE = set_user_scale_factor, NOTIFY)]
        #[qproperty(QString, wallpaper_path, cxx_name = "wallpaperPath", READ, WRITE = set_wallpaper_path, NOTIFY)]
        #[qproperty(QString, device_name, cxx_name = "deviceName", READ, WRITE = set_device_name, NOTIFY)]
        #[qproperty(bool, auto_lock, cxx_name = "autoLock", READ, WRITE = set_auto_lock, NOTIFY)]
        #[qproperty(i32, auto_lock_timeout, cxx_name = "autoLockTimeout", READ, WRITE = set_auto_lock_timeout, NOTIFY)]
        #[qproperty(bool, show_notification_previews, cxx_name = "showNotificationPreviews", READ, WRITE = set_show_notification_previews, NOTIFY)]
        #[qproperty(QString, time_format, cxx_name = "timeFormat", READ, WRITE = set_time_format, NOTIFY)]
        #[qproperty(QString, date_format, cxx_name = "dateFormat", READ, WRITE = set_date_format, NOTIFY)]
        #[qproperty(QString, ringtone, READ, WRITE = set_ringtone, NOTIFY)]
        #[qproperty(QString, notification_sound, cxx_name = "notificationSound", READ, WRITE = set_notification_sound, NOTIFY)]
        #[qproperty(QString, alarm_sound, cxx_name = "alarmSound", READ, WRITE = set_alarm_sound, NOTIFY)]
        #[qproperty(f64, media_volume, cxx_name = "mediaVolume", READ, WRITE = set_media_volume, NOTIFY)]
        #[qproperty(f64, ringtone_volume, cxx_name = "ringtoneVolume", READ, WRITE = set_ringtone_volume, NOTIFY)]
        #[qproperty(f64, alarm_volume, cxx_name = "alarmVolume", READ, WRITE = set_alarm_volume, NOTIFY)]
        #[qproperty(f64, notification_volume, cxx_name = "notificationVolume", READ, WRITE = set_notification_volume, NOTIFY)]
        #[qproperty(f64, system_volume, cxx_name = "systemVolume", READ, WRITE = set_system_volume, NOTIFY)]
        #[qproperty(bool, dnd_enabled, cxx_name = "dndEnabled", READ, WRITE = set_dnd_enabled, NOTIFY)]
        #[qproperty(bool, vibration_enabled, cxx_name = "vibrationEnabled", READ, WRITE = set_vibration_enabled, NOTIFY)]
        #[qproperty(bool, reduce_motion, cxx_name = "reduceMotion", READ, WRITE = set_reduce_motion, NOTIFY)]
        #[qproperty(QString, time_zone, cxx_name = "timeZone", READ, WRITE = set_time_zone, NOTIFY)]
        #[qproperty(bool, automatic_time, cxx_name = "automaticTime", READ, WRITE = set_automatic_time, NOTIFY)]
        #[qproperty(bool, automatic_time_zone, cxx_name = "automaticTimeZone", READ, WRITE = set_automatic_time_zone, NOTIFY)]
        #[qproperty(QString, audio_profile, cxx_name = "audioProfile", READ, WRITE = set_audio_profile, NOTIFY)]
        #[qproperty(i32, screen_timeout, cxx_name = "screenTimeout", READ, WRITE = set_screen_timeout, NOTIFY)]
        #[qproperty(bool, auto_brightness, cxx_name = "autoBrightness", READ, WRITE = set_auto_brightness, NOTIFY)]
        #[qproperty(QString, status_bar_clock_position, cxx_name = "statusBarClockPosition", READ, WRITE = set_status_bar_clock_position, NOTIFY)]
        #[qproperty(bool, show_notifications_on_lock_screen, cxx_name = "showNotificationsOnLockScreen", READ, WRITE = set_show_notifications_on_lock_screen, NOTIFY)]
        #[qproperty(bool, filter_mobile_friendly_apps, cxx_name = "filterMobileFriendlyApps", READ, WRITE = set_filter_mobile_friendly_apps, NOTIFY)]
        #[qproperty(QStringList, hidden_apps, cxx_name = "hiddenApps", READ, WRITE = set_hidden_apps, NOTIFY)]
        #[qproperty(QString, app_sort_order, cxx_name = "appSortOrder", READ, WRITE = set_app_sort_order, NOTIFY)]
        #[qproperty(i32, app_grid_columns, cxx_name = "appGridColumns", READ, WRITE = set_app_grid_columns, NOTIFY)]
        #[qproperty(bool, search_native_apps, cxx_name = "searchNativeApps", READ, WRITE = set_search_native_apps, NOTIFY)]
        #[qproperty(bool, show_notification_badges, cxx_name = "showNotificationBadges", READ, WRITE = set_show_notification_badges, NOTIFY)]
        #[qproperty(QMap_QString_QVariant, app_notification_settings, cxx_name = "appNotificationSettings", READ, WRITE = set_app_notification_settings, NOTIFY)]
        #[qproperty(bool, show_frequent_apps, cxx_name = "showFrequentApps", READ, WRITE = set_show_frequent_apps, NOTIFY)]
        #[qproperty(QMap_QString_QVariant, default_apps, cxx_name = "defaultApps", READ, WRITE = set_default_apps, NOTIFY)]
        #[qproperty(bool, first_run_complete, cxx_name = "firstRunComplete", READ, WRITE = set_first_run_complete, NOTIFY)]
        #[qproperty(QStringList, enabled_quick_settings_tiles, cxx_name = "enabledQuickSettingsTiles", READ, WRITE = set_enabled_quick_settings_tiles, NOTIFY)]
        #[qproperty(QStringList, quick_settings_tile_order, cxx_name = "quickSettingsTileOrder", READ, WRITE = set_quick_settings_tile_order, NOTIFY)]
        #[qproperty(bool, keyboard_auto_correction, cxx_name = "keyboardAutoCorrection", READ, WRITE = set_keyboard_auto_correction, NOTIFY)]
        #[qproperty(bool, keyboard_auto_capitalize, cxx_name = "keyboardAutoCapitalize", READ, WRITE = set_keyboard_auto_capitalize, NOTIFY)]
        #[qproperty(bool, keyboard_predictive_text, cxx_name = "keyboardPredictiveText", READ, WRITE = set_keyboard_predictive_text, NOTIFY)]
        #[qproperty(QString, keyboard_haptic_strength, cxx_name = "keyboardHapticStrength", READ, WRITE = set_keyboard_haptic_strength, NOTIFY)]
        #[qproperty(QString, keyboard_language, cxx_name = "keyboardLanguage", READ, WRITE = set_keyboard_language, NOTIFY)]
        #[qproperty(QString, language, READ, WRITE = set_language, NOTIFY)]
        #[qproperty(QList_QVariant, available_languages, cxx_name = "availableLanguages", READ = available_languages, CONSTANT)]
        #[qproperty(bool, unified_push_fallback_enabled, cxx_name = "unifiedPushFallbackEnabled", READ, WRITE = set_unified_push_fallback_enabled, NOTIFY)]
        type Settings = super::SettingsRust;

        /// timedated refused a time zone, automatic time or clock change.
        #[qsignal]
        #[cxx_name = "dateTimeChangeFailed"]
        fn date_time_change_failed(self: Pin<&mut Self>, reason: &QString);

        #[cxx_name = "setUserScaleFactor"]
        fn set_user_scale_factor(self: Pin<&mut Settings>, value: f64);
        #[cxx_name = "setWallpaperPath"]
        fn set_wallpaper_path(self: Pin<&mut Settings>, value: &QString);
        #[cxx_name = "setDeviceName"]
        fn set_device_name(self: Pin<&mut Settings>, value: &QString);
        #[cxx_name = "setAutoLock"]
        fn set_auto_lock(self: Pin<&mut Settings>, value: bool);
        #[cxx_name = "setAutoLockTimeout"]
        fn set_auto_lock_timeout(self: Pin<&mut Settings>, value: i32);
        #[cxx_name = "setShowNotificationPreviews"]
        fn set_show_notification_previews(self: Pin<&mut Settings>, value: bool);
        #[cxx_name = "setTimeFormat"]
        fn set_time_format(self: Pin<&mut Settings>, value: &QString);
        #[cxx_name = "setDateFormat"]
        fn set_date_format(self: Pin<&mut Settings>, value: &QString);
        #[cxx_name = "setRingtone"]
        fn set_ringtone(self: Pin<&mut Settings>, value: &QString);
        #[cxx_name = "setNotificationSound"]
        fn set_notification_sound(self: Pin<&mut Settings>, value: &QString);
        #[cxx_name = "setAlarmSound"]
        fn set_alarm_sound(self: Pin<&mut Settings>, value: &QString);
        #[cxx_name = "setMediaVolume"]
        fn set_media_volume(self: Pin<&mut Settings>, value: f64);
        #[cxx_name = "setRingtoneVolume"]
        fn set_ringtone_volume(self: Pin<&mut Settings>, value: f64);
        #[cxx_name = "setAlarmVolume"]
        fn set_alarm_volume(self: Pin<&mut Settings>, value: f64);
        #[cxx_name = "setNotificationVolume"]
        fn set_notification_volume(self: Pin<&mut Settings>, value: f64);
        #[cxx_name = "setSystemVolume"]
        fn set_system_volume(self: Pin<&mut Settings>, value: f64);
        #[cxx_name = "setDndEnabled"]
        fn set_dnd_enabled(self: Pin<&mut Settings>, value: bool);
        #[cxx_name = "setVibrationEnabled"]
        fn set_vibration_enabled(self: Pin<&mut Settings>, value: bool);
        #[cxx_name = "setReduceMotion"]
        fn set_reduce_motion(self: Pin<&mut Settings>, value: bool);
        #[cxx_name = "setTimeZone"]
        fn set_time_zone(self: Pin<&mut Settings>, value: &QString);
        #[cxx_name = "setAutomaticTime"]
        fn set_automatic_time(self: Pin<&mut Settings>, value: bool);
        #[cxx_name = "setAutomaticTimeZone"]
        fn set_automatic_time_zone(self: Pin<&mut Settings>, value: bool);
        #[cxx_name = "setAudioProfile"]
        fn set_audio_profile(self: Pin<&mut Settings>, value: &QString);
        #[cxx_name = "setScreenTimeout"]
        fn set_screen_timeout(self: Pin<&mut Settings>, value: i32);
        #[cxx_name = "setAutoBrightness"]
        fn set_auto_brightness(self: Pin<&mut Settings>, value: bool);
        #[cxx_name = "setStatusBarClockPosition"]
        fn set_status_bar_clock_position(self: Pin<&mut Settings>, value: &QString);
        #[cxx_name = "setShowNotificationsOnLockScreen"]
        fn set_show_notifications_on_lock_screen(self: Pin<&mut Settings>, value: bool);
        #[cxx_name = "setFilterMobileFriendlyApps"]
        fn set_filter_mobile_friendly_apps(self: Pin<&mut Settings>, value: bool);
        #[cxx_name = "setHiddenApps"]
        fn set_hidden_apps(self: Pin<&mut Settings>, value: &QStringList);
        #[cxx_name = "setAppSortOrder"]
        fn set_app_sort_order(self: Pin<&mut Settings>, value: &QString);
        #[cxx_name = "setAppGridColumns"]
        fn set_app_grid_columns(self: Pin<&mut Settings>, value: i32);
        #[cxx_name = "setSearchNativeApps"]
        fn set_search_native_apps(self: Pin<&mut Settings>, value: bool);
        #[cxx_name = "setShowNotificationBadges"]
        fn set_show_notification_badges(self: Pin<&mut Settings>, value: bool);
        #[cxx_name = "setAppNotificationSettings"]
        fn set_app_notification_settings(self: Pin<&mut Settings>, value: &QMap_QString_QVariant);
        #[cxx_name = "setShowFrequentApps"]
        fn set_show_frequent_apps(self: Pin<&mut Settings>, value: bool);
        #[cxx_name = "setDefaultApps"]
        fn set_default_apps(self: Pin<&mut Settings>, value: &QMap_QString_QVariant);
        #[cxx_name = "setFirstRunComplete"]
        fn set_first_run_complete(self: Pin<&mut Settings>, value: bool);
        #[cxx_name = "setEnabledQuickSettingsTiles"]
        fn set_enabled_quick_settings_tiles(self: Pin<&mut Settings>, value: &QStringList);
        #[cxx_name = "setQuickSettingsTileOrder"]
        fn set_quick_settings_tile_order(self: Pin<&mut Settings>, value: &QStringList);
        #[cxx_name = "setKeyboardAutoCorrection"]
        fn set_keyboard_auto_correction(self: Pin<&mut Settings>, value: bool);
        #[cxx_name = "setKeyboardAutoCapitalize"]
        fn set_keyboard_auto_capitalize(self: Pin<&mut Settings>, value: bool);
        #[cxx_name = "setKeyboardPredictiveText"]
        fn set_keyboard_predictive_text(self: Pin<&mut Settings>, value: bool);
        #[cxx_name = "setKeyboardHapticStrength"]
        fn set_keyboard_haptic_strength(self: Pin<&mut Settings>, value: &QString);
        #[cxx_name = "setKeyboardLanguage"]
        fn set_keyboard_language(self: Pin<&mut Settings>, value: &QString);
        #[cxx_name = "setLanguage"]
        fn set_language(self: Pin<&mut Settings>, value: &QString);
        #[cxx_name = "availableLanguages"]
        fn available_languages(self: &Settings) -> QList_QVariant;
        #[cxx_name = "setUnifiedPushFallbackEnabled"]
        fn set_unified_push_fallback_enabled(self: Pin<&mut Settings>, value: bool);

        /// Reads the file; `screen_timeout` is the device's default.
        fn load(self: Pin<&mut Settings>, screen_timeout: i32);
        /// Any key: an app's own `<appId>/...` or one of the shell's.
        #[qinvokable]
        fn get(self: &Settings, key: &QString, default_value: &QVariant) -> QVariant;
        #[qinvokable]
        fn set(self: Pin<&mut Settings>, key: &QString, value: &QVariant);
        #[qinvokable]
        fn sync(self: &Settings);
        #[cxx_name = "isNotificationsEnabledForApp"]
        fn is_notifications_enabled_for_app(self: &Settings, app_id: &QString) -> bool;
        /// The app's own keys, when it is uninstalled.
        #[cxx_name = "removeAppKeys"]
        fn remove_app_keys(self: Pin<&mut Settings>, app_id: &QString);
    }

    impl cxx_qt::Threading for Settings {}
    impl cxx_qt::Initialize for Settings {}
}

use qobject::Settings;

type Map = QMap<QMapPair_QString_QVariant>;

/// A property's type, as the file and D-Bus keep it.
trait Field: Sized + PartialEq {
    type Arg<'a>;
    fn read(value: &Value) -> Option<Self>;
    fn value(&self) -> Value;
    fn own(arg: Self::Arg<'_>) -> Self;
    fn arg(&self) -> Self::Arg<'_>;
}

macro_rules! copy_field {
    ($ty:ty, $read:expr, $value:path) => {
        impl Field for $ty {
            type Arg<'a> = $ty;
            fn read(value: &Value) -> Option<Self> {
                $read(value)
            }
            fn value(&self) -> Value {
                $value((*self).into())
            }
            fn own(arg: $ty) -> Self {
                arg
            }
            fn arg(&self) -> $ty {
                *self
            }
        }
    };
}

copy_field!(bool, Value::as_bool, Value::Bool);
copy_field!(f64, Value::as_f64, Value::Double);
copy_field!(
    i32,
    |v: &Value| v.as_i64().and_then(|n| i32::try_from(n).ok()),
    Value::Int
);

impl Field for QString {
    type Arg<'a> = &'a QString;
    fn read(value: &Value) -> Option<Self> {
        value.as_text().map(|s| QString::from(&s))
    }
    fn value(&self) -> Value {
        Value::Text(self.to_string())
    }
    fn own(arg: &QString) -> Self {
        arg.clone()
    }
    fn arg(&self) -> &QString {
        self
    }
}

fn string_list(items: &[String]) -> QStringList {
    let mut list = QList::<QString>::default();
    for s in items {
        list.append(QString::from(s));
    }
    QStringList::from(&list)
}

impl Field for QStringList {
    type Arg<'a> = &'a QStringList;
    fn read(value: &Value) -> Option<Self> {
        Some(string_list(&value.as_list()))
    }
    fn value(&self) -> Value {
        Value::List(
            QList::<QString>::from(self)
                .iter()
                .map(ToString::to_string)
                .collect(),
        )
    }
    fn own(arg: &QStringList) -> Self {
        arg.clone()
    }
    fn arg(&self) -> &QStringList {
        self
    }
}

impl Field for Map {
    type Arg<'a> = &'a Map;
    fn read(value: &Value) -> Option<Self> {
        let Value::Map(entries) = value else {
            return None;
        };
        let mut map = Map::default();
        for (k, v) in entries {
            map.insert(QString::from(k), qvariant::to_qt(&v.to_dbus()));
        }
        Some(map)
    }
    fn value(&self) -> Value {
        Value::Map(
            self.iter()
                .map(|(k, v)| {
                    (
                        k.to_string(),
                        qvariant::from_qt(v).map_or(Value::Invalid, |v| Value::from_dbus(&v)),
                    )
                })
                .collect(),
        )
    }
    fn own(arg: &Map) -> Self {
        arg.clone()
    }
    fn arg(&self) -> &Map {
        self
    }
}

/// The properties: field, type and default, the file's key ("" for none),
/// the D-Bus name, the change signal and its hook, and the setter (`custom`
/// when written out below).
macro_rules! properties {
    (@setter custom $($rest:tt)*) => {};
    (@setter $field:ident, $changed:ident, $setter:ident($arg:ty)) => {
        pub(crate) fn $setter(mut self: Pin<&mut Self>, value: $arg) {
            let value = Field::own(value);
            if self.$field != value {
                self.as_mut().rust_mut().$field = value;
                self.as_mut().$changed();
            }
        }
    };
    ($($field:ident: $ty:ty = $default:expr, $key:literal, $name:literal, $changed:ident, $hook:ident, $setter:ident($arg:ty) $($custom:ident)?;)*) => {
        pub struct SettingsRust {
            $($field: $ty,)*
            ini: Ini,
            saves: u64,
            dirty: bool,
        }

        impl Default for SettingsRust {
            fn default() -> Self {
                Self { $($field: $default,)* ini: Ini::default(), saves: 0, dirty: false }
            }
        }

        impl Settings {
            $(properties!(@setter $($custom)? $field, $changed, $setter($arg));)*

            /// The properties from the file, each one's default where it has none.
            fn read_properties(mut self: Pin<&mut Self>) {
                let mut rust = self.as_mut().rust_mut();
                $(if let Some(value) = rust.ini.0.get($key).and_then(<$ty>::read) {
                    rust.$field = value;
                })*
            }

            fn write_properties(mut self: Pin<&mut Self>) {
                let mut rust = self.as_mut().rust_mut();
                $(if !$key.is_empty() {
                    let value = rust.$field.value();
                    rust.ini.0.insert($key.to_owned(), value);
                })*
            }

            /// Sets a property by its D-Bus name; false for no such property.
            fn set_named(mut self: Pin<&mut Self>, name: &str, value: &Value) -> bool {
                match name {
                    $($name => {
                        if let Some(value) = <$ty>::read(value) {
                            self.as_mut().$setter(Field::arg(&value));
                        }
                    })*
                    _ => return false,
                }
                true
            }

            fn watch(mut self: Pin<&mut Self>) {
                $(self.as_mut().$hook(|obj| obj.changed($name)).release();)*
            }
        }

        fn state(rust: &SettingsRust) -> State {
            [$(($name, rust.$field.value()),)*]
                .into_iter()
                .filter_map(|(name, value)| Some((name.to_owned(), value.to_dbus().try_to_owned().ok()?)))
                .collect()
        }
    };
}

properties! {
    user_scale_factor: f64 = 1.0, "ui/userScaleFactor", "userScaleFactor", user_scale_factor_changed, on_user_scale_factor_changed, set_user_scale_factor(f64) custom;
    wallpaper_path: QString = QString::from(&asset_url("wallpapers/meridian.jpg")), "ui/wallpaperPath", "wallpaperPath", wallpaper_path_changed, on_wallpaper_path_changed, set_wallpaper_path(&QString);
    device_name: QString = QString::from("Marathon OS"), "system/deviceName", "deviceName", device_name_changed, on_device_name_changed, set_device_name(&QString) custom;
    auto_lock: bool = true, "system/autoLock", "autoLock", auto_lock_changed, on_auto_lock_changed, set_auto_lock(bool);
    auto_lock_timeout: i32 = 0, "system/autoLockTimeout", "autoLockTimeout", auto_lock_timeout_changed, on_auto_lock_timeout_changed, set_auto_lock_timeout(i32);
    show_notification_previews: bool = true, "system/showNotificationPreviews", "showNotificationPreviews", show_notification_previews_changed, on_show_notification_previews_changed, set_show_notification_previews(bool);
    time_format: QString = QString::from(""), "system/timeFormat", "timeFormat", time_format_changed, on_time_format_changed, set_time_format(&QString);
    date_format: QString = QString::from("US"), "system/dateFormat", "dateFormat", date_format_changed, on_date_format_changed, set_date_format(&QString);
    ringtone: QString = QString::from(&asset_url("sounds/phone/bbpro1.wav")), "audio/ringtone", "ringtone", ringtone_changed, on_ringtone_changed, set_ringtone(&QString);
    notification_sound: QString = QString::from(&asset_url("sounds/text/chime.wav")), "audio/notificationSound", "notificationSound", notification_sound_changed, on_notification_sound_changed, set_notification_sound(&QString);
    alarm_sound: QString = QString::from(&asset_url("sounds/alarms/alarm_sunrise.wav")), "audio/alarmSound", "alarmSound", alarm_sound_changed, on_alarm_sound_changed, set_alarm_sound(&QString);
    media_volume: f64 = 0.6, "audio/mediaVolume", "mediaVolume", media_volume_changed, on_media_volume_changed, set_media_volume(f64) custom;
    ringtone_volume: f64 = 0.8, "audio/ringtoneVolume", "ringtoneVolume", ringtone_volume_changed, on_ringtone_volume_changed, set_ringtone_volume(f64) custom;
    alarm_volume: f64 = 0.9, "audio/alarmVolume", "alarmVolume", alarm_volume_changed, on_alarm_volume_changed, set_alarm_volume(f64) custom;
    notification_volume: f64 = 0.7, "audio/notificationVolume", "notificationVolume", notification_volume_changed, on_notification_volume_changed, set_notification_volume(f64) custom;
    system_volume: f64 = 0.5, "audio/systemVolume", "systemVolume", system_volume_changed, on_system_volume_changed, set_system_volume(f64) custom;
    dnd_enabled: bool = false, "audio/dndEnabled", "dndEnabled", dnd_enabled_changed, on_dnd_enabled_changed, set_dnd_enabled(bool);
    vibration_enabled: bool = true, "audio/vibrationEnabled", "vibrationEnabled", vibration_enabled_changed, on_vibration_enabled_changed, set_vibration_enabled(bool);
    reduce_motion: bool = false, "accessibility/reduceMotion", "reduceMotion", reduce_motion_changed, on_reduce_motion_changed, set_reduce_motion(bool);
    time_zone: QString = QString::from(&local_zone()), "", "timeZone", time_zone_changed, on_time_zone_changed, set_time_zone(&QString) custom;
    automatic_time: bool = true, "", "automaticTime", automatic_time_changed, on_automatic_time_changed, set_automatic_time(bool) custom;
    automatic_time_zone: bool = true, "time/automaticTimeZone", "automaticTimeZone", automatic_time_zone_changed, on_automatic_time_zone_changed, set_automatic_time_zone(bool);
    audio_profile: QString = QString::from("normal"), "audio/audioProfile", "audioProfile", audio_profile_changed, on_audio_profile_changed, set_audio_profile(&QString);
    screen_timeout: i32 = 300_000, "display/screenTimeout", "screenTimeout", screen_timeout_changed, on_screen_timeout_changed, set_screen_timeout(i32);
    auto_brightness: bool = true, "display/autoBrightness", "autoBrightness", auto_brightness_changed, on_auto_brightness_changed, set_auto_brightness(bool);
    status_bar_clock_position: QString = QString::from("center"), "display/statusBarClockPosition", "statusBarClockPosition", status_bar_clock_position_changed, on_status_bar_clock_position_changed, set_status_bar_clock_position(&QString) custom;
    show_notifications_on_lock_screen: bool = true, "notifications/showOnLockScreen", "showNotificationsOnLockScreen", show_notifications_on_lock_screen_changed, on_show_notifications_on_lock_screen_changed, set_show_notifications_on_lock_screen(bool);
    filter_mobile_friendly_apps: bool = true, "apps/filterMobileFriendly", "filterMobileFriendlyApps", filter_mobile_friendly_apps_changed, on_filter_mobile_friendly_apps_changed, set_filter_mobile_friendly_apps(bool);
    hidden_apps: QStringList = string_list(&["terminal".into(), "test".into()]), "apps/hiddenApps", "hiddenApps", hidden_apps_changed, on_hidden_apps_changed, set_hidden_apps(&QStringList);
    app_sort_order: QString = QString::from("alphabetical"), "apps/sortOrder", "appSortOrder", app_sort_order_changed, on_app_sort_order_changed, set_app_sort_order(&QString);
    app_grid_columns: i32 = 0, "apps/gridColumns", "appGridColumns", app_grid_columns_changed, on_app_grid_columns_changed, set_app_grid_columns(i32);
    search_native_apps: bool = true, "apps/searchNativeApps", "searchNativeApps", search_native_apps_changed, on_search_native_apps_changed, set_search_native_apps(bool);
    show_notification_badges: bool = true, "apps/showBadges", "showNotificationBadges", show_notification_badges_changed, on_show_notification_badges_changed, set_show_notification_badges(bool);
    app_notification_settings: Map = Map::default(), "notifications/appSettings", "appNotificationSettings", app_notification_settings_changed, on_app_notification_settings_changed, set_app_notification_settings(&Map);
    show_frequent_apps: bool = false, "apps/showFrequentApps", "showFrequentApps", show_frequent_apps_changed, on_show_frequent_apps_changed, set_show_frequent_apps(bool);
    default_apps: Map = Map::default(), "", "defaultApps", default_apps_changed, on_default_apps_changed, set_default_apps(&Map);
    first_run_complete: bool = false, "system/firstRunComplete", "firstRunComplete", first_run_complete_changed, on_first_run_complete_changed, set_first_run_complete(bool);
    enabled_quick_settings_tiles: QStringList = string_list(&tiles()), "quicksettings/tiles", "enabledQuickSettingsTiles", enabled_quick_settings_tiles_changed, on_enabled_quick_settings_tiles_changed, set_enabled_quick_settings_tiles(&QStringList);
    quick_settings_tile_order: QStringList = string_list(&tiles()), "quicksettings/tileOrder", "quickSettingsTileOrder", quick_settings_tile_order_changed, on_quick_settings_tile_order_changed, set_quick_settings_tile_order(&QStringList);
    keyboard_auto_correction: bool = true, "keyboard/autoCorrection", "keyboardAutoCorrection", keyboard_auto_correction_changed, on_keyboard_auto_correction_changed, set_keyboard_auto_correction(bool);
    keyboard_auto_capitalize: bool = true, "keyboard/autoCapitalize", "keyboardAutoCapitalize", keyboard_auto_capitalize_changed, on_keyboard_auto_capitalize_changed, set_keyboard_auto_capitalize(bool);
    keyboard_predictive_text: bool = true, "keyboard/predictiveText", "keyboardPredictiveText", keyboard_predictive_text_changed, on_keyboard_predictive_text_changed, set_keyboard_predictive_text(bool);
    keyboard_haptic_strength: QString = QString::from("medium"), "keyboard/hapticStrength", "keyboardHapticStrength", keyboard_haptic_strength_changed, on_keyboard_haptic_strength_changed, set_keyboard_haptic_strength(&QString);
    keyboard_language: QString = QString::from("en_US"), "keyboard/language", "keyboardLanguage", keyboard_language_changed, on_keyboard_language_changed, set_keyboard_language(&QString);
    language: QString = QString::default(), "system/language", "language", language_changed, on_language_changed, set_language(&QString);
    unified_push_fallback_enabled: bool = false, "notifications/unifiedPushFallback", "unifiedPushFallbackEnabled", unified_push_fallback_enabled_changed, on_unified_push_fallback_enabled_changed, set_unified_push_fallback_enabled(bool);
}

impl Settings {
    #[allow(clippy::unused_self, reason = "the property getter takes the object")]
    fn available_languages(&self) -> QList<QVariant> {
        qvariant::languages()
    }
}

/// `MarathonQuickSettings.qml`'s tile ids.
fn tiles() -> Vec<String> {
    [
        "wifi",
        "cellular",
        "bluetooth",
        "airplane",
        "dnd",
        "torch",
        "location",
        "hotspot",
        "nightlight",
        "rotation",
        "autobrightness",
        "lowpower",
        "vibration",
        "power",
    ]
    .map(str::to_owned)
    .to_vec()
}

/// Where the shell's wallpapers and sounds are installed.
pub fn data_dir() -> Option<PathBuf> {
    if let Some(dir) = std::env::var("MARATHON_DATA_DIR")
        .ok()
        .filter(|d| !d.trim().is_empty())
    {
        return Some(PathBuf::from(dir.trim()));
    }
    [
        PathBuf::from("/usr/share/marathon-shell"),
        dirs::home().join(".local/share/marathon-shell"),
    ]
    .into_iter()
    .find(|d| d.is_dir())
}

fn file_url(path: &Path) -> String {
    QUrl::from_local_file(&QString::from(&*path.to_string_lossy())).to_string()
}

/// An installed asset's file URL, else the wallpaper built into the shell.
pub fn asset_url(relative: &str) -> String {
    if let Some(path) = data_dir().map(|d| d.join(relative)).filter(|p| p.exists()) {
        return file_url(&path);
    }
    relative.strip_prefix("wallpapers/").map_or_else(
        || relative.to_owned(),
        |file| format!("qrc:/wallpapers/{file}"),
    )
}

/// A built-in wallpaper or sound of an older image, at its installed path.
fn installed(path: &str) -> Option<String> {
    let relative = path
        .strip_prefix("qrc:/wallpapers/")
        .map(|f| format!("wallpapers/{f}"))
        .or_else(|| {
            path.strip_prefix("qrc:/sounds/resources/sounds/")
                .map(|f| format!("sounds/{f}"))
        })?;
    let file = data_dir()?.join(relative);
    file.exists().then(|| file_url(&file))
}

/// The sounds installed under `sounds/<dir>`, as file URLs.
fn sounds(dirs: &[&str]) -> QStringList {
    fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
        for entry in fs::read_dir(dir).into_iter().flatten().flatten() {
            let path = entry.path();
            if path.is_dir() {
                walk(&path, out);
            } else if path
                .extension()
                .is_some_and(|e| ["wav", "ogg", "mp3", "m4a"].iter().any(|x| e == *x))
            {
                out.push(path);
            }
        }
    }
    let mut found = Vec::new();
    for dir in dirs {
        let mut files = Vec::new();
        if let Some(base) = data_dir() {
            walk(&base.join("sounds").join(dir), &mut files);
        }
        files.sort_by_key(|p| p.to_string_lossy().to_lowercase());
        found.extend(files.iter().map(|p| file_url(p)));
    }
    string_list(&found)
}

const SCREEN_TIMEOUTS: [(&str, i32); 5] = [
    ("30 seconds", 30_000),
    ("1 minute", 60_000),
    ("2 minutes", 120_000),
    ("5 minutes", 300_000),
    ("Never", 0),
];

/// `file:///usr/share/sounds/ring_old_phone.ogg` is "Old Phone".
fn sound_name(path: &str) -> String {
    let path = path.strip_prefix("file://").unwrap_or(path);
    let file = path.rsplit('/').next().unwrap_or(path);
    let base = file
        .split('.')
        .next()
        .unwrap_or(file)
        .replace("alarm_", "")
        .replace("ring_", "");
    base.split(['_', '-', ' '])
        .map(|word| {
            let mut chars = word.chars();
            chars
                .next()
                .map_or_else(String::new, |c| c.to_uppercase().chain(chars).collect())
        })
        .collect::<Vec<_>>()
        .join(" ")
}

/// The zone `/etc/localtime` names.
fn local_zone() -> String {
    let target = fs::read_link("/etc/localtime").unwrap_or_default();
    let target = target.to_string_lossy();
    target.split_once("zoneinfo/").map_or_else(
        || {
            std::env::var("TZ")
                .unwrap_or_default()
                .trim_start_matches(':')
                .to_owned()
        },
        |(_, z)| z.to_owned(),
    )
}

extern "C" {
    fn tzset();
}

/// libc keeps the zone it read at start; local time and children follow `TZ`.
fn follow_zone(zone: &str) {
    std::env::set_var("TZ", format!(":{zone}"));
    // SAFETY: tzset only rereads TZ, on the GUI thread like every local-time call.
    unsafe { tzset() };
}

#[zbus::proxy(
    interface = "org.freedesktop.timedate1",
    default_service = "org.freedesktop.timedate1",
    default_path = "/org/freedesktop/timedate1"
)]
trait Timedate {
    fn set_timezone(&self, timezone: &str, interactive: bool) -> zbus::Result<()>;
    #[zbus(name = "SetNTP")]
    fn set_ntp(&self, use_ntp: bool, interactive: bool) -> zbus::Result<()>;
    fn set_time(&self, usec_utc: i64, relative: bool, interactive: bool) -> zbus::Result<()>;
    #[zbus(property)]
    fn timezone(&self) -> zbus::Result<String>;
    #[zbus(property, name = "NTP")]
    fn ntp(&self) -> zbus::Result<bool>;
}

#[zbus::proxy(
    interface = "org.freedesktop.hostname1",
    default_service = "org.freedesktop.hostname1",
    default_path = "/org/freedesktop/hostname1"
)]
trait Hostname {
    fn set_pretty_hostname(&self, hostname: &str, interactive: bool) -> zbus::Result<()>;
}

async fn timedate() -> zbus::Result<TimedateProxy<'static>> {
    TimedateProxy::new(&io::system_bus().await?).await
}

type Qt = cxx_qt::CxxQtThread<Settings>;

static QT: OnceLock<Qt> = OnceLock::new();

/// Runs `f` on the settings, on the GUI thread: how the shell's other Rust
/// objects read and change them.
pub(crate) fn with(f: impl FnOnce(Pin<&mut Settings>) + Send + 'static) {
    if let Some(qt) = QT.get() {
        qt.queue(f).ok();
    }
}

pub(crate) fn thread() -> Option<&'static Qt> {
    QT.get()
}

enum Timedated {
    Ntp(bool),
    Zone(String),
}

/// Runs a timedated change; a refusal resets `reset` and is reported.
fn ask_timedate<F, R>(
    qt: Qt,
    change: F,
    reset: fn(Pin<&mut Settings>),
    done: impl FnOnce(Pin<&mut Settings>) + Send + 'static,
) where
    F: FnOnce(TimedateProxy<'static>) -> R + Send + 'static,
    R: std::future::Future<Output = zbus::Result<()>> + Send,
{
    io::spawn(async move {
        let result = match timedate().await {
            Ok(proxy) => change(proxy).await,
            Err(e) => Err(e),
        };
        qt.queue(move |mut obj| match result {
            Ok(()) => done(obj),
            Err(e) => {
                log::warn("settings", format_args!("timedated: {e}"));
                reset(obj.as_mut());
                obj.date_time_change_failed(&QString::from(&e.to_string()));
            }
        })
        .ok();
    });
}

/// The file's writes, in order, off the GUI thread.
fn writer() -> &'static Sender<String> {
    static WRITER: OnceLock<Sender<String>> = OnceLock::new();
    WRITER.get_or_init(|| {
        let (tx, rx) = async_channel::unbounded::<String>();
        io::spawn(async move {
            while let Ok(text) = rx.recv().await {
                if let Err(e) = blocking::unblock(move || write(&text)).await {
                    log::warn("settings", format_args!("cannot save: {e}"));
                }
            }
        });
        tx
    })
}

fn file() -> PathBuf {
    dirs::config().join("marathon-os/Marathon Shell.conf")
}

/// As `QSaveFile`: a full new file, then a rename over the old one.
fn write(text: &str) -> std::io::Result<()> {
    let path = file();
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir)?;
    }
    let temp = path.with_extension("conf.new");
    let mut out = fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&temp)?;
    out.write_all(text.as_bytes())?;
    out.sync_all()?;
    fs::rename(&temp, &path)
}

impl Drop for SettingsRust {
    fn drop(&mut self) {
        if self.dirty {
            write(&self.ini.render()).ok();
        }
    }
}

impl cxx_qt::Initialize for Settings {
    fn initialize(mut self: Pin<&mut Self>) {
        self.as_mut().watch();
        self.as_mut()
            .on_date_time_change_failed(|_, reason| {
                ipc::signal("Settings", "DateTimeChangeFailed", (reason.to_string(),));
            })
            .release();
        let qt = self.qt_thread();
        QT.set(qt.clone()).ok();
        ipc::export("Settings", Settings1 { qt: qt.clone() });
        io::spawn(async move {
            let Ok(proxy) = timedate().await else { return };
            let ntp = proxy
                .receive_ntp_changed()
                .await
                .then(|c| async move { c.get().await.ok().map(Timedated::Ntp) });
            let zone = proxy
                .receive_timezone_changed()
                .await
                .then(|c| async move { c.get().await.ok().map(Timedated::Zone) });
            let mut changes = std::pin::pin!(ntp.or(zone));
            if let Ok(on) = proxy.ntp().await {
                qt.queue(move |obj| obj.timedated(Timedated::Ntp(on))).ok();
            }
            while let Some(change) = changes.next().await {
                if let Some(change) = change {
                    qt.queue(move |obj| obj.timedated(change)).ok();
                }
            }
        });
    }
}

macro_rules! volume_setters {
    ($($setter:ident: $field:ident, $changed:ident;)*) => {
        $(pub(crate) fn $setter(mut self: Pin<&mut Self>, value: f64) {
            let value = value.clamp(0.0, 1.0);
            if (self.$field - value).abs() > f64::EPSILON {
                self.as_mut().rust_mut().$field = value;
                self.as_mut().$changed();
            }
        })*
    };
}

impl Settings {
    volume_setters! {
        set_media_volume: media_volume, media_volume_changed;
        set_ringtone_volume: ringtone_volume, ringtone_volume_changed;
        set_alarm_volume: alarm_volume, alarm_volume_changed;
        set_notification_volume: notification_volume, notification_volume_changed;
        set_system_volume: system_volume, system_volume_changed;
    }

    /// Within every scale the first run and Settings offer, and some.
    fn set_user_scale_factor(mut self: Pin<&mut Self>, value: f64) {
        let value = value.clamp(0.5, 2.0);
        if (self.user_scale_factor - value).abs() > f64::EPSILON {
            self.as_mut().rust_mut().user_scale_factor = value;
            self.as_mut().user_scale_factor_changed();
        }
    }

    fn set_status_bar_clock_position(mut self: Pin<&mut Self>, value: &QString) {
        if ["left", "center", "right"].contains(&value.to_string().as_str()) {
            set!(
                self,
                status_bar_clock_position,
                status_bar_clock_position_changed,
                value.clone()
            );
        }
    }

    /// Also Bluetooth's and the network's name for the device.
    fn set_device_name(mut self: Pin<&mut Self>, value: &QString) {
        if self.device_name == *value {
            return;
        }
        self.as_mut().rust_mut().device_name = value.clone();
        self.as_mut().device_name_changed();
        let name = value.to_string();
        io::spawn(async move {
            let set = async {
                HostnameProxy::new(&io::system_bus().await?)
                    .await?
                    .set_pretty_hostname(&name, false)
                    .await
            };
            if let Err(e) = set.await {
                log::warn("settings", format_args!("SetPrettyHostname: {e}"));
            }
        });
    }

    fn set_time_zone(self: Pin<&mut Self>, value: &QString) {
        let zone = value.to_string();
        let known = Path::new("/usr/share/zoneinfo").join(&zone).is_file();
        if zone.is_empty() || !known || self.time_zone == *value {
            return;
        }
        let asked = zone.clone();
        ask_timedate(
            self.qt_thread(),
            move |p| async move { p.set_timezone(&asked, false).await },
            Settings::time_zone_changed,
            move |mut obj| {
                follow_zone(&zone);
                set!(obj, time_zone, time_zone_changed, QString::from(&zone));
            },
        );
    }

    fn set_automatic_time(self: Pin<&mut Self>, value: bool) {
        ask_timedate(
            self.qt_thread(),
            move |p| async move { p.set_ntp(value, false).await },
            Settings::automatic_time_changed,
            move |mut obj| {
                set!(obj, automatic_time, automatic_time_changed, value);
            },
        );
    }

    fn set_system_time(&self, msecs: i64) {
        ask_timedate(
            self.qt_thread(),
            move |p| async move { p.set_time(msecs * 1000, false, false).await },
            |_| {},
            |_| {},
        );
    }

    fn timedated(mut self: Pin<&mut Self>, change: Timedated) {
        match change {
            Timedated::Ntp(on) => set!(self, automatic_time, automatic_time_changed, on),
            Timedated::Zone(zone) => set!(self, time_zone, time_zone_changed, QString::from(&zone)),
        }
    }

    fn load(mut self: Pin<&mut Self>, screen_timeout: i32) {
        let mut ini = fs::read_to_string(file())
            .map(|t| Ini::parse(&t))
            .unwrap_or_default();
        let migrated = migrate(&mut ini);
        let mut rust = self.as_mut().rust_mut();
        rust.ini = ini;
        rust.screen_timeout = screen_timeout;
        rust.dirty = migrated;
        self.as_mut().read_properties();
        // Every "open in default..." resolves to one of Marathon's own apps
        // until the user picks another; an empty saved choice is none.
        let browser = if Path::new("/usr/share/applications/shipwright-pacific.desktop").exists() {
            "shipwright-pacific"
        } else {
            "browser"
        };
        let mut apps = Map::default();
        for (role, key, default) in DEFAULT_APPS {
            let default = if role == "browser" { browser } else { default };
            let saved = self
                .ini
                .0
                .get(key)
                .and_then(Value::as_text)
                .filter(|s| !s.is_empty() || default.is_empty());
            apps.insert(
                QString::from(role),
                QVariant::from(&QString::from(&saved.unwrap_or_else(|| default.to_owned()))),
            );
        }
        self.as_mut().rust_mut().default_apps = apps;
        self.as_mut().write_properties();
        if migrated {
            self.save_soon();
        }
    }

    /// A property changed: the file follows, and so do the clients.
    fn changed(mut self: Pin<&mut Self>, name: &'static str) {
        self.as_mut().write_properties();
        if name == "defaultApps" {
            let mut rust = self.as_mut().rust_mut();
            for (role, key, _) in DEFAULT_APPS {
                let app = rust
                    .default_apps
                    .get(&QString::from(role))
                    .and_then(|v| v.value::<QString>())
                    .unwrap_or_default();
                rust.ini
                    .0
                    .insert(key.to_owned(), Value::Text(app.to_string()));
            }
        }
        if let Some(value) = state(&self).remove(name) {
            ipc::signal("Settings", "PropertyChanged", (name.to_owned(), value));
        }
        if matches!(name, "dndEnabled" | "audioProfile") {
            crate::audio::push_state();
        }
        self.save_soon();
    }

    /// The file is rewritten once a burst of changes (a volume drag) settles.
    fn save_soon(mut self: Pin<&mut Self>) {
        let generation = {
            let mut rust = self.as_mut().rust_mut();
            rust.dirty = true;
            rust.saves += 1;
            rust.saves
        };
        let qt = self.qt_thread();
        io::spawn(async move {
            Timer::after(Duration::from_millis(500)).await;
            qt.queue(move |mut obj| {
                if obj.saves == generation {
                    obj.as_mut().rust_mut().dirty = false;
                    writer().try_send(obj.ini.render()).ok();
                }
            })
            .ok();
        });
    }

    pub(crate) fn get(&self, key: &QString, default_value: &QVariant) -> QVariant {
        match self.ini.0.get(&key.to_string()) {
            Some(Value::Invalid) | None => default_value.clone(),
            Some(value) => qvariant::to_qt(&value.to_dbus()),
        }
    }

    pub(crate) fn set(mut self: Pin<&mut Self>, key: &QString, value: &QVariant) {
        let Some(value) = qvariant::from_qt(value).filter(|_| storable(value)) else {
            return log::warn(
                "settings",
                format_args!("cannot store {key}: not a settings type"),
            );
        };
        self.as_mut()
            .rust_mut()
            .ini
            .0
            .insert(key.to_string(), Value::from_dbus(&value));
        self.save_soon();
    }

    pub(crate) fn sync(&self) {
        if let Err(e) = write(&self.ini.render()) {
            log::warn("settings", format_args!("cannot save: {e}"));
        }
    }

    pub(crate) fn is_notifications_enabled_for_app(&self, app_id: &QString) -> bool {
        app_id.is_empty()
            || self
                .app_notification_settings
                .get(app_id)
                .and_then(|v| v.value::<bool>())
                .unwrap_or(true)
    }

    pub(crate) fn remove_app_keys(mut self: Pin<&mut Self>, app_id: &QString) {
        if !app_id.is_empty() {
            self.as_mut()
                .rust_mut()
                .ini
                .remove_tree(&app_id.to_string());
            self.save_soon();
        }
    }
}

/// Whether every part of `value` is a type the file keeps.
fn storable(value: &QVariant) -> bool {
    use cxx_qt_lib::QMetaTypeType as T;
    match value.type_id() {
        T::QVariantList => value
            .value::<QList<QVariant>>()
            .is_some_and(|l| l.iter().all(storable)),
        T::QVariantMap => value
            .value::<Map>()
            .is_some_and(|m| m.iter().all(|(_, v)| storable(v))),
        T::UnknownType
        | T::Bool
        | T::Int
        | T::UInt
        | T::LongLong
        | T::ULongLong
        | T::Double
        | T::QString
        | T::QStringList => true,
        _ => false,
    }
}

/// The file's older shapes, brought up to date; true if any was.
fn migrate(ini: &mut Ini) -> bool {
    let mut changed = false;
    let flag = |ini: &Ini, key: &str| ini.0.get(key).and_then(Value::as_bool).unwrap_or(false);
    // Before the lock delay, autoLock off meant "don't lock on idle": those
    // users get the longest delay.
    if !flag(ini, "system/autoLockTimeoutMigrated") {
        let auto_lock = ini
            .0
            .get("system/autoLock")
            .and_then(Value::as_bool)
            .unwrap_or(true);
        ini.0.insert(
            "system/autoLockTimeout".into(),
            Value::Int(if auto_lock { 0 } else { 300 }),
        );
        ini.0
            .insert("system/autoLockTimeoutMigrated".into(), Value::Bool(true));
        changed = true;
    }
    // Once only, so a developer who unhides the Test Suite keeps it.
    if !flag(ini, "apps/testHiddenByDefault") {
        let mut hidden = ini
            .0
            .get("apps/hiddenApps")
            .map_or_else(|| vec!["terminal".to_owned()], Value::as_list);
        if !hidden.iter().any(|a| a == "test") {
            hidden.push("test".to_owned());
        }
        ini.0.insert("apps/hiddenApps".into(), Value::List(hidden));
        ini.0
            .insert("apps/testHiddenByDefault".into(), Value::Bool(true));
        changed = true;
    }
    for key in [
        "ui/wallpaperPath",
        "audio/ringtone",
        "audio/notificationSound",
        "audio/alarmSound",
    ] {
        if let Some(file) = ini
            .0
            .get(key)
            .and_then(Value::as_text)
            .and_then(|p| installed(&p))
        {
            ini.0.insert(key.into(), Value::Text(file));
            changed = true;
        }
    }
    changed
}

/// Moves Android apps' ids from `from` to `to` in the hidden apps, the
/// default apps and the per-app notification settings.
///
/// # Errors
/// The file cannot be read or written.
pub fn rename_app_ids(from: &str, to: &str) -> std::io::Result<()> {
    let text = match fs::read_to_string(file()) {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        text => text?,
    };
    let mut ini = Ini::parse(&text);
    let rename = |id: &str| app_ids::renamed(id, from, to);
    let mut changed = false;
    let hidden = ini.0.get("apps/hiddenApps").map(Value::as_list);
    if let Some(hidden) = hidden.filter(|ids| ids.iter().any(|id| id.starts_with(from))) {
        let mut next = Vec::with_capacity(hidden.len());
        for id in hidden {
            next.push(rename(&id).unwrap_or(id));
        }
        ini.0.insert("apps/hiddenApps".into(), Value::List(next));
        changed = true;
    }
    for (_, key, _) in DEFAULT_APPS {
        if let Some(id) = ini
            .0
            .get(key)
            .and_then(Value::as_text)
            .and_then(|id| rename(&id))
        {
            ini.0.insert(key.into(), Value::Text(id));
            changed = true;
        }
    }
    if let Some(Value::Map(apps)) = ini.0.get_mut("notifications/appSettings") {
        let mut next = BTreeMap::new();
        for (id, value) in std::mem::take(apps) {
            let new = rename(&id);
            changed |= new.is_some();
            next.insert(new.unwrap_or(id), value);
        }
        *apps = next;
    }
    if changed {
        write(&ini.render())?;
    }
    Ok(())
}

/// Role, the file's key and Marathon's own app for it.
const DEFAULT_APPS: [(&str, &str, &str); 9] = [
    ("browser", "apps/defaultBrowser", "browser"),
    ("dialer", "apps/defaultDialer", "phone"),
    ("messaging", "apps/defaultMessaging", "messages"),
    ("email", "apps/defaultEmail", "email"),
    ("camera", "apps/defaultCamera", "camera"),
    ("gallery", "apps/defaultGallery", "gallery"),
    ("music", "apps/defaultMusic", "music"),
    ("video", "apps/defaultVideo", ""),
    ("files", "apps/defaultFiles", ""),
];

struct Settings1 {
    qt: Qt,
}

async fn system(h: &Header<'_>) -> fdo::Result<()> {
    ipc::admit(h, "Settings", &["system"]).await.map(drop)
}

async fn storage(h: &Header<'_>) -> fdo::Result<()> {
    ipc::admit(h, "Settings.Storage", &["storage"])
        .await
        .map(drop)
}

fn owned(value: &zbus::zvariant::Value<'_>) -> fdo::Result<OwnedValue> {
    value
        .try_to_owned()
        .map_err(|e| fdo::Error::Failed(e.to_string()))
}

#[zbus::interface(name = "org.marathonos.Shell.Settings1")]
impl Settings1 {
    /// Every app reads it to size its UI, so it needs no permission.
    async fn get_state(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<State> {
        let sender = h.sender().map(ToString::to_string).unwrap_or_default();
        if !gate::in_window(&sender, "Settings.GetState") {
            return Err(fdo::Error::LimitsExceeded("Rate limit exceeded".into()));
        }
        ipc::on_gui(&self.qt, |obj| state(&obj)).await
    }

    async fn set_property(
        &self,
        name: String,
        value: OwnedValue,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        system(&h).await?;
        let value = Value::from_dbus(&value);
        let known = ipc::on_gui(&self.qt, move |obj| {
            obj.set_named(&name.clone(), &value)
                .then_some(())
                .ok_or(name)
        })
        .await?;
        known.map_err(|name| fdo::Error::InvalidArgs(format!("Unknown settings property: {name}")))
    }

    async fn available_ringtones(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<Vec<String>> {
        system(&h).await?;
        Ok(QList::<QString>::from(&sounds(&["phone", "bbm"]))
            .iter()
            .map(ToString::to_string)
            .collect())
    }

    async fn available_notification_sounds(
        &self,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<Vec<String>> {
        system(&h).await?;
        Ok(
            QList::<QString>::from(&sounds(&["text", "messages", "bbm"]))
                .iter()
                .map(ToString::to_string)
                .collect(),
        )
    }

    async fn available_alarm_sounds(
        &self,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<Vec<String>> {
        system(&h).await?;
        Ok(QList::<QString>::from(&sounds(&["alarms"]))
            .iter()
            .map(ToString::to_string)
            .collect())
    }

    async fn screen_timeout_options(
        &self,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<Vec<String>> {
        system(&h).await?;
        Ok(SCREEN_TIMEOUTS
            .iter()
            .map(|(name, _)| (*name).to_owned())
            .collect())
    }

    async fn screen_timeout_value(
        &self,
        option: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<i32> {
        system(&h).await?;
        Ok(SCREEN_TIMEOUTS
            .iter()
            .find(|(name, _)| *name == option)
            .map_or(120_000, |(_, ms)| *ms))
    }

    async fn format_sound_name(
        &self,
        path: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<String> {
        system(&h).await?;
        Ok(sound_name(&path))
    }

    async fn asset_url(
        &self,
        relative_path: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<String> {
        system(&h).await?;
        Ok(asset_url(&relative_path))
    }

    /// The caller's own `<appId>/...` keys with "storage", the Calendar's
    /// events (read only) with "calendar", anything with "system".
    async fn get(
        &self,
        key: String,
        default_value: OwnedValue,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<OwnedValue> {
        let caller = ipc::caller(&h).await.unwrap_or_default();
        if !caller.is_empty() && key.starts_with(&format!("{caller}/")) {
            storage(&h).await?;
        } else if key.starts_with("calendar/")
            && (gate::service_or_test(&caller, "calendar") || permissions::has(&caller, "calendar"))
        {
            let sender = h.sender().map(ToString::to_string).unwrap_or_default();
            if !gate::in_window(&sender, "Settings.Calendar") {
                return Err(fdo::Error::LimitsExceeded("Rate limit exceeded".into()));
            }
        } else {
            system(&h).await?;
        }
        let found = ipc::on_gui(&self.qt, move |obj| {
            obj.ini
                .0
                .get(&key)
                .filter(|v| **v != Value::Invalid)
                .map(Value::to_dbus)
        })
        .await?;
        found.map_or(Ok(default_value), |v| owned(&v))
    }

    async fn set(
        &self,
        key: String,
        value: OwnedValue,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        let caller = ipc::caller(&h).await.unwrap_or_default();
        if !caller.is_empty() && key.starts_with(&format!("{caller}/")) {
            storage(&h).await?;
        } else {
            system(&h).await?;
        }
        let value = Value::from_dbus(&value);
        ipc::on_gui(&self.qt, move |mut obj| {
            obj.as_mut().rust_mut().ini.0.insert(key, value);
            obj.save_soon();
        })
        .await
    }

    async fn sync(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        if system(&h).await.is_err() {
            storage(&h).await?;
        }
        ipc::on_gui(&self.qt, |obj| obj.sync()).await
    }

    async fn set_system_time(
        &self,
        msecs_since_epoch: i64,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        system(&h).await?;
        ipc::on_gui(&self.qt, move |obj| obj.set_system_time(msecs_since_epoch)).await
    }
}

#[cfg(test)]
mod tests {
    use super::{migrate, sound_name, Field, Ini, SettingsRust, Value};
    use cxx_qt_lib::QString;

    #[test]
    fn the_language_starts_unset_and_round_trips() {
        assert!(SettingsRust::default().language.is_empty());
        let stored = QString::from("de").value();
        assert_eq!(
            QString::read(&stored).map(|l| l.to_string()),
            Some("de".to_owned())
        );
        let ini = Ini::parse("[system]\nlanguage=fr\n");
        assert_eq!(
            ini.0
                .get("system/language")
                .and_then(QString::read)
                .map(|l| l.to_string()),
            Some("fr".to_owned())
        );
    }

    #[test]
    fn the_old_auto_lock_switch_becomes_the_lock_delay() {
        let delay = |file: &str| {
            let mut ini = Ini::parse(file);
            migrate(&mut ini);
            ini.0.get("system/autoLockTimeout").and_then(Value::as_i64)
        };
        assert_eq!(delay(""), Some(0));
        assert_eq!(
            delay("[system]\nautoLock=true\nautoLockTimeout=300\n"),
            Some(0)
        );
        assert_eq!(
            delay("[system]\nautoLock=false\nautoLockTimeout=300\n"),
            Some(300)
        );
        assert_eq!(
            delay("[system]\nautoLockTimeout=30\nautoLockTimeoutMigrated=true\n"),
            Some(30)
        );
    }

    #[test]
    fn the_test_suite_is_hidden_once() {
        let hidden = |file: &str| {
            let mut ini = Ini::parse(file);
            migrate(&mut ini);
            ini.0.get("apps/hiddenApps").map(Value::as_list)
        };
        assert_eq!(hidden("").unwrap_or_default(), ["terminal", "test"]);
        assert_eq!(
            hidden("[apps]\nhiddenApps=notes\n").unwrap_or_default(),
            ["notes", "test"]
        );
        assert_eq!(
            hidden("[apps]\nhiddenApps=@Invalid()\ntestHiddenByDefault=true\n").unwrap_or_default(),
            Vec::<String>::new()
        );
    }

    #[test]
    fn sound_files_read_as_names() {
        assert_eq!(
            sound_name("file:///usr/share/marathon-shell/sounds/alarms/alarm_early-riser.wav"),
            "Early Riser"
        );
        assert_eq!(sound_name("/x/ring_old_phone.ogg"), "Old Phone");
    }
}
