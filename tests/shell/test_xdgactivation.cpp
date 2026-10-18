#include <QTest>
#include <QGuiApplication>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QWaylandCompositor>
#include <QWaylandSeat>
#include <QWaylandSurface>

#include <cstring>
#include <string>

#include "waylandtestclient.h"
#include "xdg-activation-v1-client.h"
#include "xdgactivationv1.h"

namespace {

    struct Client {
        wl_display        *display    = nullptr;
        wl_compositor     *compositor = nullptr;
        wl_seat           *seat       = nullptr;
        xdg_activation_v1 *activation = nullptr;
        wl_surface        *surface    = nullptr;

        bool               connect(const QByteArray &socket) {
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
                    else if (std::strcmp(interface, xdg_activation_v1_interface.name) == 0)
                        self->activation = static_cast<xdg_activation_v1 *>(
                            wl_registry_bind(registry, name, &xdg_activation_v1_interface, 1));
                },
                [](void *, wl_registry *, uint32_t) {},
            };
            wl_registry_add_listener(wl_display_get_registry(display), &listener, this);
            if (!roundtrip(display) || !compositor || !activation)
                return false;
            surface = wl_compositor_create_surface(compositor);
            return roundtrip(display);
        }

        std::string requestToken(uint32_t serial) const {
            std::string              token;
            xdg_activation_token_v1 *request = xdg_activation_v1_get_activation_token(activation);
            static const xdg_activation_token_v1_listener listener = {
                [](void *data, xdg_activation_token_v1 *, const char *done) {
                    *static_cast<std::string *>(data) = done;
                },
            };
            xdg_activation_token_v1_add_listener(request, &listener, &token);
            xdg_activation_token_v1_set_serial(request, serial, seat);
            xdg_activation_token_v1_set_surface(request, surface);
            xdg_activation_token_v1_commit(request);
            roundtrip(display);
            xdg_activation_token_v1_destroy(request);
            return token;
        }

        void activate(const std::string &token) const {
            xdg_activation_v1_activate(activation, token.c_str(), surface);
            roundtrip(display);
        }

        ~Client() {
            if (display)
                wl_display_disconnect(display);
        }
    };

    struct Fixture {
        QTemporaryDir      runtime;
        QWaylandCompositor compositor;
        XdgActivationV1   *activation = nullptr;
        QWaylandSurface   *surface    = nullptr;
        Client             client;

        bool               start(const QByteArray &socket) {
            qputenv("XDG_RUNTIME_DIR", runtime.path().toLocal8Bit());
            compositor.setSocketName(socket);
            compositor.create();
            activation = new XdgActivationV1(&compositor);
            QObject::connect(&compositor, &QWaylandCompositor::surfaceCreated, &compositor,
                             [this](QWaylandSurface *created) { surface = created; });
            return client.connect(socket) && surface;
        }

        // A serial the compositor has handed out since the latest user input.
        uint32_t freshSerial() const {
            return wl_display_next_serial(compositor.display());
        }
    };

} // namespace

class TestXdgActivation : public QObject {
    Q_OBJECT

  private slots:
    void serialAfter() {
        QVERIFY(XdgActivationV1::serialAfter(5, 3, 10));
        QVERIFY(XdgActivationV1::serialAfter(10, 3, 10));
        QVERIFY(!XdgActivationV1::serialAfter(3, 3, 10));
        QVERIFY(!XdgActivationV1::serialAfter(2, 3, 10));
        QVERIFY(!XdgActivationV1::serialAfter(11, 3, 10));
        QVERIFY(XdgActivationV1::serialAfter(2, 0xfffffff0u, 5));
        QVERIFY(!XdgActivationV1::serialAfter(0xffffffe0u, 0xfffffff0u, 5));
    }

