// SPDX-FileCopyrightText: 2018, 2019, 2021 Igalia S.L
// SPDX-FileCopyrightText: 2018, 2019 Zodiac Inflight Innovations
// SPDX-FileCopyrightText: 2026 Atlantic Browser contributors (atlantic-engine qt5-plugin)
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "viewbackend.h"

#include <ctime>

#include "directsurface.h"

#include <QElapsedTimer>

#include "pacificwebview.h"

#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

#include <QGuiApplication>
#include <QHoverEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <QQuickWindow>
#include <QTimer>
#include <QTouchEvent>
#include <QVarLengthArray>
#include <QWheelEvent>

#include <cmath>
#include <cstring>

#include <glib.h>
#include <wayland-server.h>
#include <wpe/wpe.h>

namespace {

    PFNGLEGLIMAGETARGETTEXTURE2DOESPROC s_imageTargetTexture2DOES = nullptr;
    EGLDisplay                          s_display                 = EGL_NO_DISPLAY;
    int                                 s_displayState            = 0; // 0 untried, 1 ok, -1 failed

    // Frame acknowledgement (PACIFIC_FRAME_ACK):
    //   stock   ack after Qt rendered a frame that sampled the web frame; the
    //           WebProcess composites in lock-step with Qt, so every web frame
    //           costs two vsyncs (55 web frames/s on the 90 Hz Jolla Phone).
    //   sample  ack as soon as Qt samples the frame on the render
    //           thread, so the WebProcess composites its next frame while Qt
    //           draws and presents this one (WebKit's own Qt view does this):
    //           one acknowledgement per frame Qt shows. WebKit's scrolling steps
    //           once per acknowledgement (engine patch 0007), as with the direct
    //           path. Flinging with the toolbar up: 84-87 web frames/s, evenly
    //           stepped.
    //   pipeline one frame of credit: a frame arriving to an empty slot is
    //           acknowledged at once, so the next one composites while this one
    //           waits for Qt; one arriving while a frame still waits replaces it
    //           and is acknowledged when Qt samples it. With patch 0007 the
    //           WebProcess composited 134-149 frames/s that Qt sampled 87 of,
    //           each a scroll step on: shown frames moved one step or two (step
    //           ratio spread 1.0 against 0.4-0.7 with sample).
    //   eager   ack on arrival; the WebProcess free-runs and Qt samples the newest
    //           frame (Atlantic measured smoother scrolling under a slow QML scene,
    //           and a flood of frames when Qt stalls).
    //   queue   (default) one frame of slack, paced to the display (triple
    //           buffering, as Android and Chrome): frames wait in a queue of two
    //           and are shown in order, one per Qt frame, none dropped. A frame
    //           arriving with room behind it is acknowledged at once; one that
    //           fills the queue is acknowledged when Qt takes the frame ahead of
    //           it. WebKit keeps one frame ahead, so a frame that takes it a
    //           little longer no longer misses Qt's next sync, and still steps
    //           its scrolling once per shown frame (engine patch 0007).
    enum class AckMode {
        Stock,
        Sample,
        Pipeline,
        Eager,
        Queue
    };
    AckMode ackMode() {
        static const AckMode mode = [] {
            const QByteArray v = qgetenv("PACIFIC_FRAME_ACK");
            if (v == "eager")
                return AckMode::Eager;
            if (v == "stock")
                return AckMode::Stock;
            if (v == "sample")
                return AckMode::Sample;
            if (v == "pipeline")
                return AckMode::Pipeline;
            return AckMode::Queue;
        }();
        return mode;
    }

    // Pacing of acknowledgements for a headless view, which nobody looks at.
    constexpr int                                    kHeadlessFrameMs = 100;

    const wpe_view_backend_exportable_fdo_egl_client s_exportableClient = {
        nullptr, // export_egl_image (deprecated)
        [](void *data, struct wpe_fdo_egl_exported_image *image) {
            static_cast<ViewBackend *>(data)->displayImagePublic(image);
        },
        // wl_shm buffers: WPEBackend-fdo calls this, unconditionally, when the
        // WebProcess commits a software-rendered buffer. Leaving it null crashed
        // the UI process inside the Wayland dispatch (wl_closure_invoke).
        [](void *data, struct wpe_fdo_shm_exported_buffer *buffer) {
            static_cast<ViewBackend *>(data)->displayShmPublic(buffer);
        },
        nullptr,
        nullptr,
    };

} // namespace

// Lets the C callback table above reach the private member.
void ViewBackend::displayImagePublic(struct wpe_fdo_egl_exported_image *image) {
    displayImage(image);
}

