#include "sysupdatebackend.h"
#include "updateservice.h"

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QSettings>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryFile>
#include <QTest>

class FakeBackend : public UpdateBackend {
    Q_OBJECT

  public:
    QStringList calls;

    void        probe() override {
        calls << QStringLiteral("probe");
    }
    void checkNew() override {
        calls << QStringLiteral("checkNew");
    }
    void fetchReleaseInfo(const QString &version) override {
        calls << QStringLiteral("info:") + version;
    }
    void install() override {
        calls << QStringLiteral("install");
    }
    void cancel() override {
        calls << QStringLiteral("cancel");
    }
};

class TestUpdateService : public QObject {
    Q_OBJECT

    FakeBackend     *backend = nullptr;
    UpdateConditions conditions;
    QDateTime        now;
    // When valid, the clock runs on from now.
    QElapsedTimer  running;

    UpdateService *make(const QString &osVersion = QStringLiteral("26101701"),
                        const QString &bootId    = QStringLiteral("boot-b")) {
        backend = new FakeBackend;
        return new UpdateService(
            backend, [this]() { return conditions; }, osVersion, bootId,
            [this]() { return running.isValid() ? now.addMSecs(running.elapsed()) : now; }, this);
    }

    static QDateTime at(int day, int hour, int minute = 0) {
        return QDateTime(QDate(2026, 10, day), QTime(hour, minute));
    }

    // Installed with automatic updates on, at 23:00 on the 17th.
    UpdateService *readyToRestart() {
        QSettings().setValue(QStringLiteral("updates/autoUpdate"), true);
        conditions       = {2, true, 80, 1};
        UpdateService *s = available();
        emit           backend->installed(QStringLiteral("26101801"));
        return s;
    }

    UpdateService *available() {
        UpdateService *s = make();
        emit           backend->probed(true, QStringLiteral("26101701"));
        s->checkNow();
        emit backend->checked(QStringLiteral("26101801"));
        return s;
    }

    static void rememberInstall(const QString &version, const QString &bootId) {
        QSettings s;
        s.setValue(QStringLiteral("updates/installedVersion"), version);
        s.setValue(QStringLiteral("updates/installedBootId"), bootId);
    }

  private slots:
    void initTestCase() {
        QStandardPaths::setTestModeEnabled(true);
        QCoreApplication::setOrganizationName(QStringLiteral("MarathonTest"));
        QCoreApplication::setApplicationName(QStringLiteral("test_updateservice"));
    }

    void init() {
        QSettings s;
        s.clear();
        s.setValue(QStringLiteral("updates/autoCheck"), false);
        s.setValue(QStringLiteral("updates/autoUpdate"), false);
        conditions = {};
        now        = at(17, 23);
        running.invalidate();
    }

    void probesOnStart() {
        UpdateService *s = make();
        QCOMPARE(backend->calls, QStringList{"probe"});
        QCOMPARE(s->stateName(), QStringLiteral("probing"));
    }

    void unsupportedWithoutAHostTarget() {
        UpdateService *s = make();
        emit           backend->probed(false, {});
        QCOMPARE(s->state(), UpdateService::State::Unsupported);
        s->checkNow();
        QCOMPARE(backend->calls, QStringList{"probe"});
    }

    void unsupportedWhenNotBootedFromAnImage() {
        UpdateService *s = make(QString());
        emit           backend->probed(true, QStringLiteral("26101701"));
        QCOMPARE(s->state(), UpdateService::State::Unsupported);
    }

    void idleWhenTheBootedImageIsTheNewest() {
        UpdateService *s = make();
        emit           backend->probed(true, QStringLiteral("26101701"));
        QCOMPARE(s->stateName(), QStringLiteral("idle"));
    }

