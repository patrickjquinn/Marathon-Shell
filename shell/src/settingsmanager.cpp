#include "settingsmanager.h"
#include <QDebug>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>

SettingsManager::SettingsManager(QObject *parent)
    : QObject(parent)
    , m_settings("marathon-os", "Marathon Shell")
    , m_userScaleFactor(1.0)
    , m_wallpaperPath("qrc:/wallpapers/wallpaper.jpg")
    , m_deviceName("Marathon OS")
    , m_autoLock(true)
    , m_autoLockTimeout(300)
    , m_showNotificationPreviews(true)
    , m_timeFormat("12h")
    , m_dateFormat("US")
    , m_ringtone("qrc:/sounds/resources/sounds/phone/bbpro1.wav")
    , m_notificationSound("qrc:/sounds/resources/sounds/text/chime.wav")
    , m_alarmSound("qrc:/sounds/resources/sounds/alarms/alarm_sunrise.wav")
    , m_mediaVolume(0.6)
    , m_ringtoneVolume(0.8)
    , m_alarmVolume(0.9)
    , m_notificationVolume(0.7)
    , m_systemVolume(0.5)
    , m_screenTimeout(120000) // 2 minutes default
    , m_autoBrightness(false)
    , m_statusBarClockPosition("center")
    , m_showNotificationsOnLockScreen(true)
    , m_filterMobileFriendlyApps(true) // Default to ON for better mobile UX
    , m_hiddenApps()
    , m_appSortOrder("alphabetical")
    , m_appGridColumns(0) // 0 = auto
    , m_searchNativeApps(true)
    , m_showNotificationBadges(true)
    , m_showFrequentApps(false)
    , m_defaultApps()
    , m_firstRunComplete(false)
    , m_enabledQuickSettingsTiles()
    , m_quickSettingsTileOrder()
    , m_keyboardAutoCorrection(true)
    , m_keyboardPredictiveText(true)
    , m_keyboardWordFling(true)
    , m_keyboardPredictiveSpacing(false)
    , m_keyboardHapticStrength("medium") {
    qDebug() << "[SettingsManager] Initialized";
    qDebug() << "[SettingsManager] Settings file:" << m_settings.fileName();
    load();
}

