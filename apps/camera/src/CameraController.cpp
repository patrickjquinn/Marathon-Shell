#include "CameraController.h"
#include <algorithm>
#include <QCoreApplication>
#include <QDebug>
#include <QFile>
#include <QFileInfo>
#include <QThreadPool>
#include <QUrl>
#include <QtEndian>
#include <turbojpeg.h>
#include <utility>
#include "SoftwareVideoOutput.h"

namespace {
    // QCameraDevice::Position's values, which the QML takes.
    enum Position : quint8 { UnspecifiedPosition, BackFace, FrontFace };

    // libcamera names a camera on a device tree by its sensor's node, whose
    // orientation says which side it faces.
    bool isDeviceTreeCamera(const QString &id) {
        return id.startsWith("/base/");
    }

    // A cell of the sensor's device tree node, -1 without one.
    qint64 deviceTreeCell(const QString &id, const char *property) {
        if (!isDeviceTreeCamera(id))
            return -1;
        QFile file("/sys/firmware/devicetree" + id + "/" + property);
        if (!file.open(QIODevice::ReadOnly))
            return -1;
        const QByteArray value = file.read(4);
        return value.size() == 4 ? qFromBigEndian<quint32>(value.constData()) : -1;
    }

    Position positionOf(const QString &id) {
        switch (deviceTreeCell(id, "orientation")) {
            case 0: return FrontFace;
            case 1: return BackFace;
            default: return UnspecifiedPosition;
        }
    }

    // How far its frames turn clockwise to stand upright on the screen.
    int rotationOf(const QString &id) {
        const qint64 rotation = deviceTreeCell(id, "rotation");
        return rotation > 0 ? int(rotation % 360) : 0;
    }
}

CameraController::CameraController(QObject *parent)
    : QObject(parent) {
    m_session = new CameraSession;
    m_session->moveToThread(&m_thread);
    connect(&m_thread, &QThread::finished, m_session, &QObject::deleteLater);
    connect(m_session, &CameraSession::discovered, this, &CameraController::onDiscovered);
    connect(m_session, &CameraSession::streamingChanged, this,
            &CameraController::onStreamingChanged);
    connect(m_session, &CameraSession::frameReady, this, &CameraController::onFrameReady);
    connect(m_session, &CameraSession::stillCaptured, this, &CameraController::onStillCaptured);
    connect(m_session, &CameraSession::stillFinished, this, &CameraController::onStillFinished);
    connect(m_session, &CameraSession::focusFinished, this, [this](bool focused) {
        if (m_focusState == FocusSearching)
            setFocusState(focused ? FocusLocked : FocusUnlocked);
    });
    connect(m_session, &CameraSession::recordingChanged, this, [this](bool recording) {
        m_recording = recording;
        emit recordingChanged();
    });
    connect(m_session, &CameraSession::recordingFinished, this,
            &CameraController::onRecordingFinished);
    connect(m_session, &CameraSession::error, this, &CameraController::fail);
    m_thread.setObjectName("camera");
    m_thread.start();
}

// The session closes the camera, finishing a recording, as its thread ends.
CameraController::~CameraController() {
    m_thread.quit();
    m_thread.wait();
}

void CameraController::discover() {
    if (m_discovered || m_discovering)
        return;
    m_discovering = true;
    QMetaObject::invokeMethod(m_session, &CameraSession::discover, Qt::QueuedConnection);
}

void CameraController::onDiscovered(const QList<CameraInfo> &cameras) {
    m_discovering = false;
    m_cameras     = cameras;
    m_discovered  = true;
    qWarning() << "[CameraController] Found" << m_cameras.size() << "cameras";
    int index = -1;
    for (int i = 0; i < m_cameras.size() && index < 0; ++i) {
        if (m_cameras.at(i).id == m_cameraId)
            index = i;
    }
    m_currentCameraIndex = std::max(0, index);
    emit cameraCountChanged();
    emit currentCameraIndexChanged();
    emit photoResolutionsChanged();
    emit readyChanged();
    want();
}

