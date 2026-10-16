#include "windowtextureitem.h"
#include "windowtexturegeometry.h"

#include <QMultiHash>
#include <QQuickWindow>
#include <QSGGeometryNode>
#include <QSGImageNode>
#include <QSGDynamicTexture>
#include <QSGMaterialShader>
#include <QSGRendererInterface>
#include <QSGTextureMaterial>
#include <QSGTextureProvider>
#include <QtMath>

#ifdef HAVE_WAYLAND
#include <QWaylandQuickItem>
#include <QWaylandSurface>
#endif

#include <algorithm>
#include <cstring>

namespace {

    using WindowTextureGeometry::CornerVertex;
    using WindowTextureGeometry::Vertex;

    QMultiHash<const QQuickItem *, const WindowTextureItem *> s_consumers;

    class CornerMaterial : public QSGMaterial {
      public:
        CornerMaterial() {
            setFlag(Blending);
        }
        QSGMaterialType *type() const override {
            static QSGMaterialType t;
            return &t;
        }
        QSGMaterialShader *createShader(QSGRendererInterface::RenderMode) const override;
        int                compare(const QSGMaterial *other) const override {
            const auto  *o = static_cast<const CornerMaterial *>(other);
            const qint64 a = texture ? qint64(texture->comparisonKey()) : 0;
            const qint64 b = o->texture ? qint64(o->texture->comparisonKey()) : 0;
            if (a != b)
                return a < b ? -1 : 1;
            if (edges != o->edges)
                return edges.x() < o->edges.x() ||
                        (edges.x() == o->edges.x() && edges.y() < o->edges.y()) ?
                    -1 :
                    1;
            return 0;
        }

        QSGTexture *texture = nullptr;
        QPointF     edges{1, 1};
    };

    class CornerShader : public QSGMaterialShader {
      public:
        CornerShader() {
            setShaderFileName(VertexStage,
                              QStringLiteral(":/marathon/shaders/windowcorner.vert.qsb"));
            setShaderFileName(FragmentStage,
                              QStringLiteral(":/marathon/shaders/windowcorner.frag.qsb"));
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
            const QPointF edges = static_cast<CornerMaterial *>(newMaterial)->edges;
            const float   e[2]  = {float(edges.x()), float(edges.y())};
            std::memcpy(buf->data() + 72, e, 8);
            return true;
        }

        void updateSampledImage(RenderState &state, int binding, QSGTexture **texture,
                                QSGMaterial *newMaterial, QSGMaterial *) override {
            QSGTexture *t = static_cast<CornerMaterial *>(newMaterial)->texture;
            if (binding != 1 || !t)
                return;
            t->setFiltering(QSGTexture::Linear);
            t->commitTextureOperations(state.rhi(), state.resourceUpdateBatch());
            *texture = t;
        }
    };

    QSGMaterialShader *CornerMaterial::createShader(QSGRendererInterface::RenderMode) const {
        return new CornerShader;
    }

    const QSGGeometry::AttributeSet &cornerAttributes() {
        static const QSGGeometry::Attribute attrs[] = {
            QSGGeometry::Attribute::createWithAttributeType(0, 2, QSGGeometry::FloatType,
                                                            QSGGeometry::PositionAttribute),
            QSGGeometry::Attribute::createWithAttributeType(1, 2, QSGGeometry::FloatType,
                                                            QSGGeometry::TexCoordAttribute),
            QSGGeometry::Attribute::createWithAttributeType(2, 2, QSGGeometry::FloatType,
                                                            QSGGeometry::TexCoord1Attribute),
        };
        static const QSGGeometry::AttributeSet set = {3, sizeof(CornerVertex), attrs};
        return set;
    }

} // namespace

// Lives on the render thread. The provider's texture can be replaced on
// every client commit (QtWayland deletes the old one), so the node follows
// textureChanged directly instead of waiting for the item's next sync.
class WindowTextureNode : public QObject, public QSGNode {
    Q_OBJECT

