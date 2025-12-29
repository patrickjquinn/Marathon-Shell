#pragma once

#include <QObject>
#include <QCamera>
#include <QMediaCaptureSession>
#include <QMediaDevices>
#include <QImageCapture>
#include <QMediaRecorder>
#include <QVideoSink>
#include <QUrl>
#include <QTimer>
#include <QtQmlIntegration>

class CameraController : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QVideoSink *videoSink READ videoSink WRITE setVideoSink NOTIFY videoSinkChanged)
    Q_PROPERTY(bool ready READ isReady NOTIFY readyChanged)
    Q_PROPERTY(bool active READ isActive NOTIFY activeChanged)
    Q_PROPERTY(int cameraCount READ cameraCount NOTIFY cameraCountChanged)
    Q_PROPERTY(int currentCameraIndex READ currentCameraIndex NOTIFY currentCameraIndexChanged)
    Q_PROPERTY(QString currentCameraName READ currentCameraName NOTIFY currentCameraIndexChanged)
    Q_PROPERTY(bool isFrontCamera READ isFrontCamera NOTIFY currentCameraIndexChanged)

    Q_PROPERTY(qreal zoomLevel READ zoomLevel WRITE setZoomLevel NOTIFY zoomLevelChanged)
    Q_PROPERTY(qreal minZoom READ minZoom NOTIFY zoomRangeChanged)
    Q_PROPERTY(qreal maxZoom READ maxZoom NOTIFY zoomRangeChanged)

    Q_PROPERTY(bool flashEnabled READ flashEnabled WRITE setFlashEnabled NOTIFY flashEnabledChanged)
    Q_PROPERTY(bool flashAvailable READ flashAvailable NOTIFY flashAvailableChanged)

    Q_PROPERTY(
        int timerDuration READ timerDuration WRITE setTimerDuration NOTIFY timerDurationChanged)
    Q_PROPERTY(int timerCountdown READ timerCountdown NOTIFY timerCountdownChanged)
    Q_PROPERTY(bool timerActive READ timerActive NOTIFY timerActiveChanged)

    Q_PROPERTY(bool isRecording READ isRecording NOTIFY recordingChanged)
    Q_PROPERTY(int recordingDuration READ recordingDuration NOTIFY recordingDurationChanged)

    Q_PROPERTY(QString savePath READ savePath WRITE setSavePath NOTIFY savePathChanged)
    Q_PROPERTY(QString latestPhotoPath READ latestPhotoPath NOTIFY latestPhotoPathChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorOccurred)

  public:
    explicit CameraController(QObject *parent = nullptr);
    ~CameraController() override;

    QVideoSink      *videoSink() const;
    void             setVideoSink(QVideoSink *sink);

    bool             isReady() const;
    bool             isActive() const;
    int              cameraCount() const;
    int              currentCameraIndex() const;
    QString          currentCameraName() const;
    bool             isFrontCamera() const;

    qreal            zoomLevel() const;
    void             setZoomLevel(qreal level);
    qreal            minZoom() const;
    qreal            maxZoom() const;

    bool             flashEnabled() const;
    void             setFlashEnabled(bool enabled);
    bool             flashAvailable() const;

    int              timerDuration() const;
    void             setTimerDuration(int seconds);
    int              timerCountdown() const;
    bool             timerActive() const;

    bool             isRecording() const;
    int              recordingDuration() const;

    QString          savePath() const;
    void             setSavePath(const QString &path);
    QString          latestPhotoPath() const;
    QString          errorMessage() const;

    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void flipCamera();
    Q_INVOKABLE void capturePhoto();
    Q_INVOKABLE void captureWithTimer();
    Q_INVOKABLE void startRecording();
    Q_INVOKABLE void stopRecording();
    Q_INVOKABLE void focusOnPoint(qreal x, qreal y);

  signals:
    void videoSinkChanged();
    void readyChanged();
    void activeChanged();
    void cameraCountChanged();
    void currentCameraIndexChanged();
    void zoomLevelChanged();
    void zoomRangeChanged();
    void flashEnabledChanged();
    void flashAvailableChanged();
    void timerDurationChanged();
    void timerCountdownChanged();
    void timerActiveChanged();
    void recordingChanged();
    void recordingDurationChanged();
    void savePathChanged();
    void latestPhotoPathChanged();
    void errorOccurred(const QString &message);
    void photoSaved(const QString &path);
    void cameraFlipStarted();
    void cameraFlipCompleted();

  private slots:
    void onCameraActiveChanged(bool active);
    void onCameraErrorOccurred(QCamera::Error error, const QString &errorString);
    void onImageSaved(int id, const QString &fileName);
    void onImageError(int id, QImageCapture::Error error, const QString &errorString);
    void onRecorderStateChanged(QMediaRecorder::RecorderState state);
    void onRecorderError(QMediaRecorder::Error error, const QString &errorString);
    void onTimerTick();
    void onRecordingTick();

  private:
    void                  initializeCameras();
    void                  setupCamera(int index);
    void                  updateZoomRange();
    QString               generateFilePath(const QString &prefix, const QString &extension);
    void                  scanForLatestPhoto();

    QMediaDevices        *m_mediaDevices   = nullptr;
    QCamera              *m_camera         = nullptr;
    QMediaCaptureSession *m_captureSession = nullptr;
    QImageCapture        *m_imageCapture   = nullptr;
    QMediaRecorder       *m_mediaRecorder  = nullptr;
    QVideoSink           *m_videoSink      = nullptr;

    QList<QCameraDevice>  m_cameras;
    int                   m_currentCameraIndex = 0;
    bool                  m_ready              = false;

    qreal                 m_zoomLevel = 1.0;
    qreal                 m_minZoom   = 1.0;
    qreal                 m_maxZoom   = 1.0;

    bool                  m_flashEnabled = false;

    int                   m_timerDuration  = 0;
    int                   m_timerCountdown = 0;
    QTimer               *m_countdownTimer = nullptr;

    int                   m_recordingDuration = 0;
    QTimer               *m_recordingTimer    = nullptr;

    QString               m_savePath;
    QString               m_latestPhotoPath;
    QString               m_errorMessage;
};
