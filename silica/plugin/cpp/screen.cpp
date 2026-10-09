// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "screen.h"

#include <QGuiApplication>
#include "keeldconf.h"

#include <QMutex>
#include <QRegularExpression>
#include <QtMath>

namespace {

// The adaptation's dconf values, read once per process: they describe the
// panel and do not change while an app runs.
struct DisplayShape
{
    QString cutouts;
    QString corners;
};

const DisplayShape &displayShape()
{
    static QMutex mutex;
    static DisplayShape shape;
    static bool loaded = false;
    QMutexLocker lock(&mutex);
    if (loaded)
        return shape;
    loaded = true;
    if (qEnvironmentVariableIsSet("KEEL_SCREEN_CUTOUTS") || qEnvironmentVariableIsSet("KEEL_SCREEN_ROUNDED_CORNERS")) {
        shape.cutouts = qEnvironmentVariable("KEEL_SCREEN_CUTOUTS");
        shape.corners = qEnvironmentVariable("KEEL_SCREEN_ROUNDED_CORNERS");
        return shape;
    }
    if (!keel::dconf::available())
        return shape;
    shape.cutouts = keel::dconf::read(QStringLiteral("/desktop/sailfish/silica/cutouts"));
    shape.corners = keel::dconf::read(QStringLiteral("/desktop/sailfish/silica/rounded_corners"));
    return shape;
}

} // namespace

KeelScreen::KeelScreen(QObject *parent)
    : QObject(parent)
{
    track(QGuiApplication::primaryScreen());
    // The cutouts are in logical pixels: they follow the device pixel ratio.
    connect(this, &KeelScreen::geometryChanged, this, &KeelScreen::cutoutsChanged);
    if (auto *app = qobject_cast<QGuiApplication *>(QGuiApplication::instance()))
        connect(app, &QGuiApplication::primaryScreenChanged, this, [this](QScreen *s) {
            track(s);
            emit geometryChanged();
            emit screenInfoChanged();
            emit orientationChanged();
        });
}

void KeelScreen::track(QScreen *screen)
{
    if (m_screen)
        disconnect(m_screen, nullptr, this, nullptr);
    m_screen = screen;
    if (screen) {
        connect(screen, &QScreen::geometryChanged, this, &KeelScreen::geometryChanged);
        connect(screen, &QScreen::physicalSizeChanged, this, &KeelScreen::geometryChanged);
        connect(screen, &QScreen::availableGeometryChanged, this, &KeelScreen::geometryChanged);
        connect(screen, &QScreen::physicalDotsPerInchChanged, this, &KeelScreen::geometryChanged);
        connect(screen, &QScreen::orientationChanged, this, &KeelScreen::orientationChanged);
        connect(screen, &QScreen::primaryOrientationChanged, this, &KeelScreen::orientationChanged);
    }
}

int KeelScreen::width() const
{
    return m_screen ? qMin(m_screen->size().width(), m_screen->size().height()) : 540;
}

int KeelScreen::height() const
{
    return m_screen ? qMax(m_screen->size().width(), m_screen->size().height()) : 960;
}

qreal KeelScreen::diagonalInches() const
{
    // KEEL_SCREEN_DIAGONAL (inches) stands in for the panel's physical size
    // where the platform has none: Qt's offscreen platform reports every
    // screen at 100 dpi, which makes a 540x960 phone screen an 11" tablet
    // (tools/screenshots sets it for its device profiles).
    bool ok = false;
    const qreal forced = qEnvironmentVariable("KEEL_SCREEN_DIAGONAL").toDouble(&ok);
    if (ok && forced > 0)
        return forced;
    if (!m_screen)
        return 0;
    const QSizeF mm = m_screen->physicalSize();
    if (mm.width() <= 0 || mm.height() <= 0)
        return 0;
    return qSqrt(mm.width() * mm.width() + mm.height() * mm.height()) / 25.4;
}

int KeelScreen::categoryForDiagonal(qreal inches)
{
    if (inches <= 0)
        return Medium;
    if (inches < 3.8)
        return Small;
    if (inches < 7.0)
        return Medium;
    if (inches < 11.0)
        return Large;
    return ExtraLarge;
}

int KeelScreen::sizeCategory() const
{
    return categoryForDiagonal(diagonalInches());
}

int KeelScreen::desktopAvailableWidth() const
{
    return m_screen ? m_screen->availableVirtualGeometry().width() : width();
}

int KeelScreen::desktopAvailableHeight() const
{
    return m_screen ? m_screen->availableVirtualGeometry().height() : height();
}

QList<QList<int>> KeelScreen::parseIntArrays(const QString &text, int length)
{
    QList<QList<int>> out;
    static const QRegularExpression inner(QStringLiteral("\\[([^\\[\\]]*)\\]"));
    // The outer array's brackets enclose the inner ones, so only innermost
    // bracket pairs match.
    auto it = inner.globalMatch(text);
    while (it.hasNext()) {
        const QStringList parts = it.next().captured(1).split(QLatin1Char(','), Qt::SkipEmptyParts);
        if (parts.size() != length)
            continue;
        QList<int> values;
        bool ok = true;
        for (const QString &part : parts) {
            values << part.trimmed().toInt(&ok);
            if (!ok)
                break;
        }
        if (ok)
            out << values;
    }
    return out;
}

QRect KeelScreen::topCutoutOf(const QList<QList<int>> &cutouts)
{
    QRect top;
    for (const QList<int> &c : cutouts) {
        const QRect r(c.at(0), c.at(1), c.at(2), c.at(3));
        if (r.isValid() && r.top() <= 0)
            top = top.united(r);
    }
    return top;
}

QVariantMap KeelScreen::cornerOf(const QList<QList<int>> &corners, QSize size, bool right, bool bottom, qreal ratio)
{
    QVariantMap out { { QStringLiteral("x"), 0 }, { QStringLiteral("y"), 0 }, { QStringLiteral("radius"), 0 } };
    if (ratio <= 0)
        ratio = 1;
    for (const QList<int> &c : corners) {
        // A corner's side is given by the sign of its coordinates.
        if ((c.at(0) < 0) != right || (c.at(1) < 0) != bottom)
            continue;
        const int x = c.at(0) < 0 ? size.width() + c.at(0) : c.at(0);
        const int y = c.at(1) < 0 ? size.height() + c.at(1) : c.at(1);
        out[QStringLiteral("x")] = qRound(x / ratio);
        out[QStringLiteral("y")] = qRound(y / ratio);
        out[QStringLiteral("radius")] = qRound(c.at(2) / ratio);
        break;
    }
    return out;
}

QList<QList<int>> KeelScreen::cutouts() const
{
    return parseIntArrays(displayShape().cutouts, 4);
}

QRect KeelScreen::topCutout() const
{
    const QRect device = topCutoutOf(cutouts());
    if (device.isEmpty())
        return QRect();
    const qreal r = ratio();
    return QRect(qRound(device.x() / r), qRound(device.y() / r), qRound(device.width() / r),
                 qRound(device.height() / r));
}

QVariantMap KeelScreen::corner(bool right, bool bottom) const
{
    const qreal r = ratio();
    const QSize device(qRound(width() * r), qRound(height() * r));
    return cornerOf(parseIntArrays(displayShape().corners, 3), device, right, bottom, r);
}
