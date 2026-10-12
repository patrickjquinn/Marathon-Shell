#include <QTest>
#include <QSignalSpy>
#include <QStandardPaths>
#include "freedesktopnotifications.h"
#include "notificationdatabase.h"
#include "notificationmodel.h"
#include "powermanagercpp.h"

bool PowerManagerCpp::acquireWakelock(const QString &) {
    return true;
}
bool PowerManagerCpp::releaseWakelock(const QString &) {
    return true;
}

class TestFreedesktopNotify : public QObject {
    Q_OBJECT

    static bool hasAction(const QVariantList &actions, const QString &key) {
        for (const QVariant &a : actions)
            if (a.toMap().value("key").toString() == key)
                return true;
        return false;
    }

  private slots:
    void initTestCase() {
        QStandardPaths::setTestModeEnabled(true);
    }

    void notifyCarriesActionsIntoMap() {
        NotificationDatabase db;
        db.initialize();
        NotificationModel        model;
        FreedesktopNotifications fdn(&db, &model, nullptr);
        QSignalSpy               added(&model, &NotificationModel::notificationAdded);

        QVariantMap              hints;
        hints["x-kde-reply-placeholder-text"] = "Reply to Ada";
        fdn.Notify("chat", 0, "", "Ada", "Hi", {"default", "Open", "inline-reply", "Reply"}, hints,
                   -1);

        QCOMPARE(added.count(), 1);
        Notification *n = model.getNotification(added.first().first().toInt());
        QVERIFY(n);
        const QVariantMap map = n->toMap();
        QVERIFY(hasAction(map.value("actions").toList(), "inline-reply"));
        QVERIFY(hasAction(map.value("actions").toList(), "default"));
        QCOMPARE(map.value("replyPlaceholder").toString(), QString("Reply to Ada"));
    }

    void replyEmitsNotificationReplied() {
        NotificationDatabase db;
        db.initialize();
        NotificationModel        model;
        FreedesktopNotifications fdn(&db, &model, nullptr);
        QSignalSpy               replied(&fdn, &FreedesktopNotifications::NotificationReplied);
        QSignalSpy               invoked(&fdn, &FreedesktopNotifications::ActionInvoked);

        fdn.InvokeReply(7, "On my way");

        QCOMPARE(replied.count(), 1);
        QCOMPARE(replied.first().at(0).toUInt(), 7u);
        QCOMPARE(replied.first().at(1).toString(), QString("On my way"));
        QCOMPARE(invoked.count(), 0);
    }
};

QTEST_MAIN(TestFreedesktopNotify)
#include "test_freedesktopnotify.moc"
