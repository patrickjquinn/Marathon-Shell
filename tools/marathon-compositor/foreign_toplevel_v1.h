#pragma once

#include <QHash>
#include <QObject>
#include <QPointer>
#include <wayland-server-core.h>

class QWaylandCompositor;
class QWaylandXdgToplevel;
class QWaylandSurface;
class ForeignToplevelHandleV1;

// Server-side wlr_foreign_toplevel_management_unstable_v1. The marathon-
// shell binds this from the client side via marathon-core/wayland/
// foreigntoplevelclient.{h,cpp} (added in C-3) to drive its Active Frames
// task list. One handle is created per xdg_toplevel surface; each
// bound manager sees the full handle list and follows it live via
// title/app_id/state/done events.
//
// Protocol: protocols/wlr-foreign-toplevel-management-unstable-v1.xml
//
// Phase C-3 ships full title + app_id + state + activate/close request
// handling. set_maximized/minimized/fullscreen stay as no-ops for now
// (Marathon is single-window mobile UX, no maximize/minimize semantics).
class ForeignToplevelManagerV1 : public QObject {
    Q_OBJECT

  public:
    explicit ForeignToplevelManagerV1(QWaylandCompositor *compositor);
    ~ForeignToplevelManagerV1() override;

    // Called by MarathonCompositor when a new xdg_toplevel maps. Creates
    // a ForeignToplevelHandleV1, broadcasts a toplevel event to every
    // bound manager. The handle lives until the underlying surface is
    // destroyed.
    void registerToplevel(QWaylandXdgToplevel *toplevel);

  private:
    friend class ForeignToplevelHandleV1;
    static void          bind(struct wl_client *client, void *data, uint32_t version, uint32_t id);
    static void          onStop(wl_client *, wl_resource *);

    void                 broadcastNewHandle(ForeignToplevelHandleV1 *handle);
    void                 notifyBound(wl_resource *managerResource);

    QWaylandCompositor  *m_compositor = nullptr;
    struct wl_global    *m_global     = nullptr;
    QList<wl_resource *> m_managerResources;
    QHash<QWaylandXdgToplevel *, ForeignToplevelHandleV1 *> m_handlesByToplevel;
};

// One per xdg_toplevel. The same logical handle is exposed to every
// bound manager via a separate wl_resource per binding — title/app_id/
// state events fan out to all of them, and activate/close requests
// from any client are routed to the underlying QWaylandXdgToplevel.
class ForeignToplevelHandleV1 : public QObject {
    Q_OBJECT

  public:
    ForeignToplevelHandleV1(ForeignToplevelManagerV1 *manager, QWaylandXdgToplevel *toplevel);
    ~ForeignToplevelHandleV1() override;

    QWaylandXdgToplevel *toplevel() const {
        return m_toplevel.data();
    }

    // Create a new resource for this handle on the given client's manager
    // resource (called both when a manager binds — for each existing
    // handle — and when a new handle is created — for each bound manager).
    void emitToplevelTo(wl_resource *managerResource);

    // Static request handlers — exposed publicly so the file-scope
    // `handleImpl` interface struct in the .cpp can take their addresses.
    // (Private + friend works too; matches the pattern used in
    // layer_shell_v1.h and session_lock_v1.h.)
    static void onActivate(wl_client *, wl_resource *, wl_resource *seat);
    static void onClose(wl_client *, wl_resource *);
    static void onSetMaximized(wl_client *, wl_resource *);
    static void onUnsetMaximized(wl_client *, wl_resource *);
    static void onSetMinimized(wl_client *, wl_resource *);
    static void onUnsetMinimized(wl_client *, wl_resource *);
    static void onSetFullscreen(wl_client *, wl_resource *, wl_resource *output);
    static void onUnsetFullscreen(wl_client *, wl_resource *);
    static void onSetRectangle(wl_client *, wl_resource *, wl_resource *surface, int32_t x,
                               int32_t y, int32_t w, int32_t h);
    static void onDestroyHandle(wl_client *, wl_resource *resource);
    static void resourceDestroyed(wl_resource *resource);

  private:
    void                          sendDoneAll();
    void                          sendTitleAll(const QString &title);
    void                          sendAppIdAll(const QString &appId);
    void                          sendStateAll();
    void                          sendClosedAll();

    ForeignToplevelManagerV1     *m_manager = nullptr;
    QPointer<QWaylandXdgToplevel> m_toplevel;
    QList<wl_resource *>          m_resources;
    QString                       m_title;
    QString                       m_appId;
    bool                          m_activated = false;
};
