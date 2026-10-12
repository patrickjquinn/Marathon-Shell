#pragma once

#include <QColor>
#include <QObject>
#include <QTimer>
#include <QVariantMap>

// The ambience the shell publishes: the wallpaper's seed (base colour and
// scheme) for AmbienceController, and the published Keel ambience map that
// runners relay to apps.
class AmbienceService : public QObject {
    Q_OBJECT
    Q_PROPERTY(QColor baseColor READ baseColor NOTIFY seedChanged)
    Q_PROPERTY(bool light READ light NOTIFY seedChanged)
    Q_PROPERTY(QString wallpaperUrl READ wallpaperUrl NOTIFY seedChanged)
    Q_PROPERTY(QVariantMap ambience READ ambience NOTIFY ambienceChanged)

  public:
    explicit AmbienceService(QObject *parent = nullptr);

    QColor baseColor() const {
        return m_base;
    }
    bool light() const {
        return m_light;
    }
    QString wallpaperUrl() const {
        return m_wallpaperUrl;
    }
    QVariantMap ambience() const {
        return m_ambience;
    }

    void             setWallpaper(const QString &path);
    Q_INVOKABLE void publish(const QVariantMap &map);

  signals:
    void seedChanged();
    void ambienceChanged(const QVariantMap &ambience);

  private:
    QColor      m_base;
    bool        m_light = false;
    QString     m_wallpaperUrl;
    QVariantMap m_ambience;
    QVariantMap m_pending;
    QTimer      m_debounce;
};
