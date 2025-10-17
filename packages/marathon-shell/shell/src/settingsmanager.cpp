#include "settingsmanager.h"
#include <QDebug>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>

SettingsManager::SettingsManager(QObject *parent)
    : QObject(parent)
    , m_settings("marathon-os", "Marathon Shell")
    , m_userScaleFactor(1.0)
    , m_wallpaperPath("qrc:/wallpapers/resources/wallpapers/marathon-logo.jpg")
    , m_deviceName("Marathon OS")
    , m_autoLock(true)
    , m_autoLockTimeout(300)
    , m_showNotificationPreviews(true)
    , m_timeFormat("12h")
    , m_dateFormat("US")
    , m_ringtone("qrc:/sounds/phone/bbpro1.wav")
    , m_notificationSound("qrc:/sounds/text/chime.wav")
    , m_alarmSound("qrc:/sounds/alarms/alarm_sunrise.wav")
    , m_screenTimeout(120000)  // 2 minutes default
    , m_autoBrightness(false)
    , m_showNotificationsOnLockScreen(true)
{
    qDebug() << "[SettingsManager] Initialized";
    qDebug() << "[SettingsManager] Settings file:" << m_settings.fileName();
    load();
}

void SettingsManager::load() {
    // Existing
    m_userScaleFactor = m_settings.value("ui/userScaleFactor", 1.0).toReal();
    m_wallpaperPath = m_settings.value("ui/wallpaperPath", "qrc:/wallpapers/wallpaper.jpg").toString();
    
    // Migrated from QML
    m_deviceName = m_settings.value("system/deviceName", "Marathon OS").toString();
    m_autoLock = m_settings.value("system/autoLock", true).toBool();
    m_autoLockTimeout = m_settings.value("system/autoLockTimeout", 300).toInt();
    m_showNotificationPreviews = m_settings.value("system/showNotificationPreviews", true).toBool();
    m_timeFormat = m_settings.value("system/timeFormat", "12h").toString();
    m_dateFormat = m_settings.value("system/dateFormat", "US").toString();
    
    // Audio
    m_ringtone = m_settings.value("audio/ringtone", "qrc:/sounds/phone/bbpro1.wav").toString();
    m_notificationSound = m_settings.value("audio/notificationSound", "qrc:/sounds/text/chime.wav").toString();
    m_alarmSound = m_settings.value("audio/alarmSound", "qrc:/sounds/alarms/alarm_sunrise.wav").toString();
    
    // Display
    m_screenTimeout = m_settings.value("display/screenTimeout", 120000).toInt();
    m_autoBrightness = m_settings.value("display/autoBrightness", false).toBool();
    
    // Notifications
    m_showNotificationsOnLockScreen = m_settings.value("notifications/showOnLockScreen", true).toBool();
    
    qDebug() << "[SettingsManager] Loaded: userScaleFactor =" << m_userScaleFactor;
    qDebug() << "[SettingsManager] Loaded: wallpaperPath =" << m_wallpaperPath;
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
    
    // Display
    m_settings.setValue("display/screenTimeout", m_screenTimeout);
    m_settings.setValue("display/autoBrightness", m_autoBrightness);
    
    // Notifications
    m_settings.setValue("notifications/showOnLockScreen", m_showNotificationsOnLockScreen);
    
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
    if (m_deviceName == name) return;
    m_deviceName = name;
    save();
    emit deviceNameChanged();
}

void SettingsManager::setAutoLock(bool enabled) {
    if (m_autoLock == enabled) return;
    m_autoLock = enabled;
    save();
    emit autoLockChanged();
}

void SettingsManager::setAutoLockTimeout(int seconds) {
    if (m_autoLockTimeout == seconds) return;
    m_autoLockTimeout = seconds;
    save();
    emit autoLockTimeoutChanged();
}

void SettingsManager::setShowNotificationPreviews(bool show) {
    if (m_showNotificationPreviews == show) return;
    m_showNotificationPreviews = show;
    save();
    emit showNotificationPreviewsChanged();
}

void SettingsManager::setTimeFormat(const QString &format) {
    if (m_timeFormat == format) return;
    m_timeFormat = format;
    save();
    emit timeFormatChanged();
}

void SettingsManager::setDateFormat(const QString &format) {
    if (m_dateFormat == format) return;
    m_dateFormat = format;
    save();
    emit dateFormatChanged();
}

// Audio setters
void SettingsManager::setRingtone(const QString &path) {
    if (m_ringtone == path) return;
    m_ringtone = path;
    save();
    emit ringtoneChanged();
    qDebug() << "[SettingsManager] Ringtone changed to" << path;
}

void SettingsManager::setNotificationSound(const QString &path) {
    if (m_notificationSound == path) return;
    m_notificationSound = path;
    save();
    emit notificationSoundChanged();
    qDebug() << "[SettingsManager] Notification sound changed to" << path;
}

