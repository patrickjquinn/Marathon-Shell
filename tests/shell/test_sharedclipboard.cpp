#include <QClipboard>
#include <QGuiApplication>
#include <QMimeData>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QSocketNotifier>
#include <QTemporaryDir>
#include <QTimer>
#include <QWaylandQuickCompositor>
#include <QWaylandQuickItem>
#include <QWaylandQuickOutput>
#include <QWaylandSeat>
#include <QWaylandXdgShell>
#include <QTest>

#include <algorithm>
#include <csignal>
#include <cstring>
#include <poll.h>
#include <string>
#include <unistd.h>
#include <vector>
#include <wayland-client.h>
#include <wayland-server-protocol.h>
#include <wayland-server-core.h>

#include "src/wayland/sharedclipboard.h"

namespace {
    class Compositor : public QWaylandQuickCompositor {
      public:
        SharedClipboard *clipboard = nullptr;

      protected:
        void retainedSelectionReceived(QMimeData *data) override {
            clipboard->take(data);
        }
    };

    // One Qt app: copies and pastes on command, and prints what it pasted.
    struct App {
        QProcess           process;
        QString            printed;
        QWaylandQuickItem *item = nullptr;

        QString            pasted() const {
            const qsizetype start = printed.lastIndexOf(QLatin1String("PASTED["));
            if (start < 0)
                return {};
            const qsizetype end = printed.indexOf(QLatin1String("]END"), start);
            return end < 0 ? QString() : printed.mid(start + 7, end - start - 7);
        }

        void send(const QString &command) {
            process.write((command + u'\n').toUtf8());
        }
    };
} // namespace

// --android: Deckard's Android side as its hwcomposer reaches the clipboard
// (android_hardware_waydroid's WaydroidClipboard.cpp): it reads every
// selection it is offered at once, with a roundtrip and then a blocking read,
// and sets its own with a source offering text. It prints what it read as
// "CLIP[<size>:<text up to 40 bytes>]" and takes "COPY <text>" on stdin.
namespace android {
    const char *const kMimeTypes[] = {"text/plain;charset=utf-8", "UTF8_STRING", "text/plain",
                                      "TEXT", "STRING"};

    struct Client {
        wl_display              *display    = nullptr;
        wl_compositor           *compositor = nullptr;
        wl_seat                 *seat       = nullptr;
        wl_data_device_manager  *manager    = nullptr;
        wl_data_device          *device     = nullptr;
        std::vector<std::string> offered;
    };

    void sourceSend(void *data, wl_data_source *, const char *, int fd) {
        const auto *text = static_cast<const std::string *>(data);
        for (size_t done = 0; done < text->size();) {
            const ssize_t n = write(fd, text->data() + done, text->size() - done);
            if (n <= 0)
                break;
            done += size_t(n);
        }
        close(fd);
    }

    void sourceCancelled(void *data, wl_data_source *source) {
        delete static_cast<std::string *>(data);
        wl_data_source_destroy(source);
    }

    void                          sourceTarget(void *, wl_data_source *, const char *) {}
    void                          sourceDropPerformed(void *, wl_data_source *) {}
    void                          sourceFinished(void *, wl_data_source *) {}
    void                          sourceAction(void *, wl_data_source *, uint32_t) {}

    const wl_data_source_listener kSourceListener = {sourceTarget,    sourceSend,
                                                     sourceCancelled, sourceDropPerformed,
                                                     sourceFinished,  sourceAction};

    void                          offerOffer(void *data, wl_data_offer *, const char *mimeType) {
        static_cast<Client *>(data)->offered.emplace_back(mimeType);
    }
    void                         offerSourceActions(void *, wl_data_offer *, uint32_t) {}
    void                         offerAction(void *, wl_data_offer *, uint32_t) {}

    const wl_data_offer_listener kOfferListener = {offerOffer, offerSourceActions, offerAction};

    void deviceDataOffer(void *data, wl_data_device *, wl_data_offer *offer) {
        static_cast<Client *>(data)->offered.clear();
        wl_data_offer_add_listener(offer, &kOfferListener, data);
    }

