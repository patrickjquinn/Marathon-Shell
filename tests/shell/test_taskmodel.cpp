#include <QTest>
#include <QSignalSpy>
#include <QImage>
#include "../../shell/src/models/taskmodel.h"

class TestTaskModel : public QObject {
    Q_OBJECT

  private slots:

    // === CONTRACT: Empty model ===

    void emptyModelState() {
        TaskModel model;
        QCOMPARE(model.taskCount(), 0);
        QCOMPARE(model.rowCount(), 0);
        QVERIFY(!model.getTask("anything"));
        QVERIFY(!model.getTaskByAppId("anything"));
        QVERIFY(!model.getTaskBySurfaceId(0));
    }

    // === CONTRACT: launchTask inserts at position 0 (newest first) ===

    void launchTaskPrependsAndSignals() {
        TaskModel  model;
        QSignalSpy countSpy(&model, &TaskModel::taskCountChanged);
        QSignalSpy launchSpy(&model, &TaskModel::taskLaunched);

        model.launchTask("com.app", "App", "icon", "marathon");

        QCOMPARE(model.taskCount(), 1);
        QCOMPARE(countSpy.count(), 1);
        QCOMPARE(launchSpy.count(), 1);

        QString taskId = launchSpy.first().first().toString();
        QVERIFY(taskId.startsWith("task_"));
    }

    // === CONTRACT: Duplicate app launch is rejected ===

    void duplicateAppRejected() {
        TaskModel model;
        model.launchTask("com.dup", "Dup", "icon", "marathon");
        model.launchTask("com.dup", "Dup Again", "icon", "marathon");

        QCOMPARE(model.taskCount(), 1);
    }

    // === CONTRACT: Multiple different apps work ===

    void multipleApps() {
        TaskModel model;
        model.launchTask("com.a", "A", "i", "marathon");
        model.launchTask("com.b", "B", "i", "native");
        model.launchTask("com.c", "C", "i", "marathon");

        QCOMPARE(model.taskCount(), 3);
    }

    // === CONTRACT: getTaskByAppId ===

    void getTaskByAppId() {
        TaskModel model;
        model.launchTask("com.find", "Find Me", "icon", "marathon");

        Task *task = model.getTaskByAppId("com.find");
        QVERIFY(task);
        QCOMPARE(task->appId(), QString("com.find"));
        QCOMPARE(task->title(), QString("Find Me"));
    }

    // === CONTRACT: getTaskBySurfaceId ===

    void getTaskBySurfaceId() {
        TaskModel model;
        model.launchTask("com.surf", "Surf", "icon", "native", 42);

        Task *task = model.getTaskBySurfaceId(42);
        QVERIFY(task);
        QCOMPARE(task->appId(), QString("com.surf"));
        QCOMPARE(task->surfaceId(), 42);

        QVERIFY(!model.getTaskBySurfaceId(999));
    }

    // === CONTRACT: closeTask removes and signals ===

    void closeTask() {
        TaskModel  model;
        QSignalSpy launchSpy(&model, &TaskModel::taskLaunched);
        model.launchTask("com.close", "Close Me", "icon", "marathon");

        QString    taskId = launchSpy.first().first().toString();
        QSignalSpy closeSpy(&model, &TaskModel::taskClosed);
        QSignalSpy countSpy(&model, &TaskModel::taskCountChanged);

        model.closeTask(taskId);

        QCOMPARE(model.taskCount(), 0);
        QCOMPARE(closeSpy.count(), 1);
        QCOMPARE(closeSpy.first().first().toString(), taskId);
        QCOMPARE(countSpy.count(), 1);
        QVERIFY(!model.getTask(taskId));
        QVERIFY(!model.getTaskByAppId("com.close"));
    }

    // === CONTRACT: closeTask on nonexistent is a no-op ===

    void closeNonexistentNoop() {
        TaskModel model;
        model.launchTask("com.keep", "Keep", "i", "marathon");

        model.closeTask("task_nonexistent");
        QCOMPARE(model.taskCount(), 1);
    }

    // === CONTRACT: clear removes all tasks ===

    void clearAll() {
        TaskModel model;
        model.launchTask("a", "A", "i", "marathon");
        model.launchTask("b", "B", "i", "native");

        QSignalSpy countSpy(&model, &TaskModel::taskCountChanged);
        model.clear();

        QCOMPARE(model.taskCount(), 0);
        QCOMPARE(countSpy.count(), 1);
    }