bool ViewBackend::initializeDisplay(EGLDisplay display) {
    if (s_displayState != 0)
        return s_displayState > 0;
    if (display == EGL_NO_DISPLAY) {
        qWarning("Pacific WebView: no EGL display (is Qt Quick running on the OpenGL RHI?)");
        return false;
    }
    s_displayState = -1;
    // Qt has initialised the display already; a second eglInitialize only
    // bumps its reference count.
    if (eglInitialize(display, nullptr, nullptr) == EGL_FALSE) {
        qWarning("Pacific WebView: eglInitialize failed: 0x%x", eglGetError());
        return false;
    }
    const char *extensions = eglQueryString(display, EGL_EXTENSIONS);
    // libhybris shares frames through EGL_WL_bind_wayland_display (android
    // wlegl buffers); desktop Mesa dropped it, and WPEBackend-fdo then offers
    // linux-dmabuf instead, imported with EGL_EXT_image_dma_buf_import.
    const bool bindDisplay = extensions && strstr(extensions, "EGL_WL_bind_wayland_display");
    const bool dmabuf      = extensions && strstr(extensions, "EGL_EXT_image_dma_buf_import");
    if (!bindDisplay && !dmabuf)
        qWarning("Pacific WebView: EGL has neither EGL_WL_bind_wayland_display nor dma-buf import; "
                 "pages cannot be shown");
    else if (qEnvironmentVariableIsSet("PACIFIC_DEBUG"))
        qInfo("Pacific WebView: frames via %s",
              bindDisplay ? "EGL_WL_bind_wayland_display" : "linux-dmabuf");
    wpe_loader_init("libWPEBackend-fdo-1.0.so.1");
    if (!wpe_fdo_initialize_for_egl_display(display)) {
        qWarning("Pacific WebView: wpe_fdo_initialize_for_egl_display failed");
        return false;
    }
    s_imageTargetTexture2DOES = reinterpret_cast<PFNGLEGLIMAGETARGETTEXTURE2DOESPROC>(
        eglGetProcAddress("glEGLImageTargetTexture2DOES"));
    s_display      = display;
    s_displayState = 1;
    return true;
}

bool ViewBackend::displayInitialized() {
    return s_displayState > 0;
}

EGLDisplay ViewBackend::display() {
    return s_display;
}

// PACIFIC_DEBUG_FPS: once a second while frames arrive, web frames per
// second, the longest gap between two, and where a frame's time goes: from
// our acknowledgement to the WebProcess's next frame (its compositing), and
// from a frame's arrival to Qt sampling it (our side), as averages.
namespace FrameStats {
    static const bool    enabled = qEnvironmentVariableIsSet("PACIFIC_DEBUG_FPS");
    static QElapsedTimer clock;
    static qint64        ackAt = -1, arrivedAt = -1;
    static qint64        webSum = 0, qtSum = 0, gapMax = 0, lastArrival = -1, windowStart = -1;
    static int           frames = 0, webN = 0, qtN = 0, usedN = 0;
    // Frames released without Qt ever sampling them, by where: replaced in the
    // queue slot (WebKit composited past its credit), or replaced as the
    // pending frame (shown nowhere).
    static int    droppedQueued = 0, droppedPending = 0;
    static qint64 now() {
        if (!clock.isValid())
            clock.start();
        return clock.nsecsElapsed() / 1000;
    }
    static void acked() {
        if (enabled)
            ackAt = now();
    }
    static int  sampledN = 0;
    static void sampled() {
        if (!enabled)
            return;
        // Every frame Qt shows counts. Only the newest arrival's time is kept,
        // so with a frame queued behind another (queue mode) the wait is
        // measured for the frame that arrived last; counting only the timed
        // ones made "shown" read low, as if frames were dropped.
        ++sampledN;
        if (arrivedAt < 0)
            return;
        qtSum += now() - arrivedAt;
        ++qtN;
        arrivedAt = -1;
    }
    // Direct composition: the compositor used a frame (its frame callback),
    // so how many frames a second reach the screen.
    // PACIFIC_DEBUG_FRAMES: a line per web frame and per frame the compositor
    // used, stamped with CLOCK_MONOTONIC in ms (the WebProcess's clock), to find
    // stalls inside a scroll.
    static const bool perFrame = qEnvironmentVariableIsSet("PACIFIC_DEBUG_FRAMES");
    static double     monotonicMs() {
        timespec ts{};
        clock_gettime(CLOCK_MONOTONIC, &ts);
        return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
    }
    static void used() {
        if (perFrame)
            qInfo("Pacific frame used t=%.1f", monotonicMs());
        if (enabled)
            ++usedN;
    }
    static void arrived() {
        if (perFrame)
            qInfo("Pacific frame arrived t=%.1f", monotonicMs());
        if (!enabled)
            return;
        const qint64 t = now();
        if (ackAt >= 0) {
            webSum += t - ackAt;
            ++webN;
            ackAt = -1;
        }
        if (lastArrival >= 0)
            gapMax = qMax(gapMax, t - lastArrival);
        lastArrival = t;
        arrivedAt   = t;
        if (windowStart < 0)
            windowStart = t;
        ++frames;
        if (t - windowStart >= 1000000) {
            qInfo("Pacific WebView: %d web frames/s, %d shown, %d used, dropped %d queued %d "
                  "pending, longest gap %lld ms, ack->frame %.1f ms, frame->sample %.1f ms",
                  static_cast<int>(frames * 1000000LL / (t - windowStart)),
                  static_cast<int>(sampledN * 1000000LL / (t - windowStart)),
                  static_cast<int>(usedN * 1000000LL / (t - windowStart)), droppedQueued,
                  droppedPending, gapMax / 1000, webN ? webSum / 1000.0 / webN : 0.0,
                  qtN ? qtSum / 1000.0 / qtN : 0.0);
            windowStart = t;
            frames = webN = qtN = sampledN = usedN = droppedQueued = droppedPending = 0;
            webSum = qtSum = gapMax = 0;
        }
    }
}

