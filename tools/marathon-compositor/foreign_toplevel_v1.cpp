#include "foreign_toplevel_v1.h"

// wayland-scanner output for this protocol — server-header path matches
// the marathon_wayland_protocol() CMake function which strips `.xml`.
#include "wlr-foreign-toplevel-management-unstable-v1-server.h"

#include <QLoggingCategory>
#include <QWaylandCompositor>
#include <QWaylandSeat>
#include <QWaylandSurface>
#include <QWaylandXdgSurface>
#include <QWaylandXdgToplevel>

Q_LOGGING_CATEGORY(lcFT, "marathon.compositor.foreign-toplevel")

// We advertise v3 — adds the `parent` event (Qt's xdg-shell surfaces
// don't track parent toplevels through this protocol path, so we always
// send a null parent, which is the v3 default). Older clients negotiate
// down to v1/v2 automatically; nothing they care about goes away.
static constexpr uint32_t kForeignToplevelVersion = 3;

// -- manager bind / requests --------------------------------------------

static void mgrStop(wl_client *, wl_resource *resource) {
    // Stop is "the client doesn't want more updates" — destroy the
    // manager resource and send `finished`. Subsequent toplevels won't
    // be reported to this client.
    zwlr_foreign_toplevel_manager_v1_send_finished(resource);
    wl_resource_destroy(resource);
}

static const struct zwlr_foreign_toplevel_manager_v1_interface managerImpl = {
    .stop = mgrStop,
};

ForeignToplevelManagerV1::ForeignToplevelManagerV1(QWaylandCompositor *compositor)
    : QObject(compositor)
    , m_compositor(compositor) {
    wl_display *display = compositor->display();
    m_global            = wl_global_create(display, &zwlr_foreign_toplevel_manager_v1_interface,
                                           kForeignToplevelVersion, this, &bind);
    if (m_global)
        qCInfo(lcFT) << "zwlr_foreign_toplevel_manager_v1 v" << kForeignToplevelVersion
                     << "global created";
    else
        qCWarning(lcFT) << "failed to create wl_global for zwlr_foreign_toplevel_manager_v1";
}

ForeignToplevelManagerV1::~ForeignToplevelManagerV1() {
    if (m_global)
        wl_global_destroy(m_global);
}

void ForeignToplevelManagerV1::bind(wl_client *client, void *data, uint32_t version, uint32_t id) {
    auto        *mgr = static_cast<ForeignToplevelManagerV1 *>(data);
    const auto   ver = std::min<uint32_t>(version, kForeignToplevelVersion);
    wl_resource *res =
        wl_resource_create(client, &zwlr_foreign_toplevel_manager_v1_interface, ver, id);
    if (!res) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(
        res, &managerImpl, mgr, +[](wl_resource *r) {
            auto *m = static_cast<ForeignToplevelManagerV1 *>(wl_resource_get_user_data(r));
            if (m)
                m->m_managerResources.removeAll(r);
        });
    mgr->m_managerResources.append(res);
    mgr->notifyBound(res);
    qCDebug(lcFT) << "client bound foreign-toplevel-manager v" << ver << "— replaying"
                  << mgr->m_handlesByToplevel.size() << "existing handles";
}

void ForeignToplevelManagerV1::notifyBound(wl_resource *managerResource) {
    // Replay every existing handle to the freshly-bound manager.
    for (auto it = m_handlesByToplevel.constBegin(); it != m_handlesByToplevel.constEnd(); ++it) {
        it.value()->emitToplevelTo(managerResource);
    }
}

void ForeignToplevelManagerV1::registerToplevel(QWaylandXdgToplevel *toplevel) {
    if (!toplevel)
        return;
    if (m_handlesByToplevel.contains(toplevel))
        return;
    auto *handle                  = new ForeignToplevelHandleV1(this, toplevel);
    m_handlesByToplevel[toplevel] = handle;
    qCInfo(lcFT) << "new toplevel registered, broadcasting to" << m_managerResources.size()
                 << "manager(s)";
    broadcastNewHandle(handle);
}

void ForeignToplevelManagerV1::broadcastNewHandle(ForeignToplevelHandleV1 *handle) {
    for (auto *mgrResource : std::as_const(m_managerResources)) {
        handle->emitToplevelTo(mgrResource);
    }
}

