#include "settingsmanager.h"
#include <QDebug>
#include <QCoreApplication>

SettingsManager::SettingsManager(QObject* parent)
    : QObject(parent)
{
    QCoreApplication::setOrganizationName("Marathon OS");
    QCoreApplication::setApplicationName("Marathon Shell");
    
    m_settings = new QSettings(this);
    
    qDebug() << "[SettingsManager] Initialized";
    qDebug() << "[SettingsManager] Settings file:" << m_settings->fileName();
}

SettingsManager::~SettingsManager()
{
    m_settings->sync();
    qDebug() << "[SettingsManager] Settings saved and closed";
}

QVariant SettingsManager::get(const QString& key, const QVariant& defaultValue)
{
    return m_settings->value(key, defaultValue);
}

void SettingsManager::set(const QString& key, const QVariant& value)
{
    m_settings->setValue(key, value);
    emit settingChanged(key, value);
    qDebug() << "[SettingsManager] Setting changed:" << key << "=" << value;
}

void SettingsManager::remove(const QString& key)
{
    m_settings->remove(key);
    qDebug() << "[SettingsManager] Setting removed:" << key;
}

void SettingsManager::clear()
{
    m_settings->clear();
    emit settingsCleared();
    qDebug() << "[SettingsManager] All settings cleared";
}

void SettingsManager::sync()
{
    m_settings->sync();
    qDebug() << "[SettingsManager] Settings synced to disk";
}

bool SettingsManager::contains(const QString& key)
{
    return m_settings->contains(key);
}

QStringList SettingsManager::allKeys()
{
    return m_settings->allKeys();
}

