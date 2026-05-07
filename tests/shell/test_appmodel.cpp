#include <QTest>
#include <QSignalSpy>
#include "../../shell/src/models/appmodel.h"

class TestAppModel : public QObject {
    Q_OBJECT

  private slots:

    // === CONTRACT: Empty model ===

    void emptyModelState() {
        AppModel model;
        QCOMPARE(model.count(), 0);
        QCOMPARE(model.rowCount(), 0);
        QVERIFY(!model.getApp("anything"));
        QVERIFY(!model.getAppAtIndex(0));
        QVERIFY(!model.getAppAtIndex(-1));
    }

    // === CONTRACT: addApp inserts correctly ===

    void addAppBasic() {
        AppModel   model;
        QSignalSpy countSpy(&model, &AppModel::countChanged);

        model.addApp("com.test", "Test", "icon.png", "marathon");

        QCOMPARE(model.count(), 1);
        QCOMPARE(countSpy.count(), 1);

        App *app = model.getApp("com.test");
        QVERIFY(app);
        QCOMPARE(app->name(), QString("Test"));
        QCOMPARE(app->icon(), QString("icon.png"));
        QCOMPARE(app->type(), QString("marathon"));
    }

    // === CONTRACT: Duplicate ID is rejected ===

    void duplicateIdRejected() {
        AppModel model;
        model.addApp("com.dup", "First", "icon1.png", "marathon");
        model.addApp("com.dup", "Second", "icon2.png", "marathon");

        QCOMPARE(model.count(), 1);
        QCOMPARE(model.getApp("com.dup")->name(), QString("First"));
    }

    // === CONTRACT: Empty name is rejected ===

    void emptyNameRejected() {
        AppModel model;
        model.addApp("com.noname", "", "icon.png", "marathon");
        QCOMPARE(model.count(), 0);
    }

    // === CONTRACT: Empty icon is rejected ===

    void emptyIconRejected() {
        AppModel model;
        model.addApp("com.noicon", "Name", "", "marathon");
        QCOMPARE(model.count(), 0);
    }

    // === CONTRACT: Invalid type is rejected ===

    void invalidTypeRejected() {
        AppModel model;
        model.addApp("com.bad", "Bad", "icon.png", "invalid-type");
        QCOMPARE(model.count(), 0);
    }

    // === CONTRACT: All three valid types are accepted ===

    void allValidTypesAccepted() {
        AppModel model;
        model.addApp("com.m", "M", "i.png", "marathon");
        model.addApp("com.n", "N", "i.png", "native");
        model.addApp("com.s", "S", "i.png", "system");

        QCOMPARE(model.count(), 3);
    }

    // === CONTRACT: removeApp works ===

    void removeApp() {
        AppModel model;
        model.addApp("com.del", "Delete Me", "icon.png", "marathon");
        QCOMPARE(model.count(), 1);

        model.removeApp("com.del");
        QCOMPARE(model.count(), 0);
        QVERIFY(!model.getApp("com.del"));
    }

    // === CONTRACT: removeApp nonexistent is a no-op ===

    void removeNonexistentNoop() {
        AppModel model;
        model.addApp("com.keep", "Keep", "icon.png", "marathon");

        model.removeApp("com.ghost");
        QCOMPARE(model.count(), 1);
    }

    // === CONTRACT: clear removes everything ===

    void clearRemovesAll() {
        AppModel model;
        model.addApp("a", "A", "i.png", "marathon");
        model.addApp("b", "B", "i.png", "native");
        model.addApp("c", "C", "i.png", "system");

        model.clear();
        QCOMPARE(model.count(), 0);
    }

    // === CONTRACT: getAppName returns name or appId as fallback ===

    void getAppNameFallback() {
        AppModel model;
        model.addApp("com.known", "Known", "i.png", "marathon");

        QCOMPARE(model.getAppName("com.known"), QString("Known"));
        QCOMPARE(model.getAppName("com.unknown"), QString("com.unknown"));
    }

    // === CONTRACT: getAppIcon returns icon or empty for unknown ===

    void getAppIconFallback() {
        AppModel model;
        model.addApp("com.known", "Known", "my-icon.png", "marathon");

        QCOMPARE(model.getAppIcon("com.known"), QString("my-icon.png"));
        QVERIFY(model.getAppIcon("com.unknown").isEmpty());
    }

