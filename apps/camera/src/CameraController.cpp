#include "CameraController.h"
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QStandardPaths>

namespace {
    static QtMessageHandler originalHandler = nullptr;

    void                    cameraMessageHandler(QtMsgType type, const QMessageLogContext &context,
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
    , m_mediaDevices(new QMediaDevices(this))
    , m_captureSession(new QMediaCaptureSession(this))
    , m_imageCapture(new QImageCapture(this))
    , m_mediaRecorder(new QMediaRecorder(this))
    , m_countdownTimer(new QTimer(this))
    , m_recordingTimer(new QTimer(this)) {

    if (!originalHandler) {
        originalHandler = qInstallMessageHandler(cameraMessageHandler);
    }

    m_savePath = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation) + "/Marathon";
    QDir().mkpath(m_savePath);

    m_captureSession->setImageCapture(m_imageCapture);
    m_captureSession->setRecorder(m_mediaRecorder);

    connect(m_imageCapture, &QImageCapture::imageSaved, this, &CameraController::onImageSaved);
    connect(m_imageCapture, &QImageCapture::errorOccurred, this, &CameraController::onImageError);
    connect(m_mediaRecorder, &QMediaRecorder::recorderStateChanged, this,
            &CameraController::onRecorderStateChanged);
    connect(m_mediaRecorder, &QMediaRecorder::errorOccurred, this,
            &CameraController::onRecorderError);

    m_countdownTimer->setInterval(1000);
    connect(m_countdownTimer, &QTimer::timeout, this, &CameraController::onTimerTick);

    m_recordingTimer->setInterval(1000);
    connect(m_recordingTimer, &QTimer::timeout, this, &CameraController::onRecordingTick);

    initializeCameras();
    scanForLatestPhoto();
}

CameraController::~CameraController() {
    stop();
}

void CameraController::initializeCameras() {
    m_cameras = QMediaDevices::videoInputs();
    qWarning() << "[CameraController] Found" << m_cameras.size() << "cameras";

    emit cameraCountChanged();

    if (!m_cameras.isEmpty()) {
        m_ready = true;
        emit readyChanged();
    }
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

    qWarning() << "[CameraController] Using camera:" << m_cameras.at(index).description();
}

void CameraController::start() {
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
    m_countdownTimer->stop();
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
    m_captureSession->setVideoOutput(m_videoSink);
    emit videoSinkChanged();
}

bool CameraController::isReady() const {
    return m_ready;
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

QString CameraController::savePath() const {
    return m_savePath;
}

void CameraController::setSavePath(const QString &path) {
    if (m_savePath == path)
        return;

    m_savePath = path;
    QDir().mkpath(m_savePath);
    emit savePathChanged();
    scanForLatestPhoto();
}

QString CameraController::latestPhotoPath() const {
    return m_latestPhotoPath;
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
    m_latestPhotoPath = "file://" + fileName;
    emit latestPhotoPathChanged();
    emit photoSaved(m_latestPhotoPath);
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
    } else {
        m_recordingTimer->stop();
        if (state == QMediaRecorder::StoppedState) {
            m_recordingDuration = 0;
            emit recordingDurationChanged();
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

void CameraController::scanForLatestPhoto() {
    QDir        dir(m_savePath);
    QStringList filters;
    filters << "*.jpg" << "*.jpeg" << "*.png";

    QFileInfoList files = dir.entryInfoList(filters, QDir::Files, QDir::Time);

    if (!files.isEmpty()) {
        m_latestPhotoPath = "file://" + files.first().absoluteFilePath();
        emit latestPhotoPathChanged();
    }
}
