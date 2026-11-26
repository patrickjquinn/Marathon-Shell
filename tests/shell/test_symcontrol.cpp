#include <QClipboard>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QMimeData>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QSocketNotifier>
#include <QTemporaryDir>
#include <QWaylandKeymap>
#include <QWaylandQuickCompositor>
#include <QWaylandQuickItem>
#include <QWaylandQuickOutput>
#include <QWaylandSeat>
#include <QWaylandXdgShell>
#include <QTest>
#include <qpa/qwindowsysteminterface.h>

#include <cstring>
#include <unistd.h>
#include <wayland-server-core.h>

#include "src/wayland/sharedclipboard.h"
#include "src/wayland/symcontrol.h"

namespace {
    // Evdev + 8, as the Q25's keyboard reports them.
    constexpr quint32 kSym = 100 + 8;
    constexpr quint32 kA   = 30 + 8;
    constexpr quint32 kC   = 46 + 8;
    constexpr quint32 kH   = 35 + 8;
    constexpr quint32 kV   = 47 + 8;
    constexpr quint32 kX   = 45 + 8;

    class Compositor : public QWaylandQuickCompositor {
      public:
        SharedClipboard *clipboard = nullptr;
        SymControl       symControl;

      protected:
        void retainedSelectionReceived(QMimeData *data) override {
            clipboard->take(data);
        }

        bool eventFilter(QObject *watched, QEvent *event) override {
            return symControl.filter(watched, event, defaultSeat()) ||
                QWaylandQuickCompositor::eventFilter(watched, event);
        }
    };
} // namespace

// The Q25's Sym key as Ctrl in a Qt app, through a Qt compositor with the
// Q25's keymap, as WaylandCompositor's window filter applies it.
class TestSymControl : public QObject {
    Q_OBJECT

    QTemporaryDir m_runtime;
    QTemporaryDir m_xkb;
    Compositor   *m_compositor = nullptr;
    QQuickWindow *m_window     = nullptr;
    QProcess      m_app;
    QString       m_printed;

    QString       fieldText() const {
        const qsizetype start = m_printed.lastIndexOf(QLatin1String("TEXT["));
        if (start < 0)
            return {};
        const qsizetype end = m_printed.indexOf(QLatin1String("]END"), start);
        return end < 0 ? QString() : m_printed.mid(start + 5, end - start - 5);
    }

    void setField(const QString &text) {
        m_printed.clear();
        m_app.write(("SET " + text + "\n").toUtf8());
        QTRY_VERIFY(m_printed.contains("TEXT[" + text + "]END"));
    }

    // The scan code as the keyboard sends it; Qt's compositor gives the event
    // its key and modifiers from the keymap.
    void key(QEvent::Type type, quint32 code) {
        QWindowSystemInterface::handleExtendedKeyEvent(m_window, type, 0, Qt::NoModifier, code, 0,
                                                       0);
        wl_display_flush_clients(m_compositor->display());
    }

    void tap(quint32 code) {
        key(QEvent::KeyPress, code);
        key(QEvent::KeyRelease, code);
    }

    void withSym(const QList<quint32> &codes) {
        key(QEvent::KeyPress, kSym);
        for (quint32 code : codes)
            tap(code);
        key(QEvent::KeyRelease, kSym);
    }

