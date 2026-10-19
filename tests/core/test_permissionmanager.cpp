#include <QTest>
#include <QSignalSpy>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include "../../shell/src/marathonpermissionmanager.h"
#include "marathonmanifest.h"

struct Answers {
    QStringList                              answers;
    QList<bool>                              precise;
    MarathonPermissionManager::ForeignAnswer record() {
        return [this](const QString &a, bool p) {
            answers.append(a);
            precise.append(p);
        };
    }
};

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
        for (const QString &p : std::as_const(perms)) {
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

    // === CONTRACT: The manager speaks schemas/marathon-permissions-v1.json ===

    void permissionsComeFromTheVocabulary() {
        MarathonPermissionManager mgr;
        QStringList               names;
        const QList<MarathonManifest::Permission> vocabulary = MarathonManifest::permissions();
        for (const MarathonManifest::Permission &p : vocabulary) {
            names << p.name;
            QCOMPARE(mgr.getPermissionLabel(p.name), p.label);
            QCOMPARE(mgr.getPermissionDescription(p.name), p.description);
        }
        QStringList available = mgr.getAvailablePermissions();
        names.sort();
        available.sort();
        QCOMPARE(available, names);
        QVERIFY(available.contains("secret-service"));
        QCOMPARE(mgr.getPermissionLabel("phone"), mgr.getPermissionLabel("telephony"));
    }

    // === CONTRACT: Every available permission must have a description ===

    void everyPermissionHasDescription() {
        MarathonPermissionManager mgr;

        const QStringList available = mgr.getAvailablePermissions();
        for (const QString &p : available) {
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

    // === CONTRACT: an app holds only what it declared, and restricted
    // permissions only as a protected system app ===

    static MarathonAppRegistry::AppInfo app(const QString &id, const QStringList &permissions,
                                            bool system = false, bool isProtected = false) {
        MarathonAppRegistry::AppInfo info;
        info.id          = id;
        info.name        = id;
        info.entryPoint  = "Main.qml";
        info.permissions = permissions;
        info.isSystem    = system;
        info.isProtected = isProtected;
        return info;
    }

    void undeclaredPermissionsAreDenied() {
        MarathonAppRegistry registry;
        registry.registerAppInfo(app("com.crafted", {"network"}));
        MarathonPermissionManager mgr;
        mgr.setAppRegistry(&registry);
        QSignalSpy denied(&mgr, &MarathonPermissionManager::permissionDenied);

        mgr.setPermission("com.crafted", "contacts", true);
        QVERIFY(!mgr.hasPermission("com.crafted", "contacts"));
        QCOMPARE(mgr.getPermissionStatus("com.crafted", "contacts"),
                 MarathonPermissionManager::Denied);
        denied.clear();
        mgr.requestPermission("com.crafted", "contacts");
        QCOMPARE(denied.count(), 1);
        QTest::qWait(200);
        QVERIFY(!mgr.promptActive());

        QCOMPARE(mgr.getPermissionStatus("com.crafted", "network"),
                 MarathonPermissionManager::NotRequested);
        QVERIFY(mgr.getAppPermissions("com.crafted").isEmpty());
    }

    void restrictedPermissionsNeedAProtectedApp() {
        MarathonAppRegistry registry;
        registry.registerAppInfo(app("test", {"system", "contacts"}, true));
        registry.registerAppInfo(app("com.fake", {"system"}));
        registry.registerAppInfo(app("settings", {"system", "network"}, true, true));
        MarathonPermissionManager mgr;
        mgr.setAppRegistry(&registry);

        mgr.setPermission("test", "system", true);
        QVERIFY(!mgr.hasPermission("test", "system"));
        QVERIFY(!mgr.hasPermission("com.fake", "system"));
        QCOMPARE(mgr.getPermissionStatus("test", "contacts"),
                 MarathonPermissionManager::NotRequested);

        QVERIFY(mgr.hasPermission("settings", "system"));
        QVERIFY(mgr.hasPermission("settings", "network"));
        QVERIFY(!mgr.hasPermission("settings", "contacts"));
        QCOMPARE(mgr.getAppPermissions("settings"), QStringList({"network", "system"}));
        mgr.setPermission("settings", "network", false);
        QVERIFY(!mgr.hasPermission("settings", "network"));
    }

    void thePhoneAliasIsTelephony() {
        MarathonAppRegistry registry;
        registry.registerAppInfo(app("com.dialer", {"phone"}));
        MarathonPermissionManager mgr;
        mgr.setAppRegistry(&registry);
        mgr.setPermission("com.dialer", "phone", true);
        QVERIFY(mgr.hasPermission("com.dialer", "telephony"));
        QVERIFY(mgr.hasPermission("com.dialer", "phone"));
        mgr.revokePermission("com.dialer", "telephony");
        QCOMPARE(mgr.getPermissionStatus("com.dialer", "phone"),
                 MarathonPermissionManager::NotRequested);
    }

    void forgettingAnAppDropsItsDecisions() {
        {
            MarathonPermissionManager mgr;
            mgr.setPermission("com.gone", "camera", true);
            mgr.forgetApp("com.gone");
            QCOMPARE(mgr.getPermissionStatus("com.gone", "camera"),
                     MarathonPermissionManager::NotRequested);
        }
        MarathonPermissionManager mgr;
        QCOMPARE(mgr.getPermissionStatus("com.gone", "camera"),
                 MarathonPermissionManager::NotRequested);
    }

    // === CONTRACT: a decision closes only the prompt it answers ===

    void otherAppsDecisionsLeaveThePromptOpen() {
        MarathonPermissionManager mgr;
        mgr.requestPermissions("com.asking", {"camera", "contacts"});
        QTRY_VERIFY(mgr.promptActive());
        QCOMPARE(mgr.currentPermissions(), QStringList({"camera", "contacts"}));

        mgr.setPermission("com.other", "camera", true);
        QVERIFY(mgr.promptActive());
        QCOMPARE(mgr.currentAppId(), QString("com.asking"));

        mgr.setPermission("com.asking", "camera", false);
        QVERIFY(mgr.promptActive());
        QCOMPARE(mgr.currentPermissions(), QStringList({"contacts"}));

        mgr.setPermission("com.asking", "contacts", true);
        QVERIFY(!mgr.promptActive());
        QVERIFY(mgr.hasPermission("com.asking", "contacts"));
    }

    // === CONTRACT: at launch every declared permission is granted, asked
    // for, or shown as refused ===

    void launchAsksForEveryDeclaredPermission() {
        const QStringList   declared = {"system", "storage",       "network",  "telephony",
                                        "sms",    "notifications", "contacts", "location"};
        MarathonAppRegistry registry;
        registry.registerAppInfo(app("test", declared, true));
        MarathonPermissionManager mgr;
        mgr.setAppRegistry(&registry);
        QSignalSpy denied(&mgr, &MarathonPermissionManager::permissionDenied);

        mgr.requestDeclaredPermissions("test");
        // What the runner's clients ask for on their own, in the same breath.
        mgr.requestPermission("test", "telephony");
        mgr.requestPermission("test", "system");
        QTRY_VERIFY(mgr.promptActive());
        QCOMPARE(mgr.currentAppId(), QString("test"));
        QCOMPARE(mgr.currentPermissions(),
                 QStringList({"storage", "network", "telephony", "sms", "notifications", "contacts",
                              "location"}));
        QCOMPARE(mgr.currentRefused(), QStringList({"system"}));

        mgr.respond(true);
        QVERIFY(!mgr.promptActive());
        for (const QString &p : declared)
            QCOMPARE(mgr.hasPermission("test", p), p != "system");
        QVERIFY(denied.count() >= 1);
        QCOMPARE(denied.last().at(1).toString(), QString("system"));

        mgr.requestDeclaredPermissions("test");
        QTest::qWait(250);
        QVERIFY(!mgr.promptActive());
    }

    void aRefusalAloneIsStillShown() {
        MarathonAppRegistry registry;
        registry.registerAppInfo(app("com.fake.settings", {"system"}));
        MarathonPermissionManager mgr;
        mgr.setAppRegistry(&registry);

        mgr.requestDeclaredPermissions("com.fake.settings");
        QTRY_VERIFY(mgr.promptActive());
        QVERIFY(mgr.currentPermissions().isEmpty());
        QCOMPARE(mgr.currentRefused(), QStringList({"system"}));
        mgr.respond(false);
        QVERIFY(!mgr.promptActive());

        QSignalSpy denied(&mgr, &MarathonPermissionManager::permissionDenied);
        mgr.requestPermission("com.fake.settings", "system");
        QCOMPARE(denied.count(), 1);
        QTest::qWait(250);
        QVERIFY(!mgr.promptActive());
    }

    void protectedAppsAreNotAsked() {
        MarathonAppRegistry registry;
        registry.registerAppInfo(app("settings", {"system", "network", "storage"}, true, true));
        MarathonPermissionManager mgr;
        mgr.setAppRegistry(&registry);
        mgr.requestDeclaredPermissions("settings");
        QTest::qWait(250);
        QVERIFY(!mgr.promptActive());
    }

    // === CONTRACT: using an undecided permission asks instead of failing
    // silently ===

    void accessToAnUndecidedPermissionAsks() {
        MarathonAppRegistry registry;
        registry.registerAppInfo(app("test", {"system", "contacts", "telephony"}, true));
        MarathonPermissionManager mgr;
        mgr.setAppRegistry(&registry);

        QCOMPARE(mgr.askIfUndecided("test", {"telephony", "phone"}), QString("telephony"));
        QTRY_VERIFY(mgr.promptActive());
        QCOMPARE(mgr.currentPermissions(), QStringList({"telephony"}));
        mgr.respond(false);

        QVERIFY(mgr.askIfUndecided("test", {"telephony"}).isEmpty());
        QVERIFY(mgr.askIfUndecided("test", {"system"}).isEmpty());
        QVERIFY(mgr.askIfUndecided("test", {"camera"}).isEmpty());
        QVERIFY(mgr.askIfUndecided("com.unknown", {"contacts"}).isEmpty());
        QCOMPARE(mgr.askIfUndecided("test", {"contacts"}), QString("contacts"));
        QTRY_VERIFY(mgr.promptActive());
        mgr.respond(true);
        QVERIFY(mgr.hasPermission("test", "contacts"));
    }

    // === CONTRACT: foreign prompts (Android apps) answer, never store ===

    void aForeignPromptShowsAtOnceAndStoresNothing() {
        MarathonPermissionManager mgr;
        Answers                   got;
        mgr.askForeign("k1", "waydroid.org.example.cam", "camera",
                       {{"kind", "foreground"}, {"once", true}}, got.record());

        QVERIFY(mgr.promptActive());
        QCOMPARE(mgr.currentAppId(), QString("waydroid.org.example.cam"));
        QCOMPARE(mgr.currentPermissions(), QStringList({"camera"}));
        QVERIFY(mgr.currentRefused().isEmpty());
        QCOMPARE(mgr.currentOptions().value("kind").toString(), QString("foreground"));
        QVERIFY(mgr.currentOptions().value("once").toBool());

        mgr.respondWith(true, false, false);
        QCOMPARE(got.answers, QStringList({"allow"}));
        QVERIFY(!mgr.promptActive());
        QVERIFY(mgr.currentOptions().isEmpty());
        QCOMPARE(mgr.getPermissionStatus("waydroid.org.example.cam", "camera"),
                 MarathonPermissionManager::NotRequested);
        QVERIFY(!QFile::exists(permissionsFilePath()));
    }

    void onlyThisTimeOnlyWhenOffered() {
        MarathonPermissionManager mgr;
        Answers                   got;
        mgr.askForeign("a", "waydroid.a", "microphone", {{"once", true}}, got.record());
        mgr.respondWith(true, true, false);
        mgr.askForeign("b", "waydroid.b", "contacts", {}, got.record());
        mgr.respondWith(true, true, false);
        mgr.askForeign("c", "waydroid.c", "camera", {{"once", true}}, got.record());
        mgr.respondWith(false, true, false);
        QCOMPARE(got.answers, QStringList({"once", "allow", "deny"}));
    }

    void preciseIsTheSwitchOnlyWhenThereIsAChoice() {
        MarathonPermissionManager mgr;
        Answers                   got;
        mgr.askForeign("a", "waydroid.a", "location",
                       {{"accuracy", "choice"}, {"preciseDefault", true}}, got.record());
        mgr.respondWith(true, false, false);
        mgr.askForeign("b", "waydroid.b", "location", {{"accuracy", "approximate"}}, got.record());
        mgr.respondWith(true, false, true);
        mgr.askForeign("c", "waydroid.c", "location",
                       {{"kind", "precise"}, {"preciseDefault", true}}, got.record());
        mgr.respond(true);
        QCOMPARE(got.answers, QStringList({"allow", "allow", "allow"}));
        QCOMPARE(got.precise, QList<bool>({false, false, true}));
    }

    void dismissingAForeignPromptCancelsIt() {
        MarathonPermissionManager mgr;
        Answers                   got;
        mgr.askForeign("a", "waydroid.a", "camera", {}, got.record());
        mgr.askForeign("b", "waydroid.b", "camera", {}, got.record());
        mgr.askForeign("c", "waydroid.c", "camera", {}, got.record());
        mgr.cancelForeign("b");
        QCOMPARE(got.answers, QStringList({"cancel"}));
        QCOMPARE(mgr.currentAppId(), QString("waydroid.a"));

        mgr.dismissForApp("waydroid.a");
        QCOMPARE(got.answers, QStringList({"cancel", "cancel"}));
        QTRY_COMPARE(mgr.currentAppId(), QString("waydroid.c"));
        mgr.dismissAll();
        QCOMPARE(got.answers, QStringList({"cancel", "cancel", "cancel"}));
        QVERIFY(!mgr.promptActive());
        mgr.cancelForeign("c");
        QCOMPARE(got.answers.size(), 3);
    }

    // Back on Android's question is Android's back: cancelled, nothing set.
    // On a Marathon prompt it stays Deny.
    void backCancelsAForeignPromptAndDeniesAMarathonOne() {
        MarathonAppRegistry registry;
        registry.registerAppInfo(app("notes", {"storage"}));
        MarathonPermissionManager mgr;
        mgr.setAppRegistry(&registry);
        Answers got;
        mgr.askForeign("a", "waydroid.a", "camera", {{"once", true}}, got.record());
        QVERIFY(mgr.promptActive());
        mgr.respondToBack();
        QCOMPARE(got.answers, QStringList({"cancel"}));
        QVERIFY(!mgr.promptActive());

        mgr.requestPermission("notes", "storage");
        QTRY_VERIFY(mgr.promptActive());
        mgr.respondToBack();
        QVERIFY(!mgr.hasPermission("notes", "storage"));
        QCOMPARE(mgr.getPermissionStatus("notes", "storage"), MarathonPermissionManager::Denied);
    }

    void foreignAndMarathonPromptsTakeTurns() {
        MarathonAppRegistry registry;
        registry.registerAppInfo(app("notes", {"storage", "contacts"}));
        MarathonPermissionManager mgr;
        mgr.setAppRegistry(&registry);
        Answers got;

        mgr.requestPermission("notes", "storage");
        QTRY_VERIFY(mgr.promptActive());
        mgr.askForeign("a", "waydroid.a", "camera", {}, got.record());
        QCOMPARE(mgr.currentAppId(), QString("notes"));
        mgr.respond(true);
        QVERIFY(mgr.hasPermission("notes", "storage"));
        QTRY_COMPARE(mgr.currentAppId(), QString("waydroid.a"));

        mgr.requestPermission("notes", "contacts");
        QTest::qWait(300);
        QCOMPARE(mgr.currentAppId(), QString("waydroid.a"));
        mgr.respond(false);
        QCOMPARE(got.answers, QStringList({"deny"}));
        QTRY_COMPARE(mgr.currentAppId(), QString("notes"));
        QCOMPARE(mgr.currentPermissions(), QStringList({"contacts"}));
    }

    void cleanupTestCase() {
        cleanPermissions();
        QStandardPaths::setTestModeEnabled(false);
    }
};

QTEST_MAIN(TestPermissionManager)
#include "test_permissionmanager.moc"