  public:
    WindowTextureNode(QQuickWindow *window, bool software)
        : m_window(window)
        , m_software(software)
        , m_bodyGeometry(QSGGeometry::defaultAttributes_TexturedPoint2D(), 0)
        , m_cornerGeometry(cornerAttributes(), 0) {
        // A layer or ShaderEffectSource renders only when its consumer asks;
        // the source sits at opacity 0, where nothing else does.
        setFlag(QSGNode::UsePreprocess);
        if (m_software)
            return;
        m_opaque.setFiltering(QSGTexture::Linear);
        m_material.setFiltering(QSGTexture::Linear);
        m_body.setGeometry(&m_bodyGeometry);
        m_body.setMaterial(&m_material);
        m_body.setFlag(QSGNode::OwnedByParent, false);
        m_cornerGeometry.setDrawingMode(QSGGeometry::DrawTriangles);
        m_corners.setGeometry(&m_cornerGeometry);
        m_corners.setMaterial(&m_cornerMaterial);
        m_corners.setFlag(QSGNode::OwnedByParent, false);
        appendChildNode(&m_body);
        appendChildNode(&m_corners);
    }

    ~WindowTextureNode() override {
        if (!m_software) {
            removeChildNode(&m_body);
            removeChildNode(&m_corners);
        }
    }

    void setProvider(QSGTextureProvider *provider) {
        if (provider == m_provider)
            return;
        if (m_provider)
            disconnect(m_provider, nullptr, this, nullptr);
        m_provider = provider;
        if (provider) {
            connect(provider, &QSGTextureProvider::textureChanged, this, &WindowTextureNode::apply,
                    Qt::DirectConnection);
            connect(provider, &QObject::destroyed, this, &WindowTextureNode::apply,
                    Qt::DirectConnection);
        }
    }

    void setParams(const QRectF &rect, const QRectF &sourceRect, bool flipY, qreal radius,
                   qreal aaWidth) {
        m_rect       = rect;
        m_sourceRect = sourceRect;
        m_flipY      = flipY;
        m_radius     = radius;
        m_aaWidth    = aaWidth;
        apply();
    }

    bool hasTexture() const {
        return m_texture != nullptr;
    }

    void preprocess() override {
        if (auto *dynamic = qobject_cast<QSGDynamicTexture *>(m_texture);
            dynamic && dynamic->updateTexture())
            apply();
    }

  private:
    void apply() {
        m_texture = m_provider ? m_provider->texture() : nullptr;
        if (m_software)
            applySoftware();
        else
            applyRhi();
    }

    void applySoftware() {
        if (!m_texture) {
            if (m_image) {
                removeChildNode(m_image);
                delete m_image;
                m_image = nullptr;
            }
            return;
        }
        if (!m_image) {
            m_image = m_window->createImageNode();
            appendChildNode(m_image);
        }
        const QSizeF size = m_texture->textureSize();
        m_image->setTexture(m_texture);
        m_image->setFiltering(QSGTexture::Linear);
        m_image->setRect(m_rect);
        m_image->setSourceRect(
            QRectF(m_sourceRect.x() * size.width(), m_sourceRect.y() * size.height(),
                   m_sourceRect.width() * size.width(), m_sourceRect.height() * size.height()));
        m_image->setTextureCoordinatesTransform(m_flipY ? QSGImageNode::MirrorVertically :
                                                          QSGImageNode::NoTransform);
    }

    void applyRhi() {
        if (!m_texture) {
            m_bodyGeometry.allocate(0);
            m_cornerGeometry.allocate(0);
            m_body.markDirty(QSGNode::DirtyGeometry);
            m_corners.markDirty(QSGNode::DirtyGeometry);
            return;
        }
        m_opaque.setTexture(m_texture);
        m_material.setTexture(m_texture);
        m_cornerMaterial.texture = m_texture;
        m_body.setOpaqueMaterial(m_texture->hasAlphaChannel() ? nullptr : &m_opaque);

        const QRectF tex = WindowTextureGeometry::textureRect(m_texture->normalizedTextureSubRect(),
                                                              m_sourceRect, m_flipY);
        m_bodyGeometry.allocate(WindowTextureGeometry::BodyVertices);
        m_cornerGeometry.allocate(WindowTextureGeometry::CornerVertices);
        const qreal r = WindowTextureGeometry::build(
            m_rect, tex, m_radius, reinterpret_cast<Vertex *>(m_bodyGeometry.vertexData()),
            static_cast<CornerVertex *>(m_cornerGeometry.vertexData()));
        if (r <= 0)
            m_cornerGeometry.allocate(0);
        m_cornerMaterial.edges = WindowTextureGeometry::cornerEdges(r, m_aaWidth);
        m_body.markDirty(QSGNode::DirtyGeometry | QSGNode::DirtyMaterial);
        m_corners.markDirty(QSGNode::DirtyGeometry | QSGNode::DirtyMaterial);
    }

