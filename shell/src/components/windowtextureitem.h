#pragma once

#include <QPointer>
#include <QQuickItem>
#include <QRectF>
#include <qqml.h>

// Draws another item's texture (a Wayland surface item, a layer, an
// Image) without copying it: crop through sourceRect (normalized), round the
// corners without MSAA or a layer. The source stays in the scene, usually at
// opacity 0, so it keeps its texture current.
class WindowTextureItem : public QQuickItem {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QQuickItem *source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(qreal radius READ radius WRITE setRadius NOTIFY radiusChanged)
    Q_PROPERTY(QRectF sourceRect READ sourceRect WRITE setSourceRect NOTIFY sourceRectChanged)
    // The source had a texture at the last frame: safe to hide the source.
    Q_PROPERTY(bool ready READ isReady NOTIFY readyChanged)

  public:
    explicit WindowTextureItem(QQuickItem *parent = nullptr);
    ~WindowTextureItem() override;

    QQuickItem *source() const {
        return m_source;
    }
    void  setSource(QQuickItem *source);
    qreal radius() const {
        return m_radius;
    }
    void   setRadius(qreal radius);
    QRectF sourceRect() const {
        return m_sourceRect;
    }
    void setSourceRect(const QRectF &rect);
    bool isReady() const {
        return m_ready;
    }

    // An item is shown when it and its ancestors are visible and not
    // transparent. Read on the render thread during sync.
    static bool isShown(const QQuickItem *item);
    // A shown WindowTextureItem draws item's texture.
    static bool isSampled(const QQuickItem *item);

  signals:
    void sourceChanged();
    void radiusChanged();
    void sourceRectChanged();
    void readyChanged();

  protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *data) override;
    void     geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

  private:
    void                 setReady(bool ready);

    QPointer<QQuickItem> m_source;
    qreal                m_radius     = 0;
    QRectF               m_sourceRect = QRectF(0, 0, 1, 1);
    bool                 m_ready      = false;
};
