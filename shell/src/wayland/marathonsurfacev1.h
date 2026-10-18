#ifndef MARATHONSURFACEV1_H
#define MARATHONSURFACEV1_H

#include <QHash>
#include <QList>
#include <QMargins>
#include <QObject>
#include <QPointer>
#include <QPointF>
#include <QRect>
#include <QVariantList>
#include <QWaylandSurface>
#include <QWaylandXdgToplevel>
#include <wayland-server-core.h>

class QWaylandCompositor;
class SecurityContextManagerV1;
class MarathonSurfaceV1;

// marathon_surface_v1 (shell/protocols/marathon-surface-v1.xml). The global
// is for unsandboxed clients and the app runner's sandboxes.
class MarathonSurfaceManagerV1 : public QObject {
    Q_OBJECT

  public:
    static constexpr const char *kTrustedEngine = "org.marathonos.AppRunner";

    MarathonSurfaceManagerV1(QWaylandCompositor *compositor, SecurityContextManagerV1 *contexts);
    ~MarathonSurfaceManagerV1() override;

    MarathonSurfaceV1 *forSurface(const QWaylandSurface *surface) const {
        return m_surfaces.value(surface);
    }
    QList<MarathonSurfaceV1 *> surfaces() const {
        return m_surfaces.values();
    }

    static bool mayBind(bool sandboxed, const QString &engine);
    // For the display's global filter.
    bool allowsGlobal(const wl_client *client, const wl_global *global) const;

    // Request handlers, public for the C dispatch tables.
    static void bind(wl_client *client, void *data, uint32_t version, uint32_t id);
    static void getSurface(wl_client *client, wl_resource *manager, uint32_t id,
                           wl_resource *toplevel, uint32_t taskId);

  signals:
    void surfaceAdded(MarathonSurfaceV1 *surface);
    // The object is destroyed or its toplevel is gone.
    void surfaceRemoved(MarathonSurfaceV1 *surface);

  private:
    friend class MarathonSurfaceV1;

    void                                                remove(MarathonSurfaceV1 *surface);

    SecurityContextManagerV1                           *m_contexts;
    wl_global                                          *m_global = nullptr;
    QHash<const QWaylandSurface *, MarathonSurfaceV1 *> m_surfaces;
};

class MarathonSurfaceV1 : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool focusable READ focusable NOTIFY flagsChanged)
    Q_PROPERTY(bool touchable READ touchable NOTIFY flagsChanged)
    Q_PROPERTY(bool secure READ secure NOTIFY flagsChanged)
    Q_PROPERTY(bool systemBarsHidden READ systemBarsHidden NOTIFY systemBarsHiddenChanged)
    // QRects in surface coordinates; no shell gesture reads it yet.
    Q_PROPERTY(QVariantList gestureExclusion READ gestureExclusion NOTIFY gestureExclusionChanged)
    Q_PROPERTY(uint taskId READ taskId CONSTANT)

  public:
    MarathonSurfaceV1(MarathonSurfaceManagerV1 *manager, wl_resource *resource,
                      QWaylandXdgToplevel *toplevel, uint taskId);
    ~MarathonSurfaceV1() override;

    // Null once inert.
    QWaylandXdgToplevel *toplevel() const {
        return m_toplevel;
    }
    QWaylandSurface *surface() const {
        return m_surface;
    }
    bool focusable() const;
    bool touchable() const;
    bool secure() const;
    bool systemBarsHidden() const {
        return m_systemBarsHidden;
    }
    QVariantList gestureExclusion() const;
    uint         taskId() const {
        return m_taskId;
    }

    // Sends the values that changed since the last call (all of them the
    // first time); true if it sent any, and the caller must then end the
    // configure sequence with xdg_surface.configure.
    bool sendInsets(const QMargins &insets, int imeBottom);

    // back_started before the first progress of a gesture.
    void sendBackProgress(uint edge, qreal progress, const QPointF &position);
    void sendBackCommitted();
    // back_cancelled if a gesture is under way.
    void cancelBack();

    // Request handlers, public for the C dispatch table.
    static void setWindowFlags(wl_resource *resource, uint32_t flags);
    static void setGestureExclusion(wl_resource *resource, wl_array *rects);
    static void setSystemBars(wl_resource *resource, uint32_t mode);

  signals:
    void flagsChanged();
    void systemBarsHiddenChanged();
    void gestureExclusionChanged();

  private:
    void                          makeInert();
    void                          applyPendingExclusion();

    MarathonSurfaceManagerV1     *m_manager;
    wl_resource                  *m_resource;
    QPointer<QWaylandXdgToplevel> m_toplevel;
    QPointer<QWaylandSurface>     m_surface;
    uint                          m_taskId;
    uint32_t                      m_flags            = 0;
    bool                          m_systemBarsHidden = false;
    QList<QRect>                  m_exclusion;
    QList<QRect>                  m_pendingExclusion;
    bool                          m_exclusionPending = false;
    bool                          m_inert            = false;
    bool                          m_backActive       = false;
    bool                          m_insetsSent       = false;
    QMargins                      m_insets;
    int                           m_imeBottom = 0;
};

#endif // MARATHONSURFACEV1_H