    void launchTokenActivatesOnce() {
        Fixture fixture;
        QVERIFY(fixture.start("marathon-test-activation-launch"));
        QObject       launch;
        QSignalSpy    activated(fixture.activation, &XdgActivationV1::activated);

        const QString token = fixture.activation->issueToken(&launch);
        QCOMPARE(token.size(), 32);
        fixture.client.activate(token.toStdString());
        QCOMPARE(activated.size(), 1);
        QCOMPARE(activated.at(0).at(0).value<QWaylandSurface *>(), fixture.surface);
        QCOMPARE(activated.at(0).at(1).value<QObject *>(), &launch);

        fixture.client.activate(token.toStdString());
        QCOMPARE(activated.size(), 1);
    }

    void launchTokenOutlivesItsProcess() {
        Fixture fixture;
        QVERIFY(fixture.start("marathon-test-activation-gone"));
        QSignalSpy    activated(fixture.activation, &XdgActivationV1::activated);
        auto         *launch = new QObject;
        const QString token  = fixture.activation->issueToken(launch);
        delete launch;
        fixture.client.activate(token.toStdString());
        QCOMPARE(activated.size(), 1);
        QCOMPARE(activated.at(0).at(1).value<QObject *>(), nullptr);
    }

    void unknownTokenActivatesNothing() {
        Fixture fixture;
        QVERIFY(fixture.start("marathon-test-activation-unknown"));
        QSignalSpy activated(fixture.activation, &XdgActivationV1::activated);
        fixture.client.activate("0123456789abcdef0123456789abcdef");
        QCOMPARE(activated.size(), 0);
    }

    // The focused client's token, asked for with a serial from the latest
    // input, activates; without focus, or with an older serial, it does not.
    void clientTokenNeedsFocusAndRecentSerial() {
        Fixture fixture;
        QVERIFY(fixture.start("marathon-test-activation-client"));
        QSignalSpy activated(fixture.activation, &XdgActivationV1::activated);

        fixture.activation->noteUserInput();
        const uint32_t    serial = fixture.freshSerial();

        const std::string unfocused = fixture.client.requestToken(serial);
        QCOMPARE(unfocused.size(), size_t(32));
        fixture.client.activate(unfocused);
        QCOMPARE(activated.size(), 0);

        fixture.compositor.defaultSeat()->setKeyboardFocus(fixture.surface);
        fixture.client.activate(fixture.client.requestToken(serial));
        QCOMPARE(activated.size(), 1);
        QCOMPARE(activated.at(0).at(1).value<QObject *>(), nullptr);

        fixture.activation->noteUserInput();
        fixture.client.activate(fixture.client.requestToken(serial));
        QCOMPARE(activated.size(), 1);

        fixture.client.activate(fixture.client.requestToken(fixture.freshSerial()));
        QCOMPARE(activated.size(), 2);
    }

    void tokenWithoutSerialActivatesNothing() {
        Fixture fixture;
        QVERIFY(fixture.start("marathon-test-activation-noserial"));
        QSignalSpy activated(fixture.activation, &XdgActivationV1::activated);
        fixture.activation->noteUserInput();
        fixture.compositor.defaultSeat()->setKeyboardFocus(fixture.surface);

        std::string              token;
        xdg_activation_token_v1 *request =
            xdg_activation_v1_get_activation_token(fixture.client.activation);
        static const xdg_activation_token_v1_listener listener = {
            [](void *data, xdg_activation_token_v1 *, const char *done) {
                *static_cast<std::string *>(data) = done;
            },
        };
        xdg_activation_token_v1_add_listener(request, &listener, &token);
        xdg_activation_token_v1_commit(request);
        QVERIFY(roundtrip(fixture.client.display));
        xdg_activation_token_v1_destroy(request);
        fixture.client.activate(token);
        QCOMPARE(activated.size(), 0);
    }
};

int main(int argc, char **argv) {
    QGuiApplication   app(argc, argv);
    TestXdgActivation test;
    return QTest::qExec(&test, argc, argv);
}

#include "test_xdgactivation.moc"
