// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0
#include "CameraSession.h"

#include "Recorder.h"

#include <QDebug>
#include <algorithm>
#include <cstring>
#include <linux/dma-buf.h>
#include <sys/ioctl.h>
#include <sys/mman.h>

using namespace libcamera;

namespace {

    // R, G, B, X in memory: QImage's RGBX8888, GL's RGBA, GStreamer's RGBx.
    const PixelFormat  kFormat           = formats::XBGR8888;
    constexpr uint64_t kViewfinderCookie = 0;
    constexpr uint64_t kStillCookie      = 1;
    // The software ISP keeps its exposure across the photo's format; the first
    // frame after a restart can be torn.
    constexpr int    kStillFrames = 2;
    constexpr size_t kPoolSize    = 6;

    void             syncForCpu(int fd, bool start) {
        dma_buf_sync sync{
            __u64((start ? DMA_BUF_SYNC_START : DMA_BUF_SYNC_END) | DMA_BUF_SYNC_READ)};
        ioctl(fd, DMA_BUF_IOCTL_SYNC, &sync);
    }

    size_t mappedLength(const FrameBuffer *buffer) {
        const FrameBuffer::Plane &last = buffer->planes().back();
        return last.offset + last.length;
    }

    // A photo's buffer, mapped, and the allocator that owns it.
    struct StillHold {
        std::shared_ptr<FrameBufferAllocator> allocator;
        void                                 *data;
        size_t                                length;
        int                                   fd;
    };

} // namespace

CameraSession::CameraSession()
    : m_controls(controls::controls)
    , m_sticky(controls::controls) {}

CameraSession::~CameraSession() {
    release();
}

void CameraSession::want(const Wanted &wanted) {
    {
        QMutexLocker locked(&m_wantLock);
        m_wanted = wanted;
    }
    if (!m_reconcilePosted.exchange(true))
        QMetaObject::invokeMethod(this, &CameraSession::reconcile, Qt::QueuedConnection);
}

bool CameraSession::startManager() {
    if (m_manager)
        return true;
    QElapsedTimer clock;
    clock.start();
    auto manager = std::make_unique<CameraManager>();
    if (const int ret = manager->start(); ret < 0) {
        emit error(QStringLiteral("Could not start libcamera: %1").arg(strerror(-ret)));
        return false;
    }
    m_manager = std::move(manager);
    qWarning() << "[CameraSession] libcamera up in" << clock.elapsed() << "ms";
    return true;
}

void CameraSession::discover() {
    if (!startManager()) {
        emit discovered({});
        return;
    }
    QList<CameraInfo> cameras;
    for (const std::shared_ptr<Camera> &camera : m_manager->cameras()) {
        CameraInfo         info{QString::fromStdString(camera->id()), {}};
        const ControlList &props = camera->properties();
        if (const auto location = props.get(properties::Location))
            info.location = *location;
        if (const auto rotation = props.get(properties::Rotation))
            info.rotation = *rotation % 360;
        if (const auto array = props.get(properties::PixelArrayArea))
            info.pixels = qint64(array->width) * array->height;
        const std::unique_ptr<CameraConfiguration> config =
            camera->generateConfiguration({StreamRole::Viewfinder});
        if (config) {
            const StreamFormats &formats = config->at(0).formats();
            std::vector<Size>    sizes   = formats.sizes(kFormat);
            sizes.push_back(formats.range(kFormat).max);
            for (const Size &size : sizes) {
                const QSize qsize(int(size.width), int(size.height));
                if (!qsize.isEmpty() && !info.sizes.contains(qsize))
                    info.sizes.append(qsize);
            }
            std::sort(info.sizes.begin(), info.sizes.end(), [](const QSize &a, const QSize &b) {
                return a.width() * a.height() > b.width() * b.height();
            });
        }
        cameras.append(info);
    }
    // The back cameras first, largest sensor first, which makes the main one
    // the default; libcamera's order changes from boot to boot.
    const auto side = [](const CameraInfo &camera) {
        switch (camera.location) {
            case properties::LocationBack: return 0;
            case properties::LocationFront: return 1;
            case properties::LocationExternal: return 2;
            default: return 3;
        }
    };
    std::stable_sort(cameras.begin(), cameras.end(),
                     [&side](const CameraInfo &a, const CameraInfo &b) {
                         if (side(a) != side(b))
                             return side(a) < side(b);
                         return a.pixels > b.pixels;
                     });
    emit discovered(cameras);
}

