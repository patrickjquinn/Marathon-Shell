#include <QDateTime>
#include <QGuiApplication>
#include <QInputMethod>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickWindow>
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

#include <cstdio>
#include <cstring>
#include <unistd.h>

#include "marathon-shell-native/src/words.cxxqt.h"
#include "services/inputcontext.h"

namespace {
    // InputMethodEngine's focusHints(), which the keyboard reads.
    class FocusHints : public QObject {
        Q_OBJECT

      public:
        Q_INVOKABLE int focusHints() const {
            return QInputMethod::queryFocusObject(Qt::ImHints, {}).toInt();
        }
    };
} // namespace

// The shell's keyboard typing into a Marathon app as on a device: the real
// MarathonKeyboard and InputContext in a Qt compositor, a Qt client with a
// TextEdit (Silica's TextArea) on text-input v2, and the shell's refresh of
// the keyboard whenever Qt reports the field's hints.
class TestKeyboardTextInput : public QObject {
    Q_OBJECT

    QTemporaryDir            m_runtime;
    QWaylandQuickCompositor *m_compositor = nullptr;
    QQuickWindow            *m_window     = nullptr;
    QWaylandQuickItem       *m_item       = nullptr;
    QQmlEngine              *m_engine     = nullptr;
    QObject                 *m_keyboard   = nullptr;
    FocusHints               m_hints;
    QProcess                 m_app;
    QString                  m_printed;

    QString                  clientText() const {
        const qsizetype start = m_printed.lastIndexOf(QLatin1String("TEXT["));
        if (start < 0)
            return {};
        const qsizetype end = m_printed.indexOf(QLatin1String("]END"), start);
        return end < 0 ? QString() : m_printed.mid(start + 5, end - start - 5);
    }

    static QString fieldText() {
        return QInputMethod::queryFocusObject(Qt::ImSurroundingText, {}).toString();
    }

    bool shifted() const {
        return m_keyboard->property("shifted").toBool();
    }

    void setField(const QString &text) {
        m_app.write(("SET " + text + "\n").toUtf8());
        QTRY_COMPARE(clientText(), text);
        QTRY_COMPARE(fieldText(), text);
        QMetaObject::invokeMethod(m_keyboard, "hide");
        m_keyboard->setProperty("active", false);
        m_keyboard->setProperty("active", true);
    }

    // A key as the layout sends it: shifted letters come capitalised. Waits
    // for the app to report its text back, as a person's next tap does.
    void tap(const QString &keys) {
        for (const QChar c : keys) {
            if (c == u' ') {
                QMetaObject::invokeMethod(m_keyboard, "handleSpace");
            } else {
                const bool upper = shifted() || m_keyboard->property("capsLock").toBool();
                QMetaObject::invokeMethod(
                    m_keyboard, "handleKeyPress",
                    Q_ARG(QVariant, upper ? QString(c).toUpper() : QString(c)));
            }
            QTRY_COMPARE(fieldText(), clientText());
        }
    }

    // The next space is a separate tap, or the second of a double tap,
    // however long the app took to answer.
    void pause() {
        m_keyboard->setProperty("lastSpaceTime", 0);
    }

    void justTappedSpace() {
        m_keyboard->setProperty("lastSpaceTime", double(QDateTime::currentMSecsSinceEpoch()));
    }

  public slots:
    void textInputUpdated(Qt::InputMethodQueries queries) {
        if ((queries & Qt::ImHints) && m_keyboard->property("active").toBool())
            QMetaObject::invokeMethod(m_keyboard, "refreshFieldHints");
    }