    void checkFindsAnUpdateAndFetchesItsInfo() {
        UpdateService *s = make();
        emit           backend->probed(true, QStringLiteral("26101701"));
        s->checkNow();
        QCOMPARE(s->stateName(), QStringLiteral("checking"));
        emit backend->checked(QStringLiteral("26101801"));
        QCOMPARE(s->stateName(), QStringLiteral("available"));
        QCOMPARE(s->availableVersion(), QStringLiteral("26101801"));
        QCOMPARE(s->downloadSize(), -1);
        QVERIFY(s->lastCheckedMs() > 0);
        QCOMPARE(backend->calls.last(), QStringLiteral("info:26101801"));

        emit backend->releaseInfo(QStringLiteral("26101701"), 5, QStringLiteral("old"));
        QCOMPARE(s->downloadSize(), -1);
        emit backend->releaseInfo(QStringLiteral("26101801"), 1234, QStringLiteral("Fixes"));
        QCOMPARE(s->downloadSize(), 1234);
        QCOMPARE(s->releaseNotes(), QStringLiteral("Fixes"));
    }

    void checkFindsNothing() {
        UpdateService *s = make();
        emit           backend->probed(true, QStringLiteral("26101701"));
        s->checkNow();
        emit backend->checked(QString());
        QCOMPARE(s->stateName(), QStringLiteral("upToDate"));
    }

    void lastCheckedSurvivesARestart() {
        UpdateService *s = make();
        emit           backend->probed(true, QStringLiteral("26101701"));
        s->checkNow();
        emit backend->checked(QString());
        QVERIFY(s->lastCheckedMs() > 0);
        QCOMPARE(make()->lastCheckedMs(), s->lastCheckedMs());
    }

    void checkFailureIsAnErrorYouCanRetry() {
        UpdateService *s = make();
        emit           backend->probed(true, QStringLiteral("26101701"));
        s->checkNow();
        emit backend->failed(QStringLiteral("Could not resolve host"));
        QCOMPARE(s->stateName(), QStringLiteral("error"));
        QCOMPARE(s->lastError(), QStringLiteral("Could not resolve host"));
        s->checkNow();
        QCOMPARE(s->stateName(), QStringLiteral("checking"));
        QVERIFY(s->lastError().isEmpty());
    }

    void blockReasons_data() {
        QTest::addColumn<uint>("metered");
        QTest::addColumn<bool>("present");
        QTest::addColumn<double>("percent");
        QTest::addColumn<uint>("batteryState");
        QTest::addColumn<QString>("reason");
        QTest::newRow("unmetered, no battery") << 2u << false << 0.0 << 0u << "";
        QTest::newRow("unknown metering") << 0u << false << 0.0 << 0u << "";
        QTest::newRow("metered") << 1u << false << 0.0 << 0u << "metered";
        QTest::newRow("guess metered") << 3u << false << 0.0 << 0u << "metered";
        QTest::newRow("guess unmetered") << 4u << false << 0.0 << 0u << "";
        QTest::newRow("low, discharging") << 2u << true << 29.0 << 2u << "battery";
        QTest::newRow("at threshold") << 2u << true << 30.0 << 2u << "";
        QTest::newRow("low, charging") << 2u << true << 10.0 << 1u << "";
        QTest::newRow("low, pending charge") << 2u << true << 10.0 << 5u << "";
        QTest::newRow("full on charger") << 2u << true << 100.0 << 4u << "";
        QTest::newRow("metered wins") << 1u << true << 10.0 << 2u << "metered";
    }

    void blockReasons() {
        QFETCH(uint, metered);
        QFETCH(bool, present);
        QFETCH(double, percent);
        QFETCH(uint, batteryState);
        QFETCH(QString, reason);
        QCOMPARE(UpdateService::blockReason({metered, present, percent, batteryState}), reason);
    }

    void installIsRefusedOnAMeteredNetwork() {
        UpdateService *s   = available();
        conditions.metered = 1;
        s->install();
        QCOMPARE(s->stateName(), QStringLiteral("available"));
        QCOMPARE(s->blockedReason(), QStringLiteral("metered"));
        QVERIFY(!backend->calls.contains(QStringLiteral("install")));

        conditions.metered = 2;
        s->install();
        QCOMPARE(s->stateName(), QStringLiteral("downloading"));
        QVERIFY(s->blockedReason().isEmpty());
        QCOMPARE(backend->calls.last(), QStringLiteral("install"));
    }

