#include <QTest>
#include <QGuiApplication>
#include <QTemporaryDir>
#include <QWaylandCompositor>
#include <QWaylandSeat>
#include <QWaylandSurface>

#include <cstring>
#include <unistd.h>

#include "foreignfocus.h"
#include "waylandtestclient.h"

namespace {

    // Waydroid's one client: a window per Android task, and a keyboard whose
    // enter is what moves Android's front task.
    struct Client {
        wl_display         *display    = nullptr;
        wl_compositor      *compositor = nullptr;
        wl_seat            *seat       = nullptr;
        QList<wl_surface *> entered;
        int                 left = 0;

        bool                connect(const QByteArray &socket) {
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
                    else if (std::strcmp(interface, wl_seat_interface.name) == 0)
                        self->seat = static_cast<wl_seat *>(
                            wl_registry_bind(registry, name, &wl_seat_interface, 1));
                },
                [](void *, wl_registry *, uint32_t) {},
            };
            wl_registry_add_listener(wl_display_get_registry(display), &listener, this);
            if (!roundtrip(display) || !compositor || !seat)
                return false;
            static const wl_keyboard_listener keyboard = {
                [](void *, wl_keyboard *, uint32_t, int fd, uint32_t) { ::close(fd); },
                [](void *data, wl_keyboard *, uint32_t, wl_surface *surface, wl_array *) {
                    static_cast<Client *>(data)->entered << surface;
                },
                [](void *data, wl_keyboard *, uint32_t, wl_surface *) {
                    ++static_cast<Client *>(data)->left;
                },
                [](void *, wl_keyboard *, uint32_t, uint32_t, uint32_t, uint32_t) {},
                [](void *, wl_keyboard *, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t) {},
                [](void *, wl_keyboard *, int32_t, int32_t) {},
            };
            wl_keyboard_add_listener(wl_seat_get_keyboard(seat), &keyboard, this);
            return roundtrip(display);
        }

        wl_surface *createSurface() const {
            wl_surface *surface = wl_compositor_create_surface(compositor);
            roundtrip(display);
            return surface;
        }

        ~Client() {
            if (display)
                wl_display_disconnect(display);
        }
    };

    struct Fixture {
        QTemporaryDir            runtime;
        QWaylandCompositor       compositor;
        QList<QWaylandSurface *> surfaces;
        Client                   waydroid;
        Client                   other;

        bool                     start(const QByteArray &socket) {
            qputenv("XDG_RUNTIME_DIR", runtime.path().toLocal8Bit());
            compositor.setSocketName(socket);
            compositor.create();
            QObject::connect(&compositor, &QWaylandCompositor::surfaceCreated, &compositor,
                             [this](QWaylandSurface *created) { surfaces << created; });
            return waydroid.connect(socket) && other.connect(socket);
        }

        // A window filed for an app, as the shell files Waydroid's.
        QWaylandSurface *window(Client &client, const char *appId, bool foreign = true) {
            client.createSurface();
            QWaylandSurface *surface = surfaces.isEmpty() ? nullptr : surfaces.last();
            if (surface) {
                surface->setProperty("appId", QString::fromLatin1(appId));
                surface->setProperty("foreignClient", foreign);
            }
            return surface;
        }

        void focus(QWaylandSurface *surface) {
            compositor.defaultSeat()->setKeyboardFocus(surface);
            roundtrip(waydroid.display);
            waydroid.entered.clear();
            waydroid.left = 0;
        }
    };

} // namespace

// Android hands each touch to its own front task, and moves that task only
// on wl_keyboard.enter: another app's window mapping behind the one in front
// (a task Android raised itself) gets the front window entered again.
class TestForeignFocus : public QObject {
    Q_OBJECT

  private slots:
    void anotherAppMappedBehindReentersTheFront() {
        Fixture fixture;
        QVERIFY(fixture.start("marathon-test-foreign-focus-1"));
        QWaylandSurface *files =
            fixture.window(fixture.waydroid, "waydroid.com.android.documentsui");
        QWaylandSurface *settings =
            fixture.window(fixture.waydroid, "waydroid.com.android.settings");
        QVERIFY(files && settings);
        fixture.focus(files);
        QVERIFY(ForeignFocus::keepFront(fixture.compositor.defaultSeat(), settings));
        roundtrip(fixture.waydroid.display);
        QCOMPARE(fixture.waydroid.left, 1);
        QCOMPARE(fixture.waydroid.entered.size(), 1);
        QCOMPARE(fixture.compositor.defaultSeat()->keyboardFocus(), files);
    }

    // Android redraws the front task in a new window: the same app, no enter.
    void theFrontAppsOwnWindowChangesNothing() {
        Fixture fixture;
        QVERIFY(fixture.start("marathon-test-foreign-focus-2"));
        QWaylandSurface *files =
            fixture.window(fixture.waydroid, "waydroid.com.android.documentsui");
        QWaylandSurface *redraw =
            fixture.window(fixture.waydroid, "waydroid.com.android.documentsui");
        fixture.focus(files);
        QVERIFY(!ForeignFocus::keepFront(fixture.compositor.defaultSeat(), redraw));
        roundtrip(fixture.waydroid.display);
        QCOMPARE(fixture.waydroid.left, 0);
        QVERIFY(fixture.waydroid.entered.isEmpty());
    }

    // Only Waydroid's windows share a client's input; another client's
    // window, or a shell-launched app's, leaves the focus alone.
    void otherClientsAndNativeAppsChangeNothing() {
        Fixture fixture;
        QVERIFY(fixture.start("marathon-test-foreign-focus-3"));
        QWaylandSurface *files =
            fixture.window(fixture.waydroid, "waydroid.com.android.documentsui");
        QWaylandSurface *elsewhere = fixture.window(fixture.other, "org.example.other");
        fixture.focus(files);
        QVERIFY(!ForeignFocus::keepFront(fixture.compositor.defaultSeat(), elsewhere));

        QWaylandSurface *notes  = fixture.window(fixture.other, "notes", false);
        QWaylandSurface *dialog = fixture.window(fixture.other, "notes-dialog", false);
        fixture.focus(notes);
        QVERIFY(!ForeignFocus::keepFront(fixture.compositor.defaultSeat(), dialog));
    }

    void nothingInFrontChangesNothing() {
        Fixture fixture;
        QVERIFY(fixture.start("marathon-test-foreign-focus-4"));
        QWaylandSurface *settings =
            fixture.window(fixture.waydroid, "waydroid.com.android.settings");
        QVERIFY(!ForeignFocus::keepFront(fixture.compositor.defaultSeat(), settings));
    }
};

QTEST_MAIN(TestForeignFocus)
#include "test_foreignfocus.moc"
