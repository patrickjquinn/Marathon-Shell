#include "session_lock_v1.h"

#include "ext-session-lock-v1-server.h"

#include <QLoggingCategory>
#include <QWaylandCompositor>
#include <QWaylandSurface>

Q_LOGGING_CATEGORY(lcLock, "marathon.compositor.session-lock")

// Protocol version we advertise. ext_session_lock_v1 is currently v1 (the
// staging version that wayland-protocols carries; promoted to stable but
// the wire version stays 1).
static constexpr uint32_t kSessionLockVersion = 1;

// Forward decls for the manager interface vtable.
static void mgrDestroy(wl_client *, wl_resource *);
static void mgrLock(wl_client *, wl_resource *, uint32_t);
static const struct ext_session_lock_manager_v1_interface managerImpl = {
    .destroy = mgrDestroy,
    .lock    = mgrLock,
};

static void mgrDestroy(wl_client *, wl_resource *resource) {
    wl_resource_destroy(resource);
}
static void mgrLock(wl_client *client, wl_resource *resource, uint32_t id) {
    auto *mgr = static_cast<ExtSessionLockManagerV1 *>(wl_resource_get_user_data(resource));
    if (!mgr) {
        wl_client_post_no_memory(client);
        return;
    }
    new ExtSessionLockV1(mgr, client, id);
}

ExtSessionLockManagerV1::ExtSessionLockManagerV1(QWaylandCompositor *compositor)
    : QObject(compositor)
    , m_compositor(compositor) {
    wl_display *display = compositor->display();
    m_global            = wl_global_create(display, &ext_session_lock_manager_v1_interface,
                                           kSessionLockVersion, this, &bind);
    if (m_global)
        qCInfo(lcLock) << "ext_session_lock_manager_v1 v" << kSessionLockVersion
                       << "global created";
    else
        qCWarning(lcLock) << "failed to create wl_global for ext_session_lock_manager_v1";
}

ExtSessionLockManagerV1::~ExtSessionLockManagerV1() {
    if (m_global)
        wl_global_destroy(m_global);
}

void ExtSessionLockManagerV1::bind(wl_client *client, void *data, uint32_t version, uint32_t id) {
    auto        *mgr = static_cast<ExtSessionLockManagerV1 *>(data);
    const auto   ver = std::min<uint32_t>(version, kSessionLockVersion);
    wl_resource *res = wl_resource_create(client, &ext_session_lock_manager_v1_interface, ver, id);
    if (!res) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(res, &managerImpl, mgr, nullptr);
}

void ExtSessionLockManagerV1::destroyManager(wl_client *, wl_resource *resource) {
    wl_resource_destroy(resource);
}

void ExtSessionLockManagerV1::requestLock(wl_client *client, wl_resource *resource, uint32_t id) {
    // Unused — kept in the header for API symmetry; the actual handler is
    // the file-scope `mgrLock` above. The interface struct only takes free
    // functions so we route through `mgrLock`.
    Q_UNUSED(client);
    Q_UNUSED(resource);
    Q_UNUSED(id);
}

void ExtSessionLockManagerV1::setActiveLock(ExtSessionLockV1 *lock, bool nowLocked) {
    m_activeLock = lock;
    if (m_isLocked != nowLocked) {
        m_isLocked = nowLocked;
        if (nowLocked)
            emit locked();
        else
            emit unlocked();
    }
}

// -- ExtSessionLockV1 ----------------------------------------------------

static void lockDestroyReq(wl_client *, wl_resource *);
static void lockGetLockSurface(wl_client *, wl_resource *, uint32_t, wl_resource *, wl_resource *);
static void lockUnlockAndDestroy(wl_client *, wl_resource *);
static const struct ext_session_lock_v1_interface lockImpl = {
    .destroy            = lockDestroyReq,
    .get_lock_surface   = lockGetLockSurface,
    .unlock_and_destroy = lockUnlockAndDestroy,
};

static void lockDestroyReq(wl_client *, wl_resource *resource) {
    // Per spec: destroying the lock without unlock_and_destroy is a
    // protocol error if the lock was granted. For simplicity here we
    // treat it as "give up trying to lock" and just drop the resource.
    wl_resource_destroy(resource);
}

static void lockGetLockSurface(wl_client *client, wl_resource *resource, uint32_t id,
                               wl_resource *surfaceRes, wl_resource *outputRes) {
    Q_UNUSED(outputRes); // single output
    auto *lock = static_cast<ExtSessionLockV1 *>(wl_resource_get_user_data(resource));
    if (!lock) {
        wl_client_post_no_memory(client);
        return;
    }
    auto *qSurface = QWaylandSurface::fromResource(surfaceRes);
    if (!qSurface) {
        wl_resource_post_error(resource,
                               EXT_SESSION_LOCK_V1_ERROR_INVALID_DESTROY, // best available
                               "no QWaylandSurface for wl_surface");
        return;
    }
    new ExtSessionLockSurfaceV1(lock, client, id, qSurface);
}

