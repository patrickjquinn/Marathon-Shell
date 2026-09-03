#include <QTest>
#include <QSignalSpy>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include "../../shell/src/marathonpermissionmanager.h"

class TestPermissionManager : public QObject {
    Q_OBJECT

  private:
    QString permissionsFilePath() {
        QString configDir = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation);
        return configDir + "/marathon/app-permissions.json";
    }

    void cleanPermissions() {
        QFile::remove(permissionsFilePath());
    }

  private slots:
    void initTestCase() {
        QStandardPaths::setTestModeEnabled(true);
        cleanPermissions();
    }

    void cleanup() {
        cleanPermissions();
    }

    // === CONTRACT: Fresh manager with no persisted data ===

    void freshManagerHasNoPermissions() {
        MarathonPermissionManager mgr;
        QVERIFY(!mgr.hasPermission("com.any.app", "camera"));
        QVERIFY(!mgr.promptActive());
        QVERIFY(mgr.currentAppId().isEmpty());
        QCOMPARE(mgr.getPermissionStatus("com.any.app", "camera"),
                 MarathonPermissionManager::NotRequested);
        QVERIFY(mgr.getAppPermissions("com.any.app").isEmpty());
    }

    // === CONTRACT: Grant means hasPermission returns true ===

    void grantedPermissionIsAccessible() {
        MarathonPermissionManager mgr;
        QSignalSpy                grantedSpy(&mgr, &MarathonPermissionManager::permissionGranted);

        mgr.setPermission("com.app", "camera", true);

        QVERIFY(mgr.hasPermission("com.app", "camera"));
        QCOMPARE(mgr.getPermissionStatus("com.app", "camera"), MarathonPermissionManager::Granted);
        QCOMPARE(grantedSpy.count(), 1);
    }

    // === CONTRACT: Deny means hasPermission returns false, but status is Denied not NotRequested ===

    void deniedPermissionIsNotAccessible() {
        MarathonPermissionManager mgr;
        QSignalSpy                deniedSpy(&mgr, &MarathonPermissionManager::permissionDenied);

        mgr.setPermission("com.app", "camera", false);

        QVERIFY(!mgr.hasPermission("com.app", "camera"));
        QCOMPARE(mgr.getPermissionStatus("com.app", "camera"), MarathonPermissionManager::Denied);
        QCOMPARE(deniedSpy.count(), 1);
    }

    // === CONTRACT: getAppPermissions only returns GRANTED permissions ===
    // Denied permissions must not leak through.

    void getAppPermissionsExcludesDenied() {
        MarathonPermissionManager mgr;

        mgr.setPermission("com.app", "camera", true);
        mgr.setPermission("com.app", "location", true);
        mgr.setPermission("com.app", "microphone", false);
        mgr.setPermission("com.app", "storage", false);

        QStringList granted = mgr.getAppPermissions("com.app");
        QCOMPARE(granted.count(), 2);
        QVERIFY(granted.contains("camera"));
        QVERIFY(granted.contains("location"));
        QVERIFY(!granted.contains("microphone"));
        QVERIFY(!granted.contains("storage"));
    }

    // === CONTRACT: Revoke removes the permission entirely ===
    // After revoke, status should be NotRequested (not Denied).

    void revokeResetsToNotRequested() {
        MarathonPermissionManager mgr;
        QSignalSpy                revokedSpy(&mgr, &MarathonPermissionManager::permissionRevoked);

        mgr.setPermission("com.app", "camera", true);
        QCOMPARE(mgr.getPermissionStatus("com.app", "camera"), MarathonPermissionManager::Granted);

        mgr.revokePermission("com.app", "camera");

        QVERIFY(!mgr.hasPermission("com.app", "camera"));
        QCOMPARE(mgr.getPermissionStatus("com.app", "camera"),
                 MarathonPermissionManager::NotRequested);
        QCOMPARE(revokedSpy.count(), 1);
    }

    // === CONTRACT: Revoking a nonexistent permission is a no-op ===

    void revokeNonexistentIsNoop() {
        MarathonPermissionManager mgr;
        QSignalSpy                revokedSpy(&mgr, &MarathonPermissionManager::permissionRevoked);

        mgr.revokePermission("com.ghost", "camera");

        QCOMPARE(revokedSpy.count(), 0);
    }

    // === CONTRACT: Permissions persist across manager instances ===
    // This is the core durability guarantee.

    void permissionsSurviveRestart() {
        {
            MarathonPermissionManager mgr;
            mgr.setPermission("com.persist", "camera", true);
            mgr.setPermission("com.persist", "location", false);
        }

        MarathonPermissionManager mgr2;
        QVERIFY(mgr2.hasPermission("com.persist", "camera"));
        QVERIFY(!mgr2.hasPermission("com.persist", "location"));
        QCOMPARE(mgr2.getPermissionStatus("com.persist", "camera"),
                 MarathonPermissionManager::Granted);
        QCOMPARE(mgr2.getPermissionStatus("com.persist", "location"),
                 MarathonPermissionManager::Denied);
    }

    // === CONTRACT: remember=false must NOT persist to disk ===
    // The permission should work for the current session but vanish on restart.

    void rememberFalseDoesNotPersist() {
        {
            MarathonPermissionManager mgr;
            mgr.setPermission("com.temp", "camera", true, false);
        }

        MarathonPermissionManager mgr2;
        QVERIFY(!mgr2.hasPermission("com.temp", "camera"));
        QCOMPARE(mgr2.getPermissionStatus("com.temp", "camera"),
                 MarathonPermissionManager::NotRequested);
    }

    // === CONTRACT: remember=false should still grant for the CURRENT session ===

    void rememberFalseGrantsForCurrentSession() {
        MarathonPermissionManager mgr;
        mgr.setPermission("com.temp", "camera", true, false);

        QVERIFY(mgr.hasPermission("com.temp", "camera"));
        QCOMPARE(mgr.getPermissionStatus("com.temp", "camera"), MarathonPermissionManager::Granted);
    }

    // === CONTRACT: Corrupted permissions file must not crash, must start fresh ===

    void corruptedFileStartsFresh() {
        QDir().mkpath(QFileInfo(permissionsFilePath()).path());
        QFile f(permissionsFilePath());
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("THIS IS NOT JSON {{{");
        f.close();

        MarathonPermissionManager mgr;
        QCOMPARE(mgr.getPermissionStatus("com.any", "camera"),
                 MarathonPermissionManager::NotRequested);
        QVERIFY(!mgr.hasPermission("com.any", "camera"));
    }

    // === CONTRACT: Each app's permissions are isolated ===

    void appsAreIsolated() {
        MarathonPermissionManager mgr;

        mgr.setPermission("com.app.a", "camera", true);
        mgr.setPermission("com.app.b", "camera", false);

        QVERIFY(mgr.hasPermission("com.app.a", "camera"));
        QVERIFY(!mgr.hasPermission("com.app.b", "camera"));
    }

    // === CONTRACT: setPermissions (batch) must apply to all permissions ===

    void batchSetAppliesAll() {
        MarathonPermissionManager mgr;
        QSignalSpy                grantedSpy(&mgr, &MarathonPermissionManager::permissionGranted);

        QStringList               perms = {"camera", "location", "microphone"};
        mgr.setPermissions("com.batch", perms, true);

        QCOMPARE(grantedSpy.count(), 3);
        for (const QString &p : perms) {
            QVERIFY(mgr.hasPermission("com.batch", p));
        }
    }

    // === CONTRACT: Available permissions list must include all known permissions ===

    void availablePermissionsAreComplete() {
        MarathonPermissionManager mgr;
        QStringList               available = mgr.getAvailablePermissions();

        QStringList expected = {"network",   "location", "camera",        "microphone", "contacts",
                                "calendar",  "storage",  "notifications", "telephony",  "sms",
                                "bluetooth", "system",   "terminal"};

        for (const QString &p : expected) {
            QVERIFY2(available.contains(p), qPrintable("Missing permission: " + p));
        }
    }

    // === CONTRACT: Every available permission must have a description ===

    void everyPermissionHasDescription() {
        MarathonPermissionManager mgr;

        for (const QString &p : mgr.getAvailablePermissions()) {
            QString desc = mgr.getPermissionDescription(p);
            QVERIFY2(!desc.isEmpty() && desc != "Unknown permission",
                     qPrintable("No description for: " + p));
        }
    }

    // === CONTRACT: Grant then deny must result in Denied, not Granted ===

    void denyOverridesGrant() {
        MarathonPermissionManager mgr;
        mgr.setPermission("com.flip", "camera", true);
        QVERIFY(mgr.hasPermission("com.flip", "camera"));

        mgr.setPermission("com.flip", "camera", false);
        QVERIFY(!mgr.hasPermission("com.flip", "camera"));
        QCOMPARE(mgr.getPermissionStatus("com.flip", "camera"), MarathonPermissionManager::Denied);
    }

    void cleanupTestCase() {
        cleanPermissions();
        QStandardPaths::setTestModeEnabled(false);
    }
};

QTEST_MAIN(TestPermissionManager)
#include "test_permissionmanager.moc"
