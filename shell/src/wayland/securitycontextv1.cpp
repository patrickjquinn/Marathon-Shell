#include "securitycontextv1.h"

#include <QDebug>
#include <QWaylandClient>
#include <sys/socket.h>
#include <unistd.h>

extern "C" {
#include "security-context-v1-server.h"
}

// ── Manager ────────────────────────────────────────────────────────────

static const struct wp_security_context_manager_v1_interface s_managerImpl = {
    /* destroy        */
    [](struct wl_client *, struct wl_resource *resource) { wl_resource_destroy(resource); },
    /* create_listener */
    [](struct wl_client *client, struct wl_resource *resource, uint32_t id, int32_t listenFd,
       int32_t closeFd) {
        auto *mgr = static_cast<SecurityContextManagerV1 *>(wl_resource_get_user_data(resource));
        if (!mgr) {
            wl_resource_post_no_memory(resource);
            close(listenFd);
            close(closeFd);
            return;
        }
        // The protocol requires listenFd to already be a listening socket
        // (the engine has done socket()+bind()+listen()) and closeFd to
        // be the read end of a pipe whose write end the engine holds.
        new SecurityContextV1(mgr, client, id, listenFd, closeFd);
    },
};

SecurityContextManagerV1::SecurityContextManagerV1(QWaylandCompositor *compositor)
    : QObject(compositor)
    , m_compositor(compositor) {
    auto *display = static_cast<struct wl_display *>(compositor->display());
    if (!display) {
        qWarning() << "[security-context-v1] No wl_display; not registering global";
        return;
    }
    m_global = wl_global_create(display, &wp_security_context_manager_v1_interface,
                                /* version */ 1, this, &SecurityContextManagerV1::bindManager);
    if (!m_global) {
        qWarning() << "[security-context-v1] Failed to create wl_global";
        return;
    }
    qInfo() << "[security-context-v1] Global registered";
}

SecurityContextManagerV1::~SecurityContextManagerV1() {
    if (m_global)
        wl_global_destroy(m_global);
}

void SecurityContextManagerV1::bindManager(struct wl_client *client, void *data, uint32_t version,
                                           uint32_t id) {
    auto               *mgr      = static_cast<SecurityContextManagerV1 *>(data);
    struct wl_resource *resource = wl_resource_create(
        client, &wp_security_context_manager_v1_interface, qMin<uint32_t>(version, 1u), id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &s_managerImpl, mgr, nullptr);
}

SecurityContextManagerV1::Context
SecurityContextManagerV1::contextForClient(struct wl_client *client) const {
    return m_clients.value(client, {});
}

bool SecurityContextManagerV1::isSandboxed(struct wl_client *client) const {
    return m_clients.contains(client);
}

void SecurityContextManagerV1::registerClient(struct wl_client *client, const Context &context) {
    m_clients.insert(client, context);
    emit sandboxedClientConnected(context.engine, context.appId, context.instanceId);
    qInfo() << "[security-context-v1] Sandboxed client connected:"
            << "engine=" << context.engine << "app=" << context.appId
            << "instance=" << context.instanceId;
}

void SecurityContextManagerV1::unregisterClient(struct wl_client *client) {
    m_clients.remove(client);
}

// ── Per-context object ─────────────────────────────────────────────────

static const struct wp_security_context_v1_interface s_contextImpl = {
    SecurityContextV1::handleDestroy,  SecurityContextV1::handleSetSandboxEngine,
    SecurityContextV1::handleSetAppId, SecurityContextV1::handleSetInstanceId,
    SecurityContextV1::handleCommit,
};

SecurityContextV1::SecurityContextV1(SecurityContextManagerV1 *manager,
                                     struct wl_client *engineClient, uint32_t id, int listenFd,
                                     int closeFd)
    : QObject(manager)
    , m_manager(manager)
    , m_listenFd(listenFd)
    , m_closeFd(closeFd) {
    m_resource = wl_resource_create(engineClient, &wp_security_context_v1_interface, 1, id);
    if (!m_resource) {
        wl_client_post_no_memory(engineClient);
        close(m_listenFd);
        close(m_closeFd);
        deleteLater();
        return;
    }
    wl_resource_set_implementation(m_resource, &s_contextImpl, this,
                                   // destructor
                                   [](struct wl_resource *res) {
                                       auto *self = static_cast<SecurityContextV1 *>(
                                           wl_resource_get_user_data(res));
                                       if (self)
                                           self->deleteLater();
                                   });
}

SecurityContextV1::~SecurityContextV1() {
    if (m_listenSource)
        wl_event_source_remove(m_listenSource);
    if (m_listenFd >= 0)
        close(m_listenFd);
    if (m_closeNotifier) {
        m_closeNotifier->setEnabled(false);
        m_closeNotifier->deleteLater();
    }
    if (m_closeFd >= 0)
        close(m_closeFd);
}

void SecurityContextV1::handleSetSandboxEngine(struct wl_client *, struct wl_resource *resource,
                                               const char *name) {
    auto *self = static_cast<SecurityContextV1 *>(wl_resource_get_user_data(resource));
    if (!self || self->m_committed) {
        wl_resource_post_error(resource, WP_SECURITY_CONTEXT_V1_ERROR_ALREADY_USED,
                               "security context already committed");
        return;
    }
    if (!self->m_pending.engine.isEmpty()) {
        wl_resource_post_error(resource, WP_SECURITY_CONTEXT_V1_ERROR_ALREADY_SET,
                               "sandbox engine already set");
        return;
    }
    self->m_pending.engine = QString::fromUtf8(name);
}

