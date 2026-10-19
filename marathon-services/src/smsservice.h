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
class MmsManager;

struct Message {
    int     id;
    QString conversationId;
    QString sender;
    QString recipient;
    QString text;
    qint64  timestamp;
    bool    isRead;
    bool    isOutgoing;
    // sending, sent, failed or received; "" takes sent or received.
    QString status;
    QString mmsPath;
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
    ~SMSService() override;

    void             setContactsManager(ContactsManager *contactsManager);
    void             setMmsManager(MmsManager *mmsManager);

    QVariantList     conversations() const;

    Q_INVOKABLE void sendMessage(const QString &recipient, const QString &text);
    // Multi-recipient or attachments -- auto-routes to MMS via mmsd-tng.
    // recipients are E.164. attachments is a list of {contentType, filePath} maps.
    Q_INVOKABLE void         sendMultiRecipient(const QStringList &recipients, const QString &text,
                                                const QVariantList &attachments = {});
    Q_INVOKABLE QVariantList getMessages(const QString &conversationId);
    Q_INVOKABLE void         deleteConversation(const QString &conversationId);
    Q_INVOKABLE bool         deleteMessage(int id);
    Q_INVOKABLE void         markAsRead(const QString &conversationId);
    Q_INVOKABLE QString      generateConversationId(const QString &number);

    Q_INVOKABLE void         simulateIncomingSMS(const QString &sender, const QString &text);

    // Copies what fd reads into the attachment store; the attachment's id,
    // or -1. name is reduced to a file name.
    int                      addAttachment(int messageId, const QString &contentType,
                                           const QString &name, int fd);
    // The stored file of an attachment, "" if there is none.
    QString                  attachmentPath(int attachmentId) const;

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
    int                 storeMessage(const Message &msg);
    void                migrateDatabase();
    QVariantList        attachmentsOf(int messageId) const;
    void                removeAttachments(const QString &where, const QVariant &value);
    static QString      attachmentDir(int messageId);
    void                connectToModemManager();
    void                processIncomingSMS(const QString &modemPath, const QString &smsPath);
    QString             resolveContactName(const QString &number) const;

    QList<Conversation> m_conversations;
    QSqlDatabase        m_database;
    QDBusInterface     *m_modemManager;
    QTimer             *m_pollTimer;
    ContactsManager    *m_contactsManager;
    MmsManager         *m_mmsManager = nullptr;
};

#endif
