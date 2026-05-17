#include "foreigntoplevelclient.h"

#include <QGuiApplication>
#include <QLoggingCategory>
#include <qpa/qplatformnativeinterface.h>

Q_LOGGING_CATEGORY(lcFTC, "marathon.shell.foreign-toplevel")

// We advertise/bind v3 server-side; ask for the same here. Older servers
// auto-negotiate down via the registry version field; QWaylandClient-
// ExtensionTemplate respects whatever the global says.
static constexpr int kForeignToplevelVersion = 3;

ForeignToplevelClient::ForeignToplevelClient(QObject *parent)
    : QWaylandClientExtensionTemplate<ForeignToplevelClient>(kForeignToplevelVersion) {
    setParent(parent);
    // QWaylandClientExtension binds at first dispatch tick; nothing else
    // to do in the constructor. We log when active() flips.
    connect(this, &QWaylandClientExtension::activeChanged, this,
            [this]() { qCInfo(lcFTC) << "foreign-toplevel-management active:" << isActive(); });
}

ForeignToplevelClient::~ForeignToplevelClient() {
    qDeleteAll(m_handles);
    m_handles.clear();
}

ForeignToplevelHandle *ForeignToplevelClient::handleForAppId(const QString &appId) const {
    for (auto *h : m_handles) {
        if (h && h->appId() == appId)
            return h;
    }
    return nullptr;
}

void ForeignToplevelClient::zwlr_foreign_toplevel_manager_v1_toplevel(
    struct ::zwlr_foreign_toplevel_handle_v1 *toplevel) {
    auto *handle = new ForeignToplevelHandle(toplevel, this);
    m_handles.insert(toplevel, handle);
    // We can't emit toplevelAdded yet — the server may still be in the
    // burst of title/app_id/state events that bracket the initial done().
    // Wait for the first non-empty app_id (or title fallback) before
    // exposing to TaskModel; otherwise the model would see a row with
    // appId=="" and skip key lookups.
    connect(handle, &ForeignToplevelHandle::appIdChanged, this,
            [this, handle]() { onHandleAppId(handle); });
    connect(handle, &ForeignToplevelHandle::closed, this,
            [this, handle]() { onHandleClosed(handle); });
    qCDebug(lcFTC) << "new toplevel handle" << toplevel;
}

void ForeignToplevelClient::zwlr_foreign_toplevel_manager_v1_finished() {
    qCInfo(lcFTC) << "manager `finished` — server stopped";
    for (auto *h : m_handles)
        emit toplevelRemoved(h);
    qDeleteAll(m_handles);
    m_handles.clear();
}

void ForeignToplevelClient::onHandleAppId(ForeignToplevelHandle *handle) {
    if (!handle || handle->appId().isEmpty())
        return;
    // Disconnect so we only emit `toplevelAdded` once. Subsequent
    // app_id changes (rare) still propagate through the handle's own
    // appIdChanged signal.
    disconnect(handle, &ForeignToplevelHandle::appIdChanged, this, nullptr);
    qCInfo(lcFTC) << "toplevel ready:" << handle->appId() << "title=" << handle->title();
    emit toplevelAdded(handle);
}

void ForeignToplevelClient::onHandleClosed(ForeignToplevelHandle *handle) {
    if (!handle)
        return;
    emit toplevelRemoved(handle);
    // Find the wl_object key and drop from the map. Then delete.
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
    // Qt's QPA gives us the wl_seat proxy through the native interface;
    // the compositor's `activate` request requires it so it can ignore
    // un-focused inputs. There's only one seat in Marathon so we don't
    // need to disambiguate.
    auto *native = QGuiApplication::platformNativeInterface();
    if (!native) {
        qCWarning(lcFTC) << "no platform native interface — can't get seat";
        return;
    }
    auto *seat = static_cast<wl_seat *>(native->nativeResourceForIntegration("wl_seat"));
    if (!seat) {
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
    // The state event carries a packed array of u32 entries (each is a
    // `state` enum value). We only care about ACTIVATED in mobile UX —
    // maximized/minimized/fullscreen don't apply.
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
