#include "freedesktopnotifications.h"
#include "navigationroutercpp.h"
#include "notificationdatabase.h"
#include "notificationmodel.h"
#include "marathon-shell-native/src/power.cxxqt.h"
#include "updatenotifier.h"

#include <QCoreApplication>
#include <QSettings>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTest>

class FakeBackend : public UpdateBackend {
    Q_OBJECT

  public:
    QStringList calls;

    void        probe() override {}
    void        checkNew() override {}
    void        fetchReleaseInfo(const QString &) override {}
    void        install() override {
        calls << QStringLiteral("install");
    }
    void cancel() override {}
};

class TestUpdateNotifier : public QObject {
    Q_OBJECT

    std::unique_ptr<NotificationDatabase>     db;
    std::unique_ptr<NotificationModel>        model;
    std::unique_ptr<FreedesktopNotifications> server;
    std::unique_ptr<NavigationRouterCpp>      router;
    std::unique_ptr<UpdateService>            updates;
    std::unique_ptr<UpdateNotifier>           notifier;
    FakeBackend                              *backend = nullptr;
    UpdateConditions                          conditions;

    void                                      start(const QString &osVersion) {
        notifier.reset();
        updates.reset();
        backend = new FakeBackend;
        updates = std::make_unique<UpdateService>(
            backend, [this]() { return conditions; }, osVersion, QStringLiteral("boot-a"),
            [] { return QDateTime(QDate(2026, 10, 17), QTime(23, 0)); });
        notifier = std::make_unique<UpdateNotifier>(updates.get(), server.get(), router.get());
    }

    void makeAvailable() {
        start(QStringLiteral("26101701"));
        emit backend->probed(true, QStringLiteral("26101701"));
        updates->checkNow();
        emit backend->checked(QStringLiteral("26101801"));
    }

    // The update notifications in the Hub, newest last.
    QList<QVariantMap> shown() const {
        QList<QVariantMap> out;
        for (int row = 0; row < model->rowCount(); ++row) {
            const int id = model->data(model->index(row, 0), NotificationModel::IdRole).toInt();
            const QVariantMap n = model->getNotification(id)->toMap();
            if (n.value("appId") == QLatin1String(UpdateNotifier::kAppName))
                out.prepend(n);
        }
        return out;
    }

    static QStringList keys(const QVariantMap &n) {
        QStringList out;
        const QVariantList actions = n.value("actions").toList();
        for (const QVariant &a : actions)
            out << a.toMap().value("key").toString();
        return out;
    }

  private slots:
    void initTestCase() {
        QStandardPaths::setTestModeEnabled(true);
        QCoreApplication::setOrganizationName(QStringLiteral("MarathonTest"));
        QCoreApplication::setApplicationName(QStringLiteral("test_updatenotifier"));
        db = std::make_unique<NotificationDatabase>();
        db->initialize();
    }

    void init() {
        QSettings s;
        s.clear();
        s.setValue(QStringLiteral("updates/autoCheck"), false);
        s.setValue(QStringLiteral("updates/autoUpdate"), false);
        conditions = {};
        db->dismissAll();
        model  = std::make_unique<NotificationModel>();
        server = std::make_unique<FreedesktopNotifications>(db.get(), model.get(), nullptr);
        router = std::make_unique<NavigationRouterCpp>();
    }

    void cleanup() {
        notifier.reset();
        updates.reset();
        server.reset();
        model.reset();
    }

    void anAvailableUpdateOffersADownload() {
        makeAvailable();
        const QList<QVariantMap> n = shown();
        QCOMPARE(n.size(), 1);
        QCOMPARE(n[0].value("title").toString(), QStringLiteral("Update available"));
        QCOMPARE(n[0].value("body").toString(), QStringLiteral("Marathon 26101801"));
        QCOMPARE(n[0].value("icon").toString(), QStringLiteral("arrow-circle-up"));
        QCOMPARE(keys(n[0]), (QStringList{"default", "download", "later"}));

        server->activate(n[0].value("id").toUInt(), QStringLiteral("download"));
        QCOMPARE(backend->calls, QStringList{"install"});
        QCOMPARE(updates->stateName(), QStringLiteral("downloading"));
        QCOMPARE(shown().size(), 1);
        QCOMPARE(shown().at(0).value("title").toString(), QStringLiteral("Downloading update"));
    }

