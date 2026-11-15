// SPDX-FileCopyrightText: 2018, 2019, 2021 Igalia S.L
// SPDX-FileCopyrightText: 2018, 2019 Zodiac Inflight Innovations
// SPDX-FileCopyrightText: 2026 Atlantic Browser contributors (atlantic-engine qt5-plugin)
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// The libwpe view backend of one web view: WPEBackend-fdo's exportable EGL
// backend. The WebProcess renders into a wl_egl_window on fdo's private
// Wayland server (hosted in this process); each finished frame arrives here
// as an EGLImage (EGL_WAYLAND_BUFFER_WL, which libhybris maps to an Android
// native buffer), is bound to a GL texture in Qt's scene-graph context and
// composited by Qt. No CPU copy.
//
// Qt 6 port of Atlantic's qt5-plugin WPEQtViewBackend (itself derived from
// Igalia's WPE Qt API). Dropped from the port: the direct-composite
// wl_subsurface path (parked in Atlantic; Lipstick keeps a Silica window on
// the base layer), the Adreno shader-priming program and the pipelined ack
// experiment (no measured gain on the Xperia 10 II).

#pragma once

#include <array>

#include <EGL/egl.h>
#include <EGL/eglext.h>

#include <QImage>
#include <QList>
#include <QRect>
#include <QPointer>
#include <QHash>
#include <QSet>
#include <QSize>
#include <QSizeF>
#include <QtGlobal>

#include <atomic>
#include <cstdint>

#include <wpe/fdo-egl.h>
#include <wpe/fdo.h>

class QHoverEvent;
class QKeyEvent;
class QMouseEvent;
class QOpenGLContext;
class QTouchEvent;
class QWheelEvent;
class PacificWebView;

class DirectSurface;
class QWindow;

class ViewBackend {
  public:
    // Initialises WPEBackend-fdo for the EGL display Qt renders with. Once per
    // process; later calls return the first result. Must run on the GUI
    // thread before any backend is created.
    static bool       initializeDisplay(EGLDisplay display);
    static bool       displayInitialized();
    static EGLDisplay display();

    ViewBackend(const QSize &physicalSize, qreal deviceScale, PacificWebView *view);
    ~ViewBackend();
    ViewBackend(const ViewBackend &)                        = delete;
    ViewBackend             &operator=(const ViewBackend &) = delete;

    struct wpe_view_backend *backend() const;

    // Size in physical pixels plus the WebKit device scale factor (CSS px to
    // device px). WebKit gets the logical size and the scale and renders into
    // a physical-size buffer.
    void  resize(const QSize &physicalSize);
    void  setDeviceScale(qreal scale);
    qreal deviceScale() const {
        return m_deviceScale;
    }
    // Dispatches the current scale; call once a WebKitWebView is attached
    // (libwpe drops dispatches made before a client exists).
    void applyDeviceScale();

    // Headless: no Qt window samples the frames, so each one is released and
    // acknowledged at once, paced to kHeadlessFrameMs.
    void setHeadless(bool headless);
    bool headless() const {
        return m_headless;
    }

    // Render thread (updatePaintNode, Qt's GL context current): binds the
    // newest frame into a texture and returns it, 0 before the first frame.
    unsigned texture(QOpenGLContext *context);
    QSize    currentImageSize() const;
    // Frames numbered as they arrive: how many so far, and the number of
    // the one Qt's path draws now (render thread, after texture()).
    quint64 arrivedSerial() const {
        return m_arrivedSerial;
    }
    // The GL texture showing the committed frame, and that frame's size.
    unsigned textureId() const {
        return m_textureId;
    }
    QSize   committedImageSize() const;
    quint64 committedSerial() const {
        return m_serials.value(m_committedImage);
    }
    // GUI thread, after a Qt frame was swapped.
    void didRenderFrame();
    // Direct composition (directsurface.h): frames go to a subsurface while
    // wanted and possible; otherwise through Qt.
    void setDirect(bool wanted, QWindow *window, const QRect &physicalRect);
    bool directShown() const;
    void dispatchEarlyAck();

    void setActivityState(bool visible, bool focused) const;

    void dispatchHoverMove(QHoverEvent *event);
    void dispatchHoverLeave();
    void dispatchMousePress(QMouseEvent *event);
    void dispatchMouseRelease(QMouseEvent *event);
    void dispatchMouseMove(QMouseEvent *event);
    void dispatchWheel(QWheelEvent *event);
    void dispatchKey(QKeyEvent *event, bool pressed) const;
    void dispatchTouch(QTouchEvent *event);
    // WebKit's frame for a view of this size: within 2 px, as it rounds
    // through CSS pixels (2206 device pixels at 2.5x drew 2205).
    static bool sizeFits(QSize frame, QSize view);
    // Synthesised, trusted tap at a point in item coordinates (agent clicks).
    void dispatchTap(const QPointF &itemPoint) const;
    // Secondary-button click: WebKit's context menu at that point.
    void dispatchContextClick(const QPointF &itemPoint) const;