ViewBackend::ViewBackend(const QSize &physicalSize, qreal deviceScale, PacificWebView *view)
    : m_view(view)
    , m_deviceScale(deviceScale > 0 ? deviceScale : 1.0)
    , m_size(physicalSize.isValid() && !physicalSize.isEmpty() ? physicalSize : QSize(1080, 2400)) {
    m_exportable = wpe_view_backend_exportable_fdo_egl_create(
        &s_exportableClient, this, std::lround(m_size.width() / m_deviceScale),
        std::lround(m_size.height() / m_deviceScale));

    wpe_view_backend_add_activity_state(backend(),
                                        wpe_view_activity_state_visible |
                                            wpe_view_activity_state_focused |
                                            wpe_view_activity_state_in_window);

    // Without a fullscreen handler, wpe_view_backend_platform_set_fullscreen()
    // fails and WebKit leaves DOM fullscreen again at once (Atlantic: video
    // fullscreen "exits after a second").
    wpe_view_backend_set_fullscreen_handler(
        backend(),
        [](void *data, bool enable) -> bool {
            return static_cast<ViewBackend *>(data)->handleFullscreen(enable);
        },
        this);
}

ViewBackend::~ViewBackend() {
    // First: images Lipstick still read go back to WebKit as it goes.
    m_direct.reset();
    releaseImage(m_pendingImage);
    releaseImage(m_queuedImage);
    releaseImage(m_committedImage);
    releaseImage(m_directQueued);
    for (auto *image : std::as_const(m_retiredImages))
        releaseImage(image);
    wpe_view_backend_exportable_fdo_destroy(m_exportable);
    // The texture belongs to Qt's context; the scene graph node that wraps it
    // owns and deletes it (PacificWebView::updatePaintNode).
}

struct wpe_view_backend *ViewBackend::backend() const {
    return wpe_view_backend_exportable_fdo_get_view_backend(m_exportable);
}

void ViewBackend::releaseImage(struct wpe_fdo_egl_exported_image *&image) {
    // An image whose buffer Lipstick still shows goes back when it lets go.
    if (image && m_direct && m_direct->deferRelease(image)) {
        image = nullptr;
        return;
    }
    if (image && m_exportable)
        wpe_view_backend_exportable_fdo_egl_dispatch_release_exported_image(m_exportable, image);
    image = nullptr;
}

void ViewBackend::frameComplete() {
    FrameStats::acked();
    if (m_exportable)
        wpe_view_backend_exportable_fdo_dispatch_frame_complete(m_exportable);
}

int32_t ViewBackend::toWebKit(qreal itemCoordinate) const {
    // libwpe input is in device pixels: WPE's WebEventFactory divides by the
    // device scale factor itself (dividing here too put taps scale-times
    // off once the scale was not 1).
    return static_cast<int32_t>(std::lround(itemCoordinate * m_itemToPhysical));
}

void ViewBackend::resize(const QSize &physicalSize) {
    if (!physicalSize.isValid() || physicalSize.isEmpty() || physicalSize == m_size)
        return;
    m_size = physicalSize;
    wpe_view_backend_dispatch_set_size(backend(), std::lround(m_size.width() / m_deviceScale),
                                       std::lround(m_size.height() / m_deviceScale));
}

void ViewBackend::setDeviceScale(qreal scale) {
    if (scale <= 0 || qFuzzyCompare(scale, m_deviceScale))
        return;
    m_deviceScale = scale;
    applyDeviceScale();
}

void ViewBackend::applyDeviceScale() {
    // Order matters: WebKit sizes its drawing area from size x scale, so the
    // scale goes first, then the size in logical units.
    wpe_view_backend_dispatch_set_device_scale_factor(backend(), static_cast<float>(m_deviceScale));
    wpe_view_backend_dispatch_set_size(backend(), std::lround(m_size.width() / m_deviceScale),
                                       std::lround(m_size.height() / m_deviceScale));
}

void ViewBackend::setHeadless(bool headless) {
    // The latest frame is kept either way: a view shown (or promoted) later
    // draws it at once, even when the page has nothing new to paint.
    m_headless = headless;
}

void ViewBackend::setActivityState(bool visible, bool focused) const {
    const uint32_t visibleFlag = wpe_view_activity_state_visible;
    const uint32_t focusedFlag = wpe_view_activity_state_focused;
    if (visible)
        wpe_view_backend_add_activity_state(backend(), visibleFlag);
    else
        wpe_view_backend_remove_activity_state(backend(), visibleFlag);
    if (focused)
        wpe_view_backend_add_activity_state(backend(), focusedFlag);
    else
        wpe_view_backend_remove_activity_state(backend(), focusedFlag);
}

QSize ViewBackend::currentImageSize() const {
    auto *image = m_pendingImage ? m_pendingImage : m_committedImage;
    if (!image)
        return {};
    return {static_cast<int>(wpe_fdo_egl_exported_image_get_width(image)),
            static_cast<int>(wpe_fdo_egl_exported_image_get_height(image))};
}

QSize ViewBackend::committedImageSize() const {
    return m_committedImage ? imageSize(m_committedImage) : QSize();
}

