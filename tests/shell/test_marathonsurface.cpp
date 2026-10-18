#include <QTest>
#include <QGuiApplication>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QWaylandCompositor>
#include <QWaylandXdgShell>

#include <cerrno>
#include <cstring>
#include <vector>

#include "marathon-surface-v1-client.h"
#include "marathonsurfacev1.h"
#include "securitycontextv1.h"
#include "waylandtestclient.h"
#include "xdg-shell-client.h"

namespace {

    bool hasManagerGlobal(wl_display *display) {
        bool                              found    = false;
        static const wl_registry_listener listener = {
            [](void *data, wl_registry *, uint32_t, const char *interface, uint32_t) {
                if (std::strcmp(interface, marathon_surface_manager_v1_interface.name) == 0)
                    *static_cast<bool *>(data) = true;
            },
            [](void *, wl_registry *, uint32_t) {},
        };
        wl_registry *registry = wl_display_get_registry(display);
        wl_registry_add_listener(registry, &listener, &found);
        roundtrip(display);
        wl_registry_destroy(registry);
        return found;
    }

    // What the client was sent, in order.
    struct Events {
        QStringList log;
    };

    constexpr marathon_surface_v1_listener s_surfaceListener = {
        /* insets */
        [](void *data, marathon_surface_v1 *, int32_t top, int32_t bottom, int32_t left,
           int32_t right) {
            static_cast<Events *>(data)->log
                << QStringLiteral("insets %1 %2 %3 %4").arg(top).arg(bottom).arg(left).arg(right);
        },
        /* ime_inset */
        [](void *data, marathon_surface_v1 *, int32_t bottom) {
            static_cast<Events *>(data)->log << QStringLiteral("ime %1").arg(bottom);
        },
        /* back_started */
        [](void *data, marathon_surface_v1 *, uint32_t edge, wl_fixed_t x, wl_fixed_t y) {
            static_cast<Events *>(data)->log << QStringLiteral("started %1 %2 %3")
                                                    .arg(edge)
                                                    .arg(wl_fixed_to_double(x))
                                                    .arg(wl_fixed_to_double(y));
        },
        /* back_progress */
        [](void *data, marathon_surface_v1 *, wl_fixed_t progress, wl_fixed_t, wl_fixed_t) {
            static_cast<Events *>(data)->log
                << QStringLiteral("progress %1").arg(wl_fixed_to_double(progress));
        },
        /* back_committed */
        [](void *data, marathon_surface_v1 *) {
            static_cast<Events *>(data)->log << QStringLiteral("committed");
        },
        /* back_cancelled */
        [](void *data, marathon_surface_v1 *) {
            static_cast<Events *>(data)->log << QStringLiteral("cancelled");
        },
    };

    struct Client {
        wl_display                  *display    = nullptr;
        wl_compositor               *compositor = nullptr;
        xdg_wm_base                 *wmBase     = nullptr;
        marathon_surface_manager_v1 *manager    = nullptr;
        wl_surface                  *surface    = nullptr;
        xdg_surface                 *xdgSurface = nullptr;
        xdg_toplevel                *toplevel   = nullptr;
        marathon_surface_v1         *marathon   = nullptr;
        Events                       events;

        bool                         connect(const QByteArray &socket) {
            display = wl_display_connect(socket.constData());
            if (!display)
                return false;
            static const wl_registry_listener listener = {
                [](void *data, wl_registry *registry, uint32_t name, const char *interface,
                   uint32_t) {
                    auto *self = static_cast<Client *>(data);
                    if (std::strcmp(interface, wl_compositor_interface.name) == 0)
                        self->compositor = static_cast<wl_compositor *>(
                            wl_registry_bind(registry, name, &wl_compositor_interface, 4));
                    else if (std::strcmp(interface, xdg_wm_base_interface.name) == 0)
                        self->wmBase = static_cast<xdg_wm_base *>(
                            wl_registry_bind(registry, name, &xdg_wm_base_interface, 1));
                    else if (std::strcmp(interface, marathon_surface_manager_v1_interface.name) ==
                             0)
                        self->manager = static_cast<marathon_surface_manager_v1 *>(wl_registry_bind(
                            registry, name, &marathon_surface_manager_v1_interface, 1));
                },
                [](void *, wl_registry *, uint32_t) {},
            };
            wl_registry_add_listener(wl_display_get_registry(display), &listener, this);
            if (!roundtrip(display) || !compositor || !wmBase || !manager)
                return false;
            surface    = wl_compositor_create_surface(compositor);
            xdgSurface = xdg_wm_base_get_xdg_surface(wmBase, surface);
            toplevel   = xdg_surface_get_toplevel(xdgSurface);
            marathon   = marathon_surface_manager_v1_get_surface(manager, toplevel, 7);
            marathon_surface_v1_add_listener(marathon, &s_surfaceListener, &events);
            wl_surface_commit(surface);
            return roundtrip(display);
        }

