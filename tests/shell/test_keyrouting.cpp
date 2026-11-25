#include <QTest>

#include "keyrouting.h"

class TestKeyRouting : public QObject {
    Q_OBJECT

  private slots:
    void escapeIsBackWithNoApp() {
        QCOMPARE(KeyRouting::systemAction(Qt::Key_Escape, QString()), KeyRouting::Back);
    }
    void escapeGoesToKeelApps() {
        // Keel apps close menus and dialogs on Escape and turn an unused
        // one into back themselves.
        QCOMPARE(KeyRouting::systemAction(Qt::Key_Escape, QStringLiteral("keel")),
                 KeyRouting::None);
    }
    void superIsHomeForEveryApp() {
        QCOMPARE(KeyRouting::systemAction(Qt::Key_Super_L, QStringLiteral("keel")),
                 KeyRouting::Home);
        QCOMPARE(KeyRouting::systemAction(Qt::Key_Meta, QString()), KeyRouting::Home);
    }
    void phoneKeysOldAndNewCodes() {
        // bbqx0kbd: KEY_PICKUP_PHONE, KEY_HANGUP_PHONE, KEY_MENU (no xkb keysyms).
        QCOMPARE(KeyRouting::systemAction(0, QString(), 445 + 8), KeyRouting::Call);
        QCOMPARE(KeyRouting::systemAction(0, QString(), 446 + 8), KeyRouting::Hangup);
        QCOMPARE(KeyRouting::systemAction(Qt::Key_Menu, QString(), 139 + 8), KeyRouting::Home);
        // The older driver: KEY_HOMEPAGE for the menu key.
        QCOMPARE(KeyRouting::systemAction(Qt::Key_HomePage, QString(), 172 + 8), KeyRouting::Home);
        // Any other keyboard's hang-up key.
        QCOMPARE(KeyRouting::systemAction(Qt::Key_Hangup, QString()), KeyRouting::End);
    }
    void keysUnderTheScreen() {
        // The MP01's back, home and recents: KEY_BACK, KEY_HOMEPAGE, KEY_APPSELECT.
        QCOMPARE(KeyRouting::systemAction(Qt::Key_Back, QString(), 158 + 8), KeyRouting::Back);
        QCOMPARE(KeyRouting::systemAction(Qt::Key_HomePage, QString(), 172 + 8), KeyRouting::Home);
        // Recents never ends a call.
        QCOMPARE(KeyRouting::systemAction(0, QString(), 580 + 8), KeyRouting::Switcher);
    }
    void keysReadFromTheTouchscreen() {
        // As the touchscreen reader delivers them: its Qt key, evdev + 8.
        const auto action = [](quint16 code) {
            return KeyRouting::systemAction(KeyRouting::touchscreenKey(code), QString(), code + 8);
        };
        QCOMPARE(action(158), KeyRouting::Back);
        QCOMPARE(action(172), KeyRouting::Home);
        QCOMPARE(action(580), KeyRouting::Switcher);
        // Touch itself and the pen's tools stay with the touch reader.
        QCOMPARE(KeyRouting::touchscreenKey(0x14a), -1); // BTN_TOUCH
        QCOMPARE(KeyRouting::touchscreenKey(0x145), -1); // BTN_TOOL_FINGER
        QCOMPARE(KeyRouting::touchscreenKey(0x220), -1); // BTN_DPAD_UP
        QCOMPARE(KeyRouting::touchscreenKey(0x2c0), -1); // BTN_TRIGGER_HAPPY
    }
    void pcMenuKeyIsNotHome() {
        // KEY_COMPOSE also maps to Qt::Key_Menu.
        QCOMPARE(KeyRouting::systemAction(Qt::Key_Menu, QString(), 127 + 8), KeyRouting::None);
    }
    void otherKeysPassThrough() {
        QCOMPARE(KeyRouting::systemAction(Qt::Key_A, QStringLiteral("keel")), KeyRouting::None);
    }
};

QTEST_GUILESS_MAIN(TestKeyRouting)
#include "test_keyrouting.moc"
