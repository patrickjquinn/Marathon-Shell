#include <QtTest>
#include <QGuiApplication>
#include <QTemporaryDir>
#include <QWaylandCompositor>

#include <atomic>
#include <cstring>
#include <fcntl.h>
#include <mutex>
#include <set>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <thread>
#include <unistd.h>
#include <wayland-client.h>
#include <wayland-server-core.h>

#include "security-context-v1-client.h"
#include "securitycontextv1.h"

namespace {
    // Connects, records the globals it is offered, and stays connected until
    // stop. With an engine socket set, it registers that socket through the
    // protocol the way Flatpak does, and hangs up close_fd when told to.
    struct Client {
        std::string                     socket;
        std::string                     engineSocket;
        std::atomic<bool>               connected{false};
        std::atomic<bool>               failed{false};
        std::atomic<bool>               registered{false};
        std::atomic<bool>               hangUp{false};
        std::atomic<bool>               stop{false};
        std::atomic<bool>               done{false};
        std::mutex                      lock;
        std::set<std::string>           globals;
        wp_security_context_manager_v1 *manager = nullptr;

        bool                            sees(const std::string &interface) {
            std::lock_guard<std::mutex> guard(lock);
            return globals.count(interface) != 0;
        }

        void run() {
            wl_display *display = wl_display_connect(socket.c_str());
            if (!display) {
                failed = true;
                done   = true;
                return;
            }
            wl_registry                      *registry = wl_display_get_registry(display);
            static const wl_registry_listener listener = {
                [](void *data, wl_registry *registry, uint32_t name, const char *interface,
                   uint32_t) {
                    auto *self = static_cast<Client *>(data);
                    {
                        std::lock_guard<std::mutex> guard(self->lock);
                        self->globals.insert(interface);
                    }
                    if (std::strcmp(interface, wp_security_context_manager_v1_interface.name) == 0)
                        self->manager =
                            static_cast<wp_security_context_manager_v1 *>(wl_registry_bind(
                                registry, name, &wp_security_context_manager_v1_interface, 1));
                },
                [](void *, wl_registry *, uint32_t) {},
            };
            wl_registry_add_listener(registry, &listener, this);
            wl_display_roundtrip(display);
            connected = true;

            int closeWrite = -1;
            if (!engineSocket.empty() && manager)
                closeWrite = registerSocket(display);

            while (!stop && wl_display_roundtrip(display) >= 0) {
                if (hangUp && closeWrite >= 0) {
                    close(closeWrite);
                    closeWrite = -1;
                }
                usleep(5000);
            }
            if (closeWrite >= 0)
                close(closeWrite);
            wl_display_disconnect(display);
            done = true;
        }

        int registerSocket(wl_display *display) {
            const int   listenFd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
            sockaddr_un address{};
            address.sun_family = AF_UNIX;
            std::strncpy(address.sun_path, engineSocket.c_str(), sizeof(address.sun_path) - 1);
            bind(listenFd, reinterpret_cast<sockaddr *>(&address), sizeof(address));
            listen(listenFd, 8);
            int closeFds[2];
            if (pipe2(closeFds, O_CLOEXEC) != 0)
                return -1;
            wp_security_context_v1 *context =
                wp_security_context_manager_v1_create_listener(manager, listenFd, closeFds[0]);
            wp_security_context_v1_set_sandbox_engine(context, "org.flatpak");
            wp_security_context_v1_set_app_id(context, "de.haeckerfelix.Shortwave");
            wp_security_context_v1_set_instance_id(context, "1234");
            wp_security_context_v1_commit(context);
            wp_security_context_v1_destroy(context);
            wl_display_roundtrip(display);
            close(listenFd);
            close(closeFds[0]);
            registered = true;
            return closeFds[1];
        }
    };

    struct ClientThread {
        Client      client;
        std::thread thread;

        explicit ClientThread(const QByteArray &socket, const QByteArray &engineSocket = {}) {
            client.socket       = socket.toStdString();
            client.engineSocket = engineSocket.toStdString();
            thread              = std::thread([this]() { client.run(); });
        }
        // The client's last roundtrip needs the compositor, which runs here.
        ~ClientThread() {
            client.stop = true;
            while (!client.done)
                QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
            thread.join();
        }
    };

