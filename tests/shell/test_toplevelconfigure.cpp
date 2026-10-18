#include <QGuiApplication>
#include <QTemporaryDir>
#include <QTest>
#include <QWaylandCompositor>
#include <QWaylandOutput>
#include <QWaylandXdgShell>
#include <QWindow>

#include <QPointer>

#include <algorithm>
#include <atomic>
#include <cstring>
#include <mutex>
#include <poll.h>
#include <thread>
#include <vector>
#include <wayland-client.h>
#include <wayland-server-core.h>

#include "toplevelconfigure.h"
#include "xdg-shell-client.h"

namespace {
    // One toplevel that acks every configure and records what it was sent.
    struct Client {
        struct Configure {
            int                   width;
            int                   height;
            std::vector<uint32_t> states;
        };
        std::mutex             lock;
        std::vector<Configure> configures;
        std::atomic<bool>      stop{false};
        std::atomic<bool>      done{false};
        std::atomic<bool>      holdAcks{false};

        wl_compositor         *compositor = nullptr;
        xdg_wm_base           *wm         = nullptr;
        xdg_surface           *xdgSurface = nullptr;
        std::vector<uint32_t>  pending;
        std::vector<uint32_t>  held;

        size_t                 count() {
            std::scoped_lock guard(lock);
            return configures.size();
        }
        Configure last() {
            std::scoped_lock guard(lock);
            return configures.back();
        }

        void run(const QByteArray &socket) {
            wl_display *display = wl_display_connect(socket.constData());
            if (!display) {
                done = true;
                return;
            }
            static const wl_registry_listener registryListener = {
                [](void *data, wl_registry *registry, uint32_t name, const char *interface,
                   uint32_t) {
                    auto *self = static_cast<Client *>(data);
                    if (std::strcmp(interface, wl_compositor_interface.name) == 0)
                        self->compositor = static_cast<wl_compositor *>(
                            wl_registry_bind(registry, name, &wl_compositor_interface, 4));
                    else if (std::strcmp(interface, xdg_wm_base_interface.name) == 0)
                        self->wm = static_cast<xdg_wm_base *>(
                            wl_registry_bind(registry, name, &xdg_wm_base_interface, 1));
                },
                [](void *, wl_registry *, uint32_t) {},
            };
            wl_registry_add_listener(wl_display_get_registry(display), &registryListener, this);
            wl_display_roundtrip(display);

            wl_surface *surface = wl_compositor_create_surface(compositor);
            xdgSurface          = xdg_wm_base_get_xdg_surface(wm, surface);
            static const xdg_surface_listener surfaceListener = {
                [](void *data, xdg_surface *xdg, uint32_t serial) {
                    auto *self = static_cast<Client *>(data);
                    if (self->holdAcks) {
                        self->held.push_back(serial);
                        return;
                    }
                    xdg_surface_ack_configure(xdg, serial);
                },
            };
            xdg_surface_add_listener(xdgSurface, &surfaceListener, this);
            xdg_toplevel *toplevel = xdg_surface_get_toplevel(xdgSurface);
            static const xdg_toplevel_listener toplevelListener = {
                [](void *data, xdg_toplevel *, int32_t width, int32_t height, wl_array *states) {
                    auto                 *self = static_cast<Client *>(data);
                    std::vector<uint32_t> list;
                    const auto           *begin = static_cast<const uint32_t *>(states->data);
                    list.assign(begin, begin + states->size / sizeof(uint32_t));
                    std::scoped_lock guard(self->lock);
                    self->configures.push_back({width, height, list});
                },
                [](void *, xdg_toplevel *) {},
                nullptr,
                nullptr,
            };
            xdg_toplevel_add_listener(toplevel, &toplevelListener, this);
            xdg_toplevel_set_app_id(toplevel, "waydroid.test");
            wl_surface_commit(surface);

            while (!stop) {
                if (!holdAcks) {
                    for (uint32_t serial : held)
                        xdg_surface_ack_configure(xdgSurface, serial);
                    held.clear();
                }
                wl_display_flush(display);
                pollfd fd{wl_display_get_fd(display), POLLIN, 0};
                if (poll(&fd, 1, 10) > 0 && wl_display_dispatch(display) < 0)
                    break;
            }
            wl_display_disconnect(display);
            done = true;
        }
    };
} // namespace

class TestToplevelConfigure : public QObject {
    Q_OBJECT

    QTemporaryDir                  runtime;
    QWaylandCompositor            *compositor = nullptr;
    QWindow                       *window     = nullptr;
    QWaylandOutput                *output     = nullptr;
    QPointer<QWaylandXdgToplevel>  toplevel;
    Client                        *client = nullptr;
    std::thread                    thread;

    using State = QWaylandXdgToplevel::State;

    // What the client has received; the compositor flushes only when it renders.
    size_t received() {
        wl_display_flush_clients(static_cast<wl_display *>(compositor->display()));
        return client->count();
    }

