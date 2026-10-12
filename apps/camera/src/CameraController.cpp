#include "CameraController.h"
#include <QDateTime>
#include <algorithm>
#include <QDebug>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QElapsedTimer>
#include <QFutureWatcher>
#include <QMediaDevices>
#include <QtConcurrent/QtConcurrentRun>
#include <QStandardPaths>

namespace {
    QtMessageHandler originalHandler = nullptr;

    QString          posterPath(const QString &video) {
        return QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + "/posters/" +
            QFileInfo(video).completeBaseName() + ".jpg";
    }

    void             cameraMessageHandler(QtMsgType type, const QMessageLogContext &context,
                                          const QString &msg) {
        if (msg.contains("V4L2_MEMORY_USERPTR") || msg.contains("memorytransfer")) {
            return;
        }
        if (originalHandler) {
            originalHandler(type, context, msg);
        }
    }
}

CameraController::CameraController(QObject *parent)
    : QObject(parent)
    , m_countdownTimer(new QTimer(this))
    , m_recordingTimer(new QTimer(this)) {

    if (!originalHandler) {
        originalHandler = qInstallMessageHandler(cameraMessageHandler);
    }

    m_savePath = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation) + "/Marathon";

    m_countdownTimer->setInterval(1000);
    connect(m_countdownTimer, &QTimer::timeout, this, &CameraController::onTimerTick);

    m_recordingTimer->setInterval(1000);
    connect(m_recordingTimer, &QTimer::timeout, this, &CameraController::onRecordingTick);
}

CameraController::~CameraController() {
    stop();
}

// Loading the multimedia backend and enumerating cameras are slow, so they wait for start().
void CameraController::initialize() {
    if (m_discovered)
        return;

    QElapsedTimer clock;
    clock.start();

    m_captureSession = new QMediaCaptureSession(this);
    m_imageCapture   = new QImageCapture(this);
    m_mediaRecorder  = new QMediaRecorder(this);
    m_captureSession->setImageCapture(m_imageCapture);
    m_captureSession->setRecorder(m_mediaRecorder);
    m_captureSession->setVideoOutput(m_videoSink);

    connect(m_imageCapture, &QImageCapture::imageSaved, this, &CameraController::onImageSaved);
    connect(m_imageCapture, &QImageCapture::errorOccurred, this, &CameraController::onImageError);
    connect(m_mediaRecorder, &QMediaRecorder::recorderStateChanged, this,
            &CameraController::onRecorderStateChanged);
    connect(m_mediaRecorder, &QMediaRecorder::errorOccurred, this,
            &CameraController::onRecorderError);

    QDir().mkpath(m_savePath);
    m_cameras    = QMediaDevices::videoInputs();
    m_discovered = true;
    qWarning() << "[CameraController] Found" << m_cameras.size() << "cameras in"
               << clock.elapsed() << "ms";

    emit cameraCountChanged();
    emit currentCameraIndexChanged();
    emit readyChanged();

    scanForLatestCapture();
}

void CameraController::setupCamera(int index) {
    if (index < 0 || index >= m_cameras.size())
        return;

    if (m_camera) {
        m_camera->stop();
        delete m_camera;
        m_camera = nullptr;
    }

    m_camera = new QCamera(m_cameras.at(index), this);
    m_captureSession->setCamera(m_camera);

    connect(m_camera, &QCamera::activeChanged, this, &CameraController::onCameraActiveChanged);
    connect(m_camera, &QCamera::errorOccurred, this, &CameraController::onCameraErrorOccurred);

    m_currentCameraIndex = index;
    emit currentCameraIndexChanged();

    updateZoomRange();

    m_photoResolutions = m_cameras.at(index).photoResolutions();
    std::sort(m_photoResolutions.begin(), m_photoResolutions.end(),
              [](const QSize &a, const QSize &b) {
                  return a.width() * a.height() > b.width() * b.height();
              });
    emit photoResolutionsChanged();
    if (!m_photoResolutions.contains(m_photoResolution)) {
        m_photoResolution = QSize();
        emit photoResolutionChanged();
    }
    m_imageCapture->setResolution(m_photoResolution);

    qWarning() << "[CameraController] Using camera:" << m_cameras.at(index).description();
}

