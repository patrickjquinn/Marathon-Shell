#ifndef SETTINGSMANAGER_H
#define SETTINGSMANAGER_H

#include <QObject>
#include <QSettings>
#include <QVariant>
#include <QString>

class SettingsManager : public QObject
{
    Q_OBJECT

public:
    explicit SettingsManager(QObject* parent = nullptr);
    ~SettingsManager();

    Q_INVOKABLE QVariant get(const QString& key, const QVariant& defaultValue = QVariant());
    Q_INVOKABLE void set(const QString& key, const QVariant& value);
    Q_INVOKABLE void remove(const QString& key);
    Q_INVOKABLE void clear();
    Q_INVOKABLE void sync();
    Q_INVOKABLE bool contains(const QString& key);
    Q_INVOKABLE QStringList allKeys();

signals:
    void settingChanged(const QString& key, const QVariant& value);
    void settingsCleared();

private:
    QSettings* m_settings;
};

#endif // SETTINGSMANAGER_H