    void installIsRefusedOnALowBattery() {
        UpdateService *s = available();
        conditions       = {2, true, 12, 2};
        s->install();
        QCOMPARE(s->blockedReason(), QStringLiteral("battery"));
        QVERIFY(!backend->calls.contains(QStringLiteral("install")));
    }

    void installReportsProgressThenWaitsForReboot() {
        UpdateService *s = available();
        QSignalSpy     reboots(s, &UpdateService::rebootRequested);
        s->reboot();
        QCOMPARE(reboots.count(), 0);

        s->install();
        emit backend->progress(42);
        QCOMPARE(s->progress(), 42);
        s->checkNow();
        QCOMPARE(s->stateName(), QStringLiteral("downloading"));

        emit backend->installed(QStringLiteral("26101801"));
        QCOMPARE(s->stateName(), QStringLiteral("readyToReboot"));
        QCOMPARE(s->availableVersion(), QStringLiteral("26101801"));
        QSettings settings;
        QCOMPARE(settings.value("updates/installedVersion").toString(), QStringLiteral("26101801"));
        QCOMPARE(settings.value("updates/installedBootId").toString(), QStringLiteral("boot-b"));

        s->reboot();
        QCOMPARE(reboots.count(), 1);
    }

    void installFailureIsAnError() {
        UpdateService *s = available();
        s->install();
        emit backend->failed(QStringLiteral("systemd-sysupdate exited with status 1"));
        QCOMPARE(s->stateName(), QStringLiteral("error"));
        QCOMPARE(s->lastError(), QStringLiteral("systemd-sysupdate exited with status 1"));
    }

    void cancelReturnsToAvailable() {
        UpdateService *s = available();
        s->install();
        emit backend->progress(10);
        s->cancel();
        QCOMPARE(backend->calls.last(), QStringLiteral("cancel"));
        QCOMPARE(s->stateName(), QStringLiteral("available"));
        QCOMPARE(s->progress(), 0);
        emit backend->failed(QStringLiteral("Operation canceled"));
        QCOMPARE(s->stateName(), QStringLiteral("available"));
    }

    void anImageWeInstalledLastBootThatIsNotRunningRolledBack() {
        rememberInstall(QStringLiteral("26101801"), QStringLiteral("boot-a"));
        UpdateService *s = make(QStringLiteral("26101701"), QStringLiteral("boot-b"));
        emit           backend->probed(true, QStringLiteral("26101801"));
        QCOMPARE(s->stateName(), QStringLiteral("rolledBack"));
        QCOMPARE(s->rolledBackVersion(), QStringLiteral("26101801"));

        s->checkNow();
        emit backend->checked(QString());
        QCOMPARE(s->stateName(), QStringLiteral("rolledBack"));

        s->checkNow();
        emit backend->checked(QStringLiteral("26101901"));
        QCOMPARE(s->stateName(), QStringLiteral("available"));
    }

    void anImageInstalledThisBootIsPendingAReboot() {
        rememberInstall(QStringLiteral("26101801"), QStringLiteral("boot-b"));
        UpdateService *s = make(QStringLiteral("26101701"), QStringLiteral("boot-b"));
        emit           backend->probed(true, QStringLiteral("26101801"));
        QCOMPARE(s->stateName(), QStringLiteral("readyToReboot"));
        QCOMPARE(s->availableVersion(), QStringLiteral("26101801"));
    }

    void anImageInstalledElsewhereIsPendingAReboot() {
        UpdateService *s = make(QStringLiteral("26101701"), QStringLiteral("boot-b"));
        emit           backend->probed(true, QStringLiteral("26101801"));
        QCOMPARE(s->stateName(), QStringLiteral("readyToReboot"));
    }