  private slots:
    void init() {
        qputenv("XDG_RUNTIME_DIR", runtime.path().toLocal8Bit());
        static int       run    = 0;
        const QByteArray socket = "marathon-test-configure-" + QByteArray::number(run++);
        compositor              = new QWaylandCompositor;
        compositor->setSocketName(socket);
        auto *shell = new QWaylandXdgShell(compositor);
        connect(shell, &QWaylandXdgShell::toplevelCreated, this,
                [this](QWaylandXdgToplevel *created, QWaylandXdgSurface *) { toplevel = created; });
        compositor->create();
        window = new QWindow;
        output = new QWaylandOutput(compositor, window);
        client = new Client;
        thread = std::thread([this, socket]() { client->run(socket); });
        QTRY_VERIFY(toplevel);
        // Qt's own first configure, with no size.
        QTRY_COMPARE(received(), size_t(1));
        QTRY_VERIFY(ToplevelConfigure::settled(toplevel));
    }

    void cleanup() {
        client->stop = true;
        thread.join();
        delete client;
        delete output;
        delete window;
        delete compositor;
    }

    void aRepeatIsNotSent() {
        const QList<State> states{State::MaximizedState, State::ActivatedState};
        QVERIFY(ToplevelConfigure::send(toplevel, QSize(480, 419), states));
        QTRY_COMPARE(received(), size_t(2));
        QVERIFY(!ToplevelConfigure::send(toplevel, QSize(480, 419), states));
        QVERIFY(!ToplevelConfigure::send(toplevel, QSize(480, 419),
                                         {State::ActivatedState, State::MaximizedState}));
        QTest::qWait(50);
        QCOMPARE(received(), size_t(2));
        QCOMPARE(ToplevelConfigure::lastSize(toplevel), QSize(480, 419));
    }

    void aChangeIsSent() {
        QVERIFY(ToplevelConfigure::send(toplevel, QSize(480, 419), {State::MaximizedState}));
        QVERIFY(ToplevelConfigure::send(toplevel, QSize(480, 419),
                                        {State::MaximizedState, State::ActivatedState}));
        QVERIFY(ToplevelConfigure::send(toplevel, QSize(480, 300),
                                        {State::MaximizedState, State::ActivatedState}));
        QTRY_COMPARE(received(), size_t(4));
        QCOMPARE(client->last().height, 300);
    }

    // A resize keeps "activated": dropping it deactivated the window.
    void aResizeKeepsTheStates() {
        QVERIFY(ToplevelConfigure::send(toplevel, QSize(480, 419),
                                        {State::MaximizedState, State::ActivatedState}));
        QVERIFY(!ToplevelConfigure::resize(toplevel, QSize(480, 419)));
        QVERIFY(ToplevelConfigure::resize(toplevel, QSize(480, 300)));
        QTRY_COMPARE(received(), size_t(3));
        const auto states = client->last().states;
        QCOMPARE(states.size(), size_t(2));
        QVERIFY(std::find(states.cbegin(), states.cend(), 4u) != states.cend());
    }

    void activationKeepsTheSize() {
        QVERIFY(ToplevelConfigure::send(toplevel, QSize(480, 419), {State::MaximizedState}));
        QVERIFY(ToplevelConfigure::setActivated(toplevel, true));
        QVERIFY(!ToplevelConfigure::setActivated(toplevel, true));
        QTRY_COMPARE(received(), size_t(3));
        QCOMPARE(client->last().height, 419);
        QCOMPARE(client->last().states.size(), size_t(2));
        QVERIFY(ToplevelConfigure::setActivated(toplevel, false));
        QTRY_COMPARE(received(), size_t(4));
        QCOMPARE(client->last().states, std::vector<uint32_t>{1});
    }

    // The nudge's redraw request: what was last sent, not the acked state.
    void aRepeatRequestSendsTheLastConfigure() {
        client->holdAcks = true;
        QVERIFY(ToplevelConfigure::send(toplevel, QSize(480, 419),
                                        {State::MaximizedState, State::ActivatedState}));
        QVERIFY(ToplevelConfigure::repeat(toplevel));
        QTRY_COMPARE(received(), size_t(3));
        QCOMPARE(client->last().states.size(), size_t(2));
        client->holdAcks = false;
    }

    void unackedIsNotSettled() {
        client->holdAcks = true;
        QVERIFY(ToplevelConfigure::send(toplevel, QSize(480, 419), {State::MaximizedState}));
        QTRY_COMPARE(received(), size_t(2));
        QVERIFY(!ToplevelConfigure::settled(toplevel));
        client->holdAcks = false;
        QTRY_VERIFY(ToplevelConfigure::settled(toplevel));
    }
};

int main(int argc, char **argv) {
    QGuiApplication       app(argc, argv);
    TestToplevelConfigure test;
    return QTest::qExec(&test, argc, argv);
}

#include "test_toplevelconfigure.moc"
