#pragma once

#include <QObject>
#include <QPointer>
#include <wayland-server-core.h>

class QWaylandCompositor;
class QWaylandSurface;
class ExtSessionLockV1;
class ExtSessionLockSurfaceV1;

// Server-side ext_session_lock_manager_v1 (staging protocol promoted to stable
// in wayland-protocols). The marathon-shell client requests the lock at unlock
// time; while locked, the compositor MUST stop drawing all xdg-shell and
// layer-shell surfaces and render only ext_session_lock_surface_v1 surfaces.
// This is the standard protocol contract — non-negotiable.
//
// **Crash semantics** (per spec): if the client holding the lock disconnects
// before sending `unlock`, the session MUST stay locked indefinitely. The
// compositor cannot "recover" by drawing apps again. Marathon's v1 plan
// accepts this: shell crash while locked = forced reboot. A future
// marathon-locker split would isolate this blast radius.
//
// Phase C-1 ships skeleton: global is registered, locked/unlocked signals
// emitted; compositor.qml does not yet hide app surfaces (will be wired in
// C-5 once the shell consumes the protocol from the client side).
class ExtSessionLockManagerV1 : public QObject {
    Q_OBJECT

  public:
    explicit ExtSessionLockManagerV1(QWaylandCompositor *compositor);
    ~ExtSessionLockManagerV1() override;

    bool isLocked() const {
        return m_isLocked;
    }
    ExtSessionLockV1 *activeLock() const {
        return m_activeLock;
    }

    // Called by the protocol-handler free functions in session_lock_v1.cpp
    // when a lock is granted / released. Public because the wayland-scanner
    // generated vtable uses free functions, not Qt slots.
    void setActiveLock(ExtSessionLockV1 *lock, bool nowLocked);

  signals:
    void locked();
    void unlocked();

  private:
    static void         bind(struct wl_client *client, void *data, uint32_t version, uint32_t id);

    QWaylandCompositor *m_compositor = nullptr;
    struct wl_global   *m_global     = nullptr;
    ExtSessionLockV1   *m_activeLock = nullptr;
    bool                m_isLocked   = false;
};

class ExtSessionLockV1 : public QObject {
    Q_OBJECT

  public:
    ExtSessionLockV1(ExtSessionLockManagerV1 *manager, struct wl_client *client, uint32_t id);
    ~ExtSessionLockV1() override;

    void sendLocked();
    void sendFinished();

  private:
    static void                      destroyLock(wl_client *, wl_resource *resource);
    static void                      getLockSurface(wl_client *, wl_resource *resource, uint32_t id,
                                                    wl_resource *surface, wl_resource *output);
    static void                      unlockAndDestroy(wl_client *, wl_resource *resource);
    static void                      resourceDestroyed(wl_resource *resource);

    ExtSessionLockManagerV1         *m_manager  = nullptr;
    struct wl_resource              *m_resource = nullptr;
    QList<ExtSessionLockSurfaceV1 *> m_surfaces;
};

class ExtSessionLockSurfaceV1 : public QObject {
    Q_OBJECT

  public:
    ExtSessionLockSurfaceV1(ExtSessionLockV1 *lock, wl_client *client, uint32_t id,
                            QWaylandSurface *surface);
    ~ExtSessionLockSurfaceV1() override;

    QWaylandSurface *surface() const {
        return m_surface;
    }

  private:
    static void               destroyRequest(wl_client *, wl_resource *resource);
    static void               ackConfigure(wl_client *, wl_resource *resource, uint32_t serial);
    static void               resourceDestroyed(wl_resource *resource);

    ExtSessionLockV1         *m_lock = nullptr;
    QPointer<QWaylandSurface> m_surface;
    struct wl_resource       *m_resource   = nullptr;
    uint32_t                  m_lastSerial = 0;
};
