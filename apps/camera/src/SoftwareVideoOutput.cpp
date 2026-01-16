#include "SoftwareVideoOutput.h"
#include <QQuickWindow>

SoftwareVideoOutput::SoftwareVideoOutput(QQuickItem *parent)
    : QQuickItem(parent) {
    m_videoSink = new QVideoSink(this);
    connect(m_videoSink, &QVideoSink::videoFrameChanged, this,
            &SoftwareVideoOutput::onVideoFrameChanged);

    setFlag(ItemHasContents, true);
}

SoftwareVideoOutput::~SoftwareVideoOutput() {}

QObject *SoftwareVideoOutput::videoSink() const {
    return m_videoSink;
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

void SoftwareVideoOutput::onVideoFrameChanged(const QVideoFrame &frame) {
    if (!frame.isValid())
        return;

    QImage image = frame.toImage();
    if (image.isNull())
        return;

    if (image.format() != QImage::Format_RGBA8888_Premultiplied &&
        image.format() != QImage::Format_RGBA8888 &&
        image.format() != QImage::Format_ARGB32_Premultiplied) {
        image = image.convertToFormat(QImage::Format_RGBA8888_Premultiplied);
    }

    {
        QMutexLocker locker(&m_frameMutex);
        m_currentFrame = image;
        m_frameUpdated = true;
    }

    update();
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

    if (m_fillMode == Stretch) {
        targetRect = itemRect;
    } else {
        bool  fit = (m_fillMode == PreserveAspectFit);

        qreal scaleW = itemRect.width() / texSize.width();
        qreal scaleH = itemRect.height() / texSize.height();

        qreal scale;
        if (fit) {
            scale = qMin(scaleW, scaleH);
        } else {
            scale = qMax(scaleW, scaleH);
        }

        qreal w = texSize.width() * scale;
        qreal h = texSize.height() * scale;

        targetRect = QRectF((itemRect.width() - w) / 2.0, (itemRect.height() - h) / 2.0, w, h);
    }

    node->setRect(targetRect);

    node->setTextureCoordinatesTransform(QSGSimpleTextureNode::NoTransform);

    return node;
}