    void deviceSelection(void *data, wl_data_device *, wl_data_offer *offer) {
        auto *client = static_cast<Client *>(data);
        if (!offer)
            return;
        const auto mime = std::find_first_of(std::begin(kMimeTypes), std::end(kMimeTypes),
                                             client->offered.begin(), client->offered.end());
        if (mime == std::end(kMimeTypes)) {
            wl_data_offer_destroy(offer);
            return;
        }
        int fds[2];
        if (pipe(fds) != 0)
            return;
        wl_data_offer_receive(offer, *mime, fds[1]);
        close(fds[1]);
        wl_display_roundtrip(client->display);
        std::string text;
        char        buf[4096];
        for (ssize_t n; (n = read(fds[0], buf, sizeof(buf))) > 0;)
            text.append(buf, size_t(n));
        close(fds[0]);
        wl_data_offer_destroy(offer);
        std::printf("CLIP[%zu:%s]\n", text.size(), text.substr(0, 40).c_str());
        std::fflush(stdout);
    }

    void deviceEnter(void *, wl_data_device *, uint32_t, wl_surface *, wl_fixed_t, wl_fixed_t,
                     wl_data_offer *) {}
    void deviceLeave(void *, wl_data_device *) {}
    void deviceMotion(void *, wl_data_device *, uint32_t, wl_fixed_t, wl_fixed_t) {}
    void deviceDrop(void *, wl_data_device *) {}

    const wl_data_device_listener kDeviceListener = {deviceDataOffer, deviceEnter, deviceLeave,
                                                     deviceMotion,    deviceDrop,  deviceSelection};

    void global(void *data, wl_registry *registry, uint32_t name, const char *interface, uint32_t) {
        auto *client = static_cast<Client *>(data);
        if (std::strcmp(interface, wl_compositor_interface.name) == 0)
            client->compositor = static_cast<wl_compositor *>(
                wl_registry_bind(registry, name, &wl_compositor_interface, 1));
        else if (std::strcmp(interface, wl_seat_interface.name) == 0)
            client->seat =
                static_cast<wl_seat *>(wl_registry_bind(registry, name, &wl_seat_interface, 1));
        else if (std::strcmp(interface, wl_data_device_manager_interface.name) == 0)
            client->manager = static_cast<wl_data_device_manager *>(
                wl_registry_bind(registry, name, &wl_data_device_manager_interface, 1));
    }
    void                       globalRemove(void *, wl_registry *, uint32_t) {}

    const wl_registry_listener kRegistryListener = {global, globalRemove};

    int                        run() {
        Client client;
        client.display = wl_display_connect(nullptr);
        if (!client.display)
            return 1;
        wl_registry *registry = wl_display_get_registry(client.display);
        wl_registry_add_listener(registry, &kRegistryListener, &client);
        wl_display_roundtrip(client.display);
        client.device = wl_data_device_manager_get_data_device(client.manager, client.seat);
        wl_data_device_add_listener(client.device, &kDeviceListener, &client);
        wl_surface_commit(wl_compositor_create_surface(client.compositor));
        wl_display_roundtrip(client.display);
        std::printf("SHOWN\n");
        std::fflush(stdout);

        std::string input;
        while (true) {
            wl_display_flush(client.display);
            pollfd fds[2] = {{wl_display_get_fd(client.display), POLLIN, 0},
                             {STDIN_FILENO, POLLIN, 0}};
            if (poll(fds, 2, -1) < 0)
                return 1;
            if ((fds[0].revents & POLLIN) && wl_display_dispatch(client.display) < 0)
                return 1;
            if (!(fds[1].revents & POLLIN))
                continue;
            char       buf[4096];
            const auto n = read(STDIN_FILENO, buf, sizeof(buf));
            if (n <= 0)
                return 0;
            input.append(buf, size_t(n));
            for (size_t end; (end = input.find('\n')) != std::string::npos;) {
                const std::string line = input.substr(0, end);
                input.erase(0, end + 1);
                if (line.rfind("COPY ", 0) != 0)
                    continue;
                wl_data_source *source = wl_data_device_manager_create_data_source(client.manager);
                wl_data_source_add_listener(source, &kSourceListener,
                                            new std::string(line.substr(5)));
                for (const char *mime : kMimeTypes)
                    wl_data_source_offer(source, mime);
                wl_data_device_set_selection(client.device, source, 0);
            }
        }
    }
} // namespace android

