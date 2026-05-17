#include "foreigntoplevelclient.h"

#include <QGuiApplication>
#include <QLoggingCategory>
#include <qpa/qplatformnativeinterface.h>

Q_LOGGING_CATEGORY(lcFTC, "marathon.shell.foreign-toplevel")

static constexpr int kForeignToplevelVersion = 3;

ForeignToplevelClient::ForeignToplevelClient(QObject *parent)
    : QWaylandClientExtensionTemplate<ForeignToplevelClient>(kForeignToplevelVersion) {
    setParent(parent);
    connect(this, &QWaylandClientExtension::activeChanged, this,
            [this]() { qCInfo(lcFTC) << "foreign-toplevel-management active:" << isActive(); });
}

ForeignToplevelClient::~ForeignToplevelClient() {
    qDeleteAll(m_handles);
    m_handles.clear();
}

ForeignToplevelHandle *ForeignToplevelClient::handleForAppId(const QString &appId) const {
    for (auto *h : std::as_const(m_handles)) {
        if (h->appId() == appId)
            return h;
    }
    return nullptr;
}

void ForeignToplevelClient::zwlr_foreign_toplevel_manager_v1_toplevel(
    struct ::zwlr_foreign_toplevel_handle_v1 *toplevel) {
    auto *handle = new ForeignToplevelHandle(toplevel, this);
    m_handles.insert(toplevel, handle);
    // The protocol bursts title/app_id/state before the initial done();
    // gate the toplevelAdded emit on first non-empty app_id so TaskModel
    // never sees a row with an empty key.
    connect(handle, &ForeignToplevelHandle::appIdChanged, this,
            [this, handle]() { onHandleAppId(handle); });
    connect(handle, &ForeignToplevelHandle::closed, this,
            [this, handle]() { onHandleClosed(handle); });
    qCDebug(lcFTC) << "new toplevel handle" << toplevel;
}

void ForeignToplevelClient::zwlr_foreign_toplevel_manager_v1_finished() {
    qCInfo(lcFTC) << "manager `finished` — server stopped";
    for (auto *h : std::as_const(m_handles))
        emit toplevelRemoved(h);
    qDeleteAll(m_handles);
    m_handles.clear();
}

void ForeignToplevelClient::onHandleAppId(ForeignToplevelHandle *handle) {
    if (handle->appId().isEmpty())
        return;
    // One-shot: subsequent app_id changes still propagate through the
    // handle's own appIdChanged signal — we just don't re-fire Added.
    disconnect(handle, &ForeignToplevelHandle::appIdChanged, this, nullptr);
    qCInfo(lcFTC) << "toplevel ready:" << handle->appId() << "title=" << handle->title();
    emit toplevelAdded(handle);
}

void ForeignToplevelClient::onHandleClosed(ForeignToplevelHandle *handle) {
    emit toplevelRemoved(handle);
    for (auto it = m_handles.begin(); it != m_handles.end(); ++it) {
        if (it.value() == handle) {
            m_handles.erase(it);
            break;
        }
    }
    handle->deleteLater();
}

// -- handle -------------------------------------------------------------

ForeignToplevelHandle::ForeignToplevelHandle(struct ::zwlr_foreign_toplevel_handle_v1 *handle,
                                             QObject                                  *parent)
    : QObject(parent)
    , QtWayland::zwlr_foreign_toplevel_handle_v1(handle) {}

ForeignToplevelHandle::~ForeignToplevelHandle() {
    if (isInitialized())
        destroy();
}

void ForeignToplevelHandle::requestActivate() {
    auto *native = QGuiApplication::platformNativeInterface();
    auto *seat   = static_cast<wl_seat *>(native->nativeResourceForIntegration("wl_seat"));
    if (!seat) {
        // Non-Wayland QPA (offscreen tests, XCB fallback). Caller is
        // running in a configuration where activate is meaningless.
        qCWarning(lcFTC) << "no wl_seat from QPA — can't activate" << m_appId;
        return;
    }
    activate(seat);
    qCInfo(lcFTC) << "activate" << m_appId;
}

void ForeignToplevelHandle::requestClose() {
    close();
    qCInfo(lcFTC) << "close" << m_appId;
}

void ForeignToplevelHandle::zwlr_foreign_toplevel_handle_v1_title(const QString &title) {
    if (m_title == title)
        return;
    m_title = title;
    emit titleChanged();
}

void ForeignToplevelHandle::zwlr_foreign_toplevel_handle_v1_app_id(const QString &appId) {
    if (m_appId == appId)
        return;
    m_appId = appId;
    emit appIdChanged();
}

void ForeignToplevelHandle::zwlr_foreign_toplevel_handle_v1_state(wl_array *state) {
    // Mobile single-window UX: only ACTIVATED matters. Maximized /
    // minimized / fullscreen entries (also packed in this u32 array)
    // are ignored.
    bool activated = false;
    if (state && state->size > 0) {
        const auto *entries = static_cast<const uint32_t *>(state->data);
        const int   count   = state->size / sizeof(uint32_t);
        for (int i = 0; i < count; ++i) {
            if (entries[i] == state_activated) {
                activated = true;
                break;
            }
        }
    }
    if (activated != m_activated) {
        m_activated = activated;
        emit activatedChanged();
    }
}

void ForeignToplevelHandle::zwlr_foreign_toplevel_handle_v1_closed() {
    qCInfo(lcFTC) << "closed" << m_appId;
    emit closed();
}
