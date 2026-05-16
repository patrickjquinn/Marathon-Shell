#include "layer_shell_v1.h"

#include "wlr-layer-shell-unstable-v1-server.h"

#include <QLoggingCategory>
#include <QWaylandCompositor>
#include <QWaylandSurface>

Q_LOGGING_CATEGORY(lcLS, "marathon.compositor.layer-shell")

// Protocol version we advertise. zwlr_layer_shell_v1 has gone up to v5;
// each version adds opt-in requests (v2 set_layer, v3 destroy on manager,
// v4 set_exclusive_edge). v5 is wire-compatible downward — older clients
// using only the v1 subset still work fine.
static constexpr uint32_t kLayerShellVersion = 5;

// -- layer_shell manager -----------------------------------------------

static void mgrDestroy(wl_client *, wl_resource *resource) {
    wl_resource_destroy(resource);
}

static void mgrGetLayerSurface(wl_client *client, wl_resource *resource, uint32_t id,
                               wl_resource *surfaceResource, wl_resource *outputResource,
                               uint32_t layer, const char *nm) {
    Q_UNUSED(outputResource); // single-output
    auto *shell = static_cast<WlrLayerShellV1 *>(wl_resource_get_user_data(resource));
    if (!shell) {
        wl_client_post_no_memory(client);
        return;
    }
    auto *qSurface = QWaylandSurface::fromResource(surfaceResource);
    if (!qSurface) {
        wl_resource_post_error(resource, ZWLR_LAYER_SHELL_V1_ERROR_INVALID_SURFACE_STATE,
                               "no QWaylandSurface for wl_surface");
        return;
    }
    if (layer > ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY) {
        wl_resource_post_error(resource, ZWLR_LAYER_SHELL_V1_ERROR_INVALID_LAYER,
                               "layer %u out of range", layer);
        return;
    }
    auto *layerSurface =
        new WlrLayerSurfaceV1(shell, client, id, qSurface,
                              static_cast<WlrLayerShellV1::Layer>(layer), QString::fromUtf8(nm));
    emit shell->layerSurfaceCreated(layerSurface);
    qCInfo(lcLS) << "get_layer_surface id=" << id << "layer=" << layer << "ns=" << nm;
}

static const struct zwlr_layer_shell_v1_interface managerImpl = {
    .get_layer_surface = mgrGetLayerSurface,
    .destroy           = mgrDestroy,
};

WlrLayerShellV1::WlrLayerShellV1(QWaylandCompositor *compositor)
    : QObject(compositor)
    , m_compositor(compositor) {
    wl_display *display = compositor->display();
    m_global =
        wl_global_create(display, &zwlr_layer_shell_v1_interface, kLayerShellVersion, this, &bind);
    if (m_global)
        qCInfo(lcLS) << "zwlr_layer_shell_v1 v" << kLayerShellVersion << "global created";
    else
        qCWarning(lcLS) << "failed to create wl_global for zwlr_layer_shell_v1";
}

WlrLayerShellV1::~WlrLayerShellV1() {
    if (m_global)
        wl_global_destroy(m_global);
}

void WlrLayerShellV1::bind(wl_client *client, void *data, uint32_t version, uint32_t id) {
    auto        *shell = static_cast<WlrLayerShellV1 *>(data);
    const auto   ver   = std::min<uint32_t>(version, kLayerShellVersion);
    wl_resource *res   = wl_resource_create(client, &zwlr_layer_shell_v1_interface, ver, id);
    if (!res) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(res, &managerImpl, shell, nullptr);
    qCDebug(lcLS) << "client bound zwlr_layer_shell_v1 v" << ver;
}

// Unused — interface struct uses the file-scope handlers above; these
// stubs satisfy the header declarations for API symmetry.
void WlrLayerShellV1::destroyManager(wl_client *, wl_resource *) {}
void WlrLayerShellV1::getLayerSurface(wl_client *, wl_resource *, uint32_t, wl_resource *,
                                      wl_resource *, uint32_t, const char *) {}

// -- layer_surface -----------------------------------------------------

