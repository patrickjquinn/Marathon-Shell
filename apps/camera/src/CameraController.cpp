#include "CameraController.h"
#include <algorithm>
#include <QCoreApplication>
#include <QDebug>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QImageWriter>
#include <QMediaDevices>
#include <QMediaFormat>
#include <QPointer>
#include <QThreadPool>
#include <QtEndian>
#include <utility>
#include "SoftwareVideoOutput.h"

namespace {
    QtMessageHandler originalHandler = nullptr;
    // The software ISP's exposure starts again with each configuration.
    constexpr int kStillSettleFrames = 8;

    void          cameraMessageHandler(QtMsgType type, const QMessageLogContext &context,
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
    m_frameWatch.setSingleShot(true);
    m_frameWatch.setInterval(4000);
    connect(&m_frameWatch, &QTimer::timeout, this, &CameraController::checkFrames);
}

CameraController::~CameraController() {
    if (m_videoSink)
        disconnect(m_videoSink, nullptr, this, nullptr);
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
    // H.264 keeps up with the camera on a phone's CPU; Qt's default, HEVC, does not.
    QMediaFormat format(QMediaFormat::MPEG4);
    format.setVideoCodec(QMediaFormat::VideoCodec::H264);
    m_mediaRecorder->setMediaFormat(format);
    m_captureSession->setImageCapture(m_imageCapture);
    m_captureSession->setRecorder(m_mediaRecorder);
    m_captureSession->setVideoOutput(m_videoSink);

    connect(m_imageCapture, &QImageCapture::imageExposed, this, &CameraController::photoExposed);
    connect(m_imageCapture, &QImageCapture::imageCaptured, this,
            &CameraController::onImageCaptured);
    connect(m_imageCapture, &QImageCapture::errorOccurred, this, &CameraController::onImageError);
    connect(m_mediaRecorder, &QMediaRecorder::recorderStateChanged, this,
            &CameraController::onRecorderStateChanged);
    connect(m_mediaRecorder, &QMediaRecorder::errorOccurred, this,
            &CameraController::onRecorderError);

    m_cameras    = QMediaDevices::videoInputs();
    m_discovered = true;
    qWarning() << "[CameraController] Found" << m_cameras.size() << "cameras in" << clock.elapsed()
               << "ms";

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
    m_camera->setFlashMode(m_flashEnabled ? QCamera::FlashOn : QCamera::FlashOff);

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
    applyViewfinderResolution();

    qWarning() << "[CameraController] Using camera:" << m_cameras.at(index).description();
}

void CameraController::discover() {
    initialize();
}

void CameraController::start() {
    initialize();
    if (m_cameras.isEmpty()) {
        m_errorMessage = "No cameras available";
        emit errorOccurred(m_errorMessage);
        return;
    }

    if (!m_camera) {
        setupCamera(std::max(0, indexOfCamera(m_cameraId)));
    }

    if (m_camera) {
        m_camera->start();
    }
}

void CameraController::stop() {
    if (m_camera) {
        m_camera->stop();
        cancelStill();
    }
}

void CameraController::capturePhoto(const QString &path, int rotation) {
    if (!m_imageCapture || !m_camera || !m_camera->isActive() || m_stillFrames > 0) {
        m_errorMessage = "Camera not ready";
        emit errorOccurred(m_errorMessage);
        return;
    }

    // Qt's capture is the viewfinder's frame: a larger photo takes a frame
    // of its own format.
    const QCameraFormat still = fastestFormat(m_photoResolution);
    if (!still.isNull() && still.resolution() != m_camera->cameraFormat().resolution()) {
        m_still            = {path, rotation};
        m_viewfinderFormat = m_camera->cameraFormat();
        m_stillFrames      = kStillSettleFrames;
        m_camera->stop();
        m_camera->setCameraFormat(still);
        m_camera->start();
        return;
    }

    // Qt 6.11's GStreamer captureToFile() writes the frame before jpegenc: raw pixels.
    const int id = m_imageCapture->capture();
    if (id >= 0)
        m_photoPaths.insert(id, {path, rotation});
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

    if (m_videoSink)
        disconnect(m_videoSink, nullptr, this, nullptr);
    m_videoSink = videoSink;
    if (m_videoSink)
        connect(
            m_videoSink, &QVideoSink::videoFrameChanged, this,
            [this](const QVideoFrame &frame) {
                ++m_frames;
                if (m_stillFrames > 0 && m_stillFrames.fetch_sub(1) == 1)
                    QMetaObject::invokeMethod(
                        this, [this, frame] { takeStill(frame); }, Qt::QueuedConnection);
            },
            Qt::DirectConnection);
    if (m_captureSession)
        m_captureSession->setVideoOutput(m_videoSink);
    emit videoSinkChanged();
}

bool CameraController::isDiscovered() const {
    return m_discovered;
}

bool CameraController::isActive() const {
    return m_camera && m_camera->isActive();
}

int CameraController::cameraCount() const {
    return m_cameras.size();
}

// Qt's GStreamer backend numbers libcamera's cameras in the order they turn up
// and leaves them unplaced. It describes each by libcamera's own id, a device
// tree path: a stable id, and the sensor node's orientation says which side.
static bool isDeviceTreeCamera(const QCameraDevice &device) {
    return device.description().startsWith("/base/");
}

static QString idOf(const QCameraDevice &device) {
    return isDeviceTreeCamera(device) ? device.description() : QString::fromUtf8(device.id());
}

// A cell of the sensor's device tree node, -1 without one.
static qint64 deviceTreeCell(const QCameraDevice &device, const char *property) {
    if (!isDeviceTreeCamera(device))
        return -1;
    QFile file("/sys/firmware/devicetree" + device.description() + "/" + property);
    if (!file.open(QIODevice::ReadOnly))
        return -1;
    const QByteArray value = file.read(4);
    return value.size() == 4 ? qFromBigEndian<quint32>(value.constData()) : -1;
}

static QCameraDevice::Position positionOf(const QCameraDevice &device) {
    if (device.position() != QCameraDevice::UnspecifiedPosition)
        return device.position();
    switch (deviceTreeCell(device, "orientation")) {
        case 0: return QCameraDevice::FrontFace;
        case 1: return QCameraDevice::BackFace;
        default: return QCameraDevice::UnspecifiedPosition;
    }
}

// How far its frames turn clockwise to stand upright on the screen.
static int rotationOf(const QCameraDevice &device) {
    if (device.correctionAngle() != QtVideo::Rotation::None)
        return int(device.correctionAngle());
    const qint64 rotation = deviceTreeCell(device, "rotation");
    return rotation > 0 ? int(rotation % 360) : 0;
}

QVariantList CameraController::cameras() const {
    QVariantList list;
    for (const QCameraDevice &device : m_cameras)
        list.append(QVariantMap{{"id", idOf(device)},
                                {"description", device.description()},
                                {"position", int(positionOf(device))},
                                {"rotation", rotationOf(device)}});
    return list;
}

QString CameraController::defaultCameraId() const {
    if (!m_discovered)
        return QString();
    return idOf(QMediaDevices::defaultVideoInput());
}

QString CameraController::cameraId() const {
    if (m_camera)
        return idOf(m_cameras.at(m_currentCameraIndex));
    return m_cameraId;
}

int CameraController::indexOfCamera(const QString &id) const {
    for (int i = 0; i < m_cameras.size(); ++i) {
        if (idOf(m_cameras.at(i)) == id)
            return i;
    }
    return -1;
}

// Before discovery the id waits for start(); after, a running camera switches.
void CameraController::setCameraId(const QString &id) {
    if (id == cameraId())
        return;
    m_cameraId      = id;
    const int index = indexOfCamera(id);
    if (!m_camera || index < 0) {
        emit currentCameraIndexChanged();
        return;
    }
    const bool running = m_camera->isActive();
    setupCamera(index);
    if (running && m_camera)
        m_camera->start();
}

QVariantList CameraController::previewResolutions() const {
    QList<QSize> sizes;
    if (m_currentCameraIndex >= 0 && m_currentCameraIndex < m_cameras.size()) {
        for (const QCameraFormat &format : m_cameras.at(m_currentCameraIndex).videoFormats()) {
            if (!sizes.contains(format.resolution()))
                sizes.append(format.resolution());
        }
    }
    std::sort(sizes.begin(), sizes.end(), [](const QSize &a, const QSize &b) {
        return a.width() * a.height() > b.width() * b.height();
    });
    QVariantList list;
    for (const QSize &size : sizes)
        list.append(size);
    return list;
}

QSize CameraController::viewfinderResolution() const {
    return m_viewfinderResolution;
}

void CameraController::setViewfinderResolution(const QSize &size) {
    if (m_viewfinderResolution == size)
        return;
    m_viewfinderResolution = size;
    applyViewfinderResolution();
    emit viewfinderResolutionChanged();
}

// The fastest format at a resolution.
QCameraFormat CameraController::fastestFormat(const QSize &size) const {
    QCameraFormat best;
    if (!m_camera || !size.isValid())
        return best;
    for (const QCameraFormat &format : m_camera->cameraDevice().videoFormats()) {
        if (format.resolution() == size &&
            (best.isNull() || format.maxFrameRate() > best.maxFrameRate()))
            best = format;
    }
    return best;
}

// libcamerasrc cannot renegotiate a running stream ("not-negotiated"), so a
// running camera stops for the change.
void CameraController::applyViewfinderResolution() {
    if (!m_camera)
        return;
    const QCameraFormat best = fastestFormat(m_viewfinderResolution);
    if (best == m_camera->cameraFormat())
        return;
    const bool running = m_camera->isActive();
    if (running)
        m_camera->stop();
    m_camera->setCameraFormat(best);
    if (running)
        m_camera->start();
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

qreal CameraController::maxZoom() const {
    return m_maxZoom;
}

void CameraController::updateZoomRange() {
    if (m_camera) {
        m_minZoom   = m_camera->minimumZoomFactor();
        m_maxZoom   = m_camera->maximumZoomFactor();
        m_zoomLevel = qBound(m_minZoom, m_zoomLevel, m_maxZoom);
        m_camera->setZoomFactor(m_zoomLevel);
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

    // Not Qt's: its capture branch has no scaler, and a size the viewfinder
    // does not have stops the camera ("not-negotiated").
    m_photoResolution = size;
    emit photoResolutionChanged();
}

bool CameraController::isRecording() const {
    return m_mediaRecorder && m_mediaRecorder->recorderState() == QMediaRecorder::RecordingState;
}

void CameraController::onCameraActiveChanged(bool active) {
    emit activeChanged();
    if (active) {
        updateZoomRange();
        emit flashAvailableChanged();
        m_framesAtStart = m_frames;
        m_frameWatch.start();
    } else {
        m_frameWatch.stop();
    }
}

// A camera that is active but sends nothing starts again, a few times. When
// libcamera's first frame is slow, Qt can give up taking the stream to
// PLAYING ("Could not finish change state"), and none ever comes.
void CameraController::checkFrames() {
    if (!m_camera || !m_camera->isActive())
        return;
    if (m_frames != m_framesAtStart) {
        m_restarts = 0;
        return;
    }
    if (++m_restarts > 3)
        return;
    qWarning() << "[CameraController] No frames: restarting the camera";
    m_camera->stop();
    QMetaObject::invokeMethod(
        this,
        [this] {
            if (m_camera)
                m_camera->start();
        },
        Qt::QueuedConnection);
}

void CameraController::onCameraErrorOccurred(QCamera::Error error, const QString &errorString) {
    Q_UNUSED(error)
    cancelStill();
    m_errorMessage = errorString;
    emit errorOccurred(m_errorMessage);
    qWarning() << "[CameraController] Camera error:" << errorString;
}

void CameraController::onImageCaptured(int id, const QImage &image) {
    const auto photo = m_photoPaths.take(id);
    if (!photo.first.isEmpty())
        savePhoto(image, photo.first, photo.second);
}

// The settled frame of a photo's own format; the viewfinder's comes back.
void CameraController::takeStill(const QVideoFrame &frame) {
    const auto [fileName, rotation] = std::exchange(m_still, {});
    if (!m_camera || fileName.isEmpty())
        return;
    // A copy: the frame's buffer goes with the format.
    const QImage image = imageOf(frame);
    emit         photoExposed();
    m_camera->stop();
    m_camera->setCameraFormat(m_viewfinderFormat);
    m_camera->start();
    if (image.isNull()) {
        onImageError(-1, QImageCapture::ResourceError, "Could not read the photo's frame");
        return;
    }
    savePhoto(image, fileName, rotation);
}

void CameraController::cancelStill() {
    if (std::exchange(m_still, {}).first.isEmpty())
        return;
    m_stillFrames = 0;
    if (m_camera)
        m_camera->setCameraFormat(m_viewfinderFormat);
}

void CameraController::savePhoto(const QImage &image, const QString &fileName, int rotation) {
    QPointer<CameraController> self(this);
    QThreadPool::globalInstance()->start([self, image, fileName, rotation] {
        // Under another name until whole: the camera roll shows the folder.
        const QString part = fileName + ".part";
        QImageWriter  writer(part, "jpeg");
        writer.setQuality(92);
        bool saved =
            writer.write(rotation ? image.transformed(QTransform().rotate(rotation)) : image);
        const QString error = writer.errorString();
        if (saved)
            saved = QFile::rename(part, fileName);
        else
            QFile::remove(part);
        QMetaObject::invokeMethod(QCoreApplication::instance(), [self, saved, fileName, error] {
            if (!self)
                return;
            if (!saved) {
                self->onImageError(-1, QImageCapture::ResourceError, error);
                return;
            }
            qWarning() << "[CameraController] Photo saved:" << fileName;
            emit self->photoSaved(QUrl::fromLocalFile(fileName).toString());
        });
    });
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
