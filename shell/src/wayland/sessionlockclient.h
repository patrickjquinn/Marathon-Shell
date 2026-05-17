#pragma once

#include <QObject>
#include <QString>

#include <QtWaylandClient/qwaylandclientextension.h>

#include "qwayland-ext-session-lock-v1.h"

class ExtSessionLockObject;

// Shell-side client of ext_session_lock_manager_v1.
//
// Drives the protocol from SessionStore::isLocked: setLocked(true)
// requests a lock, setLocked(false) sends unlock_and_destroy. The
// compositor stops drawing app surfaces between those two calls;
// the shell's own MarathonLockScreen continues to render on the
// layer-shell overlay. The protocol's lock-surface path is not
// used — the compositor's app-surface gating is what matters here,
// and a layer-shell overlay already covers the chrome side.
class SessionLockClient : public QWaylandClientExtensionTemplate<SessionLockClient>,
                          public QtWayland::ext_session_lock_manager_v1 {
    Q_OBJECT

  public:
    explicit SessionLockClient(QObject *parent = nullptr);
    ~SessionLockClient() override;

    // Mirrors SessionStore::isLocked. Idempotent: re-locking while
    // already holding a lock is a no-op; unlocking when no lock is
    // held is a no-op.
    void setLocked(bool locked);

  Q_SIGNALS:
    void serverGrantedLock();
    void serverDeniedLock();

  private:
    ExtSessionLockObject *m_lock = nullptr;
};

// Holds a single lock attempt. Lifetime: created on lock(), destroyed
// either by the server's `finished` event (lock denied / preempted)
// or by us sending `unlock_and_destroy`.
class ExtSessionLockObject : public QObject, public QtWayland::ext_session_lock_v1 {
    Q_OBJECT

  public:
    ExtSessionLockObject(SessionLockClient *client, struct ::ext_session_lock_v1 *lock);
    ~ExtSessionLockObject() override;

    void unlockAndDestroy();

  Q_SIGNALS:
    void granted();
    void finished();

  protected:
    void ext_session_lock_v1_locked() override;
    void ext_session_lock_v1_finished() override;

  private:
    SessionLockClient *m_client      = nullptr;
    bool               m_unlockedOut = false;
};