QString CameraController::currentId() const {
    return m_currentCameraIndex < m_cameras.size() ? m_cameras.at(m_currentCameraIndex).id : QString();
}

// The session follows the camera, size and state asked for last.
void CameraController::want() {
    if (m_discovered)
        m_session->want({currentId(), m_viewfinderResolution, m_wantStreaming});
}

void CameraController::start() {
    m_wantStreaming = true;
    discover();
    want();
}

void CameraController::stop() {
    m_wantStreaming = false;
    want();
}

void CameraController::release() {
    m_wantStreaming = false;
    want();
    QMetaObject::invokeMethod(m_session, &CameraSession::release, Qt::QueuedConnection);
    if (m_videoSink)
        m_videoSink->present(QImage());
}

void CameraController::onStreamingChanged(bool streaming) {
    if (!streaming && m_still.first.isEmpty())
        setFocusState(FocusUnlocked);
    if (m_active == streaming)
        return;
    m_active = streaming;
    emit activeChanged();
}

void CameraController::onFrameReady() {
    const QImage frame = m_session->takeFrame();
    if (m_videoSink && !frame.isNull())
        m_videoSink->present(frame);
}

void CameraController::capturePhoto(const QString &path, int rotation) {
    if (!m_active || !m_still.first.isEmpty()) {
        fail("Camera not ready");
        return;
    }
    m_photoClock.start();
    m_still = {path, rotation};
    emit takingStillChanged();
    const QSize size = m_photoResolution.isValid() ? m_photoResolution : m_viewfinderResolution;
    QMetaObject::invokeMethod(
        m_session, [session = m_session, size] { session->takeStill(size); }, Qt::QueuedConnection);
}

void CameraController::onStillCaptured(const QImage &image) {
    const auto [fileName, rotation] = m_still;
    if (fileName.isEmpty())
        return;
    emit photoExposed();
    if (image.isNull()) {
        fail("Could not read the photo's frame");
        return;
    }
    savePhoto(image, fileName, rotation);
}

void CameraController::onStillFinished() {
    m_still = {};
    emit takingStillChanged();
}

bool CameraController::takingStill() const {
    return !m_still.first.isEmpty();
}

void CameraController::startRecording(const QString &path, const QString &posterPath,
                                      int rotation) {
    if (!m_active || m_recording) {
        fail("Camera not ready for recording");
        return;
    }
    m_posterPath      = posterPath;
    m_recordingPoster = m_videoSink ? m_videoSink->frame() : QImage();
    QMetaObject::invokeMethod(
        m_session, [session = m_session, path, rotation] { session->startRecording(path, rotation); },
        Qt::QueuedConnection);
}

void CameraController::stopRecording() {
    QMetaObject::invokeMethod(m_session, &CameraSession::stopRecording, Qt::QueuedConnection);
}

void CameraController::onRecordingFinished(const QString &path, bool saved) {
    const QImage  poster     = std::exchange(m_recordingPoster, {});
    const QString posterPath = std::exchange(m_posterPath, {});
    if (!saved || !QFileInfo::exists(path))
        return;
    QPointer<CameraController> self(this);
    QThreadPool::globalInstance()->start([self, poster, posterPath, path] {
        if (!posterPath.isEmpty() && !poster.isNull())
            poster.scaled(512, 512, Qt::KeepAspectRatio, Qt::SmoothTransformation).save(posterPath);
        QMetaObject::invokeMethod(QCoreApplication::instance(), [self, path] {
            if (self)
                emit self->videoSaved(QUrl::fromLocalFile(path).toString());
        });
    });
}

bool CameraController::isRecording() const {
    return m_recording;
}

void CameraController::focusOnPoint(qreal x, qreal y) {
    if (!m_active || !focusSupported())
        return;
    if (m_session->focusOn(QPointF(x, y)))
        setFocusState(FocusSearching);
}

void CameraController::unlockFocus() {
    if (m_focusState != FocusUnlocked)
        m_session->focusContinuously();
    setFocusState(FocusUnlocked);
}

bool CameraController::focusSupported() const {
    const QString id = currentId();
    return isDeviceTreeCamera(id) && QFile::exists("/sys/firmware/devicetree" + id + "/lens-focus");
}