void SettingsManager::setAlarmSound(const QString &path) {
    if (m_alarmSound == path) return;
    m_alarmSound = path;
    save();
    emit alarmSoundChanged();
    qDebug() << "[SettingsManager] Alarm sound changed to" << path;
}

// Display setters
void SettingsManager::setScreenTimeout(int ms) {
    if (m_screenTimeout == ms) return;
    m_screenTimeout = ms;
    save();
    emit screenTimeoutChanged();
    qDebug() << "[SettingsManager] Screen timeout changed to" << ms;
}

void SettingsManager::setAutoBrightness(bool enabled) {
    if (m_autoBrightness == enabled) return;
    m_autoBrightness = enabled;
    save();
    emit autoBrightnessChanged();
    qDebug() << "[SettingsManager] Auto-brightness changed to" << enabled;
}

// Notification setters
void SettingsManager::setShowNotificationsOnLockScreen(bool enabled) {
    if (m_showNotificationsOnLockScreen == enabled) return;
    m_showNotificationsOnLockScreen = enabled;
    save();
    emit showNotificationsOnLockScreenChanged();
}

// Sound scanning methods
QStringList SettingsManager::availableRingtones() {
    // Qt resources don't support directory listing, so we hardcode the list
    QStringList ringtones = {
        "qrc:/sounds/phone/bbpro1.wav",
        "qrc:/sounds/phone/bbpro2.wav",
        "qrc:/sounds/phone/bbpro3.wav",
        "qrc:/sounds/phone/bbpro4.wav",
        "qrc:/sounds/phone/bbpro5.wav",
        "qrc:/sounds/phone/bbpro6.wav",
        "qrc:/sounds/phone/bonjour.wav",
        "qrc:/sounds/phone/classicphone.wav",
        "qrc:/sounds/phone/clean.wav",
        "qrc:/sounds/phone/evolving_destiny.wav",
        "qrc:/sounds/phone/fresh.wav",
        "qrc:/sounds/phone/lively.wav",
        "qrc:/sounds/phone/open.wav",
        "qrc:/sounds/phone/radiant.wav",
        "qrc:/sounds/phone/spirit.wav"
    };
    
    qDebug() << "[SettingsManager] Available ringtones:" << ringtones.size();
    return ringtones;
}

QStringList SettingsManager::availableNotificationSounds() {
    QStringList sounds = {
        // Text sounds
        "qrc:/sounds/text/bikebell.wav",
        "qrc:/sounds/text/brief.wav",
        "qrc:/sounds/text/caffeine.wav",
        "qrc:/sounds/text/chigong.wav",
        "qrc:/sounds/text/chime.wav",
        "qrc:/sounds/text/crystal.wav",
        "qrc:/sounds/text/lucid.wav",
        "qrc:/sounds/text/presto.wav",
        "qrc:/sounds/text/pure.wav",
        "qrc:/sounds/text/tight.wav",
        "qrc:/sounds/text/ufo.wav",
        // Message sounds
        "qrc:/sounds/messages/bright.wav",
        "qrc:/sounds/messages/confident.wav",
        "qrc:/sounds/messages/contentment.wav",
        "qrc:/sounds/messages/eager.wav",
        "qrc:/sounds/messages/gungho.wav"
    };
    
    qDebug() << "[SettingsManager] Available notification sounds:" << sounds.size();
    return sounds;
}

QStringList SettingsManager::availableAlarmSounds() {
    QStringList alarms = {
        "qrc:/sounds/alarms/alarm_antelope.wav",
        "qrc:/sounds/alarms/alarm_bbproalarm.wav",
        "qrc:/sounds/alarms/alarm_definite.wav",
        "qrc:/sounds/alarms/alarm_earlyriser.wav",
        "qrc:/sounds/alarms/alarm_electronic.wav",
        "qrc:/sounds/alarms/alarm_highalert.wav",
        "qrc:/sounds/alarms/alarm_sunrise.wav",
        "qrc:/sounds/alarms/alarm_transition.wav",
        "qrc:/sounds/alarms/alarm_vintagealarm.wav"
    };
    
    qDebug() << "[SettingsManager] Available alarm sounds:" << alarms.size();
    return alarms;
}

QStringList SettingsManager::screenTimeoutOptions() {
    return QStringList() << "30 seconds" << "1 minute" << "2 minutes" << "5 minutes" << "Never";
}

int SettingsManager::screenTimeoutValue(const QString &option) {
    if (option == "30 seconds") return 30000;
    if (option == "1 minute") return 60000;
    if (option == "2 minutes") return 120000;
    if (option == "5 minutes") return 300000;
    if (option == "Never") return 0;
    return 120000; // Default to 2 minutes
}

QString SettingsManager::formatSoundName(const QString &path) {
    // Extract filename from path
    QFileInfo info(path);
    QString baseName = info.baseName();
    
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