    void bootingTheInstalledImageIsIdle() {
        rememberInstall(QStringLiteral("26101801"), QStringLiteral("boot-a"));
        UpdateService *s = make(QStringLiteral("26101801"), QStringLiteral("boot-b"));
        emit           backend->probed(true, QStringLiteral("26101801"));
        QCOMPARE(s->stateName(), QStringLiteral("idle"));
    }

    void anUpdateIsAnnouncedOncePerVersion() {
        UpdateService *s = make();
        QSignalSpy     notices(s, &UpdateService::notice);
        emit           backend->probed(true, QStringLiteral("26101701"));
        s->checkNow();
        emit backend->checked(QStringLiteral("26101801"));
        QCOMPARE(notices.count(), 1);
        QCOMPARE(notices.first().at(0).value<UpdateService::Notice>(),
                 UpdateService::Notice::Available);
        QCOMPARE(notices.first().at(1).toString(), QStringLiteral("26101801"));
        s->checkNow();
        emit backend->checked(QStringLiteral("26101801"));
        QCOMPARE(notices.count(), 1);

        UpdateService *again = make();
        QSignalSpy     later(again, &UpdateService::notice);
        emit           backend->probed(true, QStringLiteral("26101701"));
        again->checkNow();
        emit backend->checked(QStringLiteral("26101801"));
        QCOMPARE(later.count(), 0);
        again->checkNow();
        emit backend->checked(QStringLiteral("26101901"));
        QCOMPARE(later.count(), 1);
        QCOMPARE(later.first().at(1).toString(), QStringLiteral("26101901"));
    }

    void aFinishedInstallIsAnnouncedOncePerVersion() {
        UpdateService *s = available();
        QSignalSpy     notices(s, &UpdateService::notice);
        s->install();
        emit backend->installed(QStringLiteral("26101801"));
        QCOMPARE(notices.count(), 1);
        QCOMPARE(notices.first().at(0).value<UpdateService::Notice>(),
                 UpdateService::Notice::Restart);
        QCOMPARE(notices.first().at(1).toString(), QStringLiteral("26101801"));

        UpdateService *again = make();
        QSignalSpy     later(again, &UpdateService::notice);
        emit           backend->probed(true, QStringLiteral("26101801"));
        QCOMPARE(again->stateName(), QStringLiteral("readyToReboot"));
        QCOMPARE(later.count(), 0);
    }

    void anUpdateInstalledElsewhereIsAnnounced() {
        UpdateService *s = make();
        QSignalSpy     notices(s, &UpdateService::notice);
        emit           backend->probed(true, QStringLiteral("26101801"));
        QCOMPARE(notices.count(), 1);
        QCOMPARE(notices.first().at(0).value<UpdateService::Notice>(),
                 UpdateService::Notice::Restart);
    }

    void aRollbackIsAnnouncedOnce() {
        rememberInstall(QStringLiteral("26101801"), QStringLiteral("boot-a"));
        QSettings().setValue(QStringLiteral("updates/lastSeenVersion"), QStringLiteral("26101701"));
        for (int boot = 0; boot < 2; ++boot) {
            UpdateService *s = make(QStringLiteral("26101701"), QStringLiteral("boot-b"));
            QSignalSpy     notices(s, &UpdateService::notice);
            emit           backend->probed(true, QStringLiteral("26101801"));
            QCOMPARE(s->stateName(), QStringLiteral("rolledBack"));
            QCOMPARE(notices.count(), boot == 0 ? 1 : 0);
            if (boot == 0) {
                QCOMPARE(notices.first().at(0).value<UpdateService::Notice>(),
                         UpdateService::Notice::RolledBack);
                QCOMPARE(notices.first().at(1).toString(), QStringLiteral("26101801"));
            }
        }
    }