// Brings the camera to what was last wanted, doing only what differs.
void CameraSession::reconcile() {
    m_reconcilePosted = false;
    if (m_stillActive)
        return;
    Wanted wanted;
    {
        QMutexLocker locked(&m_wantLock);
        wanted = m_wanted;
    }
    const bool other       = m_camera && m_cameraId != wanted.cameraId;
    const bool reconfigure = other || !m_config || wanted.size != m_size;
    if (m_streaming && (!wanted.streaming || reconfigure)) {
        finishRecording();
        stopCamera();
        emit streamingChanged(false);
    }
    if (other)
        close();
    if (!wanted.streaming)
        return;
    if (!startManager() || (!m_camera && !open(wanted.cameraId)))
        return;
    if (reconfigure && !configureViewfinder(wanted.size))
        return;
    if (!m_configured) {
        if (const int ret = m_camera->configure(m_config.get()); ret < 0) {
            emit error(QStringLiteral("Could not configure the camera: %1").arg(strerror(-ret)));
            return;
        }
        m_configured = true;
    }
    if (!startViewfinder())
        return;
    emit streamingChanged(true);
    if (!std::exchange(m_recorderPrepared, true))
        Recorder::prepare();
}

bool CameraSession::open(const QString &id) {
    std::shared_ptr<Camera> camera = m_manager->get(id.toStdString());
    if (!camera && !m_manager->cameras().empty())
        camera = m_manager->cameras().front();
    if (!camera) {
        emit error(QStringLiteral("No camera"));
        return false;
    }
    if (const int ret = camera->acquire(); ret < 0) {
        emit error(QStringLiteral("Could not open the camera: %1").arg(strerror(-ret)));
        return false;
    }
    camera->requestCompleted.connect(this, &CameraSession::requestCompleted);
    m_camera       = std::move(camera);
    m_cameraId     = id;
    m_hasAutofocus = m_camera->controls().count(&controls::AfMode) > 0;
    QMutexLocker locked(&m_controlLock);
    m_controls.clear();
    m_sticky.clear();
    m_scalerCrop     = {};
    m_lensPosition   = -1;
    m_triggerRequest = nullptr;
    m_scanning       = false;
    if (m_hasAutofocus) {
        m_sticky.set(controls::AfMode, controls::AfModeContinuous);
        m_sticky.set(controls::AfMetering, controls::AfMeteringAuto);
    }
    return true;
}

void CameraSession::close() {
    if (!m_camera)
        return;
    m_requests.clear();
    for (const auto &[buffer, mapping] : m_mappings)
        munmap(const_cast<uchar *>(mapping.data), mapping.length);
    m_mappings.clear();
    m_allocator.reset();
    m_config.reset();
    m_configured = false;
    m_size       = {};
    m_camera->requestCompleted.disconnect(this);
    m_camera->release();
    m_camera.reset();
    m_cameraId.clear();
}

