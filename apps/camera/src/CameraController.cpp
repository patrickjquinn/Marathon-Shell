#include "CameraController.h"
#include <algorithm>
#include <QDebug>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QMediaDevices>
#include <QTimer>

namespace {
    QtMessageHandler originalHandler = nullptr;

    void cameraMessageHandler(QtMsgType type, const QMessageLogContext &context,
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
    : QObject(parent) {
    if (!originalHandler) {
        originalHandler = qInstallMessageHandler(cameraMessageHandler);
    }
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

    connect(m_imageCapture, &QImageCapture::imageExposed, this, &CameraController::photoExposed);
    connect(m_imageCapture, &QImageCapture::imageSaved, this, &CameraController::onImageSaved);
    connect(m_imageCapture, &QImageCapture::errorOccurred, this, &CameraController::onImageError);
    connect(m_mediaRecorder, &QMediaRecorder::recorderStateChanged, this,
            &CameraController::onRecorderStateChanged);
    connect(m_mediaRecorder, &QMediaRecorder::errorOccurred, this,
            &CameraController::onRecorderError);

    m_cameras    = QMediaDevices::videoInputs();
    m_discovered = true;
    qWarning() << "[CameraController] Found" << m_cameras.size() << "cameras in"
               << clock.elapsed() << "ms";

    emit cameraCountChanged();
    emit currentCameraIndexChanged();
    emit readyChanged();
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
}

void CameraController::flipCamera() {
    if (m_cameras.size() < 2) {
        emit cameraFlipStarted();
        QTimer::singleShot(150, this, [this]() { emit cameraFlipCompleted(); });
        return;
    }

    emit cameraFlipStarted();

    int nextIndex = (m_currentCameraIndex + 1) % m_cameras.size();

    QTimer::singleShot(150, this, [this, nextIndex]() {
        setupCamera(nextIndex);
        if (m_camera) {
            m_camera->start();
        }
        emit cameraFlipCompleted();
    });
}

void CameraController::capturePhoto(const QString &path) {
    if (!m_imageCapture || !m_camera || !m_camera->isActive()) {
        m_errorMessage = "Camera not ready";
        emit errorOccurred(m_errorMessage);
        return;
    }

    m_imageCapture->captureToFile(path);
}

void CameraController::startRecording(const QString &path, const QString &posterPath) {
    if (!m_mediaRecorder || !m_camera || !m_camera->isActive()) {
        m_errorMessage = "Camera not ready for recording";
        emit errorOccurred(m_errorMessage);
        return;
    }

    m_posterPath = posterPath;
    m_mediaRecorder->setOutputLocation(QUrl::fromLocalFile(path));
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

bool CameraController::isRecording() const {
    return m_mediaRecorder && m_mediaRecorder->recorderState() == QMediaRecorder::RecordingState;
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
    emit photoSaved(QUrl::fromLocalFile(fileName).toString());
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
        if (m_videoSink)
            m_recordingPoster = m_videoSink->videoFrame().toImage().scaled(
                512, 512, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    } else if (state == QMediaRecorder::StoppedState) {
        const QString video = m_mediaRecorder->actualLocation().toLocalFile();
        if (QFileInfo::exists(video)) {
            if (!m_posterPath.isEmpty() && !m_recordingPoster.isNull())
                m_recordingPoster.save(m_posterPath);
            emit videoSaved(QUrl::fromLocalFile(video).toString());
        }
        m_recordingPoster = QImage();
        m_posterPath.clear();
    }
}

void CameraController::onRecorderError(QMediaRecorder::Error error, const QString &errorString) {
    Q_UNUSED(error)
    m_errorMessage = errorString;
    emit errorOccurred(m_errorMessage);
    qWarning() << "[CameraController] Recording error:" << errorString;
}
