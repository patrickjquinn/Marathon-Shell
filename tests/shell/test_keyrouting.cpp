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
        // The older driver: KEY_APPSELECT for end, KEY_HOMEPAGE for the menu key.
        QCOMPARE(KeyRouting::systemAction(0, QString(), 580 + 8), KeyRouting::Hangup);
        QCOMPARE(KeyRouting::systemAction(Qt::Key_HomePage, QString(), 172 + 8), KeyRouting::Home);
        // Any other keyboard's hang-up key.
        QCOMPARE(KeyRouting::systemAction(Qt::Key_Hangup, QString()), KeyRouting::End);
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
