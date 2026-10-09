// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Clean-room; see glassitem.h.

#include "glassitem.h"
#include "keeltheme.h"

#include <QPainter>
#include <QPainterPath>
#include <QImage>
#include <QtMath>

#include <cmath>

KeelGlassItem::KeelGlassItem(QQuickItem *parent)
    : QQuickPaintedItem(parent)
    , m_palette(new KeelPalette(this))
{
    setAntialiasing(true);
    connect(m_palette, &KeelPalette::parentHighlightedChanged, this, [this] {
        if (!m_highlightedSet)
            emit highlightedChanged();
    });
}

void KeelGlassItem::setHighlighted(bool h)
{
    const bool was = highlighted();
    m_highlightedSet = true;
    m_highlighted = h;
    if (was != h)
        emit highlightedChanged();
}

void KeelGlassItem::resetHighlighted()
{
    const bool was = highlighted();
    m_highlightedSet = false;
    if (was != highlighted())
        emit highlightedChanged();
}

void KeelGlassItem::componentComplete()
{
    QQuickPaintedItem::componentComplete();
    m_palette->componentComplete();
    const qreal size = keel::themeValue(this, "itemSizeExtraSmall", 70);
    setImplicitSize(size, size);
}

// The glow of a glass item, measured on published Sailfish OS 4 screenshots
// (keel/silica/tests/screenshots/reference/SOURCES.md): at a distance d (in item
// heights) from the core the intensity is 1 up to 0.27 x radius, then falls
// off exponentially with a length of 0.62 x falloffRadius (a checked
// TextSwitch at radius 0.22, falloff 0.17: half intensity at 0.13, a tenth
// at 0.30). Sailfish draws the glow through a fine screen-door dither: the
// lit pixels follow Keel's glass dither pattern (the one ApplicationWindow
// lays over the wallpaper), up to about four times the mean intensity.
namespace {

// Keel's 8x8 glass dither (keel/silica/ambience/make-ambience.py), 0..1.
qreal ditherAt(int x, int y)
{
    static const qreal rows[4] = { 1.0, 15.0 / 24, 8.0 / 24, 4.0 / 24 };
    for (const int o : { 0, 4 }) {
        const int dy = ((y - o) % 8 + 8) % 8;
        if (dy > 3)
            continue;
        const int dx = ((x - o) % 8 + 8) % 8;
        const int dist = qMin(dx, 8 - dx);
        if (dist <= dy)
            return rows[dy];
    }
    return 0.0;
}

} // namespace

void KeelGlassItem::paintGlow(QPainter *p, qreal x0, qreal x1, qreal cy, qreal core,
                              qreal falloff, const QColor &color, qreal strength)
{
    if (color.alpha() == 0 || strength <= 0)
        return;
    const int w = qCeil(width());
    const int h = qCeil(height());
    if (w <= 0 || h <= 0)
        return;
    const qreal length = qMax<qreal>(0.5, falloff);
    // Fade out radially before the item's edges so the glow stays round.
    const qreal reach = qMin(height() / 2, x0 == x1 ? width() / 2 : height() / 2);
    const qreal fade = qMax<qreal>(1.0, 0.3 * reach);
    QImage image(w, h, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    const QPointF origin = mapToScene(QPointF(0, 0));
    const int ox = qRound(origin.x());
    const int oy = qRound(origin.y());
    for (int y = 0; y < h; ++y) {
        auto *line = reinterpret_cast<QRgb *>(image.scanLine(y));
        const qreal py = y + 0.5;
        for (int x = 0; x < w; ++x) {
            const qreal px = x + 0.5;
            const qreal nx = px < x0 ? x0 : (px > x1 ? x1 : px);
            const qreal dx = px - nx;
            const qreal dy = py - cy;
            const qreal d = std::sqrt(dx * dx + dy * dy);
            qreal i = d <= core ? 1.0 : std::exp(-(d - core) / length);
            const qreal toEdge = reach - d;
            if (toEdge <= 0)
                continue;
            if (toEdge < fade)
                i *= toEdge / fade;
            if (i < 0.004)
                continue;
            // Dithered towards the outside: the core stays solid.
            const qreal dither = 0.4 + 3.5 * ditherAt(ox + x, oy + y);
            const qreal a = qBound(0.0, strength * (i >= 0.6 ? i : qMin(1.0, i * dither)), 1.0)
                            * color.alphaF();
            line[x] = qPremultiply(qRgba(color.red(), color.green(), color.blue(), qRound(a * 255)));
        }
    }
    p->drawImage(QPointF(0, 0), image);
}

void KeelGlassItem::paint(QPainter *painter)
{
    const qreal w = width();
    const qreal h = height();
    if (w <= 0 || h <= 0)
        return;
    const qreal cy = h / 2;
    const qreal core = qMax<qreal>(0.75, 0.27 * m_radius * h);
    const qreal falloff = qMax<qreal>(0.0, 0.62 * m_falloffRadius * h);
    qreal x0 = w / 2;
    qreal x1 = w / 2;
    if (m_ratio <= 0.0 && w > h) {
        // A capsule along the width, inset so that the glow fits.
        x0 = h / 2;
        x1 = w - h / 2;
    }
    const qreal strength = qBound(0.0, m_brightness, 1.0) * (m_dimmed ? 0.5 : 1.0);

    // Halo behind the indicator.
    paintGlow(painter, x0, x1, cy, core, falloff * 2.2, m_backgroundColor, 0.5);

    if (m_dashed && m_dashLength > 0 && x1 > x0) {
        painter->save();
        QPainterPath clip;
        const qreal period = m_dashLength + qMax<qreal>(1.0, m_dashMargin);
        const qreal start = x0 - period + std::fmod(m_dashOffset, period);
        for (int i = 0;; ++i) {
            const qreal x = start + i * period;
            if (x >= x1 + period)
                break;
            clip.addRect(QRectF(x, 0, m_dashLength, h));
        }
        painter->setClipPath(clip);
        paintGlow(painter, x0, x1, cy, core, falloff, m_color, strength);
        painter->restore();
        return;
    }
    // The core is whiter than the glow colour, as on Sailfish.
    paintGlow(painter, x0, x1, cy, core, falloff, m_color, strength);
    paintGlow(painter, x0, x1, cy, core * 0.6, falloff * 0.35, QColor(255, 255, 255, 150), strength);
}