    QQuickWindow                *m_window;
    const bool                   m_software;
    QPointer<QSGTextureProvider> m_provider;
    QSGTexture                  *m_texture = nullptr;
    QRectF                       m_rect;
    QRectF                       m_sourceRect;
    bool                         m_flipY   = false;
    qreal                        m_radius  = 0;
    qreal                        m_aaWidth = 1;

    QSGGeometryNode              m_body;
    QSGGeometry                  m_bodyGeometry;
    QSGOpaqueTextureMaterial     m_opaque;
    QSGTextureMaterial           m_material;
    QSGGeometryNode              m_corners;
    QSGGeometry                  m_cornerGeometry;
    CornerMaterial               m_cornerMaterial;
    QSGImageNode                *m_image = nullptr;
};

WindowTextureItem::WindowTextureItem(QQuickItem *parent)
    : QQuickItem(parent) {
    setFlag(ItemHasContents);
}

WindowTextureItem::~WindowTextureItem() {
    if (m_source)
        s_consumers.remove(m_source, this);
}

void WindowTextureItem::setSource(QQuickItem *source) {
    if (source == m_source)
        return;
    if (m_source) {
        s_consumers.remove(m_source, this);
        disconnect(m_source, &QObject::destroyed, this, nullptr);
    }
    m_source = source;
    if (source) {
        s_consumers.insert(source, this);
        connect(source, &QObject::destroyed, this, [this, source]() {
            s_consumers.remove(source, this);
            update();
        });
    }
    update();
    emit sourceChanged();
}

void WindowTextureItem::setRadius(qreal radius) {
    if (qFuzzyCompare(radius, m_radius))
        return;
    m_radius = radius;
    update();
    emit radiusChanged();
}

void WindowTextureItem::setSourceRect(const QRectF &rect) {
    if (rect == m_sourceRect)
        return;
    m_sourceRect = rect;
    update();
    emit sourceRectChanged();
}

void WindowTextureItem::setReady(bool ready) {
    if (ready == m_ready)
        return;
    m_ready = ready;
    emit readyChanged();
}

void WindowTextureItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) {
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size())
        update();
}

bool WindowTextureItem::isShown(const QQuickItem *item) {
    if (!item || !item->window() || !item->isVisible())
        return false;
    for (const QQuickItem *p = item; p; p = p->parentItem()) {
        if (p->opacity() <= 0)
            return false;
    }
    return true;
}

bool WindowTextureItem::isSampled(const QQuickItem *item) {
    const auto range = s_consumers.equal_range(item);
    return std::any_of(range.first, range.second,
                       [](const WindowTextureItem *consumer) { return isShown(consumer); });
}

QSGNode *WindowTextureItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *data) {
    auto               *node = static_cast<WindowTextureNode *>(oldNode);
    QSGTextureProvider *provider =
        m_source && m_source->isTextureProvider() ? m_source->textureProvider() : nullptr;
    if (!provider || width() <= 0 || height() <= 0) {
        delete node;
        QMetaObject::invokeMethod(this, [this]() { setReady(false); }, Qt::QueuedConnection);
        return nullptr;
    }

    if (!node) {
        const bool software =
            window()->rendererInterface()->graphicsApi() == QSGRendererInterface::Software;
        node = new WindowTextureNode(window(), software);
    }
    node->setProvider(provider);

    bool flipY = false;
#ifdef HAVE_WAYLAND
    if (const auto *surfaceItem = qobject_cast<const QWaylandQuickItem *>(m_source.data()))
        flipY = surfaceItem->origin() == QWaylandSurface::OriginBottomLeft;
#endif
    // One screen pixel of fade at the arc, whatever the item's scale.
    const QMatrix4x4 &m     = data->transformNode->combinedMatrix();
    const qreal       scale = qSqrt(qAbs(m(0, 0) * m(1, 1) - m(0, 1) * m(1, 0)));
    node->setParams(boundingRect(), m_sourceRect, flipY, m_radius, scale > 0 ? 1 / scale : 1);

    const bool ready = node->hasTexture();
    QMetaObject::invokeMethod(this, [this, ready]() { setReady(ready); }, Qt::QueuedConnection);
    return node;
}

#include "windowtextureitem.moc"
