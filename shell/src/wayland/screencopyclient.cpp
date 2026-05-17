#include "screencopyclient.h"

#include <QGuiApplication>
#include <QLoggingCategory>
#include <qpa/qplatformnativeinterface.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client-protocol.h>

Q_LOGGING_CATEGORY(lcSC, "marathon.shell.screencopy")

static constexpr int kScreencopyVersion = 3;

ScreencopyClient::ScreencopyClient(QObject *parent)
    : QWaylandClientExtensionTemplate<ScreencopyClient>(kScreencopyVersion) {
    setParent(parent);
    connect(this, &QWaylandClientExtension::activeChanged, this,
            [this]() { qCInfo(lcSC) << "screencopy active:" << isActive(); });
}

ScreencopyClient::~ScreencopyClient() = default;

wl_output *ScreencopyClient::outputProxy() const {
    auto *native = QGuiApplication::platformNativeInterface();
    return static_cast<wl_output *>(native->nativeResourceForIntegration("wl_output"));
}

wl_shm *ScreencopyClient::shmProxy() const {
    auto *native = QGuiApplication::platformNativeInterface();
    return static_cast<wl_shm *>(native->nativeResourceForIntegration("wl_shm"));
}

void ScreencopyClient::capture(const QString &tag) {
    if (!isActive()) {
        qCWarning(lcSC) << "capture requested but extension not active";
        emit captureFailed(tag);
        return;
    }
    wl_output *output = outputProxy();
    wl_shm    *shm    = shmProxy();
    if (!output || !shm) {
        qCWarning(lcSC) << "missing wl_output or wl_shm proxy from QPA";
        emit captureFailed(tag);
        return;
    }
    // overlay_cursor=0: thumbnails are app frames, not cursor preview.
    struct ::zwlr_screencopy_frame_v1 *raw = capture_output(0, output);
    if (!raw) {
        emit captureFailed(tag);
        return;
    }
    auto *frame = new ScreencopyFrame(this, raw, shm, tag);
    connect(frame, &ScreencopyFrame::ready, this,
            [this, frame](const QImage &image) { onFrameReady(frame, image); });
    connect(frame, &ScreencopyFrame::failed, this, [this, frame]() { onFrameFailed(frame); });
}

void ScreencopyClient::onFrameReady(ScreencopyFrame *frame, const QImage &image) {
    emit captured(frame->tag(), image);
    frame->deleteLater();
}

void ScreencopyClient::onFrameFailed(ScreencopyFrame *frame) {
    emit captureFailed(frame->tag());
    frame->deleteLater();
}

// -- frame ------------------------------------------------------------

ScreencopyFrame::ScreencopyFrame(ScreencopyClient *client, struct ::zwlr_screencopy_frame_v1 *frame,
                                 struct wl_shm *shm, const QString &tag)
    : QObject(client)
    , QtWayland::zwlr_screencopy_frame_v1(frame)
    , m_client(client)
    , m_shm(shm)
    , m_tag(tag) {}

ScreencopyFrame::~ScreencopyFrame() {
    teardown();
    if (isInitialized())
        destroy();
}

void ScreencopyFrame::teardown() {
    if (m_buffer) {
        wl_buffer_destroy(m_buffer);
        m_buffer = nullptr;
    }
    if (m_mappedPtr) {
        munmap(m_mappedPtr, m_mappedLen);
        m_mappedPtr = nullptr;
        m_mappedLen = 0;
    }
    if (m_shmFd >= 0) {
        ::close(m_shmFd);
        m_shmFd = -1;
    }
}

void ScreencopyFrame::zwlr_screencopy_frame_v1_buffer(uint32_t format, uint32_t width,
                                                      uint32_t height, uint32_t stride) {
    // First buffer event wins — the server may also emit linux_dmabuf
    // (v3) which we deliberately ignore, falling back to shm here.
    if (m_width > 0)
        return;
    m_format = format;
    m_width  = width;
    m_height = height;
    m_stride = stride;
}

void ScreencopyFrame::zwlr_screencopy_frame_v1_buffer_done() {
    if (!allocateShmBuffer()) {
        emit failed();
        return;
    }
    copy(m_buffer);
}

bool ScreencopyFrame::allocateShmBuffer() {
    if (m_width == 0 || m_height == 0 || m_stride == 0)
        return false;
    m_mappedLen = static_cast<size_t>(m_stride) * m_height;
    // memfd_create gives us an anonymous fd suitable for wl_shm_create_pool.
    // F_SEAL_SHRINK keeps the kernel from rug-pulling the mapping if the
    // server requests it.
    m_shmFd = memfd_create("marathon-screencopy", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (m_shmFd < 0)
        return false;
    if (ftruncate(m_shmFd, m_mappedLen) < 0) {
        ::close(m_shmFd);
        m_shmFd = -1;
        return false;
    }
    m_mappedPtr = mmap(nullptr, m_mappedLen, PROT_READ | PROT_WRITE, MAP_SHARED, m_shmFd, 0);
    if (m_mappedPtr == MAP_FAILED) {
        m_mappedPtr = nullptr;
        ::close(m_shmFd);
        m_shmFd = -1;
        return false;
    }
    wl_shm_pool *pool = wl_shm_create_pool(m_shm, m_shmFd, m_mappedLen);
    m_buffer          = wl_shm_pool_create_buffer(pool, 0, m_width, m_height, m_stride, m_format);
    wl_shm_pool_destroy(pool);
    return m_buffer != nullptr;
}

void ScreencopyFrame::zwlr_screencopy_frame_v1_flags(uint32_t flags) {
    m_flags = flags;
}

void ScreencopyFrame::zwlr_screencopy_frame_v1_ready(uint32_t, uint32_t, uint32_t) {
    // wl_shm format → QImage format. We pin the server side to
    // XRGB8888, so this match is the expected path; warn and bail
    // if the server ever advertises something else.
    QImage::Format qfmt = QImage::Format_Invalid;
    switch (m_format) {
        case WL_SHM_FORMAT_XRGB8888:
        case WL_SHM_FORMAT_ARGB8888: qfmt = QImage::Format_RGB32; break;
        default:
            qCWarning(lcSC) << "unexpected shm format" << m_format;
            emit failed();
            return;
    }
    // Wrap the mapped memory directly — QImage::copy detaches into
    // its own buffer so we can safely munmap below.
    QImage view(static_cast<const uchar *>(m_mappedPtr), m_width, m_height, m_stride, qfmt);
    QImage owned = view.copy();
    if (m_flags & ZWLR_SCREENCOPY_FRAME_V1_FLAGS_Y_INVERT)
        owned.flip(Qt::Vertical);
    emit ready(owned);
}

void ScreencopyFrame::zwlr_screencopy_frame_v1_failed() {
    qCWarning(lcSC) << "server reported capture failed for tag" << m_tag;
    emit failed();
}
