#pragma once

#include <QDBusConnection>
#include <QObject>
#include <QVariantList>

// The shell's wallpapers (org.marathonos.Shell.Wallpaper1) and the current
// one, which is the wallpaperPath setting. Settings' wallpaper page uses it.
class WallpaperClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList wallpapers READ wallpapers NOTIFY wallpapersChanged)
    Q_PROPERTY(QString currentWallpaper READ currentWallpaper NOTIFY currentWallpaperChanged)

  public:
    // settings carries a wallpaperPath property (SettingsClient).
    explicit WallpaperClient(QObject *settings, const QDBusConnection &bus = QDBusConnection::sessionBus(),
                             QObject *parent = nullptr);

    QVariantList wallpapers() const {
        return m_wallpapers;
    }
    QString currentWallpaper() const;

    Q_INVOKABLE void setWallpaper(const QString &path, bool isDark);

  signals:
    void wallpapersChanged();
    void currentWallpaperChanged();

  private:
    QObject        *m_settings;
    QDBusConnection m_bus;
    QVariantList    m_wallpapers;
};
