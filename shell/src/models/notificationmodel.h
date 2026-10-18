#ifndef NOTIFICATIONMODEL_H
#define NOTIFICATIONMODEL_H

#include <QAbstractListModel>
#include <QHash>
#include <QString>
#include <QDateTime>
#include <QVariantList>
#include <QVariantMap>
#include <qqml.h>

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
    void setTimestamp(qint64 msecs) {
        m_timestamp = msecs;
    }
    bool isRead() const {
        return m_isRead;
    }
    QVariantList actions() const {
        return m_actions;
    }
    void setActions(const QVariantList &actions) {
        m_actions = actions;
    }
    QString replyPlaceholder() const {
        return m_replyPlaceholder;
    }
    void setReplyPlaceholder(const QString &text) {
        m_replyPlaceholder = text;
    }
    bool actionIcons() const {
        return m_actionIcons;
    }
    // An ongoing notification shows progress: 0..1, or -1 while unknown.
    bool ongoing() const {
        return m_ongoing;
    }
    qreal progress() const {
        return m_progress;
    }
    bool suppressSound() const {
        return m_suppressSound;
    }
    // The freedesktop hints the banner and the Hub show. The de facto
    // "value" hint (0-100, negative for unknown) makes it ongoing.
    void setHints(const QVariantMap &hints) {
        m_category      = hints.value("category").toString();
        m_actionIcons   = hints.value("action-icons").toBool();
        m_urgency       = hints.value("urgency", 1).toInt();
        m_ongoing       = hints.contains("value");
        m_suppressSound = hints.value("suppress-sound").toBool();
        const int value = hints.value("value", -1).toInt();
        m_progress      = value < 0 ? -1 : qMin(value, 100) / 100.0;
    }

    QVariantMap toMap() const {
        return {{"id", m_id},
                {"appId", m_appId},
                {"title", m_title},
                {"body", m_body},
                {"icon", m_icon},
                {"timestamp", m_timestamp},
                {"read", m_isRead},
                {"actions", m_actions},
                {"replyPlaceholder", m_replyPlaceholder},
                {"category", m_category},
                {"actionIcons", m_actionIcons},
                {"urgency", m_urgency},
                {"ongoing", m_ongoing},
                {"progress", m_progress}};
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
    qint64       m_timestamp;
    bool         m_isRead;
    QVariantList m_actions;
    QString      m_replyPlaceholder;
    QString      m_category;
    bool         m_actionIcons = false;
    int          m_urgency     = 1;
    bool         m_ongoing     = false;
    qreal        m_progress    = -1;
    bool         m_suppressSound = false;
};

class NotificationModel : public QAbstractListModel {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(int unreadCount READ unreadCount NOTIFY unreadCountChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)

  public:
    enum NotificationRoles : quint16 {
        IdRole = Qt::UserRole + 1,
        AppIdRole,
        TitleRole,
        BodyRole,
        IconRole,
        TimestampRole,
        IsReadRole,
        ActionsRole,
        ActionIconsRole,
        OngoingRole,
        ProgressRole,
        DayRole
    };
    Q_ENUM(NotificationRoles)

    explicit NotificationModel(QObject *parent = nullptr);
    ~NotificationModel() override;

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
                                    const QString &icon, const QVariantList &actions = {},
                                    const QString     &replyPlaceholder = {},
                                    const QVariantMap &hints            = {});

    // Same, but adopting an id minted elsewhere -- specifically the row id
    // NotificationDatabase::saveNotification() returns. The two used to be
    // independent counters, so a caller holding a database id could dismiss
    // an unrelated model row. Callers that persist should use this.
    int addNotificationWithId(int id, const QString &appId, const QString &title,
                              const QString &body, const QString &icon,
                              const QVariantList &actions     = {},
                              const QString &replyPlaceholder = {}, const QVariantMap &hints = {});
    // Rewrites a row in place, keeping its place, time and read state.
    // Returns false when there is no such row.
    bool updateNotification(int id, const QString &title, const QString &body, const QString &icon,
                            const QVariantList &actions, const QVariantMap &hints);
    Q_INVOKABLE void          dismissNotification(int id);
    Q_INVOKABLE void          markAsRead(int id);
    // Clears everything but the ongoing rows.
    Q_INVOKABLE void          dismissAllNotifications();
    Q_INVOKABLE Notification *getNotification(int id);
    Q_INVOKABLE int           roleId(const QString &name) const;
    // Each app once, newest first: { appId, unread }.
    Q_INVOKABLE QVariantList  sources() const;

    void                      loadFromDatabase(class NotificationDatabase *database);

  signals:
    void unreadCountChanged();
    void countChanged();
    void notificationAdded(int id);
    void notificationDismissed(int id);
    void notificationRead(int id);

  private:
    void                       updateUnreadCount();
    void                       trimToCap();

    // Mirrors NotificationDatabase::kMaxStoredNotifications so the model and
    // the table hold the same history rather than drifting apart.
    static constexpr int       kMaxNotifications = 500;

    QVector<Notification *>    m_notifications;
    QHash<int, Notification *> m_notificationIndex;
    int                        m_nextId;
    // Transient (model-only) ids run negative so they cannot collide with
    // the database row ids that the D-Bus path adopts.
    int                        m_nextTransientId = -1;
    int                        m_unreadCount;
};

#endif
