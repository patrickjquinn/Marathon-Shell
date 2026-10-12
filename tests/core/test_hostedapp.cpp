#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>

#include "hostedapp.h"
#include "keelhost.h"

class TestHostedApp : public QObject {
    Q_OBJECT

    QTemporaryDir runtime;

  private slots:
    void appGetsTheHostEnvironment() {
        KeelHost host(144);
        QVERIFY(host.start(runtime.path()));
        const QString out = runtime.filePath("env.txt");
        HostedApp     app(&host, QStringLiteral("/bin/sh"),
                          {QStringLiteral("-c"),
                           QStringLiteral("echo \"$KEEL_SHELL $KEEL_SHELL_PROTOCOL $KEEL_SHELL_COVER_ENABLED\" > ") + out});
        QSignalSpy    finished(&app, &HostedApp::finished);
        QVERIFY(app.start());
        QTRY_COMPARE(finished.size(), 1);
        QFile f(out);
        QVERIFY(f.open(QIODevice::ReadOnly));
        QCOMPARE(f.readAll().trimmed(), QByteArray("1 1 1"));
    }

    void closeAsksFirstThenStops() {
        KeelHost host(144);
        QVERIFY(host.start(runtime.path()));
        HostedApp  app(&host, QStringLiteral("/bin/sh"),
                       {QStringLiteral("-c"), QStringLiteral("trap '' TERM; sleep 30")}, 200);
        QSignalSpy closeRequested(&host, &KeelHost::CloseRequested);
        QSignalSpy finished(&app, &HostedApp::finished);
        QVERIFY(app.start());
        QTest::qWait(100);
        app.close();
        QCOMPARE(closeRequested.size(), 1);
        QTest::qWait(100);
        QCOMPARE(finished.size(), 0);
        QTRY_COMPARE_WITH_TIMEOUT(finished.size(), 1, 3000);
    }

    void exitingAppFinishes() {
        KeelHost host(144);
        QVERIFY(host.start(runtime.path()));
        HostedApp  app(&host, QStringLiteral("/bin/sh"), {QStringLiteral("-c"), QStringLiteral("exit 3")});
        QSignalSpy finished(&app, &HostedApp::finished);
        QVERIFY(app.start());
        QTRY_COMPARE(finished.size(), 1);
        QCOMPARE(finished.at(0).at(0).toInt(), 3);
    }
};

QTEST_MAIN(TestHostedApp)
#include "test_hostedapp.moc"