unsigned ViewBackend::texture(QOpenGLContext *context) {
    // Render thread, with the GUI thread blocked in the scene graph sync.
    if (m_pendingImage) {
        if (m_committedImage)
            m_retiredImages.append(m_committedImage);
        m_committedImage = m_pendingImage;
        m_pendingImage   = nullptr;
        m_sampled        = true;
        FrameStats::sampled();
        m_sampledAcked = m_pendingAcked;
        m_pendingAcked = false;
        if (ackMode() == AckMode::Queue) {
            // The frame behind it moves up; there is room again, so it is
            // acknowledged now, and Qt draws it at its next frame.
            m_sampledAcked = true;
            if (m_queuedImage) {
                m_pendingImage = m_queuedImage;
                m_queuedImage  = nullptr;
                m_pendingAcked = true;
                if (m_view) {
                    QTimer::singleShot(0, m_view, [view = m_view] {
                        if (!view)
                            return;
                        view->dispatchEarlyAck();
                        view->update();
                        if (QQuickWindow *window = view->window())
                            window->update();
                    });
                }
            }
        } else if (!m_sampledAcked &&
                   (ackMode() == AckMode::Sample || ackMode() == AckMode::Pipeline) && m_view) {
            m_sampledAcked = true;
            QTimer::singleShot(0, m_view, [view = m_view] {
                if (view)
                    view->dispatchEarlyAck();
            });
        }
    }
    auto *image = m_committedImage;
    if (!image || !context || !s_imageTargetTexture2DOES)
        return 0;

    QOpenGLFunctions *gl       = context->functions();
    void             *eglImage = wpe_fdo_egl_exported_image_get_egl_image(image);
    const QSize       size(static_cast<int>(wpe_fdo_egl_exported_image_get_width(image)),
                           static_cast<int>(wpe_fdo_egl_exported_image_get_height(image)));
    // Zero copy: the exported EGLImage is a texture's storage. Each of
    // WebKit's buffers keeps its texture while it is in use; a new size
    // makes new buffers. A texture unused for a few frames goes: a buffer
    // dropped (a new WebProcess after a navigation, a discarded page) may
    // have its image's address taken by a new one, which must not be shown
    // as the old one's. WebKit cycles through at most four buffers, so
    // those in use never age out.
    ++m_textureFrames;
    if (size != m_imageTexturesSize) {
        for (ImageTexture &t : m_imageTextures) {
            if (t.texture)
                gl->glDeleteTextures(1, &t.texture);
            t = {};
        }
        m_imageTexturesSize = size;
    }
    constexpr quint64 maxAge = 12;
    ImageTexture     *found  = nullptr;
    ImageTexture     *free   = nullptr;
    for (ImageTexture &t : m_imageTextures) {
        if (t.texture && t.image == eglImage) {
            found = &t;
        } else if (t.texture && m_textureFrames - t.usedAt > maxAge) {
            gl->glDeleteTextures(1, &t.texture);
            t = {};
        }
        if (!t.texture && !free)
            free = &t;
    }
    if (!found) {
        // A free slot, else the least recently shown.
        found = free;
        if (!found) {
            found = &m_imageTextures[0];
            for (ImageTexture &t : m_imageTextures) {
                if (t.usedAt < found->usedAt)
                    found = &t;
            }
            gl->glDeleteTextures(1, &found->texture);
            *found = {};
        }
        gl->glGenTextures(1, &found->texture);
        gl->glActiveTexture(GL_TEXTURE0);
        gl->glBindTexture(GL_TEXTURE_2D, found->texture);
        gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        s_imageTargetTexture2DOES(GL_TEXTURE_2D, static_cast<GLeglImageOES>(eglImage));
        gl->glBindTexture(GL_TEXTURE_2D, 0);
        found->image = eglImage;
    }
    found->usedAt = m_textureFrames;
    m_textureId   = found->texture;
    return m_textureId;
}

// GUI thread, queued from texture(): the sampled frame is acknowledged.
void ViewBackend::dispatchEarlyAck() {
    frameComplete();
}

// GUI thread, after Qt swapped a frame.
void ViewBackend::didRenderFrame() {
    if (!m_exportable)
        return;
    // Replaced images are no longer drawn: the frame that replaced them has
    // been rendered (a sync happens only after the previous swap).
    for (auto *image : std::as_const(m_retiredImages))
        releaseImage(image);
    m_retiredImages.clear();
    // A frame of the subsurface's size drawn: the subsurface may take over.
    if (m_directWanted && !directShown())
        applyDirect();
    if (m_sampled) {
        m_sampled = false;
        if (!m_sampledAcked)
            frameComplete();
        m_sampledAcked = false;
    }
    if (m_frameUpdateRequested) {
        m_frameUpdateRequested = false;
        if (ackMode() != AckMode::Eager)
            frameComplete();
    }
}

void ViewBackend::displayShmPublic(struct wpe_fdo_shm_exported_buffer *buffer) {
    displayShm(buffer);
}

