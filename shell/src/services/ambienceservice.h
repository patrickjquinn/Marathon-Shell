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

    // Silica's pixel ratio: the screen's density in Sailfish's quarter steps
    // (about 261 dpi per unit: Xperia 10 1.75, Jolla C 1.25), times
    // Marathon's interface scale, in steps of 0.05.
    static qreal sailfishPixelRatio(qreal dpi, qreal userScale);

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
