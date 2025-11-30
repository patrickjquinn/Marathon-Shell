#include <QTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QStandardPaths>
#include "../shell/src/marathonpermissionmanager.h"

class TestPermissionManager : public QObject {
    Q_OBJECT

  private slots:
    void initTestCase();
    void cleanupTestCase();
    void testHasPermission();
    void testRequestPermission();
    void testSetPermission();
    void testRevokePermission();
    void testGetAppPermissions();
    void testPermissionStatus();
    void testAvailablePermissions();
    void testPermissionDescription();
    void testPersistence();

  private:
    MarathonPermissionManager *manager;
    QTemporaryDir             *tempDir;
};

void TestPermissionManager::initTestCase() {
    // Use temporary directory for test data
    tempDir = new QTemporaryDir();
    QVERIFY(tempDir->isValid());

    // Override config location for testing
    qputenv("XDG_CONFIG_HOME", tempDir->path().toUtf8());

    manager = new MarathonPermissionManager(this);
}

void TestPermissionManager::cleanupTestCase() {
    delete manager;
    delete tempDir;
}

void TestPermissionManager::testHasPermission() {
    // Initially, app should have no permissions
    QVERIFY(!manager->hasPermission("test.app", "network"));
    QVERIFY(!manager->hasPermission("test.app", "camera"));

    // Grant permission
    manager->setPermission("test.app", "network", true, true);

    // Now app should have permission
    QVERIFY(manager->hasPermission("test.app", "network"));

    // But not other permissions
    QVERIFY(!manager->hasPermission("test.app", "camera"));
}

void TestPermissionManager::testRequestPermission() {
    QSignalSpy requestedSpy(manager, &MarathonPermissionManager::permissionRequested);
    QSignalSpy promptActiveSpy(manager, &MarathonPermissionManager::promptActiveChanged);

    // Request permission
    manager->requestPermission("test.app", "location");

    // Should emit signals
    QCOMPARE(requestedSpy.count(), 1);
    QVERIFY(promptActiveSpy.count() > 0);

    // Prompt should be active
    QVERIFY(manager->promptActive());
    QCOMPARE(manager->currentAppId(), QString("test.app"));
    QCOMPARE(manager->currentPermission(), QString("location"));
}

void TestPermissionManager::testSetPermission() {
    QSignalSpy grantedSpy(manager, &MarathonPermissionManager::permissionGranted);
    QSignalSpy deniedSpy(manager, &MarathonPermissionManager::permissionDenied);

    // Grant permission
    manager->setPermission("test.app", "camera", true, true);

    // Should emit granted signal
    QCOMPARE(grantedSpy.count(), 1);
    QCOMPARE(deniedSpy.count(), 0);

    // Permission should be granted
    QVERIFY(manager->hasPermission("test.app", "camera"));

    // Deny permission
    grantedSpy.clear();
    manager->setPermission("test.app", "microphone", false, true);

    // Should emit denied signal
    QCOMPARE(grantedSpy.count(), 0);
    QCOMPARE(deniedSpy.count(), 1);

    // Permission should not be granted
    QVERIFY(!manager->hasPermission("test.app", "microphone"));
}

void TestPermissionManager::testRevokePermission() {
    QSignalSpy revokedSpy(manager, &MarathonPermissionManager::permissionRevoked);

    // Grant permission first
    manager->setPermission("test.app", "storage", true, true);
    QVERIFY(manager->hasPermission("test.app", "storage"));

    // Revoke permission
    manager->revokePermission("test.app", "storage");

    // Should emit revoked signal
    QCOMPARE(revokedSpy.count(), 1);

    // Permission should no longer be granted
    QVERIFY(!manager->hasPermission("test.app", "storage"));
}

void TestPermissionManager::testGetAppPermissions() {
    QString appId = "multi.perm.app";

    // Grant multiple permissions
    manager->setPermission(appId, "network", true, true);
    manager->setPermission(appId, "location", true, true);
    manager->setPermission(appId, "camera", true, true);

    // Get all permissions
    QStringList permissions = manager->getAppPermissions(appId);

    QCOMPARE(permissions.size(), 3);
    QVERIFY(permissions.contains("network"));
    QVERIFY(permissions.contains("location"));
    QVERIFY(permissions.contains("camera"));
}

void TestPermissionManager::testPermissionStatus() {
    QString appId = "status.test.app";

    // Initially not requested
    auto status = manager->getPermissionStatus(appId, "contacts");
    QCOMPARE(status, MarathonPermissionManager::NotRequested);

    // Grant permission
    manager->setPermission(appId, "contacts", true, true);
    status = manager->getPermissionStatus(appId, "contacts");
    QCOMPARE(status, MarathonPermissionManager::Granted);

    // Deny permission
    manager->setPermission(appId, "calendar", false, true);
    status = manager->getPermissionStatus(appId, "calendar");
    QCOMPARE(status, MarathonPermissionManager::Denied);
}

void TestPermissionManager::testAvailablePermissions() {
    QStringList permissions = manager->getAvailablePermissions();

    // Should have standard permissions
    QVERIFY(!permissions.isEmpty());
    QVERIFY(permissions.contains("network"));
    QVERIFY(permissions.contains("location"));
    QVERIFY(permissions.contains("camera"));
    QVERIFY(permissions.contains("storage"));
}

void TestPermissionManager::testPermissionDescription() {
    QString desc = manager->getPermissionDescription("network");
    QVERIFY(!desc.isEmpty());
    QVERIFY(desc.contains("network") || desc.contains("internet"));

    QString locationDesc = manager->getPermissionDescription("location");
    QVERIFY(!locationDesc.isEmpty());
    QVERIFY(locationDesc.contains("location"));
}

void TestPermissionManager::testPersistence() {
    QString appId = "persist.test.app";

    // Grant some permissions
    manager->setPermission(appId, "network", true, true);
    manager->setPermission(appId, "location", true, true);

    // Create new manager instance (simulates app restart)
    delete manager;
    manager = new MarathonPermissionManager(this);

    // Permissions should still be granted
    QVERIFY(manager->hasPermission(appId, "network"));
    QVERIFY(manager->hasPermission(appId, "location"));
}

QTEST_MAIN(TestPermissionManager)
#include "test_permissionmanager.moc"