void SettingsManager::load() {
    // Existing
    m_userScaleFactor = m_settings.value("ui/userScaleFactor", 1.0).toReal();
    m_wallpaperPath =
        m_settings.value("ui/wallpaperPath", "qrc:/wallpapers/wallpaper.jpg").toString();

    // Migrated from QML
    m_deviceName               = m_settings.value("system/deviceName", "Marathon OS").toString();
    m_autoLock                 = m_settings.value("system/autoLock", true).toBool();
    m_autoLockTimeout          = m_settings.value("system/autoLockTimeout", 300).toInt();
    m_showNotificationPreviews = m_settings.value("system/showNotificationPreviews", true).toBool();
    m_timeFormat               = m_settings.value("system/timeFormat", "12h").toString();
    m_dateFormat               = m_settings.value("system/dateFormat", "US").toString();

    // Audio
    m_ringtone = m_settings.value("audio/ringtone", "qrc:/sounds/resources/sounds/phone/bbpro1.wav")
                     .toString();
    m_notificationSound =
        m_settings.value("audio/notificationSound", "qrc:/sounds/resources/sounds/text/chime.wav")
            .toString();
    m_alarmSound =
        m_settings
            .value("audio/alarmSound", "qrc:/sounds/resources/sounds/alarms/alarm_sunrise.wav")
            .toString();
    m_mediaVolume        = m_settings.value("audio/mediaVolume", 0.6).toReal();
    m_ringtoneVolume     = m_settings.value("audio/ringtoneVolume", 0.8).toReal();
    m_alarmVolume        = m_settings.value("audio/alarmVolume", 0.9).toReal();
    m_notificationVolume = m_settings.value("audio/notificationVolume", 0.7).toReal();
    m_systemVolume       = m_settings.value("audio/systemVolume", 0.5).toReal();

    // Display
    m_screenTimeout  = m_settings.value("display/screenTimeout", 120000).toInt();
    m_autoBrightness = m_settings.value("display/autoBrightness", false).toBool();
    m_statusBarClockPosition =
        m_settings.value("display/statusBarClockPosition", "center").toString();

    // Notifications
    m_showNotificationsOnLockScreen =
        m_settings.value("notifications/showOnLockScreen", true).toBool();

    // App Management
    m_filterMobileFriendlyApps = m_settings.value("apps/filterMobileFriendly", true).toBool();
    m_hiddenApps               = m_settings.value("apps/hiddenApps", QStringList()).toStringList();
    m_appSortOrder             = m_settings.value("apps/sortOrder", "alphabetical").toString();
    m_appGridColumns           = m_settings.value("apps/gridColumns", 0).toInt();
    m_searchNativeApps         = m_settings.value("apps/searchNativeApps", true).toBool();
    m_showNotificationBadges   = m_settings.value("apps/showBadges", true).toBool();
    m_showFrequentApps         = m_settings.value("apps/showFrequentApps", false).toBool();

    // Load default apps map
    QVariantMap defaultApps;
    defaultApps["browser"]   = m_settings.value("apps/defaultBrowser", "").toString();
    defaultApps["dialer"]    = m_settings.value("apps/defaultDialer", "").toString();
    defaultApps["messaging"] = m_settings.value("apps/defaultMessaging", "").toString();
    defaultApps["email"]     = m_settings.value("apps/defaultEmail", "").toString();
    defaultApps["camera"]    = m_settings.value("apps/defaultCamera", "").toString();
    defaultApps["gallery"]   = m_settings.value("apps/defaultGallery", "").toString();
    defaultApps["music"]     = m_settings.value("apps/defaultMusic", "").toString();
    defaultApps["video"]     = m_settings.value("apps/defaultVideo", "").toString();
    defaultApps["files"]     = m_settings.value("apps/defaultFiles", "").toString();
    m_defaultApps            = defaultApps;

    // OOBE
    m_firstRunComplete = m_settings.value("system/firstRunComplete", false).toBool();

    // Quick Settings - Default to all tiles enabled in default order
    QStringList defaultTiles = {
        "wifi",     "bluetooth",  "flight",    "cellular",   "rotation", "autobrightness",
        "location", "hotspot",    "vibration", "nightlight", "torch",    "notifications",
        "battery",  "screenshot", "settings",  "lock",       "power"};
    m_enabledQuickSettingsTiles =
        m_settings.value("quicksettings/enabledTiles", defaultTiles).toStringList();
    m_quickSettingsTileOrder =
        m_settings.value("quicksettings/tileOrder", defaultTiles).toStringList();

    // Keyboard settings - BB10-style defaults (all features enabled except predictive spacing)
    m_keyboardAutoCorrection    = m_settings.value("keyboard/autoCorrection", true).toBool();
    m_keyboardPredictiveText    = m_settings.value("keyboard/predictiveText", true).toBool();
    m_keyboardWordFling         = m_settings.value("keyboard/wordFling", true).toBool();
    m_keyboardPredictiveSpacing = m_settings.value("keyboard/predictiveSpacing", false).toBool();
    m_keyboardHapticStrength    = m_settings.value("keyboard/hapticStrength", "medium").toString();

    qDebug() << "[SettingsManager] Loaded: userScaleFactor =" << m_userScaleFactor;
    qDebug() << "[SettingsManager] Loaded: wallpaperPath =" << m_wallpaperPath;
    qDebug() << "[SettingsManager] Loaded: firstRunComplete =" << m_firstRunComplete;
    qDebug() << "[SettingsManager] Loaded: filterMobileFriendlyApps ="
             << m_filterMobileFriendlyApps;
    qDebug() << "[SettingsManager] Loaded: hiddenApps =" << m_hiddenApps;
    qDebug() << "[SettingsManager] Loaded: appSortOrder =" << m_appSortOrder;
}