    void aBootIntoANewVersionIsAnnouncedOnce() {
        QSettings().setValue(QStringLiteral("updates/lastSeenVersion"), QStringLiteral("26101701"));
        UpdateService *s = make(QStringLiteral("26101801"));
        QSignalSpy     notices(s, &UpdateService::notice);
        emit           backend->probed(true, QStringLiteral("26101801"));
        QCOMPARE(notices.count(), 1);
        QCOMPARE(notices.first().at(0).value<UpdateService::Notice>(),
                 UpdateService::Notice::Updated);
        QCOMPARE(notices.first().at(1).toString(), QStringLiteral("26101801"));
        QCOMPARE(backend->calls.last(), QStringLiteral("info:26101801"));
        emit backend->releaseInfo(QStringLiteral("26101801"), 7, QStringLiteral("Faster boot"));
        QCOMPARE(s->currentReleaseNotes(), QStringLiteral("Faster boot"));

        UpdateService *again = make(QStringLiteral("26101801"));
        QSignalSpy     later(again, &UpdateService::notice);
        emit           backend->probed(true, QStringLiteral("26101801"));
        QCOMPARE(later.count(), 0);
    }

    void theFirstBootIsNoUpdate() {
        UpdateService *s = make();
        QSignalSpy     notices(s, &UpdateService::notice);
        emit           backend->probed(true, QStringLiteral("26101701"));
        QCOMPARE(notices.count(), 0);
        QCOMPARE(QSettings().value("updates/lastSeenVersion").toString(),
                 QStringLiteral("26101701"));
    }

    void anInstallFromBeforeLastSeenWasKeptIsAnUpdate() {
        rememberInstall(QStringLiteral("26101801"), QStringLiteral("boot-a"));
        UpdateService *s = make(QStringLiteral("26101801"));
        QSignalSpy     notices(s, &UpdateService::notice);
        emit           backend->probed(true, QStringLiteral("26101801"));
        QCOMPARE(notices.count(), 1);
        QCOMPARE(notices.first().at(0).value<UpdateService::Notice>(),
                 UpdateService::Notice::Updated);
    }

    void aCheckFetchesTheRunningVersionsNotesUntilItHasThem() {
        UpdateService *s = make();
        emit           backend->probed(true, QStringLiteral("26101701"));
        s->checkNow();
        emit backend->checked(QString());
        QVERIFY(backend->calls.contains(QStringLiteral("info:26101701")));
        emit backend->releaseInfo(QStringLiteral("26101701"), 5, QStringLiteral("Wi-Fi fixes"));
        QCOMPARE(s->currentReleaseNotes(), QStringLiteral("Wi-Fi fixes"));
        backend->calls.clear();
        s->checkNow();
        emit backend->checked(QString());
        QCOMPARE(backend->calls, QStringList{"checkNew"});
    }

    void automaticUpdatesAreOnUnlessTurnedOff() {
        QSettings().remove(QStringLiteral("updates/autoUpdate"));
        QVERIFY(make()->autoUpdate());
        make()->setAutoUpdate(false);
        QVERIFY(!make()->autoUpdate());
    }

    void automaticUpdatesDownloadWithoutAsking() {
        QSettings().setValue(QStringLiteral("updates/autoUpdate"), true);
        UpdateService *s = make();
        QSignalSpy     notices(s, &UpdateService::notice);
        emit           backend->probed(true, QStringLiteral("26101701"));
        s->checkNow();
        emit backend->checked(QStringLiteral("26101801"));
        QCOMPARE(s->stateName(), QStringLiteral("downloading"));
        QCOMPARE(backend->calls.last(), QStringLiteral("install"));
        QCOMPARE(notices.count(), 0);
    }

    void automaticUpdatesWaitForWifiAndAnnounceMeanwhile() {
        QSettings().setValue(QStringLiteral("updates/autoUpdate"), true);
        conditions.metered = 1;
        UpdateService *s   = make();
        QSignalSpy     notices(s, &UpdateService::notice);
        emit           backend->probed(true, QStringLiteral("26101701"));
        s->checkNow();
        emit backend->checked(QStringLiteral("26101801"));
        QCOMPARE(s->stateName(), QStringLiteral("available"));
        QCOMPARE(s->blockedReason(), QStringLiteral("metered"));
        QCOMPARE(notices.count(), 1);

        s->reconsider();
        QCOMPARE(s->stateName(), QStringLiteral("available"));
        conditions.metered = 2;
        s->reconsider();
        QCOMPARE(s->stateName(), QStringLiteral("downloading"));
        QCOMPARE(notices.count(), 1);
    }

