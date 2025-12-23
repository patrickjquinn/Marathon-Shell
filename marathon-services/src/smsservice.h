#ifndef SMSSERVICE_H
#define SMSSERVICE_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QDBusInterface>
#include <QSqlDatabase>
#include <QTimer>

class ContactsManager;

struct Message {
    int     id;
    QString conversationId;
    QString sender;
    QString recipient;
    QString text;
    qint64  timestamp;
    bool    isRead;
    bool    isOutgoing;
};

struct Conversation {
    QString id;
    QString contactNumber;
    QString lastMessage;
    qint64  lastTimestamp;
    int     unreadCount;
};

class SMSService : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList conversations READ conversations NOTIFY conversationsChanged)

  public:
    explicit SMSService(QObject *parent = nullptr);
    ~SMSService();

    void                     setContactsManager(ContactsManager *contactsManager);

    QVariantList             conversations() const;

    Q_INVOKABLE void         sendMessage(const QString &recipient, const QString &text);
    Q_INVOKABLE QVariantList getMessages(const QString &conversationId);
    Q_INVOKABLE void         deleteConversation(const QString &conversationId);
    Q_INVOKABLE void         markAsRead(const QString &conversationId);
    Q_INVOKABLE QString      generateConversationId(const QString &number);

    // Simulation method for testing
    Q_INVOKABLE void simulateIncomingSMS(const QString &sender, const QString &text);

  signals:
    void messageReceived(const QString &sender, const QString &text, qint64 timestamp);
    void messageSent(const QString &recipient, qint64 timestamp);
    void sendFailed(const QString &recipient, const QString &reason);
    void conversationsChanged();

  private slots:
    void checkForNewMessages();

  private:
    void                initDatabase();
    void                loadConversations();
    void                storeMessage(const Message &msg);
    void                connectToModemManager();
    void                processIncomingSMS(const QString &smsPath);
    QString             resolveContactName(const QString &number) const;

    QList<Conversation> m_conversations;
    QSqlDatabase        m_database;
    QDBusInterface     *m_modemManager;
    QTimer             *m_pollTimer;
    ContactsManager    *m_contactsManager;

#ifdef Q_OS_MACOS
    bool m_stubMode;
    void handleStubSend(const QString &recipient, const QString &text);
#endif
};

#endif // SMSSERVICE_H
