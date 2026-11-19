#pragma once

#include <QImage>
#include <QMutex>
#include <QQuickItem>
#include <QSGSimpleTextureNode>
#include <atomic>
#include <QtQmlIntegration/qqmlintegration.h>

class SoftwareVideoOutput : public QQuickItem {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int fillMode READ fillMode WRITE setFillMode NOTIFY fillModeChanged)
    // Holds the last frame, and skips new ones.
    Q_PROPERTY(bool frozen READ frozen WRITE setFrozen NOTIFY frozenChanged)

  public:
    enum FillMode : quint8 {
        Stretch            = 0,
        PreserveAspectFit  = 1,
        PreserveAspectCrop = 2
    };
    Q_ENUM(FillMode)

    explicit SoftwareVideoOutput(QQuickItem *parent = nullptr);

    int  fillMode() const;
    void setFillMode(int mode);
    bool frozen() const;
    void setFrozen(bool frozen);

    // Shows an RGB frame; a null image clears the item.
    void   present(const QImage &frame);
    QImage frame() const;

  protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;

  signals:
    void fillModeChanged();
    void frozenChanged();

  private:
    QImage            m_currentFrame;
    mutable QMutex    m_frameMutex;
    FillMode          m_fillMode     = PreserveAspectFit;
    bool              m_frameUpdated = false;
    std::atomic<bool> m_frozen{false};
};
