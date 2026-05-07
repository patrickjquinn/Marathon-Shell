#include <QTest>
#include <QSignalSpy>
#include <QAbstractItemModelTester>
#include "marathonappregistry.h"

class TestAppRegistry : public QObject {
    Q_OBJECT

  private:
    MarathonAppRegistry::AppInfo
    makeApp(const QString &id, const QString &name,
            MarathonAppRegistry::AppType type        = MarathonAppRegistry::Marathon,
            bool                         isProtected = false) {
        MarathonAppRegistry::AppInfo info;
        info.id           = id;
        info.name         = name;
        info.icon         = "icon-" + id;
        info.type         = type;
        info.absolutePath = "/apps/" + id;
        info.entryPoint   = "Main.qml";
        info.version      = "1.0.0";
        info.isProtected  = isProtected;
        return info;
    }

  private slots:

    // === CONTRACT: Empty registry is truly empty ===

    void emptyRegistryHasZeroCount() {
        MarathonAppRegistry registry;
        QCOMPARE(registry.count(), 0);
        QCOMPARE(registry.rowCount(), 0);
        QVERIFY(registry.getAllAppIds().isEmpty());
        QVERIFY(!registry.hasApp("anything"));
        QVERIFY(registry.getApp("anything").isEmpty());
        QVERIFY(registry.getAppInfo("anything") == nullptr);
        QVERIFY(!registry.isProtected("anything"));
    }

    // === CONTRACT: Qt model contract compliance ===
    // QAbstractItemModelTester checks beginInsertRows/endInsertRows,
    // role consistency, index validity, etc.

    void modelContractIsValid() {
        MarathonAppRegistry      registry;
        QAbstractItemModelTester tester(&registry,
                                        QAbstractItemModelTester::FailureReportingMode::QtTest);

        registry.registerAppInfo(makeApp("com.app.one", "One"));
        registry.registerAppInfo(makeApp("com.app.two", "Two"));
        registry.registerAppInfo(makeApp("com.app.three", "Three"));

        QCOMPARE(registry.rowCount(), 3);
    }

    // === CONTRACT: Registration must emit signals so views update ===

    void registrationEmitsSignals() {
        MarathonAppRegistry registry;
        QSignalSpy          registeredSpy(&registry, &MarathonAppRegistry::appRegistered);
        QSignalSpy          countSpy(&registry, &MarathonAppRegistry::countChanged);

        registry.registerAppInfo(makeApp("com.test.app", "Test"));

        QCOMPARE(registeredSpy.count(), 1);
        QCOMPARE(registeredSpy.first().first().toString(), QString("com.test.app"));
        QCOMPARE(countSpy.count(), 1);
    }

    // === CONTRACT: Duplicate IDs must be silently rejected ===
    // If a duplicate sneaks through, views will have stale/double data.

    void duplicateIdIsRejected() {
        MarathonAppRegistry registry;
        QSignalSpy          registeredSpy(&registry, &MarathonAppRegistry::appRegistered);

        registry.registerAppInfo(makeApp("com.dup", "First"));
        registry.registerAppInfo(makeApp("com.dup", "Second, Different Name"));

        QCOMPARE(registry.count(), 1);
        QCOMPARE(registeredSpy.count(), 1);
        QCOMPARE(registry.getApp("com.dup")["name"].toString(), QString("First"));
    }

    // === CONTRACT: registerApp (Q_INVOKABLE) must behave identically to registerAppInfo ===
    // registerApp() allocates AppInfo* on line 96, then calls registerAppInfo(*info)
    // which allocates ANOTHER AppInfo* on line 109. The first is never freed. This tests
    // whether registerApp still works correctly despite the leak.

    void registerAppInvokableWorks() {
        MarathonAppRegistry registry;
        registry.registerApp("com.inv", "Invokable App", "icon.png",
                             static_cast<int>(MarathonAppRegistry::Marathon), "/path", "Main.qml",
                             "2.0.0", false, {"camera"});

        QVERIFY(registry.hasApp("com.inv"));
        QCOMPARE(registry.getApp("com.inv")["version"].toString(), QString("2.0.0"));
        QCOMPARE(registry.getApp("com.inv")["permissions"].toStringList(), QStringList({"camera"}));
    }

    // === CONTRACT: getApp must return ALL fields, not a subset ===

