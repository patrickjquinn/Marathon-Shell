#pragma once

#include <QObject>
#include <QPointer>
#include <QRect>
#include <wayland-server-core.h>

class QQuickWindow;
class QWaylandCompositor;
class QWaylandQuickOutput;
class ScreencopyFrameV1;

// Server-side wlr_screencopy_unstable_v1 (v3 advertised, wl_shm only).
//
// dmabuf is intentionally unsupported: the v3 linux_dmabuf event is
// omitted from buffer_done, so clients negotiate down to the wl_shm
// path. Keeps the readback simple (single CPU memcpy) at thumbnail
// cadence; dmabuf is worth revisiting if continuous-preview capture
// ever becomes a use case.
class ScreencopyManagerV1 : public QObject {
    Q_OBJECT

  public:
    explicit ScreencopyManagerV1(QWaylandCompositor *compositor, QWaylandQuickOutput *output,
                                 QQuickWindow *window);
    ~ScreencopyManagerV1() override;

    QWaylandQuickOutput *output() const {
        return m_output.data();
    }
    QQuickWindow *window() const {
        return m_window.data();
    }

    // Static request handlers — public so the file-scope interface
    // struct in the .cpp can take their addresses.
    static void bind(struct wl_client *client, void *data, uint32_t version, uint32_t id);
    static void onCaptureOutput(wl_client *, wl_resource *, uint32_t frameId, int32_t overlayCursor,
                                wl_resource *output);
    static void onCaptureOutputRegion(wl_client *, wl_resource *, uint32_t frameId,
                                      int32_t overlayCursor, wl_resource *output, int32_t x,
                                      int32_t y, int32_t width, int32_t height);
    static void onDestroyManager(wl_client *, wl_resource *resource);

  private:
    QWaylandCompositor           *m_compositor = nullptr;
    QPointer<QWaylandQuickOutput> m_output;
    QPointer<QQuickWindow>        m_window;
    struct wl_global             *m_global = nullptr;
};

// One per capture_output request. Owns its wl_resource until the
// client destroys the frame (which the protocol requires after ready/
// failed).
class ScreencopyFrameV1 : public QObject {
    Q_OBJECT

  public:
    ScreencopyFrameV1(ScreencopyManagerV1 *manager, wl_resource *resource, QQuickWindow *window,
                      const QRect &region, bool overlayCursor);
    ~ScreencopyFrameV1() override;

    static void onCopy(wl_client *, wl_resource *resource, wl_resource *buffer);
    static void onCopyWithDamage(wl_client *, wl_resource *resource, wl_resource *buffer);
    static void onDestroyFrame(wl_client *, wl_resource *resource);
    static void resourceDestroyed(wl_resource *resource);

  private:
    void                   sendBufferEvents();
    void                   performCopy(wl_resource *buffer, bool withDamage);
    void                   sendReady();
    void                   sendFailed();

    ScreencopyManagerV1   *m_manager  = nullptr;
    wl_resource           *m_resource = nullptr;
    QPointer<QQuickWindow> m_window;
    QRect                  m_region;
    bool                   m_overlayCursor = false;
    bool                   m_used          = false;
    uint32_t               m_stride        = 0;
    uint32_t               m_width         = 0;
    uint32_t               m_height        = 0;
};
