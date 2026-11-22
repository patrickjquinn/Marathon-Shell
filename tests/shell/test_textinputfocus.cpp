#include <QGuiApplication>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QSet>
#include <QSocketNotifier>
#include <QTemporaryDir>
#include <QWaylandQuickCompositor>
#include <QWaylandQuickItem>
#include <QWaylandQuickOutput>
#include <QWaylandSeat>
#include <QWaylandSurface>
#include <QWaylandTextInputManager>
#include <QWaylandTextInputManagerV3>
#include <QWaylandXdgShell>
#include <QTest>

#include <cstring>
#include <unistd.h>

#include "services/textinputfocus.h"

// A Qt app's text input as the shell sees it: enabled while a field has
// focus, and off again once focus moves to an item that takes no text, so
// the trackpad scrolls the app instead of moving a caret.
class TestTextInputFocus : public QObject {
    Q_OBJECT

    QTemporaryDir            m_runtime;
    QWaylandQuickCompositor *m_compositor = nullptr;
    QQuickWindow            *m_window     = nullptr;
    QWaylandQuickItem       *m_item       = nullptr;
    QProcess                 m_app;
    QString                  m_printed;
    QSet<QWaylandSurface *>  m_enabled;

    bool                     enabled() const {
        return m_item->surface() && m_enabled.contains(m_item->surface());
    }

    void send(const QByteArray &command) {
        m_app.write(command + '\n');
    }

    // The seat's text-input objects appear when a client first binds.
    bool connectTextInputs() {
        bool                                       found = false;
        const QList<QWaylandCompositorExtension *> extensions =
            m_compositor->defaultSeat()->extensions();
        for (QWaylandCompositorExtension *ext : extensions) {
            const QByteArray cls = ext->metaObject()->className();
            if (cls != "QWaylandTextInput" && cls != "QWaylandTextInputV3")
                continue;
            connect(ext, SIGNAL(surfaceEnabled(QWaylandSurface *)), this,
                    SLOT(surfaceEnabled(QWaylandSurface *)), Qt::UniqueConnection);
            connect(ext, SIGNAL(surfaceDisabled(QWaylandSurface *)), this,
                    SLOT(surfaceDisabled(QWaylandSurface *)), Qt::UniqueConnection);
            found = true;
        }
        return found;
    }

  public slots:
    // As WaylandCompositor::handleTextInputSurfaceEnabled/Disabled keep the
    // set TrackpadInput reads through focusedTextInputEnabled().
    void surfaceEnabled(QWaylandSurface *surface) {
        m_enabled.insert(surface);
    }
    void surfaceDisabled(QWaylandSurface *surface) {
        m_enabled.remove(surface);
    }

  private slots:
    void initTestCase() {
        qputenv("XDG_RUNTIME_DIR", m_runtime.path().toLocal8Bit());
        const QByteArray socket = "marathon-test-textinputfocus";

        m_compositor = new QWaylandQuickCompositor(this);
        m_compositor->setSocketName(socket);
        new QWaylandTextInputManager(m_compositor);
        new QWaylandTextInputManagerV3(m_compositor);
        auto *xdgShell = new QWaylandXdgShell(m_compositor);
        m_compositor->create();
        m_window = new QQuickWindow;
        new QWaylandQuickOutput(m_compositor, m_window);
        m_window->resize(400, 200);
        m_window->show();

        m_item = new QWaylandQuickItem(m_window->contentItem());
        m_item->setSize(QSizeF(400, 200));
        connect(xdgShell, &QWaylandXdgShell::toplevelCreated, m_item,
                [this](QWaylandXdgToplevel *toplevel, QWaylandXdgSurface *surface) {
                    m_item->setSurface(surface->surface());
                    toplevel->sendMaximized(QSize(400, 200));
                    m_item->takeFocus();
                });

        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert("WAYLAND_DISPLAY", QString::fromLatin1(socket));
        env.insert("QT_QPA_PLATFORM", "wayland");
        env.insert("QT_WAYLAND_SHELL_INTEGRATION", "xdg-shell");
        env.insert("QT_IM_MODULE", "wayland");
        env.insert("QT_QUICK_BACKEND", "software");
        env.insert("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1");
        env.insert("QT_FORCE_STDERR_LOGGING", "1");
        m_app.setProcessEnvironment(env);
        m_app.setProcessChannelMode(QProcess::MergedChannels);
        connect(&m_app, &QProcess::readyRead, this,
                [this]() { m_printed += QString::fromUtf8(m_app.readAll()); });
        m_app.start(QCoreApplication::applicationFilePath(), {QStringLiteral("--app")});
        QTRY_VERIFY2(m_item->surface(), qPrintable(m_printed));
        QTRY_VERIFY2(m_printed.contains(QLatin1String("READY")), qPrintable(m_printed));
        QTRY_VERIFY2(connectTextInputs(), qPrintable(m_printed));
    }

    void cleanupTestCase() {
        m_app.kill();
        m_app.waitForFinished();
    }

    void focusLeavingFieldTurnsTextInputOff_data() {
        QTest::addColumn<QByteArray>("away");
        // AddressSheet.leave() in Pacific: `field.focus = false`.
        QTest::newRow("field unfocused") << QByteArray("UNFOCUS");
        // A tap on Pacific's web view: forceActiveFocus() on an item that
        // takes no text.
        QTest::newRow("other item focused") << QByteArray("PAGE");
    }

    void focusLeavingFieldTurnsTextInputOff() {
        QFETCH(QByteArray, away);
        send("FIELD");
        QTRY_VERIFY2(enabled(), qPrintable(m_printed));
        send(away);
        QTRY_VERIFY2(!enabled(), qPrintable(m_printed));
        send("FIELD");
        QTRY_VERIFY2(enabled(), qPrintable(m_printed));
        send("PAGE");
        QTRY_VERIFY2(!enabled(), qPrintable(m_printed));
    }
};

// --app: a Qt Wayland client set up as marathon-app-runner sets up its apps,
// with a text field and an item that takes no text. "FIELD", "PAGE" and
// "UNFOCUS" lines on stdin move focus.
int main(int argc, char **argv) {
    if (argc == 2 && std::strcmp(argv[1], "--app") == 0) {
        QGuiApplication app(argc, argv);
        TextInputFocus::follow(&app);
        QQmlApplicationEngine engine;
        engine.loadData(R"(
            import QtQuick
            Window {
                width: 400; height: 200; visible: true
                TextInput { objectName: "field"; width: 400; height: 100 }
                Item { objectName: "page"; y: 100; width: 400; height: 100 }
                Component.onCompleted: console.info("READY")
            }
        )");
        QObject        *root  = engine.rootObjects().constFirst();
        auto           *field = root->findChild<QQuickItem *>("field");
        auto           *page  = root->findChild<QQuickItem *>("page");
        QSocketNotifier input(STDIN_FILENO, QSocketNotifier::Read);
        QObject::connect(&input, &QSocketNotifier::activated, field, [field, page]() {
            char          line[256];
            const ssize_t n = read(STDIN_FILENO, line, sizeof(line) - 1);
            if (n <= 0)
                return;
            for (const QByteArray &command : QByteArray(line, n).split('\n')) {
                if (command == "FIELD")
                    field->forceActiveFocus();
                else if (command == "PAGE")
                    page->forceActiveFocus();
                else if (command == "UNFOCUS")
                    field->setFocus(false);
            }
        });
        return QGuiApplication::exec();
    }
    QGuiApplication    app(argc, argv);
    TestTextInputFocus test;
    return QTest::qExec(&test, argc, argv);
}

#include "test_textinputfocus.moc"
