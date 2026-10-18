#include "xdgactivationv1.h"

#include <QDebug>
#include <QRandomGenerator>
#include <QWaylandClient>
#include <QWaylandCompositor>
#include <QWaylandSeat>
#include <QWaylandSurface>

extern "C" {
#include "xdg-activation-v1-server.h"
}

namespace {

    struct PendingToken {
        XdgActivationV1 *manager   = nullptr;
        uint32_t         serial    = 0;
        bool             hasSerial = false;
        bool             committed = false;
    };

    PendingToken *pendingToken(wl_resource *resource) {
        return static_cast<PendingToken *>(wl_resource_get_user_data(resource));
    }

    bool refuseIfCommitted(wl_resource *resource) {
        if (!pendingToken(resource)->committed)
            return false;
        wl_resource_post_error(resource, XDG_ACTIVATION_TOKEN_V1_ERROR_ALREADY_USED,
                               "token already committed");
        return true;
    }

} // namespace

static constexpr struct xdg_activation_token_v1_interface s_tokenImpl = {
    /* set_serial */
    [](wl_client *, wl_resource *resource, uint32_t serial, wl_resource *) {
        if (refuseIfCommitted(resource))
            return;
        pendingToken(resource)->serial    = serial;
        pendingToken(resource)->hasSerial = true;
    },
    /* set_app_id */
    [](wl_client *, wl_resource *resource, const char *) { refuseIfCommitted(resource); },
    /* set_surface */
    [](wl_client *, wl_resource *resource, wl_resource *) { refuseIfCommitted(resource); },
    /* commit */
    [](wl_client *client, wl_resource *resource) {
        XdgActivationV1::commitToken(client, resource);
    },
    /* destroy */
    [](wl_client *, wl_resource *resource) { wl_resource_destroy(resource); },
};

static constexpr struct xdg_activation_v1_interface s_managerImpl = {
    /* destroy */
    [](wl_client *, wl_resource *resource) { wl_resource_destroy(resource); },
    /* get_activation_token */
    [](wl_client *client, wl_resource *resource, uint32_t id) {
        XdgActivationV1::createToken(client, resource, id);
    },
    /* activate */
    [](wl_client *client, wl_resource *resource, const char *token, wl_resource *surface) {
        XdgActivationV1::activate(client, resource, token, surface);
    },
};

XdgActivationV1::XdgActivationV1(QWaylandCompositor *compositor)
    : QObject(compositor)
    , m_compositor(compositor) {
    m_clock.start();
    m_global = wl_global_create(compositor->display(), &xdg_activation_v1_interface, 1, this,
                                &XdgActivationV1::bind);
}

XdgActivationV1::~XdgActivationV1() {
    if (m_global)
        wl_global_destroy(m_global);
}

void XdgActivationV1::bind(wl_client *client, void *data, uint32_t version, uint32_t id) {
    wl_resource *resource =
        wl_resource_create(client, &xdg_activation_v1_interface, qMin<uint32_t>(version, 1u), id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &s_managerImpl, data, nullptr);
}

void XdgActivationV1::createToken(wl_client *client, wl_resource *manager, uint32_t id) {
    wl_resource *resource = wl_resource_create(client, &xdg_activation_token_v1_interface,
                                               wl_resource_get_version(manager), id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    auto *pending    = new PendingToken;
    pending->manager = static_cast<XdgActivationV1 *>(wl_resource_get_user_data(manager));
    wl_resource_set_implementation(resource, &s_tokenImpl, pending,
                                   [](wl_resource *r) { delete pendingToken(r); });
}

// A refused request still gets a token, so the client cannot tell; the
// token just activates nothing.
void XdgActivationV1::commitToken(wl_client *client, wl_resource *resource) {
    if (refuseIfCommitted(resource))
        return;
    PendingToken *pending  = pendingToken(resource);
    pending->committed     = true;
    XdgActivationV1 *self  = pending->manager;
    const QString    token = pending->hasSerial && self->mayActivate(client, pending->serial) ?
        self->addToken(nullptr, kClientTokenMs) :
        newToken();
    xdg_activation_token_v1_send_done(resource, token.toUtf8().constData());
}

void XdgActivationV1::activate(wl_client *, wl_resource *manager, const char *token,
                               wl_resource *surfaceResource) {
    auto         *self = static_cast<XdgActivationV1 *>(wl_resource_get_user_data(manager));
    const QString key  = QString::fromUtf8(token);
    if (!self->m_tokens.contains(key))
        return;
    const Token      found   = self->m_tokens.take(key);
    QWaylandSurface *surface = QWaylandSurface::fromResource(surfaceResource);
    if (!surface || found.expiresMs < self->m_clock.elapsed())
        return;
    emit self->activated(surface, found.launch.data());
}

QString XdgActivationV1::issueToken(QObject *launch) {
    return addToken(launch, kLaunchTokenMs);
}

QString XdgActivationV1::newToken() {
    quint64 bits[2];
    QRandomGenerator::system()->fillRange(bits);
    return QString::fromLatin1(
        QByteArray(reinterpret_cast<const char *>(bits), sizeof(bits)).toHex());
}

QString XdgActivationV1::addToken(QObject *launch, qint64 lifetimeMs) {
    const qint64 now = m_clock.elapsed();
    m_tokens.removeIf([now](const auto &entry) { return entry.value().expiresMs < now; });
    const QString token = newToken();
    m_tokens.insert(token, {launch, now + lifetimeMs});
    return token;
}

void XdgActivationV1::noteUserInput() {
    m_inputSerial = wl_display_get_serial(m_compositor->display());
    m_hadInput    = true;
}

bool XdgActivationV1::serialAfter(uint32_t serial, uint32_t mark, uint32_t now) {
    return uint32_t(serial - mark) - 1u < uint32_t(now - mark);
}

bool XdgActivationV1::mayActivate(wl_client *client, uint32_t serial) const {
    QWaylandSeat          *seat  = m_compositor->defaultSeat();
    const QWaylandSurface *focus = seat ? seat->keyboardFocus() : nullptr;
    if (!m_hadInput || !focus || !focus->client() || focus->client()->client() != client)
        return false;
    return serialAfter(serial, m_inputSerial, wl_display_get_serial(m_compositor->display()));
}
