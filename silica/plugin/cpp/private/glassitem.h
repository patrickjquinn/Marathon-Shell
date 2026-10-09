// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// GlassItem (Sailfish.Silica.private): the glowing indicator of switches,
// progress bars and the page stack indicator. Property names inferred from
// Silica's BSD QML (Switch, TextSwitch, ProgressBar, PageStackGlassIndicator):
// color, backgroundColor, dimmed, brightness, radius, falloffRadius,
// defaultFalloffRadius, ratio, dashed, dashLength, dashMargin, dashOffset.
// Clean-room drawing (QPainter): a core of `radius` (a fraction of the
// height) glowing out over `falloffRadius`, as a dot, or with `ratio` 0 a
// capsule along the width; `backgroundColor` is a wider halo behind it.
// Default size Theme.itemSizeExtraSmall square. Geometry and falloff curves
// are Keel's; they are to be compared with Silica on device.
#ifndef KEEL_GLASSITEM_H
#define KEEL_GLASSITEM_H

#include "palette.h"

#include <QColor>
#include <QQuickPaintedItem>
#include <QtQml/qqmlregistration.h>

class KeelGlassItem : public QQuickPaintedItem
{
    Q_OBJECT
    QML_NAMED_ELEMENT(GlassItem)
    Q_PROPERTY(QColor color READ color WRITE setColor NOTIFY colorChanged)
    Q_PROPERTY(QColor backgroundColor READ backgroundColor WRITE setBackgroundColor NOTIFY backgroundColorChanged)
    Q_PROPERTY(bool dimmed READ dimmed WRITE setDimmed NOTIFY dimmedChanged)
    Q_PROPERTY(qreal brightness READ brightness WRITE setBrightness NOTIFY brightnessChanged)
    Q_PROPERTY(qreal radius READ radius WRITE setRadius NOTIFY radiusChanged)
    Q_PROPERTY(qreal falloffRadius READ falloffRadius WRITE setFalloffRadius NOTIFY falloffRadiusChanged)
    Q_PROPERTY(qreal defaultFalloffRadius READ defaultFalloffRadius CONSTANT)
    Q_PROPERTY(qreal ratio READ ratio WRITE setRatio NOTIFY ratioChanged)
    Q_PROPERTY(bool dashed READ dashed WRITE setDashed NOTIFY dashedChanged)
    Q_PROPERTY(qreal dashLength READ dashLength WRITE setDashLength NOTIFY dashLengthChanged)
    Q_PROPERTY(qreal dashMargin READ dashMargin WRITE setDashMargin NOTIFY dashMarginChanged)
    Q_PROPERTY(qreal dashOffset READ dashOffset WRITE setDashOffset NOTIFY dashOffsetChanged)
    Q_PROPERTY(bool cache READ cache WRITE setCache NOTIFY cacheChanged)
    // A Silica item (Silica's BSD QML reads `palette` in its bindings).
    Q_PROPERTY(bool __keel_silica_style READ isSilicaStyle CONSTANT)
    Q_PROPERTY(bool highlighted READ highlighted WRITE setHighlighted RESET resetHighlighted NOTIFY highlightedChanged)
    // Shadows QQuickItem::palette (Qt 6). Qt 6.10+ warns about a shadowing
    // property unless it is marked OVERRIDE, which older moc does not know.
#if QT_VERSION >= QT_VERSION_CHECK(6, 10, 0)
    Q_PROPERTY(KeelPalette *palette READ palette CONSTANT OVERRIDE)
#else
    Q_PROPERTY(KeelPalette *palette READ palette CONSTANT)
#endif

public:
    explicit KeelGlassItem(QQuickItem *parent = nullptr);

    QColor color() const { return m_color; }
    void setColor(const QColor &c) { set(m_color, c, &KeelGlassItem::colorChanged); }
    QColor backgroundColor() const { return m_backgroundColor; }
    void setBackgroundColor(const QColor &c) { set(m_backgroundColor, c, &KeelGlassItem::backgroundColorChanged); }
    bool dimmed() const { return m_dimmed; }
    void setDimmed(bool d) { set(m_dimmed, d, &KeelGlassItem::dimmedChanged); }
    qreal brightness() const { return m_brightness; }
    void setBrightness(qreal b) { set(m_brightness, b, &KeelGlassItem::brightnessChanged); }
    qreal radius() const { return m_radius; }
    void setRadius(qreal r) { set(m_radius, r, &KeelGlassItem::radiusChanged); }
    qreal falloffRadius() const { return m_falloffRadius; }
    void setFalloffRadius(qreal r) { set(m_falloffRadius, r, &KeelGlassItem::falloffRadiusChanged); }
    qreal defaultFalloffRadius() const { return 0.17; }
    qreal ratio() const { return m_ratio; }
    void setRatio(qreal r) { set(m_ratio, r, &KeelGlassItem::ratioChanged); }
    bool dashed() const { return m_dashed; }
    void setDashed(bool d) { set(m_dashed, d, &KeelGlassItem::dashedChanged); }
    qreal dashLength() const { return m_dashLength; }
    void setDashLength(qreal l) { set(m_dashLength, l, &KeelGlassItem::dashLengthChanged); }
    qreal dashMargin() const { return m_dashMargin; }
    void setDashMargin(qreal m) { set(m_dashMargin, m, &KeelGlassItem::dashMarginChanged); }
    qreal dashOffset() const { return m_dashOffset; }
    void setDashOffset(qreal o) { set(m_dashOffset, o, &KeelGlassItem::dashOffsetChanged); }
    bool cache() const { return m_cache; }
    void setCache(bool c) { set(m_cache, c, &KeelGlassItem::cacheChanged); }

    bool isSilicaStyle() const { return true; }
    bool highlighted() const { return m_highlightedSet ? m_highlighted : m_palette->parentHighlighted(); }
    void setHighlighted(bool h);
    void resetHighlighted();
    KeelPalette *palette() const { return m_palette; }

    void paint(QPainter *painter) override;

signals:
    void colorChanged();
    void backgroundColorChanged();
    void dimmedChanged();
    void brightnessChanged();
    void radiusChanged();
    void falloffRadiusChanged();
    void ratioChanged();
    void dashedChanged();
    void dashLengthChanged();
    void dashMarginChanged();
    void dashOffsetChanged();
    void cacheChanged();
    void highlightedChanged();


protected:
    void componentComplete() override;

private:
    template<typename T>
    void set(T &field, const T &value, void (KeelGlassItem::*notify)())
    {
        if (field == value)
            return;
        field = value;
        emit(this->*notify)();
        update();
    }
    void paintGlow(QPainter *p, qreal x0, qreal x1, qreal cy, qreal core, qreal falloff,
                   const QColor &color, qreal strength);

    KeelPalette *m_palette;
    bool m_highlighted = false;
    bool m_highlightedSet = false;
    QColor m_color = QColor(255, 255, 255);
    QColor m_backgroundColor = Qt::transparent;
    bool m_dimmed = false;
    qreal m_brightness = 1.0;
    qreal m_radius = 0.22;
    qreal m_falloffRadius = 0.17;
    qreal m_ratio = 1.0;
    bool m_dashed = false;
    qreal m_dashLength = 0;
    qreal m_dashMargin = 0;
    qreal m_dashOffset = 0;
    bool m_cache = true;
};

#endif // KEEL_GLASSITEM_H
