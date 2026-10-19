#include <QSignalSpy>
#include <QStandardPaths>
#include <QTest>

#include "marathonappregistry.h"
#include "notificationhandlercpp.h"
#include "notificationmodel.h"
#include "notificationservicecpp.h"

// Tapping a notification shows the app it came from.
class TestNotificationHandler : public QObject {
    Q_OBJECT

  private slots:
    void initTestCase() {
        QStandardPaths::setTestModeEnabled(true);
    }

    // An Android app has no registry entry (its desktop entry is hidden):
    // the shell shows it through its launch service instead of giving up.
    void anAppTheRegistryCannotOpenIsShown() {
        NotificationModel      model;
        NotificationServiceCpp service(&model, nullptr, nullptr, nullptr);
        MarathonAppRegistry    registry;
        NotificationHandlerCpp handler(&service, nullptr, nullptr, &registry);
        QStringList            shown;
        handler.setShowApp([&shown](const QString &appId) {
            shown << appId;
            return true;
        });
        const int id = service.sendNotification(QStringLiteral("waydroid.org.example.chat"),
                                                QStringLiteral("Ann"), QStringLiteral("Hi"));
        handler.handleNotificationClick(id);
        QCOMPARE(shown, QStringList{QStringLiteral("waydroid.org.example.chat")});
    }
};

QTEST_GUILESS_MAIN(TestNotificationHandler)
#include "test_notificationhandler.moc"
