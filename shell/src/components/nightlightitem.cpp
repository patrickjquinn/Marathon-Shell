#include "nightlightitem.h"

#include <QQuickWindow>
#include <QSGGeometryNode>
#include <QSGMaterial>
#include <QSGMaterialShader>
#include <QSGRendererInterface>
#include <QtMath>

#include <algorithm>
#include <cstring>

namespace {

    constexpr qreal kNeutral = 6500;

    class NightLightMaterial : public QSGMaterial {
      public:
        NightLightMaterial() {
            setFlag(Blending);
        }
        QSGMaterialType *type() const override {
            static QSGMaterialType t;
            return &t;
        }
        QSGMaterialShader *createShader(QSGRendererInterface::RenderMode) const override;
        int                compare(const QSGMaterial *other) const override {
            const QVector3D o = static_cast<const NightLightMaterial *>(other)->white;
            return white == o ? 0 : (white.lengthSquared() < o.lengthSquared() ? -1 : 1);
        }
        QVector3D white{1, 1, 1};
    };

    class NightLightShader : public QSGMaterialShader {
      public:
        NightLightShader() {
            setFlag(UpdatesGraphicsPipelineState);
            setShaderFileName(VertexStage,
                              QStringLiteral(":/marathon/shaders/nightlight.vert.qsb"));
            setShaderFileName(FragmentStage,
                              QStringLiteral(":/marathon/shaders/nightlight.frag.qsb"));
        }

        bool updateUniformData(RenderState &state, QSGMaterial *newMaterial,
                               QSGMaterial *) override {
            QByteArray *buf = state.uniformData();
            if (state.isMatrixDirty())
                std::memcpy(buf->data(), state.combinedMatrix().constData(), 64);
            if (state.isOpacityDirty()) {
                const float opacity = state.opacity();
                std::memcpy(buf->data() + 64, &opacity, 4);
            }
            const QVector3D w    = static_cast<NightLightMaterial *>(newMaterial)->white;
            const float     v[4] = {w.x(), w.y(), w.z(), 1};
            std::memcpy(buf->data() + 80, v, 16);
            return true;
        }

        bool updateGraphicsPipelineState(RenderState &, GraphicsPipelineState *ps, QSGMaterial *,
                                         QSGMaterial *) override {
            ps->blendEnable          = true;
            ps->srcColor             = GraphicsPipelineState::Zero;
            ps->dstColor             = GraphicsPipelineState::SrcColor;
            ps->separateBlendFactors = true;
            ps->srcAlpha             = GraphicsPipelineState::Zero;
            ps->dstAlpha             = GraphicsPipelineState::One;
            return true;
        }
    };

    QSGMaterialShader *NightLightMaterial::createShader(QSGRendererInterface::RenderMode) const {
        return new NightLightShader;
    }

    // Linear sRGB of the Planckian locus at `kelvin` (Kim et al. 2002 cubic
    // fit, 1667-25000 K), at Y = 1.
    QVector3D locus(qreal kelvin) {
        const qreal t = std::clamp(kelvin, qreal(1667), qreal(25000));
        const qreal x = t < 4000 ?
            -0.2661239e9 / (t * t * t) - 0.2343589e6 / (t * t) + 0.8776956e3 / t + 0.179910 :
            -3.0258469e9 / (t * t * t) + 2.1070379e6 / (t * t) + 0.2226347e3 / t + 0.240390;
        const qreal y = t < 2222 ?
            -1.1063814 * x * x * x - 1.34811020 * x * x + 2.18555832 * x - 0.20219683 :
            t < 4000 ? -0.9549476 * x * x * x - 1.37418593 * x * x + 2.09137015 * x - 0.16748867 :
                       3.0817580 * x * x * x - 5.87338670 * x * x + 3.75112997 * x - 0.37001483;
        const qreal X = x / y;
        const qreal Z = (1 - x - y) / y;
        return QVector3D(float(3.2404542 * X - 1.5371385 - 0.4985314 * Z),
                         float(-0.9692660 * X + 1.8760108 + 0.0415560 * Z),
                         float(0.0556434 * X - 0.2040259 + 1.0572252 * Z));
    }

} // namespace

NightLightItem::NightLightItem(QQuickItem *parent)
    : QQuickItem(parent) {
    setFlag(ItemHasContents);
}

void NightLightItem::setTemperature(qreal kelvin) {
    if (qFuzzyCompare(m_temperature, kelvin))
        return;
    m_temperature = kelvin;
    emit temperatureChanged();
    update();
}

void NightLightItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) {
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    update();
}

QVector3D NightLightItem::whitePoint(qreal kelvin) {
    if (kelvin >= kNeutral)
        return {1, 1, 1};
    // Relative to the locus at 6500 K so that it, not D65, is neutral; the
    // frame is gamma-encoded, so the linear scale is encoded too.
    QVector3D   w = locus(kelvin) / locus(kNeutral);
    const float m = std::max({w.x(), w.y(), w.z()});
    for (int i = 0; i < 3; ++i)
        w[i] = float(qPow(std::max(w[i] / m, 0.0f), 1 / 2.2));
    return w;
}

QSGNode *NightLightItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) {
    auto *node = static_cast<QSGGeometryNode *>(oldNode);
    if (m_temperature >= kNeutral || width() <= 0 || height() <= 0 ||
        window()->rendererInterface()->graphicsApi() == QSGRendererInterface::Software) {
        delete node;
        return nullptr;
    }
    if (!node) {
        node = new QSGGeometryNode;
        node->setGeometry(new QSGGeometry(QSGGeometry::defaultAttributes_Point2D(), 4));
        node->setFlag(QSGNode::OwnsGeometry);
        node->setMaterial(new NightLightMaterial);
        node->setFlag(QSGNode::OwnsMaterial);
    }
    QSGGeometry::updateRectGeometry(node->geometry(), boundingRect());
    static_cast<NightLightMaterial *>(node->material())->white = whitePoint(m_temperature);
    node->markDirty(QSGNode::DirtyGeometry | QSGNode::DirtyMaterial);
    return node;
}
