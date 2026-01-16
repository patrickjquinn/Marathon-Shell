#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <qqml.h>

class SettingsManager;

class WallpaperStore : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString currentWallpaper READ currentWallpaper NOTIFY currentWallpaperChanged)
    Q_PROPERTY(QString path READ path NOTIFY pathChanged)
    Q_PROPERTY(bool isDark READ isDark NOTIFY isDarkChanged)
    Q_PROPERTY(QVariantList wallpapers READ wallpapers NOTIFY wallpapersChanged)

  public:
    explicit WallpaperStore(SettingsManager *settingsManager, QObject *parent = nullptr);

    QString currentWallpaper() const {
        return m_currentWallpaper;
    }
    QString path() const {
        return m_currentWallpaper;
    }
    bool isDark() const {
        return m_isDark;
    }
    QVariantList wallpapers() const {
        return m_wallpapers;
    }

    Q_INVOKABLE void setWallpaper(const QString &newPath, bool newIsDark);

  signals:
    void currentWallpaperChanged();
    void pathChanged();
    void isDarkChanged();
    void wallpapersChanged();

  private:
    QString          resolveAssetPath(const QString &relativePath, const QString &fallback) const;
    void             setCurrentWallpaper(const QString &path);
    void             setIsDark(bool isDark);
    void             refreshIsDark();

    SettingsManager *m_settingsManager;
    QString          m_currentWallpaper = QStringLiteral("qrc:/wallpapers/wallpaper.jpg");
    bool             m_isDark           = true;
    QVariantList     m_wallpapers;
};
