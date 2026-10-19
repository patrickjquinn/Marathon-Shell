#include <QGuiApplication>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QWaylandQuickCompositor>
#include <QWaylandQuickOutput>
#include <QWaylandQuickShellSurfaceItem>
#include <QWaylandSeat>
#include <QWaylandXdgShell>

#include <atomic>
#include <cstring>
#include <thread>
#include <wayland-client.h>

#include "managers/marathoninputmethodengine.h"
#include "services/inputcontext.h"
#include "services/remotetextinput.h"
#include "wayland/remotetextinputtarget.h"
#include "xdg-shell-client.h"

namespace {
    const char *const kApp = "waydroid.org.example";

    // A toplevel that binds no text-input, as Waydroid's hwcomposer is.
    struct Client {
        std::atomic<bool> stop{false};
        std::atomic<bool> done{false};
        wl_compositor    *compositor = nullptr;
        xdg_wm_base      *wmBase     = nullptr;

        void              run(const QByteArray &socket) {
            wl_display *display = wl_display_connect(socket.constData());
            if (!display) {
                done = true;
                return;
            }
            wl_registry                      *registry         = wl_display_get_registry(display);
            static const wl_registry_listener registryListener = {
                [](void *data, wl_registry *registry, uint32_t name, const char *interface,
                   uint32_t) {
                    auto *self = static_cast<Client *>(data);
                    if (std::strcmp(interface, wl_compositor_interface.name) == 0)
                        self->compositor = static_cast<wl_compositor *>(
                            wl_registry_bind(registry, name, &wl_compositor_interface, 4));
                    else if (std::strcmp(interface, xdg_wm_base_interface.name) == 0)
                        self->wmBase = static_cast<xdg_wm_base *>(
                            wl_registry_bind(registry, name, &xdg_wm_base_interface, 1));
                },
                [](void *, wl_registry *, uint32_t) {},
            };
            wl_registry_add_listener(registry, &registryListener, this);
            wl_display_roundtrip(display);

            static const xdg_wm_base_listener wmListener = {
                [](void *, xdg_wm_base *base, uint32_t serial) { xdg_wm_base_pong(base, serial); },
            };
            xdg_wm_base_add_listener(wmBase, &wmListener, nullptr);
            wl_surface                       *surface = wl_compositor_create_surface(compositor);
            xdg_surface                      *xdg = xdg_wm_base_get_xdg_surface(wmBase, surface);
            static const xdg_surface_listener xdgListener = {
                [](void *, xdg_surface *s, uint32_t serial) {
                    xdg_surface_ack_configure(s, serial);
                },
            };
            xdg_surface_add_listener(xdg, &xdgListener, nullptr);
            xdg_toplevel *toplevel = xdg_surface_get_toplevel(xdg);
            xdg_toplevel_set_app_id(toplevel, kApp);
            wl_surface_commit(surface);
            while (!stop && wl_display_roundtrip(display) >= 0) {}
            wl_display_disconnect(display);
            done = true;
        }
    };
} // namespace

// Marathon's keyboard against a real Waydroid-like window: the shell answers
// its queries and takes its commits for that window, whether the window has
// Qt's focus or only the seat's keyboard focus.
class TestRemoteTextInputWayland : public QObject {
    Q_OBJECT

    QTemporaryDir                  m_runtime;
    QWaylandQuickCompositor       *m_compositor = nullptr;
    QQuickWindow                  *m_window     = nullptr;
    QWaylandQuickOutput           *m_output     = nullptr;
    QWaylandQuickShellSurfaceItem *m_item       = nullptr;
    RemoteTextInput               *m_input      = nullptr;
    Client                        *m_client     = nullptr;
    std::thread                    m_thread;