    void withoutAutomaticUpdatesNothingDownloadsByItself() {
        UpdateService *s = available();
        s->reconsider();
        QCOMPARE(s->stateName(), QStringLiteral("available"));
        QVERIFY(!backend->calls.contains(QStringLiteral("install")));
    }

    void turningAutomaticUpdatesOnStartsAWaitingDownload() {
        UpdateService *s = available();
        s->setAutoUpdate(true);
        QCOMPARE(s->stateName(), QStringLiteral("downloading"));
        QVERIFY(QSettings().value(QStringLiteral("updates/autoUpdate")).toBool());
    }

    void aCancelledDownloadDoesNotRestartByItself() {
        QSettings().setValue(QStringLiteral("updates/autoUpdate"), true);
        UpdateService *s = available();
        QCOMPARE(s->stateName(), QStringLiteral("downloading"));
        s->cancel();
        s->reconsider();
        QCOMPARE(s->stateName(), QStringLiteral("available"));
        s->install();
        QCOMPARE(s->stateName(), QStringLiteral("downloading"));
    }

    void automaticUpdatesRestartInTheNextNightWindow() {
        UpdateService *s = readyToRestart();
        QVERIFY(s->restartScheduled());
        QCOMPARE(s->nextRestartWindow(), at(18, 2));

        QSignalSpy moved(s, &UpdateService::restartWindowChanged);
        now = at(18, 1, 30);
        s->reconsider();
        QCOMPARE(s->nextRestartWindow(), at(18, 2));
        QCOMPARE(moved.count(), 0);
        now = at(18, 6);
        s->reconsider();
        QCOMPARE(s->nextRestartWindow(), at(19, 2));
        QCOMPARE(moved.count(), 1);
    }

    void overnightRestartConditions_data() {
        QTest::addColumn<int>("hour");
        QTest::addColumn<int>("minute");
        QTest::addColumn<bool>("battery");
        QTest::addColumn<uint>("batteryState");
        QTest::addColumn<bool>("idle");
        QTest::addColumn<bool>("restarts");
        QTest::newRow("charging, screen off") << 3 << 0 << true << 1u << true << true;
        QTest::newRow("full on charger") << 2 << 0 << true << 4u << true << true;
        QTest::newRow("no battery") << 4 << 59 << false << 0u << true << true;
        QTest::newRow("on battery") << 3 << 0 << true << 2u << true << false;
        QTest::newRow("in use") << 3 << 0 << true << 1u << false << false;
        QTest::newRow("too early") << 1 << 59 << true << 1u << true << false;
        QTest::newRow("too late") << 5 << 0 << true << 1u << true << false;
    }

    void overnightRestartConditions() {
        QFETCH(int, hour);
        QFETCH(int, minute);
        QFETCH(bool, battery);
        QFETCH(uint, batteryState);
        QFETCH(bool, idle);
        QFETCH(bool, restarts);
        UpdateService *s = readyToRestart();
        QSignalSpy     reboots(s, &UpdateService::rebootRequested);
        now        = at(18, hour, minute);
        conditions = {2, battery, 80, batteryState, idle};
        s->reconsider();
        QCOMPARE(reboots.count(), restarts ? 1 : 0);
    }