void CameraController::start() {
    initialize();
    if (m_cameras.isEmpty()) {
        m_errorMessage = "No cameras available";
        emit errorOccurred(m_errorMessage);
        return;
    }

    if (!m_camera) {
        setupCamera(0);
    }

    if (m_camera) {
        m_camera->start();
    }
}

void CameraController::stop() {
    if (m_camera) {
        m_camera->stop();
    }
    cancelTimer();
    m_recordingTimer->stop();
}

void CameraController::flipCamera() {
    if (m_cameras.size() < 2) {
        emit cameraFlipStarted();
        QTimer::singleShot(150, this, [this]() { emit cameraFlipCompleted(); });
        return;
    }

    emit cameraFlipStarted();

    int  nextIndex = (m_currentCameraIndex + 1) % m_cameras.size();

    QTimer::singleShot(150, this, [this, nextIndex]() {
        setupCamera(nextIndex);
        if (m_camera) {
            m_camera->start();
        }
        emit cameraFlipCompleted();
    });
}

void CameraController::capturePhoto() {
    if (!m_imageCapture || !m_camera || !m_camera->isActive()) {
        m_errorMessage = "Camera not ready";
        emit errorOccurred(m_errorMessage);
        return;
    }

    QString filePath = generateFilePath("IMG", "jpg");
    m_imageCapture->captureToFile(filePath);
}

void CameraController::captureWithTimer() {
    if (m_timerDuration <= 0) {
        capturePhoto();
        return;
    }

    m_timerCountdown = m_timerDuration;
    emit timerCountdownChanged();
    emit timerActiveChanged();
    m_countdownTimer->start();
}

void CameraController::cancelTimer() {
    if (!m_countdownTimer->isActive())
        return;
    m_countdownTimer->stop();
    m_timerCountdown = 0;
    emit timerCountdownChanged();
    emit timerActiveChanged();
}

void CameraController::startRecording() {
    if (!m_mediaRecorder || !m_camera || !m_camera->isActive()) {
        m_errorMessage = "Camera not ready for recording";
        emit errorOccurred(m_errorMessage);
        return;
    }

    QString filePath = generateFilePath("VID", "mp4");
    m_mediaRecorder->setOutputLocation(QUrl::fromLocalFile(filePath));
    m_mediaRecorder->record();
}

void CameraController::stopRecording() {
    if (m_mediaRecorder) {
        m_mediaRecorder->stop();
    }
}

void CameraController::focusOnPoint(qreal x, qreal y) {
    if (!m_camera)
        return;

    QPointF point(x, y);
    m_camera->setCustomFocusPoint(point);
    if (m_camera->isFocusModeSupported(QCamera::FocusModeAutoNear)) {
        m_camera->setFocusMode(QCamera::FocusModeAutoNear);
    }
}

QObject *CameraController::videoSink() const {
    return m_videoSink;
}

void CameraController::setVideoSink(QObject *sink) {
    auto *videoSink = qobject_cast<QVideoSink *>(sink);
    if (m_videoSink == videoSink)
        return;

    m_videoSink = videoSink;
    if (m_captureSession)
        m_captureSession->setVideoOutput(m_videoSink);
    emit videoSinkChanged();
}

bool CameraController::isDiscovered() const {
    return m_discovered;
}

bool CameraController::isReady() const {
    return !m_cameras.isEmpty();
}

bool CameraController::isActive() const {
    return m_camera && m_camera->isActive();
}

int CameraController::cameraCount() const {
    return m_cameras.size();
}

int CameraController::currentCameraIndex() const {
    return m_currentCameraIndex;
}