// Copy and paste between apps and the shell, through the shell's compositor:
// an app pastes what another copied even after that app stops answering, and
// the shell's own copies replace an app's.
class TestSharedClipboard : public QObject {
    Q_OBJECT

    QTemporaryDir     m_runtime;
    Compositor       *m_compositor = nullptr;
    QQuickWindow     *m_window     = nullptr;
    QWaylandXdgShell *m_xdgShell   = nullptr;
    App               m_first;
    App               m_second;
    App               m_android;
    QTimer            m_flush;

    QString           androidClip() const {
        const qsizetype start = m_android.printed.lastIndexOf(QLatin1String("CLIP["));
        if (start < 0)
            return {};
        const qsizetype end = m_android.printed.indexOf(u']', start);
        return end < 0 ? QString() : m_android.printed.mid(start + 5, end - start - 5);
    }

    // The app has given up its own copy, as the shell cancelled it. It does
    // so at once; only an app frozen within those milliseconds would not.
    bool holdsSource(App &app) const {
        wl_client *client = nullptr;
        bool       holds  = false;
        wl_client_for_each(client, wl_display_get_client_list(m_compositor->display())) {
            pid_t pid = 0;
            wl_client_get_credentials(client, &pid, nullptr, nullptr);
            if (pid != pid_t(app.process.processId()))
                continue;
            wl_client_for_each_resource(
                client,
                [](wl_resource *resource, void *data) {
                    if (std::strcmp(wl_resource_get_class(resource),
                                    wl_data_source_interface.name) != 0)
                        return WL_ITERATOR_CONTINUE;
                    *static_cast<bool *>(data) = true;
                    return WL_ITERATOR_STOP;
                },
                &holds);
        }
        return holds;
    }

    // Android reads what it is offered by itself; this waits for that.
    bool androidHolds(const QString &clip) {
        return QTest::qWaitFor([this, &clip]() { return androidClip() == clip; });
    }

    void start(App &app, qreal y) {
        app.item = new QWaylandQuickItem(m_window->contentItem());
        app.item->setY(y);
        app.item->setSize(QSizeF(400, 200));
        auto connection = std::make_shared<QMetaObject::Connection>();
        *connection =
            connect(m_xdgShell, &QWaylandXdgShell::toplevelCreated, app.item,
                    [&app, connection](QWaylandXdgToplevel *toplevel, QWaylandXdgSurface *surface) {
                        disconnect(*connection);
                        app.item->setSurface(surface->surface());
                        toplevel->sendMaximized(QSize(400, 200));
                    });
        connect(&app.process, &QProcess::readyRead, this,
                [&app]() { app.printed += QString::fromUtf8(app.process.readAll()); });
        app.process.setProcessChannelMode(QProcess::MergedChannels);
        app.process.start(QCoreApplication::applicationFilePath(), {QStringLiteral("--app")});
        QTRY_VERIFY(app.item->surface());
        QTRY_VERIFY2(app.printed.contains(QLatin1String("SHOWN")), qPrintable(app.printed));
    }

    void focus(App &app) {
        app.item->takeFocus();
        QTRY_COMPARE(m_compositor->defaultSeat()->keyboardFocus(), app.item->surface());
    }

    // An app takes the clipboard's events in its own time, so it pastes until
    // the text arrives; what it pasted last is in app.pasted().
    bool pastes(App &app, const QString &expected) {
        app.printed.clear();
        app.send(QStringLiteral("PASTE"));
        return QTest::qWaitFor([&app, &expected]() {
            if (!app.printed.contains(QLatin1String("]END")))
                return false;
            if (app.pasted() == expected)
                return true;
            app.printed.clear();
            app.send(QStringLiteral("PASTE"));
            return false;
        });
    }

