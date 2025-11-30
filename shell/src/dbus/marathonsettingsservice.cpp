#include "marathonsettingsservice.h"
#include "../settingsmanager.h"
#include <QDBusConnection>
#include <QSettings>
#include <QDebug>

MarathonSettingsService::MarathonSettingsService(SettingsManager *settingsManager, QObject *parent)
    : QObject(parent)
    , m_settingsManager(settingsManager) {}

MarathonSettingsService::~MarathonSettingsService() {}

bool MarathonSettingsService::registerService() {
    QDBusConnection bus = QDBusConnection::sessionBus();

    if (!bus.registerService("org.marathon.SettingsService")) {
        qWarning() << "[SettingsService] Failed to register service:" << bus.lastError().message();
        return false;
    }

    if (!bus.registerObject("/org/marathon/SettingsService", this,
                            QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals)) {
        qWarning() << "[SettingsService] Failed to register object:" << bus.lastError().message();
        return false;
    }

    qInfo() << "[SettingsService] ✓ Registered on D-Bus";
    return true;
}

QVariant MarathonSettingsService::GetSetting(const QString &key, const QVariant &defaultValue) {
    if (!m_settingsManager)
        return defaultValue;

    // SettingsManager uses property-based access, wrap with QSettings
    QSettings settings;
    return settings.value(key, defaultValue);
}

bool MarathonSettingsService::SetSetting(const QString &key, const QVariant &value) {
    if (!m_settingsManager)
        return false;

    QSettings settings;
    settings.setValue(key, value);
    emit SettingChanged(key, value);
    return true;
}

bool MarathonSettingsService::RemoveSetting(const QString &key) {
    if (!m_settingsManager)
        return false;

    QSettings settings;
    settings.remove(key);
    emit SettingChanged(key, QVariant());
    return true;
}

QStringList MarathonSettingsService::GetAllKeys() {
    QSettings settings;
    return settings.allKeys();
}

bool MarathonSettingsService::HasSetting(const QString &key) {
    QSettings settings;
    return settings.contains(key);
}