void SettingsManager::save() {
    // Existing
    m_settings.setValue("ui/userScaleFactor", m_userScaleFactor);
    m_settings.setValue("ui/wallpaperPath", m_wallpaperPath);

    // Migrated
    m_settings.setValue("system/deviceName", m_deviceName);
    m_settings.setValue("system/autoLock", m_autoLock);
    m_settings.setValue("system/autoLockTimeout", m_autoLockTimeout);
    m_settings.setValue("system/showNotificationPreviews", m_showNotificationPreviews);
    m_settings.setValue("system/timeFormat", m_timeFormat);
    m_settings.setValue("system/dateFormat", m_dateFormat);

    // Audio
    m_settings.setValue("audio/ringtone", m_ringtone);
    m_settings.setValue("audio/notificationSound", m_notificationSound);
    m_settings.setValue("audio/alarmSound", m_alarmSound);
    m_settings.setValue("audio/mediaVolume", m_mediaVolume);
    m_settings.setValue("audio/ringtoneVolume", m_ringtoneVolume);
    m_settings.setValue("audio/alarmVolume", m_alarmVolume);
    m_settings.setValue("audio/notificationVolume", m_notificationVolume);
    m_settings.setValue("audio/systemVolume", m_systemVolume);

    // Display
    m_settings.setValue("display/screenTimeout", m_screenTimeout);
    m_settings.setValue("display/autoBrightness", m_autoBrightness);
    m_settings.setValue("display/statusBarClockPosition", m_statusBarClockPosition);

    // Notifications
    m_settings.setValue("notifications/showOnLockScreen", m_showNotificationsOnLockScreen);

    // App Management
    m_settings.setValue("apps/filterMobileFriendly", m_filterMobileFriendlyApps);
    m_settings.setValue("apps/hiddenApps", m_hiddenApps);
    m_settings.setValue("apps/sortOrder", m_appSortOrder);
    m_settings.setValue("apps/gridColumns", m_appGridColumns);
    m_settings.setValue("apps/searchNativeApps", m_searchNativeApps);
    m_settings.setValue("apps/showBadges", m_showNotificationBadges);
    m_settings.setValue("apps/showFrequentApps", m_showFrequentApps);

    // Save default apps
    m_settings.setValue("apps/defaultBrowser", m_defaultApps.value("browser", "").toString());
    m_settings.setValue("apps/defaultDialer", m_defaultApps.value("dialer", "").toString());
    m_settings.setValue("apps/defaultMessaging", m_defaultApps.value("messaging", "").toString());
    m_settings.setValue("apps/defaultEmail", m_defaultApps.value("email", "").toString());
    m_settings.setValue("apps/defaultCamera", m_defaultApps.value("camera", "").toString());
    m_settings.setValue("apps/defaultGallery", m_defaultApps.value("gallery", "").toString());
    m_settings.setValue("apps/defaultMusic", m_defaultApps.value("music", "").toString());
    m_settings.setValue("apps/defaultVideo", m_defaultApps.value("video", "").toString());
    m_settings.setValue("apps/defaultFiles", m_defaultApps.value("files", "").toString());

    // OOBE
    m_settings.setValue("system/firstRunComplete", m_firstRunComplete);

    // Quick Settings
    m_settings.setValue("quicksettings/enabledTiles", m_enabledQuickSettingsTiles);
    m_settings.setValue("quicksettings/tileOrder", m_quickSettingsTileOrder);

    // Keyboard settings
    m_settings.setValue("keyboard/autoCorrection", m_keyboardAutoCorrection);
    m_settings.setValue("keyboard/predictiveText", m_keyboardPredictiveText);
    m_settings.setValue("keyboard/wordFling", m_keyboardWordFling);
    m_settings.setValue("keyboard/predictiveSpacing", m_keyboardPredictiveSpacing);
    m_settings.setValue("keyboard/hapticStrength", m_keyboardHapticStrength);

    m_settings.sync();
    qDebug() << "[SettingsManager] Saved settings";
}