static const struct zwlr_layer_surface_v1_interface surfaceImpl = {
    .set_size                   = WlrLayerSurfaceV1::setSize,
    .set_anchor                 = WlrLayerSurfaceV1::setAnchor,
    .set_exclusive_zone         = WlrLayerSurfaceV1::setExclusiveZone,
    .set_margin                 = WlrLayerSurfaceV1::setMargin,
    .set_keyboard_interactivity = WlrLayerSurfaceV1::setKeyboardInteractivity,
    .get_popup                  = WlrLayerSurfaceV1::getPopup,
    .ack_configure              = WlrLayerSurfaceV1::ackConfigure,
    .destroy                    = WlrLayerSurfaceV1::destroyRequest,
    .set_layer                  = WlrLayerSurfaceV1::setLayer,
    .set_exclusive_edge         = WlrLayerSurfaceV1::setExclusiveEdge,
};

WlrLayerSurfaceV1::WlrLayerSurfaceV1(WlrLayerShellV1 *shell, wl_client *client, uint32_t id,
                                     QWaylandSurface *surface, WlrLayerShellV1::Layer layer,
                                     const QString &nm)
    : QObject(shell)
    , m_shell(shell)
    , m_surface(surface)
    , m_layer(layer)
    , m_namespace(nm) {
    m_resource =
        wl_resource_create(client, &zwlr_layer_surface_v1_interface, kLayerShellVersion, id);
    if (!m_resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(m_resource, &surfaceImpl, this, &destroyResource);
    qCDebug(lcLS) << "layer surface created ns=" << nm << "layer=" << int(layer);
    // STUB: send a 0x0 configure immediately so well-behaved clients
    // (layer-shell-qt) can commit their first frame. Real size
    // negotiation lands when compositor.qml grows a layer-surface
    // presenter in C-2.
    sendConfigure(QSize(0, 0));
}

WlrLayerSurfaceV1::~WlrLayerSurfaceV1() = default;

void WlrLayerSurfaceV1::sendConfigure(const QSize &size) {
    if (!m_resource)
        return;
    ++m_lastSerial;
    m_pendingSize = size;
    zwlr_layer_surface_v1_send_configure(m_resource, m_lastSerial,
                                         static_cast<uint32_t>(size.width()),
                                         static_cast<uint32_t>(size.height()));
}

void WlrLayerSurfaceV1::destroyResource(wl_resource *resource) {
    auto *self = static_cast<WlrLayerSurfaceV1 *>(wl_resource_get_user_data(resource));
    if (self)
        self->deleteLater();
}

void WlrLayerSurfaceV1::setSize(wl_client *, wl_resource *resource, uint32_t w, uint32_t h) {
    auto *self = static_cast<WlrLayerSurfaceV1 *>(wl_resource_get_user_data(resource));
    if (self)
        self->m_pendingSize = QSize(int(w), int(h));
}

void WlrLayerSurfaceV1::setAnchor(wl_client *, wl_resource *, uint32_t) {}
void WlrLayerSurfaceV1::setExclusiveZone(wl_client *, wl_resource *, int32_t) {}
void WlrLayerSurfaceV1::setMargin(wl_client *, wl_resource *, int32_t, int32_t, int32_t, int32_t) {}
void WlrLayerSurfaceV1::setKeyboardInteractivity(wl_client *, wl_resource *, uint32_t) {}
void WlrLayerSurfaceV1::getPopup(wl_client *, wl_resource *, wl_resource *) {}

void WlrLayerSurfaceV1::ackConfigure(wl_client *, wl_resource *resource, uint32_t serial) {
    auto *self = static_cast<WlrLayerSurfaceV1 *>(wl_resource_get_user_data(resource));
    if (!self || serial != self->m_lastSerial)
        return;
    qCDebug(lcLS) << "ack_configure serial=" << serial << "ns=" << self->m_namespace;
}

void WlrLayerSurfaceV1::destroyRequest(wl_client *, wl_resource *resource) {
    wl_resource_destroy(resource);
}

void WlrLayerSurfaceV1::setLayer(wl_client *, wl_resource *resource, uint32_t layer) {
    auto *self = static_cast<WlrLayerSurfaceV1 *>(wl_resource_get_user_data(resource));
    if (self && layer <= ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY)
        self->m_layer = static_cast<WlrLayerShellV1::Layer>(layer);
}

void WlrLayerSurfaceV1::setExclusiveEdge(wl_client *, wl_resource *, uint32_t) {}
