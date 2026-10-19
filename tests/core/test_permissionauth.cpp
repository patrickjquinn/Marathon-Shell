#include <QTest>

#include "ipc/permissionauth.h"

using PermissionAuth::allowed;
using PermissionAuth::Op;

class TestPermissionAuth : public QObject {
    Q_OBJECT

  private slots:
    void unknownCallerIsDenied() {
        QVERIFY(!allowed(QString(), QStringLiteral("notes"), Op::Read));
        QVERIFY(!allowed(QString(), QString(), Op::Grant));
        QVERIFY(!allowed(QStringLiteral("settings"), QString(), Op::Read));
    }

    void appActsOnItself() {
        QVERIFY(allowed(QStringLiteral("notes"), QStringLiteral("notes"), Op::Read));
        QVERIFY(allowed(QStringLiteral("notes"), QStringLiteral("notes"), Op::Request));
        QVERIFY(allowed(QStringLiteral("notes"), QStringLiteral("notes"), Op::Revoke));
    }

    // Only the user grants: through the shell's prompt or Settings.
    void appCannotGrantItself() {
        QVERIFY(!allowed(QStringLiteral("notes"), QStringLiteral("notes"), Op::Grant));
    }

    void appCannotTouchAnotherApp() {
        QVERIFY(!allowed(QStringLiteral("notes"), QStringLiteral("weather"), Op::Read));
        QVERIFY(!allowed(QStringLiteral("notes"), QStringLiteral("weather"), Op::Grant));
        QVERIFY(!allowed(QStringLiteral("notes"), QStringLiteral("weather"), Op::Request));
        QVERIFY(!allowed(QStringLiteral("notes"), QStringLiteral("settings"), Op::Grant));
    }

    void settingsManagesOtherApps() {
        QVERIFY(allowed(QStringLiteral("settings"), QStringLiteral("weather"), Op::Read));
        QVERIFY(allowed(QStringLiteral("settings"), QStringLiteral("weather"), Op::Grant));
        QVERIFY(allowed(QStringLiteral("settings"), QStringLiteral("weather"), Op::Revoke));
    }

    // A prompt must belong to the app that asked for it.
    void settingsCannotPromptForAnotherApp() {
        QVERIFY(!allowed(QStringLiteral("settings"), QStringLiteral("weather"), Op::Request));
    }

    void adminMatchIsExact() {
        QVERIFY(!allowed(QStringLiteral("Settings"), QStringLiteral("weather"), Op::Read));
        QVERIFY(!allowed(QStringLiteral("settings.evil"), QStringLiteral("weather"), Op::Read));
        QVERIFY(!allowed(QStringLiteral(" settings"), QStringLiteral("weather"), Op::Grant));
    }

    void androidAppIds() {
        using PermissionAuth::isAndroidAppId;
        QVERIFY(isAndroidAppId(QStringLiteral("waydroid.org.fossify.camera")));
        QVERIFY(isAndroidAppId(QStringLiteral("waydroid.me.hackerchick.catima")));
        QVERIFY(!isAndroidAppId(QStringLiteral("waydroid.")));
        QVERIFY(!isAndroidAppId(QStringLiteral("notes")));
        QVERIFY(!isAndroidAppId(QStringLiteral("waydroid.bad pkg")));
        QVERIFY(!isAndroidAppId(QStringLiteral("waydroid.9lives")));
        QVERIFY(!isAndroidAppId(QStringLiteral("waydroid.a..b")));
        QVERIFY(!isAndroidAppId(QStringLiteral("waydroid.") + QString(256, u'a')));
    }

    void foreignPromptOptionsAreCleaned() {
        using PermissionAuth::foreignOptions;
        QVariantMap out;
        QVERIFY(foreignOptions({}, &out));
        QCOMPARE(out.value(QStringLiteral("kind")).toString(), QStringLiteral("foreground"));
        QCOMPARE(out.value(QStringLiteral("once")).toBool(), false);
        QCOMPARE(out.value(QStringLiteral("accuracy")).toString(), QString());

        QVERIFY(foreignOptions({{QStringLiteral("kind"), QStringLiteral("background")},
                                {QStringLiteral("once"), true},
                                {QStringLiteral("accuracy"), QStringLiteral("choice")},
                                {QStringLiteral("preciseDefault"), true},
                                {QStringLiteral("request"), QStringLiteral("0123456789abcdef")},
                                {QStringLiteral("extra"), QStringLiteral("dropped")}},
                               &out));
        QCOMPARE(out.value(QStringLiteral("kind")).toString(), QStringLiteral("background"));
        QVERIFY(out.value(QStringLiteral("once")).toBool());
        QCOMPARE(out.value(QStringLiteral("accuracy")).toString(), QStringLiteral("choice"));
        QVERIFY(out.value(QStringLiteral("preciseDefault")).toBool());
        QVERIFY(!out.contains(QStringLiteral("extra")));
        QVERIFY(!out.contains(QStringLiteral("request")));

        QVERIFY(!foreignOptions({{QStringLiteral("kind"), QStringLiteral("always")}}, &out));
        QVERIFY(!foreignOptions({{QStringLiteral("accuracy"), QStringLiteral("fine")}}, &out));
        QVERIFY(!foreignOptions({{QStringLiteral("once"), QStringLiteral("yes")}}, &out));
    }
};

QTEST_GUILESS_MAIN(TestPermissionAuth)
#include "test_permissionauth.moc"
