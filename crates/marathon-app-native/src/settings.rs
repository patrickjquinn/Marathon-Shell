//! `Settings`: the shell's Settings1, the system settings and each app's
//! own keys.

use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QMap, QMapPair_QString_QVariant, QString, QStringList, QVariant};
use zbus::zvariant::{OwnedValue, Value};

use crate::shell::{allowed, relay, Arg, Field, Service, State};
use crate::variant;
use marathon_rt::{io, log};

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
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
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
        #[qproperty(QString, ringtone, cxx_name = "ringtone", READ, WRITE = set_ringtone, NOTIFY)]
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
        #[qproperty(bool, keyboard_predictive_text, cxx_name = "keyboardPredictiveText", READ, WRITE = set_keyboard_predictive_text, NOTIFY)]
        #[qproperty(QString, keyboard_haptic_strength, cxx_name = "keyboardHapticStrength", READ, WRITE = set_keyboard_haptic_strength, NOTIFY)]
        #[qproperty(QString, keyboard_language, cxx_name = "keyboardLanguage", READ, WRITE = set_keyboard_language, NOTIFY)]
        #[qproperty(bool, keyboard_auto_capitalize, cxx_name = "keyboardAutoCapitalize", READ, WRITE = set_keyboard_auto_capitalize, NOTIFY)]
        type Settings = super::SettingsRust;

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
        #[cxx_name = "setKeyboardPredictiveText"]
        fn set_keyboard_predictive_text(self: Pin<&mut Settings>, value: bool);
        #[cxx_name = "setKeyboardHapticStrength"]
        fn set_keyboard_haptic_strength(self: Pin<&mut Settings>, value: &QString);
        #[cxx_name = "setKeyboardLanguage"]
        fn set_keyboard_language(self: Pin<&mut Settings>, value: &QString);
        #[cxx_name = "setKeyboardAutoCapitalize"]
        fn set_keyboard_auto_capitalize(self: Pin<&mut Settings>, value: bool);

        #[qinvokable]
        #[cxx_name = "setSystemTime"]
        fn set_system_time(self: &Settings, msecs_since_epoch: i64);
        #[qinvokable]
        #[cxx_name = "availableRingtones"]
        fn available_ringtones(self: &Settings) -> QStringList;
        #[qinvokable]
        #[cxx_name = "availableNotificationSounds"]
        fn available_notification_sounds(self: &Settings) -> QStringList;
        #[qinvokable]
        #[cxx_name = "availableAlarmSounds"]
        fn available_alarm_sounds(self: &Settings) -> QStringList;
        #[qinvokable]
        #[cxx_name = "screenTimeoutOptions"]
        fn screen_timeout_options(self: &Settings) -> QStringList;
        #[qinvokable]
        #[cxx_name = "screenTimeoutValue"]
        fn screen_timeout_value(self: &Settings, option: &QString) -> i32;
        /// A sound file's name as pickers show it: "ring_old_phone.ogg" is "Old Phone".
        #[qinvokable]
        #[cxx_name = "formatSoundName"]
        fn format_sound_name(self: &Settings, path: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "assetUrl"]
        fn asset_url(self: &Settings, relative_path: &QString) -> QString;
        /// A key: the app's own (`<appId>/...`, with storage) or a system one.
        #[qinvokable]
        fn get(self: &Settings, key: &QString, default_value: &QVariant) -> QVariant;
        #[qinvokable]
        fn set(self: &Settings, key: &QString, value: &QVariant);
        #[qinvokable]
        fn sync(self: &Settings);
    }

    impl cxx_qt::Threading for Settings {}
    impl cxx_qt::Initialize for Settings {}
}

use qobject::Settings;

const SETTINGS: Service = Service::shell("Settings");

/// The properties: field, type and any default, the shell's name, and setter.
macro_rules! properties {
    (@default $ty:ty) => { <$ty>::default() };
    (@default $ty:ty, $default:expr) => { $default };
    ($($field:ident: $ty:ty $(= $default:expr)?, $key:literal, $changed:ident, $setter:ident($arg:ty);)*) => {
        pub struct SettingsRust {
            $($field: $ty,)*
        }

        impl Default for SettingsRust {
            fn default() -> Self {
                Self { $($field: properties!(@default $ty $(, $default)?),)* }
            }
        }

        impl Settings {
            $(fn $setter(self: Pin<&mut Self>, value: $arg) {
                store($key, value.wire().into());
            })*
        }

        /// The shell's `name` changed to `value`.
        #[allow(clippy::float_cmp, reason = "a change is any new value")]
        fn show(mut obj: Pin<&mut Settings>, name: &str, value: &OwnedValue) {
            match name {
                $($key => {
                    if let Some(value) = <$ty as Field>::from_value(value) {
                        set!(obj, $field, $changed, value);
                    }
                })*
                _ => {}
            }
        }
    };
}

