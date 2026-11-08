#pragma once

#include <QObject>
#include <QCamera>
#include <QMediaCaptureSession>
#include <QImageCapture>
#include <QMediaRecorder>
#include <QTimer>
#include <QVideoSink>
#include <atomic>
#include <QHash>
#include <QImage>
#include <QSize>
#include <QUrl>
#include <QVariantList>
#include <QtQmlIntegration/qqmlintegration.h>

class CameraController : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QObject *videoSink READ videoSink WRITE setVideoSink NOTIFY videoSinkChanged)
    Q_PROPERTY(bool discovered READ isDiscovered NOTIFY readyChanged)
    Q_PROPERTY(bool active READ isActive NOTIFY activeChanged)
    Q_PROPERTY(int cameraCount READ cameraCount NOTIFY cameraCountChanged)
    // Each camera as {id, description, position}, position a QCameraDevice::Position.
    Q_PROPERTY(QVariantList cameras READ cameras NOTIFY cameraCountChanged)
    Q_PROPERTY(QString defaultCameraId READ defaultCameraId NOTIFY cameraCountChanged)
    // Empty for the first camera.
    Q_PROPERTY(QString cameraId READ cameraId WRITE setCameraId NOTIFY currentCameraIndexChanged)
    Q_PROPERTY(
        QVariantList previewResolutions READ previewResolutions NOTIFY currentCameraIndexChanged)
    // An empty size leaves the choice to the camera backend.
    Q_PROPERTY(QSize viewfinderResolution READ viewfinderResolution WRITE setViewfinderResolution
                   NOTIFY viewfinderResolutionChanged)

    Q_PROPERTY(qreal zoomLevel READ zoomLevel WRITE setZoomLevel NOTIFY zoomLevelChanged)
    Q_PROPERTY(qreal maxZoom READ maxZoom NOTIFY zoomRangeChanged)

    Q_PROPERTY(bool flashEnabled READ flashEnabled WRITE setFlashEnabled NOTIFY flashEnabledChanged)
    Q_PROPERTY(bool flashAvailable READ flashAvailable NOTIFY flashAvailableChanged)

    Q_PROPERTY(QVariantList photoResolutions READ photoResolutions NOTIFY photoResolutionsChanged)
    Q_PROPERTY(QSize photoResolution READ photoResolution WRITE setPhotoResolution NOTIFY
                   photoResolutionChanged)

    Q_PROPERTY(bool isRecording READ isRecording NOTIFY recordingChanged)

  public:
    explicit CameraController(QObject *parent = nullptr);
    ~CameraController() override;

    QObject     *videoSink() const;
    void         setVideoSink(QObject *sink);

    bool         isDiscovered() const;
    bool         isActive() const;
    int          cameraCount() const;
    QVariantList cameras() const;
    QString      defaultCameraId() const;
    QString      cameraId() const;
    void         setCameraId(const QString &id);
    QVariantList previewResolutions() const;
    QSize        viewfinderResolution() const;
    void         setViewfinderResolution(const QSize &size);

    qreal        zoomLevel() const;
    void         setZoomLevel(qreal level);
    qreal        maxZoom() const;

    bool         flashEnabled() const;
    void         setFlashEnabled(bool enabled);
    bool         flashAvailable() const;

    QVariantList photoResolutions() const;
    QSize        photoResolution() const;
    void         setPhotoResolution(const QSize &size);

    bool         isRecording() const;

    // Enumerates the cameras without starting one.
    Q_INVOKABLE void discover();
    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();
    // Paths come from Captures (crates/marathon-app-native/src/camera.rs).
    // rotation: clockwise degrees that stand the photo upright.
    Q_INVOKABLE void capturePhoto(const QString &path, int rotation);
    Q_INVOKABLE void startRecording(const QString &path, const QString &posterPath);
    Q_INVOKABLE void stopRecording();
    Q_INVOKABLE void focusOnPoint(qreal x, qreal y);

  signals:
    void videoSinkChanged();
    void readyChanged();
    void activeChanged();
    void cameraCountChanged();
    void currentCameraIndexChanged();
    void viewfinderResolutionChanged();
    void zoomLevelChanged();
    void zoomRangeChanged();
    void flashEnabledChanged();
    void flashAvailableChanged();
    void photoResolutionsChanged();
    void photoResolutionChanged();
    void recordingChanged();
    void errorOccurred(const QString &message);
    void photoExposed();
    void photoSaved(const QString &url);
    void videoSaved(const QString &url);

  private slots:
    void onCameraActiveChanged(bool active);
    void onCameraErrorOccurred(QCamera::Error error, const QString &errorString);
    void onImageCaptured(int id, const QImage &image);
    void onImageError(int id, QImageCapture::Error error, const QString &errorString);
    void onRecorderStateChanged(QMediaRecorder::RecorderState state);
    void onRecorderError(QMediaRecorder::Error error, const QString &errorString);

  private:
    void                  initialize();
    void                  setupCamera(int index);
    void                  updateZoomRange();
    int                   indexOfCamera(const QString &id) const;
    QCameraFormat         fastestFormat(const QSize &size) const;
    void                  applyViewfinderResolution();
    void                  checkFrames();
    void                  takeStill(const QVideoFrame &frame);
    void                  cancelStill();
    void                  savePhoto(const QImage &image, const QString &fileName, int rotation);

    QCamera              *m_camera         = nullptr;
    QMediaCaptureSession *m_captureSession = nullptr;
    QImageCapture        *m_imageCapture   = nullptr;
    QMediaRecorder       *m_mediaRecorder  = nullptr;
    QVideoSink           *m_videoSink      = nullptr;

    QList<QCameraDevice>  m_cameras;
    int                   m_currentCameraIndex = 0;
    QString               m_cameraId;
    bool                  m_discovered = false;

    qreal                 m_zoomLevel = 1.0;
    qreal                 m_minZoom   = 1.0;
    qreal                 m_maxZoom   = 1.0;

    bool                  m_flashEnabled = false;

    QList<QSize>          m_photoResolutions;
    QSize                 m_photoResolution;
    QSize                 m_viewfinderResolution;

    QHash<int, std::pair<QString, int>> m_photoPaths;

    // A photo larger than the viewfinder: its path and rotation, the format
    // to go back to, and the frames left before it is taken.
    std::pair<QString, int> m_still;
    QCameraFormat           m_viewfinderFormat;
    std::atomic<int>        m_stillFrames{0};

    QImage                  m_recordingPoster;
    QString                 m_posterPath;
    QString                 m_errorMessage;

    // Frames since start, counted on the delivering thread.
    std::atomic<quint64> m_frames{0};
    quint64              m_framesAtStart = 0;
    QTimer               m_frameWatch;
    int                  m_restarts = 0;
};
