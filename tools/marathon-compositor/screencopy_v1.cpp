#include "screencopy_v1.h"

#include "wlr-screencopy-unstable-v1-server.h"

#include <QDateTime>
#include <QImage>
#include <QLoggingCategory>
#include <QQuickWindow>
#include <QWaylandCompositor>
#include <QWaylandQuickOutput>
#include <sys/mman.h>
#include <wayland-server-protocol.h>

Q_LOGGING_CATEGORY(lcScreencopy, "marathon.compositor.screencopy")

static constexpr uint32_t kScreencopyVersion = 3;

// XRGB8888 mapped to wl_shm's WL_SHM_FORMAT_XRGB8888 (== 1). We pin the
// format so the client knows exactly what to allocate; QImage's
// Format_RGB32 maps directly with no swizzle on little-endian hosts.
static constexpr uint32_t kShmFormat = WL_SHM_FORMAT_XRGB8888;

// -- manager -----------------------------------------------------------

static const struct zwlr_screencopy_manager_v1_interface managerImpl = {
    .capture_output        = ScreencopyManagerV1::onCaptureOutput,
    .capture_output_region = ScreencopyManagerV1::onCaptureOutputRegion,
    .destroy               = ScreencopyManagerV1::onDestroyManager,
};

ScreencopyManagerV1::ScreencopyManagerV1(QWaylandCompositor  *compositor,
                                         QWaylandQuickOutput *output, QQuickWindow *window)
    : QObject(compositor)
    , m_compositor(compositor)
    , m_output(output)
    , m_window(window) {
    m_global = wl_global_create(compositor->display(), &zwlr_screencopy_manager_v1_interface,
                                kScreencopyVersion, this, &bind);
    if (m_global)
        qCInfo(lcScreencopy) << "zwlr_screencopy_manager_v1 v" << kScreencopyVersion << "global"
                             << "created";
    else
        qCWarning(lcScreencopy) << "failed to create wl_global for zwlr_screencopy_manager_v1";
}

ScreencopyManagerV1::~ScreencopyManagerV1() {
    if (m_global)
        wl_global_destroy(m_global);
}

void ScreencopyManagerV1::bind(wl_client *client, void *data, uint32_t version, uint32_t id) {
    auto        *self = static_cast<ScreencopyManagerV1 *>(data);
    const auto   ver  = std::min<uint32_t>(version, kScreencopyVersion);
    wl_resource *res  = wl_resource_create(client, &zwlr_screencopy_manager_v1_interface, ver, id);
    if (!res) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(res, &managerImpl, self, nullptr);
}

void ScreencopyManagerV1::onCaptureOutput(wl_client *client, wl_resource *resource,
                                          uint32_t frameId, int32_t overlayCursor,
                                          wl_resource *output) {
    Q_UNUSED(output);
    auto        *self     = static_cast<ScreencopyManagerV1 *>(wl_resource_get_user_data(resource));
    auto        *win      = self->window();
    wl_resource *frameRes = wl_resource_create(client, &zwlr_screencopy_frame_v1_interface,
                                               wl_resource_get_version(resource), frameId);
    if (!frameRes) {
        wl_client_post_no_memory(client);
        return;
    }
    if (!win) {
        // No window yet — synthesize a failed frame so the client doesn't
        // hang waiting for buffer events.
        zwlr_screencopy_frame_v1_send_failed(frameRes);
        wl_resource_destroy(frameRes);
        return;
    }
    new ScreencopyFrameV1(self, frameRes, win, QRect(QPoint(0, 0), win->size()),
                          overlayCursor != 0);
}

void ScreencopyManagerV1::onCaptureOutputRegion(wl_client *client, wl_resource *resource,
                                                uint32_t frameId, int32_t overlayCursor,
                                                wl_resource *output, int32_t x, int32_t y,
                                                int32_t width, int32_t height) {
    Q_UNUSED(output);
    auto        *self     = static_cast<ScreencopyManagerV1 *>(wl_resource_get_user_data(resource));
    auto        *win      = self->window();
    wl_resource *frameRes = wl_resource_create(client, &zwlr_screencopy_frame_v1_interface,
                                               wl_resource_get_version(resource), frameId);
    if (!frameRes) {
        wl_client_post_no_memory(client);
        return;
    }
    if (!win) {
        zwlr_screencopy_frame_v1_send_failed(frameRes);
        wl_resource_destroy(frameRes);
        return;
    }
    QRect region(x, y, width, height);
    region = region.intersected(QRect(QPoint(0, 0), win->size()));
    new ScreencopyFrameV1(self, frameRes, win, region, overlayCursor != 0);
}

void ScreencopyManagerV1::onDestroyManager(wl_client *, wl_resource *resource) {
    wl_resource_destroy(resource);
}

// -- frame -------------------------------------------------------------

static const struct zwlr_screencopy_frame_v1_interface frameImpl = {
    .copy             = ScreencopyFrameV1::onCopy,
    .destroy          = ScreencopyFrameV1::onDestroyFrame,
    .copy_with_damage = ScreencopyFrameV1::onCopyWithDamage,
};