QString CameraController::currentCameraName() const {
    if (m_currentCameraIndex >= 0 && m_currentCameraIndex < m_cameras.size()) {
        return m_cameras.at(m_currentCameraIndex).description();
    }
    return QString();
}

bool CameraController::isFrontCamera() const {
    if (m_currentCameraIndex >= 0 && m_currentCameraIndex < m_cameras.size()) {
        return m_cameras.at(m_currentCameraIndex).position() == QCameraDevice::FrontFace;
    }
    return false;
}

qreal CameraController::zoomLevel() const {
    return m_zoomLevel;
}

void CameraController::setZoomLevel(qreal level) {
    level = qBound(m_minZoom, level, m_maxZoom);
    if (qFuzzyCompare(m_zoomLevel, level))
        return;

    m_zoomLevel = level;
    if (m_camera) {
        m_camera->setZoomFactor(m_zoomLevel);
    }
    emit zoomLevelChanged();
}

qreal CameraController::minZoom() const {
    return m_minZoom;
}

qreal CameraController::maxZoom() const {
    return m_maxZoom;
}

void CameraController::updateZoomRange() {
    if (m_camera) {
        m_minZoom   = m_camera->minimumZoomFactor();
        m_maxZoom   = m_camera->maximumZoomFactor();
        m_zoomLevel = qBound(m_minZoom, m_zoomLevel, m_maxZoom);
        emit zoomRangeChanged();
        emit zoomLevelChanged();
    }
}

bool CameraController::flashEnabled() const {
    return m_flashEnabled;
}

void CameraController::setFlashEnabled(bool enabled) {
    if (m_flashEnabled == enabled)
        return;

    m_flashEnabled = enabled;
    if (m_camera) {
        m_camera->setFlashMode(m_flashEnabled ? QCamera::FlashOn : QCamera::FlashOff);
    }
    emit flashEnabledChanged();
}

bool CameraController::flashAvailable() const {
    return m_camera && m_camera->isFlashModeSupported(QCamera::FlashOn);
}

QVariantList CameraController::photoResolutions() const {
    QVariantList list;
    for (const QSize &size : m_photoResolutions)
        list.append(size);
    return list;
}

QSize CameraController::photoResolution() const {
    return m_photoResolution;
}

// An empty size leaves the choice to the camera backend.
void CameraController::setPhotoResolution(const QSize &size) {
    if (m_photoResolution == size || (size.isValid() && !m_photoResolutions.contains(size)))
        return;

    m_photoResolution = size;
    if (m_imageCapture)
        m_imageCapture->setResolution(m_photoResolution);
    emit photoResolutionChanged();
}

int CameraController::timerDuration() const {
    return m_timerDuration;
}

void CameraController::setTimerDuration(int seconds) {
    if (m_timerDuration == seconds)
        return;

    m_timerDuration = seconds;
    emit timerDurationChanged();
}

int CameraController::timerCountdown() const {
    return m_timerCountdown;
}

bool CameraController::timerActive() const {
    return m_countdownTimer->isActive();
}

bool CameraController::isRecording() const {
    return m_mediaRecorder && m_mediaRecorder->recorderState() == QMediaRecorder::RecordingState;
}

int CameraController::recordingDuration() const {
    return m_recordingDuration;
}

QString CameraController::latestCapture() const {
    return m_latestCapture;
}

QString CameraController::latestPreview() const {
    return m_latestPreview;
}

void CameraController::setLatestCapture(const QString &file, const QString &preview) {
    m_latestCapture = QUrl::fromLocalFile(file).toString();
    m_latestPreview = preview.isEmpty() ? QString() : QUrl::fromLocalFile(preview).toString();
    emit latestCaptureChanged();
}

QString CameraController::errorMessage() const {
    return m_errorMessage;
}

void CameraController::onCameraActiveChanged(bool active) {
    emit activeChanged();
    if (active) {
        updateZoomRange();
        emit flashAvailableChanged();
    }
}

