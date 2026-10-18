#include <QTest>
#include <QDBusArgument>
#include <QImage>
#include <QSignalSpy>
#include <QStandardPaths>
#include "freedesktopnotifications.h"
#include "appmodel.h"
#include "marathonappregistry.h"
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

    // A tap can only open an app the notification names by its registry id.
    void notificationsNameTheInstalledApp() {
        NotificationDatabase db;
        db.initialize();
        NotificationModel   model;
        MarathonAppRegistry registry;
        registry.registerApp("messages", "Messages", "", 0, "", "", "1", true, {});
        registry.registerApp("org.gnome.Maps", "Maps", "", 2, "", "", "1", false, {});
        FreedesktopNotifications fdn(&db, &model, nullptr);
        fdn.setAppRegistry(&registry);
        QSignalSpy added(&model, &NotificationModel::notificationAdded);

        const auto appOf = [&](int i) {
            return model.getNotification(added.at(i).first().toInt())->toMap().value("appId");
        };
        fdn.Notify("Messages", 0, "", "Ada", "Hi", {}, {}, -1);
        fdn.Notify("Maps", 0, "", "Turn left", "", {},
                   {{"desktop-entry", QStringLiteral("org.gnome.Maps.desktop")}}, -1);
        fdn.Notify("Thunderbird", 0, "", "Mail", "", {}, {}, -1);

        QCOMPARE(added.count(), 3);
        QCOMPARE(appOf(0).toString(), QString("messages"));
        QCOMPARE(appOf(1).toString(), QString("org.gnome.Maps"));
        QCOMPARE(appOf(2).toString(), QString("Thunderbird"));
    }

    // Waydroid sends desktop-entry waydroid.<package> and the Android app's
    // label as app_name; Android's own apps have no shown desktop entry.
    void androidNotificationsNameTheirApp() {
        NotificationDatabase db;
        db.initialize();
        NotificationModel        model;
        AppModel                 apps;
        apps.addApps({QVariantMap{{"id", "waydroid.org.fdroid.fdroid"},
                                  {"name", "F-Droid"},
                                  {"icon", "f-droid.png"},
                                  {"type", "native"},
                                  {"exec", "waydroid app launch org.fdroid.fdroid"}}});
        FreedesktopNotifications fdn(&db, &model, nullptr);
        fdn.setAppModel(&apps);
        QSignalSpy added(&model, &NotificationModel::notificationAdded);
        const auto appOf = [&](int i) {
            return model.getNotification(added.at(i).first().toInt())->toMap().value("appId");
        };
        fdn.Notify("F-Droid", 0, "", "Updates", "", {},
                   {{"desktop-entry", QStringLiteral("waydroid.org.fdroid.fdroid")}}, -1);
        fdn.Notify("Clock", 0, "", "Alarm", "", {},
                   {{"desktop-entry", QStringLiteral("waydroid.com.android.deskclock")}}, -1);
        fdn.Notify("", 0, "", "Alarm", "", {},
                   {{"desktop-entry", QStringLiteral("waydroid.com.android.deskclock")}}, -1);

        QCOMPARE(added.count(), 3);
        QCOMPARE(appOf(0).toString(), QString("waydroid.org.fdroid.fdroid"));
        QCOMPARE(appOf(1).toString(), QString("Clock"));
        QCOMPARE(appOf(2).toString(), QString("waydroid.com.android.deskclock"));
    }

    static bool stored(NotificationDatabase &db, uint id) {
        const QList<NotificationDatabase::NotificationRecord> records = db.getNotifications();
        for (const auto &r : records)
            if (r.id == id)
                return true;
        return false;
    }

    // Transient (spec): shown, then gone; no Hub row, no record, no sound.
    // Deckard's Android toasts add x-marathon-toast for the bottom toast.
    void transientIsBannerOnly() {
        NotificationDatabase db;
        db.initialize();
        NotificationModel        model;
        FreedesktopNotifications fdn(&db, &model, nullptr);
        QSignalSpy               added(&model, &NotificationModel::notificationAdded);
        QSignalSpy               banners(&fdn, &FreedesktopNotifications::bannerRequested);
        QSignalSpy               toasts(&fdn, &FreedesktopNotifications::toastRequested);
        QSignalSpy               closed(&fdn, &FreedesktopNotifications::NotificationClosed);

        const uint banner = fdn.Notify("chat", 0, "", "Ada", "Hi", {}, {{"transient", true}}, 50);
        const uint toast  = fdn.Notify("Clock", 0, "alarm", "Alarm set for 7:00", "", {},
                                       {{"transient", true}, {"x-marathon-toast", true}}, 50);

        QVERIFY(banner > 0);
        QVERIFY(toast > 0 && toast != banner);
        QCOMPARE(added.count(), 0);
        QVERIFY(!stored(db, banner));
        QVERIFY(!stored(db, toast));
        QCOMPARE(banners.count(), 1);
        QCOMPARE(banners.first().first().toMap().value("id").toUInt(), banner);
        QCOMPARE(banners.first().first().toMap().value("title").toString(), QString("Ada"));
        QCOMPARE(toasts.count(), 1);
        QCOMPARE(toasts.first().first().toMap().value("title").toString(),
                 QString("Alarm set for 7:00"));
        QTRY_COMPARE(closed.count(), 2);
        QCOMPARE(closed.at(0).at(1).toUInt(), 1u);
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

    void userDismissIsPersistedAndSignalled() {
        NotificationDatabase db;
        db.initialize();
        NotificationModel        model;
        FreedesktopNotifications fdn(&db, &model, nullptr);
        QSignalSpy               closed(&fdn, &FreedesktopNotifications::NotificationClosed);

        const uint               id = fdn.Notify("chat", 0, "", "Ada", "Hi", {}, {}, -1);
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

        const uint               a = fdn.Notify("chat", 0, "", "Ada", "1", {}, {}, -1);
        const uint               b = fdn.Notify("chat", 0, "", "Ada", "2", {}, {}, -1);
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

        const uint               id = fdn.Notify("chat", 0, "", "Ada", "Hi", {}, {}, -1);
        fdn.CloseNotification(id);

        QVERIFY(!model.getNotification(int(id)));
        QCOMPARE(closed.count(), 1);
        QCOMPARE(closed.first().at(1).toUInt(), 3u);
    }

    void reloadKeepsTimeAndReadState() {
        NotificationDatabase db;
        db.initialize();
        NotificationModel                        model;
        FreedesktopNotifications                 fdn(&db, &model, nullptr);

        NotificationDatabase::NotificationRecord r{};
        r.appId          = "chat";
        r.title          = "Ada";
        r.body           = "Yesterday";
        r.timestamp      = QDateTime::currentDateTime().addDays(-1);
        const uint old   = db.saveNotification(r);
        const uint fresh = fdn.Notify("chat", 0, "", "Ada", "Now", {}, {}, -1);
        model.markAsRead(int(fresh));

        NotificationModel reloaded;
        reloaded.loadFromDatabase(&db);
        QVERIFY(reloaded.getNotification(int(old)));
        QCOMPARE(reloaded.getNotification(int(old))->timestamp() / 1000,
                 r.timestamp.toSecsSinceEpoch());
        QVERIFY(reloaded.getNotification(int(fresh))->isRead());
    }

    // The Hub keeps it, so it hasn't expired: a Nemo client that heard
    // "expired" forgets the id and its close() sends nothing.
    void iconFollowsTheSpecOrder() {
        NotificationDatabase db;
        db.initialize();
        NotificationModel        model;
        FreedesktopNotifications fdn(&db, &model, nullptr);

        const uint named  = fdn.Notify("chat", 0, "mail-unread", "Ada", "", {}, {}, -1);
        const uint pathed = fdn.Notify("chat", 0, "mail-unread", "Ada", "", {},
                                       {{"image-path", "/tmp/ada.png"}}, -1);

        QCOMPARE(model.getNotification(int(named))->icon(), QString("mail-unread"));
        QCOMPARE(model.getNotification(int(pathed))->icon(), QString("/tmp/ada.png"));
    }

    void actionClosesUnlessResident() {
        NotificationDatabase db;
        db.initialize();
        NotificationModel        model;
        FreedesktopNotifications fdn(&db, &model, nullptr);
        QSignalSpy               invoked(&fdn, &FreedesktopNotifications::ActionInvoked);
        QSignalSpy               closed(&fdn, &FreedesktopNotifications::NotificationClosed);
        const QStringList        actions{"default", "Open", "snooze", "Snooze"};

        const uint               plain = fdn.Notify("chat", 0, "", "Ada", "", actions, {}, -1);
        const uint               resident =
            fdn.Notify("chat", 0, "", "Ada", "", actions, {{"resident", true}}, -1);
        fdn.activate(plain, "snooze");
        fdn.activate(resident, "snooze");
        fdn.activate(resident, "default");

        QCOMPARE(invoked.count(), 3);
        QCOMPARE(invoked.first().at(0).toUInt(), plain);
        QCOMPARE(invoked.first().at(1).toString(), QString("snooze"));
        QVERIFY(!model.getNotification(int(plain)));
        QCOMPARE(closed.count(), 1);
        QCOMPARE(closed.first().at(0).toUInt(), plain);
        QCOMPARE(closed.first().at(1).toUInt(), 2u);
        QVERIFY(model.getNotification(int(resident)));
    }

    // A tap leaves the row for NotificationHandler, which opens the app first.
    void tapLeavesTheRow() {
        NotificationDatabase db;
        db.initialize();
        NotificationModel        model;
        FreedesktopNotifications fdn(&db, &model, nullptr);

        const uint id = fdn.Notify("chat", 0, "", "Ada", "", {"default", "Open"}, {}, -1);
        fdn.activate(id, "default");

        QVERIFY(model.getNotification(int(id)));
    }

    void actionsReachTheHub() {
        NotificationDatabase db;
        db.initialize();
        NotificationModel        model;
        FreedesktopNotifications fdn(&db, &model, nullptr);

        fdn.Notify("chat", 0, "", "Ada", "", {"call-start", "Call"}, {{"action-icons", true}}, -1);
        const QModelIndex row = model.index(0, 0);

        QCOMPARE(model.data(row, NotificationModel::ActionsRole).toList().size(), 1);
        QVERIFY(model.data(row, NotificationModel::ActionIconsRole).toBool());
        QVERIFY(model.roleNames().value(NotificationModel::ActionsRole) == "actions");
    }

    // The banner queue lets a critical one go first.
    void urgencyReachesTheBanner() {
        NotificationDatabase db;
        db.initialize();
        NotificationModel        model;
        FreedesktopNotifications fdn(&db, &model, nullptr);

        const uint               normal = fdn.Notify("chat", 0, "", "Ada", "", {}, {}, -1);
        const uint               critical =
            fdn.Notify("chat", 0, "", "Ada", "", {}, {{"urgency", QVariant::fromValue(uchar(2))}}, -1);

        QCOMPARE(model.getNotification(int(normal))->toMap().value("urgency").toInt(), 1);
        QCOMPARE(model.getNotification(int(critical))->toMap().value("urgency").toInt(), 2);
    }

    // The banner falls back to the category's icon, also after a restart.
    void categoryIsKept() {
        NotificationDatabase db;
        db.initialize();
        NotificationModel        model;
        FreedesktopNotifications fdn(&db, &model, nullptr);

        const uint               id =
            fdn.Notify("mail", 0, "", "Ada", "", {}, {{"category", "email.arrived"}}, -1);
        NotificationModel reloaded;
        reloaded.loadFromDatabase(&db);

        QCOMPARE(model.getNotification(int(id))->toMap().value("category").toString(),
                 QString("email.arrived"));
        QCOMPARE(reloaded.getNotification(int(id))->toMap().value("category").toString(),
                 QString("email.arrived"));
    }

    // Raw pixels only arrive as a QDBusArgument, so this goes over a bus.
    void imageDataBecomesTheIcon() {
        if (!QDBusConnection::sessionBus().isConnected())
            QSKIP("needs a session bus");
        NotificationDatabase db;
        db.initialize();
        NotificationModel        model;
        FreedesktopNotifications fdn(&db, &model, nullptr);
        QDBusConnection          server =
            QDBusConnection::connectToBus(QDBusConnection::SessionBus, "notification-server");
        QVERIFY(server.registerObject("/org/freedesktop/Notifications", &fdn,
                                      QDBusConnection::ExportAllSlots));
        QSignalSpy added(&model, &NotificationModel::notificationAdded);

        // image-data's (iiibiiay): 2x2 RGBA, all red.
        QDBusArgument pixels;
        pixels.beginStructure();
        pixels << 2 << 2 << 8 << true << 8 << 4 << QByteArray::fromHex("ff0000ff").repeated(4);
        pixels.endStructure();
        QDBusMessage call =
            QDBusMessage::createMethodCall(server.baseService(), "/org/freedesktop/Notifications",
                                           "org.freedesktop.Notifications", "Notify");
        call << QString("chat") << 0u << QString("mail-unread") << QString("Ada") << QString()
             << QStringList() << QVariantMap{{"image-data", QVariant::fromValue(pixels)}} << -1;
        QDBusConnection::sessionBus().asyncCall(call);

        QTRY_COMPARE(added.count(), 1);
        const QString icon = model.getNotification(added.first().first().toInt())->icon();
        const QString prefix("data:image/png;base64,");
        QVERIFY(icon.startsWith(prefix));
        const QImage decoded =
            QImage::fromData(QByteArray::fromBase64(icon.mid(prefix.size()).toLatin1()));
        QCOMPARE(decoded.size(), QSize(2, 2));
        QCOMPARE(decoded.pixelColor(1, 1), QColor(Qt::red));
        QDBusConnection::disconnectFromBus("notification-server");
    }

    void timeoutDoesNotSignalClosed() {
        NotificationDatabase db;
        db.initialize();
        NotificationModel        model;
        FreedesktopNotifications fdn(&db, &model, nullptr);
        QSignalSpy               closed(&fdn, &FreedesktopNotifications::NotificationClosed);

        const uint               id = fdn.Notify("chat", 0, "", "Ada", "Hi", {}, {}, 20);
        QTest::qWait(100);

        QCOMPARE(closed.count(), 0);
        QVERIFY(model.getNotification(int(id)));
        fdn.CloseNotification(id);
        QCOMPARE(closed.count(), 1);
    }

    void replacingDoesNotSignalClosed() {
        NotificationDatabase db;
        db.initialize();
        NotificationModel        model;
        FreedesktopNotifications fdn(&db, &model, nullptr);
        QSignalSpy               closed(&fdn, &FreedesktopNotifications::NotificationClosed);

        const uint               id = fdn.Notify("chat", 0, "", "Ada", "Hi", {}, {}, -1);
        fdn.Notify("chat", id, "", "Ada", "Hi again", {}, {}, -1);

        QCOMPARE(closed.count(), 0);
    }

    // The "value" hint, 0-100: an ongoing row whose updates keep its id.
    void progressUpdatesTheRowInPlace() {
        NotificationDatabase db;
        db.initialize();
        NotificationModel        model;
        FreedesktopNotifications fdn(&db, &model, nullptr);
        QSignalSpy               added(&model, &NotificationModel::notificationAdded);

        const uint id = fdn.Notify("dl", 0, "", "Downloading", "0%", {}, {{"value", 0}}, -1);
        QCOMPARE(fdn.Notify("dl", id, "", "Downloading", "60%", {}, {{"value", 60}}, -1), id);

        QCOMPARE(added.count(), 1);
        QCOMPARE(model.count(), 1);
        const QVariantMap n = model.getNotification(int(id))->toMap();
        QCOMPARE(n.value("body").toString(), QString("60%"));
        QCOMPARE(n.value("ongoing").toBool(), true);
        QCOMPARE(n.value("progress").toReal(), 0.6);

        // Finishing is a new notification, with its banner.
        const uint done = fdn.Notify("dl", id, "", "Downloaded", "", {}, {}, -1);
        QVERIFY(done != id);
        QCOMPARE(added.count(), 2);
        QCOMPARE(model.count(), 1);
        QVERIFY(!model.getNotification(int(done))->ongoing());
    }

    // A sender that leaves the bus can't finish its job: its progress goes.
    void progressLeavesWithItsSender() {
        if (!QDBusConnection::sessionBus().isConnected())
            QSKIP("needs a session bus");
        NotificationDatabase db;
        db.initialize();
        NotificationModel        model;
        FreedesktopNotifications fdn(&db, &model, nullptr);
        QDBusConnection          server =
            QDBusConnection::connectToBus(QDBusConnection::SessionBus, "progress-server");
        QVERIFY(server.registerObject("/org/freedesktop/Notifications", &fdn,
                                      QDBusConnection::ExportAllSlots));
        QSignalSpy added(&model, &NotificationModel::notificationAdded);
        {
            // The last copy of a connection has to go before it can close.
            QDBusConnection client =
                QDBusConnection::connectToBus(QDBusConnection::SessionBus, "progress-client");
            const auto notify = [&](const QString &title, const QVariantMap &hints) {
                QDBusMessage call = QDBusMessage::createMethodCall(
                    server.baseService(), "/org/freedesktop/Notifications",
                    "org.freedesktop.Notifications", "Notify");
                call << QString("dl") << 0u << QString() << title << QString() << QStringList()
                     << hints << -1;
                client.asyncCall(call);
            };
            notify("Running", {{"value", 10}});
            notify("Finished", {});
            QTRY_COMPARE(added.count(), 2);
        }
        const int running = added.at(0).first().toInt();
        const int done    = added.at(1).first().toInt();

        QDBusConnection::disconnectFromBus("progress-client");

        QTRY_VERIFY(!model.getNotification(running));
        QVERIFY(model.getNotification(done));
        QDBusConnection::disconnectFromBus("progress-server");
    }
};

QTEST_GUILESS_MAIN(TestFreedesktopNotify)
#include "test_freedesktopnotify.moc"
