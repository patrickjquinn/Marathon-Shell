#include "taskmodel.h"
#include <QDebug>

TaskModel::TaskModel(QObject *parent)
    : QAbstractListModel(parent) {
    qDebug() << "[TaskModel] Initialized";
}

TaskModel::~TaskModel() {
    qDeleteAll(m_tasks);
}

int TaskModel::rowCount(const QModelIndex &parent) const {
    if (parent.isValid())
        return 0;
    return m_tasks.count();
}

QVariant TaskModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_tasks.count())
        return QVariant();

    Task *task = m_tasks.at(index.row());

    switch (role) {
        case IdRole: return task->id();
        case AppIdRole: return task->appId();
        case TitleRole: return task->title();
        case IconRole: return task->icon();
        case AppTypeRole: return task->appType();
        case SurfaceIdRole: return task->surfaceId();
        case WaylandSurfaceRole:
            qInfo() << "[TaskModel] Accessing waylandSurface for" << task->appId()
                    << "- surface:" << (task->waylandSurface() ? "PRESENT" : "NULL");
            return QVariant::fromValue(task->waylandSurface());
        case TimestampRole: return task->timestamp();
        case SnapshotRole: return task->snapshot();
        default: return QVariant();
    }
}

QHash<int, QByteArray> TaskModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[IdRole]             = "id";
    roles[AppIdRole]          = "appId";
    roles[TitleRole]          = "title";
    roles[IconRole]           = "icon";
    roles[AppTypeRole]        = "type";
    roles[SurfaceIdRole]      = "surfaceId";
    roles[WaylandSurfaceRole] = "waylandSurface";
    roles[TimestampRole]      = "timestamp";
    roles[SnapshotRole]       = "snapshot";
    return roles;
}

void TaskModel::launchTask(const QString &appId, const QString &appName, const QString &appIcon,
                           const QString &appType, int surfaceId, QObject *waylandSurface) {
    // Check if task for this app already exists
    if (m_appIndex.contains(appId)) {
        qDebug() << "[TaskModel] Task already exists for app:" << appId;
        return;
    }

    QString taskId = "task_" + QString::number(QDateTime::currentMSecsSinceEpoch());

    // Insert at index 0 (newest first) instead of appending (oldest first)
    beginInsertRows(QModelIndex(), 0, 0);
    Task *task =
        new Task(taskId, appId, appName, appIcon, appType, surfaceId, waylandSurface, this);
    m_tasks.prepend(task); // Changed from append() to prepend()
    m_taskIndex[taskId] = task;
    m_appIndex[appId]   = task;
    endInsertRows();

    emit taskCountChanged();
    emit taskLaunched(taskId);
    qDebug() << "[TaskModel] Launched task:" << appName << "(" << appType << "), ID:" << taskId
             << "surface:" << (waylandSurface ? "present" : "NULL")
             << "- inserted at position 0 (newest first)";
}

void TaskModel::closeTask(const QString &taskId) {
    Task *task = m_taskIndex.value(taskId, nullptr);
    if (!task) {
        qDebug() << "[TaskModel] Task not found:" << taskId;
        return;
    }

    int index = m_tasks.indexOf(task);
    if (index >= 0) {
        QString appId = task->appId();

        beginRemoveRows(QModelIndex(), index, index);
        m_tasks.remove(index);
        m_taskIndex.remove(taskId);
        m_appIndex.remove(appId);
        endRemoveRows();

        emit taskCountChanged();
        emit taskClosed(taskId);

        qDebug() << "[TaskModel] Closed task:" << taskId;
        delete task;
    }
}

Task *TaskModel::getTask(const QString &taskId) {
    return m_taskIndex.value(taskId, nullptr);
}

Task *TaskModel::getTaskByAppId(const QString &appId) {
    return m_appIndex.value(appId, nullptr);
}

Task *TaskModel::getTaskBySurfaceId(int surfaceId) {
    // Search through all tasks to find one with matching surfaceId
    for (Task *task : m_tasks) {
        if (task && task->surfaceId() == surfaceId) {
            return task;
        }
    }
    return nullptr;
}

void TaskModel::updateTaskSnapshot(const QString &appId, const QImage &snapshot) {
    Task *task = m_appIndex.value(appId, nullptr);
    if (!task) {
        qDebug() << "[TaskModel] Cannot update snapshot: Task not found for app:" << appId;
        return;
    }

    task->setSnapshot(snapshot);

    // Notify model that this task's data changed
    int index = m_tasks.indexOf(task);
    if (index >= 0) {
        QModelIndex modelIndex = createIndex(index, 0);
        emit        dataChanged(modelIndex, modelIndex, {SnapshotRole});
        qDebug() << "[TaskModel] Updated snapshot for:" << appId << "size:" << snapshot.width()
                 << "x" << snapshot.height();
    }
}

void TaskModel::updateTaskSurface(const QString &appId, QObject *surface) {
    Task *task = m_appIndex.value(appId, nullptr);
    if (!task) {
        qDebug() << "[TaskModel] Cannot update surface: Task not found for app:" << appId;
        return;
    }

    task->setWaylandSurface(surface);

    // Notify model that this task's data changed
    int index = m_tasks.indexOf(task);
    if (index >= 0) {
        QModelIndex modelIndex = createIndex(index, 0);
        emit        dataChanged(modelIndex, modelIndex, {WaylandSurfaceRole});
        qDebug() << "[TaskModel] Updated wayland surface for:" << appId;
    }
}

void TaskModel::clear() {
    if (m_tasks.isEmpty())
        return;

    beginResetModel();
    qDeleteAll(m_tasks);
    m_tasks.clear();
    m_taskIndex.clear();
    m_appIndex.clear();
    endResetModel();

    emit taskCountChanged();
    qDebug() << "[TaskModel] Cleared all tasks";
}