  private slots:
    void initTestCase() {
        qputenv("XDG_RUNTIME_DIR", m_runtime.path().toLocal8Bit());
        const QByteArray socket = "marathon-test-clipboard";
        m_compositor            = new Compositor;
        m_compositor->setParent(this);
        m_compositor->setSocketName(socket);
        m_xdgShell = new QWaylandXdgShell(m_compositor);
        m_compositor->create();
        m_compositor->clipboard = new SharedClipboard(m_compositor);
        // The shell's event loop sends what it queued for clients whenever it
        // idles; a test's waits never idle.
        connect(&m_flush, &QTimer::timeout, m_compositor,
                [this]() { wl_display_flush_clients(m_compositor->display()); });
        m_flush.start(5);
        m_window = new QQuickWindow;
        new QWaylandQuickOutput(m_compositor, m_window);
        m_window->resize(400, 400);
        m_window->show();

        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert("WAYLAND_DISPLAY", QString::fromLatin1(socket));
        env.insert("QT_QPA_PLATFORM", "wayland");
        env.insert("QT_WAYLAND_SHELL_INTEGRATION", "xdg-shell");
        env.insert("QT_QUICK_BACKEND", "software");
        env.insert("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1");
        env.insert("QT_FORCE_STDERR_LOGGING", "1");
        m_first.process.setProcessEnvironment(env);
        m_second.process.setProcessEnvironment(env);
        start(m_first, 0);
        start(m_second, 200);

        m_android.item = new QWaylandQuickItem(m_window->contentItem());
        m_android.item->setY(400);
        m_android.item->setSize(QSizeF(400, 200));
        connect(m_compositor, &QWaylandCompositor::surfaceCreated, this,
                [this](QWaylandSurface *surface) {
                    if (surface->client()->processId() == qint64(m_android.process.processId()))
                        m_android.item->setSurface(surface);
                });
        connect(&m_android.process, &QProcess::readyRead, this,
                [this]() { m_android.printed += QString::fromUtf8(m_android.process.readAll()); });
        m_android.process.setProcessEnvironment(env);
        m_android.process.setProcessChannelMode(QProcess::MergedChannels);
        m_android.process.start(QCoreApplication::applicationFilePath(),
                                {QStringLiteral("--android")});
        QTRY_VERIFY2(m_android.printed.contains(QLatin1String("SHOWN")),
                     qPrintable(m_android.printed));
        QTRY_VERIFY(m_android.item->surface());
    }

    void cleanupTestCase() {
        for (App *app : {&m_first, &m_second, &m_android}) {
            ::kill(pid_t(app->process.processId()), SIGCONT);
            app->process.kill();
            app->process.waitForFinished();
        }
    }

    void appCopyReachesTheShell() {
        focus(m_first);
        m_first.send(QStringLiteral("COPY wifi password"));
        QTRY_COMPARE(QGuiApplication::clipboard()->text(), QStringLiteral("wifi password"));
    }

    void anotherAppPastesItAfterTheFirstIsFrozen() {
        focus(m_first);
        m_first.send(QStringLiteral("COPY from the first app"));
        QTRY_COMPARE(QGuiApplication::clipboard()->text(), QStringLiteral("from the first app"));
        ::kill(pid_t(m_first.process.processId()), SIGSTOP);
        focus(m_second);
        const bool pasted = pastes(m_second, QStringLiteral("from the first app"));
        ::kill(pid_t(m_first.process.processId()), SIGCONT);
        QVERIFY2(pasted, qPrintable(m_second.printed));
    }

    void shellCopyReplacesAnAppsOwn() {
        focus(m_first);
        m_first.send(QStringLiteral("COPY the app's own"));
        QTRY_COMPARE(QGuiApplication::clipboard()->text(), QStringLiteral("the app's own"));
        QGuiApplication::clipboard()->setText(QStringLiteral("from the shell"));
        QVERIFY2(pastes(m_first, QStringLiteral("from the shell")), qPrintable(m_first.printed));
        focus(m_second);
        QVERIFY2(pastes(m_second, QStringLiteral("from the shell")), qPrintable(m_second.printed));
    }

    void shellCopyWhileAnotherAppHasTheKeyboard() {
        focus(m_second);
        QGuiApplication::clipboard()->setText(QStringLiteral("copied in the shell"));
        focus(m_first);
        QVERIFY2(pastes(m_first, QStringLiteral("copied in the shell")),
                 qPrintable(m_first.printed));
    }

    void androidCopyReachesTheShellAndApps() {
        focus(m_android);
        m_android.send(QStringLiteral("COPY from android"));
        QTRY_COMPARE(QGuiApplication::clipboard()->text(), QStringLiteral("from android"));
        focus(m_first);
        QVERIFY2(pastes(m_first, QStringLiteral("from android")), qPrintable(m_first.printed));
    }

