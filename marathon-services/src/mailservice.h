#ifndef MAILSERVICE_H
#define MAILSERVICE_H

#include <QAbstractListModel>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <qqml.h>

// QMF id typedefs (QMailMessageIdList = QList<QMailMessageId>) live in
// qmailid.h. Include it directly so callers of notifyForNewMessages()
// see the full typedef, not a class-forward-decl that clashes with QMF.
// The heavier QMF model/action classes stay forward-declared.
#include <qmailid.h>

class QMailAccountListModel;
class QMailRetrievalAction;
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
    // Currently-selected folder id; defaults to the account's Inbox.
    // (Folder list is not exposed yet — QMailStore::queryFolders gives
    // ids directly; a per-account folder list model is a future add.)
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

    // Add a classic-password IMAP/SMTP account. Used for Fastmail,
    // self-hosted IMAP, and any provider that doesn't expose OAuth.
    // Returns the new accountId as a string (empty on failure).
    //
    // encryption values per QMF imap4/smtp plugins:
    //   0 = none, 1 = SSL (implicit, typically port 993/465),
    //   2 = STARTTLS (explicit, typically port 143/587).
    //
    // SECURITY: v1 stores the password in QMF's account-config (QSettings
    // under ~/.config/QMF/QMF.conf). That file is user-owned, but moving
    // the password into Secret-Service through a QMailCredentialsPlugin
    // is a known follow-on — tracked under the credentials-plugin task.
    Q_INVOKABLE QString addImapAccount(const QString &name, const QString &email,
                                       const QString &imapHost, int imapPort, int imapEncryption,
                                       const QString &smtpHost, int smtpPort, int smtpEncryption,
                                       const QString &username, const QString &password);

    // Start an OAuth login flow for Gmail / Outlook. Creates a QMF
    // account skeleton with the provider's well-known IMAP+SMTP
    // servers and CredentialsPlugin=marathon-oauth, then spawns the
    // marathon-mail-oauth helper to run the PKCE flow.
    //
    // Returns true if the helper started; false if the helper binary
    // is missing or the QMF account couldn't be saved. Browser auth
    // is asynchronous, so the rest of the flow comes back over three
    // signals (below).
    //
    // provider: "gmail" | "outlook" (or "google" | "microsoft" — both
    // resolve to the same canonical id in the helper's clap parser).
    Q_INVOKABLE bool startOAuthLogin(const QString &provider);

  signals:
    void currentAccountChanged();
    void currentFolderChanged();
    void unreadCountChanged();
    void syncStateChanged();

    // OAuth login flow signals — emitted asynchronously from
    // startOAuthLogin() as the helper subprocess progresses.
    //
    // oauthAuthUrlReady fires once the helper has bound its loopback
    // listener and printed the authorisation URL on stderr. The QML
    // side opens this in the system browser via Qt.openUrlExternally.
    //
    // oauthLoginSucceeded fires once the helper has exchanged the
    // PKCE code, fetched a refresh token, persisted it to Secret-
    // Service, and (best-effort) populated the From: email. The
    // accountId is already current — currentAccountChanged also fires.
    //
    // oauthLoginFailed fires on any failure. `code` is the structured
    // error from the helper envelope; the QML side treats
    // "oauth_not_configured" as "route to classic IMAP" and any other
    // code as a generic error banner.
    void oauthAuthUrlReady(const QString &url);
    void oauthLoginSucceeded(const QString &accountId);
    void oauthLoginFailed(const QString &code, const QString &message);

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
    // deletes). The QMailStore::messagesAdded lambda in the constructor
    // calls notifyForNewMessages() directly, then this slot for unread
    // recount.
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
    void notifyForNewMessages(const QMailMessageIdList &ids);

    // QMF model handles. All owned by MailService (QObject parent).
    // m_messagesModel is the MailMessageListProxy (defined in .cpp) so
    // we hold it as the abstract base — keeps the header QMF-free.
    QMailAccountListModel *m_accountsModel = nullptr;
    QAbstractListModel    *m_messagesModel = nullptr;

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
