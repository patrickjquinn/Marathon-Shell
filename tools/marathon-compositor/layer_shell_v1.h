#pragma once

#include <QObject>
#include <QPointer>
#include <QSize>
#include <wayland-server-core.h>

class QWaylandCompositor;
class QWaylandSurface;
class WlrLayerSurfaceV1;

// Server-side implementation of zwlr_layer_shell_v1 (wlroots layer-shell
// protocol). The Marathon shell binds this from the client side via
// layer-shell-qt to draw its panels (status bar, NowBar, App Drawer,
// QuickSettings, Hub, Peek, …) on the correct compositor z-layer with
// anchors and exclusive zones.
//
// Protocol XML: protocols/wlr-layer-shell-unstable-v1.xml
//
// Phase C-1 ships this as a SKELETON: the wl_global is created and clients
// can bind it, but request handlers are stubs. compositor.qml does not yet
// render layer surfaces. Wiring continues in Phase C-2 (shell becomes the
// first client) and Phase C-6 (full anchor + exclusive-zone handling).
class WlrLayerShellV1 : public QObject {
    Q_OBJECT

  public:
    enum Layer {
        Background = 0,
        Bottom     = 1,
        Top        = 2,
        Overlay    = 3,
    };
    Q_ENUM(Layer)

    explicit WlrLayerShellV1(QWaylandCompositor *compositor);
    ~WlrLayerShellV1() override;

  signals:
    void layerSurfaceCreated(WlrLayerSurfaceV1 *surface);

  private:
    static void bind(struct wl_client *client, void *data, uint32_t version, uint32_t id);
    static void destroyManager(struct wl_client *client, struct wl_resource *resource);
    static void getLayerSurface(struct wl_client *client, struct wl_resource *resource, uint32_t id,
                                struct wl_resource *surface, struct wl_resource *output,
                                uint32_t layer, const char *nm);

    QWaylandCompositor        *m_compositor = nullptr;
    struct wl_global          *m_global     = nullptr;
    QList<WlrLayerSurfaceV1 *> m_surfaces;
};

// One per zwlr_layer_surface_v1 resource. Owns the role assignment on a
// wl_surface plus the configure handshake (size, anchors, exclusive zone,
// keyboard interactivity, margins). Skeleton in C-1 — full configure
// negotiation lands in C-2 when the shell is the first real client.
class WlrLayerSurfaceV1 : public QObject {
    Q_OBJECT

  public:
    WlrLayerSurfaceV1(WlrLayerShellV1 *shell, struct wl_client *client, uint32_t id,
                      QWaylandSurface *surface, WlrLayerShellV1::Layer layer, const QString &nm);
    ~WlrLayerSurfaceV1() override;

    QWaylandSurface *surface() const {
        return m_surface;
    }
    WlrLayerShellV1::Layer layer() const {
        return m_layer;
    }
    QString nspace() const {
        return m_namespace;
    }

    // Send an `configure` event with a serial; client ack_configure's it back.
    void sendConfigure(const QSize &size);

    // Static handlers exposed so the file-scope zwlr_layer_surface_v1_interface
    // vtable can reference them. They take wl_resource* whose user_data is the
    // owning WlrLayerSurfaceV1, so they're effectively member methods on the
    // C side of the protocol API.
    static void destroyResource(struct wl_resource *resource);
    static void setSize(wl_client *, wl_resource *, uint32_t w, uint32_t h);
    static void setAnchor(wl_client *, wl_resource *, uint32_t anchor);
    static void setExclusiveZone(wl_client *, wl_resource *, int32_t zone);
    static void setMargin(wl_client *, wl_resource *, int32_t top, int32_t r, int32_t b, int32_t l);
    static void setKeyboardInteractivity(wl_client *, wl_resource *, uint32_t interactive);
    static void getPopup(wl_client *, wl_resource *, wl_resource *popup);
    static void ackConfigure(wl_client *, wl_resource *, uint32_t serial);
    static void destroyRequest(wl_client *, wl_resource *);
    static void setLayer(wl_client *, wl_resource *, uint32_t layer);
    static void setExclusiveEdge(wl_client *, wl_resource *, uint32_t edge);

  signals:
    void mapped();
    void unmapped();

  private:
    WlrLayerShellV1          *m_shell = nullptr;
    QPointer<QWaylandSurface> m_surface;
    struct wl_resource       *m_resource = nullptr;
    WlrLayerShellV1::Layer    m_layer;
    QString                   m_namespace;
    QSize                     m_pendingSize;
    uint32_t                  m_lastSerial = 0;
};