  private slots:
    void initTestCase() {
        qputenv("XDG_RUNTIME_DIR", m_runtime.path().toLocal8Bit());
        QVERIFY(QDir(m_xkb.path()).mkpath(QStringLiteral("symbols")));
        QVERIFY(QFile::copy(QStringLiteral(Q25_XKB_SYMBOLS), m_xkb.filePath("symbols/q25")));
        qputenv("XKB_CONFIG_EXTRA_PATH", m_xkb.path().toLocal8Bit());
        QWindowSystemInterface::setSynchronousWindowSystemEvents(true);

        const QByteArray socket = "marathon-test-symcontrol";
        m_compositor            = new Compositor;
        m_compositor->setParent(this);
        m_compositor->setSocketName(socket);
        auto *xdgShell = new QWaylandXdgShell(m_compositor);
        m_compositor->create();
        m_compositor->clipboard = new SharedClipboard(m_compositor);
        QWaylandKeymap *keymap  = m_compositor->defaultSeat()->keymap();
        keymap->setRules(QStringLiteral("evdev"));
        keymap->setModel(QStringLiteral("pc105"));
        keymap->setLayout(QStringLiteral("q25"));
        keymap->setVariant(QStringLiteral("printed"));
        m_window = new QQuickWindow;
        new QWaylandQuickOutput(m_compositor, m_window);
        m_window->resize(400, 200);
        m_window->show();
        m_window->requestActivate();
        m_window->installEventFilter(m_compositor);

        auto *item = new QWaylandQuickItem(m_window->contentItem());
        item->setSize(QSizeF(400, 200));
        connect(xdgShell, &QWaylandXdgShell::toplevelCreated, item,
                [item](QWaylandXdgToplevel *toplevel, QWaylandXdgSurface *surface) {
                    item->setSurface(surface->surface());
                    toplevel->sendMaximized(QSize(400, 200));
                    item->takeFocus();
                });

        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert("WAYLAND_DISPLAY", QString::fromLatin1(socket));
        env.insert("QT_QPA_PLATFORM", "wayland");
        env.insert("QT_WAYLAND_SHELL_INTEGRATION", "xdg-shell");
        env.insert("QT_QUICK_BACKEND", "software");
        env.insert("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1");
        env.insert("QT_FORCE_STDERR_LOGGING", "1");
        m_app.setProcessEnvironment(env);
        m_app.setProcessChannelMode(QProcess::MergedChannels);
        connect(&m_app, &QProcess::readyRead, this,
                [this]() { m_printed += QString::fromUtf8(m_app.readAll()); });
        m_app.start(QCoreApplication::applicationFilePath(), {QStringLiteral("--app")});
        QTRY_VERIFY2(m_printed.contains(QLatin1String("FOCUSED")), qPrintable(m_printed));
    }

    void cleanupTestCase() {
        m_app.kill();
        m_app.waitForFinished();
    }

    void lettersTypeWithoutSym() {
        setField(QString());
        tap(kC);
        tap(kA);
        QTRY_COMPARE(fieldText(), QStringLiteral("ca"));
    }

    void symACopiesAll() {
        setField(QStringLiteral("hunter2"));
        withSym({kA, kC});
        QTRY_COMPARE(QGuiApplication::clipboard()->text(), QStringLiteral("hunter2"));
        QCOMPARE(fieldText(), QStringLiteral("hunter2"));
    }

    void symVPastes() {
        QGuiApplication::clipboard()->setText(QStringLiteral("my wifi password"));
        setField(QString());
        withSym({kV});
        QTRY_COMPARE(fieldText(), QStringLiteral("my wifi password"));
    }

    void symXCuts() {
        setField(QStringLiteral("cut me"));
        withSym({kA, kX});
        QTRY_COMPARE(fieldText(), QString());
        QTRY_COMPARE(QGuiApplication::clipboard()->text(), QStringLiteral("cut me"));
    }

    void symKeepsItsOwnKeysAfterACopy() {
        setField(QStringLiteral("abc"));
        // Sym+H is Home: the cursor moves, nothing is typed.
        withSym({kA, kC, kH});
        tap(kX);
        QTRY_COMPARE(fieldText(), QStringLiteral("xabc"));
    }
};

// --app: a Qt Wayland client with one focused TextEdit. It prints its text
// and takes "SET <text>" lines on stdin, the cursor left at the end.
int main(int argc, char **argv) {
    if (argc == 2 && std::strcmp(argv[1], "--app") == 0) {
        QGuiApplication       app(argc, argv);
        QQmlApplicationEngine engine;
        engine.loadData(R"(
            import QtQuick
            Window {
                width: 400; height: 200; visible: true
                TextEdit {
                    objectName: "field"
                    anchors.fill: parent
                    focus: true
                    onActiveFocusChanged: if (activeFocus) console.info("FOCUSED")
                    onTextChanged: console.info("TEXT[" + text + "]END")
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
            QString text = QString::fromUtf8(line, n).chopped(1);
            if (!text.startsWith(QLatin1String("SET ")))
                return;
            text = text.mid(4);
            field->setProperty("text", text);
            field->setProperty("cursorPosition", text.size());
            std::printf("TEXT[%s]END\n", text.toUtf8().constData());
            std::fflush(stdout);
        });
        return QGuiApplication::exec();
    }
    QGuiApplication app(argc, argv);
    TestSymControl  test;
    return QTest::qExec(&test, argc, argv);
}

#include "test_symcontrol.moc"
