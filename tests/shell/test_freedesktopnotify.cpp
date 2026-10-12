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

    static bool stored(NotificationDatabase &db, uint id) {
        for (const auto &r : db.getNotifications())
            if (r.id == id)
                return true;
        return false;
    }

    void userDismissIsPersistedAndSignalled() {
        NotificationDatabase db;
        db.initialize();
        NotificationModel        model;
        FreedesktopNotifications fdn(&db, &model, nullptr);
        QSignalSpy               closed(&fdn, &FreedesktopNotifications::NotificationClosed);

        const uint id = fdn.Notify("chat", 0, "", "Ada", "Hi", {}, {}, -1);
        QVERIFY(stored(db, id));
        model.dismissNotification(int(id));

        QVERIFY(!stored(db, id));
        QCOMPARE(closed.count(), 1);
        QCOMPARE(closed.first().at(0).toUInt(), id);
        QCOMPARE(closed.first().at(1).toUInt(), 2u);
    }

    void dismissAllIsPersisted() {
        NotificationDatabase db;
        db.initialize();
        NotificationModel        model;
        FreedesktopNotifications fdn(&db, &model, nullptr);

        const uint a = fdn.Notify("chat", 0, "", "Ada", "1", {}, {}, -1);
        const uint b = fdn.Notify("chat", 0, "", "Ada", "2", {}, {}, -1);
        model.dismissAllNotifications();

        QVERIFY(!stored(db, a));
        QVERIFY(!stored(db, b));
    }

    void closeNotificationRemovesTheRow() {
        NotificationDatabase db;
        db.initialize();
        NotificationModel        model;
        FreedesktopNotifications fdn(&db, &model, nullptr);
        QSignalSpy               closed(&fdn, &FreedesktopNotifications::NotificationClosed);

        const uint id = fdn.Notify("chat", 0, "", "Ada", "Hi", {}, {}, -1);
        fdn.CloseNotification(id);

        QVERIFY(!model.getNotification(int(id)));
        QCOMPARE(closed.count(), 1);
        QCOMPARE(closed.first().at(1).toUInt(), 3u);
    }

    void replacingDoesNotSignalClosed() {
        NotificationDatabase db;
        db.initialize();
        NotificationModel        model;
        FreedesktopNotifications fdn(&db, &model, nullptr);
        QSignalSpy               closed(&fdn, &FreedesktopNotifications::NotificationClosed);

        const uint id = fdn.Notify("chat", 0, "", "Ada", "Hi", {}, {}, -1);
        fdn.Notify("chat", id, "", "Ada", "Hi again", {}, {}, -1);

        QCOMPARE(closed.count(), 0);
    }
};

QTEST_MAIN(TestFreedesktopNotify)
#include "test_freedesktopnotify.moc"
