#include "securitycontextv1.h"

#include <QDebug>
#include <QWaylandCompositor>

#include <cstring>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>
#include <wayland-server-core.h>

extern "C" {
#include "security-context-v1-server.h"
}

// What a sandboxed client must not reach: capturing or reading other
// clients' content, injecting input, placing surfaces above other apps,
// controlling outputs, or minting a new, less restricted context. The same
// set sway's is_privileged() hides.
static constexpr const char *kPrivilegedInterfaces[] = {
    "wp_security_context_manager_v1",
    "zwlr_screencopy_manager_v1",
    "ext_image_copy_capture_manager_v1",
    "ext_output_image_capture_source_manager_v1",
    "ext_foreign_toplevel_image_capture_source_manager_v1",
    "zwlr_export_dmabuf_manager_v1",
    "zwlr_data_control_manager_v1",
    "ext_data_control_manager_v1",
    "zwp_input_method_manager_v2",
    "zwp_input_method_v1",
    "zwp_input_panel_v1",
    "zwp_virtual_keyboard_manager_v1",
    "zwlr_virtual_pointer_manager_v1",
    "zwp_keyboard_shortcuts_inhibit_manager_v1",
    "ext_transient_seat_manager_v1",
    "zwlr_layer_shell_v1",
    "ext_session_lock_manager_v1",
    "zwlr_foreign_toplevel_manager_v1",
    "ext_foreign_toplevel_list_v1",
    "ext_workspace_manager_v1",
    "zwlr_output_manager_v1",
    "zwlr_output_power_manager_v1",
    "zwlr_gamma_control_manager_v1",
    "zxdg_output_manager_v1",
    "wp_drm_lease_device_v1",
};

struct SecurityContextManagerV1::Listener {
    SecurityContextManagerV1 *self;
    Context                   context;
    QString                   path;
    int                       listenFd;
    int                       closeFd;
    wl_event_source          *listenSource = nullptr;
    wl_event_source          *closeSource  = nullptr;
};

struct SecurityContextManagerV1::ClientWatch {
    wl_listener               destroyed;
    SecurityContextManagerV1 *self;
    wl_client                *client;
    Context                   context;
};

// A wp_security_context_v1 before commit. Committing hands the fds to a
// Listener, which outlives this object and the engine's connection.
struct SecurityContextManagerV1::Pending {
    SecurityContextManagerV1 *self;
    Context                   context;
    int                       listenFd;
    int                       closeFd;
    bool                      committed = false;
};

SecurityContextManagerV1::SecurityContextManagerV1(QWaylandCompositor *compositor)
    : QObject(compositor)
    , m_display(static_cast<wl_display *>(compositor->display())) {
    m_global = wl_global_create(m_display, &wp_security_context_manager_v1_interface, 1, this,
                                &SecurityContextManagerV1::bindManager);
}

SecurityContextManagerV1::~SecurityContextManagerV1() {
    wl_global_destroy(m_global);
    while (!m_listeners.isEmpty())
        destroyListener(m_listeners.constFirst());
    for (ClientWatch *watch : std::as_const(m_clients)) {
        wl_list_remove(&watch->destroyed.link);
        delete watch;
    }
}

bool SecurityContextManagerV1::isPrivileged(const char *interface) {
    for (const char *name : kPrivilegedInterfaces) {
        if (std::strcmp(name, interface) == 0)
            return true;
    }
    return false;
}

bool SecurityContextManagerV1::allowsGlobal(const wl_client *client,
                                            const wl_global *global) const {
    return !isSandboxed(client) || !isPrivileged(wl_global_get_interface(global)->name);
}

SecurityContextManagerV1::Context
SecurityContextManagerV1::contextForClient(const wl_client *client) const {
    const ClientWatch *watch = m_clients.value(client);
    return watch ? watch->context : Context{};
}