CameraController::FocusState CameraController::focusState() const {
    return m_focusState;
}

void CameraController::setFocusState(FocusState state) {
    if (m_focusState == state)
        return;
    m_focusState = state;
    emit focusStateChanged();
}

QObject *CameraController::videoSink() const {
    return m_videoSink;
}

void CameraController::setVideoSink(QObject *sink) {
    auto *output = qobject_cast<SoftwareVideoOutput *>(sink);
    if (m_videoSink == output)
        return;
    m_videoSink = output;
    emit videoSinkChanged();
}

bool CameraController::isDiscovered() const {
    return m_discovered;
}

bool CameraController::isActive() const {
    return m_active;
}

int CameraController::cameraCount() const {
    return m_cameras.size();
}

QVariantList CameraController::cameras() const {
    QVariantList list;
    for (const CameraInfo &camera : m_cameras)
        list.append(QVariantMap{{"id", camera.id},
                                {"description", camera.id},
                                {"position", int(positionOf(camera.id))},
                                {"rotation", rotationOf(camera.id)}});
    return list;
}

// The first camera on the back, else the first.
QString CameraController::defaultCameraId() const {
    for (const CameraInfo &camera : m_cameras) {
        if (positionOf(camera.id) == BackFace)
            return camera.id;
    }
    return m_cameras.isEmpty() ? QString() : m_cameras.first().id;
}

QString CameraController::cameraId() const {
    return m_discovered ? currentId() : m_cameraId;
}

void CameraController::setCameraId(const QString &id) {
    if (id == cameraId())
        return;
    m_cameraId = id;
    for (int i = 0; i < m_cameras.size(); ++i) {
        if (m_cameras.at(i).id == id)
            m_currentCameraIndex = i;
    }
    emit currentCameraIndexChanged();
    emit photoResolutionsChanged();
    if (!photoResolutions().contains(QVariant(m_photoResolution))) {
        m_photoResolution = QSize();
        emit photoResolutionChanged();
    }
    want();
}

QVariantList CameraController::previewResolutions() const {
    QVariantList list;
    if (m_currentCameraIndex < m_cameras.size()) {
        for (const QSize &size : m_cameras.at(m_currentCameraIndex).sizes)
            list.append(size);
    }
    return list;
}

QSize CameraController::viewfinderResolution() const {
    return m_viewfinderResolution;
}

void CameraController::setViewfinderResolution(const QSize &size) {
    if (m_viewfinderResolution == size)
        return;
    m_viewfinderResolution = size;
    want();
    emit viewfinderResolutionChanged();
}

// libcamera's software ISP offers no ScalerCrop control: no zoom.
qreal CameraController::zoomLevel() const {
    return m_zoomLevel;
}

void CameraController::setZoomLevel(qreal level) {
    Q_UNUSED(level)
}

qreal CameraController::maxZoom() const {
    return 1.0;
}

bool CameraController::flashEnabled() const {
    return m_flashEnabled;
}

void CameraController::setFlashEnabled(bool enabled) {
    if (m_flashEnabled == enabled)
        return;
    m_flashEnabled = enabled;
    emit flashEnabledChanged();
}

bool CameraController::flashAvailable() const {
    return false;
}

QVariantList CameraController::photoResolutions() const {
    return previewResolutions();
}

QSize CameraController::photoResolution() const {
    return m_photoResolution;
}

// An empty size takes photos at the viewfinder's.
void CameraController::setPhotoResolution(const QSize &size) {
    if (m_photoResolution == size ||
        (size.isValid() && !photoResolutions().contains(QVariant(size))))
        return;
    m_photoResolution = size;
    emit photoResolutionChanged();
}

