#include "marathonsurfacev1.h"

#include "securitycontextv1.h"

#include <QWaylandCompositor>
#include <QWaylandXdgSurface>

extern "C" {
#include "marathon-surface-v1-server.h"
}

namespace {

    MarathonSurfaceV1 *surfaceOf(wl_resource *resource) {
        return static_cast<MarathonSurfaceV1 *>(wl_resource_get_user_data(resource));
    }

} // namespace

static constexpr struct marathon_surface_manager_v1_interface s_managerImpl = {
    /* destroy */
    [](wl_client *, wl_resource *resource) { wl_resource_destroy(resource); },
    /* get_surface */
    [](wl_client *client, wl_resource *resource, uint32_t id, wl_resource *toplevel,
       uint32_t taskId) {
        MarathonSurfaceManagerV1::getSurface(client, resource, id, toplevel, taskId);
    },
};

static constexpr struct marathon_surface_v1_interface s_surfaceImpl = {
    /* destroy */
    [](wl_client *, wl_resource *resource) { wl_resource_destroy(resource); },
    /* set_window_flags */
    [](wl_client *, wl_resource *resource, uint32_t flags) {
        MarathonSurfaceV1::setWindowFlags(resource, flags);
    },
    /* set_gesture_exclusion */
    [](wl_client *, wl_resource *resource, wl_array *rects) {
        MarathonSurfaceV1::setGestureExclusion(resource, rects);
    },
    /* set_system_bars */
    [](wl_client *, wl_resource *resource, uint32_t mode) {
        MarathonSurfaceV1::setSystemBars(resource, mode);
    },
};

// ── Manager ────────────────────────────────────────────────────────────

MarathonSurfaceManagerV1::MarathonSurfaceManagerV1(QWaylandCompositor       *compositor,
                                                   SecurityContextManagerV1 *contexts)
    : QObject(compositor)
    , m_contexts(contexts) {
    m_global = wl_global_create(compositor->display(), &marathon_surface_manager_v1_interface, 1,
                                this, &MarathonSurfaceManagerV1::bind);
}

MarathonSurfaceManagerV1::~MarathonSurfaceManagerV1() {
    wl_global_destroy(m_global);
}

bool MarathonSurfaceManagerV1::mayBind(bool sandboxed, const QString &engine) {
    return !sandboxed || engine == QLatin1String(kTrustedEngine);
}

bool MarathonSurfaceManagerV1::allowsGlobal(const wl_client *client,
                                            const wl_global *global) const {
    return global != m_global ||
        mayBind(m_contexts->isSandboxed(client), m_contexts->contextForClient(client).engine);
}

void MarathonSurfaceManagerV1::bind(wl_client *client, void *data, uint32_t version, uint32_t id) {
    wl_resource *resource = wl_resource_create(client, &marathon_surface_manager_v1_interface,
                                               qMin<uint32_t>(version, 1u), id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &s_managerImpl, data, nullptr);
}