    void aBlockedDownloadOpensSettings() {
        makeAvailable();
        conditions.metered = 1;
        QSignalSpy links(router.get(), &NavigationRouterCpp::deepLinkRequested);
        server->activate(shown().at(0).value("id").toUInt(), QStringLiteral("download"));
        QCOMPARE(links.count(), 1);
        QCOMPARE(links[0][0].toString(), QStringLiteral("settings"));
        QCOMPARE(links[0][1].toString(), QStringLiteral("updates"));
    }

    void laterOnlyDismisses() {
        makeAvailable();
        server->activate(shown().at(0).value("id").toUInt(), QStringLiteral("later"));
        QVERIFY(shown().isEmpty());
        QCOMPARE(updates->stateName(), QStringLiteral("available"));
    }

    void aTapOpensSoftwareUpdates() {
        makeAvailable();
        QSignalSpy links(router.get(), &NavigationRouterCpp::deepLinkRequested);
        server->activate(shown().at(0).value("id").toUInt(), QStringLiteral("default"));
        QCOMPARE(links.count(), 1);
        QCOMPARE(links[0][1].toString(), QStringLiteral("updates"));
    }

    void otherNotificationsAreNotOurs() {
        makeAvailable();
        const uint other = server->Notify("Messages", 0, "", "Ada", "Hi", {}, {}, -1);
        server->activate(other, QStringLiteral("download"));
        QVERIFY(backend->calls.isEmpty());
    }

    void theRestartNoticeReplacesTheOffer() {
        makeAvailable();
        updates->install();
        emit                     backend->installed(QStringLiteral("26101801"));
        const QList<QVariantMap> n = shown();
        QCOMPARE(n.size(), 1);
        QCOMPARE(n[0].value("title").toString(), QStringLiteral("Restart to finish updating"));
        QCOMPARE(n[0].value("body").toString(), QStringLiteral("Marathon 26101801 is ready."));
        QCOMPARE(keys(n[0]), (QStringList{"default", "restart", "tonight"}));

        server->activate(n[0].value("id").toUInt(), QStringLiteral("tonight"));
        QVERIFY(updates->restartScheduled());
    }

    void aStartupPinLeavesOutTonight() {
        makeAvailable();
        updates->setStartupPin(true);
        updates->install();
        emit backend->installed(QStringLiteral("26101801"));
        QCOMPARE(keys(shown().value(0)), (QStringList{"default", "restart"}));
        QCOMPARE(shown().value(0).value("body").toString(),
                 QStringLiteral("Marathon 26101801 is ready."));
    }

    void restartNowRestarts() {
        makeAvailable();
        updates->install();
        emit       backend->installed(QStringLiteral("26101801"));
        QSignalSpy reboots(updates.get(), &UpdateService::rebootRequested);
        server->activate(shown().at(0).value("id").toUInt(), QStringLiteral("restart"));
        QCOMPARE(reboots.count(), 1);
    }

    void anAutomaticInstallSaysWhenItRestarts() {
        QSettings().setValue(QStringLiteral("updates/autoUpdate"), true);
        conditions = {2, true, 80, 1};
        makeAvailable();
        QCOMPARE(shown().size(), 1);
        QVERIFY(shown().at(0).value("ongoing").toBool());
        emit backend->installed(QStringLiteral("26101801"));
        QCOMPARE(shown().value(0).value("body").toString(),
                 QStringLiteral("Marathon 26101801 installs tonight while charging."));
    }

