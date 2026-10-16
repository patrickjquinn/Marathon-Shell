#include <QtTest>
#include <QGuiApplication>
#include <QProcess>
#include <QTemporaryDir>
#include <QWaylandCompositor>
#include <QWaylandOutput>
#include <QWindow>

#include <atomic>
#include <cstdio>
#include <cstring>
#include <thread>
#include <wayland-client.h>

#include "fractional-scale-v1-client.h"
#include "nativeclientscale.h"

namespace {
    // A bare client: binds wl_output and wp_fractional_scale_manager_v1, gives
    // one surface a fractional scale object, and records what it is told.
    struct Client {
        std::atomic<int>                outputScale{0};
        std::atomic<int>                preferredScale{0};
        std::atomic<bool>               sawFractionalGlobal{false};
        std::atomic<bool>               stop{false};
        std::atomic<bool>               done{false};
        int                             roundtrips = -1;

        wl_compositor                  *compositor = nullptr;
        wl_output                      *output     = nullptr;
        wp_fractional_scale_manager_v1 *manager    = nullptr;

        void                            run(const QByteArray &socket) {
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
                    if (std::strcmp(interface, wl_compositor_interface.name) == 0) {
                        self->compositor = static_cast<wl_compositor *>(
                            wl_registry_bind(registry, name, &wl_compositor_interface, 4));
                    } else if (std::strcmp(interface, wl_output_interface.name) == 0) {
                        self->output = static_cast<wl_output *>(
                            wl_registry_bind(registry, name, &wl_output_interface, 2));
                        static const wl_output_listener outputListener = {
                            [](void *, wl_output *, int32_t, int32_t, int32_t, int32_t, int32_t,
                               const char *, const char *, int32_t) {},
                            [](void *, wl_output *, uint32_t, int32_t, int32_t, int32_t) {},
                            [](void *, wl_output *) {},
                            [](void *data, wl_output *, int32_t factor) {
                                static_cast<Client *>(data)->outputScale = factor;
                            },
                            nullptr,
                            nullptr,
                        };
                        wl_output_add_listener(self->output, &outputListener, self);
                    } else if (std::strcmp(interface,
                                           wp_fractional_scale_manager_v1_interface.name) == 0) {
                        self->sawFractionalGlobal = true;
                        self->manager =
                            static_cast<wp_fractional_scale_manager_v1 *>(wl_registry_bind(
                                registry, name, &wp_fractional_scale_manager_v1_interface, 1));
                    }
                },
                [](void *, wl_registry *, uint32_t) {},
            };
            wl_registry_add_listener(registry, &registryListener, this);
            wl_display_roundtrip(display);

            if (compositor && manager) {
                wl_surface             *surface = wl_compositor_create_surface(compositor);
                wp_fractional_scale_v1 *fractional =
                    wp_fractional_scale_manager_v1_get_fractional_scale(manager, surface);
                static const wp_fractional_scale_v1_listener fractionalListener = {
                    [](void *data, wp_fractional_scale_v1 *, uint32_t scale) {
                        static_cast<Client *>(data)->preferredScale = static_cast<int>(scale);
                    },
                };
                wp_fractional_scale_v1_add_listener(fractional, &fractionalListener, this);
            }
            while (!stop && roundtrips-- != 0 && wl_display_roundtrip(display) >= 0) {}
            wl_display_disconnect(display);
            done = true;
        }
    };
} // namespace

class TestNativeClientScale : public QObject {
    Q_OBJECT

  private slots:
    void scaleFromDpi_data() {
        QTest::addColumn<qreal>("dpi");
        QTest::addColumn<qreal>("userScale");
        QTest::addColumn<qreal>("base");
        QTest::addColumn<qreal>("scale");
        QTest::newRow("librem5 287") << 287.0 << 1.0 << 0.0 << 1.75;
        QTest::newRow("pinephone 270") << 270.0 << 1.0 << 0.0 << 1.75;
        QTest::newRow("qemu 296") << 296.0 << 1.0 << 0.0 << 1.75;
        QTest::newRow("hackberrypi 254") << 254.0 << 1.0 << 0.0 << 1.5;
        QTest::newRow("oneplus6 402") << 402.0 << 1.0 << 0.0 << 2.5;
        QTest::newRow("reference 160") << 160.0 << 1.0 << 0.0 << 1.0;
        QTest::newRow("desktop 96 never below 1") << 96.0 << 1.0 << 0.0 << 1.0;
        QTest::newRow("no screen") << 0.0 << 1.0 << 0.0 << 1.0;
        QTest::newRow("larger interface") << 254.0 << 1.2 << 0.0 << 2.0;
        QTest::newRow("smaller interface") << 287.0 << 0.85 << 0.0 << 1.5;
        QTest::newRow("profile base") << 254.0 << 1.0 << 1.25 << 1.25;
        QTest::newRow("profile base, larger interface") << 254.0 << 1.2 << 1.25 << 1.5;
    }

