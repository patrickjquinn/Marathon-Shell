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
    void otherKeysPassThrough() {
        QCOMPARE(KeyRouting::systemAction(Qt::Key_A, QStringLiteral("keel")), KeyRouting::None);
    }
};

QTEST_GUILESS_MAIN(TestKeyRouting)
#include "test_keyrouting.moc"
