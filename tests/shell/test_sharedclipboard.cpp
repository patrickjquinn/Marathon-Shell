#include <QClipboard>
#include <QGuiApplication>
#include <QMimeData>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QSocketNotifier>
#include <QTemporaryDir>
#include <QWaylandQuickCompositor>
#include <QWaylandQuickItem>
#include <QWaylandQuickOutput>
#include <QWaylandSeat>
#include <QWaylandXdgShell>
#include <QTest>

#include <csignal>
#include <cstring>
#include <unistd.h>
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

    void              start(App &app, qreal y) {
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
        return QTest::qWaitFor([this, &app, &expected]() {
            // The shell's event loop flushes when it idles; this one never does.
            wl_display_flush_clients(m_compositor->display());
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
        m_window                = new QQuickWindow;
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
    }

    void cleanupTestCase() {
        for (App *app : {&m_first, &m_second}) {
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