void SettingsManager::setUserScaleFactor(qreal factor) {
    if (qFuzzyCompare(m_userScaleFactor, factor)) {
        return;
    }

    m_userScaleFactor = factor;
    save();
    emit userScaleFactorChanged();

    qDebug() << "[SettingsManager] userScaleFactor changed to" << factor;
}

void SettingsManager::setWallpaperPath(const QString &path) {
    if (m_wallpaperPath == path) {
        return;
    }

    m_wallpaperPath = path;
    save();
    emit wallpaperPathChanged();

    qDebug() << "[SettingsManager] wallpaperPath changed to" << path;
}

// Migrated setters
void SettingsManager::setDeviceName(const QString &name) {
    if (m_deviceName == name)
        return;
    m_deviceName = name;
    save();
    emit deviceNameChanged();
}

void SettingsManager::setAutoLock(bool enabled) {
    if (m_autoLock == enabled)
        return;
    m_autoLock = enabled;
    save();
    emit autoLockChanged();
}

void SettingsManager::setAutoLockTimeout(int seconds) {
    if (m_autoLockTimeout == seconds)
        return;
    m_autoLockTimeout = seconds;
    save();
    emit autoLockTimeoutChanged();
}

void SettingsManager::setShowNotificationPreviews(bool show) {
    if (m_showNotificationPreviews == show)
        return;
    m_showNotificationPreviews = show;
    save();
    emit showNotificationPreviewsChanged();
}

void SettingsManager::setTimeFormat(const QString &format) {
    if (m_timeFormat == format)
        return;
    m_timeFormat = format;
    save();
    emit timeFormatChanged();
}

void SettingsManager::setDateFormat(const QString &format) {
    if (m_dateFormat == format)
        return;
    m_dateFormat = format;
    save();
    emit dateFormatChanged();
}

// Audio setters
void SettingsManager::setRingtone(const QString &path) {
    if (m_ringtone == path)
        return;
    m_ringtone = path;
    save();
    emit ringtoneChanged();
    qDebug() << "[SettingsManager] Ringtone changed to" << path;
}

void SettingsManager::setNotificationSound(const QString &path) {
    if (m_notificationSound == path)
        return;
    m_notificationSound = path;
    save();
    emit notificationSoundChanged();
    qDebug() << "[SettingsManager] Notification sound changed to" << path;
}

void SettingsManager::setAlarmSound(const QString &path) {
    if (m_alarmSound == path)
        return;
    m_alarmSound = path;
    save();
    emit alarmSoundChanged();
    qDebug() << "[SettingsManager] Alarm sound changed to" << path;
}

void SettingsManager::setMediaVolume(qreal volume) {
    if (qFuzzyCompare(m_mediaVolume, volume))
        return;
    m_mediaVolume = qBound(0.0, volume, 1.0);
    save();
    emit mediaVolumeChanged();
    qDebug() << "[SettingsManager] Media volume changed to" << m_mediaVolume;
}

void SettingsManager::setRingtoneVolume(qreal volume) {
    if (qFuzzyCompare(m_ringtoneVolume, volume))
        return;
    m_ringtoneVolume = qBound(0.0, volume, 1.0);
    save();
    emit ringtoneVolumeChanged();
    qDebug() << "[SettingsManager] Ringtone volume changed to" << m_ringtoneVolume;
}

void SettingsManager::setAlarmVolume(qreal volume) {
    if (qFuzzyCompare(m_alarmVolume, volume))
        return;
    m_alarmVolume = qBound(0.0, volume, 1.0);
    save();
    emit alarmVolumeChanged();
    qDebug() << "[SettingsManager] Alarm volume changed to" << m_alarmVolume;
}

void SettingsManager::setNotificationVolume(qreal volume) {
    if (qFuzzyCompare(m_notificationVolume, volume))
        return;
    m_notificationVolume = qBound(0.0, volume, 1.0);
    save();
    emit notificationVolumeChanged();
    qDebug() << "[SettingsManager] Notification volume changed to" << m_notificationVolume;
}