void ViewBackend::displayShm(struct wpe_fdo_shm_exported_buffer *buffer) {
    struct wl_shm_buffer *shm = wpe_fdo_shm_exported_buffer_get_shm_buffer(buffer);
    QImage                frame;
    if (shm) {
        wl_shm_buffer_begin_access(shm);
        const int      width  = wl_shm_buffer_get_width(shm);
        const int      height = wl_shm_buffer_get_height(shm);
        const int      stride = wl_shm_buffer_get_stride(shm);
        const uint32_t format = wl_shm_buffer_get_format(shm);
        const auto    *pixels = static_cast<const uchar *>(wl_shm_buffer_get_data(shm));
        // ARGB8888/XRGB8888 are little-endian BGRA in memory: QImage's
        // (A)RGB32. WebKit draws premultiplied alpha.
        const QImage::Format qtFormat = format == WL_SHM_FORMAT_XRGB8888 ? QImage::Format_RGB32 :
            format == WL_SHM_FORMAT_ARGB8888 ? QImage::Format_ARGB32_Premultiplied :
                                               QImage::Format_Invalid;
        if (pixels && width > 0 && height > 0 && qtFormat != QImage::Format_Invalid)
            frame = QImage(pixels, width, height, stride, qtFormat).copy();
        else
            qWarning("Pacific WebView: unsupported wl_shm buffer (format 0x%x)", format);
        wl_shm_buffer_end_access(shm);
    }
    static bool logged = false;
    if (!logged && qEnvironmentVariableIsSet("PACIFIC_DEBUG")) {
        logged = true;
        qInfo("Pacific WebView: software frames (wl_shm, %dx%d)", frame.width(), frame.height());
    }
    // The pixels are ours now; the WebProcess can reuse the buffer.
    if (m_exportable)
        wpe_view_backend_exportable_fdo_egl_dispatch_release_shm_exported_buffer(m_exportable,
                                                                                 buffer);
    if (frame.isNull()) {
        frameComplete();
        return;
    }
    m_shmFrame = frame;
    m_shmNew   = true;
    if (scheduleOrDrop() && ackMode() == AckMode::Eager)
        frameComplete();
}

bool ViewBackend::takeShmFrame(QImage *frame) {
    if (!m_shmNew)
        return false;
    m_shmNew = false;
    *frame   = m_shmFrame;
    // A frame kept while hidden was acknowledged then.
    m_frameUpdateRequested = !m_pendingAcked;
    m_pendingAcked         = false;
    return true;
}

// Requests a Qt frame for a new web frame; false (and the frame paced and
// acknowledged without drawing) when nothing will show it.
bool ViewBackend::canShowFrames() const {
    return !m_headless && m_view && m_view->window() && m_view->isVisible();
}

void ViewBackend::dropQueuedImage() {
    // A queued frame was never acknowledged: WebKit waits for it.
    if (!m_queuedImage)
        return;
    releaseImage(m_queuedImage);
    frameComplete();
}

bool ViewBackend::scheduleOrDrop() {
    QQuickWindow *window = m_view ? m_view->window() : nullptr;
    if (m_headless || !window || !m_view->isVisible()) {
        // Nothing draws the frame now: it is kept (see displayImage) and
        // acknowledged on a slow clock, so a hidden page cannot spin.
        m_pendingAcked = true;
        if (!m_headlessAckPending) {
            m_headlessAckPending = true;
            QTimer::singleShot(kHeadlessFrameMs, m_view, [this, view = m_view] {
                if (!view)
                    return;
                m_headlessAckPending = false;
                frameComplete();
            });
        }
        return false;
    }
    m_pendingAcked = false;
    m_view->update();
    QMetaObject::invokeMethod(window, &QQuickWindow::update, Qt::QueuedConnection);
    return true;
}

bool ViewBackend::directShown() const {
    return m_direct && m_direct->isShown();
}

QSize ViewBackend::imageSize(struct wpe_fdo_egl_exported_image *image) {
    return {static_cast<int>(wpe_fdo_egl_exported_image_get_width(image)),
            static_cast<int>(wpe_fdo_egl_exported_image_get_height(image))};
}

bool ViewBackend::sizeFits(QSize frame, QSize view) {
    return std::abs(frame.width() - view.width()) <= 2 &&
        std::abs(frame.height() - view.height()) <= 2;
}

void ViewBackend::setDirect(bool wanted, QWindow *window, const QRect &physicalRect) {
    if (!DirectSurface::enabled())
        return;
    m_directWanted = wanted;
    m_directWindow = window;
    m_directRect   = physicalRect;
    applyDirect();
}

void ViewBackend::applyDirect(bool forceHide) {
    bool wanted = m_directWanted && !forceHide && m_committedImage &&
        sizeFits(imageSize(m_committedImage), m_directRect.size());
    const QRect physicalRect = m_directRect;
    QWindow    *window       = m_directWindow;
    if (wanted && !m_direct)
        m_direct = std::make_unique<DirectSurface>(
            [this] {
                FrameStats::used();
                if (m_directQueued) {
                    auto *image    = m_directQueued;
                    m_directQueued = nullptr;
                    presentDirect(image);
                    return;
                }
                if (!m_directAckPending)
                    return;
                m_directAckPending = false;
                frameComplete();
            },
            [this](struct wpe_fdo_egl_exported_image *image) {
                if (m_exportable)
                    wpe_view_backend_exportable_fdo_egl_dispatch_release_exported_image(
                        m_exportable, image);
            });
    if (!m_direct)
        return;
    m_direct->setGeometry(physicalRect);
    if (wanted && !m_direct->ensureCreated(window))
        wanted = false;
    const bool wasShown = m_direct->isShown();
    if (wanted && !wasShown)
        dropQueuedImage();
    m_direct->setShown(wanted);
    if (wasShown && !wanted) {
        // Back to Qt's path: it draws the newest frame, and a frame the
        // hidden subsurface will never be called back for is acknowledged.
        if (m_directQueued) {
            releaseImage(m_pendingImage);
            m_pendingImage     = m_directQueued;
            m_directQueued     = nullptr;
            m_pendingAcked     = true;
            m_directAckPending = false;
            frameComplete();
        }
        if (m_directAckPending) {
            m_directAckPending = false;
            frameComplete();
        }
        if (m_view)
            m_view->update();
    } else if (!wasShown && wanted && m_committedImage) {
        m_direct->present(m_committedImage);
        m_directAckPending = true;
    }
}