ScreencopyFrameV1::ScreencopyFrameV1(ScreencopyManagerV1 *manager, wl_resource *resource,
                                     QQuickWindow *window, const QRect &region, bool overlayCursor)
    : QObject(manager)
    , m_manager(manager)
    , m_resource(resource)
    , m_window(window)
    , m_region(region)
    , m_overlayCursor(overlayCursor) {
    wl_resource_set_implementation(resource, &frameImpl, this, &resourceDestroyed);
    m_width  = region.width();
    m_height = region.height();
    m_stride = m_width * 4;
    // wl_shm only supports advertising one format event here; v3 also
    // sends linux_dmabuf + buffer_done. We skip dmabuf and just emit
    // buffer + buffer_done so clients pick the shm path.
    sendBufferEvents();
}

ScreencopyFrameV1::~ScreencopyFrameV1() = default;

void ScreencopyFrameV1::sendBufferEvents() {
    zwlr_screencopy_frame_v1_send_buffer(m_resource, kShmFormat, m_width, m_height, m_stride);
    zwlr_screencopy_frame_v1_send_buffer_done(m_resource);
}

void ScreencopyFrameV1::onCopy(wl_client *, wl_resource *resource, wl_resource *buffer) {
    auto *self = static_cast<ScreencopyFrameV1 *>(wl_resource_get_user_data(resource));
    self->performCopy(buffer, false);
}

void ScreencopyFrameV1::onCopyWithDamage(wl_client *, wl_resource *resource, wl_resource *buffer) {
    auto *self = static_cast<ScreencopyFrameV1 *>(wl_resource_get_user_data(resource));
    // Marathon doesn't track per-region damage from app surfaces for
    // thumbnails — fall through to a full copy. The damage event the
    // protocol expects before ready is sent as the full frame box.
    self->performCopy(buffer, true);
}

void ScreencopyFrameV1::performCopy(wl_resource *buffer, bool withDamage) {
    if (m_used) {
        wl_resource_post_error(m_resource, ZWLR_SCREENCOPY_FRAME_V1_ERROR_ALREADY_USED,
                               "frame already used");
        return;
    }
    m_used = true;

    if (!m_window) {
        sendFailed();
        return;
    }

    // Grab the QQuickWindow's current frame as a QImage. This pulls
    // from the GPU on the main thread but only fires when the client
    // explicitly asks for a thumbnail — Active Frames throttles to 1 Hz.
    QImage frame = m_window->grabWindow();
    if (frame.isNull()) {
        sendFailed();
        return;
    }

    // Crop to the requested region and convert to the wire format. QImage
    // copy + convertToFormat gives us packed XRGB8888 (RGB32 on little
    // endian) with no padding.
    if (m_region != QRect(QPoint(0, 0), frame.size()))
        frame = frame.copy(m_region);
    if (frame.format() != QImage::Format_RGB32)
        frame.convertTo(QImage::Format_RGB32);

    // Map the client's wl_shm buffer and memcpy row by row. The client
    // is required to allocate width*4 stride; we wrote that in the
    // buffer event, so we can trust it here.
    wl_shm_buffer *shm = wl_shm_buffer_get(buffer);
    if (!shm) {
        sendFailed();
        return;
    }
    const uint32_t bufWidth  = wl_shm_buffer_get_width(shm);
    const uint32_t bufHeight = wl_shm_buffer_get_height(shm);
    const uint32_t bufStride = wl_shm_buffer_get_stride(shm);
    const uint32_t bufFormat = wl_shm_buffer_get_format(shm);
    if (bufWidth != m_width || bufHeight != m_height || bufFormat != kShmFormat) {
        wl_resource_post_error(m_resource, ZWLR_SCREENCOPY_FRAME_V1_ERROR_INVALID_BUFFER,
                               "buffer attributes don't match advertised values");
        return;
    }

    wl_shm_buffer_begin_access(shm);
    auto *dst = static_cast<uchar *>(wl_shm_buffer_get_data(shm));
    for (uint32_t y = 0; y < m_height; ++y) {
        const uchar *src = frame.constScanLine(y);
        memcpy(dst + y * bufStride, src, std::min<size_t>(bufStride, frame.bytesPerLine()));
    }
    wl_shm_buffer_end_access(shm);

    // QImage rows are top-to-bottom; that's the screencopy default.
    // No y_invert flag needed.
    zwlr_screencopy_frame_v1_send_flags(m_resource, 0);

    if (withDamage) {
        zwlr_screencopy_frame_v1_send_damage(m_resource, 0, 0, m_width, m_height);
    }

    sendReady();
}

void ScreencopyFrameV1::sendReady() {
    const qint64   ns     = QDateTime::currentMSecsSinceEpoch() * 1000000LL;
    const uint64_t sec    = ns / 1000000000LL;
    const uint32_t tvSec  = static_cast<uint32_t>(sec);
    const uint32_t tvSecH = static_cast<uint32_t>(sec >> 32);
    const uint32_t tvNsec = static_cast<uint32_t>(ns % 1000000000LL);
    zwlr_screencopy_frame_v1_send_ready(m_resource, tvSecH, tvSec, tvNsec);
}

void ScreencopyFrameV1::sendFailed() {
    zwlr_screencopy_frame_v1_send_failed(m_resource);
}

void ScreencopyFrameV1::onDestroyFrame(wl_client *, wl_resource *resource) {
    wl_resource_destroy(resource);
}

void ScreencopyFrameV1::resourceDestroyed(wl_resource *resource) {
    auto *self = static_cast<ScreencopyFrameV1 *>(wl_resource_get_user_data(resource));
    if (self)
        self->deleteLater();
}
