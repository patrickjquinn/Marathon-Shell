#include <QGuiApplication>
#include <QInputDevice>
#include <QKeyEvent>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QTest>

#include "services/inputcontext.h"
#include "services/remotetextinput.h"

namespace {
    // NOLINTNEXTLINE(bugprone-throwing-static-initialization) QStringLiteral never allocates
    const QString kApp = QStringLiteral("waydroid.org.example");

    // Stands in for an app's surface item: it counts the keys it is given.
    class Surface : public QQuickItem {
      public:
        int keys = 0;

      protected:
        void keyPressEvent(QKeyEvent *event) override {
            ++keys;
            event->accept();
        }
    };
} // namespace

// The keyboard types into an app's editor through its input method service:
// the shell answers the keyboard from the editor the service reported and
// hands the service what the keyboard typed.
class TestRemoteTextInput : public QObject {
    Q_OBJECT

    QQuickWindow    *m_window  = nullptr;
    Surface         *m_surface = nullptr;
    RemoteTextInput *m_input   = nullptr;

    static QVariant  focusQuery(Qt::InputMethodQuery query) {
        return QInputMethod::queryFocusObject(query, {});
    }

  private slots:
    void init() {
        m_window = new QQuickWindow;
        m_window->resize(200, 200);
        m_surface = new Surface;
        m_surface->setParentItem(m_window->contentItem());
        m_surface->setFlag(QQuickItem::ItemIsFocusScope);
        m_window->show();
        m_window->requestActivate();
        m_surface->forceActiveFocus();
        QTRY_COMPARE(QGuiApplication::focusObject(), m_surface);

        Surface *surface = m_surface;
        m_input          = new RemoteTextInput(
            [surface](QObject *object) { return object == surface ? kApp : QString(); });
        m_input->setService(QStringLiteral("waydroid."));
    }

    void cleanup() {
        delete m_input;
        delete m_window;
    }

    void answersTheKeyboardFromTheEditor() {
        QVERIFY(m_input->setEditor(kApp, 5, 0));
        QVERIFY(m_input->setSurroundingText(kApp, QStringLiteral("https://x"), 9, 9));
        QVERIFY(focusQuery(Qt::ImEnabled).toBool());
        QVERIFY(focusQuery(Qt::ImHints).toInt() & Qt::ImhUrlCharactersOnly);
        QCOMPARE(focusQuery(Qt::ImSurroundingText).toString(), QStringLiteral("https://x"));
        QCOMPARE(focusQuery(Qt::ImTextBeforeCursor).toString(), QStringLiteral("https://x"));
        QCOMPARE(focusQuery(Qt::ImCursorPosition).toInt(), 9);
    }

    void reportsTheSelection() {
        m_input->setEditor(kApp, 0, 0);
        m_input->setSurroundingText(kApp, QStringLiteral("abcdef"), 4, 1);
        QCOMPARE(focusQuery(Qt::ImCurrentSelection).toString(), QStringLiteral("bcd"));
        QCOMPARE(focusQuery(Qt::ImAnchorPosition).toInt(), 1);
    }

    void leavesOtherWindowsAlone() {
        QVERIFY(m_input->setEditor(QStringLiteral("waydroid.org.other"), 5, 0));
        QVERIFY(!focusQuery(Qt::ImHints).isValid());
        QSignalSpy   commits(m_input, &RemoteTextInput::commitString);
        InputContext context;
        context.insertText(QStringLiteral("x"));
        QCOMPARE(commits.count(), 0);
    }

    void claimsOnlyItsOwnApps() {
        QVERIFY(!m_input->setEditor(QStringLiteral("org.marathonos.notes"), 0, 0));
        QVERIFY(!m_input->handles(QStringLiteral("org.marathonos.notes")));
        QVERIFY(m_input->handles(kApp));
        m_input->setService(QString());
        QVERIFY(!m_input->setEditor(kApp, 0, 0));
        QVERIFY(!m_input->handles(kApp));
    }

    void clearedEditorTakesNoMoreText() {
        m_input->setEditor(kApp, 0, 0);
        QVERIFY(m_input->clearEditor(kApp));
        QVERIFY(!focusQuery(Qt::ImHints).isValid());
    }

    void typedTextIsCommitted() {
        m_input->setEditor(kApp, 0, 0);
        QSignalSpy   commits(m_input, &RemoteTextInput::commitString);
        InputContext context;
        context.insertText(QStringLiteral("hi"));
        QCOMPARE(commits.count(), 1);
        QCOMPARE(commits.at(0), (QVariantList{kApp, QStringLiteral("hi"), 0, 0}));
        // The keyboard sees its own text before the app reports back.
        QCOMPARE(focusQuery(Qt::ImSurroundingText).toString(), QStringLiteral("hi"));
        QCOMPARE(focusQuery(Qt::ImCursorPosition).toInt(), 2);
    }

    void typingReplacesTheSelection() {
        m_input->setEditor(kApp, 0, 0);
        m_input->setSurroundingText(kApp, QStringLiteral("https://old/"), 12, 0);
        InputContext context;
        context.insertText(QStringLiteral("w"));
        QCOMPARE(focusQuery(Qt::ImSurroundingText).toString(), QStringLiteral("w"));
    }

