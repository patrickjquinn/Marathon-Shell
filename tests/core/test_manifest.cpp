#include <QtTest>
#include <QTemporaryDir>

#include "marathonmanifest.h"

class TestManifest : public QObject {
    Q_OBJECT

  private slots:
    void lintReportsRulesAndPaths() {
        QTemporaryDir root;
        const QString dir = root.path() + "/com.example.app";
        QVERIFY(QDir().mkpath(dir));
        QFile f(dir + "/manifest.json");
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(R"({"manifestVersion": 1, "id": "com.example.app", "name": "App",
                   "version": "1.0.0", "entryPoint": "App.qml", "icon": "icon.svg",
                   "author": "Example", "permissions": ["camera"],
                   "testedOn": {"widths": [540], "inputModes": ["touch"]},
                   "dataLifecycle": {"appData": "remove", "cache": "remove"}})");
        f.close();

        const QList<MarathonManifest::Finding> findings = MarathonManifest::lint(dir, false);
        QStringList                            seen;
        for (const MarathonManifest::Finding &finding : findings) {
            QVERIFY(finding.error);
            seen << finding.rule + ' ' + finding.path;
        }
        QCOMPARE(
            seen,
            QStringList({"permission-reason /permissions/0", "files /entryPoint", "files /icon"}));
    }

    void lintRefusesAMissingApp() {
        const QList<MarathonManifest::Finding> findings =
            MarathonManifest::lint(QStringLiteral("/nonexistent/app.marathon"), false);
        QCOMPARE(findings.size(), 1);
        QCOMPARE(findings.first().rule, QStringLiteral("package"));
    }

    void vocabularyCarriesWording() {
        bool sawSystem = false;
        for (const MarathonManifest::Permission &p : MarathonManifest::permissions()) {
            QVERIFY(!p.description.isEmpty());
            if (p.name == QLatin1String("system"))
                sawSystem = p.restricted && p.sensitive;
        }
        QVERIFY(sawSystem);
    }
};

QTEST_GUILESS_MAIN(TestManifest)
#include "test_manifest.moc"
