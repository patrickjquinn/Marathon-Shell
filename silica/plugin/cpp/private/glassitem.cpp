// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Clean-room; see glassitem.h.

#include "glassitem.h"
#include "keeltheme.h"

#include <QFile>
#include <QQuickWindow>
#include <QSGGeometryNode>
#include <QSGImageNode>
#include <QSGMaterial>
#include <QSGMaterialShader>
#include <QSGRendererInterface>
#include <QtMath>

#include <cmath>
#include <cstddef>
#include <cstring>

KeelGlassItem::KeelGlassItem(QQuickItem *parent)
    : QQuickItem(parent)
    , m_palette(new KeelPalette(this))
{
    setFlag(ItemHasContents);
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
    QQuickItem::componentComplete();
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

// Keel's 8x8 glass dither (keel/silica/ambience/make-ambience.py), 0..1;
// glassitem.frag has the same.
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

// The GPU's glow: one quad, its position in item units, and the glow's
// shape and colours as uniforms in the layout glassitem.vert/.frag declare.
struct GlassUniforms {
    float matrix[16];
    float opacity;
    float pad[3];
    float color[4];
    float haloColor[4];
    float shape[4];
    float glow[4];
    float dash[4];
    float extra[4];
};
static_assert(sizeof(GlassUniforms) == 176, "std140 layout of glassitem.frag");

void putColor(float *out, const QColor &c)
{
    out[0] = c.redF();
    out[1] = c.greenF();
    out[2] = c.blueF();
    out[3] = c.alphaF();
}

class GlassMaterial : public QSGMaterial
{
public:
    GlassMaterial() { setFlag(Blending); }
    QSGMaterialType *type() const override
    {
        static QSGMaterialType type;
        return &type;
    }
    QSGMaterialShader *createShader(QSGRendererInterface::RenderMode) const override;
    int compare(const QSGMaterial *other) const override
    {
        const auto *o = static_cast<const GlassMaterial *>(other);
        const auto *a = reinterpret_cast<const float *>(&uniforms);
        const auto *b = reinterpret_cast<const float *>(&o->uniforms);
        for (std::size_t i = 0; i < sizeof(uniforms) / sizeof(float); ++i) {
            if (a[i] != b[i])
                return a[i] < b[i] ? -1 : 1;
        }
        return 0;
    }

    // Everything but the matrix and the opacity, which the renderer gives.
    GlassUniforms uniforms {};
};

class GlassShader : public QSGMaterialShader
{
public:
    GlassShader()
    {
        setShaderFileName(VertexStage, QStringLiteral(":/qt/qml/Sailfish/Silica/shaders/glassitem.vert.qsb"));
        setShaderFileName(FragmentStage, QStringLiteral(":/qt/qml/Sailfish/Silica/shaders/glassitem.frag.qsb"));
    }
    bool updateUniformData(RenderState &state, QSGMaterial *material, QSGMaterial *) override
    {
        QByteArray *buf = state.uniformData();
        Q_ASSERT(buf->size() >= int(sizeof(GlassUniforms)));
        auto *u = reinterpret_cast<GlassUniforms *>(buf->data());
        if (state.isMatrixDirty()) {
            const QMatrix4x4 m = state.combinedMatrix();
            std::memcpy(u->matrix, m.constData(), sizeof(u->matrix));
        }
        if (state.isOpacityDirty())
            u->opacity = state.opacity();
        const GlassUniforms &g = static_cast<GlassMaterial *>(material)->uniforms;
        const auto from = offsetof(GlassUniforms, color);
        std::memcpy(buf->data() + from, reinterpret_cast<const char *>(&g) + from, sizeof(GlassUniforms) - from);
        return true;
    }
};

QSGMaterialShader *GlassMaterial::createShader(QSGRendererInterface::RenderMode) const
{
    return new GlassShader;
}

class GlassNode : public QSGGeometryNode
{
public:
    GlassNode()
        : m_geometry(QSGGeometry::defaultAttributes_TexturedPoint2D(), 4)
    {
        setGeometry(&m_geometry);
        setMaterial(&m_material);
    }
    QSGGeometry m_geometry;
    GlassMaterial m_material;
};

bool shadersAvailable()
{
    // The shaders are in Sailfish.Silica's resources; Sailfish.Silica.private
    // alone (no Silica plugin loaded) draws in software instead.
    static const bool available = QFile::exists(QStringLiteral(":/qt/qml/Sailfish/Silica/shaders/glassitem.frag.qsb"));
    return available;
}

} // namespace

KeelGlassItem::Shape KeelGlassItem::shape() const
{
    const qreal w = width();
    const qreal h = height();
    Shape s {};
    s.cy = h / 2;
    s.core = qMax<qreal>(0.75, 0.27 * m_radius * h);
    s.falloff = qMax<qreal>(0.0, 0.62 * m_falloffRadius * h);
    s.x0 = w / 2;
    s.x1 = w / 2;
    if (m_ratio <= 0.0 && w > h) {
        // A capsule along the width, inset so that the glow fits.
        s.x0 = h / 2;
        s.x1 = w - h / 2;
    }
    s.strength = qBound(0.0, m_brightness, 1.0) * (m_dimmed ? 0.5 : 1.0);
    s.dashed = m_dashed && m_dashLength > 0 && s.x1 > s.x0;
    if (s.dashed) {
        s.dashPeriod = m_dashLength + qMax<qreal>(1.0, m_dashMargin);
        s.dashStart = s.x0 - s.dashPeriod + std::fmod(m_dashOffset, s.dashPeriod);
    }
    return s;
}

