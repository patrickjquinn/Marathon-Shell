#ifndef XDGACTIVATIONV1_H
#define XDGACTIVATIONV1_H

#include <QElapsedTimer>
#include <QHash>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QWaylandSurface>
#include <wayland-server-core.h>

class QWaylandCompositor;

// xdg_activation_v1 (staging/xdg-activation). A token activates a surface
// once. The shell issues tokens for the processes it launches; a client's
// own token is honoured only if it holds keyboard focus and its serial is
// from the latest user input.
class XdgActivationV1 : public QObject {
    Q_OBJECT

  public:
    static constexpr qint64 kClientTokenMs = 30000;
    // L5 WebEngine apps take 60-90 s from launch to their first window.
    static constexpr qint64 kLaunchTokenMs = 120000;

    explicit XdgActivationV1(QWaylandCompositor *compositor);
    ~XdgActivationV1() override;

    // A token for launch, a process the shell is about to start.
    QString issueToken(QObject *launch);
    // A press, touch or key from the user is about to reach a client.
    void noteUserInput();

    // serial came after the input serial mark and no later than now.
    static bool serialAfter(uint32_t serial, uint32_t mark, uint32_t now);

    // Request handlers, public for the C dispatch tables.
    static void bind(wl_client *client, void *data, uint32_t version, uint32_t id);
    static void createToken(wl_client *client, wl_resource *manager, uint32_t id);
    static void activate(wl_client *client, wl_resource *manager, const char *token,
                         wl_resource *surface);
    static void commitToken(wl_client *client, wl_resource *resource);

  signals:
    // An honoured activate. launch is the process the shell issued the
    // token for while it lives, otherwise null.
    void activated(QWaylandSurface *surface, QObject *launch);

  private:
    struct Token {
        QPointer<QObject> launch;
        qint64            expiresMs = 0;
    };

    static QString        newToken();
    QString               addToken(QObject *launch, qint64 lifetimeMs);
    bool                  mayActivate(wl_client *client, uint32_t serial) const;

    QWaylandCompositor   *m_compositor;
    wl_global            *m_global = nullptr;
    QHash<QString, Token> m_tokens;
    QElapsedTimer         m_clock;
    uint32_t              m_inputSerial = 0;
    bool                  m_hadInput    = false;
};

#endif // XDGACTIVATIONV1_H