void ViewBackend::displayImage(struct wpe_fdo_egl_exported_image *image) {
    FrameStats::arrived();
    m_serials.insert(image, ++m_arrivedSerial);
    // Only the last few frames can still be pending or on screen.
    if (m_serials.size() > 16)
        m_serials.removeIf([this](const auto &it) { return it.value() + 8 < m_arrivedSerial; });
    if (m_view)
        m_view->webFrameArrived(imageSize(image));
    if (directShown() && !sizeFits(imageSize(image), m_directRect.size())) {
        // The page was resized: Qt's path draws this frame, and the
        // subsurface comes back once one of its size is drawn.
        applyDirect(true);
    }
    if (directShown()) {
        // Paced: a frame that arrives before the compositor has used the
        // last one waits for its frame callback, unacknowledged, so WebKit
        // composites no faster than the panel shows.
        if (directAck() == DirectAck::Paced && m_direct->framePending()) {
            releaseImage(m_directQueued);
            m_directQueued = image;
            return;
        }
        presentDirect(image);
        return;
    }
    // A GL frame supersedes a waiting software one. Only the newest frame is
    // kept, shown or not: a view created hidden draws its page as soon as it
    // is shown.
    m_shmNew   = false;
    m_shmFrame = QImage();
    if (ackMode() == AckMode::Queue && m_pendingImage && canShowFrames()) {
        // Behind the frame Qt has yet to draw, unacknowledged: its
        // acknowledgement comes when Qt takes the one ahead (texture()).
        if (m_queuedImage) {
            // WebKit composited past its credit: the newest replaces the
            // queued one, whose acknowledgement it inherits.
            ++FrameStats::droppedQueued;
            releaseImage(m_queuedImage);
        }
        m_queuedImage = image;
        return;
    }
    const bool slotWasEmpty = !m_pendingImage;
    if (m_pendingImage)
        ++FrameStats::droppedPending;
    releaseImage(m_pendingImage);
    m_pendingImage = image;
    if (scheduleOrDrop() &&
        (ackMode() == AckMode::Eager ||
         ((ackMode() == AckMode::Pipeline || ackMode() == AckMode::Queue) && slotWasEmpty))) {
        frameComplete();
        m_pendingAcked = true;
    }
}

ViewBackend::DirectAck ViewBackend::directAck() {
    static const DirectAck mode = [] {
        const QByteArray v = qgetenv("PACIFIC_DIRECT_ACK");
        return v == "callback" ? DirectAck::Callback :
            v == "present"     ? DirectAck::Present :
                                 DirectAck::Paced;
    }();
    return mode;
}

void ViewBackend::presentDirect(struct wpe_fdo_egl_exported_image *image) {
    // Straight to the compositor. A frame copied into the subsurface lets the
    // previous one go back at once; one whose buffer was handed over goes
    // back when Lipstick releases it (DirectSurface::deferRelease). It stays
    // the committed image for Qt's path if the subsurface hides.
    m_direct->present(image);
    releaseImage(m_pendingImage);
    releaseImage(m_committedImage);
    m_committedImage = image;
    FrameStats::sampled();
    // The next frame composites while the compositor shows this one (one
    // frame of credit). Callback waits for the subsurface's frame callback
    // before WebKit may composite the next.
    if (directAck() == DirectAck::Callback)
        m_directAckPending = true;
    else
        frameComplete();
}

bool ViewBackend::handleFullscreen(bool enable) {
    if (!m_view)
        return false;
    m_view->notifyFullscreenRequest(enable);
    return true;
}

uint32_t ViewBackend::modifiers() const {
    uint32_t                    mask = m_pointerModifiers;
    const Qt::KeyboardModifiers qt   = QGuiApplication::keyboardModifiers();
    if (qt & Qt::ShiftModifier)
        mask |= wpe_input_keyboard_modifier_shift;
    if (qt & Qt::ControlModifier)
        mask |= wpe_input_keyboard_modifier_control;
    if (qt & Qt::AltModifier)
        mask |= wpe_input_keyboard_modifier_alt;
    if (qt & Qt::MetaModifier)
        mask |= wpe_input_keyboard_modifier_meta;
    return mask;
}

void ViewBackend::dispatchHoverMove(QHoverEvent *event) {
    m_hovering                       = true;
    wpe_input_pointer_event wpeEvent = {wpe_input_pointer_event_type_motion,
                                        static_cast<uint32_t>(event->timestamp()),
                                        toWebKit(event->position().x()),
                                        toWebKit(event->position().y()),
                                        m_pressedButton,
                                        m_pressedButton ? 1U : 0U,
                                        modifiers()};
    wpe_view_backend_dispatch_pointer_event(backend(), &wpeEvent);
}

void ViewBackend::dispatchHoverLeave() {
    m_hovering = false;
}

static uint32_t wpeButton(Qt::MouseButton button, uint32_t *modifier) {
    switch (button) {
        case Qt::LeftButton: *modifier = wpe_input_pointer_modifier_button1; return 1;
        case Qt::RightButton: *modifier = wpe_input_pointer_modifier_button2; return 2;
        case Qt::MiddleButton: *modifier = wpe_input_pointer_modifier_button3; return 3;
        default: *modifier = 0; return 0;
    }
}

