#ifndef SECURITYCONTEXTV1_H
#define SECURITYCONTEXTV1_H

#include <QHash>
#include <QObject>
#include <QSocketNotifier>
#include <QString>
#include <QWaylandCompositor>
#include <wayland-server-core.h>

// wp_security_context_v1 — staging/security-context.
//
// Lets a sandbox engine (marathon-app-runner, in our case future Flatpak)
// create a NEW listening socket for the apps it spawns, AND tag every
// future client on that socket with a fixed (engine, app_id, instance_id)
// triple. Once committed, sandboxed clients are reliably distinguishable
// from the rest of the compositor's clients — the compositor (and any
// privileged-portal proxies the compositor mediates) can then enforce
// per-app policy without trusting the client's own assertion.
//
// Server-side semantics from the protocol spec:
//   • A client (the sandbox engine) calls create_listener(id, listen_fd, close_fd).
//   • The engine then sets engine name / app_id / instance_id on the
//     resulting wp_security_context_v1 and calls commit(). The context
//     is immutable after commit.
//   • The compositor starts wl_event_loop_add_fd on listen_fd. Every
//     wl_client that connect()s to it inherits the security context.
//   • The compositor also watches close_fd for readability — when the
//     engine closes its end of that pipe, the listener is destroyed and
//     no new clients accepted (existing ones survive).
//
// What this commit *does not* yet do:
//   • marathon-app-runner does NOT yet call this — that's a separate
//     commit because the app-runner is a Wayland client, not part of
//     the compositor process, and the runtime plumbing is nontrivial.
//   • The compositor exposes `sandboxedClient(wl_client*) → Context` so
//     downstream (xdg-shell handlers, portal proxies, screen capture)
//     can consult it. Surface tagging is currently informational.

struct wp_client_state;

class SecurityContextV1;

class SecurityContextManagerV1 : public QObject {
    Q_OBJECT

  public:
    explicit SecurityContextManagerV1(QWaylandCompositor *compositor);
    ~SecurityContextManagerV1() override;

    // Per-client security context: what the sandbox engine declared on
    // commit(). Looked up by the wl_client pointer, which Wayland gives
    // every resource handler.
    struct Context {
        QString engine;     // e.g. "org.marathonos.AppRunner", "org.flatpak"
        QString appId;      // app manifest identifier
        QString instanceId; // unique per launch
    };

    // Resolve a wl_client to its sandboxed context, if any. Returns
    // empty Context for clients that connected on the unrestricted
    // socket (the shell itself, dev tools, etc.).
    Context contextForClient(struct wl_client *client) const;
    bool    isSandboxed(struct wl_client *client) const;

    // Resource binders — public so the wl_global callback can reach them.
    static void bindManager(struct wl_client *client, void *data, uint32_t version, uint32_t id);

  signals:
    void sandboxedClientConnected(const QString &engine, const QString &appId,
                                  const QString &instanceId);

  private:
    friend class SecurityContextV1;

    void                registerClient(struct wl_client *client, const Context &context);
    void                unregisterClient(struct wl_client *client);

    QWaylandCompositor *m_compositor;
    struct wl_global   *m_global = nullptr;
    QHash<struct wl_client *, Context> m_clients;
};

// One per create_listener call. Holds the pending context fields until
// commit() makes them immutable and starts the listener on listen_fd.
class SecurityContextV1 : public QObject {
    Q_OBJECT

  public:
    SecurityContextV1(SecurityContextManagerV1 *manager, struct wl_client *engineClient,
                      uint32_t id, int listenFd, int closeFd);
    ~SecurityContextV1() override;

    // Protocol request handlers — instance methods called by the static
    // wrappers below, which is the conventional libwayland C-to-C++ shape.
    static void handleSetSandboxEngine(struct wl_client *, struct wl_resource *, const char *name);
    static void handleSetAppId(struct wl_client *, struct wl_resource *, const char *appId);
    static void handleSetInstanceId(struct wl_client *, struct wl_resource *,
                                    const char *instanceId);
    static void handleCommit(struct wl_client *, struct wl_resource *);
    static void handleDestroy(struct wl_client *, struct wl_resource *);

  private slots:
    void onCloseFdReadable();

  private:
    static int                        onListenFdReadable(int fd, uint32_t mask, void *data);

    SecurityContextManagerV1         *m_manager;
    struct wl_resource               *m_resource = nullptr;
    SecurityContextManagerV1::Context m_pending;
    bool                              m_committed     = false;
    int                               m_listenFd      = -1;
    int                               m_closeFd       = -1;
    QSocketNotifier                  *m_closeNotifier = nullptr;
    struct wl_event_source           *m_listenSource  = nullptr;
};

#endif // SECURITYCONTEXTV1_H