    void correctionsReplaceTheTypedWord() {
        m_input->setEditor(kApp, 0, 0x7);
        m_input->setSurroundingText(kApp, QStringLiteral("hello teh"), 9, 9);
        QSignalSpy   commits(m_input, &RemoteTextInput::commitString);
        InputContext context;
        QVERIFY(context.replaceTextBeforeCursor(QStringLiteral("teh"), QStringLiteral("the")));
        QCOMPARE(commits.at(0), (QVariantList{kApp, QStringLiteral("the"), 3, 0}));
        QCOMPARE(focusQuery(Qt::ImSurroundingText).toString(), QStringLiteral("hello the"));
    }

    void keyboardKeysGoToTheService() {
        m_input->setEditor(kApp, 0, 0);
        m_input->setSurroundingText(kApp, QStringLiteral("ab"), 2, 2);
        QSignalSpy   keys(m_input, &RemoteTextInput::key);
        InputContext context;
        context.handleBackspace();
        context.handleEnter();
        context.sendCursorKey(Qt::Key_Left);
        QCOMPARE(keys.count(), 3);
        QCOMPARE(keys.at(0).at(1).toString(), QStringLiteral("backspace"));
        QCOMPARE(keys.at(1).at(1).toString(), QStringLiteral("enter"));
        QCOMPARE(keys.at(2).at(1).toString(), QStringLiteral("left"));
        QCOMPARE(m_surface->keys, 0);
        QCOMPARE(focusQuery(Qt::ImSurroundingText).toString(), QStringLiteral("a"));
    }

    // A hardware keyboard reaches the app as keys, which Android maps itself.
    void hardwareKeysPassThrough() {
        m_input->setEditor(kApp, 0, 0);
        QSignalSpy keys(m_input, &RemoteTextInput::key);
        QKeyEvent  press(QEvent::KeyPress, Qt::Key_A, Qt::NoModifier, QStringLiteral("a"));
        QGuiApplication::sendEvent(m_surface, &press);
        QCOMPARE(keys.count(), 0);
        QCOMPARE(m_surface->keys, 1);
    }

    void keysPassThroughWithoutAnEditor() {
        InputContext context;
        context.handleBackspace();
        QCOMPARE(m_surface->keys, 1);
    }

    void panelFollowsTheFocusedApp() {
        m_input->setEditor(kApp, 0, 0);
        QSignalSpy panel(m_input, &RemoteTextInput::panelRequested);
        QVERIFY(m_input->requestPanel(kApp, true));
        QVERIFY(!m_input->requestPanel(QStringLiteral("waydroid.org.other"), true));
        QVERIFY(m_input->requestPanel(kApp, false));
        QCOMPARE(panel.count(), 2);
        QCOMPARE(panel.at(0).at(0).toBool(), true);
        QCOMPARE(panel.at(1).at(0).toBool(), false);
    }

    void reportsCoverageOncePerChange() {
        QSignalSpy changes(m_input, &RemoteTextInput::panelChanged);
        m_input->setPanel(kApp, 200, 400);
        m_input->setPanel(kApp, 200, 400);
        m_input->setPanel(QStringLiteral("org.marathonos.notes"), 100, 400);
        m_input->setPanel(kApp, 0, 400);
        QCOMPARE(changes.count(), 2);
        QCOMPARE(changes.at(0), (QVariantList{kApp, 200, 400}));
        QCOMPARE(changes.at(1), (QVariantList{kApp, 0, 400}));
    }

    void mapsContentTypes() {
        const auto plain = Qt::ImhNoPredictiveText | Qt::ImhNoAutoUppercase;
        QCOMPARE(RemoteTextInput::qtHints(0, 0), plain);
        QCOMPARE(RemoteTextInput::qtHints(0, 0x1 | 0x2 | 0x4), Qt::InputMethodHints());
        QCOMPARE(RemoteTextInput::qtHints(5, 0), plain | Qt::ImhUrlCharactersOnly);
        QCOMPARE(RemoteTextInput::qtHints(6, 0), plain | Qt::ImhEmailCharactersOnly);
        QCOMPARE(RemoteTextInput::qtHints(2, 0), plain | Qt::ImhDigitsOnly);
        QCOMPARE(RemoteTextInput::qtHints(3, 0), plain | Qt::ImhFormattedNumbersOnly);
        QCOMPARE(RemoteTextInput::qtHints(4, 0), plain | Qt::ImhDialableCharactersOnly);
        QCOMPARE(RemoteTextInput::qtHints(8, 0x40 | 0x80),
                 plain | Qt::ImhHiddenText | Qt::ImhSensitiveData);
        QCOMPARE(RemoteTextInput::qtHints(9, 0x40 | 0x80),
                 plain | Qt::ImhDigitsOnly | Qt::ImhHiddenText | Qt::ImhSensitiveData);
        QCOMPARE(RemoteTextInput::qtHints(0, 0x1 | 0x4 | 0x200), Qt::ImhMultiLine);
    }
};

QTEST_MAIN(TestRemoteTextInput)
#include "test_remotetextinput.moc"
