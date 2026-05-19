#ifndef MAILSERVICE_H
#define MAILSERVICE_H

#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <qqml.h>

// Forward declarations from qmfclient. We forward-declare rather than
// include so this header doesn't drag QMF into every consumer; the
// QMF includes live in the .cpp.
class QMailAccountId;
class QMailAccountListModel;
class QMailFolderListModel;
class QMailMessageListModel;
class QMailMessageThreadedModel;
class QMailRetrievalAction;
class QMailServiceAction;
class QMailTransmitAction;

// MailService — the QtQuick-facing facade in front of QMF (Qt Messaging
// Framework). Replaces the webmail-picker that shipped before.
//
// The shell process owns one MailService singleton; apps that need mail
// state (Mail app first, future Hub mail category, lock-screen notif
// stack) all bind to it via QML.
//
// Hard rule (Marathon coding): no placeholder data. Every value here is
// either real QMF state, an empty/loading state, or the row/section gets
// hidden. There are zero fake messages, zero fake accounts.
//
// Architecture (intentional in-process choice):
//
//   ┌───────────────────────────────────────────────────────────────────┐
//   │  marathon-app-runner (Mail app process)                           │
//   │                                                                   │
//   │  QML  ──reads──▶  MailService (singleton)                         │
//   │                          │                                        │
//   │                          ▼  (in-process Qt calls — not D-Bus)     │
//   │                  QMailStore::instance()                           │
//   │                  QMailAccount / QMailMessage / Models             │
//   │                          │                                        │
//   │                          ▼  (libqmfclient ↔ messageserver5)       │
//   └──────────────────────────┼──────────────────────────────────────-─┘
//                              │ (UNIX socket / shared store)
//                              ▼
//                         messageserver5
//                         (marathon-mailserver.service, separate process)
//                              │
//                              ▼
//                         IMAP / SMTP / POP3
//
// MailService is intentionally thin — most of the model wrangling already
// lives in QMF's models. We expose them as QAbstractItemModel * properties
// (QML treats those as roles + rowCount data sources).
class MailService : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(MailService)
    QML_SINGLETON

    // Accounts list — QMailAccountListModel filtered to user-visible accounts.
    Q_PROPERTY(QObject *accounts READ accounts CONSTANT)
    // Currently-selected account id (string-encoded QMailAccountId). Empty
    // when no account is configured.
    Q_PROPERTY(QString currentAccountId READ currentAccountId WRITE setCurrentAccountId NOTIFY
                   currentAccountChanged)
    Q_PROPERTY(QString currentAccountName READ currentAccountName NOTIFY currentAccountChanged)
    // Folder list for the current account.
    Q_PROPERTY(QObject *folders READ folders NOTIFY currentAccountChanged)
    // Currently-selected folder id; defaults to the account's Inbox.
    Q_PROPERTY(QString currentFolderId READ currentFolderId WRITE setCurrentFolderId NOTIFY
                   currentFolderChanged)
    Q_PROPERTY(QString currentFolderName READ currentFolderName NOTIFY currentFolderChanged)
    // The actual list of messages in the current folder — bound by QML
    // ListView. Roles exposed via QML role names (defined in roleNames()
    // override on a proxy below): subject, from, snippet, timestamp,
    // unread, hasAttachment, messageId.
    Q_PROPERTY(QObject *messages READ messages NOTIFY currentFolderChanged)
    Q_PROPERTY(int unreadCount READ unreadCount NOTIFY unreadCountChanged)
    // Connection state of the current account's incoming server. One of
    // "offline" | "connecting" | "idle" | "syncing" | "error".
    Q_PROPERTY(QString syncState READ syncState NOTIFY syncStateChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY syncStateChanged)

  public:
    explicit MailService(QObject *parent = nullptr);
    ~MailService() override;

    // Singleton accessor for the QML registration. Qt 6 picks this up
    // automatically when QML_SINGLETON + QML_NAMED_ELEMENT are set; the
    // signature must be `static T *create(QQmlEngine *, QJSEngine *)`.
    static MailService *create(class QQmlEngine *, class QJSEngine *);

    QObject            *accounts() const;
    QString             currentAccountId() const;
    void                setCurrentAccountId(const QString &id);
    QString             currentAccountName() const;

    QObject            *folders() const;
    QString             currentFolderId() const;
    void                setCurrentFolderId(const QString &id);
    QString             currentFolderName() const;

    QObject            *messages() const;
    int                 unreadCount() const;

    QString             syncState() const;
    QString             lastError() const;

    // Q_INVOKABLE — actions the UI triggers.

    // Trigger a fetch of the current folder. On a server we already
    // IMAP-IDLE against this is mostly a no-op; on first-open it fetches
    // headers. Returns false if no current account.
    Q_INVOKABLE bool refresh();

    // Mark a message read / unread. messageId is the string-encoded
    // QMailMessageId surfaced via the messages model's "messageId" role.
    Q_INVOKABLE bool markAsRead(const QString &messageId, bool read = true);

    // Move a message to a standard folder (trash / archive). Folder is
    // resolved per-account via QMailAccount::standardFolder.
    Q_INVOKABLE bool moveToTrash(const QString &messageId);
    Q_INVOKABLE bool moveToArchive(const QString &messageId);

    // Compose-and-send. Synchronous from QML's point of view (returns
    // immediately, transmit happens async); see syncState for progress.
    Q_INVOKABLE bool send(const QString &to, const QString &cc, const QString &subject,
                          const QString &body, const QStringList &attachmentPaths = {});

    // Open a message — loads body + parts into a viewer-friendly map.
    // Returns:
    //   { "subject": ..., "from": ..., "to": [...], "cc": [...],
    //     "date": ..., "bodyHtml": "<html>...", "bodyPlain": "...",
    //     "attachments": [{ "name": ..., "size": ..., "mime": ... }] }
    Q_INVOKABLE QVariantMap openMessage(const QString &messageId);

  signals:
    void currentAccountChanged();
    void currentFolderChanged();
    void unreadCountChanged();
    void syncStateChanged();

  private slots:
    // Slots take the QMF-side concrete types — the .cpp `#include`s the
    // QMF headers, so this only resolves once we're building against
    // qmf-dev. The signatures are documented as comments here to keep
    // the header free of QMF dependencies.
    //   void onAccountAdded(const QMailAccountId &id);
    //   void onAccountRemoved(const QMailAccountId &id);
    //   void onRetrievalProgress(uint progress, uint total);
    //   void onActionCompleted(const QMailServiceAction::Status &status);
    //
    // onMessagesUpdated() handles flag changes (read/unread, folder moves,
    // deletes). onMessagesAdded() is the IDLE arrival path: each newly
    // inserted unread message in the Inbox produces a freedesktop
    // notification on org.freedesktop.Notifications via QDBus.
    void onMessagesUpdated();

  private:
    // Bind the message-list model to the current folder. Called on
    // currentAccount / currentFolder change.
    void rebindMessagesToCurrentFolder();
    // Try to load the user's last-selected account from QSettings.
    void restoreLastSelection();
    void saveLastSelection();
    // Push a freedesktop notification for each newly-arrived unread
    // incoming Inbox message in `ids`. Called from the messagesAdded
    // lambda — body signature uses QVariantList of u64 ids to keep the
    // header free of QMF includes; the .cpp casts back to
    // QMailMessageIdList.
    void notifyForNewMessages(const class QMailMessageIdList &ids);

    // QMF model handles. All owned by MailService (QObject parent).
    QMailAccountListModel     *m_accountsModel = nullptr;
    QMailFolderListModel      *m_foldersModel  = nullptr;
    QMailMessageListModel     *m_messagesModel = nullptr;
    QMailMessageThreadedModel *m_threadedModel = nullptr;

    // Action handles for kick-off + state — kept member-resident because
    // QMF actions hold the connection state we need to display.
    QMailRetrievalAction *m_retrieval = nullptr;
    QMailTransmitAction  *m_transmit  = nullptr;

    QString               m_currentAccountId;
    QString               m_currentFolderId;
    QString               m_syncState = QStringLiteral("offline");
    QString               m_lastError;
    int                   m_unreadCount = 0;
};

#endif // MAILSERVICE_H
