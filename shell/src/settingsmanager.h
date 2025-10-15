#pragma once

#include <QObject>
#include <QSettings>
#include <QVariant>

class SettingsManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(qreal userScaleFactor READ userScaleFactor WRITE setUserScaleFactor NOTIFY userScaleFactorChanged)
    Q_PROPERTY(QString wallpaperPath READ wallpaperPath WRITE setWallpaperPath NOTIFY wallpaperPathChanged)

public:
    explicit SettingsManager(QObject *parent = nullptr);
    ~SettingsManager() override = default;

    qreal userScaleFactor() const { return m_userScaleFactor; }
    void setUserScaleFactor(qreal factor);

    QString wallpaperPath() const { return m_wallpaperPath; }
    void setWallpaperPath(const QString &path);

    Q_INVOKABLE QVariant get(const QString &key, const QVariant &defaultValue = QVariant());
    Q_INVOKABLE void set(const QString &key, const QVariant &value);
    Q_INVOKABLE void sync();

signals:
    void userScaleFactorChanged();
    void wallpaperPathChanged();

private:
    void load();
    void save();

    QSettings m_settings;
    qreal m_userScaleFactor;
    QString m_wallpaperPath;
};