void CameraController::onCameraErrorOccurred(QCamera::Error error, const QString &errorString) {
    Q_UNUSED(error)
    m_errorMessage = errorString;
    emit errorOccurred(m_errorMessage);
    qWarning() << "[CameraController] Camera error:" << errorString;
}

void CameraController::onImageSaved(int id, const QString &fileName) {
    Q_UNUSED(id)
    qWarning() << "[CameraController] Photo saved:" << fileName;
    setLatestCapture(fileName, fileName);
    emit photoSaved(m_latestCapture);
}

void CameraController::onImageError(int id, QImageCapture::Error error,
                                    const QString &errorString) {
    Q_UNUSED(id)
    Q_UNUSED(error)
    m_errorMessage = errorString;
    emit errorOccurred(m_errorMessage);
    qWarning() << "[CameraController] Capture error:" << errorString;
}

void CameraController::onRecorderStateChanged(QMediaRecorder::RecorderState state) {
    emit recordingChanged();

    if (state == QMediaRecorder::RecordingState) {
        m_recordingDuration = 0;
        m_recordingTimer->start();
        if (m_videoSink)
            m_recordingPoster = m_videoSink->videoFrame().toImage().scaled(
                512, 512, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    } else {
        m_recordingTimer->stop();
        if (state == QMediaRecorder::StoppedState) {
            m_recordingDuration = 0;
            emit recordingDurationChanged();

            const QString video = m_mediaRecorder->actualLocation().toLocalFile();
            if (QFileInfo::exists(video)) {
                const QString poster = posterPath(video);
                QDir().mkpath(QFileInfo(poster).path());
                const bool saved = !m_recordingPoster.isNull() && m_recordingPoster.save(poster);
                setLatestCapture(video, saved ? poster : QString());
            }
            m_recordingPoster = QImage();
        }
    }
}

void CameraController::onRecorderError(QMediaRecorder::Error error, const QString &errorString) {
    Q_UNUSED(error)
    m_errorMessage = errorString;
    emit errorOccurred(m_errorMessage);
    qWarning() << "[CameraController] Recording error:" << errorString;
}

void CameraController::onTimerTick() {
    m_timerCountdown--;
    emit timerCountdownChanged();

    if (m_timerCountdown <= 0) {
        m_countdownTimer->stop();
        emit timerActiveChanged();
        capturePhoto();
    }
}

void CameraController::onRecordingTick() {
    m_recordingDuration++;
    emit recordingDurationChanged();
}

QString CameraController::generateFilePath(const QString &prefix, const QString &extension) {
    QString timestamp = QString::number(QDateTime::currentMSecsSinceEpoch());
    return m_savePath + "/" + prefix + "_" + timestamp + "." + extension;
}

// Runs off the GUI thread and keeps only the newest file instead of sorting the folder.
void CameraController::scanForLatestCapture() {
    using Capture = std::pair<QString, QString>;
    auto *watcher = new QFutureWatcher<Capture>(this);
    connect(watcher, &QFutureWatcher<Capture>::finished, this, [this, watcher]() {
        const Capture latest = watcher->result();
        watcher->deleteLater();
        if (!latest.first.isEmpty() && m_latestCapture.isEmpty())
            setLatestCapture(latest.first, latest.second);
    });
    watcher->setFuture(QtConcurrent::run([dir = m_savePath]() {
        QDirIterator it(dir, {"*.jpg", "*.jpeg", "*.png", "*.mp4"}, QDir::Files);
        QString      newest;
        QDateTime    newestTime;
        while (it.hasNext()) {
            const QFileInfo info = it.nextFileInfo();
            if (newest.isEmpty() || info.lastModified() > newestTime) {
                newest     = info.absoluteFilePath();
                newestTime = info.lastModified();
            }
        }
        if (!newest.endsWith(".mp4"))
            return Capture(newest, newest);
        const QString poster = posterPath(newest);
        return Capture(newest, QFileInfo::exists(poster) ? poster : QString());
    }));
}