    // Stands in for a capture protocol: only the interface name matters.
    const wl_interface kScreencopyInterface = {
        "zwlr_screencopy_manager_v1", 3, 0, nullptr, 0, nullptr};
} // namespace

class TestSecurityContext : public QObject {
    Q_OBJECT

    QTemporaryDir            *runtime    = nullptr;
    QWaylandCompositor       *compositor = nullptr;
    SecurityContextManagerV1 *manager    = nullptr;
    wl_global                *screencopy = nullptr;
    QByteArray                mainSocket;

    static bool               filter(const wl_client *client, const wl_global *global, void *data) {
        return static_cast<SecurityContextManagerV1 *>(data)->allowsGlobal(client, global);
    }

    QList<wl_client *> sandboxedClients() const {
        QList<wl_client *> out;
        wl_client         *client = nullptr;
        wl_client_for_each(
            client, wl_display_get_client_list(static_cast<wl_display *>(compositor->display()))) {
            if (manager->isSandboxed(client))
                out << client;
        }
        return out;
    }

    QByteArray path(const char *name) const {
        return (runtime->path() + QLatin1Char('/') + QLatin1String(name)).toLocal8Bit();
    }

  private slots:
    void init() {
        runtime = new QTemporaryDir;
        qputenv("XDG_RUNTIME_DIR", runtime->path().toLocal8Bit());
        mainSocket = path("marathon-test-security-context");
        compositor = new QWaylandCompositor;
        compositor->setSocketName("marathon-test-security-context");
        compositor->create();
        auto *display = static_cast<wl_display *>(compositor->display());
        manager       = new SecurityContextManagerV1(compositor);
        screencopy    = wl_global_create(display, &kScreencopyInterface, 3, nullptr,
                                         [](wl_client *, void *, uint32_t, uint32_t) {});
        wl_display_set_global_filter(display, &TestSecurityContext::filter, manager);
    }

    void cleanup() {
        wl_display_set_global_filter(static_cast<wl_display *>(compositor->display()), nullptr,
                                     nullptr);
        wl_global_destroy(screencopy);
        delete compositor;
        delete runtime;
    }

    void privilegedInterfaces() {
        QVERIFY(SecurityContextManagerV1::isPrivileged("wp_security_context_manager_v1"));
        QVERIFY(SecurityContextManagerV1::isPrivileged("zwlr_screencopy_manager_v1"));
        QVERIFY(SecurityContextManagerV1::isPrivileged("ext_image_copy_capture_manager_v1"));
        QVERIFY(SecurityContextManagerV1::isPrivileged("zwp_virtual_keyboard_manager_v1"));
        QVERIFY(SecurityContextManagerV1::isPrivileged("zwlr_layer_shell_v1"));
        QVERIFY(SecurityContextManagerV1::isPrivileged("zwlr_data_control_manager_v1"));
        QVERIFY(!SecurityContextManagerV1::isPrivileged("wl_compositor"));
        QVERIFY(!SecurityContextManagerV1::isPrivileged("xdg_wm_base"));
        QVERIFY(!SecurityContextManagerV1::isPrivileged("zwp_text_input_manager_v3"));
        QVERIFY(!SecurityContextManagerV1::isPrivileged("zwp_linux_dmabuf_v1"));
    }

    void unsandboxedClientSeesEverything() {
        ClientThread shell(mainSocket);
        QTRY_VERIFY(shell.client.connected);
        QVERIFY(shell.client.sees("wl_compositor"));
        QVERIFY(shell.client.sees("wp_security_context_manager_v1"));
        QVERIFY(shell.client.sees("zwlr_screencopy_manager_v1"));
        QVERIFY(sandboxedClients().isEmpty());
    }

