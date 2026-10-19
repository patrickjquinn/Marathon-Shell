#include <QSignalSpy>
#include <QTest>

#include "foregroundapp.h"
#include "sessionstore.h"
#include "uistore.h"

class TestForegroundApp : public QObject {
    Q_OBJECT

  private slots:
    void followsTheAppInFront() {
        UIStore       ui;
        SessionStore  session;
        session.setIsLocked(false);
        ForegroundApp front(&ui, &session);
        QSignalSpy    changed(&front, &ForegroundApp::changed);
        QCOMPARE(front.appId(), QString());

        ui.openApp(QStringLiteral("files"), QStringLiteral("Files"), QString());
        QTRY_COMPARE(front.appId(), QStringLiteral("files"));
        ui.minimizeApp();
        QTRY_COMPARE(front.appId(), QString());

        // From home, restoring another app passes through the last one's id.
        ui.restoreApp(QStringLiteral("markor"), QStringLiteral("Markor"), QString());
        QTRY_COMPARE(front.appId(), QStringLiteral("markor"));
        QTest::qWait(20);
        QCOMPARE(changed.size(), 3);
        QCOMPARE(changed.at(2).at(0).toString(), QStringLiteral("markor"));
    }

    void isEmptyWhileLocked() {
        UIStore       ui;
        SessionStore  session;
        session.setIsLocked(false);
        ForegroundApp front(&ui, &session);
        ui.openApp(QStringLiteral("files"), QStringLiteral("Files"), QString());
        QTRY_COMPARE(front.appId(), QStringLiteral("files"));
        session.setIsLocked(true);
        QTRY_COMPARE(front.appId(), QString());
        session.setIsLocked(false);
        QTRY_COMPARE(front.appId(), QStringLiteral("files"));
    }
};

QTEST_GUILESS_MAIN(TestForegroundApp)
#include "test_foregroundapp.moc"