    // === CONTRACT: isNativeApp ===

    void isNativeApp() {
        AppModel model;
        model.addApp("com.nat", "Native", "i.png", "native");
        model.addApp("com.mar", "Marathon", "i.png", "marathon");

        QVERIFY(model.isNativeApp("com.nat"));
        QVERIFY(!model.isNativeApp("com.mar"));
        QVERIFY(!model.isNativeApp("com.ghost"));
    }

    // === CONTRACT: addApps batch insert ===

    void addAppsBatch() {
        AppModel     model;
        QVariantList apps;

        QVariantMap  a1;
        a1["id"]   = "a";
        a1["name"] = "A";
        a1["icon"] = "i.png";
        a1["type"] = "marathon";
        QVariantMap a2;
        a2["id"]   = "b";
        a2["name"] = "B";
        a2["icon"] = "i.png";
        a2["type"] = "native";
        QVariantMap bad;
        bad["id"]   = "";
        bad["name"] = "";
        bad["icon"] = "";
        bad["type"] = "bad";

        apps << a1 << a2 << bad;

        QSignalSpy countSpy(&model, &AppModel::countChanged);
        model.addApps(apps);

        QCOMPARE(model.count(), 2);
        QCOMPARE(countSpy.count(), 1);
    }

    // === CONTRACT: getAppAtIndex ===

    void getAppAtIndex() {
        AppModel model;
        model.addApp("first", "First", "i.png", "marathon");
        model.addApp("second", "Second", "i.png", "marathon");

        QVERIFY(model.getAppAtIndex(0));
        QCOMPARE(model.getAppAtIndex(0)->id(), QString("first"));
        QVERIFY(model.getAppAtIndex(1));
        QVERIFY(!model.getAppAtIndex(2));
        QVERIFY(!model.getAppAtIndex(-1));
    }

    // === CONTRACT: sortAppsByName sorts alphabetically ===

    void sortAppsByName() {
        AppModel model;
        model.addApp("c", "Zebra", "i.png", "marathon");
        model.addApp("a", "Alpha", "i.png", "marathon");
        model.addApp("b", "Middle", "i.png", "marathon");

        model.sortAppsByName();

        QCOMPARE(model.getAppAtIndex(0)->name(), QString("Alpha"));
        QCOMPARE(model.getAppAtIndex(1)->name(), QString("Middle"));
        QCOMPARE(model.getAppAtIndex(2)->name(), QString("Zebra"));
    }

    // === CONTRACT: Model data() returns correct roles ===

    void dataRoles() {
        AppModel model;
        model.addApp("com.test", "Test", "icon.png", "marathon", "test-exec");

        QModelIndex idx = model.index(0);
        QCOMPARE(model.data(idx, AppModel::IdRole).toString(), QString("com.test"));
        QCOMPARE(model.data(idx, AppModel::NameRole).toString(), QString("Test"));
        QCOMPARE(model.data(idx, AppModel::IconRole).toString(), QString("icon.png"));
        QCOMPARE(model.data(idx, AppModel::TypeRole).toString(), QString("marathon"));
        QCOMPARE(model.data(idx, AppModel::ExecRole).toString(), QString("test-exec"));
    }

    // === CONTRACT: Out of bounds data() returns invalid QVariant ===

    void dataOutOfBounds() {
        AppModel model;
        model.addApp("a", "A", "i.png", "marathon");

        QModelIndex invalid = model.index(5);
        QVERIFY(!model.data(invalid, AppModel::IdRole).isValid());
    }

    // === CONTRACT: roleNames covers all roles ===

    void roleNamesComplete() {
        AppModel model;
        auto     roles = model.roleNames();

        QVERIFY(roles.contains(AppModel::IdRole));
        QVERIFY(roles.contains(AppModel::NameRole));
        QVERIFY(roles.contains(AppModel::IconRole));
        QVERIFY(roles.contains(AppModel::TypeRole));
        QVERIFY(roles.contains(AppModel::ExecRole));
    }
};

QTEST_MAIN(TestAppModel)
#include "test_appmodel.moc"
