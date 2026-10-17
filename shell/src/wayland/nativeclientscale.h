#ifndef NATIVECLIENTSCALE_H
#define NATIVECLIENTSCALE_H

#include <QByteArray>
#include <QObject>
#include <QSet>
#include <QSize>

class QWaylandCompositor;
struct wl_client;
struct wl_display;
struct wl_global;
struct wl_resource;

// The scale native Wayland clients (GTK, Qt, Flatpak apps) draw at. The shell
// runs Qt at scale 1 and sizes its own UI by DPI, so without this a native
// app draws at desktop size on a phone panel. Fractional clients get it from
// wp_fractional_scale_v1; integer-only ones (GTK3) get its ceiling as their
// wl_output scale and are drawn scaled down. Marathon's own clients scale
// themselves, so they see neither and stay at 1.
class NativeClientScale : public QObject {
    Q_OBJECT

  public:
    explicit NativeClientScale(QWaylandCompositor *compositor);
    ~NativeClientScale() override;

    // The shell's own scale factor (DPI/160, or base when set) times the
    // user's interface size, in quarter steps and never below 1.
    static qreal fromDpi(qreal dpi, qreal userScale, qreal base);
    // A client the shell started carries MARATHON_SHELL_PID=<its pid>.
    static bool  startedByShell(const QByteArray &environment, qint64 shellPid);
    static QSize toLogical(const QSize &size, qreal scale);
    static uint  toWire(qreal scale) {
        return static_cast<uint>(qRound(scale * 120));
    }

    qreal scale() const {
        return m_scale;
    }
    void setScale(qreal scale);
    bool isFirstParty(wl_client *client) const {
        return m_firstParty.contains(client);
    }
    qreal scaleFor(wl_client *client) const {
        return isFirstParty(client) ? 1.0 : m_scale;
    }
    // First-party clients do not see the fractional scale global.
    bool allowsGlobal(const wl_client *client, const wl_global *global) const {
        return global != m_global || !m_firstParty.contains(const_cast<wl_client *>(client));
    }

  signals:
    void scaleChanged();

  private:
    struct ClientWatch;
    struct OutputWatch;
    struct FractionalScale;
    struct ClientCreated;

    static void clientCreated(struct wl_listener *listener, void *data);
    static void resourceCreated(struct wl_listener *listener, void *data);
    static void clientDestroyed(struct wl_listener *listener, void *data);
    static void outputDestroyed(struct wl_listener *listener, void *data);
    static void sendOutputScale(void *data);
    static void bindManager(struct wl_client *client, void *data, uint32_t version, uint32_t id);
    static void getFractionalScale(struct wl_client *client, struct wl_resource *manager,
                                   uint32_t id, struct wl_resource *surface);
    static void surfaceDestroyed(struct wl_listener *listener, void *data);
    static void fractionalDestroyed(struct wl_resource *resource);

    void        watchOutput(struct wl_resource *output);

    struct wl_display      *m_display;
    struct wl_global       *m_global        = nullptr;
    ClientCreated          *m_clientCreated = nullptr;
    qreal                   m_scale         = 1.0;
    QSet<ClientWatch *>     m_clients;
    QSet<wl_client *>       m_firstParty;
    QSet<OutputWatch *>     m_outputs;
    QSet<FractionalScale *> m_fractional;
};

#endif // NATIVECLIENTSCALE_H