    // One ongoing row follows the download, then the install, in place.
    void theDownloadShowsItsProgress() {
        makeAvailable();
        updates->install();
        QList<QVariantMap> n = shown();
        QCOMPARE(n.size(), 1);
        const uint id = n[0].value("id").toUInt();
        QCOMPARE(n[0].value("body").toString(), QStringLiteral("Marathon OS 26101801 · 0%"));
        QVERIFY(n[0].value("ongoing").toBool());
        QCOMPARE(n[0].value("progress").toReal(), 0.0);
        QCOMPARE(keys(n[0]), QStringList{"default"});

        QSignalSpy changed(model.get(), &NotificationModel::dataChanged);
        emit       backend->progress(42);
        // Other news about the update leaves the row alone.
        updates->setAutoUpdate(true);
        QCOMPARE(changed.count(), 1);
        n = shown();
        QCOMPARE(n.size(), 1);
        QCOMPARE(n[0].value("id").toUInt(), id);
        QCOMPARE(n[0].value("body").toString(), QStringLiteral("Marathon OS 26101801 · 42%"));
        QCOMPARE(n[0].value("progress").toReal(), 0.42);

        emit backend->installing();
        n = shown();
        QCOMPARE(n[0].value("id").toUInt(), id);
        QCOMPARE(n[0].value("title").toString(), QStringLiteral("Installing update"));
        QCOMPARE(n[0].value("progress").toReal(), 0.0);

        QSignalSpy links(router.get(), &NavigationRouterCpp::deepLinkRequested);
        server->activate(id, QStringLiteral("default"));
        QCOMPARE(links.count(), 1);
        QCOMPARE(links[0][1].toString(), QStringLiteral("updates"));
    }

    void theRestartNoticeTakesTheProgressRowsPlace() {
        makeAvailable();
        updates->install();
        emit backend->progress(99);
        emit backend->installed(QStringLiteral("26101801"));
        const QList<QVariantMap> n = shown();
        QCOMPARE(n.size(), 1);
        QCOMPARE(n[0].value("title").toString(), QStringLiteral("Restart to finish updating"));
        QVERIFY(!n[0].value("ongoing").toBool());
    }

    void aFailedOrCancelledDownloadLeavesNoRow() {
        makeAvailable();
        updates->install();
        emit backend->failed(QStringLiteral("no network"));
        QVERIFY(shown().isEmpty());

        updates->checkNow();
        emit backend->checked(QStringLiteral("26101801"));
        updates->install();
        QCOMPARE(shown().size(), 1);
        updates->cancel();
        QVERIFY(shown().isEmpty());
    }

    void theNextBootReplacesTheRestartNotice() {
        makeAvailable();
        updates->install();
        emit backend->installed(QStringLiteral("26101801"));

        start(QStringLiteral("26101801"));
        emit                     backend->probed(true, QStringLiteral("26101801"));
        const QList<QVariantMap> n = shown();
        QCOMPARE(n.size(), 1);
        QCOMPARE(n[0].value("title").toString(), QStringLiteral("Updated to Marathon 26101801"));
        QCOMPARE(keys(n[0]), QStringList{"default"});
    }

    void aRollbackSaysWhichVersionIsRunning() {
        QSettings s;
        s.setValue(QStringLiteral("updates/installedVersion"), QStringLiteral("26101801"));
        s.setValue(QStringLiteral("updates/installedBootId"), QStringLiteral("boot-old"));
        start(QStringLiteral("26101701"));
        emit                     backend->probed(true, QStringLiteral("26101801"));
        const QList<QVariantMap> n = shown();
        QCOMPARE(n.size(), 1);
        QCOMPARE(n[0].value("title").toString(), QStringLiteral("Marathon 26101801 didn't start"));
        QCOMPARE(n[0].value("body").toString(),
                 QStringLiteral("The update couldn't start, so Marathon went back to 26101701."));
    }
};

QTEST_GUILESS_MAIN(TestUpdateNotifier)
#include "test_updatenotifier.moc"