        uint32_t protocolError() const {
            const wl_interface *interface = nullptr;
            uint32_t            id        = 0;
            if (wl_display_get_error(display) != EPROTO)
                return UINT32_MAX;
            return wl_display_get_protocol_error(display, &interface, &id);
        }

        ~Client() {
            if (display)
                wl_display_disconnect(display);
        }
    };

    struct Fixture {
        QTemporaryDir             runtime;
        QWaylandCompositor        compositor;
        SecurityContextManagerV1 *contexts = nullptr;
        MarathonSurfaceManagerV1 *manager  = nullptr;
        Client                    client;

        bool                      start(const QByteArray &socket) {
            qputenv("XDG_RUNTIME_DIR", runtime.path().toLocal8Bit());
            compositor.setSocketName(socket);
            compositor.create();
            new QWaylandXdgShell(&compositor);
            contexts = new SecurityContextManagerV1(&compositor);
            manager  = new MarathonSurfaceManagerV1(&compositor, contexts);
            wl_display_set_global_filter(compositor.display(), &Fixture::filter, this);
            return client.connect(socket);
        }

        ~Fixture() {
            wl_display_set_global_filter(compositor.display(), nullptr, nullptr);
        }

        // WaylandCompositor::filterGlobal's chain, for the globals made here.
        static bool filter(const wl_client *peer, const wl_global *global, void *data) {
            const auto *self = static_cast<const Fixture *>(data);
            return self->contexts->allowsGlobal(peer, global) &&
                self->manager->allowsGlobal(peer, global);
        }

        // A client of a sandbox the shell opened for engine.
        wl_display *connectSandboxed(const char *name, const char *engine) const {
            const QString path = runtime.filePath(QString::fromLatin1(name));
            if (!contexts->listen(path, {QString::fromLatin1(engine), "org.example.test", name}))
                return nullptr;
            return wl_display_connect(path.toLocal8Bit().constData());
        }

        MarathonSurfaceV1 *surface() const {
            const QList<MarathonSurfaceV1 *> all = manager->surfaces();
            return all.size() == 1 ? all.first() : nullptr;
        }
    };

} // namespace

class TestMarathonSurface : public QObject {
    Q_OBJECT

  private slots:
    void bindPolicy() {
        QVERIFY(MarathonSurfaceManagerV1::mayBind(false, QString()));
        QVERIFY(MarathonSurfaceManagerV1::mayBind(
            true, QString::fromLatin1(MarathonSurfaceManagerV1::kTrustedEngine)));
        QVERIFY(!MarathonSurfaceManagerV1::mayBind(true, QStringLiteral("org.flatpak")));
        QVERIFY(!MarathonSurfaceManagerV1::mayBind(true, QString()));
    }

    void globalFollowsTheSandboxEngine() {
        Fixture fixture;
        QVERIFY(fixture.start("marathon-test-msf-global"));
        QVERIFY(hasManagerGlobal(fixture.client.display));

        wl_display *flatpak = fixture.connectSandboxed("flatpak", "org.flatpak");
        QVERIFY(flatpak);
        QVERIFY(!hasManagerGlobal(flatpak));
        wl_display_disconnect(flatpak);

        wl_display *app = fixture.connectSandboxed("app", MarathonSurfaceManagerV1::kTrustedEngine);
        QVERIFY(app);
        QVERIFY(hasManagerGlobal(app));
        wl_display_disconnect(app);
    }