bool CameraSession::configureViewfinder(const QSize &size) {
    m_requests.clear();
    for (const auto &[buffer, mapping] : m_mappings)
        munmap(const_cast<uchar *>(mapping.data), mapping.length);
    m_mappings.clear();
    m_allocator.reset();
    m_config.reset();
    m_configured = false;
    m_pool.clear();

    std::unique_ptr<CameraConfiguration> config =
        m_camera->generateConfiguration({StreamRole::Viewfinder});
    StreamConfiguration &stream = config->at(0);
    stream.pixelFormat          = kFormat;
    if (size.isValid())
        stream.size = Size(size.width(), size.height());
    if (config->validate() == CameraConfiguration::Invalid || stream.pixelFormat != kFormat) {
        emit error(QStringLiteral("The camera cannot make %1x%2 RGB frames")
                       .arg(QString::number(size.width()), QString::number(size.height())));
        return false;
    }
    if (const int ret = m_camera->configure(config.get()); ret < 0) {
        emit error(QStringLiteral("Could not configure the camera: %1").arg(strerror(-ret)));
        return false;
    }
    auto allocator = std::make_unique<FrameBufferAllocator>(m_camera);
    if (allocator->allocate(stream.stream()) < 0) {
        emit error(QStringLiteral("Could not allocate the camera's buffers"));
        return false;
    }
    for (const std::unique_ptr<FrameBuffer> &buffer : allocator->buffers(stream.stream())) {
        const int    fd     = buffer->planes().front().fd.get();
        const size_t length = mappedLength(buffer.get());
        void        *data   = mmap(nullptr, length, PROT_READ, MAP_SHARED, fd, 0);
        if (data == MAP_FAILED) {
            emit error(QStringLiteral("Could not map the camera's buffers"));
            return false;
        }
        m_mappings[buffer.get()] = {
            static_cast<const uchar *>(data) + buffer->planes().front().offset, length, fd};
        std::unique_ptr<Request> request = m_camera->createRequest(kViewfinderCookie);
        request->addBuffer(stream.stream(), buffer.get());
        m_requests.push_back(std::move(request));
    }
    m_frameSize  = QSize(int(stream.size.width), int(stream.size.height));
    m_stride     = stream.stride;
    m_allocator  = std::move(allocator);
    m_config     = std::move(config);
    m_size       = size;
    m_configured = true;
    qWarning().noquote() << "[CameraSession] Viewfinder"
                         << QString::fromStdString(m_config->at(0).toString());
    return true;
}

bool CameraSession::startViewfinder() {
    m_startClock.start();
    m_firstFrame = true;
    if (const int ret = m_camera->start(); ret < 0) {
        emit error(QStringLiteral("Could not start the camera: %1").arg(strerror(-ret)));
        return false;
    }
    m_streaming = true;
    {
        QMutexLocker locked(&m_controlLock);
        ControlList  controls = m_sticky;
        controls.merge(m_controls, ControlList::MergePolicy::OverwriteExisting);
        m_controls = std::move(controls);
    }
    for (const std::unique_ptr<Request> &request : m_requests) {
        request->reuse(Request::ReuseBuffers);
        addControls(request.get());
        m_camera->queueRequest(request.get());
    }
    return true;
}

void CameraSession::stopCamera() {
    m_streaming = false;
    m_camera->stop();
}

// The pending controls go with the next request.
void CameraSession::addControls(Request *request) {
    QMutexLocker locked(&m_controlLock);
    if (m_controls.empty())
        return;
    if (m_controls.contains(controls::AfTrigger.id())) {
        m_triggerRequest = request;
        m_scanning       = false;
    }
    request->controls().merge(m_controls, ControlList::MergePolicy::OverwriteExisting);
    m_controls.clear();
}

bool CameraSession::focusOn(const QPointF &point) {
    if (!m_hasAutofocus)
        return false;
    QMutexLocker    locked(&m_controlLock);
    const Rectangle crop = m_scalerCrop;
    if (crop.isNull())
        return false;
    // A fifth of the frame each way around the point, kept inside it.
    const int       w = int(crop.width / 5), h = int(crop.height / 5);
    const int       x = std::clamp(crop.x + int(point.x() * crop.width) - w / 2, crop.x,
                                   crop.x + int(crop.width) - w);
    const int       y = std::clamp(crop.y + int(point.y() * crop.height) - h / 2, crop.y,
                                   crop.y + int(crop.height) - h);
    const Rectangle window(x, y, unsigned(w), unsigned(h));
    m_sticky.set(controls::AfMode, controls::AfModeAuto);
    m_sticky.set(controls::AfMetering, controls::AfMeteringWindows);
    m_sticky.set(controls::AfWindows, std::span<const Rectangle>(&window, 1));
    m_controls.merge(m_sticky, ControlList::MergePolicy::OverwriteExisting);
    m_controls.set(controls::AfTrigger, controls::AfTriggerStart);
    return true;
}

void CameraSession::focusContinuously() {
    if (!m_hasAutofocus)
        return;
    QMutexLocker locked(&m_controlLock);
    m_sticky.clear();
    m_sticky.set(controls::AfMode, controls::AfModeContinuous);
    m_sticky.set(controls::AfMetering, controls::AfMeteringAuto);
    m_controls.merge(m_sticky, ControlList::MergePolicy::OverwriteExisting);
    m_triggerRequest = nullptr;
    m_scanning       = false;
}