bool SecurityContextManagerV1::listen(const QString &path, const Context &context) {
    const QByteArray encoded = path.toLocal8Bit();
    sockaddr_un      address{};
    address.sun_family = AF_UNIX;
    if (encoded.size() >= qsizetype(sizeof(address.sun_path))) {
        qWarning() << "[security-context-v1] Socket path too long:" << path;
        return false;
    }
    std::memcpy(address.sun_path, encoded.constData(), encoded.size());
    const int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    if (fd < 0)
        return false;
    unlink(encoded.constData());
    if (bind(fd, reinterpret_cast<sockaddr *>(&address), sizeof(address)) != 0 ||
        ::listen(fd, 128) != 0) {
        qWarning() << "[security-context-v1] Cannot listen on" << path << ":" << strerror(errno);
        close(fd);
        return false;
    }
    addListener(fd, -1, context, path);
    return true;
}

void SecurityContextManagerV1::closeListener(const QString &instanceId) {
    for (Listener *listener : std::as_const(m_listeners)) {
        if (listener->context.instanceId == instanceId) {
            destroyListener(listener);
            return;
        }
    }
}

void SecurityContextManagerV1::assignAppId(const QString &instanceId, const QString &appId) {
    for (Listener *listener : std::as_const(m_listeners)) {
        if (listener->context.instanceId == instanceId && listener->context.appId.isEmpty())
            listener->context.appId = appId;
    }
    for (ClientWatch *watch : std::as_const(m_clients)) {
        if (watch->context.instanceId == instanceId && watch->context.appId.isEmpty())
            watch->context.appId = appId;
    }
}

void SecurityContextManagerV1::addListener(int listenFd, int closeFd, const Context &context,
                                           const QString &path) {
    auto          *listener = new Listener{this, context, path, listenFd, closeFd};
    wl_event_loop *loop     = wl_display_get_event_loop(m_display);
    listener->listenSource  = wl_event_loop_add_fd(
        loop, listenFd, WL_EVENT_READABLE, &SecurityContextManagerV1::acceptClient, listener);
    if (closeFd >= 0)
        listener->closeSource = wl_event_loop_add_fd(
            loop, closeFd, 0, &SecurityContextManagerV1::closeFdEvent, listener);
    m_listeners << listener;
    qInfo() << "[security-context-v1] Listening: engine=" << context.engine
            << "app=" << context.appId << "instance=" << context.instanceId;
}

// Clients that already connected keep their context.
void SecurityContextManagerV1::destroyListener(Listener *listener) {
    m_listeners.removeOne(listener);
    wl_event_source_remove(listener->listenSource);
    if (listener->closeSource)
        wl_event_source_remove(listener->closeSource);
    close(listener->listenFd);
    if (listener->closeFd >= 0)
        close(listener->closeFd);
    if (!listener->path.isEmpty())
        unlink(listener->path.toLocal8Bit().constData());
    qInfo() << "[security-context-v1] Listener closed: app=" << listener->context.appId
            << "instance=" << listener->context.instanceId;
    delete listener;
}

int SecurityContextManagerV1::acceptClient(int fd, uint32_t, void *data) {
    auto     *listener = static_cast<Listener *>(data);
    const int peer     = accept4(fd, nullptr, nullptr, SOCK_CLOEXEC);
    if (peer < 0)
        return 0;
    SecurityContextManagerV1 *self   = listener->self;
    wl_client                *client = wl_client_create(self->m_display, peer);
    if (!client) {
        close(peer);
        return 0;
    }
    auto *watch             = new ClientWatch{{}, self, client, listener->context};
    watch->destroyed.notify = &SecurityContextManagerV1::clientDestroyed;
    wl_client_add_destroy_listener(client, &watch->destroyed);
    self->m_clients.insert(client, watch);

    pid_t pid = 0;
    wl_client_get_credentials(client, &pid, nullptr, nullptr);
    qInfo() << "[security-context-v1] Sandboxed client: engine=" << listener->context.engine
            << "app=" << listener->context.appId << "instance=" << listener->context.instanceId
            << "pid=" << pid;
    return 0;
}

int SecurityContextManagerV1::closeFdEvent(int, uint32_t mask, void *data) {
    auto *listener = static_cast<Listener *>(data);
    if (mask & (uint32_t(WL_EVENT_HANGUP) | uint32_t(WL_EVENT_ERROR)))
        listener->self->destroyListener(listener);
    return 0;
}

void SecurityContextManagerV1::clientDestroyed(wl_listener *listener, void *) {
    ClientWatch *watch = wl_container_of(listener, watch, destroyed);
    wl_list_remove(&watch->destroyed.link);
    watch->self->m_clients.remove(watch->client);
    delete watch;
}

