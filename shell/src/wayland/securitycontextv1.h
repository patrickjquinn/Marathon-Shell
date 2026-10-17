#ifndef SECURITYCONTEXTV1_H
#define SECURITYCONTEXTV1_H

#include <QHash>
#include <QList>
#include <QObject>
#include <QString>

class QWaylandCompositor;
struct wl_client;
struct wl_display;
struct wl_global;
struct wl_listener;
struct wl_resource;

// wp_security_context_v1 (staging). Every client that connects on a
// sandbox's listening socket carries that sandbox's (engine, app_id,
// instance_id), which the client itself cannot change, and does not see
// the privileged globals. Flatpak registers its sockets through the
// protocol; the shell opens listeners for the sandboxes it starts
// directly with listen().
class SecurityContextManagerV1 : public QObject {
    Q_OBJECT

  public:
    struct Context {
        QString engine;
        QString appId;
        QString instanceId;
    };

    explicit SecurityContextManagerV1(QWaylandCompositor *compositor);
    ~SecurityContextManagerV1() override;

    // Accepts clients on a new socket at path until closeListener().
    bool listen(const QString &path, const Context &context);
    void closeListener(const QString &instanceId);
    // A pooled runner's sandbox is opened before its app is chosen.
    void    assignAppId(const QString &instanceId, const QString &appId);

    Context contextForClient(const wl_client *client) const;
    bool    isSandboxed(const wl_client *client) const {
        return m_clients.contains(client);
    }
    bool        allowsGlobal(const wl_client *client, const wl_global *global) const;
    static bool isPrivileged(const char *interface);

  private:
    struct Listener;
    struct ClientWatch;
    struct Pending;

    void        addListener(int listenFd, int closeFd, const Context &context, const QString &path);
    void        destroyListener(Listener *listener);
    static int  acceptClient(int fd, uint32_t mask, void *data);
    static int  closeFdEvent(int fd, uint32_t mask, void *data);
    static void clientDestroyed(wl_listener *listener, void *data);
    static void bindManager(wl_client *client, void *data, uint32_t version, uint32_t id);
    static void createListener(wl_client *client, wl_resource *manager, uint32_t id,
                               int32_t listenFd, int32_t closeFd);
    static void pendingDestroyed(wl_resource *resource);
    static void setMetadata(wl_resource *resource, QString Context::*field, const char *value,
                            const char *what);
    static void commit(wl_client *, wl_resource *resource);

    wl_display *m_display;
    wl_global  *m_global = nullptr;
    QList<Listener *>                       m_listeners;
    QHash<const wl_client *, ClientWatch *> m_clients;
};

#endif // SECURITYCONTEXTV1_H
