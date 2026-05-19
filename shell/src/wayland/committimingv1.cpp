#include "committimingv1.h"

#include <QDebug>
#include <QWaylandCompositor>
#include <QWaylandSurface>

extern "C" {
#include "commit-timing-v1-server.h"
}

// ── Manager ────────────────────────────────────────────────────────────

static const struct wp_commit_timing_manager_v1_interface s_managerImpl = {
    /* destroy */
    [](struct wl_client *, struct wl_resource *resource) { wl_resource_destroy(resource); },
    /* get_timer */
    [](struct wl_client *client, struct wl_resource *resource, uint32_t id,
       struct wl_resource *surfaceResource) {
        auto *mgr      = static_cast<CommitTimingManagerV1 *>(wl_resource_get_user_data(resource));
        auto *qSurface = QWaylandSurface::fromResource(surfaceResource);
        if (!mgr || !qSurface) {
            wl_resource_post_no_memory(resource);
            return;
        }
        if (mgr->hasTimerForSurface(qSurface)) {
            wl_resource_post_error(resource, WP_COMMIT_TIMING_MANAGER_V1_ERROR_COMMIT_TIMER_EXISTS,
                                   "commit timer already exists for this surface");
            return;
        }
        new CommitTimerV1(mgr, client, id, qSurface);
    },
};

CommitTimingManagerV1::CommitTimingManagerV1(QWaylandCompositor *compositor)
    : QObject(compositor)
    , m_compositor(compositor) {
    auto *display = static_cast<struct wl_display *>(compositor->display());
    if (!display) {
        qWarning() << "[commit-timing-v1] No wl_display; not registering global";
        return;
    }
    m_global = wl_global_create(display, &wp_commit_timing_manager_v1_interface,
                                /* version */ 1, this, &CommitTimingManagerV1::bindManager);
    if (!m_global) {
        qWarning() << "[commit-timing-v1] Failed to create wl_global";
        return;
    }
    qInfo() << "[commit-timing-v1] Global registered";
}

CommitTimingManagerV1::~CommitTimingManagerV1() {
    if (m_global)
        wl_global_destroy(m_global);
}

void CommitTimingManagerV1::bindManager(struct wl_client *client, void *data, uint32_t version,
                                        uint32_t id) {
    auto               *mgr      = static_cast<CommitTimingManagerV1 *>(data);
    struct wl_resource *resource = wl_resource_create(
        client, &wp_commit_timing_manager_v1_interface, qMin<uint32_t>(version, 1u), id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &s_managerImpl, mgr, nullptr);
}

bool CommitTimingManagerV1::hasTimerForSurface(QWaylandSurface *surface) const {
    for (CommitTimerV1 *t : m_timers)
        if (t->surface() == surface)
            return true;
    return false;
}

void CommitTimingManagerV1::registerTimer(CommitTimerV1 *timer) {
    m_timers.append(timer);
}

void CommitTimingManagerV1::unregisterTimer(CommitTimerV1 *timer) {
    m_timers.removeAll(timer);
}

// ── Per-surface timer ──────────────────────────────────────────────────

static const struct wp_commit_timer_v1_interface s_timerImpl = {
    CommitTimerV1::handleSetTimestamp,
    CommitTimerV1::handleDestroy,
};

CommitTimerV1::CommitTimerV1(CommitTimingManagerV1 *manager, struct wl_client *client, uint32_t id,
                             QWaylandSurface *surface)
    : QObject(manager)
    , m_manager(manager)
    , m_surface(surface) {
    m_resource = wl_resource_create(client, &wp_commit_timer_v1_interface, 1, id);
    if (!m_resource) {
        wl_client_post_no_memory(client);
        deleteLater();
        return;
    }
    wl_resource_set_implementation(m_resource, &s_timerImpl, this, [](struct wl_resource *res) {
        auto *self = static_cast<CommitTimerV1 *>(wl_resource_get_user_data(res));
        if (self)
            self->deleteLater();
    });
    m_manager->registerTimer(this);

    if (m_surface) {
        connect(m_surface.data(), &QWaylandSurface::redraw, this,
                &CommitTimerV1::onSurfaceCommitted);
        connect(m_surface.data(), &QWaylandSurface::surfaceDestroyed, this,
                &CommitTimerV1::onSurfaceDestroyed);
    }
}

CommitTimerV1::~CommitTimerV1() {
    if (m_manager)
        m_manager->unregisterTimer(this);
}

void CommitTimerV1::handleSetTimestamp(struct wl_client *, struct wl_resource *resource,
                                       uint32_t tv_sec_hi, uint32_t tv_sec_lo, uint32_t tv_nsec) {
    auto *self = static_cast<CommitTimerV1 *>(wl_resource_get_user_data(resource));
    if (!self)
        return;
    if (!self->m_surface) {
        wl_resource_post_error(resource, WP_COMMIT_TIMER_V1_ERROR_SURFACE_DESTROYED,
                               "associated surface no longer exists");
        return;
    }
    if (tv_nsec >= 1'000'000'000u) {
        wl_resource_post_error(resource, WP_COMMIT_TIMER_V1_ERROR_INVALID_TIMESTAMP,
                               "tv_nsec must be < 1e9");
        return;
    }
    if (self->m_pendingSet) {
        wl_resource_post_error(resource, WP_COMMIT_TIMER_V1_ERROR_TIMESTAMP_EXISTS,
                               "a pending timestamp already exists on this surface");
        return;
    }
    // wp_presentation clock is CLOCK_MONOTONIC; tv_sec is a 64-bit
    // unsigned packed into two 32-bit halves. Convert to ns.
    const quint64 secs         = (static_cast<quint64>(tv_sec_hi) << 32) | tv_sec_lo;
    self->m_pendingTimestampNs = static_cast<qint64>(secs) * 1'000'000'000LL + tv_nsec;
    self->m_pendingSet         = true;
}

void CommitTimerV1::handleDestroy(struct wl_client *, struct wl_resource *resource) {
    wl_resource_destroy(resource);
}

void CommitTimerV1::onSurfaceCommitted() {
    // Double-buffered apply.
    if (m_pendingSet) {
        m_activeTimestampNs  = m_pendingTimestampNs;
        m_pendingTimestampNs = 0;
        m_pendingSet         = false;
    } else {
        // No timestamp on this commit — clear the active one. Per spec
        // the timestamp is per-commit, not sticky.
        m_activeTimestampNs = 0;
    }
}

void CommitTimerV1::onSurfaceDestroyed() {
    m_surface.clear();
}