    void shellListenerTagsAndRestrictsClients() {
        const QByteArray socket = path("app-socket");
        QVERIFY(manager->listen(QString::fromLocal8Bit(socket),
                                {"org.marathonos.AppRunner", "notes", "notes-1"}));
        ClientThread app(socket);
        QTRY_VERIFY(app.client.connected);
        QVERIFY(app.client.sees("wl_compositor"));
        QVERIFY(app.client.sees("wl_seat"));
        QVERIFY(!app.client.sees("zwlr_screencopy_manager_v1"));
        QVERIFY(!app.client.sees("wp_security_context_manager_v1"));

        const QList<wl_client *> sandboxed = sandboxedClients();
        QCOMPARE(sandboxed.size(), 1);
        const SecurityContextManagerV1::Context context = manager->contextForClient(sandboxed[0]);
        QCOMPARE(context.engine, QStringLiteral("org.marathonos.AppRunner"));
        QCOMPARE(context.appId, QStringLiteral("notes"));
        QCOMPARE(context.instanceId, QStringLiteral("notes-1"));
    }

    void closedListenerRefusesNewClientsKeepsOldOnes() {
        const QByteArray socket = path("app-socket");
        QVERIFY(manager->listen(QString::fromLocal8Bit(socket),
                                {"org.marathonos.AppRunner", "notes", "notes-1"}));
        ClientThread first(socket);
        QTRY_VERIFY(first.client.connected);
        manager->closeListener("notes-1");
        QVERIFY(!QFile::exists(QString::fromLocal8Bit(socket)));

        ClientThread second(socket);
        QTRY_VERIFY(second.client.done);
        QVERIFY(second.client.failed);
        QCOMPARE(sandboxedClients().size(), 1);
    }

    void disconnectedClientIsForgotten() {
        const QByteArray socket = path("app-socket");
        QVERIFY(manager->listen(QString::fromLocal8Bit(socket),
                                {"org.marathonos.AppRunner", "notes", "notes-1"}));
        {
            ClientThread app(socket);
            QTRY_VERIFY(app.client.connected);
            QCOMPARE(sandboxedClients().size(), 1);
        }
        QTRY_VERIFY(wl_list_empty(
            wl_display_get_client_list(static_cast<wl_display *>(compositor->display()))));
        ClientThread shell(mainSocket);
        QTRY_VERIFY(shell.client.connected);
        QVERIFY(sandboxedClients().isEmpty());
    }

    void poolRunnerGetsItsAppOnAdoption() {
        const QByteArray socket = path("pool-socket");
        QVERIFY(manager->listen(QString::fromLocal8Bit(socket),
                                {"org.marathonos.AppRunner", QString(), "pool-1"}));
        ClientThread spare(socket);
        QTRY_VERIFY(spare.client.connected);
        QCOMPARE(manager->contextForClient(sandboxedClients().value(0)).appId, QString());

        manager->assignAppId("pool-1", "clock");
        QCOMPARE(manager->contextForClient(sandboxedClients().value(0)).appId,
                 QStringLiteral("clock"));
        manager->assignAppId("pool-1", "notes");
        QCOMPARE(manager->contextForClient(sandboxedClients().value(0)).appId,
                 QStringLiteral("clock"));
    }

    // Flatpak destroys the context object right after commit and keeps only
    // close_fd: the listener must outlive both.
    void flatpakRegisteredListener() {
        const QByteArray socket = path("flatpak-wayland");
        ClientThread     flatpak(mainSocket, socket);
        QTRY_VERIFY(flatpak.client.registered);

        {
            ClientThread app(socket);
            QTRY_VERIFY(app.client.connected);
            QVERIFY(!app.client.sees("wp_security_context_manager_v1"));
            QVERIFY(!app.client.sees("zwlr_screencopy_manager_v1"));
            const QList<wl_client *> sandboxed = sandboxedClients();
            QCOMPARE(sandboxed.size(), 1);
            const SecurityContextManagerV1::Context context =
                manager->contextForClient(sandboxed[0]);
            QCOMPARE(context.engine, QStringLiteral("org.flatpak"));
            QCOMPARE(context.appId, QStringLiteral("de.haeckerfelix.Shortwave"));
            QCOMPARE(context.instanceId, QStringLiteral("1234"));
        }

        flatpak.client.hangUp = true;
        QTest::qWait(200);
        ClientThread late(socket);
        QTRY_VERIFY(late.client.done);
        QVERIFY(late.client.failed || !late.client.connected);
    }
};

int main(int argc, char **argv) {
    QGuiApplication     app(argc, argv);
    TestSecurityContext test;
    return QTest::qExec(&test, argc, argv);
}

#include "test_securitycontext.moc"