void SettingsManager::setSystemVolume(qreal volume) {
    if (qFuzzyCompare(m_systemVolume, volume))
        return;
    m_systemVolume = qBound(0.0, volume, 1.0);
    save();
    emit systemVolumeChanged();
    qDebug() << "[SettingsManager] System volume changed to" << m_systemVolume;
}

// Display setters
void SettingsManager::setScreenTimeout(int ms) {
    if (m_screenTimeout == ms)
        return;
    m_screenTimeout = ms;
    save();
    emit screenTimeoutChanged();
    qDebug() << "[SettingsManager] Screen timeout changed to" << ms;
}

void SettingsManager::setAutoBrightness(bool enabled) {
    if (m_autoBrightness == enabled)
        return;
    m_autoBrightness = enabled;
    save();
    emit autoBrightnessChanged();
    qDebug() << "[SettingsManager] Auto-brightness changed to" << enabled;
}

void SettingsManager::setStatusBarClockPosition(const QString &position) {
    if (m_statusBarClockPosition == position)
        return;
    // Validate input
    if (position != "left" && position != "center" && position != "right") {
        qWarning() << "[SettingsManager] Invalid clock position:" << position << "- using 'center'";
        return;
    }
    m_statusBarClockPosition = position;
    save();
    emit statusBarClockPositionChanged();
    qDebug() << "[SettingsManager] Status bar clock position changed to" << position;
}

// Notification setters
void SettingsManager::setShowNotificationsOnLockScreen(bool enabled) {
    if (m_showNotificationsOnLockScreen == enabled)
        return;
    m_showNotificationsOnLockScreen = enabled;
    save();
    emit showNotificationsOnLockScreenChanged();
}

// OOBE setters
void SettingsManager::setFirstRunComplete(bool complete) {
    if (m_firstRunComplete == complete)
        return;
    m_firstRunComplete = complete;
    save();
    emit firstRunCompleteChanged();
    qDebug() << "[SettingsManager] First run complete changed to" << complete;
}

void SettingsManager::setEnabledQuickSettingsTiles(const QStringList &tiles) {
    if (m_enabledQuickSettingsTiles == tiles)
        return;
    m_enabledQuickSettingsTiles = tiles;
    save();
    emit enabledQuickSettingsTilesChanged();
    qDebug() << "[SettingsManager] Enabled Quick Settings tiles changed:" << tiles;
}

void SettingsManager::setQuickSettingsTileOrder(const QStringList &order) {
    if (m_quickSettingsTileOrder == order)
        return;
    m_quickSettingsTileOrder = order;
    save();
    emit quickSettingsTileOrderChanged();
    qDebug() << "[SettingsManager] Quick Settings tile order changed:" << order;
}

// Keyboard setters
void SettingsManager::setKeyboardAutoCorrection(bool enabled) {
    if (m_keyboardAutoCorrection == enabled)
        return;
    m_keyboardAutoCorrection = enabled;
    save();
    emit keyboardAutoCorrectionChanged();
    qDebug() << "[SettingsManager] Keyboard auto-correction:" << enabled;
}

void SettingsManager::setKeyboardPredictiveText(bool enabled) {
    if (m_keyboardPredictiveText == enabled)
        return;
    m_keyboardPredictiveText = enabled;
    save();
    emit keyboardPredictiveTextChanged();
    qDebug() << "[SettingsManager] Keyboard predictive text:" << enabled;
}

void SettingsManager::setKeyboardWordFling(bool enabled) {
    if (m_keyboardWordFling == enabled)
        return;
    m_keyboardWordFling = enabled;
    save();
    emit keyboardWordFlingChanged();
    qDebug() << "[SettingsManager] Keyboard Word Fling:" << enabled;
}

void SettingsManager::setKeyboardPredictiveSpacing(bool enabled) {
    if (m_keyboardPredictiveSpacing == enabled)
        return;
    m_keyboardPredictiveSpacing = enabled;
    save();
    emit keyboardPredictiveSpacingChanged();
    qDebug() << "[SettingsManager] Keyboard predictive spacing:" << enabled;
}