void KeelGlassItem::paintGlow(QImage &image, QPoint origin, qreal x0, qreal x1, qreal cy,
                              qreal core, qreal falloff, const QColor &color, qreal strength,
                              const Shape *dashes) const
{
    if (color.alpha() == 0 || strength <= 0)
        return;
    const int w = image.width();
    const int h = image.height();
    const qreal length = qMax<qreal>(0.5, falloff);
    // Fade out radially before the item's edges so the glow stays round.
    const qreal reach = qMin(height() / 2, x0 == x1 ? width() / 2 : height() / 2);
    const qreal fade = qMax<qreal>(1.0, 0.3 * reach);
    for (int y = 0; y < h; ++y) {
        auto *line = reinterpret_cast<QRgb *>(image.scanLine(y));
        const qreal py = y + 0.5;
        for (int x = 0; x < w; ++x) {
            const qreal px = x + 0.5;
            if (dashes) {
                const qreal t = px - dashes->dashStart;
                const qreal start = dashes->dashStart + std::floor(t / dashes->dashPeriod) * dashes->dashPeriod;
                if (t < 0 || px - start >= m_dashLength || start >= x1 + dashes->dashPeriod)
                    continue;
            }
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
            const qreal dither = 0.4 + 3.5 * ditherAt(origin.x() + x, origin.y() + y);
            const qreal a = qBound(0.0, strength * (i >= 0.6 ? i : qMin(1.0, i * dither)), 1.0)
                            * color.alphaF();
            // Over what the glows before this one drew.
            const QRgb under = line[x];
            const qreal keep = 1.0 - a;
            line[x] = qRgba(qRound(color.red() * a + qRed(under) * keep),
                            qRound(color.green() * a + qGreen(under) * keep),
                            qRound(color.blue() * a + qBlue(under) * keep),
                            qRound(255 * a + qAlpha(under) * keep));
        }
    }
}

QImage KeelGlassItem::render() const
{
    const int w = qCeil(width());
    const int h = qCeil(height());
    if (w <= 0 || h <= 0)
        return {};
    QImage image(w, h, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    const Shape s = shape();
    const QPointF scene = mapToScene(QPointF(0, 0));
    const QPoint origin(qRound(scene.x()), qRound(scene.y()));
    // Halo behind the indicator.
    paintGlow(image, origin, s.x0, s.x1, s.cy, s.core, s.falloff * 2.2, m_backgroundColor, 0.5, nullptr);
    paintGlow(image, origin, s.x0, s.x1, s.cy, s.core, s.falloff, m_color, s.strength, s.dashed ? &s : nullptr);
    // The core is whiter than the glow colour, as on Sailfish.
    if (!s.dashed)
        paintGlow(image, origin, s.x0, s.x1, s.cy, s.core * 0.6, s.falloff * 0.35,
                  QColor(255, 255, 255, 150), s.strength, nullptr);
    return image;
}

void KeelGlassItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size())
        update();
}

QSGNode *KeelGlassItem::updatePaintNode(QSGNode *old, UpdatePaintNodeData *)
{
    if (width() <= 0 || height() <= 0) {
        delete old;
        return nullptr;
    }
    const bool software = !shadersAvailable()
            || window()->rendererInterface()->graphicsApi() == QSGRendererInterface::Software;
    if (software) {
        auto *node = static_cast<QSGImageNode *>(old);
        if (!node) {
            node = window()->createImageNode();
            node->setOwnsTexture(true);
        }
        const QImage image = render();
        node->setTexture(window()->createTextureFromImage(image));
        node->setRect(QRectF(QPointF(0, 0), image.size()));
        return node;
    }
    auto *node = static_cast<GlassNode *>(old);
    if (!node)
        node = new GlassNode;
    const QRectF rect(0, 0, width(), height());
    QSGGeometry::updateTexturedRectGeometry(&node->m_geometry, rect, rect);
    node->markDirty(QSGNode::DirtyGeometry);

    const Shape s = shape();
    const QPointF scene = mapToScene(QPointF(0, 0));
    const qreal reach = qMin(height() / 2, s.x0 == s.x1 ? width() / 2 : height() / 2);
    GlassUniforms &u = node->m_material.uniforms;
    putColor(u.color, m_color);
    putColor(u.haloColor, m_backgroundColor);
    const float shapeValues[4] = { static_cast<float>(s.x0), static_cast<float>(s.x1), static_cast<float>(s.cy), static_cast<float>(reach) };
    std::memcpy(u.shape, shapeValues, sizeof(u.shape));
    const float glowValues[4] = { static_cast<float>(s.core), static_cast<float>(s.falloff), static_cast<float>(qMax<qreal>(1.0, 0.3 * reach)),
                                  static_cast<float>(s.strength) };
    std::memcpy(u.glow, glowValues, sizeof(u.glow));
    const float dashValues[4] = { s.dashed ? 1.0f : 0.0f, static_cast<float>(s.dashStart), static_cast<float>(s.dashPeriod),
                                  static_cast<float>(m_dashLength) };
    std::memcpy(u.dash, dashValues, sizeof(u.dash));
    const float extraValues[4] = { static_cast<float>(scene.x()), static_cast<float>(scene.y()),
                                   static_cast<float>(s.falloff * 2.2), static_cast<float>(s.x1 + s.dashPeriod) };
    std::memcpy(u.extra, extraValues, sizeof(u.extra));
    node->markDirty(QSGNode::DirtyMaterial);
    return node;
}