properties! {
    user_scale_factor: f64 = 1.0, "userScaleFactor", user_scale_factor_changed, set_user_scale_factor(f64);
    wallpaper_path: QString, "wallpaperPath", wallpaper_path_changed, set_wallpaper_path(&QString);
    device_name: QString, "deviceName", device_name_changed, set_device_name(&QString);
    auto_lock: bool = true, "autoLock", auto_lock_changed, set_auto_lock(bool);
    auto_lock_timeout: i32, "autoLockTimeout", auto_lock_timeout_changed, set_auto_lock_timeout(i32);
    show_notification_previews: bool = true, "showNotificationPreviews", show_notification_previews_changed, set_show_notification_previews(bool);
    time_format: QString = QString::from("24h"), "timeFormat", time_format_changed, set_time_format(&QString);
    date_format: QString = QString::from("US"), "dateFormat", date_format_changed, set_date_format(&QString);
    ringtone: QString, "ringtone", ringtone_changed, set_ringtone(&QString);
    notification_sound: QString, "notificationSound", notification_sound_changed, set_notification_sound(&QString);
    alarm_sound: QString, "alarmSound", alarm_sound_changed, set_alarm_sound(&QString);
    media_volume: f64, "mediaVolume", media_volume_changed, set_media_volume(f64);
    ringtone_volume: f64, "ringtoneVolume", ringtone_volume_changed, set_ringtone_volume(f64);
    alarm_volume: f64, "alarmVolume", alarm_volume_changed, set_alarm_volume(f64);
    notification_volume: f64, "notificationVolume", notification_volume_changed, set_notification_volume(f64);
    system_volume: f64, "systemVolume", system_volume_changed, set_system_volume(f64);
    dnd_enabled: bool, "dndEnabled", dnd_enabled_changed, set_dnd_enabled(bool);
    vibration_enabled: bool = true, "vibrationEnabled", vibration_enabled_changed, set_vibration_enabled(bool);
    reduce_motion: bool, "reduceMotion", reduce_motion_changed, set_reduce_motion(bool);
    time_zone: QString = QString::from("UTC"), "timeZone", time_zone_changed, set_time_zone(&QString);
    automatic_time: bool = true, "automaticTime", automatic_time_changed, set_automatic_time(bool);
    automatic_time_zone: bool = true, "automaticTimeZone", automatic_time_zone_changed, set_automatic_time_zone(bool);
    audio_profile: QString = QString::from("normal"), "audioProfile", audio_profile_changed, set_audio_profile(&QString);
    screen_timeout: i32, "screenTimeout", screen_timeout_changed, set_screen_timeout(i32);
    auto_brightness: bool, "autoBrightness", auto_brightness_changed, set_auto_brightness(bool);
    status_bar_clock_position: QString = QString::from("center"), "statusBarClockPosition", status_bar_clock_position_changed, set_status_bar_clock_position(&QString);
    show_notifications_on_lock_screen: bool = true, "showNotificationsOnLockScreen", show_notifications_on_lock_screen_changed, set_show_notifications_on_lock_screen(bool);
    filter_mobile_friendly_apps: bool = true, "filterMobileFriendlyApps", filter_mobile_friendly_apps_changed, set_filter_mobile_friendly_apps(bool);
    hidden_apps: QStringList, "hiddenApps", hidden_apps_changed, set_hidden_apps(&QStringList);
    app_sort_order: QString = QString::from("alphabetical"), "appSortOrder", app_sort_order_changed, set_app_sort_order(&QString);
    app_grid_columns: i32, "appGridColumns", app_grid_columns_changed, set_app_grid_columns(i32);
    search_native_apps: bool = true, "searchNativeApps", search_native_apps_changed, set_search_native_apps(bool);
    show_notification_badges: bool = true, "showNotificationBadges", show_notification_badges_changed, set_show_notification_badges(bool);
    app_notification_settings: QMap<QMapPair_QString_QVariant>, "appNotificationSettings", app_notification_settings_changed, set_app_notification_settings(&QMap<QMapPair_QString_QVariant>);
    show_frequent_apps: bool, "showFrequentApps", show_frequent_apps_changed, set_show_frequent_apps(bool);
    default_apps: QMap<QMapPair_QString_QVariant>, "defaultApps", default_apps_changed, set_default_apps(&QMap<QMapPair_QString_QVariant>);
    first_run_complete: bool, "firstRunComplete", first_run_complete_changed, set_first_run_complete(bool);
    enabled_quick_settings_tiles: QStringList, "enabledQuickSettingsTiles", enabled_quick_settings_tiles_changed, set_enabled_quick_settings_tiles(&QStringList);
    quick_settings_tile_order: QStringList, "quickSettingsTileOrder", quick_settings_tile_order_changed, set_quick_settings_tile_order(&QStringList);
    keyboard_auto_correction: bool = true, "keyboardAutoCorrection", keyboard_auto_correction_changed, set_keyboard_auto_correction(bool);
    keyboard_predictive_text: bool = true, "keyboardPredictiveText", keyboard_predictive_text_changed, set_keyboard_predictive_text(bool);
    keyboard_haptic_strength: QString = QString::from("medium"), "keyboardHapticStrength", keyboard_haptic_strength_changed, set_keyboard_haptic_strength(&QString);
    keyboard_language: QString = QString::from("en_US"), "keyboardLanguage", keyboard_language_changed, set_keyboard_language(&QString);
    keyboard_auto_capitalize: bool = true, "keyboardAutoCapitalize", keyboard_auto_capitalize_changed, set_keyboard_auto_capitalize(bool);
}