void SettingsManager::setKeyboardHapticStrength(const QString &strength) {
    if (m_keyboardHapticStrength == strength)
        return;
    m_keyboardHapticStrength = strength;
    save();
    emit keyboardHapticStrengthChanged();
    qDebug() << "[SettingsManager] Keyboard haptic strength:" << strength;
}

// Sound scanning methods
QStringList SettingsManager::availableRingtones() {
    // Qt resources don't support directory listing, so we hardcode the list
    // Note: The full path includes 'resources/sounds' because that's how they're stored in resources.qrc
    QStringList ringtones = {
        "qrc:/sounds/resources/sounds/phone/bbpro1.wav",
        "qrc:/sounds/resources/sounds/phone/bbpro2.wav",
        "qrc:/sounds/resources/sounds/phone/bbpro3.wav",
        "qrc:/sounds/resources/sounds/phone/bbpro4.wav",
        "qrc:/sounds/resources/sounds/bbm/bbpro5.wav", // bbpro5-6 are in the bbm folder
        "qrc:/sounds/resources/sounds/bbm/bbpro6.wav",
        "qrc:/sounds/resources/sounds/phone/bonjour.wav",
        "qrc:/sounds/resources/sounds/phone/classicphone.wav",
        "qrc:/sounds/resources/sounds/phone/clean.wav",
        "qrc:/sounds/resources/sounds/phone/evolving_destiny.wav",
        "qrc:/sounds/resources/sounds/phone/fresh.wav",
        "qrc:/sounds/resources/sounds/phone/lively.wav",
        "qrc:/sounds/resources/sounds/phone/open.wav",
        "qrc:/sounds/resources/sounds/phone/radiant.wav",
        "qrc:/sounds/resources/sounds/phone/spirit.wav"};

    qDebug() << "[SettingsManager] Available ringtones:" << ringtones.size();
    return ringtones;
}

QStringList SettingsManager::availableNotificationSounds() {
    QStringList sounds = {// Text sounds
                          "qrc:/sounds/resources/sounds/text/bikebell.wav",
                          "qrc:/sounds/resources/sounds/text/brief.wav",
                          "qrc:/sounds/resources/sounds/text/caffeine.wav",
                          "qrc:/sounds/resources/sounds/text/chigong.wav",
                          "qrc:/sounds/resources/sounds/text/chime.wav",
                          "qrc:/sounds/resources/sounds/text/crystal.wav",
                          "qrc:/sounds/resources/sounds/text/lucid.wav",
                          "qrc:/sounds/resources/sounds/text/presto.wav",
                          "qrc:/sounds/resources/sounds/text/pure.wav",
                          "qrc:/sounds/resources/sounds/text/tight.wav",
                          "qrc:/sounds/resources/sounds/text/ufo.wav",
                          // Message sounds
                          "qrc:/sounds/resources/sounds/messages/bright.wav",
                          "qrc:/sounds/resources/sounds/messages/confident.wav",
                          "qrc:/sounds/resources/sounds/messages/contentment.wav",
                          "qrc:/sounds/resources/sounds/messages/eager.wav",
                          "qrc:/sounds/resources/sounds/messages/gungho.wav"};

    qDebug() << "[SettingsManager] Available notification sounds:" << sounds.size();
    return sounds;
}

QStringList SettingsManager::availableAlarmSounds() {
    QStringList alarms = {"qrc:/sounds/resources/sounds/alarms/alarm_antelope.wav",
                          "qrc:/sounds/resources/sounds/alarms/alarm_bbproalarm.wav",
                          "qrc:/sounds/resources/sounds/alarms/alarm_definite.wav",
                          "qrc:/sounds/resources/sounds/alarms/alarm_earlyriser.wav",
                          "qrc:/sounds/resources/sounds/alarms/alarm_electronic.wav",
                          "qrc:/sounds/resources/sounds/alarms/alarm_highalert.wav",
                          "qrc:/sounds/resources/sounds/alarms/alarm_sunrise.wav",
                          "qrc:/sounds/resources/sounds/alarms/alarm_transition.wav",
                          "qrc:/sounds/resources/sounds/alarms/alarm_vintagealarm.wav"};

    qDebug() << "[SettingsManager] Available alarm sounds:" << alarms.size();
    return alarms;
}