    void androidGetsTheShellsAndAnAppsCopies() {
        focus(m_second);
        QGuiApplication::clipboard()->setText(QStringLiteral("shell to android"));
        focus(m_android);
        QVERIFY2(androidHolds(QStringLiteral("16:shell to android")),
                 qPrintable(m_android.printed));
        focus(m_first);
        m_first.send(QStringLiteral("COPY app to android"));
        QTRY_COMPARE(QGuiApplication::clipboard()->text(), QStringLiteral("app to android"));
        QTRY_VERIFY(!holdsSource(m_first));
        focus(m_android);
        QVERIFY2(androidHolds(QStringLiteral("14:app to android")), qPrintable(m_android.printed));
    }

    // Android blocks on every selection it is offered until it has read it.
    void androidIsNeverOfferedAFrozenAppsCopy() {
        focus(m_first);
        m_first.send(QStringLiteral("COPY before the freeze"));
        QTRY_COMPARE(QGuiApplication::clipboard()->text(), QStringLiteral("before the freeze"));
        QTRY_VERIFY(!holdsSource(m_first));
        ::kill(pid_t(m_first.process.processId()), SIGSTOP);
        m_android.printed.clear();
        focus(m_android);
        const bool held = androidHolds(QStringLiteral("17:before the freeze"));
        ::kill(pid_t(m_first.process.processId()), SIGCONT);
        QVERIFY2(held, qPrintable(m_android.printed));
    }

    // More than a pipe holds: the compositor must not wait on Android's read
    // while Android waits on the compositor's roundtrip.
    void androidReadsABigCopyWithoutAHang() {
        focus(m_second);
        const QString big(1000000, u'x');
        QGuiApplication::clipboard()->setText(big);
        m_android.printed.clear();
        focus(m_android);
        QVERIFY2(androidHolds(QStringLiteral("1000000:") + big.left(40)),
                 qPrintable(m_android.printed.left(200)));
    }

    void unicodeSurvives() {
        focus(m_second);
        m_second.send(QStringLiteral("COPY café ☕ naïve"));
        QTRY_COMPARE(QGuiApplication::clipboard()->text(), QStringLiteral("café ☕ naïve"));
        focus(m_first);
        QVERIFY2(pastes(m_first, QStringLiteral("café ☕ naïve")), qPrintable(m_first.printed));
    }
};

// --app: a Qt Wayland client with one TextEdit. "COPY <text>" puts the text in
// the field and copies it; "PASTE" empties the field, pastes and prints it.
int main(int argc, char **argv) {
    if (argc == 2 && std::strcmp(argv[1], "--android") == 0)
        return android::run();
    if (argc == 2 && std::strcmp(argv[1], "--app") == 0) {
        QGuiApplication       app(argc, argv);
        QQmlApplicationEngine engine;
        engine.loadData(R"(
            import QtQuick
            Window {
                width: 400; height: 200; visible: true
                onActiveChanged: if (active) console.info("SHOWN")
                Component.onCompleted: console.info("SHOWN")
                TextEdit {
                    objectName: "field"
                    anchors.fill: parent
                    focus: true
                }
            }
        )");
        QObject        *field = engine.rootObjects().constFirst()->findChild<QObject *>("field");
        QSocketNotifier input(STDIN_FILENO, QSocketNotifier::Read);
        QObject::connect(&input, &QSocketNotifier::activated, field, [field]() {
            char       line[4096];
            const auto n = read(STDIN_FILENO, line, sizeof(line) - 1);
            if (n <= 0)
                return;
            const QStringList commands =
                QString::fromUtf8(line, n).split(u'\n', Qt::SkipEmptyParts);
            for (const QString &command : commands) {
                if (command.startsWith(QLatin1String("COPY "))) {
                    field->setProperty("text", command.mid(5));
                    QMetaObject::invokeMethod(field, "selectAll");
                    QMetaObject::invokeMethod(field, "copy");
                } else if (command == QLatin1String("PASTE")) {
                    field->setProperty("text", QString());
                    QMetaObject::invokeMethod(field, "paste");
                    std::printf("PASTED[%s]END\n",
                                field->property("text").toString().toUtf8().constData());
                    std::fflush(stdout);
                }
            }
        });
        return QGuiApplication::exec();
    }
    QGuiApplication     app(argc, argv);
    TestSharedClipboard test;
    return QTest::qExec(&test, argc, argv);
}

#include "test_sharedclipboard.moc"
