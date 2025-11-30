#ifndef TASKMODEL_H
#define TASKMODEL_H

#include <QAbstractListModel>
#include <QHash>
#include <QString>
#include <QDateTime>
#include <QImage>
#include <QPointer>

class Task : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString id READ id CONSTANT)
    Q_PROPERTY(QString appId READ appId CONSTANT)
    Q_PROPERTY(QString title READ title CONSTANT)
    Q_PROPERTY(QString icon READ icon CONSTANT)
    Q_PROPERTY(QString appType READ appType CONSTANT)
    Q_PROPERTY(int surfaceId READ surfaceId CONSTANT)
    Q_PROPERTY(QObject *waylandSurface READ waylandSurface NOTIFY waylandSurfaceChanged)
    Q_PROPERTY(qint64 timestamp READ timestamp CONSTANT)
    Q_PROPERTY(QImage snapshot READ snapshot NOTIFY snapshotChanged)

  public:
    explicit Task(const QString &id, const QString &appId, const QString &title,
                  const QString &icon, const QString &appType, int surfaceId,
                  QObject *waylandSurface = nullptr, QObject *parent = nullptr)
        : QObject(parent)
        , m_id(id)
        , m_appId(appId)
        , m_title(title)
        , m_icon(icon)
        , m_appType(appType)
        , m_surfaceId(surfaceId)
        , m_waylandSurface(waylandSurface)
        , m_timestamp(QDateTime::currentMSecsSinceEpoch()) {}

    QString id() const {
        return m_id;
    }
    QString appId() const {
        return m_appId;
    }
    QString title() const {
        return m_title;
    }
    QString icon() const {
        return m_icon;
    }
    QString appType() const {
        return m_appType;
    }
    int surfaceId() const {
        return m_surfaceId;
    }
    QObject *waylandSurface() const {
        return m_waylandSurface.data();
    }
    qint64 timestamp() const {
        return m_timestamp;
    }
    QImage snapshot() const {
        return m_snapshot;
    }

    void setSnapshot(const QImage &snapshot) {
        m_snapshot = snapshot;
        emit snapshotChanged();
    }

    void setWaylandSurface(QObject *surface) {
        if (m_waylandSurface != surface) {
            m_waylandSurface = surface;
            emit waylandSurfaceChanged();
        }
    }

  signals:
    void snapshotChanged();
    void waylandSurfaceChanged();

  private:
    QString           m_id;
    QString           m_appId;
    QString           m_title;
    QString           m_icon;
    QString           m_appType;
    int               m_surfaceId;
    QPointer<QObject> m_waylandSurface; // Use QPointer for safe lifecycle management
    qint64            m_timestamp;
    QImage            m_snapshot;
};

class TaskModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int taskCount READ taskCount NOTIFY taskCountChanged)

  public:
    enum TaskRoles {
        IdRole = Qt::UserRole + 1,
        AppIdRole,
        TitleRole,
        IconRole,
        AppTypeRole,
        SurfaceIdRole,
        WaylandSurfaceRole,
        TimestampRole,
        SnapshotRole
    };

    explicit TaskModel(QObject *parent = nullptr);
    ~TaskModel();

    int      rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int                    taskCount() const {
        return m_tasks.count();
    }

    Q_INVOKABLE void  launchTask(const QString &appId, const QString &appName,
                                 const QString &appIcon, const QString &appType, int surfaceId = -1,
                                 QObject *waylandSurface = nullptr);
    Q_INVOKABLE void  closeTask(const QString &taskId);
    Q_INVOKABLE Task *getTask(const QString &taskId);
    Q_INVOKABLE Task *getTaskByAppId(const QString &appId);
    Q_INVOKABLE Task *getTaskBySurfaceId(int surfaceId);
    Q_INVOKABLE void  updateTaskSnapshot(const QString &appId, const QImage &snapshot);
    Q_INVOKABLE void  updateTaskSurface(const QString &appId, QObject *surface);
    Q_INVOKABLE void  clear();

  signals:
    void taskCountChanged();
    void taskLaunched(const QString &taskId);
    void taskClosed(const QString &taskId);

  private:
    QVector<Task *>        m_tasks;
    QHash<QString, Task *> m_taskIndex; // task ID -> Task
    QHash<QString, Task *> m_appIndex;  // app ID -> Task (for quick lookup)
};

#endif // TASKMODEL_H
