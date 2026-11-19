#include "SoftwareVideoOutput.h"
#include <QQuickWindow>

SoftwareVideoOutput::SoftwareVideoOutput(QQuickItem *parent)
    : QQuickItem(parent) {
    setFlag(ItemHasContents, true);
}

int SoftwareVideoOutput::fillMode() const {
    return m_fillMode;
}

void SoftwareVideoOutput::setFillMode(int mode) {
    if (m_fillMode == static_cast<FillMode>(mode))
        return;
    m_fillMode = static_cast<FillMode>(mode);
    emit fillModeChanged();
    update();
}

bool SoftwareVideoOutput::frozen() const {
    return m_frozen;
}

void SoftwareVideoOutput::setFrozen(bool frozen) {
    if (m_frozen.exchange(frozen) != frozen)
        emit frozenChanged();
}

void SoftwareVideoOutput::present(const QImage &frame) {
    if (m_frozen && !frame.isNull())
        return;
    {
        QMutexLocker locker(&m_frameMutex);
        m_currentFrame = frame;
        m_frameUpdated = true;
    }
    update();
}

QImage SoftwareVideoOutput::frame() const {
    QMutexLocker locker(&m_frameMutex);
    return m_currentFrame;
}

QSGNode *SoftwareVideoOutput::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) {
    if (!window())
        return nullptr;

    QSGSimpleTextureNode *node = static_cast<QSGSimpleTextureNode *>(oldNode);
    if (!node) {
        node = new QSGSimpleTextureNode();
        node->setOwnsTexture(true);
    }

    QImage image;
    bool   newFrame = false;
    {
        QMutexLocker locker(&m_frameMutex);
        if (m_frameUpdated) {
            image          = m_currentFrame;
            m_frameUpdated = false;
            newFrame       = true;
        } else if (!m_currentFrame.isNull()) {

            image = m_currentFrame;
        }
    }

    if (image.isNull()) {
        delete node;
        return nullptr;
    }

    if (newFrame) {

        QSGTexture *texture = window()->createTextureFromImage(image);
        if (texture) {
            node->setTexture(texture);

            texture->setFiltering(QSGTexture::Linear);
        }
    }

    if (!node->texture())
        return node;

    QSize texSize = node->texture()->textureSize();
    if (texSize.isEmpty())
        return node;

    QRectF itemRect(0, 0, width(), height());
    QRectF targetRect = itemRect;
    QRectF sourceRect(QPointF(0, 0), texSize);

    if (m_fillMode == Stretch) {
        targetRect = itemRect;
    } else if (m_fillMode == PreserveAspectCrop) {
        // The middle of the frame, in the item's shape, so nothing spills out.
        const qreal scale =
            qMax(itemRect.width() / texSize.width(), itemRect.height() / texSize.height());
        const QSizeF shown(itemRect.width() / scale, itemRect.height() / scale);
        sourceRect =
            QRectF((texSize.width() - shown.width()) / 2.0,
                   (texSize.height() - shown.height()) / 2.0, shown.width(), shown.height());
    } else {
        const qreal scale =
            qMin(itemRect.width() / texSize.width(), itemRect.height() / texSize.height());

        qreal w = texSize.width() * scale;
        qreal h = texSize.height() * scale;

        targetRect = QRectF((itemRect.width() - w) / 2.0, (itemRect.height() - h) / 2.0, w, h);
    }

    node->setRect(targetRect);
    node->setSourceRect(sourceRect);

    node->setTextureCoordinatesTransform(QSGSimpleTextureNode::NoTransform);

    return node;
}