// The photo as a JPEG stood upright: libjpeg-turbo turns the coded blocks
// (lossless), far quicker than turning 12 million pixels before encoding. A
// lossless turn needs whole 16-pixel blocks, so a few edge columns go.
static QByteArray encodePhoto(const QImage &image, int rotation, bool square, QString *error) {
    int pixelFormat;
    switch (image.format()) {
        case QImage::Format_RGBA8888:
        case QImage::Format_RGBX8888: pixelFormat = TJPF_RGBX; break;
        case QImage::Format_ARGB32:
        case QImage::Format_RGB32: pixelFormat = TJPF_BGRX; break;
        default: return encodePhoto(image.convertToFormat(QImage::Format_RGB32), rotation, square, error);
    }
    // Whole 16-pixel blocks, so the turn below is lossless; a square from the middle.
    const int side   = std::min(image.width(), image.height()) & ~15;
    const int width  = square ? side : image.width() & ~15;
    const int height = square ? side : image.height() & ~15;
    const uchar *top = image.constBits() + (image.width() - width) / 2 * 4 +
        (image.height() - height) / 2 * image.bytesPerLine();

    tjhandle       encoder = tjInitCompress();
    unsigned char *jpeg    = nullptr;
    unsigned long  size    = 0;
    const bool encoded = encoder && tjCompress2(encoder, top, width, int(image.bytesPerLine()), height,
                                                pixelFormat, &jpeg, &size, TJSAMP_420, 92, 0) == 0;
    if (!encoded)
        *error = QString::fromUtf8(tjGetErrorStr2(encoder));
    tjDestroy(encoder);
    if (!encoded) {
        tjFree(jpeg);
        return {};
    }

    rotation = ((rotation % 360) + 360) % 360;
    if (rotation == 0) {
        QByteArray out(reinterpret_cast<const char *>(jpeg), qsizetype(size));
        tjFree(jpeg);
        return out;
    }
    tjtransform turn{};
    turn.op      = rotation == 90 ? TJXOP_ROT90 : rotation == 180 ? TJXOP_ROT180 : TJXOP_ROT270;
    turn.options = TJXOPT_PERFECT;
    tjhandle       rotator = tjInitTransform();
    unsigned char *turned  = nullptr;
    unsigned long  turnedSize = 0;
    const bool rotated = rotator && tjTransform(rotator, jpeg, size, 1, &turned, &turnedSize, &turn, 0) == 0;
    if (!rotated)
        *error = QString::fromUtf8(tjGetErrorStr2(rotator));
    tjDestroy(rotator);
    tjFree(jpeg);
    QByteArray out;
    if (rotated)
        out = QByteArray(reinterpret_cast<const char *>(turned), qsizetype(turnedSize));
    tjFree(turned);
    return out;
}

void CameraController::savePhoto(const QImage &image, const QString &fileName, int rotation) {
    QPointer<CameraController> self(this);
    const qint64 exposedAfter = m_photoClock.elapsed();
    const bool   square       = m_squarePhotos;
    QThreadPool::globalInstance()->start([self, image, fileName, rotation, square, exposedAfter] {
        QElapsedTimer clock;
        clock.start();
        QString          error;
        const QByteArray jpeg = encodePhoto(image, rotation, square, &error);
        // Under another name until whole: the camera roll shows the folder.
        const QString part  = fileName + ".part";
        QFile         file(part);
        bool          saved = !jpeg.isEmpty() && file.open(QIODevice::WriteOnly) &&
            file.write(jpeg) == jpeg.size() && file.flush();
        file.close();
        if (saved)
            saved = QFile::rename(part, fileName);
        if (!saved) {
            QFile::remove(part);
            if (error.isEmpty())
                error = file.errorString();
        }
        const qint64 writtenIn = clock.elapsed();
        QMetaObject::invokeMethod(QCoreApplication::instance(),
                                  [self, saved, fileName, error, exposedAfter, writtenIn] {
            if (!self)
                return;
            if (!saved) {
                self->fail(error);
                return;
            }
            qWarning().noquote() << "[CameraController] Photo saved:" << fileName << "- exposed after"
                                 << exposedAfter << "ms, written in" << writtenIn << "ms";
            emit self->photoSaved(QUrl::fromLocalFile(fileName).toString());
        });
    });
}

void CameraController::fail(const QString &message) {
    qWarning() << "[CameraController]" << message;
    emit errorOccurred(message);
}