/// Writes a system setting; the shell answers with `PropertyChanged`.
fn store(name: &'static str, value: Value<'static>) {
    static ASKED: AtomicBool = AtomicBool::new(false);
    io::spawn(async move {
        let mut asked = ASKED.load(Ordering::Relaxed);
        let held = allowed("system", &mut asked).await.unwrap_or(false);
        ASKED.store(asked, Ordering::Relaxed);
        if held {
            SETTINGS.call("SetProperty", (name, value));
        }
    });
}

impl cxx_qt::Initialize for Settings {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        relay(
            qt.clone(),
            SETTINGS,
            "DateTimeChangeFailed",
            |obj, (r,): (String,)| {
                obj.date_time_change_failed(&QString::from(&r));
            },
        );
        relay(
            qt.clone(),
            SETTINGS,
            "PropertyChanged",
            |obj, (name, value): (String, OwnedValue)| {
                follow_time_zone(&name, &value);
                show(obj, &name, &value);
            },
        );
        // A read, which every app needs to size its UI: no permission.
        io::spawn(async move {
            loop {
                match SETTINGS.ask::<_, State>("GetState", &()).await {
                    Ok(state) => {
                        qt.queue(move |mut obj| {
                            for (name, value) in &state {
                                show(obj.as_mut(), name, value);
                            }
                        })
                        .ok();
                        return;
                    }
                    Err(_) => {
                        async_io::Timer::after(std::time::Duration::from_millis(250)).await;
                    }
                }
            }
        });
    }
}

extern "C" {
    fn tzset();
}

/// libc keeps the zone it read at startup; local time follows a new `TZ`.
fn follow_time_zone(name: &str, value: &OwnedValue) {
    let Ok(zone) = <&str>::try_from(value) else {
        return;
    };
    if name != "timeZone" || zone.is_empty() {
        return;
    }
    std::env::set_var("TZ", format!(":{zone}"));
    // SAFETY: tzset only rereads TZ; it runs on the GUI thread, like every
    // local-time call the app makes.
    unsafe { tzset() };
}

impl Settings {
    crate::shell::asks! { SETTINGS;
        screen_timeout_value(option: &QString) -> i32 => "ScreenTimeoutValue";
        available_ringtones() -> QStringList => "AvailableRingtones";
        available_notification_sounds() -> QStringList => "AvailableNotificationSounds";
        available_alarm_sounds() -> QStringList => "AvailableAlarmSounds";
        screen_timeout_options() -> QStringList => "ScreenTimeoutOptions";
        asset_url(relative_path: &QString) -> QString => "AssetUrl";
    }

    fn set_system_time(&self, msecs_since_epoch: i64) {
        SETTINGS.call("SetSystemTime", (msecs_since_epoch,));
    }

    fn format_sound_name(&self, path: &QString) -> QString {
        QString::from(&sound_name(&path.to_string()))
    }

    fn get(&self, key: &QString, default_value: &QVariant) -> QVariant {
        let fallback = variant::from_qt(default_value).unwrap_or_else(|| Value::from(""));
        let value: Option<OwnedValue> = SETTINGS.ask_now("Get", &(key.to_string(), fallback));
        value.map_or_else(|| default_value.clone(), |v| variant::to_qt(&v))
    }

    fn set(&self, key: &QString, value: &QVariant) {
        match variant::from_qt(value) {
            Some(value) => SETTINGS.call("Set", (key.to_string(), value)),
            None => log::warn(
                "Settings",
                format_args!("cannot store {key}: no D-Bus type"),
            ),
        }
    }

    fn sync(&self) {
        SETTINGS.call("Sync", ());
    }
}

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

#[cfg(test)]
mod tests {
    #[test]
    fn sound_names_read_as_words() {
        assert_eq!(
            super::sound_name("file:///usr/share/sounds/ring_old_phone.ogg"),
            "Old Phone"
        );
        assert_eq!(super::sound_name("/x/alarm_early-bird.wav"), "Early Bird");
    }
}