void SecurityContextV1::handleSetAppId(struct wl_client *, struct wl_resource *resource,
                                       const char *appId) {
    auto *self = static_cast<SecurityContextV1 *>(wl_resource_get_user_data(resource));
    if (!self || self->m_committed) {
        wl_resource_post_error(resource, WP_SECURITY_CONTEXT_V1_ERROR_ALREADY_USED,
                               "security context already committed");
        return;
    }
    if (!self->m_pending.appId.isEmpty()) {
        wl_resource_post_error(resource, WP_SECURITY_CONTEXT_V1_ERROR_ALREADY_SET,
                               "app_id already set");
        return;
    }
    self->m_pending.appId = QString::fromUtf8(appId);
}

void SecurityContextV1::handleSetInstanceId(struct wl_client *, struct wl_resource *resource,
                                            const char *instanceId) {
    auto *self = static_cast<SecurityContextV1 *>(wl_resource_get_user_data(resource));
    if (!self || self->m_committed) {
        wl_resource_post_error(resource, WP_SECURITY_CONTEXT_V1_ERROR_ALREADY_USED,
                               "security context already committed");
        return;
    }
    if (!self->m_pending.instanceId.isEmpty()) {
        wl_resource_post_error(resource, WP_SECURITY_CONTEXT_V1_ERROR_ALREADY_SET,
                               "instance_id already set");
        return;
    }
    self->m_pending.instanceId = QString::fromUtf8(instanceId);
}

int SecurityContextV1::onListenFdReadable(int /*fd*/, uint32_t /*mask*/, void *data) {
    auto *self = static_cast<SecurityContextV1 *>(data);
    if (!self || !self->m_manager)
        return 0;

    // The engine handed us a listening socket. accept() returns a new
    // connected FD per new client; we hand it to libwayland which creates
    // a wl_client and tags it with our context.
    int peerFd = accept4(self->m_listenFd, nullptr, nullptr, SOCK_CLOEXEC | SOCK_NONBLOCK);
    if (peerFd < 0)
        return 0;

    auto *display = static_cast<struct wl_display *>(self->m_manager->m_compositor->display());
    struct wl_client *peer = wl_client_create(display, peerFd);
    if (!peer) {
        close(peerFd);
        return 0;
    }
    self->m_manager->registerClient(peer, self->m_pending);
    // Per-client unregistration on disconnect is best-effort. Sandbox
    // tagging is stable for the client's lifetime; the manager's hash
    // is reaped on compositor shutdown. We could attach a destroy
    // listener via wl_client_add_destroy_listener but the static C
    // signature requires a side-allocated wl_listener with .notify set
    // to a free function, which buys little for a hash entry that
    // costs ~32 bytes and survives only one process.
    return 0;
}

void SecurityContextV1::onCloseFdReadable() {
    // The sandbox engine closed its end of close_fd. Per protocol spec
    // the listener must be torn down (no more accepts), but already-
    // connected clients are unaffected and remain tagged.
    if (m_listenSource) {
        wl_event_source_remove(m_listenSource);
        m_listenSource = nullptr;
    }
    if (m_listenFd >= 0) {
        close(m_listenFd);
        m_listenFd = -1;
    }
    if (m_closeNotifier) {
        m_closeNotifier->setEnabled(false);
        m_closeNotifier->deleteLater();
        m_closeNotifier = nullptr;
    }
    if (m_closeFd >= 0) {
        close(m_closeFd);
        m_closeFd = -1;
    }
    qInfo() << "[security-context-v1] Listener closed for engine=" << m_pending.engine
            << "app=" << m_pending.appId;
}

void SecurityContextV1::handleCommit(struct wl_client *, struct wl_resource *resource) {
    auto *self = static_cast<SecurityContextV1 *>(wl_resource_get_user_data(resource));
    if (!self || self->m_committed) {
        wl_resource_post_error(resource, WP_SECURITY_CONTEXT_V1_ERROR_ALREADY_USED,
                               "security context already committed");
        return;
    }
    if (self->m_pending.engine.isEmpty()) {
        // Protocol: sandbox_engine is required, but the error enum only
        // has invalid_metadata for this class of bad-commit.
        wl_resource_post_error(resource, WP_SECURITY_CONTEXT_V1_ERROR_INVALID_METADATA,
                               "sandbox engine name must be set before commit");
        return;
    }
    self->m_committed = true;

    auto *display = static_cast<struct wl_display *>(self->m_manager->m_compositor->display());
    auto *loop    = wl_display_get_event_loop(display);
    self->m_listenSource = wl_event_loop_add_fd(loop, self->m_listenFd, WL_EVENT_READABLE,
                                                &SecurityContextV1::onListenFdReadable, self);

    self->m_closeNotifier = new QSocketNotifier(self->m_closeFd, QSocketNotifier::Read, self);
    QObject::connect(self->m_closeNotifier, &QSocketNotifier::activated, self,
                     &SecurityContextV1::onCloseFdReadable);

    qInfo() << "[security-context-v1] Listener committed: engine=" << self->m_pending.engine
            << "app=" << self->m_pending.appId << "instance=" << self->m_pending.instanceId;
}

void SecurityContextV1::handleDestroy(struct wl_client *, struct wl_resource *resource) {
    wl_resource_destroy(resource);
}
