#pragma once

#include <QElapsedTimer>
#include <QImage>
#include <QObject>
#include <QPointer>
#include <QSize>
#include <QThread>
#include <QVariantList>
#include <QtQmlIntegration/qqmlintegration.h>

#include "CameraSession.h"

class SoftwareVideoOutput;

class CameraController : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QObject *videoSink READ videoSink WRITE setVideoSink NOTIFY videoSinkChanged)
    Q_PROPERTY(bool discovered READ isDiscovered NOTIFY readyChanged)
    Q_PROPERTY(bool active READ isActive NOTIFY activeChanged)
    Q_PROPERTY(int cameraCount READ cameraCount NOTIFY cameraCountChanged)
    // Each camera as {id, description, position, rotation}; position as Qt's
    // QCameraDevice::Position.
    Q_PROPERTY(QVariantList cameras READ cameras NOTIFY cameraCountChanged)
    Q_PROPERTY(QString defaultCameraId READ defaultCameraId NOTIFY cameraCountChanged)
    // Empty for the first camera.
    Q_PROPERTY(QString cameraId READ cameraId WRITE setCameraId NOTIFY currentCameraIndexChanged)
    Q_PROPERTY(
        QVariantList previewResolutions READ previewResolutions NOTIFY currentCameraIndexChanged)
    // An empty size leaves the choice to libcamera.
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
    // The camera runs in a photo's format, whose frames are not the viewfinder's.
    Q_PROPERTY(bool takingStill READ takingStill NOTIFY takingStillChanged)
    // Photos keep only the square in the middle of the frame.
    Q_PROPERTY(bool squarePhotos MEMBER m_squarePhotos NOTIFY squarePhotosChanged)
    // The camera has a focus motor (a lens-focus link in the device tree).
    Q_PROPERTY(bool focusSupported READ focusSupported NOTIFY currentCameraIndexChanged)
    Q_PROPERTY(FocusState focusState READ focusState NOTIFY focusStateChanged)

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
    bool         takingStill() const;

    // Enumerates the cameras without starting one.
    Q_INVOKABLE void discover();
    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();
    // Stops and closes the camera and libcamera, so its devices close;
    // start() opens them again.
    Q_INVOKABLE void release();
    // Paths come from Captures (crates/marathon-app-native/src/camera.rs).
    // rotation: clockwise degrees that stand the photo upright.
    Q_INVOKABLE void capturePhoto(const QString &path, int rotation);
    // rotation: clockwise degrees that stand the video upright.
    Q_INVOKABLE void startRecording(const QString &path, const QString &posterPath, int rotation);
    Q_INVOKABLE void stopRecording();
    // A point of the frame, 0..1 each way: focus there and hold.
    Q_INVOKABLE void focusOnPoint(qreal x, qreal y);
    // Back to continuous focus over the whole frame.
    Q_INVOKABLE void unlockFocus();

  public:
    enum FocusState : quint8 { FocusUnlocked, FocusSearching, FocusLocked };
    Q_ENUM(FocusState)

    bool       focusSupported() const;
    FocusState focusState() const;

  signals:
    void focusStateChanged();
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
    void takingStillChanged();
    void squarePhotosChanged();
    void errorOccurred(const QString &message);
    void photoExposed();
    void photoSaved(const QString &url);
    void videoSaved(const QString &url);

  private:
    void                  want();
    QString               currentId() const;
    void                  onDiscovered(const QList<CameraInfo> &cameras);
    void                  onStreamingChanged(bool streaming);
    void                  onFrameReady();
    void                  onStillCaptured(const QImage &image);
    void                  onStillFinished();
    void                  onRecordingFinished(const QString &path, bool saved);
    void                  savePhoto(const QImage &image, const QString &fileName, int rotation);
    void                  setFocusState(FocusState state);
    void                  fail(const QString &message);

    QThread               m_thread;
    // Lives on m_thread.
    CameraSession        *m_session = nullptr;
    QPointer<SoftwareVideoOutput> m_videoSink;

    QList<CameraInfo>     m_cameras;
    int                   m_currentCameraIndex = 0;
    QString               m_cameraId;
    bool                  m_discovered  = false;
    bool                  m_discovering = false;
    bool                  m_wantStreaming = false;
    bool                  m_active      = false;

    qreal                 m_zoomLevel    = 1.0;
    bool                  m_flashEnabled = false;

    QSize                 m_photoResolution;
    QSize                 m_viewfinderResolution;

    // A photo being taken: its path and rotation.
    std::pair<QString, int> m_still;
    bool                    m_squarePhotos = false;
    // From the shutter to the photo's frame.
    QElapsedTimer           m_photoClock;

    FocusState              m_focusState = FocusUnlocked;

    bool                    m_recording = false;
    QImage                  m_recordingPoster;
    QString                 m_posterPath;
};