    void aStartupPinKeepsItFromRestartingByItself() {
        UpdateService *s = readyToRestart();
        QSignalSpy     reboots(s, &UpdateService::rebootRequested);
        s->setStartupPin(true);
        QVERIFY(!s->restartScheduled());
        QVERIFY(!s->nextRestartWindow().isValid());
        now        = at(18, 3);
        conditions = {2, true, 80, 1, true};
        s->reconsider();
        QCOMPARE(reboots.count(), 0);
        s->scheduleRestart();
        QVERIFY(!s->restartScheduled());

        s->setStartupPin(false);
        QCOMPARE(reboots.count(), 1);
    }

    void tonightSchedulesTheRestartWithoutAutomaticUpdates() {
        UpdateService *s = available();
        s->install();
        emit backend->installed(QStringLiteral("26101801"));
        QVERIFY(!s->restartScheduled());
        QVERIFY(!s->nextRestartWindow().isValid());
        s->scheduleRestart();
        QVERIFY(s->restartScheduled());
        QCOMPARE(s->nextRestartWindow(), at(18, 2));

        UpdateService *again = make();
        emit           backend->probed(true, QStringLiteral("26101801"));
        QVERIFY(again->restartScheduled());
    }

    void theWindowOpeningRestartsAnIdleDevice() {
        UpdateService *s = readyToRestart();
        QSignalSpy     reboots(s, &UpdateService::rebootRequested);
        conditions.idle = true;
        now             = at(18, 1, 59).addMSecs(59800);
        running.start();
        s->reconsider();
        QCOMPARE(reboots.count(), 0);
        QTRY_COMPARE_WITH_TIMEOUT(reboots.count(), 1, 3000);
    }

    void imageVersionFromOsRelease_data() {
        QTest::addColumn<QByteArray>("content");
        QTest::addColumn<QString>("version");
        QTest::newRow("plain") << QByteArray("ID=postmarketos\nIMAGE_VERSION=26101701\n")
                               << "26101701";
        QTest::newRow("quoted") << QByteArray("IMAGE_VERSION=\"26101701\"\nID=x\n") << "26101701";
        QTest::newRow("missing") << QByteArray("ID=postmarketos\nIMAGE_ID=qemu\n") << "";
    }

    void imageVersionFromOsRelease() {
        QFETCH(QByteArray, content);
        QFETCH(QString, version);
        QTemporaryFile f;
        QVERIFY(f.open());
        f.write(content);
        f.close();
        QCOMPARE(UpdateService::imageVersion(f.fileName()), version);
        QCOMPARE(UpdateService::imageVersion(QStringLiteral("/nonexistent/os-release")), QString());
    }

    void appStreamGivesSizeAndNotesForTheVersion() {
        const QByteArray                xml = R"(<?xml version="1.0"?>
<components version="0.16" origin="marathon-os">
  <component merge="append">
    <id>org.marathonos.MarathonOS</id>
    <releases>
      <release version="26101801" date="2026-10-18">
        <description><p>Faster   boot.</p><ul><li>Fix Wi-Fi</li></ul></description>
        <artifacts>
          <artifact type="binary"><size type="download">1000</size><size type="installed">9</size></artifact>
          <artifact type="binary"><size type="download">24</size></artifact>
        </artifacts>
      </release>
      <release version="26101701"><description><p>Older</p></description>
        <artifacts><artifact type="binary"><size type="download">7</size></artifact></artifacts>
      </release>
    </releases>
    <bundle type="systemd" class="sysupdate"/>
  </component>
</components>)";
        const SysupdateBackend::Release r =
            SysupdateBackend::parseAppStream(xml, QStringLiteral("26101801"));
        QCOMPARE(r.downloadSize, 1024);
        QCOMPARE(r.notes, QStringLiteral("Faster boot.\n• Fix Wi-Fi"));

        const SysupdateBackend::Release none =
            SysupdateBackend::parseAppStream(xml, QStringLiteral("26101901"));
        QCOMPARE(none.downloadSize, -1);
        QVERIFY(none.notes.isEmpty());

        QCOMPARE(SysupdateBackend::parseAppStream("<components><release", "x").downloadSize, -1);
    }
};

QTEST_GUILESS_MAIN(TestUpdateService)
#include "test_updateservice.moc"
