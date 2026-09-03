#ifndef NOTIFICATIONDATABASE_H
#define NOTIFICATIONDATABASE_H

#include <QObject>
#include <QString>
#include <QDateTime>
#include <QVariantMap>
#include <QVariantList>
#include <QSqlDatabase>

class NotificationDatabase : public QObject {
    Q_OBJECT

  public:
    struct NotificationRecord {
        uint         id;
        QString      appId;
        QString      title;
        QString      body;
        QString      iconPath;
        QDateTime    timestamp;
        bool         read;
        bool         dismissed;
        QString      category;
        int          priority;
        QVariantList actions;
        QVariantMap  metadata;
    };

    explicit NotificationDatabase(QObject *parent = nullptr);
    ~NotificationDatabase() override;

    bool                      initialize();
    uint                      saveNotification(const NotificationRecord &notif);
    QList<NotificationRecord> getNotifications(const QString &appId = QString());
    QList<NotificationRecord> getUnreadNotifications();
    bool                      markAsRead(uint id);
    bool                      dismiss(uint id);
    bool                      dismissAll();
    bool                      clearAll();

    // Retention cap. Generous enough that the Hub still reads as full
    // history; bounded so the table cannot grow forever.
    static constexpr int      kMaxStoredNotifications = 500;
    int                       getUnreadCount() const;

  private:
    QSqlDatabase       m_db;
    QString            m_dbPath;

    bool               createTables();
    void               pruneToCap();
    NotificationRecord recordFromQuery(class QSqlQuery &query);
};

#endif
