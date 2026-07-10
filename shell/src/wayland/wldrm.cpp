#include "src/wayland/wldrm.h"

#include "src/managers/deviceprofile.h"
#include <QDebug>
#include <QFile>
#include <QWaylandCompositor>

#include <unistd.h>
#include <wayland-server.h>

#include "wayland-drm-server.h"

// ---------------------------------------------------------------------------
// Inert wl_buffer — wl_drm's create_*_buffer requests carry a mandatory
// new_id, so we must hand back a wl_buffer. Mesa never calls these when
// zwp_linux_dmabuf_v1 is advertised (it allocates through dmabuf and uses
// wl_drm only for device discovery), so this path is defensive: return a
// backing-less buffer rather than post a protocol error that would kill the
// client connection.
// ---------------------------------------------------------------------------
static void inertBufferDestroy(struct wl_client *, struct wl_resource *resource) {
    wl_resource_destroy(resource);
}

static const struct wl_buffer_interface kInertBufferImpl = {
    inertBufferDestroy,
};

static void createInertBuffer(struct wl_client *client, uint32_t id) {
    struct wl_resource *buffer = wl_resource_create(client, &wl_buffer_interface, 1, id);
    if (!buffer) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(buffer, &kInertBufferImpl, nullptr, nullptr);
}

// ---------------------------------------------------------------------------
// wl_drm request handlers
// ---------------------------------------------------------------------------
static void drmAuthenticate(struct wl_client *, struct wl_resource *resource, uint32_t /*id*/) {
    // Render nodes carry no DRM-magic authentication; acknowledge at once.
    wl_drm_send_authenticated(resource);
}

static void drmCreateBuffer(struct wl_client *client, struct wl_resource * /*resource*/, uint32_t id,
                            uint32_t /*name*/, int32_t /*width*/, int32_t /*height*/,
                            uint32_t /*stride*/, uint32_t /*format*/) {
    createInertBuffer(client, id);
}

static void drmCreatePlanarBuffer(struct wl_client *client, struct wl_resource * /*resource*/,
                                  uint32_t id, uint32_t /*name*/, int32_t /*width*/,
                                  int32_t /*height*/, uint32_t /*format*/, int32_t /*offset0*/,
                                  int32_t /*stride0*/, int32_t /*offset1*/, int32_t /*stride1*/,
                                  int32_t /*offset2*/, int32_t /*stride2*/) {
    createInertBuffer(client, id);
}

static void drmCreatePrimeBuffer(struct wl_client *client, struct wl_resource * /*resource*/,
                                 uint32_t id, int32_t name, int32_t /*width*/, int32_t /*height*/,
                                 uint32_t /*format*/, int32_t /*offset0*/, int32_t /*stride0*/,
                                 int32_t /*offset1*/, int32_t /*stride1*/, int32_t /*offset2*/,
                                 int32_t /*stride2*/) {
    // We never use the imported fd (buffers flow through zwp_linux_dmabuf);
    // close it so we don't leak the client's descriptor.
    if (name >= 0)
        ::close(name);
    createInertBuffer(client, id);
}

static const struct wl_drm_interface kDrmImpl = {
    drmAuthenticate,
    drmCreateBuffer,
    drmCreatePlanarBuffer,
    drmCreatePrimeBuffer,
};

// ---------------------------------------------------------------------------
// WlDrmManager
// ---------------------------------------------------------------------------
WlDrmManager::WlDrmManager(QWaylandCompositor *compositor)
    : QObject(compositor)
    , m_compositor(compositor) {
    // wl_drm is legacy device-discovery/buffer-sharing. Marathon now discovers
    // the render device through the linux-dmabuf-v1 v4 main_device feedback
    // plugin, which also imports the buffers. Leaving wl_drm advertised is
    // actively harmful on Mesa >= 26.1 / etnaviv: Mesa binds wl_drm and allocates
    // its surface buffers via create_prime_buffer (our inert stub) instead of
    // dmabuf, so no importable buffer reaches the compositor and the app surface
    // never maps. Default OFF; opt in with MARATHON_WL_DRM=1 only on a stack
    // where the dmabuf-v1 plugin is unavailable.
    if (qgetenv("MARATHON_WL_DRM") != QByteArrayLiteral("1")) {
        qInfo() << "[WlDrm] not advertised (default) — clients use linux-dmabuf-v1;"
                << "set MARATHON_WL_DRM=1 to force-enable the legacy wl_drm global";
        return;
    }

    // DeviceProfile::renderNode() already resolves MARATHON_RENDER_NODE env >
    // conf RENDER_NODE > /dev/dri/renderD128 default, so this stays byte-for-byte
    // the historical value on an un-provisioned L5 while an overlay can retarget it.
    m_deviceNode = DeviceProfile::instance().renderNode().toLocal8Bit();

    if (!QFile::exists(QString::fromLocal8Bit(m_deviceNode))) {
        qWarning() << "[WlDrm] render node" << m_deviceNode
                   << "not present — wl_drm NOT advertised; wayland clients fall back to software";
        return;
    }

    auto *display = static_cast<struct wl_display *>(m_compositor->display());
    m_global      = wl_global_create(display, &wl_drm_interface, 2, this, &WlDrmManager::bindManager);
    if (!m_global)
        qWarning() << "[WlDrm] wl_global_create failed — wayland clients fall back to software";
    else
        qInfo() << "[WlDrm] advertised wl_drm v2 (device=" << m_deviceNode << ", cap=PRIME)";
}

WlDrmManager::~WlDrmManager() {
    if (m_global)
        wl_global_destroy(m_global);
}

void WlDrmManager::bindManager(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    auto          *self    = static_cast<WlDrmManager *>(data);
    const uint32_t bindVer = qMin(version, 2u);

    struct wl_resource *resource =
        wl_resource_create(client, &wl_drm_interface, static_cast<int>(bindVer), id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &kDrmImpl, self, nullptr);

    // Name the render device Mesa should open. For a render node this is all
    // Mesa needs — it opens the node directly and skips DRM-magic auth.
    wl_drm_send_device(resource, self->m_deviceNode.constData());

    // Advertise the formats etnaviv scans out. The exact set isn't
    // load-bearing for device discovery, but Mesa expects at least the
    // common 32-bpp packed formats.
    wl_drm_send_format(resource, WL_DRM_FORMAT_ARGB8888);
    wl_drm_send_format(resource, WL_DRM_FORMAT_XRGB8888);
    wl_drm_send_format(resource, WL_DRM_FORMAT_ABGR8888);
    wl_drm_send_format(resource, WL_DRM_FORMAT_XBGR8888);

    // PRIME (>= v2) tells Mesa to allocate via dmabuf/PRIME and skip the
    // legacy GEM-flink + authenticate path render nodes can't satisfy.
    if (bindVer >= 2)
        wl_drm_send_capabilities(resource, WL_DRM_CAPABILITY_PRIME);
}