QImage CameraSession::takeFrame() {
    m_framePosted = false;
    QMutexLocker locked(&m_frameLock);
    return std::exchange(m_frame, {});
}

// On libcamera's thread.
void CameraSession::requestCompleted(Request *request) {
    if (request->status() == Request::RequestCancelled)
        return;
    const ControlList &metadata   = request->metadata();
    bool               focusEnded = false, focused = false;
    {
        QMutexLocker locked(&m_controlLock);
        if (const auto crop = metadata.get(controls::ScalerCrop))
            m_scalerCrop = *crop;
        if (const auto lens = metadata.get(controls::LensPosition))
            m_lensPosition = *lens;
        if (request == m_triggerRequest) {
            m_triggerRequest = nullptr;
            m_scanning       = true;
        }
        const auto af = metadata.get(controls::AfState);
        if (m_scanning && af && *af != controls::AfStateScanning) {
            m_scanning = false;
            focusEnded = true;
            focused    = *af == controls::AfStateFocused;
        }
    }
    if (focusEnded)
        emit focusFinished(focused);

    FrameBuffer *buffer = request->buffers().begin()->second;
    if (request->cookie() == kStillCookie) {
        if (--m_stillFrames != 0)
            return;
        const StreamConfiguration &stream = request->buffers().begin()->first->configuration();
        auto *hold = new StillHold{m_stillAllocator, nullptr, mappedLength(buffer),
                                   buffer->planes().front().fd.get()};
        hold->data = mmap(nullptr, hold->length, PROT_READ, MAP_SHARED, hold->fd, 0);
        QImage image;
        if (hold->data != MAP_FAILED) {
            syncForCpu(hold->fd, true);
            image = QImage(
                static_cast<const uchar *>(hold->data) + buffer->planes().front().offset,
                int(stream.size.width), int(stream.size.height), int(stream.stride),
                QImage::Format_RGBX8888,
                [](void *info) {
                    auto *held = static_cast<StillHold *>(info);
                    syncForCpu(held->fd, false);
                    munmap(held->data, held->length);
                    delete held;
                },
                hold);
        } else {
            delete hold;
        }
        emit stillCaptured(image);
        QMetaObject::invokeMethod(this, &CameraSession::finishStill, Qt::QueuedConnection);
        return;
    }

    if (buffer->metadata().status == FrameMetadata::FrameSuccess) {
        const QImage frame = copyFrame(buffer);
        if (std::exchange(m_firstFrame, false))
            qWarning() << "[CameraSession] First frame after" << m_startClock.elapsed() << "ms";
        {
            QMutexLocker locked(&m_recorderLock);
            if (m_recorder)
                m_recorder->push(frame, qint64(buffer->metadata().timestamp));
        }
        {
            QMutexLocker locked(&m_frameLock);
            m_frame = frame;
        }
        if (!m_framePosted.exchange(true))
            emit frameReady();
    }
    if (!m_streaming)
        return;
    request->reuse(Request::ReuseBuffers);
    addControls(request);
    m_camera->queueRequest(request);
}

QImage CameraSession::copyFrame(const FrameBuffer *buffer) {
    const Mapping &mapping = m_mappings.at(buffer);
    auto           free    = std::find_if(m_pool.begin(), m_pool.end(),
                                          [](const QImage &image) { return image.isDetached(); });
    QImage         spare;
    QImage        *frame = nullptr;
    if (free != m_pool.end()) {
        frame = &*free;
    } else if (m_pool.size() < kPoolSize) {
        frame = &m_pool.emplace_back(m_frameSize, QImage::Format_RGBX8888);
    } else {
        spare = QImage(m_frameSize, QImage::Format_RGBX8888);
        frame = &spare;
    }
    syncForCpu(mapping.fd, true);
    if (qsizetype(m_stride) == frame->bytesPerLine()) {
        memcpy(frame->bits(), mapping.data, size_t(m_stride) * size_t(m_frameSize.height()));
    } else {
        const size_t row = size_t(m_frameSize.width()) * 4;
        for (int y = 0; y < m_frameSize.height(); ++y)
            memcpy(frame->scanLine(y), mapping.data + size_t(y) * m_stride, row);
    }
    syncForCpu(mapping.fd, false);
    return *frame;
}