// -- handle -------------------------------------------------------------

static const struct zwlr_foreign_toplevel_handle_v1_interface handleImpl = {
    .set_maximized    = ForeignToplevelHandleV1::onSetMaximized,
    .unset_maximized  = ForeignToplevelHandleV1::onUnsetMaximized,
    .set_minimized    = ForeignToplevelHandleV1::onSetMinimized,
    .unset_minimized  = ForeignToplevelHandleV1::onUnsetMinimized,
    .activate         = ForeignToplevelHandleV1::onActivate,
    .close            = ForeignToplevelHandleV1::onClose,
    .set_rectangle    = ForeignToplevelHandleV1::onSetRectangle,
    .destroy          = ForeignToplevelHandleV1::onDestroyHandle,
    .set_fullscreen   = ForeignToplevelHandleV1::onSetFullscreen,
    .unset_fullscreen = ForeignToplevelHandleV1::onUnsetFullscreen,
};

ForeignToplevelHandleV1::ForeignToplevelHandleV1(ForeignToplevelManagerV1 *manager,
                                                 QWaylandXdgToplevel      *toplevel)
    : QObject(manager)
    , m_manager(manager)
    , m_toplevel(toplevel) {
    if (!toplevel)
        return;

    // Snapshot initial properties so the first done() sends a complete state.
    m_title = toplevel->title();
    m_appId = toplevel->appId();

    // Wire up live updates from the underlying xdg_toplevel.
    connect(toplevel, &QWaylandXdgToplevel::titleChanged, this, [this]() {
        if (!m_toplevel)
            return;
        const QString t = m_toplevel->title();
        if (t == m_title)
            return;
        m_title = t;
        sendTitleAll(t);
        sendDoneAll();
    });
    connect(toplevel, &QWaylandXdgToplevel::appIdChanged, this, [this]() {
        if (!m_toplevel)
            return;
        const QString a = m_toplevel->appId();
        if (a == m_appId)
            return;
        m_appId = a;
        sendAppIdAll(a);
        sendDoneAll();
    });
    // QWaylandXdgToplevel doesn't expose an "activated" signal directly,
    // but activate() is driven by the compositor's seat focus. We emit
    // state changes from outside via a manual call when focus shifts;
    // for now (C-3) the activated bit is set on initial mapping if the
    // surface is the current focus. C-3+ will hook seat focus changes.
    auto *xdgSurface = toplevel->xdgSurface();
    if (xdgSurface) {
        connect(xdgSurface->surface(), &QWaylandSurface::surfaceDestroyed, this, [this]() {
            sendClosedAll();
            if (m_manager)
                m_manager->m_handlesByToplevel.remove(m_toplevel);
            deleteLater();
        });
    }
}

ForeignToplevelHandleV1::~ForeignToplevelHandleV1() = default;

void ForeignToplevelHandleV1::emitToplevelTo(wl_resource *managerResource) {
    wl_client   *client = wl_resource_get_client(managerResource);
    const auto   ver    = wl_resource_get_version(managerResource);
    wl_resource *res =
        wl_resource_create(client, &zwlr_foreign_toplevel_handle_v1_interface, ver, 0);
    if (!res) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(res, &handleImpl, this, &resourceDestroyed);
    m_resources.append(res);

    zwlr_foreign_toplevel_manager_v1_send_toplevel(managerResource, res);

    // Burst the current state to the new resource. Client will see
    // title → app_id → state → done in one frame.
    if (!m_title.isEmpty())
        zwlr_foreign_toplevel_handle_v1_send_title(res, m_title.toUtf8().constData());
    if (!m_appId.isEmpty())
        zwlr_foreign_toplevel_handle_v1_send_app_id(res, m_appId.toUtf8().constData());

    wl_array state;
    wl_array_init(&state);
    if (m_activated) {
        auto *entry = static_cast<uint32_t *>(wl_array_add(&state, sizeof(uint32_t)));
        if (entry)
            *entry = ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_ACTIVATED;
    }
    zwlr_foreign_toplevel_handle_v1_send_state(res, &state);
    wl_array_release(&state);

    zwlr_foreign_toplevel_handle_v1_send_done(res);
}