    void getAppReturnsCompleteData() {
        MarathonAppRegistry registry;

        auto                app = makeApp("com.full", "Full App");
        app.permissions         = {"camera", "location"};
        app.searchKeywords      = {"photo", "snap"};
        app.categories          = {"utilities", "media"};
        app.handlesUriSchemes   = {"https", "marathon"};
        app.defaultFor          = {"image/jpeg"};
        app.deepLinksJson       = R"({"open":"/open"})";
        registry.registerAppInfo(app);

        QVariantMap result = registry.getApp("com.full");
        QCOMPARE(result.count(), 14);
        QCOMPARE(result["id"].toString(), QString("com.full"));
        QCOMPARE(result["permissions"].toStringList(), QStringList({"camera", "location"}));
        QCOMPARE(result["searchKeywords"].toStringList(), QStringList({"photo", "snap"}));
        QCOMPARE(result["categories"].toStringList(), QStringList({"utilities", "media"}));
        QCOMPARE(result["handlesUriSchemes"].toStringList(), QStringList({"https", "marathon"}));
        QCOMPARE(result["defaultFor"].toStringList(), QStringList({"image/jpeg"}));
        QCOMPARE(result["deepLinks"].toString(), QString(R"({"open":"/open"})"));
    }

    // === CONTRACT: Model data() roles must match getApp() keys ===
    // If these diverge, QML views see different data than C++ consumers.

    void modelDataMatchesGetApp() {
        MarathonAppRegistry registry;

        auto                app = makeApp("com.match", "Match Test");
        app.version             = "3.0.0";
        app.isProtected         = true;
        registry.registerAppInfo(app);

        QVariantMap fromGetApp = registry.getApp("com.match");
        QModelIndex idx        = registry.index(0);

        QCOMPARE(registry.data(idx, MarathonAppRegistry::IdRole).toString(),
                 fromGetApp["id"].toString());
        QCOMPARE(registry.data(idx, MarathonAppRegistry::NameRole).toString(),
                 fromGetApp["name"].toString());
        QCOMPARE(registry.data(idx, MarathonAppRegistry::VersionRole).toString(),
                 fromGetApp["version"].toString());
        QCOMPARE(registry.data(idx, MarathonAppRegistry::IsProtectedRole).toBool(),
                 fromGetApp["isProtected"].toBool());
    }

    // === CONTRACT: Protected apps MUST NOT be unprotectable via the registry ===

    void protectedFlagPreserved() {
        MarathonAppRegistry registry;

        registry.registerAppInfo(makeApp("com.sys", "System", MarathonAppRegistry::System, true));
        registry.registerAppInfo(makeApp("com.user", "User", MarathonAppRegistry::Marathon, false));

        QVERIFY(registry.isProtected("com.sys"));
        QVERIFY(!registry.isProtected("com.user"));
        QVERIFY(!registry.isProtected("com.nonexistent"));
    }

    // === CONTRACT: Negative/out-of-bounds model indices must return invalid QVariant ===

    void outOfBoundsReturnsInvalid() {
        MarathonAppRegistry registry;
        registry.registerAppInfo(makeApp("com.only", "Only One"));

        QVERIFY(!registry.data(registry.index(-1), MarathonAppRegistry::IdRole).isValid());
        QVERIFY(!registry.data(registry.index(1), MarathonAppRegistry::IdRole).isValid());
        QVERIFY(!registry.data(registry.index(999), MarathonAppRegistry::IdRole).isValid());
        QVERIFY(!registry.data(registry.index(0), 99999).isValid());
    }

    // === CONTRACT: Ordering must be stable (insertion order) ===

    void insertionOrderPreserved() {
        MarathonAppRegistry registry;

        registry.registerAppInfo(makeApp("com.alpha", "Alpha"));
        registry.registerAppInfo(makeApp("com.beta", "Beta"));
        registry.registerAppInfo(makeApp("com.gamma", "Gamma"));

        QCOMPARE(registry.data(registry.index(0), MarathonAppRegistry::IdRole).toString(),
                 QString("com.alpha"));
        QCOMPARE(registry.data(registry.index(1), MarathonAppRegistry::IdRole).toString(),
                 QString("com.beta"));
        QCOMPARE(registry.data(registry.index(2), MarathonAppRegistry::IdRole).toString(),
                 QString("com.gamma"));
    }
};

QTEST_MAIN(TestAppRegistry)
#include "test_appregistry.moc"