void MarathonSurfaceManagerV1::getSurface(wl_client *client, wl_resource *manager, uint32_t id,
                                          wl_resource *toplevelResource, uint32_t taskId) {
    auto *self     = static_cast<MarathonSurfaceManagerV1 *>(wl_resource_get_user_data(manager));
    auto *toplevel = QWaylandXdgToplevel::fromResource(toplevelResource);
    if (!toplevel) {
        wl_resource_post_no_memory(manager);
        return;
    }
    QWaylandSurface *surface = toplevel->xdgSurface()->surface();
    if (self->m_surfaces.contains(surface)) {
        wl_resource_post_error(manager, MARATHON_SURFACE_MANAGER_V1_ERROR_ALREADY_EXISTS,
                               "the toplevel already has a marathon_surface_v1");
        return;
    }
    wl_resource *resource = wl_resource_create(client, &marathon_surface_v1_interface,
                                               wl_resource_get_version(manager), id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    auto *created = new MarathonSurfaceV1(self, resource, toplevel, taskId);
    self->m_surfaces.insert(surface, created);
    emit self->surfaceAdded(created);
}

void MarathonSurfaceManagerV1::remove(MarathonSurfaceV1 *surface) {
    for (auto it = m_surfaces.begin(); it != m_surfaces.end(); ++it) {
        if (it.value() == surface) {
            m_surfaces.erase(it);
            emit surfaceRemoved(surface);
            return;
        }
    }
}

// ── Per-toplevel state ─────────────────────────────────────────────────

MarathonSurfaceV1::MarathonSurfaceV1(MarathonSurfaceManagerV1 *manager, wl_resource *resource,
                                     QWaylandXdgToplevel *toplevel, uint taskId)
    : QObject(manager)
    , m_manager(manager)
    , m_resource(resource)
    , m_toplevel(toplevel)
    , m_surface(toplevel->xdgSurface()->surface())
    , m_taskId(taskId) {
    wl_resource_set_implementation(m_resource, &s_surfaceImpl, this, [](wl_resource *r) {
        MarathonSurfaceV1 *self = surfaceOf(r);
        self->m_resource        = nullptr;
        self->makeInert();
        self->deleteLater();
    });
    connect(toplevel, &QObject::destroyed, this, &MarathonSurfaceV1::makeInert);
    connect(m_surface, &QWaylandSurface::redraw, this, &MarathonSurfaceV1::applyPendingExclusion);
}

// The manager can be deleted before the display destroys this resource.
MarathonSurfaceV1::~MarathonSurfaceV1() {
    if (m_resource)
        wl_resource_set_destructor(m_resource, nullptr);
}

bool MarathonSurfaceV1::focusable() const {
    return !(m_flags & MARATHON_SURFACE_V1_WINDOW_FLAGS_NOT_FOCUSABLE);
}

bool MarathonSurfaceV1::touchable() const {
    return !(m_flags & MARATHON_SURFACE_V1_WINDOW_FLAGS_NOT_TOUCHABLE);
}

bool MarathonSurfaceV1::secure() const {
    return m_flags & MARATHON_SURFACE_V1_WINDOW_FLAGS_SECURE;
}

QVariantList MarathonSurfaceV1::gestureExclusion() const {
    QVariantList rects;
    for (const QRect &rect : m_exclusion)
        rects << rect;
    return rects;
}

void MarathonSurfaceV1::makeInert() {
    if (m_inert)
        return;
    m_inert = true;
    m_manager->remove(this);
}

void MarathonSurfaceV1::setWindowFlags(wl_resource *resource, uint32_t flags) {
    MarathonSurfaceV1 *self = surfaceOf(resource);
    if (!marathon_surface_v1_window_flags_is_valid(flags, wl_resource_get_version(resource))) {
        wl_resource_post_error(resource, MARATHON_SURFACE_V1_ERROR_INVALID_FLAGS,
                               "unknown window flags 0x%x", flags);
        return;
    }
    if (self->m_inert || self->m_flags == flags)
        return;
    self->m_flags = flags;
    emit self->flagsChanged();
}

void MarathonSurfaceV1::setGestureExclusion(wl_resource *resource, wl_array *rects) {
    MarathonSurfaceV1 *self = surfaceOf(resource);
    if (rects->size % (4 * sizeof(int32_t)) != 0) {
        wl_resource_post_error(resource, MARATHON_SURFACE_V1_ERROR_INVALID_RECTS,
                               "rects is not a whole number of rectangles");
        return;
    }
    QList<QRect>   pending;
    const int32_t *values = static_cast<const int32_t *>(rects->data);
    for (size_t i = 0; i < rects->size / sizeof(int32_t); i += 4) {
        if (values[i + 2] < 0 || values[i + 3] < 0) {
            wl_resource_post_error(resource, MARATHON_SURFACE_V1_ERROR_INVALID_RECTS,
                                   "rectangle with a negative size");
            return;
        }
        pending << QRect(values[i], values[i + 1], values[i + 2], values[i + 3]);
    }
    self->m_pendingExclusion = std::move(pending);
    self->m_exclusionPending = true;
}

void MarathonSurfaceV1::applyPendingExclusion() {
    if (m_inert || !m_exclusionPending)
        return;
    m_exclusionPending = false;
    if (m_pendingExclusion == m_exclusion)
        return;
    m_exclusion = m_pendingExclusion;
    emit gestureExclusionChanged();
}

void MarathonSurfaceV1::setSystemBars(wl_resource *resource, uint32_t mode) {
    MarathonSurfaceV1 *self = surfaceOf(resource);
    if (!marathon_surface_v1_system_bars_is_valid(mode, wl_resource_get_version(resource))) {
        wl_resource_post_error(resource, MARATHON_SURFACE_V1_ERROR_INVALID_MODE,
                               "unknown system bars mode %u", mode);
        return;
    }
    const bool hidden = mode == MARATHON_SURFACE_V1_SYSTEM_BARS_HIDDEN;
    if (self->m_inert || self->m_systemBarsHidden == hidden)
        return;
    self->m_systemBarsHidden = hidden;
    emit self->systemBarsHiddenChanged();
}

bool MarathonSurfaceV1::sendInsets(const QMargins &insets, int imeBottom) {
    if (m_inert)
        return false;
    bool sent = false;
    if (!m_insetsSent || insets != m_insets) {
        marathon_surface_v1_send_insets(m_resource, insets.top(), insets.bottom(), insets.left(),
                                        insets.right());
        m_insets = insets;
        sent     = true;
    }
    if (!m_insetsSent || imeBottom != m_imeBottom) {
        marathon_surface_v1_send_ime_inset(m_resource, imeBottom);
        m_imeBottom = imeBottom;
        sent        = true;
    }
    m_insetsSent = true;
    return sent;
}

void MarathonSurfaceV1::sendBackProgress(uint edge, qreal progress, const QPointF &position) {
    if (m_inert)
        return;
    const wl_fixed_t x = wl_fixed_from_double(position.x());
    const wl_fixed_t y = wl_fixed_from_double(position.y());
    if (!m_backActive) {
        marathon_surface_v1_send_back_started(m_resource, edge, x, y);
        m_backActive = true;
    }
    marathon_surface_v1_send_back_progress(m_resource, wl_fixed_from_double(progress), x, y);
}

void MarathonSurfaceV1::sendBackCommitted() {
    if (m_inert)
        return;
    marathon_surface_v1_send_back_committed(m_resource);
    m_backActive = false;
}

void MarathonSurfaceV1::cancelBack() {
    if (m_inert || !m_backActive)
        return;
    marathon_surface_v1_send_back_cancelled(m_resource);
    m_backActive = false;
}
