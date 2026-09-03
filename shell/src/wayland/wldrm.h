#ifndef WLDRM_H
#define WLDRM_H

#include <QByteArray>
#include <QObject>
#include <wayland-server-core.h>

class QWaylandCompositor;

// wl_drm — Mesa's legacy device-discovery protocol.
//
// Marathon's Qt Wayland compositor advertises only zwp_linux_dmabuf_v1 v3
// (no main_device feedback — that lives in v4, which is gated off because a
// second same-interface global breaks Qt's buffer import, see linuxdmabufv1.h)
// and no wl_drm. On Mesa <= ~26.1.0 a wayland-egl client would still guess the
// renderD128 node on its own; Mesa 26.1.1 tightened that and now falls back to
// llvmpipe (software) when the compositor names no render device. Result: the
// shell (direct GBM/KMS) renders on etnaviv HW while every app (wayland-egl)
// renders on llvmpipe — visibly slow scrolling.
//
// wl_drm is the interface Mesa's EGL wayland platform has always used to learn
// its render device: on bind we send the render node path via `device`, the
// supported formats, and the PRIME `capabilities` bit. Mesa opens the render
// node directly (render nodes need no DRM-magic auth), sees PRIME, and creates
// its GLES context on etnaviv — then hands buffers back through Qt's existing
// v3 dmabuf import path. wl_drm supplies ONLY the device + PRIME cap; it does
// not allocate buffers, so it never conflicts with the dmabuf buffer path.
class WlDrmManager : public QObject {
    Q_OBJECT

  public:
    explicit WlDrmManager(QWaylandCompositor *compositor);
    ~WlDrmManager() override;

    // Entry point from C wayland-server via wl_global_create's bind callback.
    static void bindManager(struct wl_client *client, void *data, uint32_t version, uint32_t id);

  private:
    QWaylandCompositor *m_compositor = nullptr;
    struct wl_global   *m_global     = nullptr;
    // Render node Mesa clients should allocate/render on. /dev/dri/renderD128
    // by default; overridable via MARATHON_RENDER_NODE for boards whose
    // etnaviv render node is numbered differently.
    QByteArray m_deviceNode;
};

#endif // WLDRM_H
