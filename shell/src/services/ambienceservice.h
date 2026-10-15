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
    Q_PROPERTY(qreal pixelRatio READ pixelRatio NOTIFY pixelRatioChanged)

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
    qreal pixelRatio() const {
        return m_pixelRatio;
    }

    // Silica's pixel ratio for Marathon's scale (dpi / 160 x interface
    // size), Silica's 540 px canvas fitted to Marathon's 390 units, in steps
    // of 0.05. A device's own ratio, when it sets one, replaces the density.
    static qreal sailfishPixelRatio(qreal dpi, qreal userScale, qreal deviceRatio = 0);

    void             setWallpaper(const QString &path);
    void             setPixelRatio(qreal ratio);
    Q_INVOKABLE void publish(const QVariantMap &map);

  signals:
    void seedChanged();
    void pixelRatioChanged();
    void ambienceChanged(const QVariantMap &ambience);

  private:
    QColor      m_base;
    bool        m_light = false;
    QString     m_wallpaperUrl;
    QVariantMap m_ambience;
    QVariantMap m_pending;
    qreal       m_pixelRatio = 0;
    QTimer      m_debounce;
};
