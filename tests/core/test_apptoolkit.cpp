#include <QtTest>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>

#include "marathonappregistry.h"
#include "marathonappscanner.h"

class TestAppToolkit : public QObject {
    Q_OBJECT

    QTemporaryDir home;

    void writeApp(const QString &id, const QString &toolkit) {
        const QString dir = home.path() + "/system-apps/" + id;
        QDir().mkpath(dir);
        QJsonObject m{{"id", id},
                      {"name", id},
                      {"version", "1.0"},
                      {"entryPoint", "Main.qml"},
                      {"icon", "icon.svg"}};
        if (!toolkit.isEmpty())
            m.insert("toolkit", toolkit);
        QFile f(dir + "/manifest.json");
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(QJsonDocument(m).toJson());
        QFile qml(dir + "/Main.qml");
        QVERIFY(qml.open(QIODevice::WriteOnly));
        qml.write("import QtQuick\nItem {}\n");
    }

  private slots:
    void initTestCase() {
        qputenv("HOME", home.path().toUtf8());
        qputenv("MARATHON_APPS_DIR", (home.path() + "/system-apps").toUtf8());
    }

    void defaultsToKeel() {
        writeApp("plain", QString());
        MarathonAppRegistry registry;
        MarathonAppScanner  scanner(&registry);
        QVERIFY(scanner.scanSingleApp("plain"));
        QCOMPARE(registry.getApp("plain").value("toolkit").toString(), QStringLiteral("keel"));
    }

    void readsLegacyToolkit() {
        writeApp("legacy", "marathonui");
        MarathonAppRegistry registry;
        MarathonAppScanner  scanner(&registry);
        QVERIFY(scanner.scanSingleApp("legacy"));
        QCOMPARE(registry.getApp("legacy").value("toolkit").toString(),
                 QStringLiteral("marathonui"));
    }
};

QTEST_GUILESS_MAIN(TestAppToolkit)
#include "test_apptoolkit.moc"