    // === CONTRACT: clear on empty is a no-op (no crash) ===

    void clearEmpty() {
        TaskModel model;
        model.clear();
        QCOMPARE(model.taskCount(), 0);
    }

    // === CONTRACT: updateTaskSnapshot updates the task ===

    void updateSnapshot() {
        TaskModel model;
        model.launchTask("com.snap", "Snap", "i", "marathon");

        QImage img(100, 100, QImage::Format_ARGB32);
        img.fill(Qt::red);

        model.updateTaskSnapshot("com.snap", img);

        Task *task = model.getTaskByAppId("com.snap");
        QVERIFY(task);
        QCOMPARE(task->snapshot().size(), img.size());
    }

    // === CONTRACT: updateTaskSnapshot on nonexistent is a no-op ===

    void updateSnapshotNonexistent() {
        TaskModel model;
        QImage    img(10, 10, QImage::Format_ARGB32);
        model.updateTaskSnapshot("com.ghost", img);
        // No crash
    }

    // === CONTRACT: updateTaskSurface ===

    void updateTaskSurface() {
        TaskModel model;
        model.launchTask("com.surf", "Surf", "i", "marathon");

        QObject mockSurface;
        model.updateTaskSurface("com.surf", &mockSurface);

        Task *task = model.getTaskByAppId("com.surf");
        QVERIFY(task);
        QCOMPARE(task->waylandSurface(), &mockSurface);
    }

    // === CONTRACT: updateTaskNativeInfo promotes type to native ===

    void updateTaskNativeInfo() {
        TaskModel model;
        model.launchTask("com.promote", "Promote", "i", "marathon");

        QObject mockSurface;
        model.updateTaskNativeInfo("com.promote", 77, &mockSurface);

        Task *task = model.getTaskByAppId("com.promote");
        QVERIFY(task);
        QCOMPARE(task->appType(), QString("native"));
        QCOMPARE(task->surfaceId(), 77);
        QCOMPARE(task->waylandSurface(), &mockSurface);
    }

    // === CONTRACT: Newest task is at index 0 ===

    void newestFirst() {
        TaskModel model;
        model.launchTask("com.old", "Old", "i", "marathon");
        QTest::qWait(2); // ensure different timestamp
        model.launchTask("com.new", "New", "i", "marathon");

        QModelIndex idx0 = model.index(0);
        QCOMPARE(model.data(idx0, TaskModel::AppIdRole).toString(), QString("com.new"));
    }

    // === CONTRACT: data() roles ===

    void dataRoles() {
        TaskModel model;
        model.launchTask("com.test", "Test App", "test-icon", "marathon", 5);

        QModelIndex idx = model.index(0);
        QCOMPARE(model.data(idx, TaskModel::AppIdRole).toString(), QString("com.test"));
        QCOMPARE(model.data(idx, TaskModel::TitleRole).toString(), QString("Test App"));
        QCOMPARE(model.data(idx, TaskModel::IconRole).toString(), QString("test-icon"));
        QCOMPARE(model.data(idx, TaskModel::AppTypeRole).toString(), QString("marathon"));
        QCOMPARE(model.data(idx, TaskModel::SurfaceIdRole).toInt(), 5);
        QVERIFY(model.data(idx, TaskModel::TimestampRole).toLongLong() > 0);
    }

    // === CONTRACT: roleNames covers all roles ===

    void roleNamesComplete() {
        TaskModel model;
        auto      roles = model.roleNames();
        QVERIFY(roles.contains(TaskModel::IdRole));
        QVERIFY(roles.contains(TaskModel::AppIdRole));
        QVERIFY(roles.contains(TaskModel::TitleRole));
        QVERIFY(roles.contains(TaskModel::IconRole));
        QVERIFY(roles.contains(TaskModel::AppTypeRole));
        QVERIFY(roles.contains(TaskModel::SurfaceIdRole));
        QVERIFY(roles.contains(TaskModel::WaylandSurfaceRole));
        QVERIFY(roles.contains(TaskModel::TimestampRole));
        QVERIFY(roles.contains(TaskModel::SnapshotRole));
    }
};

QTEST_MAIN(TestTaskModel)
#include "test_taskmodel.moc"