void ForeignToplevelHandleV1::sendDoneAll() {
    for (auto *res : std::as_const(m_resources))
        zwlr_foreign_toplevel_handle_v1_send_done(res);
}
void ForeignToplevelHandleV1::sendTitleAll(const QString &title) {
    const QByteArray utf8 = title.toUtf8();
    for (auto *res : std::as_const(m_resources))
        zwlr_foreign_toplevel_handle_v1_send_title(res, utf8.constData());
}
void ForeignToplevelHandleV1::sendAppIdAll(const QString &appId) {
    const QByteArray utf8 = appId.toUtf8();
    for (auto *res : std::as_const(m_resources))
        zwlr_foreign_toplevel_handle_v1_send_app_id(res, utf8.constData());
}
void ForeignToplevelHandleV1::sendStateAll() {
    wl_array state;
    wl_array_init(&state);
    if (m_activated) {
        auto *entry = static_cast<uint32_t *>(wl_array_add(&state, sizeof(uint32_t)));
        if (entry)
            *entry = ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_ACTIVATED;
    }
    for (auto *res : std::as_const(m_resources))
        zwlr_foreign_toplevel_handle_v1_send_state(res, &state);
    wl_array_release(&state);
}
void ForeignToplevelHandleV1::sendClosedAll() {
    for (auto *res : std::as_const(m_resources))
        zwlr_foreign_toplevel_handle_v1_send_closed(res);
}

// Static request handlers. All but activate/close are no-ops in Marathon
// (mobile single-window UX, no maximize/minimize/fullscreen semantics).

void ForeignToplevelHandleV1::onActivate(wl_client *, wl_resource *resource, wl_resource *seatRes) {
    Q_UNUSED(seatRes);
    auto *self = static_cast<ForeignToplevelHandleV1 *>(wl_resource_get_user_data(resource));
    if (!self || !self->m_toplevel)
        return;
    // Activate = focus this surface. The xdg-shell QWaylandSeat owns
    // keyboard focus; setting it here equivalently brings the surface
    // to the front in the compositor's scene (the QML side observes
    // QWaylandSeat::keyboardFocus and re-stacks accordingly — wired in
    // the compositor.qml updates from C-3 onward).
    auto *xdgSurface = self->m_toplevel->xdgSurface();
    if (!xdgSurface)
        return;
    auto *surface = xdgSurface->surface();
    if (!surface)
        return;
    auto *compositor = surface->compositor();
    if (!compositor)
        return;
    if (auto *seat = compositor->defaultSeat())
        seat->setKeyboardFocus(surface);
    self->m_activated = true;
    self->sendStateAll();
    self->sendDoneAll();
    qCDebug(lcFT) << "activate" << self->m_appId;
}

void ForeignToplevelHandleV1::onClose(wl_client *, wl_resource *resource) {
    auto *self = static_cast<ForeignToplevelHandleV1 *>(wl_resource_get_user_data(resource));
    if (self && self->m_toplevel)
        self->m_toplevel->sendClose();
    qCDebug(lcFT) << "close" << (self ? self->m_appId : QString());
}

void ForeignToplevelHandleV1::onSetMaximized(wl_client *, wl_resource *) {}
void ForeignToplevelHandleV1::onUnsetMaximized(wl_client *, wl_resource *) {}
void ForeignToplevelHandleV1::onSetMinimized(wl_client *, wl_resource *) {}
void ForeignToplevelHandleV1::onUnsetMinimized(wl_client *, wl_resource *) {}
void ForeignToplevelHandleV1::onSetFullscreen(wl_client *, wl_resource *, wl_resource *) {}
void ForeignToplevelHandleV1::onUnsetFullscreen(wl_client *, wl_resource *) {}
void ForeignToplevelHandleV1::onSetRectangle(wl_client *, wl_resource *, wl_resource *, int32_t,
                                             int32_t, int32_t, int32_t) {}

void ForeignToplevelHandleV1::onDestroyHandle(wl_client *, wl_resource *resource) {
    wl_resource_destroy(resource);
}

void ForeignToplevelHandleV1::resourceDestroyed(wl_resource *resource) {
    auto *self = static_cast<ForeignToplevelHandleV1 *>(wl_resource_get_user_data(resource));
    if (self)
        self->m_resources.removeAll(resource);
}
