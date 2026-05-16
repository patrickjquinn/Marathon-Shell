#include "textinputv3.h"
#include "text-input-unstable-v3-server.h"
#include <QDebug>

static const struct zwp_text_input_manager_v3_interface managerInterface = {
    .destroy        = TextInputManagerV3::handleManagerDestroy,
    .get_text_input = TextInputManagerV3::handleGetTextInput};

static const struct zwp_text_input_v3_interface textInputInterface = {
    .destroy               = TextInputV3::handleDestroy,
    .enable                = TextInputV3::handleEnable,
    .disable               = TextInputV3::handleDisable,
    .set_surrounding_text  = TextInputV3::handleSetSurroundingText,
    .set_text_change_cause = TextInputV3::handleSetTextChangeCause,
    .set_content_type      = TextInputV3::handleSetContentType,
    .set_cursor_rectangle  = TextInputV3::handleSetCursorRectangle,
    .commit                = TextInputV3::handleCommit};

TextInputManagerV3::TextInputManagerV3(QWaylandCompositor *compositor)
    : QObject(compositor)
    , m_compositor(compositor)
    , m_global(nullptr) {
    struct wl_display *display = compositor->display();
    m_global =
        wl_global_create(display, &zwp_text_input_manager_v3_interface, 1, this, bindManager);
    if (m_global)
        qInfo() << "[TextInputManagerV3] zwp_text_input_manager_v3 enabled";
    else
        qWarning() << "[TextInputManagerV3] Failed to create global";
}

TextInputManagerV3::~TextInputManagerV3() {
    if (m_global)
        wl_global_destroy(m_global);
}

void TextInputManagerV3::bindManager(struct wl_client *client, void *data, uint32_t version,
                                     uint32_t id) {
    auto               *manager = static_cast<TextInputManagerV3 *>(data);
    struct wl_resource *resource =
        wl_resource_create(client, &zwp_text_input_manager_v3_interface, version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &managerInterface, manager, nullptr);
}

void TextInputManagerV3::handleGetTextInput(struct wl_client *client, struct wl_resource *resource,
                                            uint32_t id, struct wl_resource *seat) {
    Q_UNUSED(seat);
    auto         *manager = static_cast<TextInputManagerV3 *>(wl_resource_get_user_data(resource));
    QWaylandSeat *waylandSeat = manager->m_compositor->defaultSeat();
    auto         *textInput   = new TextInputV3(manager, client, id, waylandSeat);
    manager->m_textInputs.append(textInput);

    connect(textInput, &TextInputV3::enabled, manager, [manager, waylandSeat]() {
        emit manager->textInputEnabled(waylandSeat->keyboardFocus());
    });
    connect(textInput, &TextInputV3::disabled, manager, [manager, waylandSeat]() {
        emit manager->textInputDisabled(waylandSeat->keyboardFocus());
    });
}

void TextInputManagerV3::handleManagerDestroy(struct wl_client   *client,
                                              struct wl_resource *resource) {
    Q_UNUSED(client);
    wl_resource_destroy(resource);
}

TextInputV3::TextInputV3(TextInputManagerV3 *manager, struct wl_client *client, uint32_t id,
                         QWaylandSeat *seat)
    : QObject(manager)
    , m_manager(manager)
    , m_resource(nullptr)
    , m_seat(seat)
    , m_focusSurface(nullptr)
    , m_pendingEnabled(false)
    , m_serial(0) {
    m_resource = wl_resource_create(client, &zwp_text_input_v3_interface, 1, id);
    if (!m_resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(m_resource, &textInputInterface, this, nullptr);
}

TextInputV3::~TextInputV3() {}

void TextInputV3::sendEnter(QWaylandSurface *surface) {
    if (!surface || !m_resource)
        return;
    struct wl_resource *surfaceResource = surface->resource();
    if (surfaceResource) {
        zwp_text_input_v3_send_enter(m_resource, surfaceResource);
        m_focusSurface = surface;
    }
}

void TextInputV3::sendLeave(QWaylandSurface *surface) {
    if (!surface || !m_resource)
        return;
    struct wl_resource *surfaceResource = surface->resource();
    if (surfaceResource) {
        zwp_text_input_v3_send_leave(m_resource, surfaceResource);
        m_focusSurface = nullptr;
    }
}

void TextInputV3::sendDone(uint32_t serial) {
    if (m_resource)
        zwp_text_input_v3_send_done(m_resource, serial);
}

void TextInputV3::handleEnable(struct wl_client *client, struct wl_resource *resource) {
    Q_UNUSED(client);
    auto *ti             = static_cast<TextInputV3 *>(wl_resource_get_user_data(resource));
    ti->m_pendingEnabled = true;
}

void TextInputV3::handleDisable(struct wl_client *client, struct wl_resource *resource) {
    Q_UNUSED(client);
    auto *ti             = static_cast<TextInputV3 *>(wl_resource_get_user_data(resource));
    ti->m_pendingEnabled = false;
}

void TextInputV3::handleSetSurroundingText(struct wl_client *, struct wl_resource *, const char *,
                                           int32_t, int32_t) {}

void TextInputV3::handleSetTextChangeCause(struct wl_client *, struct wl_resource *, uint32_t) {}

void TextInputV3::handleSetContentType(struct wl_client *, struct wl_resource *, uint32_t,
                                       uint32_t) {}

void TextInputV3::handleSetCursorRectangle(struct wl_client *, struct wl_resource *, int32_t,
                                           int32_t, int32_t, int32_t) {}

void TextInputV3::handleCommit(struct wl_client *client, struct wl_resource *resource) {
    Q_UNUSED(client);
    auto *ti = static_cast<TextInputV3 *>(wl_resource_get_user_data(resource));
    ti->m_serial++;

    if (ti->m_pendingEnabled)
        emit ti->enabled();
    else
        emit ti->disabled();

    ti->sendDone(ti->m_serial);
}

void TextInputV3::handleDestroy(struct wl_client *client, struct wl_resource *resource) {
    Q_UNUSED(client);
    wl_resource_destroy(resource);
}