void ViewBackend::dispatchMousePress(QMouseEvent *event) {
    uint32_t       modifier = 0;
    const uint32_t button   = wpeButton(event->button(), &modifier);
    m_pressedButton         = button;
    m_pointerModifiers |= modifier;
    wpe_input_pointer_event wpeEvent = {wpe_input_pointer_event_type_button,
                                        static_cast<uint32_t>(event->timestamp()),
                                        toWebKit(event->position().x()),
                                        toWebKit(event->position().y()),
                                        button,
                                        1,
                                        modifiers()};
    wpe_view_backend_dispatch_pointer_event(backend(), &wpeEvent);
}

void ViewBackend::dispatchMouseRelease(QMouseEvent *event) {
    uint32_t       modifier = 0;
    const uint32_t button   = wpeButton(event->button(), &modifier);
    m_pressedButton         = 0;
    m_pointerModifiers &= ~modifier;
    wpe_input_pointer_event wpeEvent = {wpe_input_pointer_event_type_button,
                                        static_cast<uint32_t>(event->timestamp()),
                                        toWebKit(event->position().x()),
                                        toWebKit(event->position().y()),
                                        button,
                                        0,
                                        modifiers()};
    wpe_view_backend_dispatch_pointer_event(backend(), &wpeEvent);
}

void ViewBackend::dispatchMouseMove(QMouseEvent *event) {
    wpe_input_pointer_event wpeEvent = {wpe_input_pointer_event_type_motion,
                                        static_cast<uint32_t>(event->timestamp()),
                                        toWebKit(event->position().x()),
                                        toWebKit(event->position().y()),
                                        m_pressedButton,
                                        m_pressedButton ? 1U : 0U,
                                        modifiers()};
    wpe_view_backend_dispatch_pointer_event(backend(), &wpeEvent);
}

void ViewBackend::dispatchWheel(QWheelEvent *event) {
    const QPoint            degrees  = event->angleDelta() / 8;
    wpe_input_axis_2d_event wpeEvent = {};
    // A flag combination libwpe defines as such (mask_2d | motion_smooth).
    wpeEvent.base.type = static_cast<
        wpe_input_axis_event_type>( // NOLINT(clang-analyzer-optin.core.EnumCastOutOfRange)
        wpe_input_axis_event_type_mask_2d | wpe_input_axis_event_type_motion_smooth);
    wpeEvent.base.time      = static_cast<uint32_t>(event->timestamp());
    wpeEvent.base.x         = toWebKit(event->position().x());
    wpeEvent.base.y         = toWebKit(event->position().y());
    wpeEvent.base.modifiers = modifiers();
    wpeEvent.x_axis         = degrees.x();
    wpeEvent.y_axis         = degrees.y();
    wpe_view_backend_dispatch_axis_event(backend(), &wpeEvent.base);
}

// XKB keysym for a key event without a native one. Maliit's soft keys and
// synthesised events have nativeVirtualKey() == 0, and passing the Qt key code
// to wpe_input_xkb_context_get_key_code (which wants a hardware code) turned
// every such key, Enter included, into keysym 0 (Atlantic).
static uint32_t keysymForQtKey(const QKeyEvent *event) {
    switch (event->key()) {
        case Qt::Key_Return:
        case Qt::Key_Enter: return 0xff0d;
        case Qt::Key_Backspace: return 0xff08;
        case Qt::Key_Tab: return 0xff09;
        case Qt::Key_Backtab: return 0xfe20;
        case Qt::Key_Escape: return 0xff1b;
        case Qt::Key_Delete: return 0xffff;
        case Qt::Key_Insert: return 0xff63;
        case Qt::Key_Left: return 0xff51;
        case Qt::Key_Up: return 0xff52;
        case Qt::Key_Right: return 0xff53;
        case Qt::Key_Down: return 0xff54;
        case Qt::Key_PageUp: return 0xff55;
        case Qt::Key_PageDown: return 0xff56;
        case Qt::Key_Home: return 0xff50;
        case Qt::Key_End: return 0xff57;
        default: break;
    }
    const QString text = event->text();
    if (!text.isEmpty()) {
        const uint32_t cp = text.at(0).isHighSurrogate() && text.size() > 1 ?
            QChar::surrogateToUcs4(text.at(0), text.at(1)) :
            text.at(0).unicode();
        if (cp >= 0x20 && cp < 0x100)
            return cp;
        if (cp >= 0x100)
            return 0x01000000 | cp;
    }
    return 0;
}

void ViewBackend::dispatchKey(QKeyEvent *event, bool pressed) const {
    uint32_t keysym = event->nativeVirtualKey();
    if (!keysym)
        keysym = keysymForQtKey(event);
    uint32_t              mods = 0;
    Qt::KeyboardModifiers qt   = event->modifiers();
    if (qt & Qt::ShiftModifier)
        mods |= wpe_input_keyboard_modifier_shift;
    if (qt & Qt::ControlModifier)
        mods |= wpe_input_keyboard_modifier_control;
    if (qt & Qt::MetaModifier)
        mods |= wpe_input_keyboard_modifier_meta;
    if (qt & Qt::AltModifier)
        mods |= wpe_input_keyboard_modifier_alt;
    wpe_input_keyboard_event wpeEvent = {static_cast<uint32_t>(event->timestamp()), keysym,
                                         event->nativeScanCode(), pressed, mods};
    wpe_view_backend_dispatch_keyboard_event(backend(), &wpeEvent);
}