static void lockUnlockAndDestroy(wl_client *, wl_resource *resource) {
    auto *lock = static_cast<ExtSessionLockV1 *>(wl_resource_get_user_data(resource));
    if (lock && lock->parent()) {
        if (auto *mgr = qobject_cast<ExtSessionLockManagerV1 *>(lock->parent()))
            mgr->setActiveLock(nullptr, false); // private but ExtSessionLockV1 is friend
    }
    wl_resource_destroy(resource);
}

ExtSessionLockV1::ExtSessionLockV1(ExtSessionLockManagerV1 *manager, wl_client *client, uint32_t id)
    : QObject(manager)
    , m_manager(manager) {
    m_resource =
        wl_resource_create(client, &ext_session_lock_v1_interface, kSessionLockVersion, id);
    if (!m_resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(m_resource, &lockImpl, this, &resourceDestroyed);
    // Grant the lock immediately — Marathon trusts its own shell. A
    // hardened build could refuse based on which client made the request.
    sendLocked();
    if (m_manager)
        m_manager->setActiveLock(this, true);
    qCInfo(lcLock) << "session locked";
}

ExtSessionLockV1::~ExtSessionLockV1() = default;

void ExtSessionLockV1::sendLocked() {
    if (m_resource)
        ext_session_lock_v1_send_locked(m_resource);
}

void ExtSessionLockV1::sendFinished() {
    if (m_resource)
        ext_session_lock_v1_send_finished(m_resource);
}

void ExtSessionLockV1::destroyLock(wl_client *, wl_resource *resource) {
    wl_resource_destroy(resource);
}

void ExtSessionLockV1::getLockSurface(wl_client *, wl_resource *, uint32_t, wl_resource *,
                                      wl_resource *) {
    // Unused — see lockGetLockSurface above.
}

void ExtSessionLockV1::unlockAndDestroy(wl_client *, wl_resource *) {
    // Unused — see lockUnlockAndDestroy.
}

void ExtSessionLockV1::resourceDestroyed(wl_resource *resource) {
    auto *self = static_cast<ExtSessionLockV1 *>(wl_resource_get_user_data(resource));
    if (!self)
        return;
    // Per ext-session-lock-v1: if the resource is destroyed without
    // unlock_and_destroy, the session MUST remain locked. We honor this by
    // NOT clearing m_isLocked here — the compositor stays in the locked
    // state until the next boot, exactly per the protocol contract.
    if (self->m_manager) {
        // Leave m_isLocked = true; only clear the activeLock pointer so
        // the rest of the compositor doesn't try to call a freed object.
        self->m_manager->m_activeLock = nullptr;
    }
    self->deleteLater();
    qCWarning(lcLock) << "lock client disconnected — session remains locked per protocol";
}

// -- ExtSessionLockSurfaceV1 ---------------------------------------------

static void surfDestroyReq(wl_client *, wl_resource *resource) {
    wl_resource_destroy(resource);
}
static void surfAckConfigure(wl_client *, wl_resource *resource, uint32_t serial) {
    Q_UNUSED(resource);
    Q_UNUSED(serial);
}
static const struct ext_session_lock_surface_v1_interface lockSurfaceImpl = {
    .destroy       = surfDestroyReq,
    .ack_configure = surfAckConfigure,
};

ExtSessionLockSurfaceV1::ExtSessionLockSurfaceV1(ExtSessionLockV1 *lock, wl_client *client,
                                                 uint32_t id, QWaylandSurface *surface)
    : QObject(lock)
    , m_lock(lock)
    , m_surface(surface) {
    m_resource =
        wl_resource_create(client, &ext_session_lock_surface_v1_interface, kSessionLockVersion, id);
    if (!m_resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(m_resource, &lockSurfaceImpl, this, &resourceDestroyed);
    // C-1 STUB: send a 0x0 configure so the client can commit. C-5 sends
    // the actual output size to render the lock at fullscreen.
    ++m_lastSerial;
    ext_session_lock_surface_v1_send_configure(m_resource, m_lastSerial, 0, 0);
    qCDebug(lcLock) << "lock surface created";
}

ExtSessionLockSurfaceV1::~ExtSessionLockSurfaceV1() = default;

void ExtSessionLockSurfaceV1::destroyRequest(wl_client *, wl_resource *) {}
void ExtSessionLockSurfaceV1::ackConfigure(wl_client *, wl_resource *, uint32_t) {}
void ExtSessionLockSurfaceV1::resourceDestroyed(wl_resource *resource) {
    auto *self = static_cast<ExtSessionLockSurfaceV1 *>(wl_resource_get_user_data(resource));
    if (self)
        self->deleteLater();
}
