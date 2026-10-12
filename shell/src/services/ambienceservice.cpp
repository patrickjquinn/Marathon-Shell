#include "ambienceservice.h"
#include "ambiencederivation.h"

#include <QImageReader>
#include <QUrl>

AmbienceService::AmbienceService(QObject *parent)
    : QObject(parent) {
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(250);
    connect(&m_debounce, &QTimer::timeout, this, [this]() {
        if (m_pending == m_ambience)
            return;
        m_ambience = m_pending;
        emit ambienceChanged(m_ambience);
    });
}

void AmbienceService::setWallpaper(const QString &path) {
    const QUrl    url   = QUrl(path);
    const QString local = url.scheme() == QLatin1String("qrc") ? QLatin1Char(':') + url.path()
        : url.isLocalFile()                                    ? url.toLocalFile()
                                                               : path;
    QImageReader reader(local);
    reader.setScaledSize(QSize(64, 64));
    const QImage img = reader.read();
    if (img.isNull())
        return;
    const AmbienceSeed seed   = deriveAmbienceSeed(img);
    const QColor       chosen = bundledHighlight(local);
    m_base                    = chosen.isValid() ? chosen : seed.base;
    m_light                 = seed.light;
    m_wallpaperUrl          = local.startsWith(QLatin1Char(':')) ? QStringLiteral("qrc") + local
                                                                 : QUrl::fromLocalFile(local).toString();
    emit seedChanged();
}

qreal AmbienceService::sailfishPixelRatio(qreal dpi, qreal userScale) {
    return qMax(0.75, qRound(dpi / 235.0 * userScale * 4) / 4.0);
}

void AmbienceService::setPixelRatio(qreal ratio) {
    if (qFuzzyCompare(ratio, m_pixelRatio))
        return;
    m_pixelRatio = ratio;
    emit pixelRatioChanged();
    publish(m_pending.isEmpty() ? m_ambience : m_pending);
}

void AmbienceService::publish(const QVariantMap &map) {
    m_pending = map;
    if (m_pixelRatio > 0)
        m_pending.insert(QStringLiteral("/desktop/sailfish/silica/theme_pixel_ratio"), m_pixelRatio);
    m_debounce.start();
}
