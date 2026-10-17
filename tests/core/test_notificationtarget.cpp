#include <QtTest>

#include "marathonappregistry.h"
#include "notificationtarget.h"

class TestNotificationTarget : public QObject {
    Q_OBJECT

    MarathonAppRegistry registry;

  private slots:
    void initTestCase() {
        registry.registerApp("messages", "Messages", "", 0, "", "", "1", true, {});
        registry.registerApp("notes", "Notes", "", 0, "", "", "1", true, {});
        registry.registerApp("de.haeckerfelix.Shortwave", "Shortwave", "", 2, "", "", "1", false,
                             {});
    }

    void appFromCgroup_data() {
        QTest::addColumn<QString>("cgroup");
        QTest::addColumn<QString>("app");
        const QString user = "0::/user.slice/user-1000.slice/user@1000.service/";
        QTest::newRow("marathon app") << user + "app.slice/marathon-app-notes" << "notes";
        QTest::newRow("marathon app scope")
            << user + "app.slice/marathon-app-notes.scope" << "notes";
        QTest::newRow("flatpak") << user +
                "app.slice/app-flatpak-de.haeckerfelix.Shortwave-41.scope"
                                 << "de.haeckerfelix.Shortwave";
        QTest::newRow("xdg scope")
            << user + "app.slice/app-gnome-org.gnome.Maps-8812.scope" << "org.gnome.Maps";
        QTest::newRow("xdg service")
            << user + "app.slice/app-org.gnome.Maps@a1b2.service" << "org.gnome.Maps";
        QTest::newRow("shell") << user + "marathon.slice/marathon-shell-212919.scope" << "";
        QTest::newRow("session") << "0::/user.slice/user-0.slice/session-c963.scope" << "";
    }

    void appFromCgroup() {
        QFETCH(QString, cgroup);
        QFETCH(QString, app);
        QCOMPARE(NotificationTarget::appFromCgroup(cgroup), app);
    }

    void resolve_data() {
        QTest::addColumn<QStringList>("candidates");
        QTest::addColumn<QString>("app");
        QTest::newRow("registry id") << QStringList{"notes"} << "notes";
        QTest::newRow("desktop file")
            << QStringList{"de.haeckerfelix.Shortwave.desktop"} << "de.haeckerfelix.Shortwave";
        QTest::newRow("display name") << QStringList{"Messages"} << "messages";
        QTest::newRow("case") << QStringList{"NOTES"} << "notes";
        QTest::newRow("first match wins")
            << QStringList{"", "nope", "Shortwave", "notes"} << "de.haeckerfelix.Shortwave";
        QTest::newRow("unknown") << QStringList{"Thunderbird"} << "";
    }

    void resolve() {
        QFETCH(QStringList, candidates);
        QFETCH(QString, app);
        QCOMPARE(NotificationTarget::resolve(candidates, &registry), app);
    }

    void resolveWithoutRegistry() {
        QCOMPARE(NotificationTarget::resolve({"notes"}, nullptr), QString());
    }
};

QTEST_GUILESS_MAIN(TestNotificationTarget)
#include "test_notificationtarget.moc"
