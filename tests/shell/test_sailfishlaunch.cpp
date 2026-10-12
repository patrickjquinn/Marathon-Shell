#include <QtTest>

#include "sailfishlaunch.h"

class TestSailfishLaunch : public QObject {
    Q_OBJECT

  private slots:
    void sailfishAppsRunUnderTheKeelHost() {
        const QVariantMap app{{"id", "harbour-foo"}, {"sailfish", true}};
        QCOMPARE(SailfishLaunch::command(app, QStringLiteral("sailfish-qml harbour-foo")),
                 QStringLiteral("marathon-keel-host --app-id harbour-foo -- sailfish-qml harbour-foo"));
    }
    void sailjailPermissionsReachTheHost() {
        const QVariantMap app{{"id", "harbour-foo"},
                              {"sailfish", true},
                              {"sailjailPermissions", QStringList{"Internet", "Pictures"}},
                              {"sailjailOrganization", "org.example"},
                              {"sailjailApplication", "foo"}};
        QCOMPARE(SailfishLaunch::command(app, QStringLiteral("harbour-foo")),
                 QStringLiteral("marathon-keel-host --app-id harbour-foo --sailjail Internet,Pictures "
                                "--org org.example --app foo -- harbour-foo"));
    }
    void otherAppsRunAsTheyAre() {
        const QVariantMap app{{"id", "foot"}};
        QCOMPARE(SailfishLaunch::command(app, QStringLiteral("foot")), QStringLiteral("foot"));
    }
};

QTEST_GUILESS_MAIN(TestSailfishLaunch)
#include "test_sailfishlaunch.moc"