    void scaleFromDpi() {
        QFETCH(qreal, dpi);
        QFETCH(qreal, userScale);
        QFETCH(qreal, base);
        QFETCH(qreal, scale);
        QCOMPARE(NativeClientScale::fromDpi(dpi, userScale, base), scale);
    }

    void logicalSizes() {
        QCOMPARE(NativeClientScale::toLogical(QSize(720, 1344), 1.0), QSize(720, 1344));
        QCOMPARE(NativeClientScale::toLogical(QSize(720, 668), 1.5), QSize(480, 445));
        QCOMPARE(NativeClientScale::toLogical(QSize(720, 1344), 1.75), QSize(411, 768));
        QCOMPARE(NativeClientScale::toWire(1.0), 120u);
        QCOMPARE(NativeClientScale::toWire(1.5), 180u);
        QCOMPARE(NativeClientScale::toWire(1.75), 210u);
    }

    void startedByShell() {
        const QByteArray environment("HOME=/home/user\0MARATHON_SHELL_PID=42\0LANG=C\0", 44);
        QVERIFY(NativeClientScale::startedByShell(environment, 42));
        QVERIFY(!NativeClientScale::startedByShell(environment, 4));
        QVERIFY(!NativeClientScale::startedByShell(environment, 420));
        QVERIFY(!NativeClientScale::startedByShell(QByteArray("MARATHON_SHELL_PID=420", 22), 42));
        QVERIFY(!NativeClientScale::startedByShell(QByteArray(), 42));
    }

    // This test process was not started by a shell, so it is a native client.
    void nativeClientIsToldTheScale() {
        QTemporaryDir runtime;
        qputenv("XDG_RUNTIME_DIR", runtime.path().toLocal8Bit());
        const QByteArray   socket = "marathon-test-native-scale";

        QWaylandCompositor compositor;
        compositor.setSocketName(socket);
        compositor.create();
        QWindow        window;
        QWaylandOutput output(&compositor, &window);
        auto          *scale = new NativeClientScale(&compositor);
        scale->setScale(1.5);

        Client      client;
        std::thread thread([&client, &socket]() { client.run(socket); });

        QTRY_VERIFY(client.sawFractionalGlobal);
        QTRY_COMPARE(client.preferredScale.load(), 180);
        QTRY_COMPARE(client.outputScale.load(), 2);

        scale->setScale(1.25);
        QTRY_COMPARE(client.preferredScale.load(), 150);
        QTRY_COMPARE(client.outputScale.load(), 2);

        scale->setScale(2.5);
        QTRY_COMPARE(client.preferredScale.load(), 300);
        QTRY_COMPARE(client.outputScale.load(), 3);

        client.stop = true;
        QTRY_VERIFY(client.done);
        thread.join();
    }

    // A client the shell started (MARATHON_SHELL_PID in its environment)
    // sees no fractional scale global and keeps wl_output scale 1.
    void shellClientStaysAtOne() {
        QTemporaryDir runtime;
        qputenv("XDG_RUNTIME_DIR", runtime.path().toLocal8Bit());
        const QByteArray   socket = "marathon-test-shell-client";

        QWaylandCompositor compositor;
        compositor.setSocketName(socket);
        compositor.create();
        QWindow        window;
        QWaylandOutput output(&compositor, &window);
        auto          *scale = new NativeClientScale(&compositor);
        scale->setScale(1.5);

        QProcess            probe;
        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert("MARATHON_SHELL_PID", QString::number(QCoreApplication::applicationPid()));
        probe.setProcessEnvironment(env);
        probe.start(QCoreApplication::applicationFilePath(),
                    {QStringLiteral("--probe"), QString::fromLatin1(socket)});
        QTRY_COMPARE(probe.state(), QProcess::NotRunning);
        QCOMPARE(probe.readAllStandardOutput().trimmed(), QByteArray("fractional=0 output=1"));
    }
};

// --probe SOCKET: connect as a client, then print what the compositor sent.
int main(int argc, char **argv) {
    if (argc == 3 && std::strcmp(argv[1], "--probe") == 0) {
        Client client;
        client.roundtrips = 4;
        client.run(argv[2]);
        std::printf("fractional=%d output=%d\n", client.sawFractionalGlobal.load() ? 1 : 0,
                    client.outputScale.load());
        return 0;
    }
    QGuiApplication       app(argc, argv);
    TestNativeClientScale test;
    return QTest::qExec(&test, argc, argv);
}

#include "test_nativeclientscale.moc"
