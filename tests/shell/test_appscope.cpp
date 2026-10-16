#include <QtTest>

#include "appscope.h"

class TestAppScope : public QObject {
    Q_OBJECT

    const QString shell = QStringLiteral(
        "/user.slice/user-1000.slice/user@1000.service/marathon.slice/marathon-shell-812.scope");

  private slots:
    void flatpakScope() {
        QCOMPARE(AppScope::unitForCgroup("/user.slice/user-1000.slice/user@1000.service/app.slice/"
                                         "app-flatpak-de.haeckerfelix.Shortwave-2104.scope",
                                         shell),
                 QStringLiteral("app-flatpak-de.haeckerfelix.Shortwave-2104.scope"));
    }

    void launcherScope() {
        QCOMPARE(AppScope::unitForCgroup("/user.slice/user-1000.slice/user@1000.service/app.slice/"
                                         "app-gnome-org.gnome.Maps-3301.scope",
                                         shell),
                 QStringLiteral("app-gnome-org.gnome.Maps-3301.scope"));
    }

    void shellChildIsNotScoped() {
        QVERIFY(AppScope::unitForCgroup(shell, shell).isEmpty());
    }

    void marathonAppCgroupIsNotScoped() {
        QVERIFY(AppScope::unitForCgroup("/user.slice/user-1000.slice/user@1000.service/"
                                        "marathon.slice/marathon-apps/marathon-app-notes",
                                        shell)
                    .isEmpty());
    }

    // A dev shell started from a terminal lives in the terminal's scope.
    void neverTheScopeTheShellIsIn() {
        const QString terminal = "/user.slice/user-1000.slice/user@1000.service/app.slice/"
                                 "app-gnome-org.gnome.Ptyxis-77.scope";
        QVERIFY(AppScope::unitForCgroup(terminal, terminal + "/vte-spawn").isEmpty());
        QVERIFY(AppScope::unitForCgroup(terminal, terminal).isEmpty());
    }

    void serviceIsNotAScope() {
        QVERIFY(
            AppScope::unitForCgroup(
                "/user.slice/user-1000.slice/user@1000.service/app.slice/app-foo.service", shell)
                .isEmpty());
        QVERIFY(AppScope::unitForCgroup(QString(), shell).isEmpty());
    }

    void readsTheUnifiedLine() {
        QCOMPARE(AppScope::cgroupFromProcFile("0::/user.slice/app-x-1.scope\n"),
                 QStringLiteral("/user.slice/app-x-1.scope"));
        QCOMPARE(AppScope::cgroupFromProcFile("1:name=systemd:/a\n0::/b\n"), QStringLiteral("/b"));
        QVERIFY(AppScope::cgroupFromProcFile("").isEmpty());
    }
};

QTEST_GUILESS_MAIN(TestAppScope)
#include "test_appscope.moc"
