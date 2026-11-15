#include <QGuiApplication>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QTest>
#include <QWaylandIdleInhibitManagerV1>
#include <QWaylandQuickCompositor>
#include <QWaylandQuickItem>
#include <QWaylandQuickOutput>
#include <QWaylandSurface>

#include <cstring>
#include <sys/mman.h>
#include <unistd.h>

#include "idle-inhibit-unstable-v1-client.h"
#include "src/wayland/idleinhibit.h"
#include "waylandtestclient.h"

namespace {

    // A video player: a mapped window that asks the screen to stay on.
    struct Client {
        wl_display                  *display    = nullptr;
        wl_compositor               *compositor = nullptr;
        wl_shm                      *shm        = nullptr;
        zwp_idle_inhibit_manager_v1 *inhibits   = nullptr;

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
                    else if (std::strcmp(interface, wl_shm_interface.name) == 0)
                        self->shm = static_cast<wl_shm *>(
                            wl_registry_bind(registry, name, &wl_shm_interface, 1));
                    else if (std::strcmp(interface, zwp_idle_inhibit_manager_v1_interface.name) ==
                             0)
                        self->inhibits =
                            static_cast<zwp_idle_inhibit_manager_v1 *>(wl_registry_bind(
                                registry, name, &zwp_idle_inhibit_manager_v1_interface, 1));
                },
                [](void *, wl_registry *, uint32_t) {},
            };
            wl_registry_add_listener(wl_display_get_registry(display), &listener, this);
            return roundtrip(display) && compositor && shm && inhibits;
        }

        void mapInhibiting() const {
            constexpr int size = 4 * 4 * 4;
            const int     fd   = memfd_create("idle-inhibit-test", MFD_CLOEXEC);
            QVERIFY(fd >= 0 && ftruncate(fd, size) == 0);
            wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
            wl_buffer   *buffer =
                wl_shm_pool_create_buffer(pool, 0, 4, 4, 16, WL_SHM_FORMAT_ARGB8888);
            wl_shm_pool_destroy(pool);
            ::close(fd);
            wl_surface *surface = wl_compositor_create_surface(compositor);
            zwp_idle_inhibit_manager_v1_create_inhibitor(inhibits, surface);
            wl_surface_attach(surface, buffer, 0, 0);
            wl_surface_commit(surface);
            QVERIFY(roundtrip(display));
        }

        ~Client() {
            if (display)
                wl_display_disconnect(display);
        }
    };

} // namespace

class TestIdleInhibit : public QObject {
    Q_OBJECT

    QTemporaryDir           runtime;
    QWaylandQuickCompositor compositor;
    QQuickWindow            window;
    QWaylandQuickItem      *item = nullptr;
    Client                  player;

  private slots:
    void initTestCase() {
        qputenv("XDG_RUNTIME_DIR", runtime.path().toLocal8Bit());
        const QByteArray socket = "marathon-test-idle-inhibit";
        compositor.setSocketName(socket);
        new QWaylandIdleInhibitManagerV1(&compositor);
        compositor.create();
        new QWaylandQuickOutput(&compositor, &window);
        window.resize(200, 200);
        window.show();

        item = new QWaylandQuickItem(window.contentItem());
        item->setSize(QSizeF(200, 200));
        connect(&compositor, &QWaylandCompositor::surfaceCreated, item,
                [this](QWaylandSurface *surface) { item->setSurface(surface); });

        QVERIFY(player.connect(socket));
        player.mapInhibiting();
        QTRY_VERIFY(item->surface() && item->surface()->hasContent());
        QTRY_VERIFY(item->surface()->inhibitsIdle());
    }

    void init() {
        item->setVisible(true);
        item->setOpacity(1);
        item->surface()->setProperty("appId", QVariant());
    }

    void namesTheShownInhibitor() {
        item->surface()->setProperty("appId", QStringLiteral("video"));
        QCOMPARE(IdleInhibit::shownInhibitor(compositor.surfaces()), QStringLiteral("video"));
    }

    void namesAnAppWithoutAnIdByItsPid() {
        QCOMPARE(IdleInhibit::shownInhibitor(compositor.surfaces()),
                 QStringLiteral("pid %1").arg(getpid()));
    }

    // An app in the background, or under the lock screen, keeps its window
    // mapped: its inhibitor must not keep the screen on.
    void ignoresAHiddenSurface() {
        item->setVisible(false);
        QCOMPARE(IdleInhibit::shownInhibitor(compositor.surfaces()), QString());
    }

    void ignoresATransparentSurface() {
        item->setOpacity(0);
        QCOMPARE(IdleInhibit::shownInhibitor(compositor.surfaces()), QString());
    }
};

QTEST_MAIN(TestIdleInhibit)
#include "test_idleinhibit.moc"
