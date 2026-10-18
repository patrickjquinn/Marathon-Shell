#include <QTest>
#include <QSignalSpy>
#include <QStandardPaths>
#include "../../shell/src/models/notificationmodel.h"
#include "../../shell/src/dbus/notificationdatabase.h"

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

        // addNotification() is the transient (model-only) path: negative ids,
        // disjoint from database-backed ones (see NotificationModel).
        QVERIFY(id < 0);
        QCOMPARE(model.count(), 1);
        QCOMPARE(model.unreadCount(), 1);
        QCOMPARE(countSpy.count(), 1);
        QCOMPARE(unreadSpy.count(), 1);
        QCOMPARE(addedSpy.count(), 1);
        QCOMPARE(addedSpy.first().first().toInt(), id);
    }

    // === CONTRACT: transient IDs are unique and never collide with persisted ones ===

    void transientIdsAreUnique() {
        NotificationModel model;
        int               id1 = model.addNotification("a", "T1", "B1", "i");
        int               id2 = model.addNotification("a", "T2", "B2", "i");
        int               id3 = model.addNotification("b", "T3", "B3", "i");

        QVERIFY(id1 < 0 && id2 < 0 && id3 < 0);
        QVERIFY(id2 < id1);
        QVERIFY(id3 < id2);
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

    // === CONTRACT: the "value" hint makes a row ongoing, with its progress ===

    void valueHintMakesItOngoing() {
        NotificationModel model;
        model.addNotificationWithId(1, "a", "Plain", "B", "i");
        model.addNotificationWithId(2, "a", "Known", "B", "i", {}, {}, {{"value", 42}});
        model.addNotificationWithId(3, "a", "Unknown", "B", "i", {}, {}, {{"value", -1}});
        const auto at = [&](int id, int role) {
            for (int row = 0; row < model.rowCount(); ++row) {
                const QModelIndex idx = model.index(row);
                if (model.data(idx, NotificationModel::IdRole).toInt() == id)
                    return model.data(idx, role);
            }
            return QVariant();
        };
        QCOMPARE(at(1, NotificationModel::OngoingRole).toBool(), false);
        QCOMPARE(at(2, NotificationModel::OngoingRole).toBool(), true);
        QCOMPARE(at(2, NotificationModel::ProgressRole).toReal(), 0.42);
        QCOMPARE(at(3, NotificationModel::OngoingRole).toBool(), true);
        QCOMPARE(at(3, NotificationModel::ProgressRole).toReal(), -1.0);
        QCOMPARE(model.roleId("progress"), int(NotificationModel::ProgressRole));
    }

    // === CONTRACT: an update rewrites the row where it is, quietly ===

    void updateKeepsThePlaceTimeAndReadState() {
        NotificationModel model;
        model.addNotificationWithId(1, "a", "Downloading", "0%", "i", {}, {}, {{"value", 0}});
        model.addNotificationWithId(2, "b", "Newer", "B", "i");
        model.markAsRead(1);
        const qint64 time = model.getNotification(1)->timestamp();
        QSignalSpy   added(&model, &NotificationModel::notificationAdded);
        QSignalSpy   changed(&model, &NotificationModel::dataChanged);

        QVERIFY(model.updateNotification(1, "Downloading", "50%", "i", {}, {{"value", 50}}));

        QCOMPARE(model.count(), 2);
        QCOMPARE(model.data(model.index(1), NotificationModel::IdRole).toInt(), 1);
        QCOMPARE(model.data(model.index(1), NotificationModel::BodyRole).toString(),
                 QString("50%"));
        QCOMPARE(model.data(model.index(1), NotificationModel::ProgressRole).toReal(), 0.5);
        QCOMPARE(model.getNotification(1)->timestamp(), time);
        QVERIFY(model.getNotification(1)->isRead());
        QCOMPARE(changed.count(), 1);
        QCOMPARE(added.count(), 0);
        QVERIFY(!model.updateNotification(99, "T", "B", "i", {}, {}));
    }

    // === CONTRACT: clearing the Hub leaves what is still running ===

    void dismissAllKeepsOngoing() {
        NotificationModel model;
        model.addNotificationWithId(1, "a", "Done", "B", "i");
        model.addNotificationWithId(2, "a", "Running", "B", "i", {}, {}, {{"value", 10}});
        QSignalSpy dismissed(&model, &NotificationModel::notificationDismissed);

        model.dismissAllNotifications();

        QCOMPARE(model.count(), 1);
        QVERIFY(model.getNotification(2));
        QVERIFY(!model.getNotification(1));
        QCOMPARE(dismissed.count(), 1);
        QCOMPARE(dismissed.first().first().toInt(), 1);
    }

    // === CONTRACT: progress from the last session is gone on reload ===

    void reloadDropsProgress() {
        QStandardPaths::setTestModeEnabled(true);
        NotificationDatabase db;
        QVERIFY(db.initialize());
        db.clearAll();
        NotificationDatabase::NotificationRecord r{};
        r.appId          = "a";
        r.title          = "Done";
        r.timestamp      = QDateTime::currentDateTime();
        const uint done  = db.saveNotification(r);
        r.title          = "Running";
        r.metadata       = {{"value", 30}};
        const uint stale = db.saveNotification(r);

        NotificationModel model;
        model.loadFromDatabase(&db);

        QVERIFY(model.getNotification(int(done)));
        QVERIFY(!model.getNotification(int(stale)));
        QCOMPARE(db.getNotifications().size(), 1);
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