// The camera restarts in the photo's format, gives its second frame, and
// goes back to the viewfinder.
void CameraSession::takeStill(const QSize &size) {
    if (!m_streaming || m_stillActive) {
        emit error(QStringLiteral("Camera not ready"));
        emit stillFinished();
        return;
    }
    stopCamera();
    m_configured = false;
    std::unique_ptr<CameraConfiguration> config =
        m_camera->generateConfiguration({StreamRole::StillCapture});
    StreamConfiguration &stream = config->at(0);
    stream.pixelFormat          = kFormat;
    stream.size                 = Size(size.width(), size.height());
    stream.bufferCount          = kStillFrames;
    auto allocator              = std::make_shared<FrameBufferAllocator>(m_camera);
    if (config->validate() == CameraConfiguration::Invalid || stream.pixelFormat != kFormat ||
        m_camera->configure(config.get()) < 0 || allocator->allocate(stream.stream()) < 0) {
        emit error(QStringLiteral("Could not take a photo at %1x%2")
                       .arg(QString::number(size.width()), QString::number(size.height())));
        emit stillFinished();
        reconcile();
        return;
    }
    m_stillActive    = true;
    m_stillAllocator = std::move(allocator);
    for (const std::unique_ptr<FrameBuffer> &buffer : m_stillAllocator->buffers(stream.stream())) {
        std::unique_ptr<Request> request = m_camera->createRequest(kStillCookie);
        request->addBuffer(stream.stream(), buffer.get());
        m_stillRequests.push_back(std::move(request));
    }
    // Reconfigured, the autofocus starts a new scan: the photo keeps the lens where it was.
    ControlList &first = m_stillRequests.front()->controls();
    {
        QMutexLocker locked(&m_controlLock);
        if (m_hasAutofocus && m_lensPosition >= 0) {
            first.set(controls::AfMode, controls::AfModeManual);
            first.set(controls::LensPosition, m_lensPosition);
        }
    }
    m_stillFrames = int(m_stillRequests.size());
    if (const int ret = m_camera->start(); ret < 0) {
        emit error(QStringLiteral("Could not start the camera: %1").arg(strerror(-ret)));
        finishStill();
        return;
    }
    for (const std::unique_ptr<Request> &request : m_stillRequests)
        m_camera->queueRequest(request.get());
}

void CameraSession::finishStill() {
    if (!m_stillActive)
        return;
    m_camera->stop();
    m_stillRequests.clear();
    m_stillAllocator.reset();
    m_stillActive = false;
    bool streaming;
    {
        QMutexLocker locked(&m_wantLock);
        streaming = m_wanted.streaming;
    }
    // Unwanted meanwhile, the viewfinder stays off.
    if (!streaming)
        emit streamingChanged(false);
    reconcile();
    emit stillFinished();
}

void CameraSession::startRecording(const QString &path, int rotation) {
    if (!m_streaming || m_stillActive) {
        emit error(QStringLiteral("Camera not ready for recording"));
        return;
    }
    QString                   message;
    std::unique_ptr<Recorder> recorder = Recorder::start(path, m_frameSize, rotation, &message);
    if (!recorder) {
        emit error(message);
        return;
    }
    {
        QMutexLocker locked(&m_recorderLock);
        m_recorder = std::move(recorder);
    }
    m_recordingPath = path;
    emit recordingChanged(true);
}

void CameraSession::stopRecording() {
    finishRecording();
}

void CameraSession::finishRecording() {
    std::unique_ptr<Recorder> recorder;
    {
        QMutexLocker locked(&m_recorderLock);
        recorder = std::move(m_recorder);
    }
    if (!recorder)
        return;
    QString    message;
    const bool saved = recorder->finish(&message);
    if (!saved)
        emit error(message);
    emit recordingChanged(false);
    emit recordingFinished(std::exchange(m_recordingPath, {}), saved);
}

void CameraSession::release() {
    finishRecording();
    if (m_streaming || m_stillActive) {
        stopCamera();
        emit streamingChanged(false);
    }
    if (std::exchange(m_stillActive, false)) {
        m_stillRequests.clear();
        m_stillAllocator.reset();
        emit stillFinished();
    }
    close();
    m_pool.clear();
    {
        QMutexLocker locked(&m_frameLock);
        m_frame = {};
    }
    m_manager.reset();
}