    void flagsAndSystemBars() {
        Fixture fixture;
        QVERIFY(fixture.start("marathon-test-msf-flags"));
        MarathonSurfaceV1 *surface = fixture.surface();
        QVERIFY(surface);
        QCOMPARE(surface->taskId(), 7u);
        QVERIFY(surface->focusable());
        QVERIFY(surface->touchable());
        QVERIFY(!surface->secure());

        QSignalSpy flags(surface, &MarathonSurfaceV1::flagsChanged);
        marathon_surface_v1_set_window_flags(fixture.client.marathon,
                                             MARATHON_SURFACE_V1_WINDOW_FLAGS_SECURE |
                                                 MARATHON_SURFACE_V1_WINDOW_FLAGS_NOT_FOCUSABLE);
        QVERIFY(roundtrip(fixture.client.display));
        QCOMPARE(flags.size(), 1);
        QVERIFY(!surface->focusable());
        QVERIFY(surface->touchable());
        QVERIFY(surface->secure());

        marathon_surface_v1_set_system_bars(fixture.client.marathon,
                                            MARATHON_SURFACE_V1_SYSTEM_BARS_HIDDEN);
        QVERIFY(roundtrip(fixture.client.display));
        QVERIFY(surface->systemBarsHidden());
    }

    void unknownFlagsAreAnError() {
        Fixture fixture;
        QVERIFY(fixture.start("marathon-test-msf-badflags"));
        marathon_surface_v1_set_window_flags(fixture.client.marathon, 8);
        roundtrip(fixture.client.display);
        QCOMPARE(fixture.client.protocolError(), uint32_t(MARATHON_SURFACE_V1_ERROR_INVALID_FLAGS));
    }

    void secondSurfaceForAToplevelIsAnError() {
        Fixture fixture;
        QVERIFY(fixture.start("marathon-test-msf-twice"));
        marathon_surface_manager_v1_get_surface(fixture.client.manager, fixture.client.toplevel, 0);
        roundtrip(fixture.client.display);
        QCOMPARE(fixture.client.protocolError(),
                 uint32_t(MARATHON_SURFACE_MANAGER_V1_ERROR_ALREADY_EXISTS));
    }

    void gestureExclusionAppliesOnCommit() {
        Fixture fixture;
        QVERIFY(fixture.start("marathon-test-msf-exclusion"));
        MarathonSurfaceV1 *surface = fixture.surface();
        QVERIFY(surface);

        std::vector<int32_t> values{0, 100, 40, 200, 300, 0, 20, 20};
        wl_array             rects{values.size() * sizeof(int32_t), values.size() * sizeof(int32_t),
                                   values.data()};
        marathon_surface_v1_set_gesture_exclusion(fixture.client.marathon, &rects);
        QVERIFY(roundtrip(fixture.client.display));
        QVERIFY(surface->gestureExclusion().isEmpty());

        wl_surface_commit(fixture.client.surface);
        QVERIFY(roundtrip(fixture.client.display));
        QCOMPARE(surface->gestureExclusion(),
                 QVariantList({QRect(0, 100, 40, 200), QRect(300, 0, 20, 20)}));
    }

    void partialRectangleIsAnError() {
        Fixture fixture;
        QVERIFY(fixture.start("marathon-test-msf-badrects"));
        int32_t  values[3] = {0, 0, 10};
        wl_array rects{sizeof(values), sizeof(values), values};
        marathon_surface_v1_set_gesture_exclusion(fixture.client.marathon, &rects);
        roundtrip(fixture.client.display);
        QCOMPARE(fixture.client.protocolError(), uint32_t(MARATHON_SURFACE_V1_ERROR_INVALID_RECTS));
    }

