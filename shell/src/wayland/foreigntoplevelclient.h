#pragma once

#include <QHash>
#include <QObject>
#include <QString>

#include <QtWaylandClient/qwaylandclientextension.h>

// The qtwaylandscanner-generated headers live in the build dir under
// `qwayland-wlr-foreign-toplevel-management-unstable-v1.h`. Two headers get
// generated per protocol: the public `qwayland-*.h` (event listener +
// request wrappers) and the private `wayland-*-client-protocol.h`. We only
// touch the public one here.
#include "qwayland-wlr-foreign-toplevel-management-unstable-v1.h"

class ForeignToplevelHandle;

// Shell-side client of zwlr_foreign_toplevel_manager_v1 v3.
//
// QWaylandClientExtensionTemplate handles registry walking + bind for us:
// once the Wayland compositor advertises the manager global, this object's
// active() property flips to true and the manager interface is bound on
// our wl_display. From then on, every `toplevel` event minted by the
// server becomes a new ForeignToplevelHandle exposed via the
// `toplevelAdded` signal.
//
// TaskModel subscribes to toplevelAdded/Removed/Title/AppId/State and
// drives Active Frames from those events instead of the in-process
// QWaylandCompositor surface map. Once Phase C-6 lands, the in-process
// path is deleted; for now both coexist behind MARATHON_WAYLAND_CLIENT_MODE.
class ForeignToplevelClient : public QWaylandClientExtensionTemplate<ForeignToplevelClient>,
                              public QtWayland::zwlr_foreign_toplevel_manager_v1 {
    Q_OBJECT

  public:
    explicit ForeignToplevelClient(QObject *parent = nullptr);
    ~ForeignToplevelClient() override;

    // Look up a live handle by app_id. Used by AppLifecycleManager to
    // call activate/close on the right handle when the user taps a task.
    ForeignToplevelHandle *handleForAppId(const QString &appId) const;

  Q_SIGNALS:
    void toplevelAdded(ForeignToplevelHandle *handle);
    void toplevelRemoved(ForeignToplevelHandle *handle);

  protected:
    void zwlr_foreign_toplevel_manager_v1_toplevel(
        struct ::zwlr_foreign_toplevel_handle_v1 *toplevel) override;
    void zwlr_foreign_toplevel_manager_v1_finished() override;

  private:
    void onHandleAppId(ForeignToplevelHandle *handle);
    void onHandleClosed(ForeignToplevelHandle *handle);

    QHash<struct ::zwlr_foreign_toplevel_handle_v1 *, ForeignToplevelHandle *> m_handles;
};

// One per zwlr_foreign_toplevel_handle_v1 resource. Mirrors the server-
// side state (title, app_id, activated) for the shell to render. Owned
// by ForeignToplevelClient and destroyed on the protocol's `closed`
// event (after which `destroy` is sent and the resource is freed).
class ForeignToplevelHandle : public QObject, public QtWayland::zwlr_foreign_toplevel_handle_v1 {
    Q_OBJECT
    Q_PROPERTY(QString title READ title NOTIFY titleChanged)
    Q_PROPERTY(QString appId READ appId NOTIFY appIdChanged)
    Q_PROPERTY(bool activated READ activated NOTIFY activatedChanged)

  public:
    ForeignToplevelHandle(struct ::zwlr_foreign_toplevel_handle_v1 *handle, QObject *parent);
    ~ForeignToplevelHandle() override;

    QString title() const {
        return m_title;
    }
    QString appId() const {
        return m_appId;
    }
    bool activated() const {
        return m_activated;
    }

    // QML-friendly request wrappers. Activate needs a seat; the shell's
    // single QWaylandSeat is the implicit default and Qt's QPA gives us
    // its proxy through QGuiApplication::nativeInterface().
    Q_INVOKABLE void requestActivate();
    Q_INVOKABLE void requestClose();

  Q_SIGNALS:
    void titleChanged();
    void appIdChanged();
    void activatedChanged();
    void closed();

  protected:
    void zwlr_foreign_toplevel_handle_v1_title(const QString &title) override;
    void zwlr_foreign_toplevel_handle_v1_app_id(const QString &appId) override;
    void zwlr_foreign_toplevel_handle_v1_state(wl_array *state) override;
    void zwlr_foreign_toplevel_handle_v1_closed() override;

  private:
    QString m_title;
    QString m_appId;
    bool    m_activated = false;
};
