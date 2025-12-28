#pragma once

#include <QImage>
#include <QMutex>
#include <QQuickItem>
#include <QSGSimpleTextureNode>
#include <QVideoFrame>
#include <QVideoSink>
#include <QtQmlIntegration>

class SoftwareVideoOutput : public QQuickItem {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QVideoSink *videoSink READ videoSink CONSTANT)
    Q_PROPERTY(int fillMode READ fillMode WRITE setFillMode NOTIFY fillModeChanged)

  public:
    enum FillMode {
        Stretch            = 0,
        PreserveAspectFit  = 1,
        PreserveAspectCrop = 2
    };
    Q_ENUM(FillMode)

    explicit SoftwareVideoOutput(QQuickItem *parent = nullptr);
    ~SoftwareVideoOutput() override;

    QVideoSink *videoSink() const;

    int         fillMode() const;
    void        setFillMode(int mode);

  protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;

  signals:
    void fillModeChanged();

  private slots:
    void onVideoFrameChanged(const QVideoFrame &frame);

  private:
    QVideoSink    *m_videoSink = nullptr;
    QImage         m_currentFrame;
    mutable QMutex m_frameMutex;
    FillMode       m_fillMode     = PreserveAspectFit;
    bool           m_frameUpdated = false;
};