    void insetsAreSentWhenTheyChange() {
        Fixture fixture;
        QVERIFY(fixture.start("marathon-test-msf-insets"));
        MarathonSurfaceV1 *surface = fixture.surface();
        QVERIFY(surface);
        Events &events = fixture.client.events;

        QVERIFY(surface->sendInsets(QMargins(), 0));
        QVERIFY(roundtrip(fixture.client.display));
        QCOMPARE(events.log, QStringList({"insets 0 0 0 0", "ime 0"}));

        events.log.clear();
        QVERIFY(!surface->sendInsets(QMargins(), 0));
        QVERIFY(surface->sendInsets(QMargins(), 310));
        QVERIFY(roundtrip(fixture.client.display));
        QCOMPARE(events.log, QStringList({"ime 310"}));

        events.log.clear();
        QVERIFY(surface->sendInsets(QMargins(1, 2, 3, 4), 310));
        QVERIFY(roundtrip(fixture.client.display));
        QCOMPARE(events.log, QStringList({"insets 2 4 1 3"}));
    }

    void backGestureSequence() {
        Fixture fixture;
        QVERIFY(fixture.start("marathon-test-msf-back"));
        MarathonSurfaceV1 *surface = fixture.surface();
        QVERIFY(surface);
        Events &events = fixture.client.events;

        surface->cancelBack();
        surface->sendBackProgress(MARATHON_SURFACE_V1_BACK_EDGE_RIGHT, 0.25, QPointF(100, 900));
        surface->sendBackProgress(MARATHON_SURFACE_V1_BACK_EDGE_RIGHT, 0.5, QPointF(80, 900));
        surface->sendBackCommitted();
        QVERIFY(roundtrip(fixture.client.display));
        QCOMPARE(events.log,
                 QStringList({"started 2 100 900", "progress 0.25", "progress 0.5", "committed"}));

        events.log.clear();
        surface->sendBackProgress(MARATHON_SURFACE_V1_BACK_EDGE_RIGHT, 0.5, QPointF(80, 900));
        surface->cancelBack();
        surface->cancelBack();
        surface->sendBackCommitted();
        QVERIFY(roundtrip(fixture.client.display));
        QCOMPARE(events.log,
                 QStringList({"started 2 80 900", "progress 0.5", "cancelled", "committed"}));
    }

    // A surface whose toplevel is gone is inert: no events, requests ignored.
    void toplevelDestroyedFirst() {
        Fixture fixture;
        QVERIFY(fixture.start("marathon-test-msf-inert"));
        MarathonSurfaceV1 *surface = fixture.surface();
        QVERIFY(surface);
        QSignalSpy removed(fixture.manager, &MarathonSurfaceManagerV1::surfaceRemoved);

        xdg_toplevel_destroy(fixture.client.toplevel);
        QVERIFY(roundtrip(fixture.client.display));
        QCOMPARE(removed.size(), 1);
        QVERIFY(fixture.manager->surfaces().isEmpty());

        QVERIFY(!surface->sendInsets(QMargins(), 5));
        surface->sendBackProgress(MARATHON_SURFACE_V1_BACK_EDGE_RIGHT, 0.5, QPointF());
        marathon_surface_v1_set_window_flags(fixture.client.marathon,
                                             MARATHON_SURFACE_V1_WINDOW_FLAGS_SECURE);
        QVERIFY(roundtrip(fixture.client.display));
        QVERIFY(!surface->secure());
        QVERIFY(fixture.client.events.log.isEmpty());

        marathon_surface_v1_destroy(fixture.client.marathon);
        QVERIFY(roundtrip(fixture.client.display));
        QCOMPARE(removed.size(), 1);
        QCOMPARE(fixture.client.protocolError(), UINT32_MAX);
    }

    void destroyingTheObjectRemovesIt() {
        Fixture fixture;
        QVERIFY(fixture.start("marathon-test-msf-destroy"));
        QPointer<MarathonSurfaceV1> surface = fixture.surface();
        QVERIFY(surface);
        QSignalSpy removed(fixture.manager, &MarathonSurfaceManagerV1::surfaceRemoved);
        marathon_surface_v1_destroy(fixture.client.marathon);
        QVERIFY(roundtrip(fixture.client.display));
        QCOMPARE(removed.size(), 1);
        QTRY_VERIFY(!surface);
    }
};

int main(int argc, char **argv) {
    QGuiApplication     app(argc, argv);
    TestMarathonSurface test;
    return QTest::qExec(&test, argc, argv);
}

#include "test_marathonsurface.moc"