void ViewBackend::dispatchTouch(QTouchEvent *event) {
    // A libwpe touch event describes one point transition. Qt batches
    // simultaneous transitions into one QTouchEvent, and WebCore drops a
    // touchstart that mixes a pressed point with never-announced stationary
    // ones, so serialise: one down/up per point plus one motion (Atlantic).
    const QList<QEventPoint> &points = event->points();
    if (points.isEmpty())
        return;
    const auto time = static_cast<uint32_t>(event->timestamp());

    auto       dispatchOne = [&](wpe_input_touch_event_type type, int mainId) {
        QVarLengthArray<wpe_input_touch_event_raw, 8> raw;
        for (const QEventPoint &point : points) {
            if (!m_announcedTouchIds.contains(point.id()))
                continue;
            const wpe_input_touch_event_type pointType =
                point.id() == mainId ? type : wpe_input_touch_event_type_motion;
            raw.append({pointType, time, point.id(), toWebKit(point.position().x()),
                        toWebKit(point.position().y())});
        }
        if (raw.isEmpty())
            return;
        wpe_input_touch_event wpeEvent = {
            raw.data(), static_cast<uint64_t>(raw.size()), type, mainId, time, modifiers()};
        wpe_view_backend_dispatch_touch_event(backend(), &wpeEvent);
    };

    if (event->type() == QEvent::TouchBegin)
        m_announcedTouchIds.clear();

    if (event->type() == QEvent::TouchCancel) {
        // libwpe has no cancel: end every announced point.
        for (const QEventPoint &point : points) {
            if (m_announcedTouchIds.contains(point.id()))
                dispatchOne(wpe_input_touch_event_type_up, point.id());
        }
        m_announcedTouchIds.clear();
        return;
    }

    for (const QEventPoint &point : points) {
        if (point.state() == QEventPoint::Pressed && !m_announcedTouchIds.contains(point.id())) {
            m_announcedTouchIds.insert(point.id());
            dispatchOne(wpe_input_touch_event_type_down, point.id());
        }
    }
    for (const QEventPoint &point : points) {
        if (point.state() == QEventPoint::Updated && m_announcedTouchIds.contains(point.id())) {
            dispatchOne(wpe_input_touch_event_type_motion, point.id());
            break;
        }
    }
    // TouchEnd releases every remaining point, whatever state it reports, or
    // the page keeps a phantom finger down (stuck long press).
    const bool releaseAll = event->type() == QEvent::TouchEnd;
    for (const QEventPoint &point : points) {
        if ((point.state() == QEventPoint::Released || releaseAll) &&
            m_announcedTouchIds.contains(point.id())) {
            dispatchOne(wpe_input_touch_event_type_up, point.id());
            m_announcedTouchIds.remove(point.id());
        }
    }
}

void ViewBackend::dispatchTap(const QPointF &itemPoint) const {
    // A primary-button click: WebKit turns it into trusted pointer, mouse and
    // click events, as reliably as a finger. (A synthesised touch pair is not
    // turned into a click by WPE's gesture handling when both halves arrive
    // in the same event-loop turn.)
    const auto              time   = static_cast<uint32_t>(g_get_monotonic_time() / 1000);
    const int32_t           x      = toWebKit(itemPoint.x());
    const int32_t           y      = toWebKit(itemPoint.y());
    wpe_input_pointer_event motion = {wpe_input_pointer_event_type_motion, time, x, y, 0, 0, 0};
    wpe_view_backend_dispatch_pointer_event(backend(), &motion);
    wpe_input_pointer_event press = {wpe_input_pointer_event_type_button, time + 1, x, y, 1, 1,
                                     wpe_input_pointer_modifier_button1};
    wpe_view_backend_dispatch_pointer_event(backend(), &press);
    wpe_input_pointer_event release = {
        wpe_input_pointer_event_type_button, time + 60, x, y, 1, 0, 0};
    wpe_view_backend_dispatch_pointer_event(backend(), &release);
}

void ViewBackend::dispatchContextClick(const QPointF &itemPoint) const {
    const auto              time   = static_cast<uint32_t>(g_get_monotonic_time() / 1000);
    const int32_t           x      = toWebKit(itemPoint.x());
    const int32_t           y      = toWebKit(itemPoint.y());
    wpe_input_pointer_event motion = {wpe_input_pointer_event_type_motion, time, x, y, 0, 0, 0};
    wpe_view_backend_dispatch_pointer_event(backend(), &motion);
    wpe_input_pointer_event press = {wpe_input_pointer_event_type_button, time + 1, x, y, 2, 1,
                                     wpe_input_pointer_modifier_button2};
    wpe_view_backend_dispatch_pointer_event(backend(), &press);
    wpe_input_pointer_event release = {
        wpe_input_pointer_event_type_button, time + 60, x, y, 2, 0, 0};
    wpe_view_backend_dispatch_pointer_event(backend(), &release);
}

void ViewBackend::redraw() {
    QQuickWindow *window = m_view ? m_view->window() : nullptr;
    if (!window || (!m_pendingImage && !m_committedImage && m_shmFrame.isNull()))
        return;
    if (!m_shmFrame.isNull())
        m_shmNew = true;
    m_view->update();
    QMetaObject::invokeMethod(window, &QQuickWindow::update, Qt::QueuedConnection);
}
