#include "nativeclientscale.h"

#include <QCoreApplication>
#include <QFile>
#include <QWaylandCompositor>

#include <cmath>
#include <cstring>
#include <sys/types.h>
#include <utility>
#include <wayland-server-core.h>
#include <wayland-server-protocol.h>

extern "C" {
#include "fractional-scale-v1-server.h"
}

struct NativeClientScale::ClientWatch {
    wl_listener        resourceCreated;
    wl_listener        destroyed;
    NativeClientScale *self;
    wl_client         *client;
    bool               firstParty;
};

struct NativeClientScale::OutputWatch {
    wl_listener        destroyed;
    wl_resource       *output;
    wl_event_source   *pending;
    NativeClientScale *self;
};

struct NativeClientScale::FractionalScale {
    wl_listener        surfaceDestroyed;
    wl_resource       *resource;
    wl_resource       *surface;
    NativeClientScale *self;
};

struct NativeClientScale::ClientCreated {
    wl_listener        listener;
    NativeClientScale *self;
};

NativeClientScale::NativeClientScale(QWaylandCompositor *compositor)
    : QObject(compositor)
    , m_display(static_cast<wl_display *>(compositor->display())) {
    m_global = wl_global_create(m_display, &wp_fractional_scale_manager_v1_interface, 1, this,
                                &NativeClientScale::bindManager);
    m_clientCreated                  = new ClientCreated{};
    m_clientCreated->self            = this;
    m_clientCreated->listener.notify = &NativeClientScale::clientCreated;
    wl_display_add_client_created_listener(m_display, &m_clientCreated->listener);
}

NativeClientScale::~NativeClientScale() {
    wl_global_destroy(m_global);
    wl_list_remove(&m_clientCreated->listener.link);
    delete m_clientCreated;
    for (ClientWatch *watch : std::as_const(m_clients)) {
        wl_list_remove(&watch->resourceCreated.link);
        wl_list_remove(&watch->destroyed.link);
        delete watch;
    }
    for (OutputWatch *watch : std::as_const(m_outputs)) {
        if (watch->pending)
            wl_event_source_remove(watch->pending);
        wl_list_remove(&watch->destroyed.link);
        delete watch;
    }
    for (FractionalScale *fractional : std::as_const(m_fractional)) {
        if (fractional->surface)
            wl_list_remove(&fractional->surfaceDestroyed.link);
        wl_resource_set_user_data(fractional->resource, nullptr);
        delete fractional;
    }
}

qreal NativeClientScale::fromDpi(qreal dpi, qreal userScale, qreal base) {
    const qreal scale = (base > 0 ? base : dpi / 160.0) * userScale;
    return qMax(1.0, std::round(scale * 4) / 4);
}

bool NativeClientScale::startedByShell(const QByteArray &environment, qint64 shellPid) {
    const QByteArray entry = "MARATHON_SHELL_PID=" + QByteArray::number(shellPid);
    const QList<QByteArray> variables = environment.split('\0');
    for (const QByteArray &variable : variables) {
        if (variable == entry)
            return true;
    }
    return false;
}

QSize NativeClientScale::toLogical(const QSize &size, qreal scale) {
    return QSize(qRound(size.width() / scale), qRound(size.height() / scale));
}

void NativeClientScale::setScale(qreal scale) {
    if (qFuzzyCompare(scale, m_scale))
        return;
    m_scale = scale;
    for (OutputWatch *watch : std::as_const(m_outputs))
        sendOutputScale(watch);
    for (const FractionalScale *fractional : std::as_const(m_fractional))
        wp_fractional_scale_v1_send_preferred_scale(fractional->resource, toWire(m_scale));
    emit scaleChanged();
}

void NativeClientScale::clientCreated(wl_listener *listener, void *data) {
    ClientCreated     *created = wl_container_of(listener, created, listener);
    NativeClientScale *self    = created->self;
    auto              *client  = static_cast<wl_client *>(data);

    pid_t              pid = 0;
    wl_client_get_credentials(client, &pid, nullptr, nullptr);
    QFile      environment(QStringLiteral("/proc/%1/environ").arg(pid));
    const bool firstParty = pid > 0 && environment.open(QIODevice::ReadOnly) &&
        startedByShell(environment.readAll(), QCoreApplication::applicationPid());

    auto *watch                   = new ClientWatch{};
    watch->self                   = self;
    watch->client                 = client;
    watch->firstParty             = firstParty;
    watch->resourceCreated.notify = &NativeClientScale::resourceCreated;
    watch->destroyed.notify       = &NativeClientScale::clientDestroyed;
    wl_client_add_resource_created_listener(client, &watch->resourceCreated);
    wl_client_add_destroy_listener(client, &watch->destroyed);
    self->m_clients.insert(watch);
    if (firstParty)
        self->m_firstParty.insert(client);
}

