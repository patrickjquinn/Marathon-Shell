#ifndef MARATHONSETTINGSSERVICE_H
#define MARATHONSETTINGSSERVICE_H

#include <QObject>
#include <QDBusContext>
#include <QDBusConnection>
#include <QVariant>

class SettingsManager;

class MarathonSettingsService : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathon.SettingsService")

  public:
    explicit MarathonSettingsService(SettingsManager *settingsManager, QObject *parent = nullptr);
    ~MarathonSettingsService();

    bool registerService();

  public slots:
    QVariant    GetSetting(const QString &key, const QVariant &defaultValue);
    bool        SetSetting(const QString &key, const QVariant &value);
    bool        RemoveSetting(const QString &key);
    QStringList GetAllKeys();
    bool        HasSetting(const QString &key);

  signals:
    void SettingChanged(const QString &key, const QVariant &value);

  private:
    SettingsManager *m_settingsManager;
};

#endif // MARATHONSETTINGSSERVICE_H