    // Item coordinates to libwpe input coordinates (device pixels).
    void setItemToPhysical(qreal ratio) {
        m_itemToPhysical = ratio;
    }
    int32_t toWebKit(qreal itemCoordinate) const;

    bool    handleFullscreen(bool enable);
    // Entry point for WPEBackend-fdo's C callback table.
    void displayImagePublic(struct wpe_fdo_egl_exported_image *image);
    void displayShmPublic(struct wpe_fdo_shm_exported_buffer *buffer);

    // Software-rendered frames (wl_shm buffers: the WebProcess on a software
    // GL such as llvmpipe, e.g. the CPU fallback): copied out of the buffer
    // on arrival. Render thread, from updatePaintNode: true and the frame
    // when a new one is waiting.
    bool takeShmFrame(QImage *frame);
    bool hasShmFrame() const {
        return !m_shmFrame.isNull();
    }
    // Asks Qt for a frame when a kept frame should now be drawn (the view
    // was shown).
    void redraw();

  private:
    void displayImage(struct wpe_fdo_egl_exported_image *image);
    // How direct composition acknowledges frames (PACIFIC_DIRECT_ACK):
    // paced (default) presents at most one frame per compositor frame
    // callback and acknowledges it on presenting; present presents and
    // acknowledges every frame as it arrives; callback presents at once and
    // acknowledges on the frame callback.
    enum class DirectAck {
        Paced,
        Present,
        Callback
    };
    static DirectAck directAck();
    void             presentDirect(struct wpe_fdo_egl_exported_image *image);
    // Shows or hides the subsurface for what setDirect() last asked: shown
    // only once the frame Qt last drew has the subsurface's size (sizeFits). An older
    // frame of another size left part of the subsurface empty, the window's
    // white background, until WebKit drew at the new size (the toolbar
    // sliding away grows the page). Until then Qt's path draws the page.
    void         applyDirect(bool forceHide = false);
    static QSize imageSize(struct wpe_fdo_egl_exported_image *image);
    void         displayShm(struct wpe_fdo_shm_exported_buffer *buffer);
    bool         scheduleOrDrop();
    bool         canShowFrames() const;
    void         dropQueuedImage();
    void         releaseImage(struct wpe_fdo_egl_exported_image *&image);
    void         frameComplete();
    uint32_t     modifiers() const;

    // Members grouped by size (pointers, values, then flags): clang-tidy's
    // padding check.
    QPointer<PacificWebView>                m_view;
    struct wpe_view_backend_exportable_fdo *m_exportable = nullptr;
    // A web frame moves pending (arrived) -> committed (sampled by Qt's
    // render thread, drawn from then on) -> retired (replaced; given back
    // to the WebProcess once the frame that replaced it has been swapped).
    struct wpe_fdo_egl_exported_image *m_pendingImage   = nullptr;
    struct wpe_fdo_egl_exported_image *m_committedImage = nullptr;
    // PACIFIC_FRAME_ACK=queue: the frame behind m_pendingImage.
    struct wpe_fdo_egl_exported_image         *m_queuedImage = nullptr;
    QList<struct wpe_fdo_egl_exported_image *> m_retiredImages;
    std::unique_ptr<DirectSurface>             m_direct;
    QPointer<QWindow>                          m_directWindow;
    // Paced direct composition: a frame waiting for the compositor.
    struct wpe_fdo_egl_exported_image                  *m_directQueued   = nullptr;
    qreal                                               m_deviceScale    = 1.0;
    qreal                                               m_itemToPhysical = 1.0;
    QImage                                              m_shmFrame;
    QSet<int>                                           m_announcedTouchIds;
    QHash<struct wpe_fdo_egl_exported_image *, quint64> m_serials;
    quint64                                             m_arrivedSerial = 0;

    QRect                                               m_directRect;
    QSize                                               m_size;
    // A texture per frame image, as DirectSurface keeps (WebKit draws into
    // a few buffers in turn, and fdo keeps one EGLImage per buffer): an
    // image already bound is shown as it is, instead of the driver
    // importing it again for each new frame. Render thread only.
    struct ImageTexture {
        void    *image   = nullptr;
        unsigned texture = 0;
        quint64  usedAt  = 0; // the frame count when last shown
    };
    std::array<ImageTexture, 4> m_imageTextures{};
    QSize                       m_imageTexturesSize;
    quint64                     m_textureFrames    = 0;
    unsigned                    m_textureId        = 0; // the committed frame's texture
    uint32_t                    m_pointerModifiers = 0;
    uint32_t                    m_pressedButton    = 0;

    bool                        m_sampled      = false; // a frame sampled since the last swap
    bool                        m_sampledAcked = false; // ... and already acknowledged
    bool                        m_frameUpdateRequested = false; // software (wl_shm) frames
    bool                        m_directWanted         = false;
    bool                        m_directAckPending     = false;
    bool                        m_headless             = false;
    bool                        m_headlessAckPending   = false;
    bool                        m_shmNew               = false;
    bool                        m_pendingAcked         = false;
    bool                        m_hovering             = false;
};
