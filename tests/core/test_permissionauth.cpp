#include <QTest>

#include "ipc/permissionauth.h"

using PermissionAuth::allowed;
using PermissionAuth::Op;

class TestPermissionAuth : public QObject {
    Q_OBJECT

  private slots:
    void unknownCallerIsDenied() {
        QVERIFY(!allowed(QString(), QStringLiteral("notes"), Op::Read));
        QVERIFY(!allowed(QString(), QString(), Op::Change));
        QVERIFY(!allowed(QStringLiteral("settings"), QString(), Op::Read));
    }

    void appActsOnItself() {
        QVERIFY(allowed(QStringLiteral("notes"), QStringLiteral("notes"), Op::Read));
        QVERIFY(allowed(QStringLiteral("notes"), QStringLiteral("notes"), Op::Request));
    }

    void appCannotTouchAnotherApp() {
        QVERIFY(!allowed(QStringLiteral("notes"), QStringLiteral("weather"), Op::Read));
        QVERIFY(!allowed(QStringLiteral("notes"), QStringLiteral("weather"), Op::Change));
        QVERIFY(!allowed(QStringLiteral("notes"), QStringLiteral("weather"), Op::Request));
        QVERIFY(!allowed(QStringLiteral("notes"), QStringLiteral("settings"), Op::Change));
    }

    void settingsManagesOtherApps() {
        QVERIFY(allowed(QStringLiteral("settings"), QStringLiteral("weather"), Op::Read));
        QVERIFY(allowed(QStringLiteral("settings"), QStringLiteral("weather"), Op::Change));
    }

    // A prompt must belong to the app that asked for it.
    void settingsCannotPromptForAnotherApp() {
        QVERIFY(!allowed(QStringLiteral("settings"), QStringLiteral("weather"), Op::Request));
    }

    void adminMatchIsExact() {
        QVERIFY(!allowed(QStringLiteral("Settings"), QStringLiteral("weather"), Op::Read));
        QVERIFY(!allowed(QStringLiteral("settings.evil"), QStringLiteral("weather"), Op::Read));
        QVERIFY(!allowed(QStringLiteral(" settings"), QStringLiteral("weather"), Op::Change));
    }
};

QTEST_GUILESS_MAIN(TestPermissionAuth)
#include "test_permissionauth.moc"
