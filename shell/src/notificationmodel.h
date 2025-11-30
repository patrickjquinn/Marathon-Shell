#ifndef NOTIFICATIONMODEL_H
#define NOTIFICATIONMODEL_H

#include <QAbstractListModel>
#include <QHash>
#include <QString>
#include <QDateTime>

class Notification : public QObject {
    Q_OBJECT
    Q_PROPERTY(int id READ id CONSTANT)
    Q_PROPERTY(QString appId READ appId CONSTANT)
    Q_PROPERTY(QString title READ title CONSTANT)
    Q_PROPERTY(QString body READ body CONSTANT)
    Q_PROPERTY(QString icon READ icon CONSTANT)
    Q_PROPERTY(qint64 timestamp READ timestamp CONSTANT)
    Q_PROPERTY(bool isRead READ isRead WRITE setIsRead NOTIFY isReadChanged)

  public:
    explicit Notification(int id, const QString &appId, const QString &title, const QString &body,
                          const QString &icon, QObject *parent = nullptr)
        : QObject(parent)
        , m_id(id)
        , m_appId(appId)
        , m_title(title)
        , m_body(body)
        , m_icon(icon)
        , m_timestamp(QDateTime::currentMSecsSinceEpoch())
        , m_isRead(false) {}

    int id() const {
        return m_id;
    }
    QString appId() const {
        return m_appId;
    }
    QString title() const {
        return m_title;
    }
    QString body() const {
        return m_body;
    }
    QString icon() const {
        return m_icon;
    }
    qint64 timestamp() const {
        return m_timestamp;
    }
    bool isRead() const {
        return m_isRead;
    }

    void setIsRead(bool read) {
        if (m_isRead != read) {
            m_isRead = read;
            emit isReadChanged();
        }
    }

  signals:
    void isReadChanged();

  private:
    int     m_id;
    QString m_appId;
    QString m_title;
    QString m_body;
    QString m_icon;
    qint64  m_timestamp;
    bool    m_isRead;
};

class NotificationModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int unreadCount READ unreadCount NOTIFY unreadCountChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)

  public:
    enum NotificationRoles {
        IdRole = Qt::UserRole + 1,
        AppIdRole,
        TitleRole,
        BodyRole,
        IconRole,
        TimestampRole,
        IsReadRole
    };
    Q_ENUM(NotificationRoles)

    explicit NotificationModel(QObject *parent = nullptr);
    ~NotificationModel();

    int      rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int                    unreadCount() const {
        return m_unreadCount;
    }
    int count() const {
        return m_notifications.count();
    }

    Q_INVOKABLE int addNotification(const QString &appId, const QString &title, const QString &body,
                                    const QString &icon);
    Q_INVOKABLE void          dismissNotification(int id);
    Q_INVOKABLE void          markAsRead(int id);
    Q_INVOKABLE void          dismissAllNotifications();
    Q_INVOKABLE Notification *getNotification(int id);

    void                      loadFromDatabase(class NotificationDatabase *database);

  signals:
    void unreadCountChanged();
    void countChanged();
    void notificationAdded(int id);
    void notificationDismissed(int id);

  private:
    void                       updateUnreadCount();

    QVector<Notification *>    m_notifications;
    QHash<int, Notification *> m_notificationIndex;
    int                        m_nextId;
    int                        m_unreadCount;
};

#endif // NOTIFICATIONMODEL_H
