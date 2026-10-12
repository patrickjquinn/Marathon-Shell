#include <QtTest>

#include "sailjail.h"

class TestSailjail : public QObject {
    Q_OBJECT

    static QStringList args(const QStringList &perms) {
        return Sailjail::bwrapArgs(perms, QStringLiteral("org.example"), QStringLiteral("foo"),
                                   QStringLiteral("/home/user"), QStringLiteral("/run/user/1000"));
    }
    static bool hasBind(const QStringList &a, const QString &flag, const QString &path) {
        for (int i = 0; i + 2 < a.size(); ++i)
            if (a.at(i) == flag && a.at(i + 1) == path && a.at(i + 2) == path)
                return true;
        return false;
    }

  private slots:
    void noInternetMeansNoNetwork() {
        QVERIFY(args({}).contains(QStringLiteral("--unshare-net")));
        QVERIFY(!args({QStringLiteral("Internet")}).contains(QStringLiteral("--unshare-net")));
    }
    void homeIsPrivateButTheAppsOwnDirsAreWritable() {
        const QStringList a = args({});
        QVERIFY(hasBind(a, "--tmpfs", "/home/user") || a.contains("/home/user"));
        QVERIFY(hasBind(a, "--bind", "/home/user/.local/share/org.example/foo"));
        QVERIFY(hasBind(a, "--bind", "/home/user/.cache/org.example/foo"));
        QVERIFY(hasBind(a, "--bind", "/home/user/.config/org.example/foo"));
        QVERIFY(!hasBind(a, "--bind", "/home/user/Pictures"));
    }
    void mediaPermissionsBindTheirFolders() {
        const QStringList a = args({"Pictures", "Music", "Videos", "Documents", "Downloads"});
        for (const char *dir : {"Pictures", "Music", "Videos", "Documents", "Downloads"})
            QVERIFY2(hasBind(a, "--bind-try", QStringLiteral("/home/user/") + QLatin1String(dir)), dir);
    }
    void systemIsReadOnlyAndRuntimeDirShared() {
        const QStringList a = args({});
        QVERIFY(hasBind(a, "--ro-bind", "/usr"));
        QVERIFY(hasBind(a, "--bind", "/run/user/1000"));
        QVERIFY(a.contains(QStringLiteral("--die-with-parent")));
        const int dev = a.indexOf(QStringLiteral("--dev"));
        QVERIFY(dev >= 0);
        QCOMPARE(a.at(dev + 1), QStringLiteral("/dev"));
    }
    void cameraExposesVideoDevices() {
        QVERIFY(args({"Camera"}).contains(QStringLiteral("/dev/video0")));
        QVERIFY(!args({}).contains(QStringLiteral("/dev/video0")));
    }
    void unknownPermissionsAreIgnored() {
        QCOMPARE(args({"NoSuchThing"}), args({}));
    }
};

QTEST_GUILESS_MAIN(TestSailjail)
#include "test_sailjail.moc"
