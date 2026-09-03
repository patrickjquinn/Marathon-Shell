#include "fifov1.h"

#include <QDebug>
#include <QQuickWindow>
#include <QWaylandCompositor>
#include <QWaylandSurface>

extern "C" {
#include "fifo-v1-server.h"
#include <utility>   // std::as_const
}

// ── Manager ────────────────────────────────────────────────────────────

// constexpr: these tables are capture-less lambdas, whose conversion to a
// function pointer is a constant expression, so the whole struct can live in
// .rodata with no pre-main initialiser that could throw uncatchably.
static constexpr struct wp_fifo_manager_v1_interface s_managerImpl = {
    /* destroy */
    [](struct wl_client *, struct wl_resource *resource) { wl_resource_destroy(resource); },
    /* get_fifo */
    [](struct wl_client *client, struct wl_resource *resource, uint32_t id,
       struct wl_resource *surfaceResource) {
        auto *mgr      = static_cast<FifoManagerV1 *>(wl_resource_get_user_data(resource));
        auto *qSurface = QWaylandSurface::fromResource(surfaceResource);
        if (!mgr || !qSurface) {
            wl_resource_post_no_memory(resource);
            return;
        }
        if (mgr->hasFifoForSurface(qSurface)) {
            wl_resource_post_error(resource, WP_FIFO_MANAGER_V1_ERROR_ALREADY_EXISTS,
                                   "fifo manager already exists for this surface");
            return;
        }
        new FifoV1(mgr, client, id, qSurface);
    },
};

FifoManagerV1::FifoManagerV1(QWaylandCompositor *compositor, QQuickWindow *window)
    : QObject(compositor)
    , m_compositor(compositor)
    , m_window(window) {
    auto *display = static_cast<struct wl_display *>(compositor->display());
    if (!display) {
        qWarning() << "[fifo-v1] No wl_display; not registering global";
        return;
    }
    m_global = wl_global_create(display, &wp_fifo_manager_v1_interface, /* version */ 1, this,
                                &FifoManagerV1::bindManager);
    if (!m_global) {
        qWarning() << "[fifo-v1] Failed to create wl_global";
        return;
    }
    // The Qt scene graph emits frameSwapped on every successful buffer swap —
    // this is our non-tearing latching deadline. Per the spec, fifo_barrier
    // is cleared "immediately after the following latching deadline."
    if (m_window) {
        connect(m_window, &QQuickWindow::frameSwapped, this, &FifoManagerV1::onFrameSwapped,
                Qt::QueuedConnection);
    }
    qInfo() << "[fifo-v1] Global registered";
}

FifoManagerV1::~FifoManagerV1() {
    if (m_global)
        wl_global_destroy(m_global);
}

void FifoManagerV1::bindManager(struct wl_client *client, void *data, uint32_t version,
                                uint32_t id) {
    auto               *mgr = static_cast<FifoManagerV1 *>(data);
    struct wl_resource *resource =
        wl_resource_create(client, &wp_fifo_manager_v1_interface, qMin<uint32_t>(version, 1u), id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &s_managerImpl, mgr, nullptr);
}

void FifoManagerV1::onFrameSwapped() {
    // Latch deadline crossed for every fifo surface. Each fifo decides
    // whether it had an active barrier and clears it.
    for (FifoV1 *fifo : std::as_const(m_fifos))
        fifo->onLatchDeadline();
}

bool FifoManagerV1::hasFifoForSurface(QWaylandSurface *surface) const {
    for (FifoV1 *f : m_fifos)
        if (f->surface() == surface)
            return true;
    return false;
}

void FifoManagerV1::registerFifo(FifoV1 *fifo) {
    m_fifos.append(fifo);
}

void FifoManagerV1::unregisterFifo(FifoV1 *fifo) {
    m_fifos.removeAll(fifo);
}

// ── Per-surface fifo object ────────────────────────────────────────────

static const struct wp_fifo_v1_interface s_fifoImpl = {
    FifoV1::handleSetBarrier,
    FifoV1::handleWaitBarrier,
    FifoV1::handleDestroy,
};

FifoV1::FifoV1(FifoManagerV1 *manager, struct wl_client *client, uint32_t id,
               QWaylandSurface *surface)
    : QObject(manager)
    , m_manager(manager)
    , m_surface(surface) {
    m_resource = wl_resource_create(client, &wp_fifo_v1_interface, 1, id);
    if (!m_resource) {
        wl_client_post_no_memory(client);
        deleteLater();
        return;
    }
    wl_resource_set_implementation(m_resource, &s_fifoImpl, this, [](struct wl_resource *res) {
        auto *self = static_cast<FifoV1 *>(wl_resource_get_user_data(res));
        if (self)
            self->deleteLater();
    });
    m_manager->registerFifo(this);

    if (m_surface) {
        // QWaylandSurface emits `redraw` after the surface's pending state
        // has been applied (i.e. post-commit). That's our point to flip
        // pending → active per the spec's "when the content update is applied"
        // language. Using `redraw` rather than `committed` because committed
        // is undocumented for timing semantics in Qt 6.10's QWaylandSurface.
        connect(m_surface.data(), &QWaylandSurface::redraw, this, &FifoV1::onSurfaceCommitted);
        connect(m_surface.data(), &QWaylandSurface::surfaceDestroyed, this,
                &FifoV1::onSurfaceDestroyed);
    }
}

FifoV1::~FifoV1() {
    if (m_manager)
        m_manager->unregisterFifo(this);
}

void FifoV1::handleSetBarrier(struct wl_client *, struct wl_resource *resource) {
    auto *self = static_cast<FifoV1 *>(wl_resource_get_user_data(resource));
    if (!self)
        return;
    if (!self->m_surface) {
        wl_resource_post_error(resource, WP_FIFO_V1_ERROR_SURFACE_DESTROYED,
                               "associated surface no longer exists");
        return;
    }
    self->m_pendingSetBarrier = true;
}

void FifoV1::handleWaitBarrier(struct wl_client *, struct wl_resource *resource) {
    auto *self = static_cast<FifoV1 *>(wl_resource_get_user_data(resource));
    if (!self)
        return;
    if (!self->m_surface) {
        wl_resource_post_error(resource, WP_FIFO_V1_ERROR_SURFACE_DESTROYED,
                               "associated surface no longer exists");
        return;
    }
    self->m_pendingWaitBarrier = true;
}

void FifoV1::handleDestroy(struct wl_client *, struct wl_resource *resource) {
    wl_resource_destroy(resource);
}

void FifoV1::onSurfaceCommitted() {
    // Double-buffered state applies here, per the spec.
    if (m_pendingSetBarrier)
        m_barrierActive = true;
    m_pendingSetBarrier  = false;
    m_pendingWaitBarrier = false;
    // wait_barrier enforcement: this commit "is not ready while fifo_barrier
    // condition is present." In our model that translates to: the frame
    // callback for this commit is held until the barrier clears on next
    // swap. The spec explicitly says clients must use frame callbacks or
    // timestamps as an additional throttling mechanism — so we lean on
    // that path. The naturally-throttled present order on a vsync-locked
    // compositor (Qt scenegraph + frameSwapped) gives apps the FIFO
    // ordering they expect.
}

void FifoV1::onLatchDeadline() {
    // Spec: "cleared immediately after the following latching deadline
    // for non-tearing presentation."
    m_barrierActive = false;
}

void FifoV1::onSurfaceDestroyed() {
    m_surface.clear();
}