  private slots:
    void init() {
        qputenv("XDG_RUNTIME_DIR", m_runtime.path().toLocal8Bit());
        const QByteArray socket = "marathon-test-remote-text-input";
        m_compositor            = new QWaylandQuickCompositor;
        m_compositor->setSocketName(socket);
        auto *xdgShell = new QWaylandXdgShell(m_compositor);
        m_compositor->create();
        m_window = new QQuickWindow;
        m_output = new QWaylandQuickOutput(m_compositor, m_window);
        m_window->resize(200, 200);
        m_window->show();
        m_window->requestActivate();

        m_item = new QWaylandQuickShellSurfaceItem(m_window->contentItem());
        m_item->setSize(QSizeF(200, 100));
        connect(xdgShell, &QWaylandXdgShell::toplevelCreated, m_item,
                [this](QWaylandXdgToplevel *toplevel, QWaylandXdgSurface *surface) {
                    m_item->setShellSurface(surface);
                    toplevel->sendMaximized(QSize(200, 100));
                    m_item->takeFocus();
                });

        m_client = new Client;
        m_thread = std::thread([this, socket]() { m_client->run(socket); });
        QTRY_COMPARE(QGuiApplication::focusObject(), m_item);
        QTRY_VERIFY(m_compositor->defaultSeat()->keyboardFocus() == m_item->surface());
        QTRY_COMPARE(RemoteTextInputTarget::appIdOf(m_item, m_compositor),
                     QString::fromLatin1(kApp));

        QWaylandCompositor *compositor = m_compositor;
        m_input                        = new RemoteTextInput([compositor](QObject *object) {
            return RemoteTextInputTarget::appIdOf(object, compositor);
        });
        m_input->setService(QStringLiteral("waydroid."));
        m_input->setEditor(QString::fromLatin1(kApp), 5, 0);
    }

    void cleanup() {
        delete m_input;
        m_client->stop = true;
        QTRY_VERIFY(m_client->done.load());
        m_thread.join();
        delete m_client;
        delete m_item;
        delete m_output;
        delete m_window;
        QTRY_VERIFY(m_compositor->clients().isEmpty());
        delete m_compositor;
    }

    // QInputMethod::queryFocusObject calls QWaylandQuickItem's invokable
    // inputMethodQuery directly, past event filters.
    void keyboardSeesTheFieldsHints() {
        InputContext context;
        context.detectInputMode();
        QCOMPARE(context.inputMode(), QStringLiteral("url"));
        MarathonInputMethodEngine engine;
        QVERIFY(engine.focusHints() & Qt::ImhUrlCharactersOnly);
    }

    void typedTextIsCommitted() {
        QSignalSpy   commits(m_input, &RemoteTextInput::commitString);
        InputContext context;
        context.insertText(QStringLiteral("hi"));
        QCOMPARE(commits.count(), 1);
        QCOMPARE(commits.at(0).at(1).toString(), QStringLiteral("hi"));
    }

    void seatFocusAloneIsEnough() {
        QQuickItem other(m_window->contentItem());
        other.forceActiveFocus();
        QTRY_COMPARE(QGuiApplication::focusObject(), &other);
        QCOMPARE(m_compositor->defaultSeat()->keyboardFocus(), m_item->surface());
        QSignalSpy   commits(m_input, &RemoteTextInput::commitString);
        InputContext context;
        context.insertText(QStringLiteral("x"));
        QCOMPARE(commits.count(), 1);
        context.detectInputMode();
        QCOMPARE(context.inputMode(), QStringLiteral("url"));
    }

    void shellTextFieldsKeepTheirText() {
        QQuickItem field(m_window->contentItem());
        field.setFlag(QQuickItem::ItemAcceptsInputMethod);
        field.forceActiveFocus();
        QTRY_COMPARE(QGuiApplication::focusObject(), &field);
        QSignalSpy   commits(m_input, &RemoteTextInput::commitString);
        InputContext context;
        context.insertText(QStringLiteral("x"));
        QCOMPARE(commits.count(), 0);
    }
};

QTEST_MAIN(TestRemoteTextInputWayland)
#include "test_remotetextinputwayland.moc"
