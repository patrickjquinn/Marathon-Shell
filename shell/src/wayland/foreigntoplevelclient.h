#pragma once

#include <QHash>
#include <QObject>
#include <QString>

#include <QtWaylandClient/qwaylandclientextension.h>

#include "qwayland-wlr-foreign-toplevel-management-unstable-v1.h"

class ForeignToplevelHandle;

// Shell-side client of zwlr_foreign_toplevel_manager_v1 v3.
//
// QWaylandClientExtensionTemplate handles registry walking + bind, then
// flips active() once the global is advertised. Each `toplevel` event
// becomes a ForeignToplevelHandle exposed via toplevelAdded after its
// first non-empty app_id arrives — emitting earlier would feed TaskModel
// rows with empty keys (the v1 protocol bursts title/app_id/state before
// the initial done()).
class ForeignToplevelClient : public QWaylandClientExtensionTemplate<ForeignToplevelClient>,
                              public QtWayland::zwlr_foreign_toplevel_manager_v1 {
    Q_OBJECT

  public:
    explicit ForeignToplevelClient(QObject *parent = nullptr);
    ~ForeignToplevelClient() override;

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

// One per zwlr_foreign_toplevel_handle_v1 resource. Owned by the client;
// `destroy` is sent in the dtor when still bound (closed() fires before
// then in the normal-shutdown path).
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

    // The protocol's activate request needs a wl_seat — looked up via
    // QPA. Marathon has exactly one seat so we don't disambiguate.
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
