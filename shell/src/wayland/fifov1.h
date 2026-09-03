#ifndef FIFOV1_H
#define FIFOV1_H

#include <QHash>
#include <QObject>
#include <QPointer>
#include <wayland-server-core.h>

class QWaylandCompositor;
class QWaylandSurface;
class QQuickWindow;
class FifoV1;

// wp_fifo_v1 — staging/fifo (Valve, 2023).
//
// Adds display-refresh-cycle completion as a content-update readiness
// constraint. Two primitives on a per-surface fifo object:
//
//   set_barrier  — the NEXT commit's apply sets a "fifo_barrier" condition
//                  on the surface. Cleared at the next non-tearing latching
//                  deadline (vsync in our setup).
//   wait_barrier — the NEXT commit's apply waits for the fifo_barrier
//                  condition to clear.
//
// Why we want it: SDL3 (and Chromium via the wayland Ozone backend) now
// switch their main render loop to fifo-v1 semantics when both this AND
// commit-timing-v1 are advertised. Without it they fall back to the more
// jittery wp_presentation timestamp path. Other compositors (wlroots, KWin
// 6.4+, Smithay) ship it; Marathon advertising it lets these apps run their
// preferred path.
//
// Implementation honesty: Qt 6.10 does NOT expose a pre-commit hook on
// QWaylandSurface — we cannot literally defer commit-apply in public API.
// What we DO do, and what is enough for the spec's intent:
//
//   • Track per-surface barrier state. set_barrier flags the next commit;
//     on QWaylandSurface::committed we transfer the flag to "barrier active."
//   • Listen on QQuickWindow::frameSwapped (the vsync-driven render loop).
//     On each swap we clear all surfaces' active barriers.
//   • For surfaces with wait_barrier pending: when the surface tries to
//     commit, if a barrier is still active on this surface OR any other
//     fifo surface, we suppress emit of `frame` callbacks for one swap
//     cycle — which is what apps actually consume to throttle.
//
// This delivers the visible-to-user property the protocol guarantees
// (frame N+1 is never presented before frame N completes a vsync) without
// touching Qt's private API. Apps that depend on _strict_ commit-apply
// deferral (extremely rare) will see a one-frame deviation under load —
// documented and acceptable for v1.

class FifoManagerV1 : public QObject {
    Q_OBJECT

  public:
    explicit FifoManagerV1(QWaylandCompositor *compositor, QQuickWindow *window);
    ~FifoManagerV1() override;

    static void bindManager(struct wl_client *client, void *data, uint32_t version, uint32_t id);

    // Spec: at most one wp_fifo_v1 per wl_surface.
    bool hasFifoForSurface(QWaylandSurface *surface) const;

  private slots:
    void onFrameSwapped();

  private:
    friend class FifoV1;

    void                   registerFifo(FifoV1 *fifo);
    void                   unregisterFifo(FifoV1 *fifo);

    QWaylandCompositor    *m_compositor;
    QPointer<QQuickWindow> m_window;
    struct wl_global      *m_global = nullptr;
    QList<FifoV1 *>        m_fifos;
};

class FifoV1 : public QObject {
    Q_OBJECT

  public:
    FifoV1(FifoManagerV1 *manager, struct wl_client *client, uint32_t id, QWaylandSurface *surface);
    ~FifoV1() override;

    // Called by manager on QQuickWindow::frameSwapped. Clears any active
    // barrier this surface holds — non-tearing latching deadline passed.
    void onLatchDeadline();

    bool hasActiveBarrier() const {
        return m_barrierActive;
    }

    QWaylandSurface *surface() const {
        return m_surface.data();
    }

    // Protocol request handlers.
    static void handleSetBarrier(struct wl_client *, struct wl_resource *);
    static void handleWaitBarrier(struct wl_client *, struct wl_resource *);
    static void handleDestroy(struct wl_client *, struct wl_resource *);

  private slots:
    void onSurfaceCommitted();
    void onSurfaceDestroyed();

  private:
    FifoManagerV1            *m_manager;
    struct wl_resource       *m_resource = nullptr;
    QPointer<QWaylandSurface> m_surface;
    // Double-buffered per the protocol: pending state is applied on commit.
    bool m_pendingSetBarrier  = false;
    bool m_pendingWaitBarrier = false;
    // Active state after commit. Cleared on next latch deadline.
    bool m_barrierActive = false;
};

#endif // FIFOV1_H
