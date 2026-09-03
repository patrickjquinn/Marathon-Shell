#include <QTest>
#include <QSignalSpy>
#include "../../shell/src/models/notificationmodel.h"

class TestNotificationModel : public QObject {
    Q_OBJECT

  private slots:

    // === CONTRACT: Empty model ===

    void emptyModelState() {
        NotificationModel model;
        QCOMPARE(model.count(), 0);
        QCOMPARE(model.unreadCount(), 0);
        QCOMPARE(model.rowCount(), 0);
        QVERIFY(!model.getNotification(1));
    }

    // === CONTRACT: addNotification inserts at position 0 (newest first) ===

    void addNotificationPrependsAndSignals() {
        NotificationModel model;
        QSignalSpy        countSpy(&model, &NotificationModel::countChanged);
        QSignalSpy        unreadSpy(&model, &NotificationModel::unreadCountChanged);
        QSignalSpy        addedSpy(&model, &NotificationModel::notificationAdded);

        int               id = model.addNotification("com.app", "Title", "Body", "icon");

        QVERIFY(id > 0);
        QCOMPARE(model.count(), 1);
        QCOMPARE(model.unreadCount(), 1);
        QCOMPARE(countSpy.count(), 1);
        QCOMPARE(unreadSpy.count(), 1);
        QCOMPARE(addedSpy.count(), 1);
        QCOMPARE(addedSpy.first().first().toInt(), id);
    }

    // === CONTRACT: IDs are monotonically increasing ===

    void idsAreIncreasing() {
        NotificationModel model;
        int               id1 = model.addNotification("a", "T1", "B1", "i");
        int               id2 = model.addNotification("a", "T2", "B2", "i");
        int               id3 = model.addNotification("b", "T3", "B3", "i");

        QVERIFY(id2 > id1);
        QVERIFY(id3 > id2);
    }

    // === CONTRACT: Newest notification is at index 0 ===

    void newestFirst() {
        NotificationModel model;
        model.addNotification("a", "First", "B", "i");
        int         id2 = model.addNotification("a", "Second", "B", "i");

        QModelIndex idx0 = model.index(0);
        QCOMPARE(model.data(idx0, NotificationModel::TitleRole).toString(), QString("Second"));
        QCOMPARE(model.data(idx0, NotificationModel::IdRole).toInt(), id2);
    }

    // === CONTRACT: markAsRead reduces unread count ===

    void markAsRead() {
        NotificationModel model;
        int               id = model.addNotification("a", "T", "B", "i");

        QCOMPARE(model.unreadCount(), 1);

        QSignalSpy unreadSpy(&model, &NotificationModel::unreadCountChanged);
        model.markAsRead(id);

        QCOMPARE(model.unreadCount(), 0);
        QCOMPARE(unreadSpy.count(), 1);

        Notification *n = model.getNotification(id);
        QVERIFY(n);
        QVERIFY(n->isRead());
    }

    // === CONTRACT: markAsRead on already-read is a no-op ===

    void markAsReadIdempotent() {
        NotificationModel model;
        int               id = model.addNotification("a", "T", "B", "i");

        model.markAsRead(id);
        QSignalSpy unreadSpy(&model, &NotificationModel::unreadCountChanged);
        model.markAsRead(id);

        QCOMPARE(unreadSpy.count(), 0);
    }

    // === CONTRACT: dismissNotification removes and signals ===

    void dismissNotification() {
        NotificationModel model;
        int               id = model.addNotification("a", "T", "B", "i");

        QSignalSpy        dismissSpy(&model, &NotificationModel::notificationDismissed);
        QSignalSpy        countSpy(&model, &NotificationModel::countChanged);

        model.dismissNotification(id);

        QCOMPARE(model.count(), 0);
        QVERIFY(!model.getNotification(id));
        QCOMPARE(dismissSpy.count(), 1);
        QCOMPARE(dismissSpy.first().first().toInt(), id);
        QCOMPARE(countSpy.count(), 1);
    }

    // === CONTRACT: dismissNotification on nonexistent is a no-op ===

    void dismissNonexistentNoop() {
        NotificationModel model;
        model.addNotification("a", "T", "B", "i");

        model.dismissNotification(9999);
        QCOMPARE(model.count(), 1);
    }

    // === CONTRACT: dismissAllNotifications clears everything ===

    void dismissAll() {
        NotificationModel model;
        model.addNotification("a", "T1", "B", "i");
        model.addNotification("b", "T2", "B", "i");
        model.addNotification("c", "T3", "B", "i");

        model.dismissAllNotifications();

        QCOMPARE(model.count(), 0);
        QCOMPARE(model.unreadCount(), 0);
    }

    // === CONTRACT: dismissAll on empty is a no-op (no crash) ===

    void dismissAllEmpty() {
        NotificationModel model;
        model.dismissAllNotifications();
        QCOMPARE(model.count(), 0);
    }

    // === CONTRACT: unreadCount tracks correctly across operations ===

    void unreadCountTracking() {
        NotificationModel model;
        int               id1 = model.addNotification("a", "T1", "B", "i");
        int               id2 = model.addNotification("a", "T2", "B", "i");
        model.addNotification("a", "T3", "B", "i");

        QCOMPARE(model.unreadCount(), 3);

        model.markAsRead(id1);
        QCOMPARE(model.unreadCount(), 2);

        model.dismissNotification(id2);
        QCOMPARE(model.unreadCount(), 1);
    }

    // === CONTRACT: data() returns correct fields ===

    void dataRoles() {
        NotificationModel model;
        int               id = model.addNotification("com.app", "Title", "Body text", "app-icon");

        QModelIndex       idx = model.index(0);
        QCOMPARE(model.data(idx, NotificationModel::IdRole).toInt(), id);
        QCOMPARE(model.data(idx, NotificationModel::AppIdRole).toString(), QString("com.app"));
        QCOMPARE(model.data(idx, NotificationModel::TitleRole).toString(), QString("Title"));
        QCOMPARE(model.data(idx, NotificationModel::BodyRole).toString(), QString("Body text"));
        QCOMPARE(model.data(idx, NotificationModel::IconRole).toString(), QString("app-icon"));
        QVERIFY(model.data(idx, NotificationModel::TimestampRole).toLongLong() > 0);
        QCOMPARE(model.data(idx, NotificationModel::IsReadRole).toBool(), false);
    }

    // === CONTRACT: roleId lookup ===

    void roleIdLookup() {
        NotificationModel model;
        QCOMPARE(model.roleId("title"), static_cast<int>(NotificationModel::TitleRole));
        QCOMPARE(model.roleId("body"), static_cast<int>(NotificationModel::BodyRole));
        QCOMPARE(model.roleId("nonexistent"), -1);
    }

    // === CONTRACT: roleNames covers all roles ===

    void roleNamesComplete() {
        NotificationModel model;
        auto              roles = model.roleNames();
        QVERIFY(roles.contains(NotificationModel::IdRole));
        QVERIFY(roles.contains(NotificationModel::AppIdRole));
        QVERIFY(roles.contains(NotificationModel::TitleRole));
        QVERIFY(roles.contains(NotificationModel::BodyRole));
        QVERIFY(roles.contains(NotificationModel::IconRole));
        QVERIFY(roles.contains(NotificationModel::TimestampRole));
        QVERIFY(roles.contains(NotificationModel::IsReadRole));
    }
};

QTEST_MAIN(TestNotificationModel)
#include "test_notificationmodel.moc"
