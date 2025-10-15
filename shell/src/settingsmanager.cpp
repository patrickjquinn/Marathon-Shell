#include "settingsmanager.h"
#include <QDebug>

SettingsManager::SettingsManager(QObject *parent)
    : QObject(parent)
    , m_settings("marathon-os", "Marathon Shell")
    , m_userScaleFactor(1.0)
    , m_wallpaperPath("qrc:/wallpapers/wallpaper.jpg")
{
    qDebug() << "[SettingsManager] Initialized";
    qDebug() << "[SettingsManager] Settings file:" << m_settings.fileName();
    load();
}

void SettingsManager::load() {
    m_userScaleFactor = m_settings.value("ui/userScaleFactor", 1.0).toReal();
    m_wallpaperPath = m_settings.value("ui/wallpaperPath", "qrc:/wallpapers/wallpaper.jpg").toString();
    
    qDebug() << "[SettingsManager] Loaded: userScaleFactor =" << m_userScaleFactor;
    qDebug() << "[SettingsManager] Loaded: wallpaperPath =" << m_wallpaperPath;
}

void SettingsManager::save() {
    m_settings.setValue("ui/userScaleFactor", m_userScaleFactor);
    m_settings.setValue("ui/wallpaperPath", m_wallpaperPath);
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

QVariant SettingsManager::get(const QString &key, const QVariant &defaultValue) {
    return m_settings.value(key, defaultValue);
}

void SettingsManager::set(const QString &key, const QVariant &value) {
    m_settings.setValue(key, value);
}

void SettingsManager::sync() {
    m_settings.sync();
}
