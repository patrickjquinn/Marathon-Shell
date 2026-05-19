#ifndef COMMITTIMINGV1_H
#define COMMITTIMINGV1_H

#include <QObject>
#include <QPointer>
#include <wayland-server-core.h>

class QWaylandCompositor;
class QWaylandSurface;
class CommitTimerV1;

// wp_commit_timing_v1 — staging/commit-timing (Valve, 2023).
//
// Lets clients set a target presentation timestamp on a per-commit basis.
// The compositor MUST NOT present the commit before the timestamp; it
// SHOULD present as close to the timestamp as possible. Critically, this
// is the protocol Mesa's queued-presentation loop, SDL3, and Chromium's
// Ozone Wayland backend probe for alongside fifo-v1 — when BOTH are
// advertised, they switch to a deadline-driven scheduler that visibly
// kills frame-time jitter under load.
//
// Pairing with fifo-v1: fifo gives ordering ("don't present N+1 until N
// completes a vsync"); commit-timing gives deadlines ("present N at or
// after time T"). Together, apps get the scheduling primitives they need
// for sub-frame-precision animation across compositor + GPU latency.
//
// Implementation honesty: like fifo-v1, Qt 6.10 does not expose a
// pre-render hook that lets us literally hold a buffer back from the
// scenegraph render path. What we DO is:
//
//   • Track per-surface pending + active timestamps. Double-buffered
//     per the spec — set_timestamp marks pending; on QWaylandSurface::redraw
//     (post-commit apply) we transfer to active.
//   • Expose CommitTimerV1::activeTimestampNs() so the compositor's
//     render-tick can consult it.
//   • A future commit (when we integrate with a proper compositor-side
//     present scheduler) will use this state to clamp render-to-present
//     latency. The visible-to-user-today property is that apps that probe
//     for the protocol find it, and their preferred scheduler path runs.
//
// Strict enforcement (skipping render for surfaces whose timestamp hasn't
// passed) is deferred until we have an explicit per-surface present
// gate in the render loop — the Phase C compositor split is a natural
// time for that. Until then, the timestamps are advisory: a vsync-locked
// compositor presents within one refresh cycle of commit anyway, which
// is sub-millisecond for typical animation use.

class CommitTimingManagerV1 : public QObject {
    Q_OBJECT

  public:
    explicit CommitTimingManagerV1(QWaylandCompositor *compositor);
    ~CommitTimingManagerV1() override;

    static void bindManager(struct wl_client *client, void *data, uint32_t version, uint32_t id);

    bool        hasTimerForSurface(QWaylandSurface *surface) const;

  private:
    friend class CommitTimerV1;

    void                   registerTimer(CommitTimerV1 *timer);
    void                   unregisterTimer(CommitTimerV1 *timer);

    QWaylandCompositor    *m_compositor;
    struct wl_global      *m_global = nullptr;
    QList<CommitTimerV1 *> m_timers;
};

class CommitTimerV1 : public QObject {
    Q_OBJECT

  public:
    CommitTimerV1(CommitTimingManagerV1 *manager, struct wl_client *client, uint32_t id,
                  QWaylandSurface *surface);
    ~CommitTimerV1() override;

    QWaylandSurface *surface() const {
        return m_surface.data();
    }

    // Active = post-commit. ns since CLOCK_MONOTONIC epoch, matching the
    // wp_presentation clock domain. 0 means "no timestamp set."
    qint64 activeTimestampNs() const {
        return m_activeTimestampNs;
    }

    static void handleSetTimestamp(struct wl_client *, struct wl_resource *, uint32_t tv_sec_hi,
                                   uint32_t tv_sec_lo, uint32_t tv_nsec);
    static void handleDestroy(struct wl_client *, struct wl_resource *);

  private slots:
    void onSurfaceCommitted();
    void onSurfaceDestroyed();

  private:
    CommitTimingManagerV1    *m_manager;
    struct wl_resource       *m_resource = nullptr;
    QPointer<QWaylandSurface> m_surface;
    qint64                    m_pendingTimestampNs = 0;
    qint64                    m_activeTimestampNs  = 0;
    bool                      m_pendingSet         = false;
};

#endif // COMMITTIMINGV1_H