QStringList SettingsManager::screenTimeoutOptions() {
    return QStringList() << "30 seconds" << "1 minute" << "2 minutes" << "5 minutes" << "Never";
}

int SettingsManager::screenTimeoutValue(const QString &option) {
    if (option == "30 seconds")
        return 30000;
    if (option == "1 minute")
        return 60000;
    if (option == "2 minutes")
        return 120000;
    if (option == "5 minutes")
        return 300000;
    if (option == "Never")
        return 0;
    return 120000; // Default to 2 minutes
}

void SettingsManager::setFilterMobileFriendlyApps(bool enabled) {
    if (m_filterMobileFriendlyApps == enabled) {
        return;
    }

    m_filterMobileFriendlyApps = enabled;
    emit filterMobileFriendlyAppsChanged();
    save();

    qDebug() << "[SettingsManager] Filter mobile-friendly apps:" << enabled;
}

void SettingsManager::setHiddenApps(const QStringList &apps) {
    if (m_hiddenApps == apps) {
        return;
    }

    m_hiddenApps = apps;
    emit hiddenAppsChanged();
    save();

    qDebug() << "[SettingsManager] Hidden apps:" << apps.size();
}

void SettingsManager::setAppSortOrder(const QString &order) {
    if (m_appSortOrder == order) {
        return;
    }

    m_appSortOrder = order;
    emit appSortOrderChanged();
    save();

    qDebug() << "[SettingsManager] App sort order:" << order;
}

void SettingsManager::setAppGridColumns(int columns) {
    if (m_appGridColumns == columns) {
        return;
    }

    m_appGridColumns = columns;
    emit appGridColumnsChanged();
    save();

    qDebug() << "[SettingsManager] App grid columns:" << columns;
}

void SettingsManager::setSearchNativeApps(bool enabled) {
    if (m_searchNativeApps == enabled) {
        return;
    }

    m_searchNativeApps = enabled;
    emit searchNativeAppsChanged();
    save();

    qDebug() << "[SettingsManager] Search native apps:" << enabled;
}

void SettingsManager::setShowNotificationBadges(bool enabled) {
    if (m_showNotificationBadges == enabled) {
        return;
    }

    m_showNotificationBadges = enabled;
    emit showNotificationBadgesChanged();
    save();

    qDebug() << "[SettingsManager] Show notification badges:" << enabled;
}

void SettingsManager::setShowFrequentApps(bool enabled) {
    if (m_showFrequentApps == enabled) {
        return;
    }

    m_showFrequentApps = enabled;
    emit showFrequentAppsChanged();
    save();

    qDebug() << "[SettingsManager] Show frequent apps:" << enabled;
}

void SettingsManager::setDefaultApps(const QVariantMap &apps) {
    if (m_defaultApps == apps) {
        return;
    }

    m_defaultApps = apps;
    emit defaultAppsChanged();
    save();

    qDebug() << "[SettingsManager] Default apps updated";
}

QString SettingsManager::formatSoundName(const QString &path) {
    // Extract filename from path
    QFileInfo info(path);
    QString   baseName = info.baseName();

    // Remove prefixes like "alarm_"
    baseName.remove("alarm_");
    baseName.remove("ring_");

    // Replace underscores/hyphens with spaces
    baseName.replace('_', ' ');
    baseName.replace('-', ' ');

    // Capitalize first letter of each word
    QStringList words = baseName.split(' ');
    for (int i = 0; i < words.size(); ++i) {
        if (!words[i].isEmpty()) {
            words[i][0] = words[i][0].toUpper();
        }
    }

    return words.join(' ');
}

QVariant SettingsManager::get(const QString &key, const QVariant &defaultValue) {
    return m_settings.value(key, defaultValue);
}

void SettingsManager::set(const QString &key, const QVariant &value) {
    m_settings.setValue(key, value);
}

void SettingsManager::sync() {
    m_settings.sync();
}
