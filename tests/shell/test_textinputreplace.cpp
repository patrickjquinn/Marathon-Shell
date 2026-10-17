#include <QGuiApplication>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QWaylandQuickCompositor>
#include <QWaylandQuickItem>
#include <QWaylandQuickOutput>
#include <QWaylandSurface>
#include <QWaylandTextInputManagerV3>
#include <QtTest>

#include <atomic>
#include <functional>
#include <cstring>
#include <mutex>
#include <thread>
#include <wayland-client.h>

#include "services/inputcontext.h"
#include "text-input-unstable-v3-client.h"

namespace {
    // A text-input-v3 client, as GTK is: it reports its text and cursor and
    // records what the input method asks it to do.
    struct Client {
        QByteArray                 surrounding;
        int                        cursor = 0;

        std::atomic<bool>          entered{false};
        std::atomic<bool>          stop{false};
        std::atomic<bool>          done{false};
        std::mutex                 mutex;
        QStringList                events;

        wl_compositor             *compositor = nullptr;
        wl_seat                   *seat       = nullptr;
        zwp_text_input_manager_v3 *manager    = nullptr;

        void                       record(const QString &event) {
            const std::lock_guard<std::mutex> lock(mutex);
            events << event;
        }

        QStringList recorded() {
            const std::lock_guard<std::mutex> lock(mutex);
            return events;
        }

        void run(const QByteArray &socket) {
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
                    else if (std::strcmp(interface, wl_seat_interface.name) == 0)
                        self->seat = static_cast<wl_seat *>(
                            wl_registry_bind(registry, name, &wl_seat_interface, 1));
                    else if (std::strcmp(interface, zwp_text_input_manager_v3_interface.name) == 0)
                        self->manager = static_cast<zwp_text_input_manager_v3 *>(wl_registry_bind(
                            registry, name, &zwp_text_input_manager_v3_interface, 1));
                },
                [](void *, wl_registry *, uint32_t) {},
            };
            wl_registry_add_listener(registry, &registryListener, this);
            wl_display_roundtrip(display);

            zwp_text_input_v3 *input = zwp_text_input_manager_v3_get_text_input(manager, seat);
            static const zwp_text_input_v3_listener inputListener = {
                [](void *data, zwp_text_input_v3 *, wl_surface *) {
                    static_cast<Client *>(data)->entered = true;
                },
                [](void *, zwp_text_input_v3 *, wl_surface *) {},
                [](void *data, zwp_text_input_v3 *, const char *text, int32_t, int32_t) {
                    if (text && *text)
                        static_cast<Client *>(data)->record(
                            QStringLiteral("preedit %1").arg(QString::fromUtf8(text)));
                },
                [](void *data, zwp_text_input_v3 *, const char *text) {
                    static_cast<Client *>(data)->record(
                        QStringLiteral("commit %1").arg(QString::fromUtf8(text)));
                },
                [](void *data, zwp_text_input_v3 *, uint32_t before, uint32_t after) {
                    static_cast<Client *>(data)->record(
                        QStringLiteral("delete %1 %2").arg(before).arg(after));
                },
                [](void *data, zwp_text_input_v3 *, uint32_t) {
                    static_cast<Client *>(data)->record(QStringLiteral("done"));
                },
            };
            zwp_text_input_v3_add_listener(input, &inputListener, this);
            wl_display_roundtrip(display);
            wl_surface *surface = wl_compositor_create_surface(compositor);
            wl_surface_commit(surface);

            bool enabled = false;
            while (!stop && wl_display_roundtrip(display) >= 0) {
                if (entered && !enabled) {
                    enabled = true;
                    zwp_text_input_v3_enable(input);
                    zwp_text_input_v3_set_surrounding_text(input, surrounding.constData(), cursor,
                                                           cursor);
                    zwp_text_input_v3_commit(input);
                }
            }
            wl_display_disconnect(display);
            done = true;
        }
    };
} // namespace

// The keyboard's edits leave the shell as text-input-v3 requests a client
// applies to its own text, with deletions counted in UTF-8 bytes.
class TestTextInputReplace : public QObject {
    Q_OBJECT

    QStringList edit(const QByteArray                          &surrounding,
                     const std::function<void(InputContext &)> &act) {
        QTemporaryDir runtime;
        qputenv("XDG_RUNTIME_DIR", runtime.path().toLocal8Bit());
        const QByteArray        socket = "marathon-test-text-input";

        QWaylandQuickCompositor compositor;
        compositor.setSocketName(socket);
        new QWaylandTextInputManagerV3(&compositor);
        compositor.create();
        QQuickWindow        window;
        QWaylandQuickOutput output(&compositor, &window);
        window.resize(200, 200);
        window.show();
        window.requestActivate();

        QWaylandQuickItem item(window.contentItem());
        connect(&compositor, &QWaylandCompositor::surfaceCreated, &item,
                [&item](QWaylandSurface *surface) {
                    item.setSurface(surface);
                    item.takeFocus();
                });

        Client client;
        client.surrounding = surrounding;
        client.cursor      = int(surrounding.size());
        std::thread thread([&client, &socket]() { client.run(socket); });

        [&]() {
            QTRY_VERIFY(client.entered);
            QTRY_COMPARE(QGuiApplication::focusObject(), &item);
            QTRY_COMPARE(QInputMethod::queryFocusObject(Qt::ImSurroundingText, {}).toString(),
                         QString::fromUtf8(surrounding));
        }();

        InputContext context;
        act(context);
        QTest::qWait(100);

        client.stop = true;
        if (!QTest::qWaitFor([&client]() { return client.done.load(); }, 5000))
            qFatal("the client did not stop");
        thread.join();
        return client.recorded();
    }

  private slots:
    void replacesTheWordBeforeTheCursor() {
        const QStringList events = edit("hello teh", [](InputContext &context) {
            QVERIFY(context.replaceTextBeforeCursor(QStringLiteral("teh"), QStringLiteral("the")));
        });
        QCOMPARE(events, (QStringList{"delete 3 0", "commit the", "done"}));
    }

    void countsDeletionInBytes() {
        const QStringList events = edit("a naïve", [](InputContext &context) {
            QVERIFY(
                context.replaceTextBeforeCursor(QStringLiteral("naïve"), QStringLiteral("naive")));
        });
        QCOMPARE(events, (QStringList{"delete 6 0", "commit naive", "done"}));
    }

    void turnsTheSecondSpaceIntoAPeriod() {
        const QStringList events = edit(
            "hello ", [](InputContext &context) { QVERIFY(context.insertDoubleSpacePeriod()); });
        QCOMPARE(events, (QStringList{"delete 1 0", "commit . ", "done"}));
    }

    void leavesTextItDidNotType() {
        const QStringList events = edit("hello tehs", [](InputContext &context) {
            QVERIFY(!context.replaceTextBeforeCursor(QStringLiteral("teh"), QStringLiteral("the")));
        });
        QCOMPARE(events, QStringList());
    }
};

QTEST_MAIN(TestTextInputReplace)
#include "test_textinputreplace.moc"
