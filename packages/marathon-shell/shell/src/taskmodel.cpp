#include "taskmodel.h"
#include <QDebug>

TaskModel::TaskModel(QObject* parent)
    : QAbstractListModel(parent)
{
    qDebug() << "[TaskModel] Initialized";
}

TaskModel::~TaskModel()
{
    qDeleteAll(m_tasks);
}

int TaskModel::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid())
        return 0;
    return m_tasks.count();
}

QVariant TaskModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() >= m_tasks.count())
        return QVariant();

    Task* task = m_tasks.at(index.row());

    switch (role) {
    case IdRole:
        return task->id();
    case AppIdRole:
        return task->appId();
    case TitleRole:
        return task->title();
    case IconRole:
        return task->icon();
    case AppTypeRole:
        return task->appType();
    case SurfaceIdRole:
        return task->surfaceId();
    case TimestampRole:
        return task->timestamp();
    case SnapshotRole:
        return task->snapshot();
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> TaskModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[IdRole] = "id";
    roles[AppIdRole] = "appId";
    roles[TitleRole] = "title";
    roles[IconRole] = "icon";
    roles[AppTypeRole] = "type";
    roles[SurfaceIdRole] = "surfaceId";
    roles[TimestampRole] = "timestamp";
    roles[SnapshotRole] = "snapshot";
    return roles;
}

void TaskModel::launchTask(const QString& appId, const QString& appName, 
                           const QString& appIcon, const QString& appType, int surfaceId)
{
    // Check if task for this app already exists
    if (m_appIndex.contains(appId)) {
        qDebug() << "[TaskModel] Task already exists for app:" << appId;
        return;
    }

    QString taskId = "task_" + QString::number(QDateTime::currentMSecsSinceEpoch());

    beginInsertRows(QModelIndex(), m_tasks.count(), m_tasks.count());
    Task* task = new Task(taskId, appId, appName, appIcon, appType, surfaceId, this);
    m_tasks.append(task);
    m_taskIndex[taskId] = task;
    m_appIndex[appId] = task;
    endInsertRows();

    emit taskCountChanged();
    emit taskLaunched(taskId);
    qDebug() << "[TaskModel] Launched task:" << appName << "(" << appType << "), ID:" << taskId;
}

void TaskModel::closeTask(const QString& taskId)
{
    Task* task = m_taskIndex.value(taskId, nullptr);
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

Task* TaskModel::getTask(const QString& taskId)
{
    return m_taskIndex.value(taskId, nullptr);
}

Task* TaskModel::getTaskByAppId(const QString& appId)
{
    return m_appIndex.value(appId, nullptr);
}

void TaskModel::updateTaskSnapshot(const QString& appId, const QImage& snapshot)
{
    Task* task = m_appIndex.value(appId, nullptr);
    if (!task) {
        qDebug() << "[TaskModel] Cannot update snapshot: Task not found for app:" << appId;
        return;
    }
    
    task->setSnapshot(snapshot);
    
    // Notify model that this task's data changed
    int index = m_tasks.indexOf(task);
    if (index >= 0) {
        QModelIndex modelIndex = createIndex(index, 0);
        emit dataChanged(modelIndex, modelIndex, {SnapshotRole});
        qDebug() << "[TaskModel] Updated snapshot for:" << appId << "size:" << snapshot.width() << "x" << snapshot.height();
    }
}

void TaskModel::clear()
{
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