  private slots:
    void initTestCase() {
        qputenv("XDG_RUNTIME_DIR", m_runtime.path().toLocal8Bit());
        const QByteArray socket = "marathon-test-keyboard";

        m_compositor = new QWaylandQuickCompositor(this);
        m_compositor->setSocketName(socket);
        new QWaylandTextInputManager(m_compositor);
        new QWaylandTextInputManagerV3(m_compositor);
        auto *xdgShell = new QWaylandXdgShell(m_compositor);
        m_compositor->create();
        m_window = new QQuickWindow;
        new QWaylandQuickOutput(m_compositor, m_window);
        m_window->resize(400, 700);
        m_window->show();
        m_window->requestActivate();

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
        QTRY_COMPARE(QGuiApplication::focusObject(), m_item);
        QTRY_VERIFY2(m_printed.contains(QLatin1String("FOCUSED")), qPrintable(m_printed));

        qmlRegisterType<InputContext>("MarathonOS.Shell", 1, 0, "InputContext");
        qmlRegisterSingletonType<marathon::Dictionary>(
            "MarathonOS.Shell", 1, 0, "Dictionary",
            [](QQmlEngine *, QJSEngine *) -> QObject * { return new marathon::Dictionary(); });
        qmlRegisterSingletonType<marathon::DomainSuggestions>(
            "MarathonOS.Shell", 1, 0, "DomainSuggestions",
            [](QQmlEngine *, QJSEngine *) -> QObject * { return new marathon::DomainSuggestions(); });
        m_engine = new QQmlEngine(this);
        const QStringList imports = qEnvironmentVariable("MARATHON_TEST_QML_IMPORTS").split(u':');
        for (const QString &path : imports)
            m_engine->addImportPath(path);
        m_engine->rootContext()->setContextProperty("InputMethodEngine", &m_hints);
        QQmlComponent component(m_engine,
                                QUrl::fromLocalFile(QStringLiteral(MARATHON_KEYBOARD_QML)));
        m_keyboard = component.createWithInitialProperties({{"y", 200}});
        QVERIFY2(m_keyboard, qPrintable(component.errorString()));
        qobject_cast<QQuickItem *>(m_keyboard)->setParentItem(m_window->contentItem());

        // As WaylandCompositor::handleTextInputUpdate and MarathonShell.qml do.
        const QList<QWaylandCompositorExtension *> extensions =
            m_compositor->defaultSeat()->extensions();
        for (QWaylandCompositorExtension *ext : extensions) {
            if (QByteArray(ext->metaObject()->className()) == "QWaylandTextInput")
                connect(ext, SIGNAL(updateInputMethod(Qt::InputMethodQueries)), this,
                        SLOT(textInputUpdated(Qt::InputMethodQueries)));
        }
    }

    void cleanupTestCase() {
        m_app.kill();
        m_app.waitForFinished();
    }

    void capitalisesOnlyAtSentenceStart() {
        setField(QStringLiteral("Test note: buy milk, eggs and coffee on Friday."));
        tap(QStringLiteral(" "));
        QVERIFY(shifted());
        tap(QStringLiteral("teh "));
        QCOMPARE(clientText(),
                 QStringLiteral("Test note: buy milk, eggs and coffee on Friday. The "));
        QVERIFY(!shifted());
        tap(QStringLiteral("hello "));
        QVERIFY(!shifted());
        QCOMPARE(clientText(),
                 QStringLiteral("Test note: buy milk, eggs and coffee on Friday. The hello "));
    }

    void slowDoubleSpaceStaysMidSentence() {
        setField(QString());
        tap(QStringLiteral("buy milk "));
        pause();
        tap(QStringLiteral(" "));
        QVERIFY(!shifted());
        tap(QStringLiteral("eggs"));
        QCOMPARE(clientText(), QStringLiteral("Buy milk  eggs"));
    }

    void doubleSpaceEndsSentence() {
        setField(QString());
        tap(QStringLiteral("buy milk "));
        justTappedSpace();
        tap(QStringLiteral(" "));
        QVERIFY(shifted());
        tap(QStringLiteral("eggs"));
        QCOMPARE(clientText(), QStringLiteral("Buy milk. Eggs"));
    }

    void keepsCapitalsOfCorrectedWord() {
        setField(QString());
        tap(QStringLiteral("note "));
        QMetaObject::invokeMethod(m_keyboard, "handleShift");
        QMetaObject::invokeMethod(m_keyboard, "handleShift");
        QVERIFY(m_keyboard->property("capsLock").toBool());
        tap(QStringLiteral("teh "));
        QCOMPARE(clientText(), QStringLiteral("Note THE "));
    }
};

// --app: a Qt Wayland client with one focused TextEdit. It prints its text
// and takes "SET <text>" lines on stdin.
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
        });
        return QGuiApplication::exec();
    }
    QGuiApplication       app(argc, argv);
    TestKeyboardTextInput test;
    return QTest::qExec(&test, argc, argv);
}

#include "test_keyboardtextinput.moc"