void SecurityContextManagerV1::bindManager(wl_client *client, void *data, uint32_t version,
                                           uint32_t id) {
    static constexpr struct wp_security_context_manager_v1_interface impl = {
        /* destroy */
        [](wl_client *, wl_resource *resource) { wl_resource_destroy(resource); },
        /* create_listener */
        &SecurityContextManagerV1::createListener,
    };
    wl_resource *resource = wl_resource_create(client, &wp_security_context_manager_v1_interface,
                                               static_cast<int>(qMin(version, 1u)), id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &impl, data, nullptr);
}

void SecurityContextManagerV1::createListener(wl_client *client, wl_resource *manager, uint32_t id,
                                              int32_t listenFd, int32_t closeFd) {
    static constexpr struct wp_security_context_v1_interface impl = {
        /* destroy */
        [](wl_client *, wl_resource *resource) { wl_resource_destroy(resource); },
        /* set_sandbox_engine */
        [](wl_client *, wl_resource *resource, const char *name) {
            setMetadata(resource, &Context::engine, name, "sandbox_engine");
        },
        /* set_app_id */
        [](wl_client *, wl_resource *resource, const char *appId) {
            setMetadata(resource, &Context::appId, appId, "app_id");
        },
        /* set_instance_id */
        [](wl_client *, wl_resource *resource, const char *instanceId) {
            setMetadata(resource, &Context::instanceId, instanceId, "instance_id");
        },
        &SecurityContextManagerV1::commit,
    };
    auto     *self = static_cast<SecurityContextManagerV1 *>(wl_resource_get_user_data(manager));
    int       listening = 0;
    socklen_t length    = sizeof(listening);
    if (getsockopt(listenFd, SOL_SOCKET, SO_ACCEPTCONN, &listening, &length) != 0 || !listening) {
        close(listenFd);
        close(closeFd);
        wl_resource_post_error(manager, WP_SECURITY_CONTEXT_MANAGER_V1_ERROR_INVALID_LISTEN_FD,
                               "listen_fd is not a listening socket");
        return;
    }
    wl_resource *resource = wl_resource_create(client, &wp_security_context_v1_interface,
                                               wl_resource_get_version(manager), id);
    if (!resource) {
        close(listenFd);
        close(closeFd);
        wl_client_post_no_memory(client);
        return;
    }
    auto *pending = new Pending{self, {}, listenFd, closeFd};
    wl_resource_set_implementation(resource, &impl, pending,
                                   &SecurityContextManagerV1::pendingDestroyed);
}

void SecurityContextManagerV1::pendingDestroyed(wl_resource *resource) {
    auto *pending = static_cast<Pending *>(wl_resource_get_user_data(resource));
    if (!pending->committed) {
        close(pending->listenFd);
        close(pending->closeFd);
    }
    delete pending;
}

void SecurityContextManagerV1::setMetadata(wl_resource *resource, QString Context::*field,
                                           const char *value, const char *what) {
    auto *pending = static_cast<Pending *>(wl_resource_get_user_data(resource));
    if (pending->committed) {
        wl_resource_post_error(resource, WP_SECURITY_CONTEXT_V1_ERROR_ALREADY_USED,
                               "security context already committed");
    } else if (!(pending->context.*field).isEmpty()) {
        wl_resource_post_error(resource, WP_SECURITY_CONTEXT_V1_ERROR_ALREADY_SET, "%s already set",
                               what);
    } else {
        pending->context.*field = QString::fromUtf8(value);
    }
}

void SecurityContextManagerV1::commit(wl_client *, wl_resource *resource) {
    auto *pending = static_cast<Pending *>(wl_resource_get_user_data(resource));
    if (pending->committed) {
        wl_resource_post_error(resource, WP_SECURITY_CONTEXT_V1_ERROR_ALREADY_USED,
                               "security context already committed");
        return;
    }
    if (pending->context.engine.isEmpty()) {
        wl_resource_post_error(resource, WP_SECURITY_CONTEXT_V1_ERROR_INVALID_METADATA,
                               "sandbox engine must be set before commit");
        return;
    }
    pending->committed = true;
    pending->self->addListener(pending->listenFd, pending->closeFd, pending->context, QString());
}