void NativeClientScale::clientDestroyed(wl_listener *listener, void *) {
    ClientWatch *watch = wl_container_of(listener, watch, destroyed);
    wl_list_remove(&watch->resourceCreated.link);
    wl_list_remove(&watch->destroyed.link);
    watch->self->m_firstParty.remove(watch->client);
    watch->self->m_clients.remove(watch);
    delete watch;
}

void NativeClientScale::resourceCreated(wl_listener *listener, void *data) {
    ClientWatch *watch    = wl_container_of(listener, watch, resourceCreated);
    auto        *resource = static_cast<wl_resource *>(data);
    if (!watch->firstParty &&
        std::strcmp(wl_resource_get_class(resource), wl_output_interface.name) == 0)
        watch->self->watchOutput(resource);
}

// The resource is created before Qt's bind handler sends it scale 1, so the
// native scale goes out on the next idle, after it.
void NativeClientScale::watchOutput(wl_resource *output) {
    if (wl_resource_get_version(output) < WL_OUTPUT_SCALE_SINCE_VERSION)
        return;
    auto *watch             = new OutputWatch{};
    watch->self             = this;
    watch->output           = output;
    watch->destroyed.notify = &NativeClientScale::outputDestroyed;
    wl_resource_add_destroy_listener(output, &watch->destroyed);
    watch->pending = wl_event_loop_add_idle(wl_display_get_event_loop(m_display),
                                            &NativeClientScale::sendOutputScale, watch);
    m_outputs.insert(watch);
}

void NativeClientScale::outputDestroyed(wl_listener *listener, void *) {
    OutputWatch *watch = wl_container_of(listener, watch, destroyed);
    if (watch->pending)
        wl_event_source_remove(watch->pending);
    wl_list_remove(&watch->destroyed.link);
    watch->self->m_outputs.remove(watch);
    delete watch;
}

void NativeClientScale::sendOutputScale(void *data) {
    auto *watch    = static_cast<OutputWatch *>(data);
    watch->pending = nullptr;
    wl_output_send_scale(watch->output, static_cast<int32_t>(std::ceil(watch->self->m_scale)));
    wl_output_send_done(watch->output);
}

void NativeClientScale::bindManager(wl_client *client, void *data, uint32_t version, uint32_t id) {
    static constexpr struct wp_fractional_scale_manager_v1_interface impl = {
        /* destroy */
        [](wl_client *, wl_resource *resource) { wl_resource_destroy(resource); },
        /* get_fractional_scale */
        &NativeClientScale::getFractionalScale,
    };
    wl_resource *resource = wl_resource_create(client, &wp_fractional_scale_manager_v1_interface,
                                               static_cast<int>(qMin(version, 1u)), id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &impl, data, nullptr);
}

void NativeClientScale::getFractionalScale(wl_client *client, wl_resource *manager, uint32_t id,
                                           wl_resource *surface) {
    static constexpr struct wp_fractional_scale_v1_interface impl = {
        /* destroy */
        [](wl_client *, wl_resource *resource) { wl_resource_destroy(resource); },
    };
    auto *self = static_cast<NativeClientScale *>(wl_resource_get_user_data(manager));
    for (const FractionalScale *fractional : std::as_const(self->m_fractional)) {
        if (fractional->surface == surface) {
            wl_resource_post_error(manager,
                                   WP_FRACTIONAL_SCALE_MANAGER_V1_ERROR_FRACTIONAL_SCALE_EXISTS,
                                   "the surface already has a fractional_scale object");
            return;
        }
    }
    wl_resource *resource = wl_resource_create(client, &wp_fractional_scale_v1_interface,
                                               wl_resource_get_version(manager), id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    auto *fractional                    = new FractionalScale{};
    fractional->self                    = self;
    fractional->resource                = resource;
    fractional->surface                 = surface;
    fractional->surfaceDestroyed.notify = &NativeClientScale::surfaceDestroyed;
    wl_resource_add_destroy_listener(surface, &fractional->surfaceDestroyed);
    wl_resource_set_implementation(resource, &impl, fractional,
                                   &NativeClientScale::fractionalDestroyed);
    self->m_fractional.insert(fractional);
    wp_fractional_scale_v1_send_preferred_scale(resource, toWire(self->scaleFor(client)));
}

// The object outlives its surface as an inert one until the client drops it.
void NativeClientScale::surfaceDestroyed(wl_listener *listener, void *) {
    FractionalScale *fractional = wl_container_of(listener, fractional, surfaceDestroyed);
    wl_list_remove(&fractional->surfaceDestroyed.link);
    fractional->surface = nullptr;
}

void NativeClientScale::fractionalDestroyed(wl_resource *resource) {
    auto *fractional = static_cast<FractionalScale *>(wl_resource_get_user_data(resource));
    if (!fractional)
        return;
    if (fractional->surface)
        wl_list_remove(&fractional->surfaceDestroyed.link);
    fractional->self->m_fractional.remove(fractional);
    delete fractional;
}
